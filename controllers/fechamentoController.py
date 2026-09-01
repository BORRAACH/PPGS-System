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
from services.pizzeriaServerService import pizzeria_server
from services.rede import (baixaComandas, contagemCaixa, despesasCaixa, edicoesCaixa, extrasCaixa,
                           fechamentoCache, rede, relogio, tombstones)

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

# Despesas do dia (ver services/rede/despesasCaixa.py). Eventos próprios,
# e não um campo "tipo" dentro dos de extras, pelo mesmo motivo que os
# dois módulos são separados: as duas coisas entram na conta do dia em
# sentidos opostos.
_EVENTO_DESPESA_LANCADA = "despesa_lancada"
_EVENTO_DESPESA_APAGADA = "despesa_apagada"

# Alteração feita numa comanda que JÁ tinha baixa (ver
# services/rede/edicoesCaixa.py). Mesmo raciocínio de _EVENTO_COMANDA_BAIXADA:
# o payload é o fato em si (quem, o quê, quanto mudou), porque a outra máquina
# não tem como deduzir sozinha que houve correção — ela vê a comanda nova
# chegar e a antiga sumir, o que é indistinguível de um lançamento comum
# seguido de uma exclusão.
#
# Não há evento de "edição apagada": o domínio é append-only, uma alteração
# registrada nunca é desfeita.
_EVENTO_EDICAO_CAIXA = "edicao_caixa"

# Contagem manual de Cartão/Dinheiro/Pix, usada pra calcular o "Lucro" (ver
# services/rede/contagemCaixa.py). Ao contrário dos dois eventos acima, uma
# gravação de contagem SOBRESCREVE a anterior do mesmo dia — o payload
# carrega o idEvento pra quem recebe arbitrar qual versão é mais nova (ver
# services/rede/contagemCaixa.py:aplicar_remoto), mesmo desenho de
# services/cardapioService.py.
_EVENTO_CONTAGEM_ATUALIZADA = "contagem_caixa_atualizada"


# Largura do papel, em colunas. É a mesma que comandaTextoService assume nas
# divisórias ("-" * 40) e no marcador de itens — está aqui como constante
# porque o recibo de diária precisa DELA para alinhar valor à direita, e um
# 40 solto no meio da montagem não diria de onde veio.
_COLUNAS_PAPEL = 40

# Como o valor da diária é discriminado no recibo de pagamento (ver
# _montar_recibo_extra). Rótulo e alíquota vieram do dono, e são exatamente o
# que sai impresso.
#
# ATENÇÃO ao somar: estas cinco alíquotas dão 1,0001, não 1. A coluna fecha um
# centavo ACIMA do "TOTAL A RECEBER" a cada R$ 100 de diária (R$ 100,00 vira
# 8,00 + 7,67 + 2,56 + 7,67 + 74,11 = R$ 100,01). O total impresso é sempre o
# valor lançado, nunca a soma das partes — então o recibo nunca cobra a mais do
# que foi pago; o que não bate é a conferência da coluna. Para fechar exato,
# a alíquota do salário líquido teria de ser 0,741, ou a linha teria de ser
# calculada como o resto (valor menos as outras quatro).
_DISCRIMINACAO_DIARIA = (
    ("FGTS", 0.08),
    ("FÉRIAS", 0.0767),
    ("1/3 SOBRE AS FÉRIAS", 0.0256),
    ("13º SALÁRIO", 0.0767),
    ("SALÁRIO LÍQUIDO", 0.7411),
)

