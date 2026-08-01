import hashlib
import json
import os
from datetime import datetime, timedelta

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services import comandaParserService as parser
from services.rede import baixaComandas, fechamentoCache, rede

# Tipo de evento de gossip (ver services/rede/eventos.py:BarramentoEventos)
# usado pra propagar o resumo de um dia recém-calculado pra malha inteira —
# mesmo mecanismo genérico usado por CardapioController ("cardapio_alterado")
# e SalaoController ("mesa_atualizada").
_EVENTO_FECHAMENTO_ATUALIZADO = "fechamento_atualizado"

# Caminho rápido pra propagar uma baixa recém-dada. Diferente do evento
# acima, aqui o payload é a informação em si (a chave e o id da baixa), não
# um aviso de "recalcule aí" — a baixa é um fato que a outra máquina não tem
# como deduzir sozinha a partir das comandas dela.
_EVENTO_COMANDA_BAIXADA = "comanda_baixada"

# Janela (em dias) que o resumo periódico de anti-entropy compara pra este
# domínio — mesmo raciocínio de _JANELA_RECONCILIACAO_PEDIDOS_DIAS em
# consultaController.py: mantém o resumo comparado a cada ciclo limitado,
# em vez de crescer pra sempre conforme os dias de operação se acumulam.
_JANELA_RECONCILIACAO_FECHAMENTO_DIAS = 30


def _hoje_iso():
    return datetime.now().strftime("%Y-%m-%d")


