"""Montagem do texto de comandas (tabela de itens, valores) compartilhada por
balcaoController.py, entregaController.py e salaoController.py — extraído de
dentro dos dois primeiros (que tinham essas mesmas funções duplicadas
byte-a-byte) quando salaoController.py apareceu como um terceiro consumidor.
"""

import re

from services import comandaEstiloService as estilo

# Separador usado em Pizzas.qml (nomesArray.join(" / ")) para pizzas meio a meio.
# Tem espaço dos dois lados, o que o distingue de nomes como "Atum c/ Cebola".
SEPARADOR_SABORES = " / "

# Codepage que a Bematech usa para acentuação (ç, ã, é...) em modo ESC/POS.
# Não é UTF-8: se salvar como UTF-8, os acentos saem corrompidos no cupom impresso.
CODEPAGE_IMPRESSORA = "cp850"


def dividir_sabores(pedido_texto):
    """Separa um pedido em (lista_de_sabores, tamanho).

    "Atum c/ Cebola / Bacon c/ Ovos (Grande)" vira
    (["Atum c/ Cebola", "Bacon c/ Ovos"], "Grande").
    """
    tamanho = None
    corpo = pedido_texto

    match = re.match(r"^(.*)\s\(([^)]+)\)$", pedido_texto)
    if match:
        corpo = match.group(1)
        tamanho = match.group(2)

    sabores = [s.strip() for s in corpo.split(SEPARADOR_SABORES) if s.strip()]
    return sabores, tamanho


def valor_para_float(valor_texto):
    """Converte "R$ 45,00" em 45.0. Retorna 0.0 se não conseguir interpretar."""
    if not valor_texto:
        return 0.0

    limpo = valor_texto.replace("R$", "").strip()
    limpo = limpo.replace(".", "").replace(",", ".")
    try:
        return float(limpo)
    except ValueError:
        return 0.0


# Prefixos que marcam as linhas extras impressas abaixo de um item (ver
# montar_grupos/formatar_tabela) — precisam ser reconhecíveis de volta por
# consultaController._reconstruir_itens, para não confundi-las com uma
# observação livre digitada pelo atendente.
PREFIXO_ADICIONAL = "+ "
PREFIXO_BORDA = "* "


def _linhas_de_list_model(modelo):
    """Lê um ListModel da QML (que chega aqui como QAbstractListModel) linha
    a linha, devolvendo uma lista de dicts — ou None se `modelo` não for um.

    Só olha os métodos que precisa (duck typing), sem importar PyQt6: este
    módulo é usado também por scripts e testes que rodam sem Qt carregado."""
    try:
        contar = modelo.rowCount
        indice_de = modelo.index
        ler = modelo.data
        papeis = modelo.roleNames()
    except AttributeError:
        return None

    nomes = {numero: bytes(nome).decode("utf-8", errors="replace") for numero, nome in papeis.items()}
    linhas = []
    for i in range(contar()):
        indice = indice_de(i, 0)
        linhas.append({nome: ler(indice, numero) for numero, nome in nomes.items()})
    return linhas


def _como_lista_de_dicts(valor):
    """Normaliza o que a QML mandou num campo que deveria ser uma lista de
    objetos (hoje: "adicionais").

    Existe porque um array atribuído a um role de ListModel não continua
    sendo um array: vira um list-model aninhado, que chega no Python como
    QAbstractListModel. Iterar nisso levanta TypeError — e uma exceção
    escapando de um slot chamado pela QML derrubava o app inteiro (ver
    Config/logConfig.protegido). As telas de Balcão/Entrega/Salão evitam
    isso guardando os adicionais como string JSON no ListModel, mas essa
    convenção é fácil de esquecer numa tela nova, então a conversão é feita
    aqui também — assim o pior caso vira "os adicionais saem certos do
    mesmo jeito", não "a comanda inteira se perde"."""
    if not valor:
        return []

    if isinstance(valor, dict):
        return [valor]

    if not isinstance(valor, (list, tuple)):
        linhas = _linhas_de_list_model(valor)
        if linhas is None:
            print(f"[comandaTextoService] Campo de adicionais em formato inesperado ({type(valor).__name__}) — ignorado.")
            return []
        valor = linhas

    return [item for item in valor if isinstance(item, dict)]


