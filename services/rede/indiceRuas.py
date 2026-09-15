"""Índice local das ruas da cidade da pizzaria — a primeira fonte das
sugestões de rua da Entrega.qml (ver services/sugestoesEndereco.py).

Por que existe. O Photon responde em 1,5-2 s, só devolve as ruas que ele
julga mais relevantes, e o bairro que ele dá a cada rua é um palpite do
OpenStreetMap: em Taubaté, 137 dos 167 bairros do mapa são só um ponto, e a
"Rua São Vicente de Paula" sai como "Jardim Morumby", quando a comanda (e os
Correios) dizem "Vila Nossa Senhora das Graças". Com todas as ruas do
município guardadas aqui, a busca é instantânea, funciona sem internet, cobre
a cidade inteira e carrega o bairro oficial.

De onde vem cada coisa (o download é de services/montadorIndiceRuas.py, numa
thread; quem muda o índice é sempre a thread da interface):

- as ruas: todas as vias com nome dentro do limite do município, numa
  consulta só ao Overpass;
- os bairros, em três graus de confiança (ver _PRIORIDADE_ORIGEM):
  "correios" (ViaCEP, consultado rua a rua em segundo plano), "osm" (pontos
  de bairro do mapa a até 800 m da rua, do mais perto para o mais longe) e
  "photon" (o bairro que o Photon deu a uma rua que ainda faltava aqui).

Replicado pela malha em NUMERO_BLOCOS blocos (a rua vai para um bloco pelo
hash da chave), e não rua a rua: com ~2.300 ruas, o resumo da reconciliação
mandaria milhares de chaves a cada ciclo; e por inicial, quase tudo cairia no
bloco "r" de "Rua". A fusão é união — rua nunca some, bairros se somam —,
então dois lados que trocam um bloco chegam ao mesmo conteúdo, e o hash dele
para de diferir.

A "base" diz de que cidade é o índice. Índices de cidades diferentes não se
misturam: vale o de montagem mais nova (idEvento), e o outro é descartado
inteiro — é o que acontece quando a localização da pizzaria muda na tela Rede.

Custo na máquina fraca (medido com Taubaté, 2.311 ruas):

- o arquivo tem ~550 KB e é gravado compacto e com ATRASO (gravar_pendente,
  chamado por um timer do dono): a reconciliação aplica 32 blocos seguidos, e
  gravar a cada bloco levava 650 ms de tela parada;
- a leitura do arquivo e a montagem da lista de busca (ler_arquivo) são
  funções puras, que o dono roda numa thread na abertura do sistema;
- a busca em si é binária sobre a lista pronta: frações de milissegundo.

Guardado em pedidos/.sync/indice_ruas.json:
`{"base": {"cidade", "uf", "idEvento", "localizacaoId"},
  "ruas": {chave: {"nome", "correios", "bairros": [{"nome", "origem", "distancia"}]}}}`
— "correios" diz se a rua já foi consultada no ViaCEP (tendo achado bairro
ou não), para a consulta em segundo plano retomar de onde parou."""

import bisect
import hashlib
import json
import os

from services.buscaCardapio import normalizar
from services.enderecoFormatado import normalizar_endereco, termos_de_busca
from services.rede import caminhos, relogio

_ROTULO = "indiceRuas"

DOMINIO = "indice_ruas"

NUMERO_BLOCOS = 32

ORIGEM_CORREIOS = "correios"
ORIGEM_OSM = "osm"
ORIGEM_PHOTON = "photon"

# Menor = mais confiável. O "osm" vem antes do "photon" porque é o ponto de
# bairro mais próximo da rua, enquanto o Photon devolve o distrito (em
# Taubaté, "Monção" para uma rua da Vila das Graças).
_PRIORIDADE_ORIGEM = {ORIGEM_CORREIOS: 0, ORIGEM_OSM: 1, ORIGEM_PHOTON: 2}

# Ruas devolvidas por busca. A lista na tela mostra 8; o resto serve à
# ordenação por bairro, que precisa de candidatos para escolher.
_LIMITE_BUSCA = 40
_LIMITE_BAIRROS = 20

