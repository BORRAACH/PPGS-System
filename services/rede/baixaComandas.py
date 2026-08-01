"""Registro persistido das comandas que já receberam baixa — o que separa
"a comanda existe" de "a comanda está conferida e conta no caixa do dia".

Comanda **aberta** aparece na Consulta como sempre (editável, reimprimível)
mas fica de fora do fechamento de caixa; comanda **fechada** entra na conta
(ver controllers/fechamentoController.py). A baixa é dada pelo popup de
fechamento rápido de Fechamento.qml.

Por que um sidecar, e não um campo no arquivo da comanda: o `.txt` é o cupom
ESC/POS impresso, byte a byte — mexer nele muda o que sai no papel e quebra
os parsers de services/comandaParserService.py. Mesmo raciocínio, e mesmo
endereço (`pedidos/.sync/`, ver services/rede/caminhos.py), de
services/rede/indicePedidos.py.

**Presença = fechada. Ausência = aberta.** Não existe entrada dizendo "esta
está aberta", e é isso que dispensa qualquer migração: toda comanda que já
estava em disco antes deste módulo, e toda comanda que chegar de uma máquina
ainda não atualizada, é lida como aberta — o estado certo, já que ninguém
conferiu nenhuma delas.

O valor guardado é o id de linha do tempo de services/rede/relogio.py, e não
um `True`: de graça ele diz qual máquina deu a baixa (relogio.maquina_do_id)
e em que ordem as baixas aconteceram.

O conjunto só cresce e nunca reverte — não há operação de "reabrir" (a saída
para uma baixa dada por engano é editar a comanda, que gera um arquivo novo,
sem baixa). Isso é o que torna a sincronização entre as máquinas livre de
conflito por construção: duas máquinas que deem baixa na mesma comanda
chegam ao mesmo resultado sem ninguém precisar arbitrar nada, diferente do
domínio "pedidos", onde uma divergência vira conflito manual (ver
ConsultaController._comparar_pedido_reconciliacao)."""

import os

from services.rede import caminhos, relogio, tombstones

_ROTULO = "baixaComandas"


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "baixas.json")


def carregar():
    """`{nome_arquivo: idEvento}` de todas as comandas com baixa, do ponto de
    vista desta máquina (as que ela mesma baixou e as que aprendeu de outras).
    Exposto inteiro porque a Consulta precisa do mapa todo de uma vez, para
    não reler o JSON uma vez por comanda listada."""
    return caminhos.carregar_json(_caminho_arquivo(), _ROTULO)


def _salvar(dados):
    caminhos.salvar_json(_caminho_arquivo(), dados, _ROTULO)


def esta_fechada(nome_arquivo):
    return nome_arquivo in carregar()


def registrar(nome_arquivo, quando=None):
    """Marca a comanda como fechada e devolve o id da baixa.

    `quando` vem preenchido quando a baixa foi aprendida de outra máquina
    (evento de gossip ou reconciliação): preservar o id de origem é o que faz
    todas as máquinas gravarem exatamente a MESMA marca para a mesma baixa —
    mesmo cuidado de tombstones.registrar e indicePedidos.registrar_recebido.
    Gerar um id local aqui faria cada máquina anunciar um valor diferente
    para a mesma baixa, e elas ficariam se pedindo a mesma chave a cada ciclo
    de anti-entropy.

    Idempotente: uma comanda que já tem baixa não é regravada, senão uma
    reentrega de gossip trocaria o id original por outro sem motivo."""
    dados = carregar()
    existente = dados.get(nome_arquivo)
    if existente:
        return existente

    quando = quando or relogio.novo_id()
    dados[nome_arquivo] = quando
    _salvar(dados)
    return quando


def mesclar(recebidos):
    """Aplica um mapa de baixas vindo de um peer. Devolve só as chaves que
    eram novidade aqui — quem chama usa isso para saber quais dias precisam
    ser recalculados."""
    if not recebidos:
        return []

    for quando in recebidos.values():
        relogio.observar(quando)

    dados = carregar()
    novas = [chave for chave in recebidos if chave not in dados]
    if not novas:
        return []

    for chave in novas:
        dados[chave] = recebidos[chave]
    _salvar(dados)
    return novas


def purgar_apagadas():
    """Descarta as baixas de comandas que foram apagadas de propósito — é daí
    que vem todo o crescimento indevido do arquivo, inclusive o do
    apagar-e-recriar em que a edição de uma comanda consiste (ver
    Balcao.qml/Entrega.qml:limparFormularioPedido).

    Deliberadamente NÃO existe uma purga por idade, ao contrário de
    tombstones.purgar_antigos: descartar a baixa de uma comanda de 180 dias
    atrás a devolveria ao estado "aberta" e o caixa daquele dia cairia
    sozinho, em silêncio. O critério é o tombstone porque ele é global e
    propagado pela malha — assim nenhuma máquina purga a baixa de uma comanda
    que ela apenas ainda não recebeu. Chamado uma vez por ciclo de
    reconciliação (ver FechamentoController._resumo_baixas)."""
    dados = carregar()
    if not dados:
        return

    apagadas = tombstones.carregar("pedidos")
    sobrando = [chave for chave in dados if chave in apagadas]
    if not sobrando:
        return

    for chave in sobrando:
        del dados[chave]
    _salvar(dados)
