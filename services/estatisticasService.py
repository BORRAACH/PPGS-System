"""Estatísticas diárias de venda: um JSON por dia, gravado a cada "Fechar Caixa"
(ver controllers/estatisticasController.py), e a soma de um período para a
página de Estatística (qml/pages/estatistica/Estatistica.qml).

POR QUE UM ARQUIVO PRÓPRIO, e não o cache do fechamento
(services/rede/fechamentoCache.py). Aquele é um cache do sistema operacional,
recalculável e descartável, com o que a tela de Fechamento precisa (as comandas
de cada modalidade, o texto de busca). Isto aqui é o HISTÓRICO que se consulta
meses depois: fica em pedidos/estatisticas/ (fora do git, como as comandas),
guarda só números e rankings e não depende de a comanda ainda existir — uma
comanda apagada daqui a um ano não some das vendas do dia em que foi fechada.

Nada aqui toca em Qt: o controller lê as comandas do dia e entrega a
montar_dia uma lista já interpretada; agregar só soma dicionários. As duas
rodam também na thread que gera o histórico."""

import os
import re
from datetime import date, datetime, timedelta

from services.rede import caminhos

VERSAO = 1
MODALIDADES = ("Balcão", "Entrega", "Mesa")
FORMAS_PAGAMENTO = (("dinheiro", "Dinheiro"), ("pix", "Pix"), ("cartao", "Cartão"))

# Maior período que a página pode pedir de uma vez: um ano de arquivos lidos.
MAXIMO_DIAS_PERIODO = 366
LIMITE_PRODUTOS = 15
LIMITE_BAIRROS = 10

_ROTULO = "estatisticas"
_PADRAO_DATA_ISO = re.compile(r"^\d{4}-\d{2}-\d{2}$")
_PADRAO_HORA = re.compile(r"(\d{1,2}):(\d{2})")


# ---------- Arquivos ----------

def pasta():
    """pedidos/estatisticas/ — dentro da árvore das comandas (fora do git),
    mas fora do padrão "*.txt" que os scans de comandas varrem."""
    return os.path.join(caminhos.pasta_pedidos(), "estatisticas")


def data_valida(data_iso):
    if not isinstance(data_iso, str) or not _PADRAO_DATA_ISO.match(data_iso):
        return False
    try:
        date.fromisoformat(data_iso)
    except ValueError:
        return False
    return True


def _caminho(data_iso):
    return os.path.join(pasta(), f"{data_iso}.json")


def carregar(data_iso):
    """As estatísticas gravadas de `data_iso`, ou None."""
    if not data_valida(data_iso):
        return None
    return caminhos.carregar_json(_caminho(data_iso), _ROTULO) or None


def salvar(data_iso, dados):
    if data_valida(data_iso):
        caminhos.salvar_json(_caminho(data_iso), dados, _ROTULO)


def listar_dias():
    """Os dias ("AAAA-MM-DD") que já têm arquivo, em ordem."""
    if not os.path.isdir(pasta()):
        return []
    return sorted(nome[:-5] for nome in os.listdir(pasta()) if nome.endswith(".json") and data_valida(nome[:-5]))


def datas_do_periodo(inicio, fim):
    """Os dias de `inicio` a `fim` (inclusive), no máximo MAXIMO_DIAS_PERIODO,
    ou [] quando as datas não servem."""
    if not data_valida(inicio) or not data_valida(fim):
        return []
    atual, final = date.fromisoformat(inicio), date.fromisoformat(fim)
    if final < atual:
        atual, final = final, atual
    datas = []
    while atual <= final and len(datas) < MAXIMO_DIAS_PERIODO:
        datas.append(atual.isoformat())
        atual += timedelta(days=1)
    return datas


# ---------- Um dia ----------

def _hora(data_hora):
    """"15/09/2026 19:02:11" → "19"; "" sem hora."""
    achado = _PADRAO_HORA.search(data_hora or "")
    return f"{int(achado.group(1)):02d}" if achado else ""


def _centavos(valor):
    try:
        return round(float(valor or 0), 2)
    except (TypeError, ValueError):
        return 0.0


