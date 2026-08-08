import hashlib
import json
import os
import unicodedata
from datetime import datetime, timedelta

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services import comandaEstiloService as estilo
from services import comandaParserService as parser
from services import comandaTextoService as texto
from services import formulaLucroService
from services.rede import baixaComandas, contagemCaixa, extrasCaixa, fechamentoCache, rede, tombstones

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

# Pagamento de diária a um funcionário — dinheiro que sai do caixa fora de
# qualquer venda (ver services/rede/extrasCaixa.py). Mesmo raciocínio de
# _EVENTO_COMANDA_BAIXADA: o payload é o fato em si (quem, quanto, quando),
# não um aviso de "recalcule aí", porque a outra máquina não tem como
# deduzir esse lançamento sozinha a partir de nenhuma comanda.
_EVENTO_EXTRA_LANCADO = "extra_lancado"

# Exclusão de um pagamento de diária (ver excluirExtraDiaria) — mesmo
# raciocínio de _EVENTO_COMANDA_BAIXADA: o payload é o fato em si (qual id,
# quando), porque a outra máquina não tem como deduzir uma exclusão
# sozinha.
_EVENTO_EXTRA_APAGADO = "extra_apagado"

# Contagem manual de Cartão/Dinheiro/Pix, usada pra calcular o "Lucro" (ver
# services/rede/contagemCaixa.py). Ao contrário dos dois eventos acima, uma
# gravação de contagem SOBRESCREVE a anterior do mesmo dia — o payload
# carrega o idEvento pra quem recebe arbitrar qual versão é mais nova (ver
# services/rede/contagemCaixa.py:aplicar_remoto), mesmo desenho de
# services/cardapioService.py.
_EVENTO_CONTAGEM_ATUALIZADA = "contagem_caixa_atualizada"


def _hoje_iso():
    return datetime.now().strftime("%Y-%m-%d")


