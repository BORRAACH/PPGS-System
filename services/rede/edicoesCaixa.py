"""Registro persistido das ALTERAÇÕES feitas em comandas que já receberam
baixa — quem mexeu no caixa depois de ele já estar fechado, e o que mudou.

POR QUE EXISTE. Uma comanda fechada é uma venda já contada no caixa do dia
(ver services/rede/baixaComandas.py). Corrigi-la depois disso muda o total de
um dia que alguém já conferiu, e até aqui isso não deixava marca nenhuma no
papel: o cupom de fechamento reimpresso simplesmente trazia outro número, sem
dizer que houve correção nem quem a fez. O histórico da malha
(services/rede/historicoEventos.py) registra a autorização, mas ele tem
retenção curta (7 dias / 1000 eventos), vive na tela de Rede e não sai
impresso — não serve como trilha de um documento de caixa.

Daí um domínio próprio, e não um campo dentro de baixaComandas: a baixa é um
fato binário e imutável ("esta comanda conta"), enquanto aqui cada alteração é
um registro novo — a mesma comanda pode ser corrigida três vezes, e o cupom
precisa mostrar as três.

APPEND-ONLY, como historicoEventos e ao contrário de extras/despesas: uma
alteração é um fato datado que já aconteceu, não um lançamento que se corrige
depois. Não há `editar` nem `apagar`, e é isso que torna a sincronização livre
de conflito por construção — reconciliar é a união dos dois lados, sem
tombstone e sem arbitragem de revisão.

O QUE ELE NÃO É. O nome gravado é o de quem digitou o código de dois dígitos,
e a malha não autentica ninguém (ver o topo de services/rede/usuarios.py):
isto responde "quem mexeu nisto?", não "prove que foi você". Com ninguém
cadastrado o campo sai vazio e o cupom imprime "não identificado" — o buraco
do bootstrap continua existindo, mas nunca em silêncio.

Guardado em pedidos/.sync/edicoes_caixa.json (ver services/rede/caminhos.py):
`{idEvento: {"dataIso", "acao", "usuario", "dataHora", "codigo", "cliente",
"valorAntes", "valorDepois", "noCaixa", "arquivo", "arquivoNovo"}}`."""

import os

from services.rede import caminhos, relogio

_ROTULO = "edicoesCaixa"

# Mesmo nome do domínio de reconciliação — ver FechamentoController, que o
# registra com esta constante.
DOMINIO = "edicoes"

# As duas formas de mexer numa comanda já fechada, ambas partindo do
# Fechamento (ver qml/pages/fechamento/PopupFechamentoRapido.qml): corrigir
# (apaga e regrava, ver components/EdicaoComanda.js) e apagar de vez. Vão
# como constante porque o cupom escolhe o rótulo por elas.
ACAO_EDITADA = "editada"
ACAO_EXCLUIDA = "excluida"


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "edicoes_caixa.json")


def carregar():
    """`{idEvento: {dataIso, acao, usuario, ...}}` de todas as alterações
    conhecidas por esta máquina (as feitas aqui e as aprendidas de outras)."""
    return caminhos.carregar_json(_caminho_arquivo(), _ROTULO)


def _salvar(dados):
    caminhos.salvar_json(_caminho_arquivo(), dados, _ROTULO)


def listar_do_dia(data_iso):
    """Alterações que atingiram o caixa de `data_iso` ("AAAA-MM-DD"), na
    ordem em que aconteceram.

    `dataIso` é o dia da COMANDA alterada, não o dia em que a alteração foi
    feita: é o caixa daquele dia que mudou de valor, e é no cupom dele que a
    linha precisa sair. Os dois normalmente coincidem (a correção fica presa
    ao dia corrente, ver `ehHoje` em PopupFechamentoRapido.qml), mas quem lê
    isto não deve depender disso.

    Ordenar pelo id equivale a ordenar cronologicamente — o id de
    services/rede/relogio.py embute o instante de criação."""
    dados = carregar()
    itens = [
        dict(registro, id=id_evento)
        for id_evento, registro in dados.items()
        if registro.get("dataIso") == data_iso
    ]
    itens.sort(key=lambda item: item["id"])
    return itens


def contar_do_usuario(nome):
    """Quantas alterações em comanda já fechada este nome assina.

    Diferente de historicoEventos.contar_autorizacoes, aqui NÃO há janela: este
    domínio nunca é purgado, então o número é a vida inteira da pessoa. O
    casamento também é pelo nome — é o que está gravado no registro (ver
    registrar), porque é o nome que sai impresso no cupom de fechamento."""
    nome = (nome or "").strip()
    if not nome:
        return 0
    return sum(1 for registro in carregar().values() if (registro.get("usuario") or "").strip() == nome)