# Estado em memória e caches derivados dele. Só a thread da interface mexe
# nestes globais; as threads só usam as funções puras (ler_arquivo,
# preparar_ruas, chave_rua).
_estado = None
_sujo = False  # mudou em memória e ainda não foi para o disco
_chaves_busca = None  # ([chave] ordenada, [(sufixo do meio, chave)] ordenada)
_bairros_busca = None  # [(prioridade, nome normalizado, nome)]
_blocos = None  # {bloco: {chave: rua}}
_hashes = None  # {bloco: sha1}
# (lista de busca de quando foi montado, {nome comparável: chave}). Refeito
# quando _chaves_busca é trocada, ou seja, quando o índice muda.
_equivalentes = None


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "indice_ruas.json")


def _limpar(texto):
    return " ".join(str(texto or "").split())


def chave_rua(nome):
    return normalizar(nome)


def bloco_da_chave(chave):
    numero = int(hashlib.sha1(chave.encode("utf-8")).hexdigest()[:8], 16) % NUMERO_BLOCOS
    return f"b{numero:02d}"


def _identidade(base):
    """(cidade normalizada, UF) — o que diz se dois índices são da mesma
    cidade. Vazio quando não há índice."""
    if not isinstance(base, dict) or not normalizar(base.get("cidade")):
        return ()
    return (normalizar(base.get("cidade")), str(base.get("uf") or "").upper())


# ---------- Validação e fusão (funções puras) ----------

def _normalizar_bairro(bairro):
    if not isinstance(bairro, dict):
        return None
    nome = _limpar(bairro.get("nome"))
    origem = bairro.get("origem")
    if not normalizar(nome) or origem not in _PRIORIDADE_ORIGEM:
        return None
    try:
        distancia = max(0, int(bairro.get("distancia") or 0))
    except (TypeError, ValueError):
        distancia = 0
    return {"nome": nome, "origem": origem, "distancia": distancia}


def _ordenar_bairros(bairros):
    """Um por nome (comparado sem acento), ficando com a origem mais
    confiável; em ordem de confiança e, dentro dela, de proximidade. A ordem
    só depende do conjunto — é o que faz as máquinas convergirem."""
    melhores = {}
    for bairro in bairros:
        k = normalizar(bairro["nome"])
        ordem = (_PRIORIDADE_ORIGEM[bairro["origem"]], bairro["distancia"], bairro["nome"])
        if k not in melhores or ordem < melhores[k][0]:
            melhores[k] = (ordem, bairro)
    return [bairro for _ordem, bairro in sorted(melhores.values(), key=lambda par: par[0])]


def _normalizar_rua(rua):
    if not isinstance(rua, dict):
        return None
    nome = _limpar(rua.get("nome"))
    if not normalizar(nome):
        return None
    brutos = rua.get("bairros") if isinstance(rua.get("bairros"), list) else []
    bairros = [b for b in map(_normalizar_bairro, brutos) if b]
    return {"nome": nome, "correios": bool(rua.get("correios")), "bairros": _ordenar_bairros(bairros)}


def _grafia_preferida(a, b):
    """Entre duas grafias da mesma rua ("Rua Sao Jose" / "Rua São José"), a
    acentuada; empatando, a primeira em ordem alfabética — para as máquinas
    escolherem a mesma sem conversar."""
    return min(a, b, key=lambda nome: (-sum(1 for c in nome if ord(c) > 127), nome))


def _mesclar_rua(atual, nova):
    if atual is None:
        return nova
    return {
        "nome": _grafia_preferida(atual["nome"], nova["nome"]),
        "correios": atual["correios"] or nova["correios"],
        "bairros": _ordenar_bairros(atual["bairros"] + nova["bairros"]),
    }


def preparar_ruas(brutas):
    """{chave: rua} validado e fundido a partir de ruas soltas (grafias
    diferentes da mesma rua viram uma entrada). Pura — o montador chama isto
    na thread, para a interface receber o download já pronto."""
    ruas = {}
    for bruta in brutas:
        rua = _normalizar_rua(bruta)
        if rua:
            k = chave_rua(rua["nome"])
            ruas[k] = _mesclar_rua(ruas.get(k), rua)
    return ruas