def montar_dia(data_iso, comandas, alteracoes, extras, despesas, contagem, formas_pagamento,
               origem, anterior=None, id_fechamento=""):
    """As estatísticas de `data_iso`.

    `comandas`: [{arquivo, tipo, codigo, cliente, usuario, valor, dataHora,
    fechada, itens: [{pedido, valor}], taxaEntrega, bairro}] — todas as do dia,
    com baixa ou sem. Venda é só a comanda com baixa, a mesma regra do caixa
    (FechamentoController._calcular_resumo_dia); as sem baixa vão em "abertas".

    `alteracoes`: registros de services/rede/alteracoesComandas.py.
    `formas_pagamento`: {dinheiro, pix, cartao} das vendas, já somado pelo
    controller (a Mesa divide a conta por forma de pagamento).

    `origem`: "fechamento" (alguém fechou o caixa), "historico" (gerado das
    comandas de um dia passado) ou "ao_vivo" (hoje, sem gravar). `anterior` é o
    arquivo que já existia: os fechamentos se acumulam nele, e um dia fechado
    continua "fechamento" quando é regravado por outro caminho.
    `id_fechamento` identifica o fechamento que gerou esta gravação — o mesmo em
    todas as máquinas, para o aviso repetido da rede não contar duas vezes."""
    anterior = anterior or {}
    fechadas = [c for c in comandas if c.get("fechada")]
    abertas = [c for c in comandas if not c.get("fechada")]

    total = 0.0
    por_modalidade = {m: {"quantidade": 0, "total": 0.0} for m in MODALIDADES}
    por_hora = {}
    produtos = {}
    entregas = {"quantidade": 0, "taxas": 0.0, "porBairro": {}}
    usuarios = {}
    comandas_fechadas = []

    for comanda in sorted(fechadas, key=lambda c: (c.get("dataHora") or "")[-8:]):
        valor = _centavos(comanda.get("valor"))
        tipo = comanda.get("tipo") or "Balcão"
        hora = _hora(comanda.get("dataHora"))
        total += valor

        grupo = por_modalidade.setdefault(tipo, {"quantidade": 0, "total": 0.0})
        grupo["quantidade"] += 1
        grupo["total"] += valor

        if hora:
            faixa = por_hora.setdefault(hora, {"quantidade": 0, "total": 0.0})
            faixa["quantidade"] += 1
            faixa["total"] += valor

        # O nome do item é o que saiu impresso (em caixa alta, com o tamanho):
        # é a única identidade de um produto depois da comanda pronta — a mesma
        # regra dos "produtos" do fechamento.
        for item in comanda.get("itens") or []:
            nome = (item.get("pedido") or "").strip()
            if not nome:
                continue
            contagem_item = produtos.setdefault(nome, [0, 0.0])
            contagem_item[0] += 1
            contagem_item[1] += _centavos(item.get("valor"))

        if tipo == "Entrega":
            entregas["quantidade"] += 1
            entregas["taxas"] += _centavos(comanda.get("taxaEntrega"))
            bairro = (comanda.get("bairro") or "").strip()
            if bairro:
                entregas["porBairro"][bairro] = entregas["porBairro"].get(bairro, 0) + 1

        nome_usuario = (comanda.get("usuario") or "").strip() or "Sem usuário"
        do_usuario = usuarios.setdefault(nome_usuario, {"quantidade": 0, "total": 0.0})
        do_usuario["quantidade"] += 1
        do_usuario["total"] += valor

        comandas_fechadas.append({
            "codigo": comanda.get("codigo", ""),
            "tipo": tipo,
            "cliente": comanda.get("cliente", ""),
            "valor": valor,
            "hora": (comanda.get("dataHora") or "")[-8:-3],
        })

    editadas = [a for a in alteracoes if a.get("acao") == "editada"]
    excluidas = [a for a in alteracoes if a.get("acao") == "excluida"]
    total_extras = sum(_centavos(e.get("valor")) for e in extras)
    total_despesas = sum(_centavos(d.get("valor")) for d in despesas)

    ids_fechamento = list(anterior.get("idsFechamento") or [])
    ultimo_fechamento = anterior.get("ultimoFechamento", "")
    if origem == "fechamento":
        if id_fechamento and id_fechamento not in ids_fechamento:
            ids_fechamento.append(id_fechamento)
        ultimo_fechamento = datetime.now().isoformat(timespec="seconds")
    foi_fechado = bool(ids_fechamento) or anterior.get("origem") == "fechamento"

    return {
        "versao": VERSAO,
        "data": data_iso,
        "geradoEm": datetime.now().isoformat(timespec="seconds"),
        "origem": "fechamento" if foi_fechado else ("ao_vivo" if origem == "ao_vivo" else "historico"),
        "fechamentos": len(ids_fechamento),
        "idsFechamento": ids_fechamento,
        "ultimoFechamento": ultimo_fechamento,
        "vendas": {
            "quantidade": len(fechadas),
            "total": round(total, 2),
            "ticketMedio": round(total / len(fechadas), 2) if fechadas else 0.0,
        },
        "porModalidade": {m: {"quantidade": g["quantidade"], "total": round(g["total"], 2)} for m, g in por_modalidade.items()},
        "formasPagamento": {chave: round(float((formas_pagamento or {}).get(chave, 0.0)), 2) for chave, _ in FORMAS_PAGAMENTO},
        "porHora": {h: {"quantidade": f["quantidade"], "total": round(f["total"], 2)} for h, f in sorted(por_hora.items())},
        # Do mais vendido para o menos, desempate pelo nome: ordem estável.
        "produtos": [
            {"nome": nome, "quantidade": q, "total": round(t, 2)}
            for nome, (q, t) in sorted(produtos.items(), key=lambda par: (-par[1][0], par[0]))
        ],
        "entregas": {
            "quantidade": entregas["quantidade"],
            "taxas": round(entregas["taxas"], 2),
            "porBairro": dict(sorted(entregas["porBairro"].items(), key=lambda par: (-par[1], par[0]))),
        },
        "usuarios": {nome: {"quantidade": u["quantidade"], "total": round(u["total"], 2)} for nome, u in sorted(usuarios.items())},
        "abertas": {"quantidade": len(abertas), "total": round(sum(_centavos(c.get("valor")) for c in abertas), 2)},
        "comandasFechadas": comandas_fechadas,
        "alteracoes": {
            "editadas": len(editadas),
            "excluidas": len(excluidas),
            "editadasFechadas": sum(1 for a in editadas if a.get("fechada")),
            "excluidasFechadas": sum(1 for a in excluidas if a.get("fechada")),
            "valorExcluido": round(sum(_centavos(a.get("valorAntes")) for a in excluidas), 2),
            "itens": [
                {chave: a.get(chave) for chave in ("acao", "tipo", "codigo", "cliente", "usuario", "dataHora", "valorAntes", "valorDepois", "fechada")}
                for a in alteracoes
            ],
        },
        "extras": {"quantidade": len(extras), "total": round(total_extras, 2)},
        "despesas": {"quantidade": len(despesas), "total": round(total_despesas, 2)},
        "contagem": (
            {chave: _centavos(contagem.get(chave)) for chave in ("cartao", "dinheiro", "pix")}
            if isinstance(contagem, dict) else None
        ),
        # O que sobra das vendas depois do que saiu do caixa no dia.
        "liquido": round(total - total_extras - total_despesas, 2),
    }


