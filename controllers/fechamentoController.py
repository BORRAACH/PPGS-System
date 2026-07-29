import hashlib
import json
import os
from datetime import datetime, timedelta

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services import comandaParserService as parser
from services.rede import fechamentoCache, rede

# Tipo de evento de gossip (ver services/rede/eventos.py:BarramentoEventos)
# usado pra propagar o resumo de um dia recém-calculado pra malha inteira —
# mesmo mecanismo genérico usado por CardapioController ("cardapio_alterado")
# e SalaoController ("mesa_atualizada").
_EVENTO_FECHAMENTO_ATUALIZADO = "fechamento_atualizado"

# Janela (em dias) que o resumo periódico de anti-entropy compara pra este
# domínio — mesmo raciocínio de _JANELA_RECONCILIACAO_PEDIDOS_DIAS em
# consultaController.py: mantém o resumo comparado a cada ciclo limitado,
# em vez de crescer pra sempre conforme os dias de operação se acumulam.
_JANELA_RECONCILIACAO_FECHAMENTO_DIAS = 30


def _hoje_iso():
    return datetime.now().strftime("%Y-%m-%d")


class FechamentoController(QObject):
    """Fechamento de caixa diário: soma o valor de todas as comandas
    lançadas (Balcão/Entrega/Mesa) num dia, agrupadas por origem, e separa
    comandas suspeitas (sem nome + NP + Pix) pra revisão manual.

    Complexidade pensada pra nunca crescer com o histórico: cada cálculo é
    O(k), k = comandas *daquele dia* (o nome do arquivo já embute a data —
    ver comandaParserService.data_arquivo_aaaammdd — então dias diferentes
    do pedido nunca chegam a ser abertos). Ler um dia já calculado antes é
    O(1) (ver services/rede/fechamentoCache.py, um JSON por dia)."""

    # Emitido quando o resumo de um dia muda (recebido de outra máquina por
    # gossip) — Fechamento.qml usa pra recarregar sozinha se for o dia que
    # está sendo exibido agora.
    fechamentoAtualizado = pyqtSignal(str)

    def __init__(self):
        super().__init__()
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.pasta_pedidos = os.path.join(base_dir, "pedidos")

        rede.registrarEvento(_EVENTO_FECHAMENTO_ATUALIZADO, self._ao_receber_fechamento_remoto)
        rede.registrarDominioSincronizado(
            "fechamento",
            self._resumo_fechamento,
            self._obter_fechamento_reconciliacao,
            self._aplicar_fechamento_reconciliacao,
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

    def _calcular_resumo_dia(self, data_iso):
        total = 0.0
        quantidade = 0
        por_tipo = {}
        suspeitas = []

        for nome_arquivo in self._listar_arquivos_do_dia(data_iso):
            caminho = os.path.join(self.pasta_pedidos, nome_arquivo)
            try:
                with open(caminho, "rb") as arquivo:
                    conteudo_bytes = arquivo.read()
            except OSError as erro:
                print(f"[FechamentoController] Falha ao ler {caminho}: {erro}")
                continue

            conteudo = conteudo_bytes.decode(parser.CODEPAGE_IMPRESSORA, errors="replace")
            conteudo = parser.limpar_codigos_impressora(conteudo)

            tipo = parser.tipo_comanda(nome_arquivo)
            cliente = parser.extrair_campo(parser.PADRAO_CLIENTE, conteudo)
            forma_pagamento = parser.extrair_campo(parser.PADRAO_FORMA_PAGAMENTO, conteudo)
            status = parser.extrair_status_pagamento(conteudo)
            valor = parser.extrair_valor_total(conteudo)

            item = {
                "arquivo": nome_arquivo,
                "cliente": cliente,
                "valor": valor,
                "formaPagamento": forma_pagamento,
                "status": status,
                "dataHora": parser.extrair_campo(parser.PADRAO_DATA, conteudo),
            }

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
