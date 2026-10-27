"""Combos promocionais de pizza (data/cardapio/combos.json).

Um combo diz: "N pizzas de um tamanho, escolhidas entre estas, saem por R$ X
no total, nos dias da agenda". Não confundir com data/cardapio/promocoes/,
que troca o PREÇO DE UM SABOR (ver qml/pages/pedidos/pizzas/Pizzas.qml) — aqui
o preço depende do conjunto de pizzas do pedido.

Este módulo é puro (sem Qt, sem rede) para ser testável; a ponte com a tela e
a sincronização pela malha ficam em CardapioController
(services/cardapioService.py), que o importa.

Formato de um combo no arquivo:

    {
      "id": "a1b2c3d4",
      "nome": "Duas grandes",
      "valor": "69,90",             # preço do grupo inteiro
      "quantidade": 2,              # pizzas por grupo
      "tamanho": "Grande",
      "pizzas": ["Calabresa", ...], # elegíveis, pelo NOME (o id é renumerado
                                    # a cada gravação do cardápio)
      "ativo": true,
      "agenda": {
        "dias": [1, 2, 3, 4],       # 0=domingo ... 6=sábado; vazio = todos
        "inicio": "", "fim": "",    # "AAAA-MM-DD"; vazio = sem limite
        "datas": []                 # dias avulsos que valem sempre (feriados)
      }
    }

Pizzas fora do combo, ou além de um múltiplo de `quantidade`, ficam com o
preço cheio. Borda e adicionais nunca entram no preço do combo: são cobrados
por fora, como em qualquer pizza.
"""

import json
import os
import re
import unicodedata
import uuid
from datetime import date, datetime

from Config import caminhos as _caminhos

ARQUIVO = "combos.json"

# Valor de `escolhido` para "o atendente recusou todos os combos concorrentes".
SEM_COMBO = "nenhum"

_DATA = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def caminho_arquivo():
    return os.path.join(_caminhos.RAIZ_DADOS, "data", "cardapio", ARQUIVO)


def _chave(texto):
    """Nome comparável: sem acento, minúsculo, sem espaços nas pontas."""
    base = unicodedata.normalize("NFKD", str(texto or ""))
    return "".join(c for c in base if not unicodedata.combining(c)).casefold().strip()


def _data_valida(texto):
    if not _DATA.match(texto):
        return False
    try:
        datetime.strptime(texto, "%Y-%m-%d")
    except ValueError:
        return False
    return True


# ---------- Agenda ----------


def agenda_vale_em(agenda, dia):
    """True se `dia` (datetime.date) está dentro da agenda.

    Dia avulso vale sempre. Fora isso, valem juntas as restrições presentes:
    dia da semana E período. Agenda totalmente vazia = todos os dias; agenda
    só com datas avulsas = apenas essas datas."""
    agenda = agenda or {}
    dias = list(agenda.get("dias") or [])
    inicio = agenda.get("inicio") or ""
    fim = agenda.get("fim") or ""
    datas = list(agenda.get("datas") or [])
    texto = dia.isoformat()

    if texto in datas:
        return True
    if not dias and not inicio and not fim:
        return not datas
    if dias:
        # date.weekday(): segunda=0 ... domingo=6; a agenda usa 0=domingo.
        if (dia.weekday() + 1) % 7 not in dias:
            return False
    if inicio and texto < inicio:
        return False
    if fim and texto > fim:
        return False
    return True


def combo_disponivel_em(combo, dia):
    return bool(combo.get("ativo", True)) and agenda_vale_em(combo.get("agenda"), dia)


# ---------- Leitura e gravação ----------


def _normalizar_agenda(bruta):
    bruta = bruta if isinstance(bruta, dict) else {}
    dias = sorted({int(d) for d in (bruta.get("dias") or []) if str(d).isdigit() and 0 <= int(d) <= 6})
    datas = sorted({str(d) for d in (bruta.get("datas") or []) if _data_valida(str(d))})
    inicio = str(bruta.get("inicio") or "")
    fim = str(bruta.get("fim") or "")
    return {
        "dias": dias,
        "inicio": inicio if _data_valida(inicio) else "",
        "fim": fim if _data_valida(fim) else "",
        "datas": datas,
    }


