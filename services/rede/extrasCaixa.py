"""Registro persistido dos pagamentos de diária a funcionários — dinheiro que
sai do caixa fora de qualquer venda (ver controllers/fechamentoController.py).

O CONJUNTO de lançamentos só cresce (não existe "apagar" — um lançamento
errado por engano não é o escopo desta tela). Mas, diferente de
baixaComandas.py, o CONTEÚDO de um lançamento (nome/valor) pode ser
corrigido depois — é o que "editar" faz aqui. Cada lançamento carrega dois
ids de services/rede/relogio.py:

- a própria chave do dict ("idEvento") — a identidade do lançamento na
  malha, atribuída na criação e IMUTÁVEL para sempre (mesmo depois de
  editado, continua sendo "o mesmo lançamento").
- "idEventoRevisao" — qual versão do conteúdo (nome/valor) é a mais
  recente. Criado igual ao idEvento; toda edição gera um novo. É o que
  resolve o conflito de duas máquinas editando o mesmo lançamento quase ao
  mesmo tempo (relogio.mais_novo vence — mesmo desenho de
  services/cardapioService.py), sem depender da ordem de chegada dos
  eventos de gossip/reconciliação.

Guardado em pedidos/.sync/extras.json (mesmo endereço de baixas.json/
eventos.json — ver services/rede/caminhos.py):
`{idEvento: {"dataIso", "funcionario", "valor", "dataHora", "idEventoRevisao"}}`."""

import os

from services.rede import caminhos, relogio, tombstones

_ROTULO = "extrasCaixa"


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "extras.json")


def carregar():
    """`{idEvento: {dataIso, funcionario, valor, dataHora}}` de todos os
    pagamentos de diária conhecidos por esta máquina (os que ela mesma
    lançou e os que aprendeu de outras)."""
    return caminhos.carregar_json(_caminho_arquivo(), _ROTULO)


def _salvar(dados):
    caminhos.salvar_json(_caminho_arquivo(), dados, _ROTULO)


def listar_do_dia(data_iso):
    """Lançamentos de `data_iso` ("AAAA-MM-DD"), na ordem em que foram
    registrados (o id de relogio.py embute o instante de criação, então
    ordenar por ele equivale a ordenar cronologicamente)."""
    dados = carregar()
    itens = [
        dict(registro, id=id_evento)
        for id_evento, registro in dados.items()
        if registro.get("dataIso") == data_iso
    ]
    itens.sort(key=lambda item: item["id"])
    return itens


def registrar(data_iso, funcionario, valor, data_hora, quando=None):
    """Grava um novo pagamento de diária e devolve o id do lançamento.

    `quando` vem preenchido quando o lançamento foi aprendido de outra
    máquina (gossip ou reconciliação): preservar o id de origem é o que faz
    todas as máquinas concordarem sobre o MESMO lançamento — mesmo cuidado
    de baixaComandas.registrar. Gerar um id local aqui faria cada máquina
    anunciar um valor diferente para o mesmo pagamento.

    Idempotente: um id que já existe não é regravado, senão uma reentrega de
    gossip duplicaria a linha (e o desconto no caixa) no lançamento."""
    dados = carregar()
    id_evento = quando or relogio.novo_id()
    if id_evento in dados:
        return id_evento

    dados[id_evento] = {
        "dataIso": data_iso,
        "funcionario": funcionario,
        "valor": valor,
        "dataHora": data_hora,
        "idEventoRevisao": id_evento,
    }
    _salvar(dados)
    return id_evento


def editar(id_evento, funcionario, valor, quando=None):
    """Corrige nome/valor de um lançamento já existente — mantém o mesmo
    id (a identidade do lançamento) e a mesma dataHora original (a edição
    corrige um erro de digitação, não muda quando o dinheiro foi
    entregue). `quando` só vem preenchido quando a edição é aprendida de
    outra máquina (ver aplicar_edicao_remota); senão gera uma revisão
    nova. Devolve o id da revisão, ou None se o lançamento não existe mais
    (não deveria acontecer — não há como apagar um lançamento)."""
    dados = carregar()
    registro = dados.get(id_evento)
    if registro is None:
        return None

    id_revisao = quando or relogio.novo_id()
    registro["funcionario"] = funcionario
    registro["valor"] = valor
    registro["idEventoRevisao"] = id_revisao
    _salvar(dados)
    return id_revisao


def apagar(id_evento, quando=None):
    """Apaga um lançamento — tombstone genérico de
    services/rede/tombstones.py (domínio "extras"), mesmo padrão de
    ConsultaController.apagarComanda. `quando` só vem preenchido quando a
    exclusão é aprendida de outra máquina (gossip ou reconciliação);
    senão gera um novo.

    Sempre registra o tombstone, mesmo se o id já não existir mais aqui —
    é o que impede a "ressurreição" de um lançamento apagado quando o
    gossip da exclusão chega antes do próprio lançamento (a ordem de
    entrega na malha não é garantida). Devolve o id do tombstone."""
    quando = tombstones.registrar("extras", id_evento, quando)
    dados = carregar()
    if id_evento in dados:
        del dados[id_evento]
        _salvar(dados)
    return quando


def aplicar_edicao_remota(id_evento, funcionario, valor, id_revisao):
    """Aplica uma edição vinda de outra máquina só se `id_revisao` for
    estritamente mais nova que a revisão já conhecida aqui — mesmo cuidado
    de contagemCaixa.aplicar_remoto, pra duas máquinas editando o mesmo
    lançamento quase ao mesmo tempo não desfazerem uma a da outra. Devolve
    True só se aplicou de fato (o lançamento existe aqui E a revisão
    recebida venceu)."""
    dados = carregar()
    registro = dados.get(id_evento)
    if registro is None:
        return False

    if id_revisao:
        relogio.observar(id_revisao)

    versao_local = registro.get("idEventoRevisao", id_evento)
    if not id_revisao or not relogio.mais_novo(id_revisao, versao_local):
        return False

    registro["funcionario"] = funcionario
    registro["valor"] = valor
    registro["idEventoRevisao"] = id_revisao
    _salvar(dados)
    return True
