import json
import os
import uuid
from collections import Counter
from datetime import datetime

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services import comandaEstiloService as estilo
from services import comandaSequencialService as sequencial
from services import comandaTextoService as texto
from services.rede import relogio, rede, tombstones

# Tipo de evento de gossip (ver services/rede/eventos.py:BarramentoEventos)
# usado pra sincronizar mesas abertas entre as máquinas da malha — mesmo
# mecanismo genérico que CardapioController usa para "cardapio_alterado",
# só que aqui o payload é o dict da mesa direto (sem envelope base64: ao
# contrário de um arquivo de cardápio, não precisamos preservar bytes
# exatos, o dict já é serializável em JSON puro).
_EVENTO_MESA_ATUALIZADA = "mesa_atualizada"
_EVENTO_MESA_FECHADA = "mesa_fechada"

# Marca impressa no topo da comanda de produção (a via que vai pro
# pizzaiolo, ver imprimirComandaCozinha) — em negrito direto, e não como um
# "campo" configurável em EstiloImpressora.qml, pelo mesmo motivo da marca de
# comanda de teste em balcaoController: é um aviso fixo pra quem tira o papel
# da impressora saber que aquilo não é o cupom do cliente.
_MARCA_COMANDA_COZINHA = f"{estilo.NEGRITO_LIGA}*** COMANDA COZINHA ***{estilo.NEGRITO_DESLIGA}"


def _valor_total_itens(itens):
    return sum(texto.valor_para_float(item.get("valor", "")) for item in itens)


def _itens_reais(itens):
    """Só os itens de verdade da mesa. O formulário do Salão sempre tem ao
    menos uma linha (em branco enquanto ninguém escolheu nada) e ela é salva
    junto com as outras — contá-la como item faria a comanda do pizzaiolo sair
    com uma linha vazia, ou até sair sozinha numa mesa ainda sem nada."""
    return [item for item in (itens or []) if (item.get("pedido") or "").strip()]


def _chave_item(item):
    """Identidade de um item para efeito de "já foi pra cozinha ou não".

    Duas pizzas iguais pedidas na mesma mesa têm a MESMA chave de propósito —
    a comparação de itens pendentes é feita por multiconjunto (ver
    _itens_pendentes_cozinha), então a segunda continua sendo uma pendência
    própria. Serializado com sort_keys pra a ordem das chaves do dict (que
    varia entre o que veio da QML e o que foi relido do JSON) não fazer dois
    itens idênticos parecerem diferentes."""
    return json.dumps(
        {
            "pedido": item.get("pedido", ""),
            "observacao": item.get("observacao", ""),
            "valor": item.get("valor", ""),
            "borda": item.get("borda") or None,
            "adicionais": item.get("adicionais") or [],
        },
        sort_keys=True,
        ensure_ascii=False,
        default=str,
    )


def _itens_pendentes_cozinha(mesa):
    """Itens da mesa que ainda não foram impressos para o pizzaiolo.

    Uma comanda de mesa é incrementada várias vezes ao longo da visita, e a
    cada lançamento o formulário devolve a lista INTEIRA de itens. Reimprimir
    tudo faria o pizzaiolo produzir de novo o que já saiu — daí a comparação
    com o que já foi impresso (gravado em "itensImpressosCozinha" pela
    própria impressão), como multiconjunto: três refrigerantes iguais já
    impressos abatem exatamente três dos que estão na mesa agora, e o quarto
    continua pendente."""
    restantes = Counter(_chave_item(item) for item in _itens_reais(mesa.get("itensImpressosCozinha")))

    pendentes = []
    for item in _itens_reais(mesa.get("itens")):
        chave = _chave_item(item)
        if restantes.get(chave):
            restantes[chave] -= 1
            continue
        pendentes.append(item)
    return pendentes


def _item_sem_precos(item):
    """Cópia do item com os preços de borda e adicionais zerados.

    O valor do item em si não precisa de tratamento (_linhas_itens_producao
    ignora a coluna de valor), mas os de borda/adicional vêm embutidos NO
    TEXTO montado por comandaTextoService ("* CATUPIRY (R$ 8,00)") — o único
    jeito de tirá-los é não mandar o preço pra lá."""
    borda = item.get("borda")
    adicionais = item.get("adicionais") or []
    return {
        "pedido": item.get("pedido", ""),
        "observacao": item.get("observacao", ""),
        "valor": "",
        "borda": {**borda, "valor": ""} if isinstance(borda, dict) else borda,
        "adicionais": [{**a, "valor": ""} if isinstance(a, dict) else a for a in adicionais],
    }


