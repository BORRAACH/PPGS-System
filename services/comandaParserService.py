"""Extração de campos do cabeçalho de uma comanda já salva (pedidos/*.txt) —
compartilhado por ConsultaController (exibir/editar/apagar) e
FechamentoController (somar/agrupar por dia).

Extraído de controllers/consultaController.py quando FechamentoController
apareceu como um segundo consumidor dessas mesmas regexes — mesmo motivo
que já levou comandaTextoService.py a existir (ver o docstring de lá).
Comportamento idêntico ao que já rodava dentro de ConsultaController; só
mudou de endereço.

Não inclui aqui o parsing pesado de itens/tabela (`_reconstruir_itens` em
consultaController.py) — isso só interessa a quem precisa reabrir a comanda
num formulário editável (Consulta > Editar), não a quem só precisa dos
campos de cabeçalho (cliente, data, forma de pagamento, status, valor)."""

import re

from services.comandaTextoService import valor_para_float

CODEPAGE_IMPRESSORA = "cp850"

ESC = "\x1b"
# Remove os códigos ESC/POS de negrito (ESC E 0x01 / ESC E 0x00) embutidos no
# .txt pelos controllers de venda — só fazem sentido para a impressora
# térmica, não para exibição em tela nem para extrair campos.
_PADRAO_NEGRITO = re.compile(re.escape(ESC) + r"E[\x00\x01]")

# Sem underscore: usadas de fora (ConsultaController) via extrair_campo(),
# diferente das de baixo, que só interessam às funções desta própria
# arquivo (por isso ficam encapsuladas em extrair_status_pagamento/
# extrair_valor_total em vez de expostas soltas).
PADRAO_CLIENTE = re.compile(r"^Cliente:[ \t]*(.*)$", re.MULTILINE)
PADRAO_DATA = re.compile(r"^Data:[ \t]*(.*)$", re.MULTILINE)
PADRAO_FORMA_PAGAMENTO = re.compile(r"^Forma de pagamento:[ \t]*(.*)$", re.MULTILINE)

_PADRAO_STATUS_PAGAMENTO = re.compile(r"^Status:[ \t]*(.*)$", re.MULTILINE)
# balcaoController imprime o status colado no fim da linha do valor total
# (ex: "Valor do pedido: R$ 45,00 [PG]") em vez de uma linha "Status:"
# própria como o entregaController — precisa de um padrão à parte para
# reconstruir.
_PADRAO_STATUS_PAGAMENTO_INLINE = re.compile(r"^Valor do pedido:.*\[(NP|PG)\][ \t]*$", re.MULTILINE)
# Valor total do pedido (Balcão/Entrega/Mesa sempre imprimem essa linha, com
# ou sem o status colado no fim — ver acima). Não-guloso antes de "R$" pra
# pular por cima de qualquer código ESC/POS de estilo que o campo tenha
# (negrito/sublinhado/etc. configurados em Configurações > Estilo).
_PADRAO_VALOR_TOTAL = re.compile(r"^Valor do pedido:.*?R\$\s*([\d.,]+)", re.MULTILINE)

# Os três tipos de comanda embutem a data (AAAAMMDD) no próprio nome do
# arquivo: "pedido_AAAAMMDD_HHMMSS_hash.txt" (Balcão), "entrega_..." e
# "mesa_..." — ver data_arquivo_aaaammdd.
_PADRAO_PREFIXO_ARQUIVO = re.compile(r"^(mesa|entrega|pedido)_(\d{8})_")


def limpar_codigos_impressora(texto):
    return _PADRAO_NEGRITO.sub("", texto)


def extrair_campo(padrao, texto):
    match = padrao.search(texto)
    return match.group(1).strip() if match else ""


def extrair_status_pagamento(texto):
    """Tenta primeiro a linha "Status:" própria (entregaController); se não
    encontrar, tenta o formato colado na linha do valor total
    (balcaoController). Comandas de Mesa não têm nenhum dos dois no nível
    do cabeçalho (cada divisão da conta tem sua própria forma/status, lá
    embaixo na seção "DIVISÃO DA CONTA") — devolve "" nesse caso."""
    status = extrair_campo(_PADRAO_STATUS_PAGAMENTO, texto)
    if status:
        return status

    match = _PADRAO_STATUS_PAGAMENTO_INLINE.search(texto)
    return match.group(1) if match else ""


def extrair_valor_total(texto):
    """Valor total impresso na comanda (já inclui taxa de entrega, quando
    houver — ver EntregaController._salvarComanda). 0.0 se não encontrar."""
    match = _PADRAO_VALOR_TOTAL.search(texto)
    if not match:
        return 0.0
    return valor_para_float("R$ " + match.group(1))


def tipo_comanda(nome_arquivo):
    if nome_arquivo.startswith("mesa_"):
        return "Mesa"
    if nome_arquivo.startswith("entrega_"):
        return "Entrega"
    return "Balcão"


def data_arquivo_aaaammdd(nome_arquivo):
    """Extrai a data (string "AAAAMMDD") embutida no nome do arquivo, sem
    abrir/ler o conteúdo — permite filtrar comandas de um dia específico
    (ver FechamentoController._calcular_resumo_dia) antes de gastar
    qualquer I/O de disco com arquivos de outros dias. None se o nome não
    bater com o padrão esperado (arquivo de origem desconhecida)."""
    match = _PADRAO_PREFIXO_ARQUIVO.match(nome_arquivo)
    return match.group(2) if match else None
