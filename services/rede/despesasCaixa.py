"""Registro persistido das DESPESAS do dia — dinheiro que sai do caixa para
pagar contas do negócio (gás, embalagem, insumo comprado na hora), fora de
qualquer venda. Decalque de extrasCaixa.py, do qual herda o desenho inteiro:
mesma chave (idEvento do relógio lógico), mesma revisão de conteúdo
(idEventoRevisao), mesmo tombstone incondicional ao apagar.

POR QUE UM MÓDULO SEPARADO DOS EXTRAS, e não um campo "tipo" dentro deles: as
duas coisas entram na conta do dia de formas OPOSTAS (ver
FechamentoController._calcular_resumo_dia e a tela de Fechamento).

- Uma diária (extras) sai da gaveta e aparece como FALTA ao conferir o caixa —
  é justamente o que se quer enxergar: o dinheiro não está mais lá.
- Uma despesa é somada de volta à contagem de Cartão/Dinheiro/Pix, para a
  gaveta parar de acusar falta por dinheiro que se sabe onde foi.

Misturar os dois num campo discriminador faria toda leitura precisar lembrar
de filtrar pelo tipo certo — e esquecer o filtro num lugar só já erraria o
caixa do dia sem nada na tela denunciando.

Cada despesa tem NOME e VALOR (o "funcionario" dos extras vira "nome" aqui,
que é a descrição do que foi pago).

Guardado em pedidos/.sync/despesas.json (ver services/rede/caminhos.py):
`{idEvento: {"dataIso", "nome", "valor", "dataHora", "idEventoRevisao"}}`."""

import os

from services.rede import caminhos, relogio, tombstones

_ROTULO = "despesasCaixa"

# Mesmo nome do domínio de reconciliação e do de tombstones — ver
# FechamentoController, que registra os dois com esta constante.
DOMINIO = "despesas"


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "despesas.json")


def carregar():
    """`{idEvento: {dataIso, nome, valor, dataHora}}` de todas as despesas
    conhecidas por esta máquina (as que ela mesma lançou e as que aprendeu de
    outras)."""
    return caminhos.carregar_json(_caminho_arquivo(), _ROTULO)


def _salvar(dados):
    caminhos.salvar_json(_caminho_arquivo(), dados, _ROTULO)


def listar_do_dia(data_iso):
    """Despesas de `data_iso` ("AAAA-MM-DD"), na ordem em que foram
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


def registrar(data_iso, nome, valor, data_hora, quando=None):
    """Grava uma nova despesa e devolve o id do lançamento.

    `quando` vem preenchido quando o lançamento foi aprendido de outra
    máquina (gossip ou reconciliação): preservar o id de origem é o que faz
    todas as máquinas concordarem sobre o MESMO lançamento — mesmo cuidado
    de baixaComandas.registrar. Gerar um id local aqui faria cada máquina
    anunciar um valor diferente para o mesmo pagamento.

    Idempotente: um id que já existe não é regravado, senão uma reentrega de
    gossip duplicaria a linha (e o desconto no caixa) na despesa."""
    dados = carregar()
    id_evento = quando or relogio.novo_id()
    if id_evento in dados:
        return id_evento

    dados[id_evento] = {
        "dataIso": data_iso,
        "nome": nome,
        "valor": valor,
        "dataHora": data_hora,
        "idEventoRevisao": id_evento,
    }
    _salvar(dados)
    return id_evento


def editar(id_evento, nome, valor, quando=None):
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
    registro["nome"] = nome
    registro["valor"] = valor
    registro["idEventoRevisao"] = id_revisao
    _salvar(dados)
    return id_revisao


def apagar(id_evento, quando=None):
    """Apaga um lançamento — tombstone genérico de
    services/rede/tombstones.py (domínio "despesas"), mesmo padrão de
    ConsultaController.apagarComanda. `quando` só vem preenchido quando a
    exclusão é aprendida de outra máquina (gossip ou reconciliação);
    senão gera um novo.

    Sempre registra o tombstone, mesmo se o id já não existir mais aqui —
    é o que impede a "ressurreição" de um lançamento apagado quando o
    gossip da exclusão chega antes do próprio lançamento (a ordem de
    entrega na malha não é garantida). Devolve o id do tombstone."""
    quando = tombstones.registrar(DOMINIO, id_evento, quando)
    dados = carregar()
    if id_evento in dados:
        del dados[id_evento]
        _salvar(dados)
    return quando


def aplicar_edicao_remota(id_evento, nome, valor, id_revisao):
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

    registro["nome"] = nome
    registro["valor"] = valor
    registro["idEventoRevisao"] = id_revisao
    _salvar(dados)
    return True