def _normalizar_combo(bruto):
    """Combo no formato canônico, ou None se não der pra aproveitar."""
    if not isinstance(bruto, dict):
        return None
    # Import tardio: cardapioService importa este módulo.
    from services.cardapioService import normalizar_preco

    preco = normalizar_preco(bruto.get("valor"))
    if preco is None:
        return None
    try:
        quantidade = int(bruto.get("quantidade", 2))
    except (TypeError, ValueError):
        return None
    pizzas = []
    vistos = set()
    for nome in bruto.get("pizzas") or []:
        nome = str(nome or "").strip()
        if nome and _chave(nome) not in vistos:
            vistos.add(_chave(nome))
            pizzas.append(nome)
    return {
        "id": str(bruto.get("id") or "").strip() or uuid.uuid4().hex[:8],
        "nome": str(bruto.get("nome") or "").strip(),
        "valor": preco,
        "quantidade": quantidade,
        "tamanho": str(bruto.get("tamanho") or "").strip(),
        "pizzas": pizzas,
        "ativo": bool(bruto.get("ativo", True)),
        "agenda": _normalizar_agenda(bruto.get("agenda")),
    }


def carregar():
    """Combos gravados. Lista vazia se o arquivo não existe ou está ilegível:
    sem combos o app vende normalmente, só sem desconto."""
    try:
        with open(caminho_arquivo(), "r", encoding="utf-8") as arquivo:
            dados = json.load(arquivo)
    except FileNotFoundError:
        return []
    except (OSError, json.JSONDecodeError) as erro:
        print(f"[combosService] Falha ao ler {caminho_arquivo()}: {erro} — sem combos.")
        return []
    if not isinstance(dados, list):
        return []
    return [c for c in (_normalizar_combo(item) for item in dados) if c is not None]


def validar(combos):
    """Devolve (lista_canônica, "") ou (None, mensagem para a tela)."""
    if not isinstance(combos, list):
        return None, "Lista de combos inválida."
    saida = []
    ids = set()
    for posicao, bruto in enumerate(combos, start=1):
        combo = _normalizar_combo(bruto)
        if combo is None:
            return None, f"O valor do combo {posicao} não é um preço válido."
        rotulo = combo["nome"] or f"combo {posicao}"
        if not combo["nome"]:
            return None, f"O combo {posicao} precisa de um nome."
        if combo["quantidade"] < 2:
            return None, f'"{rotulo}": a quantidade de pizzas deve ser 2 ou mais.'
        if not combo["tamanho"]:
            return None, f'"{rotulo}": informe o tamanho das pizzas.'
        if not combo["pizzas"]:
            return None, f'"{rotulo}": escolha ao menos uma pizza elegível.'
        agenda = combo["agenda"]
        if agenda["inicio"] and agenda["fim"] and agenda["inicio"] > agenda["fim"]:
            return None, f'"{rotulo}": o período termina antes de começar.'
        if combo["id"] in ids:
            combo["id"] = uuid.uuid4().hex[:8]
        ids.add(combo["id"])
        saida.append(combo)
    return saida, ""


def salvar(combos):
    """Reescreve combos.json. Devolve "" ou a mensagem de erro; o arquivo só é
    tocado se tudo validar (mesma garantia de cardapioService.salvar)."""
    canonicos, erro = validar(combos)
    if erro:
        return erro
    caminho = caminho_arquivo()
    temporario = caminho + ".tmp"
    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
        with open(temporario, "w", encoding="utf-8", newline="\n") as arquivo:
            json.dump(canonicos, arquivo, indent=2, ensure_ascii=False)
            arquivo.write("\n")
        os.replace(temporario, caminho)
    except OSError as erro_io:
        print(f"[combosService] Falha ao gravar {caminho}: {erro_io}")
        try:
            os.remove(temporario)
        except OSError:
            pass
        return f"Não foi possível gravar os combos: {erro_io}"
    return ""


# ---------- Cálculo ----------


def _objeto(valor, padrao):
    if isinstance(valor, str):
        try:
            valor = json.loads(valor)
        except json.JSONDecodeError:
            return padrao
    return padrao if valor is None else valor


def _reais(texto):
    from services.comandaTextoService import valor_para_float

    return valor_para_float(str(texto or ""))