class FechamentoController(QObject):
    """Fechamento de caixa diário: soma o valor das comandas **fechadas**
    (Balcão/Entrega/Mesa) lançadas num dia, agrupadas por origem, e separa
    comandas suspeitas (sem nome + NP + Pix) pra revisão manual.

    Comanda aberta é uma venda que ainda não foi conferida: ela existe, está
    na Consulta e pode ser editada, mas não entra no caixa enquanto alguém
    não der baixa nela pelo popup de fechamento rápido (ver
    services/rede/baixaComandas.py e qml/pages/fechamento/). O resumo
    carrega quantas e quanto ficaram de fora, pra essa diferença entre o que
    foi vendido e o que entrou no caixa nunca ficar invisível na tela.

    Complexidade pensada pra nunca crescer com o histórico: cada cálculo é
    O(k), k = comandas *daquele dia* (o nome do arquivo já embute a data —
    ver comandaParserService.data_arquivo_aaaammdd — então dias diferentes
    do pedido nunca chegam a ser abertos). Ler um dia já calculado antes é
    O(1) (ver services/rede/fechamentoCache.py, um JSON por dia)."""

    # Emitido quando o resumo de um dia muda (recebido de outra máquina por
    # gossip) — Fechamento.qml usa pra recarregar sozinha se for o dia que
    # está sendo exibido agora.
    fechamentoAtualizado = pyqtSignal(str)

    # Emitido quando uma comanda recebe baixa (aqui ou em outra máquina) —
    # Consulta.qml usa pra atualizar o selo Aberta/Fechada da lista, e
    # Fechamento.qml pra recarregar o dia exibido.
    baixasAtualizadas = pyqtSignal()

    def __init__(self):
        super().__init__()
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.pasta_pedidos = os.path.join(base_dir, "pedidos")

        rede.registrarEvento(_EVENTO_FECHAMENTO_ATUALIZADO, self._ao_receber_fechamento_remoto)
        rede.registrarEvento(_EVENTO_COMANDA_BAIXADA, self._ao_receber_baixa_remota)
        rede.registrarDominioSincronizado(
            "fechamento",
            self._resumo_fechamento,
            self._obter_fechamento_reconciliacao,
            self._aplicar_fechamento_reconciliacao,
        )
        rede.registrarDominioSincronizado(
            "baixas",
            self._resumo_baixas,
            self._obter_baixa_reconciliacao,
            self._aplicar_baixa_reconciliacao,
            None,
            self._comparar_baixa_reconciliacao,
        )

    # ---------- Anti-entropy (ver services/rede/redeService.py:registrarDominioSincronizado) ----------
    # Sem "apagados": não existe operação de apagar um resumo de
    # fechamento — é um cache sempre recalculável a partir de pedidos/*.txt.

    def _resumo_fechamento(self):
        hoje = _hoje_iso()
        # "Hoje" nunca usa cache (obterFechamento sempre recalcula ao
        # vivo, comandas continuam chegando o dia inteiro) — comparar
        # geraria divergência esperada e constante entre as máquinas, sem
        # nenhum benefício real.
        limite = (datetime.now() - timedelta(days=_JANELA_RECONCILIACAO_FECHAMENTO_DIAS)).strftime("%Y-%m-%d")
        itens = {}
        for data_iso in fechamentoCache.listar_dias():
            if data_iso == hoje or data_iso < limite:
                continue
            resumo = fechamentoCache.carregar(data_iso)
            if resumo is None:
                continue
            itens[data_iso] = hashlib.sha256(json.dumps(resumo, sort_keys=True).encode("utf-8")).hexdigest()[:16]
        return {"itens": itens}

    def _obter_fechamento_reconciliacao(self, data_iso):
        """Payload deliberadamente vazio de números: quem recebe recalcula o
        dia com as próprias comandas (ver _ao_receber_fechamento_remoto), e
        mandar o resumo inteiro só gastaria banda com um valor que o outro
        lado vai descartar. O que importa é a mensagem chegar — ela é o
        aviso de "este dia mudou aqui, confira o seu"."""
        if fechamentoCache.carregar(data_iso) is None:
            return None
        return {"data": data_iso}

    def _aplicar_fechamento_reconciliacao(self, data_iso, _payload):
        self._ao_receber_fechamento_remoto({"data": data_iso})

    # ---------- Anti-entropy do domínio "baixas" ----------
    # Bem mais simples que o domínio "pedidos" porque o conjunto de baixas só
    # cresce e nunca reverte (ver services/rede/baixaComandas.py): não há o
    # que arbitrar, nenhuma versão pode ser sobrescrita por outra e nada
    # jamais vira conflito manual. Sem "apagados" também: baixa não se
    # desfaz — a saída pra uma dada por engano é editar a comanda, que gera
    # um arquivo novo, sem baixa.

    def _resumo_baixas(self):
        """Anuncia as baixas recentes. A janela recorta só o que é ANUNCIADO:
        o arquivo em disco guarda todas para sempre, porque é dele que sai o
        caixa de qualquer dia do histórico — o que se evita aqui é a
        mensagem de reconciliação crescer sem limite conforme os anos de
        operação se acumulam, mesmo raciocínio de
        ConsultaController._resumo_pedidos.

        A janela é a mesma do domínio "fechamento": uma baixa mais antiga que
        isso não pode mais mudar nenhum resumo que ainda seja comparado entre
        as máquinas, então continuar anunciando-a não corrigiria nada."""
        baixaComandas.purgar_apagadas()

        limite = (
            datetime.now() - timedelta(days=_JANELA_RECONCILIACAO_FECHAMENTO_DIAS)
        ).strftime("%Y%m%d")

        itens = {}
        for nome_arquivo, id_evento in baixaComandas.carregar().items():
            data = parser.data_arquivo_aaaammdd(nome_arquivo)
            if data is not None and data < limite:
                continue
            itens[nome_arquivo] = id_evento
        return {"itens": itens}

    def _comparar_baixa_reconciliacao(self, _nome_arquivo, id_local, _id_peer):
        """Só puxa o que não existe aqui. O comparador padrão de
        registrarDominioSincronizado é `local != peer`, e ele não serve neste
        domínio: duas máquinas que deram baixa na mesma comanda de forma
        independente (ambas offline, por exemplo) guardam ids diferentes pra
        ela, e a diferença nunca some — as duas ficariam pedindo a mesma
        chave uma pra outra a cada ciclo, pra sempre. Qual dos dois ids
        sobrevive não importa: o efeito ("esta comanda está fechada") é o
        mesmo nos dois casos."""
        return id_local is None

    def _obter_baixa_reconciliacao(self, nome_arquivo):
        id_evento = baixaComandas.carregar().get(nome_arquivo)
        if not id_evento:
            return None
        return {"idEvento": id_evento}

    def _aplicar_baixa_reconciliacao(self, nome_arquivo, payload):
        payload = payload or {}
        self._registrar_baixa_aprendida(nome_arquivo, payload.get("idEvento", ""))

    def _ao_receber_baixa_remota(self, payload):
        """Reação ao gossip "comanda_baixada" — o caminho rápido, pra baixa
        dada em outra máquina aparecer aqui na hora, sem esperar o próximo
        ciclo de reconciliação."""
        payload = payload or {}
        nome_arquivo = payload.get("arquivo")
        if not nome_arquivo:
            return
        self._registrar_baixa_aprendida(os.path.basename(nome_arquivo), payload.get("idEvento", ""))

    def _registrar_baixa_aprendida(self, nome_arquivo, id_evento):
        """Grava uma baixa vinda de fora e atualiza o que depende dela.
        Preserva o id recebido (ver baixaComandas.registrar) — inventar um id
        local faria esta máquina anunciar um valor diferente do das outras
        pra mesma baixa.

        Não faz nada se a comanda já estava fechada aqui: a mesma baixa chega
        pelos dois caminhos (gossip e reconciliação), e recalcular o dia a
        cada reentrega só faria a tela piscar à toa."""
        if baixaComandas.esta_fechada(nome_arquivo):
            return

        baixaComandas.registrar(nome_arquivo, id_evento)

        data_iso = self._data_iso_da_comanda(nome_arquivo)
        if data_iso:
            self._recalcular_e_cachear(data_iso)
        self.baixasAtualizadas.emit()

    def _data_iso_da_comanda(self, nome_arquivo):
        """"AAAA-MM-DD" do dia da comanda, deduzido do nome do arquivo (que
        já embute a data — ver comandaParserService.data_arquivo_aaaammdd).
        "" quando o nome não bate com o padrão esperado."""
        aaaammdd = parser.data_arquivo_aaaammdd(nome_arquivo)
        if not aaaammdd:
            return ""
        return f"{aaaammdd[:4]}-{aaaammdd[4:6]}-{aaaammdd[6:]}"

    def _recalcular_e_cachear(self, data_iso):
        """Recalcula o dia a partir das comandas desta máquina e atualiza o
        cache local. Não publica nada na rede — é a reação a uma novidade
        que veio de lá, e republicar aqui faria as máquinas ficarem se
        cutucando de volta indefinidamente.

        Só grava e avisa a tela se o resultado mudou de verdade: enquanto as
        comandas não convergirem, os resumos das duas máquinas continuam
        diferentes e este caminho roda a cada ciclo — sem essa checagem, a
        página de Fechamento se recarregaria sozinha a cada 2 minutos sem
        nada ter mudado."""
        resumo = self._calcular_resumo_dia(data_iso)
        if resumo == fechamentoCache.carregar(data_iso):
            return

        fechamentoCache.salvar(data_iso, resumo)
        self.fechamentoAtualizado.emit(data_iso)

    def _listar_arquivos_do_dia(self, data_iso):
        """Nomes de arquivo cuja data embutida bate com `data_iso`, sem
        abrir/ler o conteúdo de nenhum — só essa lista é de fato lida
        depois, em _calcular_resumo_dia."""
        if not os.path.isdir(self.pasta_pedidos):
            return []

        aaaammdd = data_iso.replace("-", "")
        return [
            nome_arquivo
            for nome_arquivo in os.listdir(self.pasta_pedidos)
            if nome_arquivo.endswith(".txt") and parser.data_arquivo_aaaammdd(nome_arquivo) == aaaammdd
        ]

    def _ler_comanda(self, nome_arquivo):
        """Abre uma comanda do dia e extrai dela os campos de cabeçalho que
        tanto o resumo do caixa quanto o popup de fechamento rápido usam.
        None quando o arquivo não pôde ser lido.

        `conteudo` (o cupom inteiro, já sem os códigos da impressora) vai
        junto porque o popup precisa exibir a comanda completa; o resumo
        simplesmente não copia esse campo pro que grava em cache."""
        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)
        try:
            with open(caminho, "rb") as arquivo:
                conteudo_bytes = arquivo.read()
        except OSError as erro:
            print(f"[FechamentoController] Falha ao ler {caminho}: {erro}")
            return None

        conteudo = conteudo_bytes.decode(parser.CODEPAGE_IMPRESSORA, errors="replace")
        conteudo = parser.limpar_codigos_impressora(conteudo)

        return {
            "arquivo": nome_arquivo,
            "tipo": parser.tipo_comanda(nome_arquivo),
            "codigo": parser.codigo_comanda(nome_arquivo, conteudo),
            "cliente": parser.extrair_campo(parser.PADRAO_CLIENTE, conteudo),
            "valor": parser.extrair_valor_total(conteudo),
            "formaPagamento": parser.extrair_campo(parser.PADRAO_FORMA_PAGAMENTO, conteudo),
            "status": parser.extrair_status_pagamento(conteudo),
            "dataHora": parser.extrair_campo(parser.PADRAO_DATA, conteudo),
            "conteudo": conteudo.strip("\n"),
        }

    def _calcular_resumo_dia(self, data_iso):
        total = 0.0
        quantidade = 0
        por_tipo = {}
        suspeitas = []
        total_aberto = 0.0
        quantidade_aberta = 0

        baixas = baixaComandas.carregar()

        for nome_arquivo in self._listar_arquivos_do_dia(data_iso):
            dados = self._ler_comanda(nome_arquivo)
            if dados is None:
                continue

            tipo = dados["tipo"]
            cliente = dados["cliente"]
            forma_pagamento = dados["formaPagamento"]
            status = dados["status"]
            valor = dados["valor"]

            item = {
                "arquivo": nome_arquivo,
                "cliente": cliente,
                "valor": valor,
                "formaPagamento": forma_pagamento,
                "status": status,
                "dataHora": dados["dataHora"],
            }

            # Comanda sem baixa é venda ainda não conferida: fica fora de
            # total/porTipo/suspeitas e só é contada à parte, pra tela poder
            # mostrar o quanto ainda não entrou no caixa (ver
            # services/rede/baixaComandas.py).
            if nome_arquivo not in baixas:
                total_aberto += valor
                quantidade_aberta += 1
                continue

            total += valor
            quantidade += 1

            grupo = por_tipo.setdefault(tipo, {"total": 0.0, "quantidade": 0, "comandas": []})
            grupo["total"] += valor
            grupo["quantidade"] += 1
            grupo["comandas"].append(item)

            # Mesa não tem uma única forma/status no nível do cabeçalho —
            # cada divisão da conta é paga por uma pessoa diferente, com
            # sua própria forma/status (ver
            # comandaParserService.extrair_status_pagamento) — então essa
            # checagem só faz sentido pra Balcão/Entrega, que têm um único
            # pagante por comanda.
            if tipo != "Mesa" and cliente.strip() == "" and status == "NP" and forma_pagamento == "Pix":
                suspeitas.append(item)

        return {
            "data": data_iso,
            "total": total,
            "quantidade": quantidade,
            "porTipo": por_tipo,
            "suspeitas": suspeitas,
            "abertas": {"quantidade": quantidade_aberta, "total": total_aberto},
        }

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
    def calcularFechamento(self, data_iso):
        """Recalcula o resumo de `data_iso` ("AAAA-MM-DD") direto das
        comandas, sempre — salva no cache local desta máquina e propaga
        pra malha inteira. Usado pelo botão "Fechar Caixa" e sempre que o
        dia exibido em Fechamento.qml é hoje."""
        resumo = self._calcular_resumo_dia(data_iso)
        fechamentoCache.salvar(data_iso, resumo)
        rede.publicarEvento(_EVENTO_FECHAMENTO_ATUALIZADO, {"data": data_iso, "resumo": resumo})
        return resumo

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
    def obterFechamento(self, data_iso):
        """Ponto de entrada usado ao abrir a página ou trocar de data: hoje
        é sempre recalculado ao vivo (comandas continuam chegando o dia
        inteiro, inclusive de outras máquinas); dias passados usam o cache
        já salvo (O(1)) quando existe, e só caem pra calcular na hora se
        ainda não tiver sido salvo antes nesta máquina."""
        if data_iso == _hoje_iso():
            return self.calcularFechamento(data_iso)

        resumo_em_cache = fechamentoCache.carregar(data_iso)
        if resumo_em_cache is not None:
            return resumo_em_cache

        return self.calcularFechamento(data_iso)

    # ---------- Fechamento rápido (ver qml/pages/fechamento/PopupFechamentoRapido.qml) ----------

    @pyqtSlot(str, result="QVariantList")
    @protegido([])
    def listarComandasAbertas(self, data_iso):
        """Comandas de `data_iso` que ainda não receberam baixa, inteiras
        (com o cupom em `conteudo`), da mais recente pra mais antiga.

        A ordem sai do carimbo embutido no nome do arquivo (ver
        comandaParserService.carimbo_arquivo) — e não do mtime, que é o que
        listarComandas usa. Numa comanda recebida pela rede o mtime é o da
        gravação local, então cada máquina veria a fila do popup numa ordem
        diferente; o carimbo do nome é o mesmo em todas. É o mesmo raciocínio
        já documentado em ConsultaController._resumo_pedidos.

        Ordenar pelo nome inteiro não serviria: o prefixo (pedido_/entrega_/
        mesa_) vem antes do carimbo e dominaria a comparação, agrupando por
        tipo em vez de por horário."""
        baixas = baixaComandas.carregar()

        arquivos = sorted(
            self._listar_arquivos_do_dia(data_iso),
            key=parser.carimbo_arquivo,
            reverse=True,
        )

        abertas = []
        for nome_arquivo in arquivos:
            if nome_arquivo in baixas:
                continue
            dados = self._ler_comanda(nome_arquivo)
            if dados is not None:
                dados["fechada"] = False
                abertas.append(dados)

        return abertas

    @pyqtSlot(str, result="QVariantList")
    @protegido([])
    def listarComandasFechadas(self, data_iso):
        """Comandas de `data_iso` que já receberam baixa, no mesmo formato e
        ordem de listarComandasAbertas — alimenta a fila do botão "Editar
        caixa" em Fechamento.qml, simétrico ao "Fechamento rápido" só que do
        lado oposto (fechadas em vez de abertas)."""
        baixas = baixaComandas.carregar()

        arquivos = sorted(
            self._listar_arquivos_do_dia(data_iso),
            key=parser.carimbo_arquivo,
            reverse=True,
        )

        fechadas = []
        for nome_arquivo in arquivos:
            if nome_arquivo not in baixas:
                continue
            dados = self._ler_comanda(nome_arquivo)
            if dados is not None:
                dados["fechada"] = True
                fechadas.append(dados)

        return fechadas

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
    def obterComanda(self, nome_arquivo):
        """Uma comanda qualquer do disco, no mesmo formato de
        listarComandasAbertas mais o campo "fechada".

        Existe porque listarComandasAbertas, por definição, não alcança as
        comandas que JÁ receberam baixa — e são justamente elas que a página
        de Fechamento precisa abrir pra corrigir: uma comanda suspeita (sem
        nome, NP, Pix) só entra na lista de suspeitas depois de baixada."""
        nome_arquivo = os.path.basename(nome_arquivo)
        dados = self._ler_comanda(nome_arquivo)
        if dados is None:
            return {}

        dados["fechada"] = baixaComandas.esta_fechada(nome_arquivo)
        return dados

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def reimprimirComanda(self, nome_arquivo):
        """Manda a comanda pra impressora exatamente como ela está em disco.

        Sem decodificar e sem limpar_codigos_impressora: o .txt JÁ é o cupom
        ESC/POS byte a byte (é por isso que ele não é um JSON — ver
        services/rede/baixaComandas.py), então reimprimir é reenviar o
        arquivo, não remontar a comanda. Diferente de editar, não grava nada
        novo: nenhum arquivo, nenhum código sequencial, nenhum evento na malha.

        O True daqui significa só "o pedido de impressão foi despachado" — a
        impressão em si é assíncrona e o resultado chega por
        rede.impressaoResultado, igual ao de um pedido novo."""
        nome_arquivo = os.path.basename(nome_arquivo)
        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)

        try:
            with open(caminho, "rb") as arquivo:
                conteudo_bytes = arquivo.read()
        except OSError as erro:
            print(f"[FechamentoController] Falha ao ler {caminho} para reimpressão: {erro}")
            return False

        rede.solicitar_impressao(conteudo_bytes)
        return True

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def darBaixa(self, nome_arquivo):
        """Fecha a comanda: a partir daqui ela conta no caixa do dia. Não há
        operação inversa — desfazer uma baixa dada por engano é editar a
        comanda pela Consulta ou pelo próprio popup, o que gera um arquivo
        novo, sem baixa (ver services/rede/baixaComandas.py)."""
        nome_arquivo = os.path.basename(nome_arquivo)
        if baixaComandas.esta_fechada(nome_arquivo):
            return True

        id_evento = baixaComandas.registrar(nome_arquivo)
        data_iso = self._data_iso_da_comanda(nome_arquivo)

        # O id da baixa viaja junto pra que todas as máquinas gravem a MESMA
        # marca pra este fechamento — sem isso cada uma registraria "quando
        # eu soube", e o resumo de anti-entropy nunca convergiria (ver
        # _comparar_baixa_reconciliacao).
        rede.publicarEvento(
            _EVENTO_COMANDA_BAIXADA,
            {"arquivo": nome_arquivo, "idEvento": id_evento, "data": data_iso},
        )

        # calcularFechamento (e não _recalcular_e_cachear): o caixa do dia
        # mudou por decisão desta máquina, então a malha inteira precisa
        # saber que aquele dia mudou aqui.
        if data_iso:
            self.calcularFechamento(data_iso)
        self.baixasAtualizadas.emit()
        return True

    def _ao_receber_fechamento_remoto(self, payload):
        """Reação a um "fechamento_atualizado" vindo de OUTRA máquina.

        A mensagem é tratada como um AVISO de que aquele dia mudou em algum
        lugar, não como um valor a copiar: o que se faz aqui é recalcular o
        dia a partir das comandas desta máquina. Os números do peer são
        ignorados de propósito.

        Antes se gravava o resumo recebido direto por cima do local, com o
        argumento de que o cache é 100% recalculável e o cálculo é
        determinístico — o que só vale se as duas máquinas tiverem as MESMAS
        comandas. Quando não têm (justamente o problema que a sincronização
        de comandas resolve, e que existe de verdade enquanto uma máquina
        está se atualizando), o resultado era um ping-pong permanente: A
        anunciava seu resumo, B copiava; B anunciava o dele, A copiava; e
        como obterFechamento devolve o cache pra dias passados sem nunca
        recalcular, o valor do caixa daquele dia ficava alternando entre as
        duas máquinas a cada ciclo de 2 min, sem nada pra desempatar.

        Recalcular localmente resolve os dois lados: nenhuma máquina impõe
        um número à outra, e assim que as comandas convergirem (pelo domínio
        "pedidos" + tombstones) as duas chegam ao mesmo resultado sozinhas —
        aí os resumos passam a bater e o tráfego cessa. Também é o
        comportamento mais seguro no meio do caminho: uma máquina que ainda
        não recebeu 3 comandas do dia não consegue mais sobrescrever com um
        total menor o caixa de quem já as tem."""
        payload = payload or {}
        data_iso = payload.get("data")
        if not data_iso:
            return

        self._recalcular_e_cachear(data_iso)