def _montar_busca(estado):
    """As listas ordenadas que a busca binária percorre, e os bairros
    conhecidos com a origem mais confiável de cada um. Pura.

    Duas listas, e não uma: os nomes inteiros ("rua sao vicente de paula") e
    os começos de palavra do meio ("sao vicente de paula", "vicente de
    paula", ...). A busca esgota a primeira antes de olhar a segunda e para
    no limite — com uma lista só, a primeira letra ("r", que casa com quase
    toda "Rua ...") obrigava a percorrer e ordenar milhares de entradas numa
    tecla só."""
    inicios = []
    meios = []
    bairros = {}
    for k, rua in estado["ruas"].items():
        inicios.append(k)
        palavras = k.split()
        for posicao in range(1, len(palavras)):
            meios.append((" ".join(palavras[posicao:]), k))
        for bairro in rua["bairros"]:
            nb = normalizar(bairro["nome"])
            ordem = _PRIORIDADE_ORIGEM[bairro["origem"]]
            if nb not in bairros or ordem < bairros[nb][0]:
                bairros[nb] = (ordem, bairro["nome"])
    inicios.sort()
    meios.sort()
    return (inicios, meios), sorted((ordem, nb, nome) for nb, (ordem, nome) in bairros.items())


# ---------- Leitura e gravação ----------

def ler_arquivo():
    """(estado, busca) lidos do disco. Pura — feita para rodar numa thread na
    abertura do sistema; quem adota o resultado é instalar_leitura."""
    dados = caminhos.carregar_json(_caminho_arquivo(), _ROTULO)
    base = dados.get("base") if isinstance(dados.get("base"), dict) else {}
    brutas = dados.get("ruas") if isinstance(dados.get("ruas"), dict) else {}
    estado = {"base": base if _identidade(base) else {}, "ruas": preparar_ruas(brutas.values())}
    return estado, _montar_busca(estado)


def instalar_leitura(leitura):
    """Adota o que ler_arquivo leu — só se o índice ainda não estiver em
    memória (uma busca ou um bloco da malha pode ter chegado antes e
    carregado na hora). Devolve True se adotou."""
    global _estado, _chaves_busca, _bairros_busca
    if _estado is not None:
        return False
    estado, (chaves, bairros) = leitura
    _estado = estado
    _invalidar_caches()
    _chaves_busca, _bairros_busca = chaves, bairros
    return True


def carregado():
    return _estado is not None


def _invalidar_caches():
    global _chaves_busca, _bairros_busca, _blocos, _hashes
    _chaves_busca = _bairros_busca = _blocos = _hashes = None


def _carregar():
    if _estado is None:
        instalar_leitura(ler_arquivo())
    return _estado


def _salvar(estado):
    """Troca o estado em memória; o disco fica para gravar_pendente."""
    global _estado, _sujo
    _estado = estado
    _sujo = True
    _invalidar_caches()


def gravar_pendente():
    """Grava o índice se ele mudou desde a última gravação. Chamado pelo dono
    com atraso (uma gravação por rajada de mudanças) e no fechamento."""
    global _sujo
    if not _sujo or _estado is None:
        return False
    caminhos.salvar_json(_caminho_arquivo(), _estado, _ROTULO, compacto=True)
    _sujo = False
    return True


def base():
    return dict(_carregar()["base"])


def contagens():
    """(ruas, ruas com bairro dos Correios, ruas já consultadas no ViaCEP)."""
    ruas = _carregar()["ruas"].values()
    oficiais = sum(1 for r in ruas if any(b["origem"] == ORIGEM_CORREIOS for b in r["bairros"]))
    return len(ruas), oficiais, sum(1 for r in ruas if r["correios"])


def chaves_consultadas():
    return {k for k, r in _carregar()["ruas"].items() if r["correios"]}


def pendentes_correios():
    """[(chave, nome)] das ruas que ainda não passaram pelo ViaCEP."""
    return sorted((k, r["nome"]) for k, r in _carregar()["ruas"].items() if not r["correios"])