def montar_grupos(itens):
    """Converte os itens do pedido em grupos (um por item; uma pizza meio a
    meio gera várias linhas — uma por sabor/fração — mas continua sendo um
    único grupo), para que se possa separar os grupos com uma linha em
    branco depois de formatados.

    Cada grupo é um dict: {"linhas": [(coluna_pedido, valor, extras)], ...},
    "borda": texto da borda (nível do item/pizza inteira, "" se não houver),
    "observacao": texto da observação geral do item.

    "extras" (dentro de cada linha) é a lista de adicionais atribuídos
    especificamente àquele sabor (ver Pizzas.qml/PopupAdicionaisBordas.qml) —
    cada um sai numa linha própria, logo abaixo da fração correspondente."""
    grupos = []
    for item in itens:
        # Nome do item e observação saem em caixa alta no cupom impresso.
        pedido = item.get("pedido", "").upper()
        observacao = item.get("observacao", "").upper()
        valor = item.get("valor", "")
        adicionais = _como_lista_de_dicts(item.get("adicionais"))

        sabores, tamanho = dividir_sabores(pedido)

        if len(sabores) <= 1:
            sabor_unico = sabores[0] if sabores else pedido
            linhas = [(f"- {pedido}", valor, _extras_adicionais(adicionais, sabor_unico))]
        else:
            # Pizza meio a meio: cada sabor ocupa "1/N" da pizza.
            total = len(sabores)
            linhas = []
            for indice, sabor in enumerate(sabores):
                nome_sabor = f"{sabor} ({tamanho})" if indice == 0 and tamanho else sabor
                coluna_pedido = f"1/{total} - {nome_sabor}"
                valor_linha = valor if indice == 0 else ""
                linhas.append((coluna_pedido, valor_linha, _extras_adicionais(adicionais, sabor)))

        grupos.append({
            "linhas": linhas,
            "observacao": observacao,
            "borda": _formatar_borda(item.get("borda")),
        })

    return grupos


def _extras_adicionais(adicionais, sabor):
    """Linhas dos adicionais atribuídos a `sabor` (comparação sem diferenciar
    caixa — os nomes de sabor chegam em caixa alta do cupom, mas o adicional
    guarda o nome do sabor como veio de Pizzas.qml)."""
    extras = []
    for adicional in adicionais:
        if (adicional.get("sabor") or "").strip().upper() != (sabor or "").strip().upper():
            continue
        nome = (adicional.get("nome") or "").upper()
        valor_adicional = adicional.get("valor") or ""
        sufixo = f" ({valor_adicional})" if valor_adicional else ""
        extras.append(f"{PREFIXO_ADICIONAL}{nome}{sufixo}")
    return extras


def _formatar_borda(borda):
    if not borda:
        return ""

    if not isinstance(borda, dict):
        # Mesmo motivo de _como_lista_de_dicts: o que a QML manda nem sempre
        # é o dict simples que este código espera.
        print(f"[comandaTextoService] Campo de borda em formato inesperado ({type(borda).__name__}) — ignorado.")
        return ""

    nome = (borda.get("nome") or "").strip()
    if not nome:
        return ""

    valor_borda = borda.get("valor") or ""
    sufixo = f" ({valor_borda})" if valor_borda else ""
    return f"{PREFIXO_BORDA}{nome.upper()}{sufixo}"


def formatar_tabela(grupos):
    """Alinha pedido e valor em uma coluna "|" e separa cada grupo com uma
    linha em branco. Depois de cada fração vêm seus adicionais (se houver);
    depois de TODAS as frações do grupo vêm a borda (quando houver) e por
    último a observação — mesmo numa pizza meio a meio (ou dividida em mais
    partes), borda e observação saem só ao final, abaixo do nome completo,
    nunca entre uma fração e outra."""
    linhas = [linha for grupo in grupos for linha in grupo["linhas"]]
    if not linhas:
        return []

    largura_pedido = max(len(l[0]) for l in linhas)

    texto_linhas = []
    for indice, grupo in enumerate(grupos):
        if indice > 0:
            texto_linhas.append("")

        for coluna_pedido, valor, extras in grupo["linhas"]:
            # Alinha primeiro com o texto puro, e só então aplica o
            # estilo configurado — assim os bytes de controle (invisíveis
            # na impressão) não contam como largura na coluna.
            coluna_pedido_fmt = estilo.formatar_campo(coluna_pedido.ljust(largura_pedido), "pedido")
            texto_linhas.append(f"{coluna_pedido_fmt} | {valor}")
            for extra in extras:
                texto_linhas.append(f"  {estilo.formatar_campo(extra, 'adicional_item')}")

        if grupo["borda"]:
            texto_linhas.append(f"  {estilo.formatar_campo(grupo['borda'], 'borda_item')}")
        if grupo["observacao"]:
            texto_linhas.append(f"  {estilo.formatar_campo(grupo['observacao'], 'observacao_item')}")

    return texto_linhas