# ---------- Um período ----------

def agregar(estatisticas_por_dia, inicio, fim):
    """A soma de `inicio` a `fim` para a página: uma série por dia (os dias sem
    arquivo entram zerados, marcados `temDados: false`, para o gráfico não
    pular datas) e os totais e rankings do período."""
    datas = datas_do_periodo(inicio, fim)
    serie = []
    sem_dados = []
    totais = {
        "faturamento": 0.0, "vendas": 0, "liquido": 0.0, "extras": 0.0, "despesas": 0.0,
        "abertas": 0, "valorAberto": 0.0, "entregas": 0, "taxasEntrega": 0.0,
        "editadas": 0, "excluidas": 0, "valorExcluido": 0.0,
    }
    modalidades = {m: {"quantidade": 0, "total": 0.0} for m in MODALIDADES}
    formas = {chave: 0.0 for chave, _ in FORMAS_PAGAMENTO}
    horas = {}
    produtos = {}
    bairros = {}
    usuarios = {}

    for data_iso in datas:
        dia = estatisticas_por_dia.get(data_iso)
        if not dia:
            sem_dados.append(data_iso)
            serie.append({
                "data": data_iso, "temDados": False, "faturamento": 0.0, "vendas": 0, "ticketMedio": 0.0,
                "liquido": 0.0, "porModalidade": {m: 0.0 for m in MODALIDADES},
                "vendasPorModalidade": {m: 0 for m in MODALIDADES}, "editadas": 0, "excluidas": 0,
                "origem": "", "ultimoFechamento": "",
            })
            continue

        vendas = dia.get("vendas") or {}
        por_modalidade = dia.get("porModalidade") or {}
        alteracoes = dia.get("alteracoes") or {}
        entregas = dia.get("entregas") or {}
        abertas = dia.get("abertas") or {}
        serie.append({
            "data": data_iso,
            "temDados": True,
            "faturamento": vendas.get("total", 0.0),
            "vendas": vendas.get("quantidade", 0),
            "ticketMedio": vendas.get("ticketMedio", 0.0),
            "liquido": dia.get("liquido", 0.0),
            "porModalidade": {m: (por_modalidade.get(m) or {}).get("total", 0.0) for m in MODALIDADES},
            "vendasPorModalidade": {m: (por_modalidade.get(m) or {}).get("quantidade", 0) for m in MODALIDADES},
            "editadas": alteracoes.get("editadas", 0),
            "excluidas": alteracoes.get("excluidas", 0),
            "origem": dia.get("origem", ""),
            "ultimoFechamento": dia.get("ultimoFechamento", ""),
        })

        totais["faturamento"] += vendas.get("total", 0.0)
        totais["vendas"] += vendas.get("quantidade", 0)
        totais["liquido"] += dia.get("liquido", 0.0)
        totais["extras"] += (dia.get("extras") or {}).get("total", 0.0)
        totais["despesas"] += (dia.get("despesas") or {}).get("total", 0.0)
        totais["abertas"] += abertas.get("quantidade", 0)
        totais["valorAberto"] += abertas.get("total", 0.0)
        totais["entregas"] += entregas.get("quantidade", 0)
        totais["taxasEntrega"] += entregas.get("taxas", 0.0)
        totais["editadas"] += alteracoes.get("editadas", 0)
        totais["excluidas"] += alteracoes.get("excluidas", 0)
        totais["valorExcluido"] += alteracoes.get("valorExcluido", 0.0)

        for m, grupo in por_modalidade.items():
            destino = modalidades.setdefault(m, {"quantidade": 0, "total": 0.0})
            destino["quantidade"] += grupo.get("quantidade", 0)
            destino["total"] += grupo.get("total", 0.0)
        for chave in formas:
            formas[chave] += (dia.get("formasPagamento") or {}).get(chave, 0.0)
        for hora, faixa in (dia.get("porHora") or {}).items():
            destino = horas.setdefault(hora, {"quantidade": 0, "total": 0.0})
            destino["quantidade"] += faixa.get("quantidade", 0)
            destino["total"] += faixa.get("total", 0.0)
        for produto in dia.get("produtos") or []:
            destino = produtos.setdefault(produto.get("nome", ""), [0, 0.0])
            destino[0] += produto.get("quantidade", 0)
            destino[1] += produto.get("total", 0.0)
        for bairro, quantidade in (entregas.get("porBairro") or {}).items():
            bairros[bairro] = bairros.get(bairro, 0) + quantidade
        for nome, usuario in (dia.get("usuarios") or {}).items():
            destino = usuarios.setdefault(nome, {"quantidade": 0, "total": 0.0})
            destino["quantidade"] += usuario.get("quantidade", 0)
            destino["total"] += usuario.get("total", 0.0)

    totais = {chave: (round(valor, 2) if isinstance(valor, float) else valor) for chave, valor in totais.items()}
    totais["ticketMedio"] = round(totais["faturamento"] / totais["vendas"], 2) if totais["vendas"] else 0.0

    # Vendas por hora só entre a primeira e a última hora com movimento: um
    # gráfico de 24 barras com 18 vazias esconderia o horário de pico.
    por_hora = []
    if horas:
        primeira, ultima = int(min(horas)), int(max(horas))
        por_hora = [
            {"hora": f"{h:02d}", "quantidade": horas.get(f"{h:02d}", {}).get("quantidade", 0),
             "total": round(horas.get(f"{h:02d}", {}).get("total", 0.0), 2)}
            for h in range(primeira, ultima + 1)
        ]

    return {
        "inicio": datas[0] if datas else inicio,
        "fim": datas[-1] if datas else fim,
        "dias": serie,
        "diasComDados": len(datas) - len(sem_dados),
        "diasSemDados": sem_dados,
        "totais": totais,
        "porModalidade": [
            {"nome": m, "quantidade": g["quantidade"], "total": round(g["total"], 2)}
            for m, g in modalidades.items()
        ],
        "formasPagamento": [{"nome": rotulo, "total": round(formas[chave], 2)} for chave, rotulo in FORMAS_PAGAMENTO],
        "porHora": por_hora,
        "produtos": [
            {"nome": nome, "quantidade": q, "total": round(t, 2)}
            for nome, (q, t) in sorted(produtos.items(), key=lambda par: (-par[1][0], par[0]))[:LIMITE_PRODUTOS]
        ],
        "bairros": [
            {"nome": nome, "quantidade": q}
            for nome, q in sorted(bairros.items(), key=lambda par: (-par[1], par[0]))[:LIMITE_BAIRROS]
        ],
        "usuarios": [
            {"nome": nome, "quantidade": u["quantidade"], "total": round(u["total"], 2)}
            for nome, u in sorted(usuarios.items(), key=lambda par: (-par[1]["total"], par[0]))
        ],
    }
