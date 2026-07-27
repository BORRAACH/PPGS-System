"""Mescla data/cardapio/*.json quando uma máquina tem edição local (feita
pela tela Cardápio) e ao mesmo tempo puxa uma atualização que também mexeu
no mesmo arquivo — chamado por Config/atualizador.py depois de um "git
merge --ff-only" bem-sucedido (ver _mesclar_cardapios_locais lá).

Sem PyQt6/services de propósito: atualizador.py roda cedo, antes da malha
de rede (services/rede/redeService.py cria um RedeService — e com ele um
QTcpServer/QTimer — assim que importado) e nem sempre depois de existir uma
QApplication. Importar services/cardapioService.py aqui arrastaria as duas
coisas pra um momento arriscado de o processo ainda não estar pronto pra
elas.

Política de mesclagem, item a item (casado pelo campo "nome" — mesma chave
que a tela já usa pra barrar duplicata, ver PopupItemCardapio.qml):
  - Item só na atualização (novo lá, não existia antes): entra.
  - Item que sumiu na atualização (existia antes, não existe mais lá): sai
    — mesmo que ainda exista localmente sem nenhuma edição.
  - Item só localmente (adicionado nesta máquina, nunca chegou a um
    commit): entra — acréscimo puro, sem conflito com nada.
  - Item presente nas duas versões: os campos de PREÇO ficam com o valor
    local SE o local mudou esse preço em relação à versão anterior ao
    merge (edição de verdade feita nesta máquina); qualquer outro campo
    (nome, ingredientes, os demais preços) vem da atualização.
"""

import json

# Mesma lista de arquivos/campos de preço que services/cardapioService.py
# CATEGORIAS descreve — duplicado aqui por causa do isolamento de import
# explicado acima; se um campo de preço mudar lá, mude aqui também.
CAMPOS_PRECO_POR_ARQUIVO = {
    "pizzas.json": ("valorMini", "valorBroto", "valorGrande"),
    "lanches.json": ("valor.pao_hamburguer", "valor.pao_frances", "valor.pao_baby"),
    "bebidas.json": ("valor",),
    "outros.json": ("valor",),
}

# pizzas.json e lanches.json têm "id" por item (renumerado por posição a
# cada gravação, ver services/cardapioService.py:_numerar_itens); bebidas
# e outros não. Depois de mesclar itens vindos de versões diferentes, os
# ids antigos não significam mais nada — renumeramos de novo aqui.
ARQUIVOS_NUMERADOS = {"pizzas.json", "lanches.json"}


def _ler_caminho(item, caminho):
    atual = item
    for parte in caminho.split("."):
        if not isinstance(atual, dict):
            return None
        atual = atual.get(parte)
    return atual


def _gravar_caminho(item, caminho, valor):
    partes = caminho.split(".")
    atual = item
    for parte in partes[:-1]:
        atual = atual.setdefault(parte, {})
    atual[partes[-1]] = valor


def _por_nome(itens):
    return {item["nome"]: item for item in itens if isinstance(item, dict) and item.get("nome")}


def _mesclar_item(item_base, item_local, item_atualizado, campos_preco):
    """Copia o item da atualização e só troca os campos de preço que o
    local mudou de verdade (valor diferente da base) — tudo o mais vem da
    atualização, inclusive se a base for None (item novo dos dois lados
    ao mesmo tempo, coincidência rara, mas aí não tem "preço editado" pra
    preservar, então nem entra no if)."""
    mesclado = json.loads(json.dumps(item_atualizado))
    for caminho in campos_preco:
        valor_base = _ler_caminho(item_base, caminho) if item_base else None
        valor_local = _ler_caminho(item_local, caminho)
        if valor_local is not None and valor_local != valor_base:
            _gravar_caminho(mesclado, caminho, valor_local)
    return mesclado


def mesclar(nome_arquivo, texto_base, texto_local, texto_atualizado):
    """Devolve o JSON (texto, já formatado com indent=2) resultado de
    mesclar as três versões de `nome_arquivo` (ex: "pizzas.json"):
    `texto_base` é o conteúdo no commit de onde a máquina partiu,
    `texto_local` é o que estava não commitado nesta máquina antes de
    atualizar, `texto_atualizado` é o que o merge acabou de trazer.

    Em qualquer situação inesperada (JSON inválido em alguma das versões,
    formato que não é lista...) desiste da mesclagem e devolve
    `texto_atualizado` como veio, sem levantar exceção — quem chama trata
    isso como "nada pra mesclar, fica só com a atualização", nunca como
    erro fatal que travaria a abertura do app."""
    campos_preco = CAMPOS_PRECO_POR_ARQUIVO.get(nome_arquivo, ())

    try:
        base = json.loads(texto_base) if texto_base else []
        local = json.loads(texto_local)
        atualizado = json.loads(texto_atualizado)
    except (TypeError, ValueError) as erro:
        print(f"[mesclarCardapio] {nome_arquivo}: JSON inválido em alguma das versões ({erro}) — mantendo a versão da atualização.")
        return texto_atualizado

    if not isinstance(local, list) or not isinstance(atualizado, list):
        print(f"[mesclarCardapio] {nome_arquivo}: formato inesperado (esperava uma lista) — mantendo a versão da atualização.")
        return texto_atualizado

    base_por_nome = _por_nome(base) if isinstance(base, list) else {}
    local_por_nome = _por_nome(local)

    mesclado = []
    nomes_na_atualizacao = set()

    for item_atualizado in atualizado:
        if not isinstance(item_atualizado, dict):
            continue
        nome = item_atualizado.get("nome")
        nomes_na_atualizacao.add(nome)
        item_local = local_por_nome.get(nome)
        if item_local is not None:
            mesclado.append(_mesclar_item(base_por_nome.get(nome), item_local, item_atualizado, campos_preco))
        else:
            mesclado.append(item_atualizado)

    # Itens só locais (não estavam na base nem vieram na atualização): a
    # máquina adicionou algo que ainda não chegou a um commit — entra sem
    # conflito nenhum.
    for nome, item_local in local_por_nome.items():
        if nome not in nomes_na_atualizacao and nome not in base_por_nome:
            mesclado.append(item_local)

    if nome_arquivo in ARQUIVOS_NUMERADOS:
        for indice, item in enumerate(mesclado, start=1):
            item["id"] = indice

    return json.dumps(mesclado, indent=2, ensure_ascii=False) + "\n"