def registrar(data_iso, acao, usuario, data_hora, codigo="", cliente="",
              valor_antes=0.0, valor_depois=0.0, no_caixa=False, arquivo="",
              arquivo_novo="", quando=None):
    """Grava uma alteração e devolve o id do registro.

    `quando` vem preenchido quando a alteração foi aprendida de outra máquina
    (gossip ou reconciliação): preservar o id de origem é o que faz todas as
    máquinas gravarem exatamente a MESMA marca para a mesma alteração — mesmo
    cuidado de baixaComandas.registrar. Gerar um id local aqui faria cada
    máquina anunciar um valor diferente para o mesmo fato, e elas ficariam se
    pedindo a mesma chave a cada ciclo de anti-entropy.

    Idempotente: um id que já existe não é regravado, senão uma reentrega de
    gossip duplicaria a linha no cupom."""
    dados = carregar()
    id_evento = quando or relogio.novo_id()
    if id_evento in dados:
        return id_evento

    dados[id_evento] = {
        "dataIso": data_iso,
        "acao": acao,
        "usuario": usuario,
        "dataHora": data_hora,
        "codigo": codigo,
        "cliente": cliente,
        "valorAntes": valor_antes,
        "valorDepois": valor_depois,
        # Se o que sobrou da alteração AINDA conta no caixa do dia. False
        # numa exclusão (não sobrou nada) e também numa correção em que a
        # baixa não foi devolvida (ver qml/pages/fechamento/PopupManterBaixa.qml):
        # nos dois casos o dia perdeu "valorAntes" inteiro, e é essa
        # diferença que quem confere o caixa está procurando. Separado de
        # "valorDepois" porque uma comanda pode legitimamente valer R$ 0,00 —
        # usar o zero como sinal confundiria os dois casos.
        "noCaixa": no_caixa,
        # Os nomes de arquivo não saem impressos — ficam para conferir duas
        # máquinas na mão quando uma correção acaba mal (o "arquivoNovo" é
        # justamente o que a Consulta ainda tem em disco).
        "arquivo": arquivo,
        "arquivoNovo": arquivo_novo,
    }
    _salvar(dados)
    return id_evento


# ---------- Sincronização entre máquinas ----------
# Registro imutável: a versão de cada um é o próprio id, e reconciliar é a
# união dos dois lados — mesmo contrato de services/rede/historicoEventos.py.
# Sem "apagados": não existe operação de apagar uma alteração já registrada.


def resumo(limite_data_iso=""):
    """`{"itens": {id: id}, "apagados": {}}` das alterações a anunciar num
    ciclo de anti-entropy. `limite_data_iso` corta as anteriores à janela de
    reconciliação (ver FechamentoController._resumo_edicoes): uma alteração
    num caixa velho não muda mais nenhum número comparado entre as máquinas,
    e o registro em si nunca é purgado do disco."""
    dados = carregar()
    itens = {
        id_evento: id_evento
        for id_evento, registro in dados.items()
        if registro.get("dataIso", "") >= limite_data_iso
    }
    return {"itens": itens, "apagados": {}}


def obter(id_evento):
    registro = carregar().get(id_evento)
    if not registro:
        return None
    return dict(registro, id=id_evento)


def aplicar(id_evento, payload):
    """Grava uma alteração aprendida de outra máquina. Devolve o dia atingido
    ("AAAA-MM-DD") quando a gravação foi novidade aqui, e "" quando já era
    conhecida — quem chama usa isso para saber se algum cupom mudou."""
    if not isinstance(payload, dict) or not id_evento:
        return ""

    relogio.observar(id_evento)
    if id_evento in carregar():
        return ""

    data_iso = payload.get("dataIso", "")
    registrar(
        data_iso,
        payload.get("acao", ""),
        payload.get("usuario", ""),
        payload.get("dataHora", ""),
        codigo=payload.get("codigo", ""),
        cliente=payload.get("cliente", ""),
        valor_antes=payload.get("valorAntes", 0.0),
        valor_depois=payload.get("valorDepois", 0.0),
        no_caixa=bool(payload.get("noCaixa", False)),
        arquivo=payload.get("arquivo", ""),
        arquivo_novo=payload.get("arquivoNovo", ""),
        quando=id_evento,
    )
    return data_iso