def _pizza_do_item(item):
    """(sabores, tamanho, valor_base) de uma linha do pedido que é pizza, ou
    None. valor_base é o preço da pizza SEM borda nem adicionais — é o que o
    combo substitui."""
    from services.comandaTextoService import dividir_sabores

    nome = str(item.get("pedido", item.get("nome", "")) or "").strip()
    sabores, tamanho = dividir_sabores(nome)
    if not sabores or not tamanho:
        return None
    base = _reais(item.get("valor"))
    borda = _objeto(item.get("borda"), None)
    if isinstance(borda, dict):
        base -= _reais(borda.get("valor"))
    for adicional in _objeto(item.get("adicionais"), []) or []:
        if isinstance(adicional, dict):
            base -= _reais(adicional.get("valor"))
    return sabores, tamanho, max(base, 0.0)


def _desconto_do_combo(combo, pizzas):
    """(desconto, grupos) do combo sobre `pizzas` [(sabores, tamanho, base)].

    Forma o máximo de grupos completos, usando as pizzas elegíveis MAIS
    CARAS primeiro: é o que dá o maior desconto, e as que sobram são as mais
    baratas. Desconto nunca negativo — se o grupo já custa menos que o combo,
    a pizza fica no preço cheio."""
    elegiveis_nomes = {_chave(n) for n in combo["pizzas"]}
    tamanho = _chave(combo["tamanho"])
    bases = sorted(
        (
            base
            for sabores, tam, base in pizzas
            if _chave(tam) == tamanho and all(_chave(s) in elegiveis_nomes for s in sabores)
        ),
        reverse=True,
    )
    quantidade = combo["quantidade"]
    grupos = len(bases) // quantidade
    valor = _reais(combo["valor"])
    desconto = 0.0
    for g in range(grupos):
        soma = sum(bases[g * quantidade:(g + 1) * quantidade])
        desconto += max(soma - valor, 0.0)
    return round(desconto, 2), grupos


def calcular(itens, dia=None, escolhido="", combos=None):
    """Desconto de combo para as linhas de um pedido.

    `itens`: linhas {pedido, valor, borda, adicionais}. `escolhido`: id do
    combo que o atendente elegeu quando há concorrência.

    Devolve:
      {"aplicado": {"id","nome","desconto","grupos"} | None,
       "conflito": [{"id","nome","desconto","grupos"}, ...]}

    Com UM combo rendendo desconto, ele é aplicado sozinho. Com dois ou mais
    (conflito), nada é aplicado até `escolhido` apontar para um deles — quem
    chama abre o popup de escolha com a lista de `conflito`."""
    dia = dia or date.today()
    combos = carregar() if combos is None else combos
    pizzas = [p for p in (_pizza_do_item(i) for i in itens or [] if isinstance(i, dict)) if p]

    candidatos = []
    for combo in combos:
        if not combo_disponivel_em(combo, dia):
            continue
        desconto, grupos = _desconto_do_combo(combo, pizzas)
        if desconto > 0:
            candidatos.append({"id": combo["id"], "nome": combo["nome"], "desconto": desconto, "grupos": grupos})

    if len(candidatos) <= 1:
        return {"aplicado": candidatos[0] if candidatos else None, "conflito": []}
    if escolhido == SEM_COMBO:
        return {"aplicado": None, "conflito": candidatos}
    for candidato in candidatos:
        if candidato["id"] == escolhido:
            return {"aplicado": candidato, "conflito": candidatos}
    return {"aplicado": None, "conflito": candidatos}


def com_desconto(itens, escolhido="", dia=None, combos=None):
    """`itens` mais, se algum combo valer, uma linha final com o desconto.

    A linha é um item comum (nome, valor negativo): assim o cupom, o parser, o
    "Valor do pedido" e o fechamento do caixa a tratam sem formato novo. Quem
    precisa dela fora da lista de produtos reconhece pelo nome
    (comandaTextoService.eh_desconto_combo).

    O nome do combo vai na observação, que sai numa linha própria: um nome de
    combo comprido quebraria o nome da linha, e a sobra seria relida como
    observação de qualquer jeito."""
    from services.comandaTextoService import PREFIXO_DESCONTO_COMBO

    itens = list(itens or [])
    aplicado = calcular(itens, dia=dia, escolhido=escolhido, combos=combos)["aplicado"]
    if aplicado is None:
        return itens
    detalhe = aplicado["nome"] + (f" x{aplicado['grupos']}" if aplicado["grupos"] > 1 else "")
    valor = f"-R$ {aplicado['desconto']:.2f}".replace(".", ",")
    itens.append({
        "pedido": PREFIXO_DESCONTO_COMBO,
        "observacao": detalhe,
        "valor": valor,
        "borda": None,
        "adicionais": [],
    })
    return itens
