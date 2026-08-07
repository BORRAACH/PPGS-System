"""Compara duas versões da MESMA comanda campo a campo, para dizer se elas
são de fato iguais ou em quê exatamente divergem.

Por que isto existe. A tela de Consulta destacava comandas como "diferente em
outra máquina" comparando só o `idEvento` das duas
(controllers/consultaController.py), nunca o conteúdo. Como
`indicePedidos.id_evento()` cai num id SINTETIZADO do nome do arquivo quando a
comanda não tem entrada em `eventos.json` — comanda antiga, ou recebida de um
peer que não mandou o id —, bastava uma das máquinas ter o id real e a outra o
sintético para a mesma comanda, byte a byte idêntica, ficar destacada para
sempre. O destaque só faz sentido quando os valores realmente não batem, e é
isso que este módulo responde.

O que NÃO é comparado, de propósito:

- Bytes ESC/POS de estilo (negrito, sublinhado, tamanho da fonte). Eles vêm de
  Config/estilo_impressao.json, que cada máquina pode ter configurado de um
  jeito, e mudar a cor de um campo não muda a venda. Por isso a comparação
  roda sobre o texto já passado por `parser.limpar_codigos_impressora`.
- A ORDEM dos campos no papel, pelo mesmo motivo (ver
  comandaEstiloService.ordem_secoes): o que importa é o valor de cada campo,
  não em que linha ele saiu.

O que É comparado: todos os campos de venda, sempre os mesmos para os três
tipos de comanda — um campo que não existe naquele tipo fica "" dos dois lados
e nunca acusa diferença sozinho. Comparar o conjunto inteiro (em vez de só os
campos do tipo) é de propósito: se uma máquina tem "Taxa de entrega" e a outra
não, isso É uma divergência real e precisa aparecer.
"""

from services import comandaParserService as parser

# Rótulos em português para a tela (ver PainelDetalhe.qml) — mesma redação dos
# prefixos impressos no cupom, para o usuário reconhecer a linha no papel.
ROTULOS = {
    "codigo": "Código",
    "cliente": "Cliente",
    "mesa": "Mesa",
    "telefone": "Telefone",
    "endereco": "Endereço",
    "bairro": "Bairro",
    "data": "Data",
    "observacao": "Observação",
    "forma_pagamento": "Forma de pagamento",
    "troco_para": "Troco para",
    "status": "Status",
    "taxa_entrega": "Taxa de entrega",
    "valor_total": "Valor do pedido",
    "divisao_conta": "Divisão da conta",
    "itens": "Itens do pedido",
}


def _texto_limpo(conteudo):
    """Aceita tanto os bytes crus do arquivo quanto o texto já decodificado —
    quem chama às vezes tem um (o payload que veio da rede), às vezes o outro
    (o arquivo já lido para exibir)."""
    if isinstance(conteudo, (bytes, bytearray)):
        conteudo = bytes(conteudo).decode(parser.CODEPAGE_IMPRESSORA, errors="replace")
    return parser.limpar_codigos_impressora(conteudo)


def _resumir_item(item):
    """Um item da tabela reduzido a texto estável, para poder comparar item a
    item sem depender de como o dict foi montado. Inclui borda e adicionais:
    trocar o recheio da borda muda o preço da venda tanto quanto trocar o
    sabor."""
    partes = [item.get("pedido", ""), item.get("valor", "")]

    observacao = item.get("observacao", "")
    if observacao:
        partes.append(f"obs: {observacao}")

    borda = item.get("borda")
    if borda and borda.get("nome"):
        partes.append(f"borda: {borda['nome']} {borda.get('valor', '')}".strip())

    for adicional in item.get("adicionais") or []:
        partes.append(f"adicional: {adicional.get('nome', '')} {adicional.get('valor', '')}".strip())

    return " | ".join(parte for parte in partes if parte)


def campos_comparaveis(conteudo, nome_arquivo):
    """Todos os campos de venda de uma comanda, normalizados para comparação.

    `itens` e `divisao_conta` viram listas de strings (uma por linha) em vez de
    dicts aninhados: a comparação fica linha a linha, o que é o que a tela
    precisa mostrar, e não depende da forma interna do dict."""
    texto = _texto_limpo(conteudo)
    linhas_tabela = parser.linhas_tabela_itens(texto.split("\n"))
    itens = parser.reconstruir_itens(linhas_tabela) if linhas_tabela is not None else []

    divisoes = [
        f"{divisao['nome']}: {divisao['valor']:.2f} [{divisao['formaPagamento']}] [{divisao['status']}]"
        for divisao in parser.extrair_divisoes_mesa(texto)
    ]

    return {
        "codigo": parser.codigo_comanda(nome_arquivo, texto),
        "cliente": parser.extrair_campo(parser.PADRAO_CLIENTE, texto),
        "mesa": parser.extrair_campo(parser.PADRAO_MESA, texto),
        "telefone": parser.extrair_campo(parser.PADRAO_TELEFONE, texto),
        "endereco": parser.extrair_campo(parser.PADRAO_ENDERECO, texto),
        "bairro": parser.extrair_campo(parser.PADRAO_BAIRRO, texto),
        "data": parser.extrair_campo(parser.PADRAO_DATA, texto),
        "observacao": parser.extrair_campo(parser.PADRAO_OBSERVACAO_GERAL, texto),
        "forma_pagamento": parser.extrair_campo(parser.PADRAO_FORMA_PAGAMENTO, texto),
        "troco_para": parser.extrair_campo(parser.PADRAO_TROCO, texto),
        "status": parser.extrair_status_pagamento(texto),
        "taxa_entrega": parser.extrair_campo(parser.PADRAO_TAXA_ENTREGA, texto),
        # Número, não o texto impresso: comparar "R$ 45,00" com "R$ 45.00"
        # acusaria diferença onde a venda é a mesma.
        "valor_total": f"{parser.extrair_valor_total(texto):.2f}",
        "divisao_conta": divisoes,
        "itens": [_resumir_item(item) for item in itens],
    }


def _formatar(valor):
    """Lista vira uma linha por elemento; o resto vira texto puro. É o que a
    tela mostra na coluna de cada máquina."""
    if isinstance(valor, list):
        return "\n".join(valor)
    return valor or ""


def comparar(campos_a, campos_b):
    """Os campos cujo valor difere entre as duas versões, na ordem de ROTULOS
    (a mesma ordem em que saem no papel). Lista vazia = as duas comandas são
    a mesma venda, com os mesmos valores."""
    diferencas = []
    for campo in ROTULOS:
        valor_a = campos_a.get(campo)
        valor_b = campos_b.get(campo)
        if valor_a == valor_b:
            continue
        diferencas.append({
            "campo": campo,
            "rotulo": ROTULOS[campo],
            "local": _formatar(valor_a),
            "remoto": _formatar(valor_b),
        })
    return diferencas


def diferencas_entre(conteudo_a, conteudo_b, nome_arquivo):
    """Atalho para os dois passos acima, que é como quem chama sempre usa."""
    return comparar(
        campos_comparaveis(conteudo_a, nome_arquivo),
        campos_comparaveis(conteudo_b, nome_arquivo),
    )
