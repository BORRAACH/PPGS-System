"""Downloads que alimentam o índice de ruas (services/rede/indiceRuas.py): as
ruas do município pelo Overpass e o bairro oficial de cada uma pelo ViaCEP.

Nada aqui toca em QObject, arquivo ou malha — só faz HTTP e devolve dados, e
por isso pode rodar numa thread. Quem roda e quem grava o resultado (sempre na
thread da interface) é o SugestoesEnderecoService: o índice tem um dono só, e
a malha, que também escreve nele, nunca disputa o arquivo com uma thread.

Pensado para a máquina fraca do balcão:

- o Overpass é UMA requisição (~1,2 MB e ~5 s para Taubaté), refeita só
  quando a localização da pizzaria muda ou o índice passa de 30 dias;
- o ViaCEP vai rua a rua, espaçado (ver o chamador) — para uma cidade de
  2.500 ruas leva por volta de uma hora, quase tudo espera de rede, sem
  disputar CPU com a tela; e retoma de onde parou na abertura seguinte;
- o cálculo de proximidade entre ruas e bairros cede a vez à thread da
  interface a cada punhado de ruas."""

import json
import math
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

from services.buscaCardapio import normalizar
from services.rede import indiceRuas

# Duas instâncias públicas: a principal cai de vez em quando por excesso de
# carga, e o download do índice é raro o bastante para valer a segunda.
_URLS_OVERPASS = (
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
)
_URL_VIACEP = "https://viacep.com.br/ws/{uf}/{cidade}/{logradouro}/json/"
_USER_AGENT = "ppgs-system"
_TIMEOUT_OVERPASS_S = 180
_TIMEOUT_VIACEP_S = 15

# Tipos de via que recebem endereço. Fora: footway, path, cycleway, track —
# trilha e ciclovia com nome não recebem entrega.
_TIPOS_VIA = "motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|pedestrian|road|service"
_TIPOS_BAIRRO = "suburb|neighbourhood|quarter"

# Até onde um ponto de bairro do mapa conta como "o bairro desta rua". Os
# pontos marcam o miolo do bairro, não o limite: 800 m pega o bairro de uma
# rua de ponta sem pegar o do outro lado da cidade.
_RAIO_BAIRRO_M = 800
_MAXIMO_BAIRROS_OSM = 3
_METROS_POR_GRAU = 111_320
# De quantas em quantas ruas o cálculo de proximidade solta o GIL.
_RUAS_POR_PAUSA = 50


class ErroMontagem(Exception):
    pass


def _consulta_overpass(lat, lon):
    """Município e estado que contêm o ponto (`is_in` — por coordenada, e não
    por nome: "Bom Jesus" existe em cinco estados), todas as vias com nome
    dentro do município e os pontos de bairro dele."""
    return f"""[out:json][timeout:{_TIMEOUT_OVERPASS_S}];
is_in({lat:.7f},{lon:.7f})->.a;
area.a["boundary"="administrative"]["admin_level"="8"]->.cidade;
area.a["boundary"="administrative"]["admin_level"="4"]->.estado;
.cidade out tags;
.estado out tags;
way(area.cidade)["highway"~"^({_TIPOS_VIA})$"]["name"];
out tags center qt;
(node(area.cidade)["place"~"^({_TIPOS_BAIRRO})$"];way(area.cidade)["place"~"^({_TIPOS_BAIRRO})$"];relation(area.cidade)["place"~"^({_TIPOS_BAIRRO})$"];);
out tags center qt;"""


def _ponto(elemento):
    if "center" in elemento:
        return elemento["center"]["lat"], elemento["center"]["lon"]
    if "lat" in elemento and "lon" in elemento:
        return elemento["lat"], elemento["lon"]
    return None


def _distancia_m(a, b):
    dlat = (a[0] - b[0]) * _METROS_POR_GRAU
    dlon = (a[1] - b[1]) * _METROS_POR_GRAU * math.cos(math.radians(a[0]))
    return math.hypot(dlat, dlon)


def _baixar_overpass(consulta, cancelado):
    corpo = urllib.parse.urlencode({"data": consulta}).encode("utf-8")
    ultimo_erro = None
    for url in _URLS_OVERPASS:
        if cancelado.is_set():
            raise ErroMontagem("cancelado")
        requisicao = urllib.request.Request(url, data=corpo, headers={"User-Agent": _USER_AGENT})
        try:
            with urllib.request.urlopen(requisicao, timeout=_TIMEOUT_OVERPASS_S + 20) as resposta:
                return json.load(resposta)
        except (urllib.error.URLError, OSError, ValueError) as erro:
            ultimo_erro = erro
    raise ErroMontagem(f"mapa de ruas indisponível ({ultimo_erro})")