def aplicar_montagem(base_nova, ruas_novas, preparadas=False):
    """Adota o resultado de um download do Overpass. Mesma cidade: soma ao
    que já existe — os bairros dos Correios já consultados não se perdem num
    download novo. Outra cidade: substitui tudo. `preparadas`: as ruas já
    vêm de preparar_ruas ({chave: rua}). Devolve o total de ruas."""
    estado = _carregar()
    novas = ruas_novas if preparadas else preparar_ruas(ruas_novas.values())

    if _identidade(estado["base"]) and _identidade(estado["base"]) == _identidade(base_nova):
        ruas = dict(estado["ruas"])
        for k, rua in novas.items():
            ruas[k] = _mesclar_rua(ruas.get(k), rua)
    else:
        ruas = dict(novas)

    _salvar({"base": dict(base_nova), "ruas": ruas})
    return len(ruas)


def _somar(ruas_novas, preparar):
    """Funde ruas no índice atual e devolve só as que mudaram (para a
    publicação na malha). `preparar(chave, atual, dado)` monta a rua a
    fundir, ou None para pular."""
    estado = _carregar()
    if not _identidade(estado["base"]):
        return {}
    ruas = dict(estado["ruas"])
    mudadas = {}
    for k, dado in ruas_novas.items():
        nova = preparar(k, ruas.get(k), dado)
        if nova is None:
            continue
        chave = chave_rua(nova["nome"])
        fundida = _mesclar_rua(ruas.get(chave), nova)
        if fundida != ruas.get(chave):
            ruas[chave] = fundida
            mudadas[chave] = fundida
    if mudadas:
        _salvar({"base": estado["base"], "ruas": ruas})
    return mudadas


def adicionar(ruas_novas):
    """Soma ruas descobertas fora do download (as que o Photon achou e
    faltavam aqui). `ruas_novas`: {qualquer chave: rua}."""
    return _somar(ruas_novas, lambda _k, _atual, dado: _normalizar_rua(dado))


def marcar_correios(resultados):
    """Grava o que o ViaCEP respondeu: {chave: [nomes de bairro]}. A rua fica
    marcada como consultada mesmo sem bairro achado — senão seria consultada
    de novo a cada abertura do sistema."""
    def preparar(_k, atual, bairros):
        if atual is None:
            return None
        return {
            "nome": atual["nome"],
            "correios": True,
            "bairros": [{"nome": _limpar(b), "origem": ORIGEM_CORREIOS, "distancia": 0} for b in bairros if normalizar(b)],
        }
    return _somar(resultados, preparar)


# ---------- Malha (gossip e anti-entropy) ----------

def aplicar_remoto(payload):
    """Funde um bloco (ou um lote de ruas publicado por gossip) vindo de
    outra máquina: {"base", "ruas"}. Devolve True se algo mudou aqui."""
    if not isinstance(payload, dict) or not _identidade(payload.get("base")):
        return False
    base_remota = payload["base"]
    relogio.observar(base_remota.get("idEvento", ""))

    estado = _carregar()
    base_local = estado["base"]
    if not _identidade(base_local):
        base_final, ruas = base_remota, {}
    elif _identidade(base_local) == _identidade(base_remota):
        mais_nova = relogio.mais_novo(base_remota.get("idEvento", ""), base_local.get("idEvento", ""))
        base_final, ruas = (base_remota if mais_nova else base_local), dict(estado["ruas"])
    elif relogio.mais_novo(base_remota.get("idEvento", ""), base_local.get("idEvento", "")):
        base_final, ruas = base_remota, {}
    else:
        return False

    mudou = base_final is not base_local
    brutas = payload.get("ruas") if isinstance(payload.get("ruas"), dict) else {}
    for k, rua in preparar_ruas(brutas.values()).items():
        fundida = _mesclar_rua(ruas.get(k), rua)
        if fundida != ruas.get(k):
            ruas[k] = fundida
            mudou = True

    if mudou:
        _salvar({"base": dict(base_final), "ruas": ruas})
    return mudou