def _linhas_itens_producao(grupos):
    """Tabela de itens da comanda do pizzaiolo — mesma montagem de grupos de
    comandaTextoService (pizza meio a meio vira uma linha por sabor, com os
    adicionais de cada fração logo abaixo, e borda/observação ao final do
    grupo), só que sem a coluna de valor.

    Não dá pra usar texto.formatar_tabela() aqui: ela sempre escreve
    "pedido | valor", e passar os itens com valor vazio deixaria um "|" solto
    no fim de cada linha do papel."""
    linhas = []
    for indice, grupo in enumerate(grupos):
        if indice > 0:
            linhas.append("")

        for coluna_pedido, _valor, extras in grupo["linhas"]:
            linhas.append(estilo.formatar_campo(coluna_pedido, "pedido"))
            for extra in extras:
                linhas.append(f"  {estilo.formatar_campo(extra, 'adicional_item')}")

        if grupo["borda"]:
            linhas.append(f"  {estilo.formatar_campo(grupo['borda'], 'borda_item')}")
        if grupo["observacao"]:
            linhas.append(f"  {estilo.formatar_campo(grupo['observacao'], 'observacao_item')}")

    return linhas


class SalaoController(QObject):
    """Gerencia comandas de mesa (Salao.qml): diferente de Balcão/Entrega,
    uma comanda de mesa fica "aberta" — salva e sincronizada pela rede local
    (ver services/rede/eventos.py), incrementada várias vezes ao longo da
    visita do cliente — e só vira um cupom impresso de verdade quando a
    conta é fechada (fecharMesa), com a divisão entre as pessoas embutida
    no próprio cupom.

    Mesas abertas vivem em pedidos/mesas/*.json (uma subpasta — invisível
    ao scan não-recursivo e só-.txt de ConsultaController.listarComandas(),
    então não aparecem lá enquanto abertas). O cupom final de uma mesa
    fechada é salvo como pedidos/mesa_<algo>.txt, igual a qualquer outra
    comanda (aparece normalmente na Consulta)."""

    mesasAtualizadas = pyqtSignal()

    def __init__(self):
        super().__init__()
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.pasta_pedidos = os.path.join(base_dir, "pedidos")
        self.pasta_mesas = os.path.join(self.pasta_pedidos, "mesas")
        os.makedirs(self.pasta_mesas, exist_ok=True)

        # Só conta peers pra decidir quando um peer NOVO entrou (ver
        # _ao_peers_mudarem) — peersMudaram(int) dispara tanto em entradas
        # quanto em saídas, e só a entrada de alguém precisa de catch-up.
        self._ultima_quantidade_peers = 0

        rede.registrarEvento(_EVENTO_MESA_ATUALIZADA, self._ao_receber_mesa_remota)
        rede.registrarEvento(_EVENTO_MESA_FECHADA, self._ao_receber_mesa_fechada_remota)
        rede.peersMudaram.connect(self._ao_peers_mudarem)
        rede.registrarDominioSincronizado(
            "mesas",
            self._resumo_mesas,
            self._obter_mesa_reconciliacao,
            self._aplicar_mesa_reconciliacao,
            self._apagar_mesa_reconciliacao,
        )

    # ---------- Anti-entropy (ver services/rede/redeService.py:registrarDominioSincronizado) ----------

    def _resumo_mesas(self):
        # "idEvento" já é o critério de desempate usado por
        # _ao_receber_mesa_remota (ver services/rede/relogio.py) —
        # reaproveitado aqui como a "versão" de cada mesa, sem precisar de
        # nenhum hash de conteúdo.
        itens = {mesa["id"]: mesa.get("idEvento", "") for mesa in self._listar_mesas_locais() if mesa.get("id")}
        return {"itens": itens, "apagados": tombstones.carregar("mesas")}

    def _obter_mesa_reconciliacao(self, mesa_id):
        return self._ler_mesa_arquivo(self._caminho_mesa(mesa_id))

    def _aplicar_mesa_reconciliacao(self, mesa_id, payload):
        self._ao_receber_mesa_remota(payload)

    def _apagar_mesa_reconciliacao(self, mesa_id):
        self._ao_receber_mesa_fechada_remota({"id": mesa_id})

    # ---------- Arquivos locais ----------

    def _caminho_mesa(self, mesa_id):
        return os.path.join(self.pasta_mesas, f"mesa_{mesa_id}.json")

    def _ler_mesa_arquivo(self, caminho):
        try:
            with open(caminho, "r", encoding="utf-8") as arquivo:
                return json.load(arquivo)
        except (OSError, json.JSONDecodeError) as erro:
            print(f"[salaoController] Falha ao ler {caminho}: {erro}")
            return None

    def _gravar_mesa_arquivo(self, mesa):
        caminho = self._caminho_mesa(mesa["id"])
        try:
            with open(caminho, "w", encoding="utf-8") as arquivo:
                json.dump(mesa, arquivo, indent=2, ensure_ascii=False)
        except OSError as erro:
            print(f"[salaoController] Falha ao gravar {caminho}: {erro}")
            return False
        return True

    def _listar_mesas_locais(self):
        """Todas as mesas abertas gravadas localmente, como dicts completos
        (não só o resumo de listarMesasAbertas) — usado tanto por
        listarMesasAbertas quanto pelo catch-up em _ao_peers_mudarem."""
        mesas = []
        for nome_arquivo in os.listdir(self.pasta_mesas):
            if not nome_arquivo.endswith(".json"):
                continue
            mesa = self._ler_mesa_arquivo(os.path.join(self.pasta_mesas, nome_arquivo))
            if mesa:
                mesas.append(mesa)
        return mesas

    # ---------- API para a QML ----------

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarMesasAbertas(self):
        """Resumo de cada mesa aberta (mesa, cliente, total, qtd de itens),
        ordenado pelo número da mesa — usado pela faixa de mesas abertas em
        Salao.qml."""
        resumos = []
        for mesa in self._listar_mesas_locais():
            itens = mesa.get("itens", [])
            resumos.append({
                "id": mesa.get("id", ""),
                "mesa": mesa.get("mesa", 0),
                "cliente": mesa.get("cliente", ""),
                "valorTotal": _valor_total_itens(itens),
                "quantidadeItens": len(itens),
            })
        resumos.sort(key=lambda r: r["mesa"])
        return resumos

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
    def carregarMesa(self, mesa_id):
        mesa = self._ler_mesa_arquivo(self._caminho_mesa(mesa_id))
        return mesa or {}

    @pyqtSlot("QVariantMap", result="QVariantMap")
    @protegido({"erro": "Falha inesperada ao salvar a mesa — ver logs/app.log."})
    def salvarMesa(self, dados):
        """Cria (id vazio) ou atualiza uma mesa aberta. Recusa salvar se OUTRA
        mesa já aberta estiver usando o mesmo número (não faz sentido duas
        mesas físicas abertas com o mesmo número ao mesmo tempo). Devolve o
        dict salvo (com "erro": "") em caso de sucesso, ou só {"erro": "..."}
        em caso de conflito — mesma convenção de cardapioService.salvar."""
        id_original = dados.get("id") or ""
        mesa_id = id_original or uuid.uuid4().hex
        numero_mesa = dados.get("mesa")

        for outra in self._listar_mesas_locais():
            if outra.get("id") != mesa_id and outra.get("mesa") == numero_mesa:
                return {"erro": f"Já existe uma mesa aberta com o número {numero_mesa}."}

        agora = datetime.now().isoformat()
        # Só tenta ler o arquivo existente se já havia um id (mesa sendo
        # atualizada) — numa mesa nova, o arquivo ainda não existe, e
        # tentar ler geraria um log de "falha ao ler" enganoso pra um caso
        # totalmente esperado.
        mesa_existente = self._ler_mesa_arquivo(self._caminho_mesa(mesa_id)) if id_original else None
        mesa_existente = mesa_existente or {}
        mesa = {
            "id": mesa_id,
            "mesa": numero_mesa,
            "cliente": dados.get("cliente", ""),
            "itens": dados.get("itens", []),
            # Preservado do arquivo anterior, igual a "criadaEm": salvar a
            # mesa de novo (mais uma rodada de pedidos) não pode fazer o que
            # já foi pro pizzaiolo virar pendência outra vez (ver
            # _itens_pendentes_cozinha).
            "itensImpressosCozinha": mesa_existente.get("itensImpressosCozinha", []),
            "criadaEm": mesa_existente.get("criadaEm", agora),
            "atualizadaEm": agora,
            # Critério de desempate real entre máquinas (ver
            # _ao_receber_mesa_remota/_resumo_mesas) — atualizadaEm fica só
            # como campo legível pra quem olhar o JSON, não é mais usado
            # pra decidir quem vence (ver services/rede/relogio.py).
            "idEvento": relogio.novo_id(),
        }

        if not self._gravar_mesa_arquivo(mesa):
            return {"erro": "Não foi possível salvar a mesa."}

        rede.publicarEvento(_EVENTO_MESA_ATUALIZADA, mesa)
        resultado = dict(mesa)
        resultado["erro"] = ""
        return resultado

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def apagarMesa(self, mesa_id):
        """Cancela uma mesa aberta sem imprimir nada (mesa aberta por
        engano, por exemplo) — apaga o arquivo local e avisa a rede pra
        ninguém ficar com o card "zumbi" de uma mesa que já não existe
        mais aqui."""
        caminho = self._caminho_mesa(mesa_id)
        try:
            os.remove(caminho)
        except OSError as erro:
            print(f"[salaoController] Falha ao apagar {caminho}: {erro}")
            return False

        tombstones.registrar("mesas", mesa_id)
        rede.publicarEvento(_EVENTO_MESA_FECHADA, {"id": mesa_id})
        return True

    @pyqtSlot(str, result="QVariantList")
    @protegido([])
    def itensPendentesCozinha(self, mesa_id):
        """Itens da mesa que ainda não foram impressos para o pizzaiolo — o
        que Salao.qml mostra no popup depois de lançar o pedido (e o que
        decide se vale a pena abrir o popup: lista vazia = nada novo pra
        produzir, nem pergunta)."""
        mesa = self._ler_mesa_arquivo(self._caminho_mesa(mesa_id))
        if mesa is None:
            return []

        return _itens_pendentes_cozinha(mesa)

    @pyqtSlot(str, result=bool)
    @pyqtSlot(str, int, result=bool)
    @protegido(False)
    def imprimirComandaCozinha(self, mesa_id, copias=1):
        """Imprime a via de produção (a que vai pro pizzaiolo) com os itens
        ainda não impressos desta mesa, e marca todos os itens atuais como já
        impressos.

        Ao contrário do cupom final de fecharMesa, esta comanda NÃO é gravada
        em pedidos/ nem propagada como pedido pela malha: não é um documento
        de venda (não tem valores, não deve aparecer na Consulta), é só papel
        pra cozinha. O que É propagado é a mesa atualizada, pra outra máquina
        da malha não oferecer de novo a impressão dos mesmos itens.

        A marcação acontece mesmo que a impressão falhe depois — igual a
        fecharMesa, o resultado da impressão é assíncrono (chega por
        rede.impressaoResultado) e não dá pra esperar por ele aqui. Numa falha
        de impressora, o caminho é reimprimir pela Consulta/impressora, não
        salvar a mesa de novo."""
        mesa = self._ler_mesa_arquivo(self._caminho_mesa(mesa_id))
        if mesa is None:
            return False

        pendentes = _itens_pendentes_cozinha(mesa)
        if not pendentes:
            return False

        conteudo_bytes = self._montarComandaCozinha(mesa, pendentes)

        mesa["itensImpressosCozinha"] = _itens_reais(mesa.get("itens"))
        mesa["atualizadaEm"] = datetime.now().isoformat()
        mesa["idEvento"] = relogio.novo_id()
        if self._gravar_mesa_arquivo(mesa):
            rede.publicarEvento(_EVENTO_MESA_ATUALIZADA, mesa)

        for _ in range(max(1, copias)):
            rede.solicitar_impressao(conteudo_bytes)

        return True

    def _montarComandaCozinha(self, mesa, itens):
        """Via de produção: mesa, cliente, hora e os itens — sem valor
        nenhum, nem por item nem total. Quem está no forno precisa saber o
        que fazer, e preço só polui (e faria o papel ser confundido com o
        cupom do cliente).

        Layout fixo, sem passar por comandaEstiloService.ordem_secoes(): a
        ordem configurável em Configurações descreve a comanda de VENDA (tem
        forma de pagamento, troco, total...), campos que não existem aqui. O
        estilo por campo (negrito/tamanho de pedido, borda, adicional) é
        respeitado normalmente, esse sim se aplica igual."""
        agora = datetime.now()
        grupos = texto.montar_grupos([_item_sem_precos(item) for item in itens])

        linhas = [_MARCA_COMANDA_COZINHA]
        linhas.extend(estilo.linhas_espacamento_secoes())
        linhas.append(f"Mesa: {estilo.formatar_campo(str(mesa.get('mesa', '')), 'mesa')}")

        cliente = (mesa.get("cliente") or "").strip()
        if cliente:
            linhas.append(f"Cliente: {estilo.formatar_campo(cliente, 'cliente')}")

        linhas.append(f"Data: {estilo.formatar_campo(agora.strftime('%d/%m/%Y %H:%M:%S'), 'data')}")
        linhas.extend(estilo.linhas_espacamento_secoes())
        linhas.append(texto.MARCADOR_ITENS)
        linhas.extend(estilo.linhas_espacamento_secoes())
        linhas.extend(_linhas_itens_producao(grupos))
        linhas.extend(estilo.linhas_espacamento_secoes())
        linhas.append(texto.MARCADOR_ITENS)

        conteudo = "\n".join(linhas) + "\n"
        return conteudo.encode(texto.CODEPAGE_IMPRESSORA, errors="replace")

    @pyqtSlot(str, "QVariantList", result=bool)
    @pyqtSlot(str, "QVariantList", int, result=bool)
    @protegido(False)
    def fecharMesa(self, mesa_id, divisoes, copias=1):
        """Fecha a conta: monta o cupom final (itens + divisão da conta já
        resolvida — cada item de `divisoes` já vem com nome/valor/forma de
        pagamento/status prontos, o rateio "igual" já foi calculado do lado
        da QML), salva e propaga como uma comanda normal (igual a
        BalcaoController.enviarPedido), apaga a mesa aberta e avisa a rede
        que ela fechou, e só então pede a impressão.

        A ordem importa: fechar a mesa (apagar o .json aberto + avisar a
        malha) não pode depender do resultado da impressão — rede.
        solicitar_impressao já pede a impressão de forma assíncrona (roda
        numa thread, o resultado chega depois por rede.impressaoResultado),
        mas mesmo assim a mesa é sempre considerada fechada assim que o
        cupom final é salvo, nunca só depois de tentar imprimir. Sem essa
        garantia, uma falha ao imprimir deixaria a mesa "presa" aberta em
        Salao.qml mesmo com o cupom final já salvo e visível na Consulta."""
        mesa = self._ler_mesa_arquivo(self._caminho_mesa(mesa_id))
        if mesa is None:
            return False

        conteudo_bytes = self._montarCupomFinal(mesa, divisoes)

        agora = datetime.now()
        nome_arquivo = f"mesa_{agora.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}.txt"
        caminho_arquivo = os.path.join(self.pasta_pedidos, nome_arquivo)
        try:
            with open(caminho_arquivo, "wb") as arquivo:
                arquivo.write(conteudo_bytes)
        except OSError as erro:
            print(f"[salaoController] Falha ao salvar o cupom final em {caminho_arquivo}: {erro}")
            return False

        rede.transmitir_pedido(nome_arquivo, conteudo_bytes)

        try:
            os.remove(self._caminho_mesa(mesa_id))
        except OSError:
            pass
        tombstones.registrar("mesas", mesa_id)
        rede.publicarEvento(_EVENTO_MESA_FECHADA, {"id": mesa_id})

        for _ in range(max(1, copias)):
            rede.solicitar_impressao(conteudo_bytes)

        return True

    def _montarCupomFinal(self, mesa, divisoes):
        itens = mesa.get("itens", [])
        grupos = texto.montar_grupos(itens)
        valor_total = _valor_total_itens(itens)
        agora = datetime.now()

        codigo_pedido = sequencial.gerar_codigo_pedido(agora)
        valor_total_formatado = f"R$ {valor_total:.2f}".replace(".", ",")

        divisao_linhas = None
        if divisoes:
            divisao_linhas = ["DIVISÃO DA CONTA"]
            for divisao in divisoes:
                nome = estilo.formatar_campo(divisao.get("nome", ""), "cliente")
                valor = divisao.get("valor", "")
                forma = divisao.get("formaPagamento", "")
                status = estilo.formatar_campo(divisao.get("status", "NP"), "status")
                divisao_linhas.append(f"{nome}: {valor} [{forma}] [{status}]")

        renderizadores = {
            "id_pedido": [f"ID: {estilo.formatar_campo(codigo_pedido, 'id_pedido')}"],
            "mesa": [f"Mesa: {estilo.formatar_campo(str(mesa.get('mesa', '')), 'mesa')}"],
            "cliente": [f"Cliente: {estilo.formatar_campo(mesa.get('cliente', ''), 'cliente')}"],
            "data": [f"Data: {estilo.formatar_campo(agora.strftime('%d/%m/%Y %H:%M:%S'), 'data')}"],
            "itens": texto.formatar_tabela(grupos),
            "valor_total": [f"Valor do pedido: {estilo.formatar_campo(valor_total_formatado, 'valor_total')}"],
            "divisao_conta": divisao_linhas,
        }
        linhas_arquivo = texto.montar_linhas_por_ordem(estilo.ordem_secoes(), renderizadores)

        conteudo = "\n".join(linhas_arquivo) + "\n"
        return conteudo.encode(texto.CODEPAGE_IMPRESSORA, errors="replace")

    # ---------- Rede (gossip) ----------

    def _ao_receber_mesa_remota(self, payload):
        """Grava localmente uma mesa criada/atualizada em outra máquina —
        só se for mais nova que a que já temos (comparação por idEvento,
        ver services/rede/relogio.py — a linha do tempo comum da malha),
        pra um reenvio de catch-up atrasado (ver _ao_peers_mudarem) não
        desfazer uma edição mais recente feita nesta própria máquina
        enquanto isso.

        Também recusa reabrir uma mesa que esta máquina já sabe que foi
        fechada (tombstone local) — sem essa checagem, um peer com uma
        cópia desatualizada da mesa (estava offline quando ela fechou)
        conseguia "ressuscitá-la" aqui, tanto via gossip quanto via
        reconciliação periódica (ver services/rede/tombstones.py).

        Chamada tanto pelo gossip (mesa_atualizada) quanto pela
        reconciliação (_aplicar_mesa_reconciliacao) — por isso o
        relogio.observar() aqui cobre os dois caminhos de uma vez."""
        mesa = payload or {}
        mesa_id = mesa.get("id")
        if not mesa_id or mesa_id in tombstones.carregar("mesas"):
            return

        relogio.observar(mesa.get("idEvento"))

        existente = self._ler_mesa_arquivo(self._caminho_mesa(mesa_id))
        if existente and not relogio.mais_novo(mesa.get("idEvento", ""), existente.get("idEvento", "")):
            return

        if self._gravar_mesa_arquivo(mesa):
            self.mesasAtualizadas.emit()

    def _ao_receber_mesa_fechada_remota(self, payload):
        mesa_id = (payload or {}).get("id", "")
        if not mesa_id:
            return

        try:
            os.remove(self._caminho_mesa(mesa_id))
        except OSError:
            pass
        # Todo nó que APRENDE do fechamento precisa lembrar dele, não só
        # quem fechou originalmente — mesmo motivo documentado em
        # ConsultaController.removerPedidoRemoto.
        tombstones.registrar("mesas", mesa_id)
        self.mesasAtualizadas.emit()

    def _ao_peers_mudarem(self, quantidade):
        """Quando um peer NOVO entra na malha (quantidade aumentou, não só
        mudou), republica todas as mesas abertas conhecidas localmente —
        pega carona no próprio fan-out do gossip (BarramentoEventos manda
        pra todo mundo conectado agora) pra o peer recém-chegado ficar
        sabendo do estado atual, sem precisar de nenhum protocolo de
        catch-up novo em RedeService."""
        aumentou = quantidade > self._ultima_quantidade_peers
        self._ultima_quantidade_peers = quantidade
        if not aumentou:
            return

        for mesa in self._listar_mesas_locais():
            rede.publicarEvento(_EVENTO_MESA_ATUALIZADA, mesa)
