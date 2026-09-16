"""Registro persistido de TODA edição e exclusão de comanda — com baixa ou sem —
para as estatísticas do dia (ver services/estatisticasService.py).

POR QUE EXISTE, ao lado de services/rede/edicoesCaixa.py. Aquele registra só as
alterações em comandas JÁ FECHADAS, porque é o que sai impresso no cupom de
fechamento como correção do caixa. Uma comanda ainda sem baixa corrigida ou
apagada pela Consulta não deixava marca nenhuma além do tombstone da
sincronização (services/rede/tombstones.py), que não diz se foi edição ou
exclusão, nem quem, nem quanto valia. Misturar as duas coisas em edicoesCaixa
faria o cupom imprimir correções que não mexeram no caixa — daí um domínio
próprio, que nunca sai no papel.

Os dois ganchos já existem e são chamados em toda alteração:
FechamentoController.registrarEdicaoCaixa (Balcão/Entrega, ao gravar a comanda
corrigida) e registrarExclusaoCaixa (Consulta, antes de apagar). É ali que este
registro é gravado, sempre, antes do teste de baixa.

APPEND-ONLY, mesmo contrato de edicoesCaixa: uma alteração é um fato datado que
já aconteceu. Não há editar nem apagar, e sincronizar é a união dos dois lados,
sem tombstone e sem arbitragem.

Guardado em pedidos/.sync/alteracoes_comandas.json (ver
services/rede/caminhos.py): `{idEvento: {"dataIso", "acao", "tipo", "usuario",
"dataHora", "codigo", "cliente", "valorAntes", "valorDepois", "fechada",
"arquivo", "arquivoNovo"}}`."""

import os

from services.rede import caminhos, relogio

_ROTULO = "alteracoesComandas"

# Nome do domínio de reconciliação — ver FechamentoController, que o registra
# com esta constante.
DOMINIO = "alteracoes"

ACAO_EDITADA = "editada"
ACAO_EXCLUIDA = "excluida"


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "alteracoes_comandas.json")


def carregar():
    """`{idEvento: registro}` de todas as alterações conhecidas por esta
    máquina (as feitas aqui e as aprendidas de outras)."""
    return caminhos.carregar_json(_caminho_arquivo(), _ROTULO)


def _salvar(dados):
    caminhos.salvar_json(_caminho_arquivo(), dados, _ROTULO)


def listar_do_dia(data_iso):
    """Alterações em comandas de `data_iso` ("AAAA-MM-DD"), na ordem em que
    aconteceram. `dataIso` é o dia da COMANDA, como em edicoesCaixa: é das
    vendas daquele dia que a alteração fala. Ordenar pelo id é ordenar pelo
    tempo — o id de services/rede/relogio.py embute o instante de criação."""
    itens = [
        dict(registro, id=id_evento)
        for id_evento, registro in carregar().items()
        if registro.get("dataIso") == data_iso
    ]
    itens.sort(key=lambda item: item["id"])
    return itens


def dias_com_alteracoes():
    """Os dias ("AAAA-MM-DD") que têm alguma alteração registrada — um dia
    cujas comandas foram todas apagadas continua tendo o que contar."""
    return {registro.get("dataIso") for registro in carregar().values() if registro.get("dataIso")}


def registrar(data_iso, acao, tipo, usuario, data_hora, codigo="", cliente="",
              valor_antes=0.0, valor_depois=0.0, fechada=False, arquivo="",
              arquivo_novo="", quando=None):
    """Grava uma alteração e devolve o id. `quando` vem preenchido quando ela
    foi aprendida de outra máquina, para todas guardarem o mesmo id.
    Idempotente: um id já conhecido não é regravado."""
    dados = carregar()
    id_evento = quando or relogio.novo_id()
    if id_evento in dados:
        return id_evento

    dados[id_evento] = {
        "dataIso": data_iso,
        "acao": acao,
        # Balcão, Entrega ou Mesa (ver comandaParserService.tipo_comanda).
        "tipo": tipo,
        "usuario": usuario,
        "dataHora": data_hora,
        "codigo": codigo,
        "cliente": cliente,
        "valorAntes": valor_antes,
        "valorDepois": valor_depois,
        # Se a comanda já tinha baixa quando foi alterada — o que separa uma
        # correção do caixa (que também está em edicoesCaixa) de uma correção
        # comum de uma venda ainda não conferida.
        "fechada": fechada,
        "arquivo": arquivo,
        "arquivoNovo": arquivo_novo,
    }
    _salvar(dados)
    return id_evento


# ---------- Sincronização entre máquinas ----------
# Mesmo contrato de edicoesCaixa: a versão de cada registro é o próprio id, e
# reconciliar é a união.


def resumo(limite_data_iso=""):
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
    quando foi novidade aqui, e "" quando já era conhecida."""
    if not isinstance(payload, dict) or not id_evento:
        return ""

    relogio.observar(id_evento)
    if id_evento in carregar():
        return ""

    data_iso = payload.get("dataIso", "")
    registrar(
        data_iso,
        payload.get("acao", ""),
        payload.get("tipo", ""),
        payload.get("usuario", ""),
        payload.get("dataHora", ""),
        codigo=payload.get("codigo", ""),
        cliente=payload.get("cliente", ""),
        valor_antes=payload.get("valorAntes", 0.0),
        valor_depois=payload.get("valorDepois", 0.0),
        fechada=bool(payload.get("fechada", False)),
        arquivo=payload.get("arquivo", ""),
        arquivo_novo=payload.get("arquivoNovo", ""),
        quando=id_evento,
    )
    return data_iso