class FechamentoController(QObject):
    """Fechamento de caixa diário: soma o valor das comandas **fechadas**
    (Balcão/Entrega/Mesa) lançadas num dia, agrupadas por origem. Cada
    comanda carrega um flag "suspeita" (ver comandaParserService.eh_suspeita)
    pra revisão manual — sinalizada com borda vermelha em Consulta e
    Fechamento, não mais numa lista separada.

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

    # Emitido quando um pagamento de diária é lançado em OUTRA máquina e
    # aprendido aqui (gossip/reconciliação, ver _registrar_extra_aprendido).
    # Um lançamento feito NESTA máquina não passa por aqui — quem chama
    # registrarExtraDiaria já recebe o registro de volta e decide sozinho
    # como reagir (ver PopupExtras.qml/concluido), mesmo raciocínio de
    # baixasAtualizadas/darBaixa.
    extrasAtualizados = pyqtSignal()

    # Emitido quando a contagem de Cartão/Dinheiro/Pix de um dia muda em
    # OUTRA máquina e é aprendida aqui — mesmo raciocínio de
    # extrasAtualizados: uma gravação feita NESTA máquina não passa por
    # aqui (ver registrarContagem).
    contagemAtualizada = pyqtSignal(str)

    def __init__(self):
        super().__init__()
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.pasta_pedidos = os.path.join(base_dir, "pedidos")

        rede.registrarEvento(_EVENTO_FECHAMENTO_ATUALIZADO, self._ao_receber_fechamento_remoto)
        rede.registrarEvento(_EVENTO_COMANDA_BAIXADA, self._ao_receber_baixa_remota)
        rede.registrarEvento(_EVENTO_EXTRA_LANCADO, self._ao_receber_extra_remoto)
        rede.registrarEvento(_EVENTO_EXTRA_APAGADO, self._ao_receber_extra_apagado_remoto)
        rede.registrarEvento(_EVENTO_CONTAGEM_ATUALIZADA, self._ao_receber_contagem_remota)
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
        rede.registrarDominioSincronizado(
            "extras",
            self._resumo_extras,
            self._obter_extra_reconciliacao,
            self._aplicar_extra_reconciliacao,
            self._apagar_extra_reconciliacao,
        )
        rede.registrarDominioSincronizado(
            "contagem",
            self._resumo_contagem,
            self._obter_contagem_reconciliacao,
            self._aplicar_contagem_reconciliacao,
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

    # ---------- Anti-entropy do domínio "extras" (pagamentos de diária) ----------
    # O CONJUNTO só cresce (não há "apagar"), mas o CONTEÚDO de um
    # lançamento pode ser corrigido depois (ver editarExtraDiaria) — por
    # isso a versão comparada é "idEventoRevisao", não o id do lançamento
    # em si, e o comparador é o padrão (versao_local != versao_peer):
    # tanto um lançamento novo quanto uma edição de um já existente batem
    # nessa condição, e _registrar_extra_aprendido decide qual dos dois
    # casos é, olhando se o id já existe aqui.

    def _resumo_extras(self):
        """Anuncia os pagamentos de diária recentes, na mesma janela do
        domínio "fechamento"/"baixas" — um lançamento mais antigo que isso
        não muda mais nenhum resumo comparado entre as máquinas. Os
        "apagados" (ver tombstones.py) viajam junto e não têm janela
        própria: são purgados globalmente por
        RedeService._disparar_reconciliacao (tombstones.purgar_antigos),
        mesmo mecanismo que já vale pro domínio "pedidos"."""
        limite = (datetime.now() - timedelta(days=_JANELA_RECONCILIACAO_FECHAMENTO_DIAS)).strftime("%Y-%m-%d")
        itens = {}
        for id_evento, registro in extrasCaixa.carregar().items():
            if registro.get("dataIso", "") < limite:
                continue
            itens[id_evento] = registro.get("idEventoRevisao", id_evento)
        return {"itens": itens, "apagados": tombstones.carregar("extras")}

    def _obter_extra_reconciliacao(self, id_evento):
        registro = extrasCaixa.carregar().get(id_evento)
        if not registro:
            return None
        return dict(registro, id=id_evento)

    def _aplicar_extra_reconciliacao(self, id_evento, payload):
        self._registrar_extra_aprendido(id_evento, payload or {})

    def _apagar_extra_reconciliacao(self, id_evento):
        # tombstones.mesclar já gravou o tombstone (com o id de quem
        # apagou) antes de chamar aqui — mesmo padrão de
        # ConsultaController._apagar_pedido_reconciliacao.
        quando = tombstones.carregar("extras").get(id_evento, "")
        self._aplicar_exclusao_extra(id_evento, quando)

    def _ao_receber_extra_remoto(self, payload):
        """Reação ao gossip "extra_lancado" — o caminho rápido, pra um
        lançamento novo OU uma edição feita em outra máquina aparecer aqui
        na hora, sem esperar o próximo ciclo de reconciliação."""
        payload = payload or {}
        id_evento = payload.get("id")
        if id_evento:
            self._registrar_extra_aprendido(id_evento, payload)

    def _ao_receber_extra_apagado_remoto(self, payload):
        """Reação ao gossip "extra_apagado" — o caminho rápido pra uma
        exclusão feita em outra máquina aparecer aqui na hora."""
        payload = payload or {}
        id_evento = payload.get("id")
        if id_evento:
            self._aplicar_exclusao_extra(id_evento, payload.get("quando", ""))

    def _aplicar_exclusao_extra(self, id_evento, quando):
        """Aplica uma exclusão aprendida de fora (gossip ou reconciliação).
        Registra o tombstone mesmo se o lançamento já não existir aqui —
        é o que impede um terceiro nó desatualizado de reintroduzi-lo
        depois (mesmo raciocínio de tombstones.registrar)."""
        registro = extrasCaixa.carregar().get(id_evento)
        data_iso = registro.get("dataIso", "") if registro else ""

        extrasCaixa.apagar(id_evento, quando=quando or None)

        if data_iso:
            self._recalcular_e_cachear(data_iso)
        self.extrasAtualizados.emit()

    def _registrar_extra_aprendido(self, id_evento, payload):
        """Grava um lançamento novo OU aplica uma edição vinda de fora,
        conforme o id já seja conhecido aqui ou não. Idempotente nos dois
        casos: um lançamento novo que já existe não é regravado
        (extrasCaixa.registrar), e uma edição mais antiga que a revisão já
        aplicada aqui é ignorada (extrasCaixa.aplicar_edicao_remota) — a
        mesma novidade chega pelos dois caminhos (gossip e reconciliação),
        e reaplicar a cada reentrega só faria a tela piscar à toa.

        Um lançamento apagado aqui não pode voltar por um anúncio de um
        peer que ainda não soube da exclusão — mesmo cuidado de
        ConsultaController.aplicarPedidoRemoto."""
        if id_evento in tombstones.carregar("extras"):
            return

        data_iso = payload.get("dataIso")
        mudou = False

        if id_evento in extrasCaixa.carregar():
            mudou = extrasCaixa.aplicar_edicao_remota(
                id_evento,
                payload.get("funcionario", ""),
                payload.get("valor", 0),
                payload.get("idEventoRevisao", ""),
            )
        else:
            extrasCaixa.registrar(
                data_iso or "",
                payload.get("funcionario", ""),
                payload.get("valor", 0),
                payload.get("dataHora", ""),
                quando=id_evento,
            )
            mudou = True

        if not mudou:
            return

        if data_iso:
            self._recalcular_e_cachear(data_iso)
        self.extrasAtualizados.emit()

    # ---------- Anti-entropy do domínio "contagem" (Cartão/Dinheiro/Pix) ----------
    # Ao contrário de "baixas"/"extras" (que só crescem), aqui um mesmo dia
    # pode ser regravado — a arbitração de qual versão vale é feita por
    # services/rede/contagemCaixa.py:aplicar_remoto via idEvento/mais_novo,
    # mesmo desenho de services/cardapioService.py.

    def _resumo_contagem(self):
        limite = (datetime.now() - timedelta(days=_JANELA_RECONCILIACAO_FECHAMENTO_DIAS)).strftime("%Y-%m-%d")
        itens = {}
        for data_iso, registro in contagemCaixa.carregar().items():
            if data_iso < limite:
                continue
            itens[data_iso] = registro.get("idEvento", "")
        return {"itens": itens}

    def _obter_contagem_reconciliacao(self, data_iso):
        registro = contagemCaixa.obter_dia(data_iso)
        if not registro:
            return None
        return dict(registro, dataIso=data_iso)

    def _aplicar_contagem_reconciliacao(self, data_iso, payload):
        self._aplicar_contagem_remota(data_iso, payload or {})

    def _ao_receber_contagem_remota(self, payload):
        """Reação ao gossip "contagem_caixa_atualizada" — o caminho rápido,
        pra uma contagem editada em outra máquina aparecer aqui na hora."""
        payload = payload or {}
        data_iso = payload.get("dataIso")
        if data_iso:
            self._aplicar_contagem_remota(data_iso, payload)

    def _aplicar_contagem_remota(self, data_iso, payload):
        aplicado = contagemCaixa.aplicar_remoto(
            data_iso,
            payload.get("cartao", 0),
            payload.get("dinheiro", 0),
            payload.get("pix", 0),
            payload.get("idEvento", ""),
        )
        if aplicado:
            self.contagemAtualizada.emit(data_iso)

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
    def obterContagem(self, data_iso):
        """Contagem de Cartão/Dinheiro/Pix já salva para `data_iso`, ou
        zerada se o dia nunca foi contado."""
        registro = contagemCaixa.obter_dia(data_iso)
        if not registro:
            return {"cartao": 0, "dinheiro": 0, "pix": 0}
        return {
            "cartao": registro.get("cartao", 0),
            "dinheiro": registro.get("dinheiro", 0),
            "pix": registro.get("pix", 0),
        }

    @pyqtSlot(str, str, str, str, result="QVariantMap")
    @protegido({})
    def registrarContagem(self, data_iso, cartao_texto, dinheiro_texto, pix_texto):
        """Grava (sobrescrevendo) a contagem de `data_iso` e propaga pra
        malha. Devolve a contagem salva, já convertida pra número — o
        popup usa o retorno pra atualizar a tela na hora."""
        cartao = texto.valor_para_float(cartao_texto)
        dinheiro = texto.valor_para_float(dinheiro_texto)
        pix = texto.valor_para_float(pix_texto)

        id_evento = contagemCaixa.registrar(data_iso, cartao, dinheiro, pix)
        rede.publicarEvento(_EVENTO_CONTAGEM_ATUALIZADA, {
            "dataIso": data_iso,
            "cartao": cartao,
            "dinheiro": dinheiro,
            "pix": pix,
            "idEvento": id_evento,
        })

        return {"cartao": cartao, "dinheiro": dinheiro, "pix": pix}

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

        tipo = parser.tipo_comanda(nome_arquivo)
        cliente = parser.extrair_campo(parser.PADRAO_CLIENTE, conteudo)
        forma_pagamento = parser.extrair_campo(parser.PADRAO_FORMA_PAGAMENTO, conteudo)
        status = parser.extrair_status_pagamento(conteudo)
        endereco = parser.extrair_campo(parser.PADRAO_ENDERECO, conteudo)

        return {
            "arquivo": nome_arquivo,
            "tipo": tipo,
            "codigo": parser.codigo_comanda(nome_arquivo, conteudo),
            "cliente": cliente,
            "valor": parser.extrair_valor_total(conteudo),
            "formaPagamento": forma_pagamento,
            "status": status,
            "dataHora": parser.extrair_campo(parser.PADRAO_DATA, conteudo),
            "conteudo": conteudo.strip("\n"),
            "suspeita": parser.eh_suspeita(tipo, cliente, forma_pagamento, status, endereco),
        }

    @staticmethod
    def _texto_de_busca(dados, tipo):
        """Uma linha só, normalizada, com tudo por onde a comanda pode ser
        procurada na tela de Fechamento: modalidade, código, cliente, forma de
        pagamento, status, os itens pedidos e o valor.

        Normalizar aqui (minúsculas, sem acento) e não na tela é de propósito:
        assim "Açaí" acha "acai" e "JOÃO" acha "joao" sem cada comparação ter
        que refazer esse trabalho — a tela filtra a cada tecla digitada.

        O valor entra em três formas — "45.9", "45,90" e "4590" — porque é
        assim que as pessoas procuram: quem lembra do valor digita "45,90" ou
        "45.90", e quem confere pelo cupom às vezes digita só os dígitos. Sem
        isso, buscar "45,90" não acharia nada, já que o número guardado é um
        float.

        O cupom inteiro NÃO entra: ele traz prefixos ("Cliente:", "Forma de
        pagamento:") e linhas de separador que casariam com quase qualquer
        busca curta, enchendo o resultado de falso positivo."""
        valor = dados.get("valor") or 0.0
        com_virgula = f"{valor:.2f}".replace(".", ",")

        partes = [
            tipo,
            dados.get("codigo", ""),
            dados.get("cliente", ""),
            dados.get("formaPagamento", ""),
            dados.get("status", ""),
            dados.get("dataHora", ""),
            f"{valor:.2f}",
            com_virgula,
            com_virgula.replace(",", ""),
        ]

        conteudo = dados.get("conteudo") or ""
        linhas_tabela = parser.linhas_tabela_itens(conteudo.split("\n"))
        for item in parser.reconstruir_itens(linhas_tabela) if linhas_tabela is not None else []:
            partes.append(item.get("pedido", ""))
            partes.append(item.get("observacao", ""))
            borda = item.get("borda")
            if borda and borda.get("nome"):
                partes.append(borda["nome"])
            for adicional in item.get("adicionais") or []:
                partes.append(adicional.get("nome", ""))

        texto = " ".join(parte for parte in partes if parte)
        # NFKD + descarte dos acentos: "Açaí" -> "acai".
        sem_acento = unicodedata.normalize("NFKD", texto)
        return "".join(c for c in sem_acento if not unicodedata.combining(c)).lower()

    def _calcular_resumo_dia(self, data_iso):
        total = 0.0
        quantidade = 0
        por_tipo = {}
        total_aberto = 0.0
        quantidade_aberta = 0

        baixas = baixaComandas.carregar()

        for nome_arquivo in self._listar_arquivos_do_dia(data_iso):
            dados = self._ler_comanda(nome_arquivo)
            if dados is None:
                continue

            tipo = dados["tipo"]
            valor = dados["valor"]

            item = {
                "arquivo": nome_arquivo,
                "cliente": dados["cliente"],
                "valor": valor,
                "formaPagamento": dados["formaPagamento"],
                "status": dados["status"],
                "dataHora": dados["dataHora"],
                "codigo": dados["codigo"],
                # Tudo que a busca da tela precisa varrer, já normalizado (ver
                # _texto_de_busca). Vai pronto do Python porque o cupom inteiro
                # só existe aqui: o resumo não carrega "conteudo" (seria o
                # cupom de cada comanda dentro do cache do dia e do payload
                # que a malha sincroniza), e sem os itens não daria pra achar
                # uma comanda pelo que foi pedido.
                "busca": self._texto_de_busca(dados, tipo),
                # Ver comandaParserService.eh_suspeita — a tela marca com
                # borda vermelha em vez de listar à parte (ver
                # Fechamento.qml).
                "suspeita": dados["suspeita"],
            }

            # Comanda sem baixa é venda ainda não conferida: fica fora de
            # total/porTipo e só é contada à parte, pra tela poder mostrar o
            # quanto ainda não entrou no caixa (ver
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

        extras = extrasCaixa.listar_do_dia(data_iso)
        total_extras = sum(item["valor"] for item in extras)

        return {
            "data": data_iso,
            "total": total,
            "quantidade": quantidade,
            "porTipo": por_tipo,
            "abertas": {"quantidade": quantidade_aberta, "total": total_aberto},
            "extras": {"quantidade": len(extras), "total": total_extras, "itens": extras},
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
        if resumo_em_cache is not None and self._cache_tem_busca(resumo_em_cache):
            return resumo_em_cache

        return self.calcularFechamento(data_iso)

    @staticmethod
    def _cache_tem_busca(resumo):
        """Se o resumo em cache foi gravado por uma versão que já montava o
        campo "busca" de cada comanda (ver _texto_de_busca).

        Sem esta checagem a busca da tela ficaria cega justamente nos dias
        passados — que são os que sempre vêm do cache, e onde mais se procura
        uma comanda. Recalcular o dia é O(k) nas comandas daquele dia e grava
        o cache novo, então isso acontece uma vez por dia antigo visitado."""
        for grupo in (resumo.get("porTipo") or {}).values():
            for comanda in grupo.get("comandas") or []:
                if "busca" not in comanda:
                    return False
        return True

    # ---------- Cupom impresso ao "Fechar Caixa" ----------

    def _somar_por_forma_pagamento(self, tipo, comandas):
        """{"dinheiro", "pix", "cartao"} com a soma de `comandas` (a lista
        já filtrada de um tipo, vinda de porTipo[tipo]["comandas"]) por
        forma de pagamento. "Crédito" e "Débito" caem no mesmo balde
        "cartao" — o cupom não distingue os dois, só pergunta "cartão".

        Mesa não tem uma forma de pagamento por comanda (ver
        comandaParserService.eh_suspeita) — cada divisão da conta paga do
        seu jeito, então aqui a comanda precisa ser relida do disco pra
        somar por divisão (ver comandaParserService.extrair_divisoes_mesa)."""
        somas = {"dinheiro": 0.0, "pix": 0.0, "cartao": 0.0}

        def balde(forma):
            if forma == "Dinheiro":
                return "dinheiro"
            if forma == "Pix":
                return "pix"
            if forma in ("Crédito", "Débito"):
                return "cartao"
            return None

        if tipo == "Mesa":
            for item in comandas:
                dados = self._ler_comanda(item["arquivo"])
                if dados is None:
                    continue
                for divisao in parser.extrair_divisoes_mesa(dados["conteudo"]):
                    chave = balde(divisao["formaPagamento"])
                    if chave:
                        somas[chave] += divisao["valor"]
            return somas

        for item in comandas:
            chave = balde(item.get("formaPagamento", ""))
            if chave:
                somas[chave] += item.get("valor", 0.0)
        return somas

    def _montar_recibo_fechamento(self, data_iso, resumo):
        """Monta, em bytes ESC/POS, o cupom-resumo impresso ao clicar
        "Fechar Caixa": bruto, líquido (bruto menos os pagamentos de
        diária), o total de cada origem já dividido por forma de
        pagamento, os pagamentos de diária do dia e o Lucro (ver
        services/formulaLucroService.py, a mesma fórmula configurável que
        Fechamento.qml mostra na tela)."""

        def fmt(valor):
            return f"R$ {valor:.2f}".replace(".", ",")

        partes_data = data_iso.split("-")
        data_formatada = f"{partes_data[2]}/{partes_data[1]}/{partes_data[0]}" if len(partes_data) == 3 else data_iso

        bruto = resumo.get("total", 0.0)
        extras_info = resumo.get("extras") or {"total": 0.0, "itens": []}
        total_extras = extras_info.get("total", 0.0)
        itens_extras = extras_info.get("itens", [])
        liquido = bruto - total_extras

        contagem = contagemCaixa.obter_dia(data_iso) or {}
        total_contagem = contagem.get("cartao", 0) + contagem.get("dinheiro", 0) + contagem.get("pix", 0)
        lucro = formulaLucroService.calcular_lucro(bruto, total_contagem, total_extras)

        linhas = [
            f"{estilo.NEGRITO_LIGA}FECHAMENTO DE CAIXA{estilo.NEGRITO_DESLIGA}",
            f"Data: {data_formatada}",
            *estilo.linhas_espacamento_secoes(),
            "-" * 40,
            *estilo.linhas_espacamento_secoes(),
            f"Total bruto vendido: {fmt(bruto)}",
            f"Total líquido (bruto - extras): {fmt(liquido)}",
            *estilo.linhas_espacamento_secoes(),
            "-" * 40,
            f"{estilo.NEGRITO_LIGA}POR ORIGEM{estilo.NEGRITO_DESLIGA}",
            "-" * 40,
        ]

        por_tipo = resumo.get("porTipo") or {}
        algum_tipo = False
        for tipo in ("Balcão", "Entrega", "Mesa"):
            info = por_tipo.get(tipo)
            if not info or info.get("quantidade", 0) == 0:
                continue
            algum_tipo = True
            formas = self._somar_por_forma_pagamento(tipo, info.get("comandas", []))
            linhas.extend(estilo.linhas_espacamento_secoes())
            linhas.append(f"{estilo.NEGRITO_LIGA}{tipo}: {fmt(info.get('total', 0.0))}{estilo.NEGRITO_DESLIGA}")
            linhas.append(f"  Dinheiro: {fmt(formas['dinheiro'])}")
            linhas.append(f"  Pix: {fmt(formas['pix'])}")
            linhas.append(f"  Cartão: {fmt(formas['cartao'])}")

        if not algum_tipo:
            linhas.extend(estilo.linhas_espacamento_secoes())
            linhas.append("Nenhuma comanda lançada neste dia.")

        linhas.extend(estilo.linhas_espacamento_secoes())
        linhas.append("-" * 40)
        linhas.append(f"{estilo.NEGRITO_LIGA}PAGAMENTOS DE DIÁRIA{estilo.NEGRITO_DESLIGA}")
        linhas.append("-" * 40)
        if itens_extras:
            for item in itens_extras:
                linhas.append(f"{item.get('funcionario', '')} - {item.get('dataHora', '')} - {fmt(item.get('valor', 0.0))}")
        else:
            linhas.append("Nenhum pagamento de diária neste dia.")

        linhas.extend(estilo.linhas_espacamento_secoes())
        linhas.append("-" * 40)
        linhas.append(f"{estilo.NEGRITO_LIGA}LUCRO: {fmt(lucro)}{estilo.NEGRITO_DESLIGA}")
        linhas.append("-" * 40)

        conteudo = "\n".join(linhas) + "\n"
        return conteudo.encode(parser.CODEPAGE_IMPRESSORA, errors="replace")

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def imprimirFechamentoCaixa(self, data_iso):
        """Imprime o cupom-resumo do dia (ver _montar_recibo_fechamento).
        Chamado só pelo botão "Fechar Caixa" em Fechamento.qml —
        calcularFechamento sozinho não imprime nada, porque também é
        chamado por outros fluxos (darBaixa, registrarExtraDiaria,
        reconciliação com outra máquina) que não devem disparar impressão
        nenhuma. O resultado chega depois, assíncrono, por
        redeController.impressaoResultado, igual a qualquer outra
        impressão do app."""
        resumo = self._calcular_resumo_dia(data_iso)
        rede.solicitar_impressao(self._montar_recibo_fechamento(data_iso, resumo))
        return True

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
        de Fechamento precisa abrir pra corrigir: uma comanda com borda
        vermelha (ver comandaParserService.eh_suspeita) só aparece na lista
        de "Mapeamento por origem" depois de baixada."""
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

    # ---------- Extras (pagamento de diária a funcionário, ver qml/pages/fechamento/PopupExtras.qml) ----------

    @pyqtSlot(str, str, str, result="QVariantMap")
    @protegido({})
    def registrarExtraDiaria(self, data_iso, funcionario, valor_texto):
        """Lança um pagamento de diária no dia `data_iso` e devolve o
        registro gravado (com "id"), ou {} se o nome vier vazio ou o valor
        não for positivo. O registro devolvido já basta para o popup montar
        e imprimir o recibo, sem precisar de uma segunda chamada."""
        funcionario = (funcionario or "").strip()
        valor = texto.valor_para_float(valor_texto)
        if not funcionario or valor <= 0:
            return {}

        agora = datetime.now()
        data_hora = agora.strftime("%d/%m/%Y %H:%M:%S")
        id_evento = extrasCaixa.registrar(data_iso, funcionario, valor, data_hora)

        # O id viaja junto pra que todas as máquinas gravem a MESMA marca
        # pra este lançamento — mesmo cuidado de darBaixa.
        rede.publicarEvento(_EVENTO_EXTRA_LANCADO, {
            "id": id_evento,
            "dataIso": data_iso,
            "funcionario": funcionario,
            "valor": valor,
            "dataHora": data_hora,
            "idEventoRevisao": id_evento,
        })

        # calcularFechamento (e não _recalcular_e_cachear): o caixa do dia
        # mudou por decisão desta máquina, então a malha inteira precisa
        # saber que aquele dia mudou aqui — mesmo raciocínio de darBaixa.
        self.calcularFechamento(data_iso)
        self.extrasAtualizados.emit()

        return {
            "id": id_evento,
            "dataIso": data_iso,
            "funcionario": funcionario,
            "valor": valor,
            "dataHora": data_hora,
        }

    @pyqtSlot(str, str, str, result="QVariantMap")
    @protegido({})
    def editarExtraDiaria(self, id_evento, funcionario, valor_texto):
        """Corrige o nome/valor de um pagamento de diária já lançado —
        mesmo id, mesma dataHora original (ver
        services/rede/extrasCaixa.py:editar) — e propaga a edição pra
        malha. Devolve o registro atualizado (mesmo formato de
        registrarExtraDiaria), ou {} se o nome vier vazio, o valor não for
        positivo, ou o lançamento não existir mais."""
        funcionario = (funcionario or "").strip()
        valor = texto.valor_para_float(valor_texto)
        if not funcionario or valor <= 0:
            return {}

        registro_atual = extrasCaixa.carregar().get(id_evento)
        if registro_atual is None:
            return {}

        id_revisao = extrasCaixa.editar(id_evento, funcionario, valor)
        if id_revisao is None:
            return {}

        data_iso = registro_atual.get("dataIso", "")
        data_hora = registro_atual.get("dataHora", "")

        rede.publicarEvento(_EVENTO_EXTRA_LANCADO, {
            "id": id_evento,
            "dataIso": data_iso,
            "funcionario": funcionario,
            "valor": valor,
            "dataHora": data_hora,
            "idEventoRevisao": id_revisao,
        })

        self.calcularFechamento(data_iso)
        self.extrasAtualizados.emit()

        return {
            "id": id_evento,
            "dataIso": data_iso,
            "funcionario": funcionario,
            "valor": valor,
            "dataHora": data_hora,
        }

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def excluirExtraDiaria(self, id_evento):
        """Apaga um pagamento de diária já lançado (ver
        services/rede/extrasCaixa.py:apagar) e propaga a exclusão pra
        malha. Devolve False se o lançamento já não existir mais aqui."""
        registro = extrasCaixa.carregar().get(id_evento)
        if registro is None:
            return False

        data_iso = registro.get("dataIso", "")
        quando = extrasCaixa.apagar(id_evento)

        rede.publicarEvento(_EVENTO_EXTRA_APAGADO, {"id": id_evento, "quando": quando})

        # calcularFechamento (e não _recalcular_e_cachear): o caixa do dia
        # mudou por decisão desta máquina — mesmo raciocínio de
        # registrarExtraDiaria/darBaixa.
        if data_iso:
            self.calcularFechamento(data_iso)
        self.extrasAtualizados.emit()
        return True

    def _montar_recibo_extra(self, registro):
        """Monta o recibo de pagamento de diária em bytes ESC/POS, pronto
        pra impressora — mesmo padrão de balcaoController._salvarComanda
        (linhas montadas com comandaEstiloService, depois codificadas na
        codepage da impressora). Termina com um espaço em branco e uma
        linha para assinatura, que este tipo de recibo não tinha antes."""
        linhas = [
            f"{estilo.NEGRITO_LIGA}PAGAMENTO DE DIÁRIA{estilo.NEGRITO_DESLIGA}",
            *estilo.linhas_espacamento_secoes(),
            "-" * 40,
            *estilo.linhas_espacamento_secoes(),
            f"Funcionário: {registro.get('funcionario', '')}",
            f"Valor: R$ {float(registro.get('valor', 0)):.2f}".replace(".", ","),
            f"Data: {registro.get('dataHora', '')}",
            *estilo.linhas_espacamento_secoes(),
            "-" * 40,
            "",
            "",
            "_" * 30,
            "Assinatura",
        ]
        conteudo = "\n".join(linhas) + "\n"
        return conteudo.encode(parser.CODEPAGE_IMPRESSORA, errors="replace")

    @pyqtSlot("QVariantMap", result=bool)
    @protegido(False)
    def imprimirReciboExtra(self, registro):
        """Pede a impressão do recibo pela malha local, igual a
        reimprimirComanda — o resultado chega depois, assíncrono, por
        redeController.impressaoResultado."""
        rede.solicitar_impressao(self._montar_recibo_extra(registro))
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