# Quem paga, na linha "RECEBI DE". Constante, e não configurável, porque não
# existe cadastro de estabelecimento em lugar nenhum do app — quando existir, é
# daqui que ele passa a ser lido, e este é o único ponto a mexer.
_NOME_EMPRESA = "Grande Sabor"


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
    despesasAtualizadas = pyqtSignal()

    # Emitido quando uma alteração numa comanda já fechada é aprendida de
    # OUTRA máquina (ver services/rede/edicoesCaixa.py). Mesmo raciocínio de
    # extrasAtualizados: uma alteração feita NESTA máquina não passa por aqui
    # — quem chamou registrarEdicaoCaixa/registrarExclusaoCaixa já sabe o que
    # acabou de acontecer.
    edicoesAtualizadas = pyqtSignal()

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
        rede.registrarEvento(_EVENTO_DESPESA_LANCADA, self._ao_receber_despesa_remota)
        rede.registrarEvento(_EVENTO_DESPESA_APAGADA, self._ao_receber_despesa_apagada_remota)
        rede.registrarEvento(_EVENTO_EDICAO_CAIXA, self._ao_receber_edicao_remota)
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
            despesasCaixa.DOMINIO,
            self._resumo_despesas,
            self._obter_despesa_reconciliacao,
            self._aplicar_despesa_reconciliacao,
            self._apagar_despesa_reconciliacao,
        )
        rede.registrarDominioSincronizado(
            edicoesCaixa.DOMINIO,
            self._resumo_edicoes,
            self._obter_edicao_reconciliacao,
            self._aplicar_edicao_reconciliacao,
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

    # ---------- Anti-entropy do domínio "despesas" ----------
    # Decalque exato do bloco de "extras" acima, com o mesmo contrato de dois
    # ids (identidade imutável + revisão de conteúdo) e a mesma janela de
    # reconciliação. O que muda entre os dois é só o SENTIDO com que o valor
    # entra na conta do dia — ver _calcular_resumo_dia e o topo de
    # services/rede/despesasCaixa.py.

    def _resumo_despesas(self):
        limite = (datetime.now() - timedelta(days=_JANELA_RECONCILIACAO_FECHAMENTO_DIAS)).strftime("%Y-%m-%d")
        itens = {}
        for id_evento, registro in despesasCaixa.carregar().items():
            if registro.get("dataIso", "") < limite:
                continue
            itens[id_evento] = registro.get("idEventoRevisao", id_evento)
        return {"itens": itens, "apagados": tombstones.carregar(despesasCaixa.DOMINIO)}

    def _obter_despesa_reconciliacao(self, id_evento):
        registro = despesasCaixa.carregar().get(id_evento)
        if not registro:
            return None
        return dict(registro, id=id_evento)

    def _aplicar_despesa_reconciliacao(self, id_evento, payload):
        self._registrar_despesa_aprendida(id_evento, payload or {})

    def _apagar_despesa_reconciliacao(self, id_evento):
        # tombstones.mesclar já gravou o tombstone antes de chamar aqui.
        quando = tombstones.carregar(despesasCaixa.DOMINIO).get(id_evento, "")
        self._aplicar_exclusao_despesa(id_evento, quando)

    def _ao_receber_despesa_remota(self, payload):
        payload = payload or {}
        id_evento = payload.get("id")
        if id_evento:
            self._registrar_despesa_aprendida(id_evento, payload)

    def _ao_receber_despesa_apagada_remota(self, payload):
        payload = payload or {}
        id_evento = payload.get("id")
        if id_evento:
            self._aplicar_exclusao_despesa(id_evento, payload.get("quando", ""))

    def _aplicar_exclusao_despesa(self, id_evento, quando):
        registro = despesasCaixa.carregar().get(id_evento)
        data_iso = registro.get("dataIso", "") if registro else ""

        despesasCaixa.apagar(id_evento, quando=quando or None)

        if data_iso:
            self._recalcular_e_cachear(data_iso)
        self.despesasAtualizadas.emit()

    def _registrar_despesa_aprendida(self, id_evento, payload):
        """Mesma lógica de _registrar_extra_aprendido: grava um lançamento
        novo OU aplica uma edição, conforme o id já seja conhecido aqui, e
        nunca ressuscita o que já foi apagado."""
        if id_evento in tombstones.carregar(despesasCaixa.DOMINIO):
            return

        data_iso = payload.get("dataIso")
        mudou = False

        if id_evento in despesasCaixa.carregar():
            mudou = despesasCaixa.aplicar_edicao_remota(
                id_evento,
                payload.get("nome", ""),
                payload.get("valor", 0),
                payload.get("idEventoRevisao", ""),
            )
        else:
            despesasCaixa.registrar(
                data_iso or "",
                payload.get("nome", ""),
                payload.get("valor", 0),
                payload.get("dataHora", ""),
                quando=id_evento,
            )
            mudou = True

        if not mudou:
            return

        if data_iso:
            self._recalcular_e_cachear(data_iso)
        self.despesasAtualizadas.emit()

    # ---------- Anti-entropy do domínio "edicoes" (alterações no caixa fechado) ----------
    # O mais simples dos domínios daqui, e de propósito: uma alteração já
    # feita é um fato imutável, então não há revisão de conteúdo (a versão é
    # o próprio id), não há tombstone e não há comparador próprio —
    # reconciliar é a união dos dois lados, mesmo contrato de
    # services/rede/historicoEventos.py.

    def _resumo_edicoes(self):
        """Anuncia as alterações recentes, na mesma janela dos outros
        domínios do caixa: uma correção num dia mais velho que isso não muda
        mais nenhum cupom que alguém vá reimprimir. O registro em si NÃO é
        purgado do disco por causa disso — sair da janela é parar de ser
        anunciado, não deixar de existir."""
        limite = (datetime.now() - timedelta(days=_JANELA_RECONCILIACAO_FECHAMENTO_DIAS)).strftime("%Y-%m-%d")
        return edicoesCaixa.resumo(limite)

    def _obter_edicao_reconciliacao(self, id_evento):
        return edicoesCaixa.obter(id_evento)

    def _aplicar_edicao_reconciliacao(self, id_evento, payload):
        self._registrar_edicao_aprendida(id_evento, payload or {})

    def _ao_receber_edicao_remota(self, payload):
        """Reação ao gossip "edicao_caixa" — o caminho rápido, pra uma
        correção feita em outra máquina aparecer no cupom daqui na hora, sem
        esperar o próximo ciclo de reconciliação."""
        payload = payload or {}
        id_evento = payload.get("id")
        if id_evento:
            self._registrar_edicao_aprendida(id_evento, payload)

    def _registrar_edicao_aprendida(self, id_evento, payload):
        """Grava uma alteração aprendida de fora, venha ela do gossip ou da
        reconciliação — os dois caminhos desembocam aqui. Idempotente pelo id
        (ver edicoesCaixa.aplicar): a mesma novidade chega pelos dois, e
        reaplicar só faria a tela piscar à toa.

        Não chama _recalcular_e_cachear, ao contrário dos extras: a alteração
        em si não muda nenhum número do dia — quem muda é a comanda nova e a
        baixa dela, que viajam pelos próprios domínios ("pedidos"/"baixas") e
        já disparam o recálculo por lá."""
        if not edicoesCaixa.aplicar(id_evento, payload):
            return

        self.edicoesAtualizadas.emit()

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
            # Quem lançou o pedido — alimenta o filtro por usuário da tela e
            # entra na busca (ver _texto_de_busca). "" quando o cupom não traz
            # a linha "Usuário:".
            "usuario": parser.extrair_campo(parser.PADRAO_USUARIO, conteudo),
            "valor": parser.extrair_valor_total(conteudo),
            "formaPagamento": forma_pagamento,
            "status": status,
            "dataHora": parser.extrair_campo(parser.PADRAO_DATA, conteudo),
            "conteudo": conteudo.strip("\n"),
            "suspeita": parser.eh_suspeita(tipo, cliente, forma_pagamento, status, endereco),
        }

    @staticmethod
    def _itens_da_comanda(conteudo):
        """Os itens do pedido de volta a partir do cupom já lido (desfaz
        comandaTextoService.formatar_tabela — ver
        comandaParserService.reconstruir_itens). Lista vazia quando a comanda
        não tem tabela de itens reconhecível.

        Fica separado porque o mesmo parse serve a dois consumidores no
        resumo do dia: o texto de busca da tela e a contagem de produtos
        vendidos. Sem isso, cada comanda do dia seria varrida duas vezes."""
        linhas_tabela = parser.linhas_tabela_itens((conteudo or "").split("\n"))
        if linhas_tabela is None:
            return []
        return parser.reconstruir_itens(linhas_tabela)

    @staticmethod
    def _texto_de_busca(dados, tipo, itens):
        """Uma linha só, normalizada, com tudo por onde a comanda pode ser
        procurada na tela de Fechamento: modalidade, código, cliente, usuário
        que lançou, forma de pagamento, status, os itens pedidos e o valor.

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
        busca curta, enchendo o resultado de falso positivo.

        `itens` vem pronto de _itens_da_comanda — quem chama já precisou
        deles para contar os produtos vendidos do dia."""
        valor = dados.get("valor") or 0.0
        com_virgula = f"{valor:.2f}".replace(".", ",")

        partes = [
            tipo,
            dados.get("codigo", ""),
            dados.get("cliente", ""),
            dados.get("usuario", ""),
            dados.get("formaPagamento", ""),
            dados.get("status", ""),
            dados.get("dataHora", ""),
            f"{valor:.2f}",
            com_virgula,
            com_virgula.replace(",", ""),
        ]

        for item in itens:
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
        # {nome do produto: [quantas vezes saiu, quanto somou]}. O nome é o
        # texto do item como saiu na comanda (já em caixa alta, com o tamanho
        # entre parênteses) — é a única identidade que um item tem depois de
        # impresso, já que o cupom não guarda id de cardápio. Uma pizza meio a
        # meio conta como UM produto ("SABOR A / SABOR B (GRANDE)"), que é o
        # que ela é do ponto de vista da venda.
        produtos = {}

        baixas = baixaComandas.carregar()

        for nome_arquivo in self._listar_arquivos_do_dia(data_iso):
            dados = self._ler_comanda(nome_arquivo)
            if dados is None:
                continue

            tipo = dados["tipo"]
            valor = dados["valor"]
            itens = self._itens_da_comanda(dados.get("conteudo"))

            item = {
                "arquivo": nome_arquivo,
                "cliente": dados["cliente"],
                "usuario": dados["usuario"],
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
                "busca": self._texto_de_busca(dados, tipo, itens),
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

            # Só as comandas com baixa entram aqui, pelo mesmo motivo de
            # total/porTipo logo acima: um pedido ainda não conferido não é
            # venda do caixa deste dia.
            for item_pedido in itens:
                nome = (item_pedido.get("pedido") or "").strip()
                if not nome:
                    continue
                contagem = produtos.setdefault(nome, [0, 0.0])
                contagem[0] += 1
                contagem[1] += texto.valor_para_float(item_pedido.get("valor"))

        extras = extrasCaixa.listar_do_dia(data_iso)
        total_extras = sum(item["valor"] for item in extras)

        despesas = despesasCaixa.listar_do_dia(data_iso)
        total_despesas = sum(item["valor"] for item in despesas)

        return {
            "data": data_iso,
            "total": total,
            "quantidade": quantidade,
            "porTipo": por_tipo,
            "abertas": {"quantidade": quantidade_aberta, "total": total_aberto},
            "extras": {"quantidade": len(extras), "total": total_extras, "itens": extras},
            # Despesas do dia. Entram na conta pelo lado OPOSTO ao dos
            # extras: soma-se este total à contagem de Cartão/Dinheiro/Pix,
            # para a gaveta parar de acusar falta por dinheiro que se sabe
            # onde foi parar (ver dinheiroComSaidas em Fechamento.qml, e
            # _montar_recibo_fechamento, que refaz a mesma soma pro cupom). A
            # chave não existe em resumos gravados em cache antes disto, e a
            # tela trata a ausência.
            "despesas": {"quantidade": len(despesas), "total": total_despesas, "itens": despesas},
            # Do mais vendido pro menos vendido, com desempate pelo nome —
            # ordem estável, que é o que permite comparar dois resumos com
            # `==` em _recalcular_e_cachear sem falso positivo de "mudou".
            "produtos": [
                {"nome": nome, "quantidade": contagem[0], "total": contagem[1]}
                for nome, contagem in sorted(produtos.items(), key=lambda par: (-par[1][0], par[0]))
            ],
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
        # Só a data, sem os números: _ao_receber_fechamento_remoto DESCARTA o
        # resumo recebido de propósito e recalcula o dia com as comandas da
        # própria máquina, então mandá-lo era gastar banda com um valor que o
        # outro lado nunca leu — mesmo raciocínio já escrito em
        # _obter_fechamento_reconciliacao, que sempre mandou só a data.
        # O resumo tem ~22 KB (a lista de produtos vendidos é a maior parte) e
        # isto é publicado a cada baixa, extra e abertura da tela.
        rede.publicarEvento(_EVENTO_FECHAMENTO_ATUALIZADO, {"data": data_iso})
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
        if resumo_em_cache is not None and self._cache_atualizado(resumo_em_cache):
            return resumo_em_cache

        return self.calcularFechamento(data_iso)

    @staticmethod
    def _cache_atualizado(resumo):
        """Se o resumo em cache foi gravado por uma versão do app que já
        montava tudo que o resumo tem hoje: o campo "busca" de cada comanda
        (ver _texto_de_busca) e a lista de produtos vendidos do dia (ver
        _calcular_resumo_dia).

        Sem esta checagem, os dias passados — que são os que sempre vêm do
        cache — ficariam com a busca cega e sem produtos justamente onde mais
        se procura uma comanda e onde o envio ao pizzeria-server precisa dos
        números. Recalcular o dia é O(k) nas comandas daquele dia e grava o
        cache novo, então isso acontece uma vez por dia antigo visitado.

        O campo "usuario" entra na mesma conferência: sem ele o filtro por
        usuário da tela veria um dia antigo inteiro como "sem usuário", que é
        pior que demorar um instante a mais na primeira visita ao dia."""
        if "produtos" not in resumo:
            return False

        for grupo in (resumo.get("porTipo") or {}).values():
            for comanda in grupo.get("comandas") or []:
                if "busca" not in comanda or "usuario" not in comanda:
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

    @staticmethod
    def _linhas_alteracoes_do_dia(data_iso, fmt):
        """Bloco "ALTERAÇÕES APÓS A BAIXA" do cupom: uma entrada por comanda
        já fechada que foi corrigida ou apagada depois, dizendo quem mexeu,
        quando, e o que o caixa daquele dia ganhou ou perdeu com isso (ver
        services/rede/edicoesCaixa.py).

        POR QUE ISTO SAI NO PAPEL. O total do dia já mudava sozinho quando
        alguém corrigia uma comanda fechada — dois cupons do mesmo dia
        traziam números diferentes sem nada explicando a diferença. A trilha
        existia só na tela de Rede (historicoEventos), que tem retenção de
        uma semana e não acompanha o papel que o dono guarda.

        Lido direto de edicoesCaixa, e NÃO do resumo do dia: o resumo é
        cacheado e sincronizado (services/rede/fechamentoCache.py), e um
        cupom reimpresso a partir de um cache gravado antes desta seção
        existir viria sem as alterações — justamente o cupom em que elas mais
        importam. Mesmo motivo de a contagem manual ser lida direto logo
        acima.

        O bloco sai mesmo sem nenhuma alteração, dizendo isso com todas as
        letras: num documento de caixa, "ninguém mexeu" é uma informação, e
        uma seção ausente seria indistinguível de uma versão antiga do app.
        """
        rotulos = {
            edicoesCaixa.ACAO_EDITADA: "Corrigida",
            edicoesCaixa.ACAO_EXCLUIDA: "Apagada",
        }

        linhas = [estilo.formatar_campo("ALTERAÇÕES APÓS A BAIXA", "fech_edicoes_titulo")]

        alteracoes = edicoesCaixa.listar_do_dia(data_iso)
        if not alteracoes:
            linhas.extend(estilo.linhas_espacamento_secoes())
            # Sem alteração nenhuma, a mensagem ocupa o lugar das linhas de
            # alteração e usa o estilo delas — mesma escolha do caso vazio de
            # "POR ORIGEM", em vez de pedir mais um campo configurável.
            linhas.append(estilo.formatar_campo("Nenhuma alteração após a baixa.", "fech_edicoes_item"))
            return linhas

        for item in alteracoes:
            acao = item.get("acao", "")
            identificacao = " - ".join(
                parte for parte in (
                    rotulos.get(acao, acao or "Alterada"),
                    item.get("codigo", ""),
                    item.get("cliente", ""),
                ) if parte
            )

            # Sem ninguém cadastrado o guarda libera e devolve nome vazio (ver
            # UsuariosController.validarCodigo). A linha continua saindo: o
            # que interessa a quem confere é que o caixa foi mexido, e "não
            # identificado" já diz que o cadastro estava vazio na hora.
            usuario = item.get("usuario", "") or "não identificado"

            antes = fmt(item.get("valorAntes", 0.0))
            if acao == edicoesCaixa.ACAO_EXCLUIDA:
                transicao = f"{antes} -> comanda apagada"
            elif item.get("noCaixa"):
                transicao = f"{antes} -> {fmt(item.get('valorDepois', 0.0))}"
            else:
                transicao = f"{antes} -> {fmt(item.get('valorDepois', 0.0))} (fora do caixa)"

            linhas.extend(estilo.linhas_espacamento_secoes())
            linhas.append(estilo.formatar_campo(identificacao, "fech_edicoes_item"))
            # Os dois espaços de recuo ficam FORA do trecho estilizado, igual
            # às formas de pagamento do bloco "POR ORIGEM".
            autoria = f"{usuario} - {item.get('dataHora', '')}".strip(" -")
            linhas.append(f"  {estilo.formatar_campo(autoria, 'fech_edicoes_autor')}")
            linhas.append(f"  {estilo.formatar_campo(transicao, 'fech_edicoes_autor')}")

        return linhas

    def _montar_recibo_fechamento(self, data_iso, resumo):
        """Monta, em bytes ESC/POS, o cupom-resumo impresso ao clicar
        "Fechar Caixa": bruto, líquido (bruto menos os pagamentos de
        diária), o total de cada origem já dividido por forma de
        pagamento, os pagamentos de diária do dia, a sobra/falta do caixa
        (a contagem manual comparada com o bruto) e o lucro (a contagem
        menos as diárias).

        ESSAS DUAS ÚLTIMAS CONTAS SÓ EXISTEM AQUI. A tela de Fechamento
        mostrava as duas em cartões ao lado da contagem e não mostra mais: o
        veredito sobre o dia é do cupom, e a tela ficou com o que se digita e
        se confere. Quem mexer nas contas abaixo não tem outro lugar pra
        conferir contra — este é o único que as faz.

        Sai também o bloco "ALTERAÇÕES APÓS A BAIXA" — as comandas já
        fechadas que alguém corrigiu ou apagou depois, com o nome de quem
        fez (ver _linhas_alteracoes_do_dia).

        Mesmo caminho de _montar_recibo_extra e das comandas de venda: cada
        campo vira um renderizador já estilizado, e a ordem/divisórias saem
        da configuração da tela (comandaTextoService.montar_linhas_por_ordem).
        "fech_por_origem", "fech_diarias" e "fech_edicoes" são blocos de
        várias linhas — equivalentes à tabela de itens de uma comanda:
        posição única, estilo por sub-linha."""

        def fmt(valor):
            return f"R$ {valor:.2f}".replace(".", ",")

        partes_data = data_iso.split("-")
        data_formatada = f"{partes_data[2]}/{partes_data[1]}/{partes_data[0]}" if len(partes_data) == 3 else data_iso

        bruto = resumo.get("total", 0.0)
        extras_info = resumo.get("extras") or {"total": 0.0, "itens": []}
        total_extras = extras_info.get("total", 0.0)
        itens_extras = extras_info.get("itens", [])
        liquido = bruto - total_extras

        despesas_info = resumo.get("despesas") or {"total": 0.0, "itens": []}
        total_despesas = despesas_info.get("total", 0.0)

        contagem = contagemCaixa.obter_dia(data_iso) or {}
        # Diárias e despesas entram na contagem somadas ao DINHEIRO, como na
        # tela: as duas saem em cédula da gaveta, e sem somá-las de volta esse
        # dinheiro apareceria como falta (ver dinheiroComSaidas em
        # Fechamento.qml). O papel e a tela precisam dar o mesmo número — é o
        # pior tipo de divergência, porque o dono confere um contra o outro.
        saidas_em_dinheiro = total_extras + total_despesas
        total_contagem = (
            contagem.get("cartao", 0)
            + contagem.get("dinheiro", 0)
            + saidas_em_dinheiro
            + contagem.get("pix", 0)
        )
        # Sobra (positivo) ou falta (negativo) do caixa: o que foi contado à
        # mão comparado com o que as comandas do dia dizem que foi vendido.
        #
        # Diária e despesa NÃO aparecem aqui como falta — elas já entraram em
        # total_contagem, logo acima. Antes apareciam, e o argumento era que
        # era isso que se queria enxergar; na prática obrigava quem confere a
        # fazer a conta de cabeça toda vez pra descontar o que ele mesmo tinha
        # acabado de lançar.
        #
        # CUIDADO AO LER: o bruto só conta comandas que receberam baixa (ver
        # _calcular_resumo_dia), então comanda em aberto puxa isto pro lado de
        # "SOBROU" sem que tenha sobrado nada.
        diferenca = total_contagem - bruto
        # O lucro do dia é outra conta, e não passa pelo bruto: o que entrou na
        # gaveta menos o que saiu dela em diária e em despesa. O bruto serve
        # pra conferir a gaveta (a diferença acima), não pra dizer quanto
        # sobrou no fim do dia — venda que ainda não virou dinheiro contado
        # não é lucro nenhum.
        #
        # Como as saídas entram em total_contagem logo acima e são subtraídas
        # aqui, elas se anulam, e o lucro acaba sendo exatamente o dinheiro que
        # sobrou: cartão + dinheiro contado + pix. ISSO CORRIGIU UM DESCONTO EM
        # DOBRO: a diária saía da gaveta (logo, a contagem já era menor por
        # causa dela) e ainda era subtraída aqui — uma diária de R$ 80 tirava
        # R$ 160 do lucro do dia.
        lucro = total_contagem - total_extras - total_despesas

        linhas_origem = [estilo.formatar_campo("POR ORIGEM", "fech_origem_titulo")]
        por_tipo = resumo.get("porTipo") or {}
        algum_tipo = False
        for tipo in ("Balcão", "Entrega", "Mesa"):
            info = por_tipo.get(tipo)
            if not info or info.get("quantidade", 0) == 0:
                continue
            algum_tipo = True
            formas = self._somar_por_forma_pagamento(tipo, info.get("comandas", []))
            linhas_origem.extend(estilo.linhas_espacamento_secoes())
            linhas_origem.append(estilo.formatar_campo(f"{tipo}: {fmt(info.get('total', 0.0))}", "fech_origem_nome"))
            for rotulo, chave_forma in (("Dinheiro", "dinheiro"), ("Pix", "pix"), ("Cartão", "cartao")):
                linhas_origem.append(f"  {estilo.formatar_campo(f'{rotulo}: {fmt(formas[chave_forma])}', 'fech_origem_forma')}")

        if not algum_tipo:
            linhas_origem.extend(estilo.linhas_espacamento_secoes())
            # Sem origem nenhuma, a mensagem ocupa o lugar das linhas de
            # origem — e por isso usa o estilo delas, em vez de pedir mais um
            # campo configurável só pro caso vazio.
            linhas_origem.append(estilo.formatar_campo("Nenhuma comanda lançada neste dia.", "fech_origem_nome"))

        linhas_diarias = [estilo.formatar_campo("PAGAMENTOS DE DIÁRIA", "fech_diarias_titulo")]
        if itens_extras:
            for item in itens_extras:
                linhas_diarias.append(estilo.formatar_campo(
                    f"{item.get('funcionario', '')} - {item.get('dataHora', '')} - {fmt(item.get('valor', 0.0))}",
                    "fech_diarias_item",
                ))
        else:
            linhas_diarias.append(estilo.formatar_campo("Nenhum pagamento de diária neste dia.", "fech_diarias_item"))

        linhas_edicoes = self._linhas_alteracoes_do_dia(data_iso, fmt)

        renderizadores = {
            "fech_titulo": [estilo.formatar_campo("FECHAMENTO DE CAIXA", "fech_titulo")],
            "fech_data": [f"Data: {estilo.formatar_campo(data_formatada, 'fech_data')}"],
            "fech_bruto": [f"Total bruto vendido: {estilo.formatar_campo(fmt(bruto), 'fech_bruto')}"],
            "fech_liquido": [f"Total líquido (bruto - extras): {estilo.formatar_campo(fmt(liquido), 'fech_liquido')}"],
            "fech_por_origem": linhas_origem,
            "fech_diarias": linhas_diarias,
            "fech_edicoes": linhas_edicoes,
            # A chave continua "fech_lucro" mesmo o campo tendo virado
            # sobra/falta: é ela que está gravada no estilo e na ordem das
            # seções de cada máquina (ver Config/estilo_impressao.json), e
            # renomeá-la sumiria com a seção do cupom.
            "fech_lucro": [estilo.formatar_campo(
                f"{'SOBROU' if diferenca >= 0 else 'FALTOU'}: {fmt(abs(diferenca))}",
                "fech_lucro",
            )],
            "fech_lucro_real": [estilo.formatar_campo(f"LUCRO: {fmt(lucro)}", "fech_lucro_real")],
        }

        linhas = texto.montar_linhas_por_ordem(estilo.ordem_secoes(), renderizadores)
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

    # ---------- Envio do resumo do dia ao servidor central ----------

    def _montar_payload_servidor(self, data_iso, resumo):
        """Traduz o resumo interno do dia no corpo que o pizzeria-server
        espera em POST /fechamentos (ver models::Fechamento lá).

        Os números são exatamente os mesmos que saem no cupom de fechamento
        (ver _montar_recibo_fechamento) — o papel impresso e o que o servidor
        guarda não podem contar histórias diferentes do mesmo dia."""
        bruto = resumo.get("total", 0.0)
        total_extras = (resumo.get("extras") or {}).get("total", 0.0)

        origens = []
        for tipo, info in (resumo.get("porTipo") or {}).items():
            formas = self._somar_por_forma_pagamento(tipo, info.get("comandas", []))
            origens.append({
                "tipo": tipo,
                "quantidade": info.get("quantidade", 0),
                "total": info.get("total", 0.0),
                "dinheiro": formas["dinheiro"],
                "pix": formas["pix"],
                "cartao": formas["cartao"],
            })

        return {
            "data": data_iso,
            # É este id que decide, no servidor, qual de dois fechamentos do
            # mesmo dia predomina — um relógio lógico híbrido, não o relógio
            # de parede: as máquinas da pizzaria não rodam NTP, e um envio
            # vindo de um terminal adiantado não pode desfazer um fechamento
            # que aconteceu depois (ver services/rede/relogio.py).
            "id_evento": relogio.novo_id(),
            "enviado_em": datetime.now().isoformat(timespec="seconds"),
            "quantidade_vendas": resumo.get("quantidade", 0),
            "total_vendas": bruto,
            "total_extras": total_extras,
            "total_liquido": bruto - total_extras,
            "origens": origens,
            "produtos": resumo.get("produtos") or [],
        }

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def enviarFechamentoServidor(self, data_iso):
        """Publica o resumo de `data_iso` no pizzeria-server. Chamado pelo
        botão "Fechar Caixa" (ver Fechamento.qml), logo depois de
        calcularFechamento — daí ler do cache que aquele acabou de gravar em
        vez de varrer as comandas do dia uma terceira vez.

        O resultado chega depois, assíncrono, por
        pizzeriaServerController.fechamentoEnviado — igual a qualquer outra
        chamada ao servidor central."""
        resumo = fechamentoCache.carregar(data_iso)
        if resumo is None or not self._cache_atualizado(resumo):
            resumo = self._calcular_resumo_dia(data_iso)

        pizzeria_server.enviarFechamento(self._montar_payload_servidor(data_iso, resumo))
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
    @pyqtSlot(str, int, result=bool)
    @protegido(False)
    def reimprimirComanda(self, nome_arquivo, copias=1):
        """Manda a comanda pra impressora exatamente como ela está em disco,
        `copias` vezes (padrão 1).

        Sem decodificar e sem limpar_codigos_impressora: o .txt JÁ é o cupom
        ESC/POS byte a byte (é por isso que ele não é um JSON — ver
        services/rede/baixaComandas.py), então reimprimir é reenviar o
        arquivo, não remontar a comanda. Diferente de editar, não grava nada
        novo: nenhum arquivo, nenhum código sequencial, nenhum evento na malha.

        As cópias repetem só o PEDIDO de impressão, nunca a leitura nem a
        gravação — mesmo desenho de BalcaoController.enviarPedido. Uma
        reimpressão não grava nada de todo jeito, mas manter os dois iguais é o
        que evita alguém "melhorar" um dos dois sozinho depois.

        O True daqui significa só "os pedidos de impressão foram despachados" —
        a impressão em si é assíncrona e o resultado chega por
        rede.impressaoResultado, igual ao de um pedido novo. Com várias cópias
        chega um resultado por cópia."""
        nome_arquivo = os.path.basename(nome_arquivo)
        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)

        try:
            with open(caminho, "rb") as arquivo:
                conteudo_bytes = arquivo.read()
        except OSError as erro:
            print(f"[FechamentoController] Falha ao ler {caminho} para reimpressão: {erro}")
            return False

        for _ in range(max(1, copias)):
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

    # ---------- Alterações em comanda já fechada (ver services/rede/edicoesCaixa.py) ----------
    # Os dois slots abaixo são chamados pela QML no MOMENTO em que a
    # alteração acontece de verdade, e não quando ela é pedida: a edição
    # registra ao SALVAR o formulário (Balcao.qml/Entrega.qml), não ao abrir
    # — quem abre a correção e desiste no meio não alterou caixa nenhum, e um
    # registro ali viraria uma linha no cupom acusando uma mudança que nunca
    # houve.
    #
    # Nos dois casos o usuário vem de quem chamou (é ele que tem o nome
    # devolvido por PopupAutorizacao), mas QUEM DECIDE SE HÁ O QUE REGISTRAR
    # é este controller, olhando se a comanda tinha baixa. Deixar essa
    # decisão na QML significaria repetir a mesma pergunta em três telas, e
    # bastaria uma esquecer para a alteração sumir do cupom em silêncio.

    def _instantaneo_da_comanda(self, nome_arquivo):
        """(codigo, cliente, valor) da comanda, lidos do .txt enquanto ele
        ainda existe. Tudo vazio/zero quando o arquivo não pôde ser lido — o
        registro da alteração vale mesmo assim: perder o valor antigo é ruim,
        perder a linha inteira é pior."""
        dados = self._ler_comanda(os.path.basename(nome_arquivo))
        if dados is None:
            return "", "", 0.0
        return dados.get("codigo", ""), dados.get("cliente", ""), dados.get("valor", 0.0)

    @pyqtSlot(str, str, str, bool, result=bool)
    @protegido(False)
    def registrarEdicaoCaixa(self, arquivo_original, arquivo_novo, usuario, manteve_baixa):
        """Anota que uma comanda JÁ FECHADA foi corrigida, para a linha sair
        no cupom de fechamento daquele dia (ver _montar_recibo_fechamento).

        Chamado por Balcao.qml/Entrega.qml logo depois de a comanda nova ser
        gravada e ANTES de a antiga ser apagada — é a única janela em que os
        dois valores existem em disco ao mesmo tempo, e é a diferença entre
        eles que interessa a quem confere o caixa.

        Devolve False, sem registrar nada, quando a comanda editada não tinha
        baixa: aí não houve alteração de caixa nenhuma, só uma correção comum
        de uma venda ainda não conferida (o caminho da Consulta)."""
        arquivo_original = os.path.basename(arquivo_original or "")
        arquivo_novo = os.path.basename(arquivo_novo or "")
        if not arquivo_original or not baixaComandas.esta_fechada(arquivo_original):
            return False

        codigo, cliente, valor_antes = self._instantaneo_da_comanda(arquivo_original)
        _codigo_novo, _cliente_novo, valor_depois = self._instantaneo_da_comanda(arquivo_novo)

        return self._registrar_alteracao_caixa(
            arquivo_original,
            edicoesCaixa.ACAO_EDITADA,
            usuario,
            codigo,
            cliente,
            valor_antes,
            valor_depois,
            # Uma correção que NÃO devolve a baixa tira a venda do caixa (ver
            # qml/pages/fechamento/PopupManterBaixa.qml): o dia perde o valor
            # inteiro, e o cupom precisa dizer isso — senão a linha mostraria
            # uma troca de valores enquanto o total do dia caiu tudo.
            no_caixa=bool(manteve_baixa),
            arquivo_novo=arquivo_novo,
        )

    @pyqtSlot(str, str, result=bool)
    @protegido(False)
    def registrarExclusaoCaixa(self, arquivo, usuario):
        """Anota que uma comanda JÁ FECHADA foi apagada de vez. Chamado por
        PopupConfirmarExclusao.qml ANTES de apagar, enquanto ainda dá para ler
        do .txt o valor que o caixa do dia vai perder.

        Fica no mesmo domínio da edição, e não num separado, porque para quem
        confere o caixa as duas são a mesma pergunta — "o que mexeram aqui
        depois de eu ter fechado?". Devolve False quando a comanda não tinha
        baixa (o caso normal da Consulta, que nem oferece a lixeira para
        comanda fechada)."""
        arquivo = os.path.basename(arquivo or "")
        if not arquivo or not baixaComandas.esta_fechada(arquivo):
            return False

        codigo, cliente, valor_antes = self._instantaneo_da_comanda(arquivo)
        return self._registrar_alteracao_caixa(
            arquivo,
            edicoesCaixa.ACAO_EXCLUIDA,
            usuario,
            codigo,
            cliente,
            valor_antes,
            0.0,
        )

    def _registrar_alteracao_caixa(self, arquivo, acao, usuario, codigo, cliente,
                                   valor_antes, valor_depois, no_caixa=False,
                                   arquivo_novo=""):
        """Grava e anuncia à malha — o que edição e exclusão têm em comum.

        O registro inteiro viaja no gossip (e não só o id, como faz
        _EVENTO_FECHAMENTO_ATUALIZADO): a outra máquina não tem como
        reconstruir sozinha nem o valor de antes (o .txt já não existe mais lá
        nem aqui) nem quem autorizou."""
        data_iso = self._data_iso_da_comanda(arquivo)
        if not data_iso:
            return False

        data_hora = datetime.now().strftime("%d/%m/%Y %H:%M:%S")
        id_evento = edicoesCaixa.registrar(
            data_iso,
            acao,
            usuario or "",
            data_hora,
            codigo=codigo,
            cliente=cliente,
            valor_antes=valor_antes,
            valor_depois=valor_depois,
            no_caixa=no_caixa,
            arquivo=arquivo,
            arquivo_novo=arquivo_novo,
        )

        registro = edicoesCaixa.obter(id_evento)
        if registro:
            rede.publicarEvento(_EVENTO_EDICAO_CAIXA, registro)
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

    @staticmethod
    def _linha_pontilhada(rotulo, valor, campo):
        """"FGTS.................... R$ 8,00" ocupando a linha inteira, com o
        valor encostado na margem direita e pontos preenchendo o meio.

        Os pontos são contados sobre o TEXTO PURO, e o estilo é aplicado só
        depois: os bytes de controle ESC/POS são invisíveis no papel mas
        contariam como largura aqui, e a coluna sairia torta — mesmo cuidado
        já documentado em comandaTextoService.formatar_tabela.

        Rótulo comprido demais para a linha ainda sai inteiro, com um ponto
        só de separação: cortar o nome da verba seria pior do que quebrar o
        alinhamento de uma linha."""
        pontos = max(1, _COLUNAS_PAPEL - len(rotulo) - len(valor) - 1)
        return estilo.formatar_campo(f"{rotulo}{'.' * pontos} {valor}", campo)

    @staticmethod
    def _hora_e_data(data_hora):
        """("23:26", "01/06/2026") a partir do "dd/mm/aaaa HH:MM:SS" gravado
        no lançamento (ver registrarExtraDiaria). Um registro com formato
        inesperado — gravado por uma versão futura, ou editado à mão — devolve
        o texto todo como data e hora vazia, em vez de derrubar a impressão do
        recibo por causa de um split."""
        partes = str(data_hora or "").split()
        if len(partes) < 2:
            return "", str(data_hora or "")
        return partes[1][:5], partes[0]

    def _montar_recibo_extra(self, registro):
        """Monta o recibo de pagamento de diária em bytes ESC/POS, pronto pra
        impressora, no formato de quitação que o funcionário assina:

            RECIBO DE PAGAMENTO
            FUNCIONÁRIO EXTRA
            23:26                         01/06/2026
            ----------------------------------------
            RECEBI DE Grande Sabor
            A QUANTIA DE R$ 100,00
            SENDO
            FGTS............................ R$ 8,00
            ...
            TOTAL A RECEBER............... R$ 100,00
            DANDO TOTAL QUITAÇÃO A EMPRESA,
            ...
            Maria Souza
            ______________________________
            (assinatura)

        O valor é discriminado nas verbas de _DISCRIMINACAO_DIARIA — ver a
        observação sobre a soma lá, que vale para todo recibo impresso aqui.

        Mesmo caminho de _montar_recibo_fechamento e das comandas de venda: um
        renderizador por campo (cada um já passado por estilo.formatar_campo) e
        a montagem final por comandaTextoService.montar_linhas_por_ordem, que
        decide ordem e divisórias a partir da tela de Configurações. Como a
        ordem é a mesma lista global (estilo.ordem_secoes()), as chaves dos
        outros dois papéis não aparecem em `renderizadores` e são puladas.

        "extra_discriminacao" é um bloco de várias linhas, âncora de posição
        igual a "fech_por_origem": ele se move inteiro, e o estilo é por
        sub-linha."""

        def fmt(numero):
            return f"R$ {numero:.2f}".replace(".", ",")

        valor = float(registro.get("valor", 0) or 0)
        nome = registro.get("funcionario", "")
        hora, data = self._hora_e_data(registro.get("dataHora", ""))

        # Hora à esquerda, data à direita, na mesma linha. Pelo menos um
        # espaço entre as duas mesmo se a linha estourar a largura, para elas
        # nunca saírem grudadas uma na outra.
        espacos = max(1, _COLUNAS_PAPEL - len(hora) - len(data))
        linha_hora_data = estilo.formatar_campo(f"{hora}{' ' * espacos}{data}", "extra_hora_data")

        linhas_discriminacao = [estilo.formatar_campo("SENDO", "extra_discriminacao_item")]
        for rotulo, aliquota in _DISCRIMINACAO_DIARIA:
            linhas_discriminacao.append(
                self._linha_pontilhada(rotulo, fmt(valor * aliquota), "extra_discriminacao_item")
            )
        # O total é o valor LANÇADO, não a soma das linhas acima — ver
        # _DISCRIMINACAO_DIARIA. O recibo quita o que o funcionário recebeu na
        # mão, e é esse número que precisa bater com o caixa do dia.
        linhas_discriminacao.append(
            self._linha_pontilhada("TOTAL A RECEBER", fmt(valor), "extra_discriminacao_total")
        )

        renderizadores = {
            "extra_titulo": [estilo.formatar_campo("RECIBO DE PAGAMENTO", "extra_titulo")],
            "extra_subtitulo": [estilo.formatar_campo("FUNCIONÁRIO EXTRA", "extra_subtitulo")],
            "extra_hora_data": [linha_hora_data],
            "extra_recebi": [f"RECEBI DE {estilo.formatar_campo(_NOME_EMPRESA, 'extra_recebi')}"],
            "extra_valor": [f"A QUANTIA DE {estilo.formatar_campo(fmt(valor), 'extra_valor')}"],
            "extra_discriminacao": linhas_discriminacao,
            "extra_quitacao": [
                estilo.formatar_campo(linha, "extra_quitacao")
                for linha in (
                    "DANDO TOTAL QUITAÇÃO A EMPRESA,",
                    "SOBRE OS VALORES ACIMA",
                    "DISCRIMINADOS",
                    "DO MAIS NADA A RECLAMAR",
                )
            ],
            # O nome sai sozinho, sem rótulo, logo acima da linha de
            # assinatura: é o nome de quem assina, e não um campo de
            # cabeçalho — daí ele e o bloco de assinatura ficarem na mesma
            # categoria, sem divisória entre os dois (ver CATEGORIA_CAMPO).
            "extra_assina_nome": [estilo.formatar_campo(nome, "extra_assina_nome")],
            # As duas linhas em branco são do próprio bloco (espaço pra
            # assinar), não espaçamento entre seções — por isso continuam
            # literais aqui em vez de virarem linhas_espacamento_secoes().
            "extra_assinatura": ["", "", estilo.formatar_campo("_" * 30, "extra_assinatura"), "(assinatura)"],
        }

        linhas = texto.montar_linhas_por_ordem(estilo.ordem_secoes(), renderizadores)
        conteudo = "\n".join(linhas) + "\n"
        return conteudo.encode(parser.CODEPAGE_IMPRESSORA, errors="replace")


    # ---------- Despesas do dia ----------
    # Espelham os três slots de extras acima. Estão separados, e não
    # parametrizados por um "tipo", pelo motivo documentado no topo de
    # services/rede/despesasCaixa.py.

    @pyqtSlot(str, str, str, result="QVariantMap")
    @protegido({})
    def registrarDespesa(self, data_iso, nome, valor_texto):
        """Lança uma despesa no dia `data_iso` e devolve o registro gravado
        (com "id"), ou {} se o nome vier vazio ou o valor não for
        positivo."""
        nome = (nome or "").strip()
        valor = texto.valor_para_float(valor_texto)
        if not nome or valor <= 0:
            return {}

        agora = datetime.now()
        data_hora = agora.strftime("%d/%m/%Y %H:%M:%S")
        id_evento = despesasCaixa.registrar(data_iso, nome, valor, data_hora)

        rede.publicarEvento(_EVENTO_DESPESA_LANCADA, {
            "id": id_evento,
            "dataIso": data_iso,
            "nome": nome,
            "valor": valor,
            "dataHora": data_hora,
            "idEventoRevisao": id_evento,
        })

        # calcularFechamento (e não _recalcular_e_cachear): a mudança nasceu
        # aqui, então a malha inteira precisa saber que este dia mudou —
        # mesma assimetria de registrarExtraDiaria.
        self.calcularFechamento(data_iso)
        self.despesasAtualizadas.emit()

        return {
            "id": id_evento,
            "dataIso": data_iso,
            "nome": nome,
            "valor": valor,
            "dataHora": data_hora,
        }

    @pyqtSlot(str, str, str, result="QVariantMap")
    @protegido({})
    def editarDespesa(self, id_evento, nome, valor_texto):
        """Corrige nome/valor de uma despesa já lançada — mesmo id, mesma
        dataHora original."""
        nome = (nome or "").strip()
        valor = texto.valor_para_float(valor_texto)
        if not nome or valor <= 0:
            return {}

        registro = despesasCaixa.carregar().get(id_evento)
        if registro is None:
            return {}

        id_revisao = despesasCaixa.editar(id_evento, nome, valor)
        if id_revisao is None:
            return {}

        data_iso = registro.get("dataIso", "")
        rede.publicarEvento(_EVENTO_DESPESA_LANCADA, {
            "id": id_evento,
            "dataIso": data_iso,
            "nome": nome,
            "valor": valor,
            "dataHora": registro.get("dataHora", ""),
            "idEventoRevisao": id_revisao,
        })

        if data_iso:
            self.calcularFechamento(data_iso)
        self.despesasAtualizadas.emit()

        return {
            "id": id_evento,
            "dataIso": data_iso,
            "nome": nome,
            "valor": valor,
            "dataHora": registro.get("dataHora", ""),
        }

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def excluirDespesa(self, id_evento):
        registro = despesasCaixa.carregar().get(id_evento)
        if registro is None:
            return False

        data_iso = registro.get("dataIso", "")
        quando = despesasCaixa.apagar(id_evento)
        rede.publicarEvento(_EVENTO_DESPESA_APAGADA, {"id": id_evento, "quando": quando})

        if data_iso:
            self.calcularFechamento(data_iso)
        self.despesasAtualizadas.emit()
        return True
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
