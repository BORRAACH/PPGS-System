"""Contagem manual de caixa por forma de pagamento (Cartão, Dinheiro, Pix),
usada para calcular o "Lucro" da tela de Fechamento (ver
controllers/fechamentoController.py e
qml/pages/fechamento/Fechamento.qml). Diferente de extrasCaixa.py (que só
cresce), aqui há UM registro por dia, sobrescrito a cada edição — o dono
pode refazer a contagem quantas vezes precisar até fechar o caixa.

Guardado em pedidos/.sync/contagem.json (mesmo endereço de baixas.json/
extras.json — ver services/rede/caminhos.py):
`{dataIso: {"cartao", "dinheiro", "pix", "idEvento"}}`. idEvento
(services/rede/relogio.py) resolve o conflito de duas máquinas editando o
mesmo dia quase ao mesmo tempo — o mais novo (relogio.mais_novo) vence,
mesmo desenho de services/cardapioService.py."""

import os

from services.rede import caminhos, relogio

_ROTULO = "contagemCaixa"


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "contagem.json")


def carregar():
    """`{dataIso: {cartao, dinheiro, pix, idEvento}}` de todos os dias já
    contados nesta máquina."""
    return caminhos.carregar_json(_caminho_arquivo(), _ROTULO)


def _salvar(dados):
    caminhos.salvar_json(_caminho_arquivo(), dados, _ROTULO)


def obter_dia(data_iso):
    """O registro de `data_iso`, ou None se o dia nunca foi contado."""
    return carregar().get(data_iso)


def registrar(data_iso, cartao, dinheiro, pix, quando=None):
    """Grava (sobrescrevendo) a contagem de `data_iso` e devolve o id da
    gravação. `quando` só vem preenchido quando o valor é aprendido de
    outra máquina (ver aplicar_remoto) — preservar o id de origem é o que
    faz as duas concordarem sobre a MESMA gravação."""
    dados = carregar()
    id_evento = quando or relogio.novo_id()
    dados[data_iso] = {
        "cartao": cartao,
        "dinheiro": dinheiro,
        "pix": pix,
        "idEvento": id_evento,
    }
    _salvar(dados)
    return id_evento


def aplicar_remoto(data_iso, cartao, dinheiro, pix, id_recebido):
    """Sobrescreve a contagem de `data_iso` só se `id_recebido` for
    estritamente mais novo que a versão já conhecida aqui — mesmo cuidado
    de cardapioService._ao_receber_cardapio_remoto, pra duas máquinas
    contando o caixa quase ao mesmo tempo não desfazerem uma a da outra.
    Devolve True só se aplicou de fato."""
    existente = obter_dia(data_iso)
    if id_recebido:
        relogio.observar(id_recebido)
    if existente and (not id_recebido or not relogio.mais_novo(id_recebido, existente.get("idEvento", ""))):
        return False

    registrar(data_iso, cartao, dinheiro, pix, quando=id_recebido or relogio.novo_id())
    return True