def _preparar_blocos():
    global _blocos, _hashes
    if _blocos is not None:
        return
    estado = _carregar()
    blocos = {f"b{i:02d}": {} for i in range(NUMERO_BLOCOS)}
    for k, rua in estado["ruas"].items():
        blocos[bloco_da_chave(k)][k] = rua
    identidade = list(_identidade(estado["base"]))
    _blocos = blocos
    _hashes = {
        nome: hashlib.sha1(
            json.dumps({"cidade": identidade, "ruas": ruas}, sort_keys=True, ensure_ascii=False).encode("utf-8")
        ).hexdigest()
        for nome, ruas in blocos.items()
    }


def resumo():
    if not _identidade(_carregar()["base"]):
        return {"itens": {}}
    _preparar_blocos()
    return {"itens": dict(_hashes)}


def obter(bloco):
    estado = _carregar()
    if not _identidade(estado["base"]):
        return None
    _preparar_blocos()
    return {"base": dict(estado["base"]), "ruas": dict(_blocos.get(bloco, {}))}


# ---------- Busca ----------

def _preparar_busca():
    global _chaves_busca, _bairros_busca
    if _chaves_busca is None:
        _chaves_busca, _bairros_busca = _montar_busca(_carregar())


def _para_sugestao(rua):
    return {
        "nome": rua["nome"],
        "bairros": [b["nome"] for b in rua["bairros"]],
        "oficiais": [b["nome"] for b in rua["bairros"] if b["origem"] == ORIGEM_CORREIOS],
    }


def buscar_ruas(termo):
    """Ruas cujo nome tem uma palavra começando por `termo` —
    [{"nome", "bairros", "oficiais"}], primeiro as que começam pelo termo
    (em ordem alfabética), depois as que o têm no meio (em ordem da parte
    que casou). Para no limite: o custo não cresce com o tamanho da cidade.
    O termo vale também com a abreviação resolvida ("av indep" acha a
    "Avenida Independência", ver enderecoFormatado.termos_de_busca)."""
    termos = termos_de_busca(termo)
    if not termos:
        return []
    _preparar_busca()
    inicios, meios = _chaves_busca

    achadas = []
    vistas = set()
    for termo_normalizado in termos:
        indice = bisect.bisect_left(inicios, termo_normalizado)
        while indice < len(inicios) and len(achadas) < _LIMITE_BUSCA and inicios[indice].startswith(termo_normalizado):
            if inicios[indice] not in vistas:
                vistas.add(inicios[indice])
                achadas.append(inicios[indice])
            indice += 1

    for termo_normalizado in termos:
        indice = bisect.bisect_left(meios, (termo_normalizado,))
        while indice < len(meios) and len(achadas) < _LIMITE_BUSCA:
            sufixo, k = meios[indice]
            if not sufixo.startswith(termo_normalizado):
                break
            if k not in vistas:
                vistas.add(k)
                achadas.append(k)
            indice += 1

    ruas = _carregar()["ruas"]
    return [_para_sugestao(ruas[k]) for k in achadas]


def rua_equivalente(nome):
    """A rua do índice que é a mesma de `nome` — sem caixa, acento e
    pontuação, e com abreviação resolvida ("R. SAO VICENTE DE PAULA") —, no
    formato de _para_sugestao, ou None."""
    global _equivalentes
    ruas = _carregar()["ruas"]
    rua = ruas.get(chave_rua(nome))
    if rua is None:
        _preparar_busca()
        if _equivalentes is None or _equivalentes[0] is not _chaves_busca:
            mapa = {}
            for k, dados in ruas.items():
                mapa.setdefault(normalizar_endereco(dados["nome"]), k)
            _equivalentes = (_chaves_busca, mapa)
        k = _equivalentes[1].get(normalizar_endereco(nome))
        rua = ruas.get(k) if k else None
    return _para_sugestao(rua) if rua else None


def buscar_bairros(termo):
    """Nomes de bairro conhecidos pelo índice com uma palavra começando por
    `termo`, os dos Correios primeiro."""
    termos = termos_de_busca(termo)
    if not termos:
        return []
    _preparar_busca()
    return [
        nome for _ordem, nb, nome in _bairros_busca
        if any(f" {t}" in f" {nb}" or f" {t}" in f" {normalizar_endereco(nome)}" for t in termos)
    ][:_LIMITE_BAIRROS]