def baixar_cidade(lat, lon, cancelado):
    """({"cidade", "uf"}, {chave: rua}) do município que contém (lat, lon),
    com os bairros "osm" de cada rua já calculados e as ruas já passadas por
    indiceRuas.preparar_ruas — a thread da interface só adota o resultado.
    `cancelado`: threading.Event que interrompe o trabalho (fechamento do
    sistema)."""
    dados = _baixar_overpass(_consulta_overpass(lat, lon), cancelado)

    cidade = uf = ""
    vias = {}
    bairros = []
    for elemento in dados.get("elements") or []:
        tags = elemento.get("tags") or {}
        if elemento.get("type") == "area":
            if tags.get("admin_level") == "8":
                cidade = tags.get("name") or cidade
            elif tags.get("admin_level") == "4":
                uf = str(tags.get("ISO3166-2") or "").rpartition("-")[2]
            continue
        ponto = _ponto(elemento)
        nome = " ".join(str(tags.get("name") or "").split())
        if ponto is None or not nome:
            continue
        if "place" in tags:
            bairros.append((nome, ponto))
        elif "highway" in tags:
            vias.setdefault(nome, []).append(ponto)

    if not cidade or not vias:
        raise ErroMontagem("a localização da pizzaria não caiu dentro de um município conhecido pelo mapa")

    ruas = {}
    for numero, (nome, pontos) in enumerate(vias.items()):
        if numero % _RUAS_POR_PAUSA == 0:
            if cancelado.is_set():
                raise ErroMontagem("cancelado")
            time.sleep(0.001)
        perto = {}
        for nome_bairro, ponto_bairro in bairros:
            distancia = min(_distancia_m(ponto, ponto_bairro) for ponto in pontos)
            if distancia <= _RAIO_BAIRRO_M and distancia < perto.get(nome_bairro, math.inf):
                perto[nome_bairro] = distancia
        mais_perto = sorted(perto.items(), key=lambda par: par[1])[:_MAXIMO_BAIRROS_OSM]
        ruas[nome] = {
            "nome": nome,
            "correios": False,
            "bairros": [{"nome": b, "origem": indiceRuas.ORIGEM_OSM, "distancia": int(d)} for b, d in mais_perto],
        }
    return {"cidade": cidade, "uf": uf}, indiceRuas.preparar_ruas(ruas.values())


def _sem_acento(texto):
    decomposto = unicodedata.normalize("NFD", str(texto or ""))
    return "".join(c for c in decomposto if unicodedata.category(c) != "Mn")


def consultar_correios(uf, cidade, nome):
    """Bairros dos Correios para a rua `nome` — [] quando o ViaCEP não a
    conhece (ou conhece com outra grafia: "Dom Pedro I" / "Dom Pedro
    Primeiro"). Levanta ErroMontagem só em falha de rede/serviço, que é o que
    o chamador trata com espera e nova tentativa.

    A resposta traz toda rua que CONTÉM o termo; só conta a de nome igual. Uma
    avenida longa volta com um CEP por trecho, cada um com o seu bairro — os
    trechos viram bairros diferentes da mesma rua."""
    if len(normalizar(nome)) < 3:
        return []
    url = _URL_VIACEP.format(
        uf=urllib.parse.quote(uf),
        cidade=urllib.parse.quote(_sem_acento(cidade)),
        logradouro=urllib.parse.quote(nome, safe=""),
    )
    requisicao = urllib.request.Request(url, headers={"User-Agent": _USER_AGENT})
    try:
        with urllib.request.urlopen(requisicao, timeout=_TIMEOUT_VIACEP_S) as resposta:
            dados = json.load(resposta)
    except urllib.error.HTTPError as erro:
        if erro.code == 400:
            # Termo que o ViaCEP recusa (caractere estranho no nome da via):
            # não é falha do serviço, só uma rua sem resposta.
            return []
        raise ErroMontagem(f"ViaCEP respondeu HTTP {erro.code}") from erro
    except (urllib.error.URLError, OSError, ValueError) as erro:
        raise ErroMontagem(f"ViaCEP indisponível ({erro})") from erro

    if not isinstance(dados, list):
        return []
    alvo = normalizar(nome)
    bairros = []
    for endereco in dados:
        if not isinstance(endereco, dict) or normalizar(endereco.get("logradouro")) != alvo:
            continue
        bairro = " ".join(str(endereco.get("bairro") or "").split())
        if bairro and bairro not in bairros:
            bairros.append(bairro)
    return bairros
