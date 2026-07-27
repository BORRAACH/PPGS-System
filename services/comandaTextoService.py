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


def montar_grupos(itens):
    """Converte os itens do pedido em grupos de linhas (coluna_pedido, observacao, valor).

    Cada item vira um grupo (uma pizza meio a meio gera várias linhas, mas
    continua sendo um único grupo), para que se possa separar os grupos
    com uma linha em branco depois de formatados.
    """
    grupos = []
    for item in itens:
        # Nome do item e observação saem em caixa alta no cupom impresso.
        pedido = item.get("pedido", "").upper()
        observacao = item.get("observacao", "").upper()
        valor = item.get("valor", "")

        sabores, tamanho = dividir_sabores(pedido)

        if len(sabores) <= 1:
            grupos.append([(f"- {pedido}", observacao, valor)])
            continue

        # Pizza meio a meio: cada sabor ocupa "1/N" da pizza.
        total = len(sabores)
        grupo = []
        for indice, sabor in enumerate(sabores):
            nome_sabor = f"{sabor} ({tamanho})" if indice == 0 and tamanho else sabor
            coluna_pedido = f"1/{total} - {nome_sabor}"
            if indice == 0:
                grupo.append((coluna_pedido, observacao, valor))
            else:
                grupo.append((coluna_pedido, "", ""))
        grupos.append(grupo)

    return grupos


def formatar_tabela(grupos):
    """Alinha pedido e valor em uma coluna "|" e separa cada grupo com uma
    linha em branco. A observação (quando houver) vai numa linha própria,
    recuada e com o estilo configurado para o campo "observacao_item" (ver
    services/comandaEstiloService.py), depois de TODAS as frações do
    grupo — mesmo numa pizza meio a meio (ou dividida em mais partes), a
    observação sai só ao final, abaixo do nome completo, nunca entre uma
    fração e outra."""
    linhas = [linha for grupo in grupos for linha in grupo]
    if not linhas:
        return []

    largura_pedido = max(len(l[0]) for l in linhas)

    texto_linhas = []
    for indice, grupo in enumerate(grupos):
        if indice > 0:
            texto_linhas.append("")

        observacao_grupo = ""
        for coluna_pedido, observacao, valor in grupo:
            # Alinha primeiro com o texto puro, e só então aplica o
            # estilo configurado — assim os bytes de controle (invisíveis
            # na impressão) não contam como largura na coluna.
            coluna_pedido_fmt = estilo.formatar_campo(coluna_pedido.ljust(largura_pedido), "pedido")
            texto_linhas.append(f"{coluna_pedido_fmt} | {valor}")
            if observacao:
                observacao_grupo = observacao

        if observacao_grupo:
            texto_linhas.append(f"  {estilo.formatar_campo(observacao_grupo, 'observacao_item')}")

    return texto_linhas
