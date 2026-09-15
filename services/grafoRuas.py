"""Grafo das ruas em volta da pizzaria e caminho mais rápido entre dois pontos:
a base da comparação de rotas de entrega da tela Mapa (qml/pages/mapa/Maps.qml,
controllers/rotasController.py).

MODELO. Grafo dirigido e ponderado:

- vértice: um nó do OpenStreetMap que pertence a uma via (cruzamento, curva,
  ponta de rua);
- aresta: o trecho entre dois nós seguidos de uma via, em cada sentido em que
  ela pode ser percorrida. Mão única vira uma aresta só;
- peso: o tempo do trecho, em segundos: a distância dividida pela velocidade da
  via (o maxspeed do OSM ou, sem ele, uma velocidade típica do tipo de via).

ALGORITMOS.

- Kosaraju, na montagem: acha as componentes fortemente conexas e fica só com
  a maior. Estacionamento, condomínio e mão única mal mapeada formam ilhas de
  onde não se sai (ou aonde não se chega), e um endereço encaixado numa delas
  daria "sem caminho". Dentro da maior componente, de qualquer vértice se
  chega a qualquer outro.
- A*, na consulta: Dijkstra guiado por uma estimativa do tempo que falta, a
  distância em linha reta até o destino dividida pela maior velocidade do
  grafo. Essa estimativa nunca passa do tempo real, então o caminho achado
  continua o mais rápido, e a busca abre bem menos vértices que o Dijkstra puro,
  que se espalha em círculo.
- Duas entregas: com a pizzaria P e as entregas A e B, uma viagem única só tem
  duas ordens (P→A→B→P e P→B→A→P). Comparar as duas já é a solução exata do
  caixeiro-viajante desse tamanho.

FORMATO. Lista de adjacência compacta (CSR): as arestas que saem do vértice v
ocupam as posições inicio[v] até inicio[v + 1] - 1 de destino, segundos e
metros. São listas simples de números: cabem num JSON, e o A* só indexa, sem um
objeto por aresta.

Nada aqui toca em QObject. Download, montagem e buscas rodam em thread (quem
chama é o RotasController)."""

import heapq
import math
import os
import time

from services import requisicaoHttp
from services.montadorIndiceRuas import _URLS_OVERPASS
from services.rede import caminhos

VERSAO_CACHE = 1
_ROTULO = "grafo ruas"

# Área baixada: 0,12° para cada lado da pizzaria (~13 km em latitude). Cobre a
# cidade e as entregas mais longas sem pesar demais o download (~10 MB).
MEIA_LARGURA_GRAUS = 0.12
_TIMEOUT_OVERPASS_S = 180
# O cache é refeito depois disto, ou se a pizzaria mudar de lugar.
_IDADE_MAXIMA_S = 60 * 24 * 3600
_DESLOCAMENTO_MAXIMO_M = 2000

# Endereço mais longe que isto do vértice mais próximo fica fora da área.
RAIO_MAXIMO_ENCAIXE_M = 400

# "A caminho": a segunda entrega atrasa no máximo isto por passar antes na
# primeira. São 5 min ou 25% da viagem direta até ela, o que for maior.
TOLERANCIA_DESVIO_S = 300
TOLERANCIA_DESVIO_FRACAO = 0.25

_METROS_POR_GRAU = 111_320
# Célula do índice espacial do encaixe: ~550 m.
_CELULA_GRAUS = 0.005

# Vias por onde a moto de entrega passa. Fora: calçada, trilha, ciclovia.
_TIPOS_VIA = (
    "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
    "secondary", "secondary_link", "tertiary", "tertiary_link", "unclassified",
    "residential", "living_street", "service", "road",
)

# km/h típicos na cidade para vias sem maxspeed.
_VELOCIDADE_KMH = {
    "motorway": 90, "motorway_link": 50, "trunk": 70, "trunk_link": 40,
    "primary": 50, "primary_link": 35, "secondary": 45, "secondary_link": 30,
    "tertiary": 40, "tertiary_link": 30, "unclassified": 30, "residential": 30,
    "living_street": 15, "service": 15, "road": 30,
}
_VELOCIDADE_PADRAO_KMH = 30


class ErroRota(Exception):
    pass


# ---------- Download ----------

def _consulta_overpass(lat, lon):
    sul, oeste = lat - MEIA_LARGURA_GRAUS, lon - MEIA_LARGURA_GRAUS
    norte, leste = lat + MEIA_LARGURA_GRAUS, lon + MEIA_LARGURA_GRAUS
    tipos = "|".join(_TIPOS_VIA)
    # `>;` traz os nós das vias, só com as coordenadas (`out skel`). Via
    # particular e corredor de estacionamento ficam de fora.
    return f"""[out:json][timeout:{_TIMEOUT_OVERPASS_S}];
way({sul:.5f},{oeste:.5f},{norte:.5f},{leste:.5f})["highway"~"^({tipos})$"]["access"!~"^(private|no)$"]["service"!~"^(parking_aisle|drive-through)$"]["area"!="yes"];
out body qt;
>;
out skel qt;"""


def baixar_elementos(lat, lon, cancelado):
    """Vias e nós do OSM em volta de (lat, lon). `cancelado`: threading.Event
    que interrompe antes de cada tentativa (fechamento do sistema)."""
    consulta = _consulta_overpass(lat, lon)
    ultimo_erro = None
    for url in _URLS_OVERPASS:
        if cancelado.is_set():
            raise ErroRota("cancelado")
        try:
            dados = requisicaoHttp.obter_json(url, formulario={"data": consulta}, timeout=_TIMEOUT_OVERPASS_S + 20)
        except requisicaoHttp.ErroRequisicao as erro:
            ultimo_erro = erro
            continue
        return dados.get("elements") or []
    raise ErroRota(f"Mapa de ruas indisponível ({ultimo_erro}).")


# ---------- Montagem ----------

def _distancia_m(lat1, lon1, lat2, lon2):
    # Aproximação plana: com trechos de metros a quilômetros, o erro diante
    # da distância no globo não aparece.
    dy = (lat2 - lat1) * _METROS_POR_GRAU
    dx = (lon2 - lon1) * _METROS_POR_GRAU * math.cos(math.radians((lat1 + lat2) / 2))
    return math.hypot(dx, dy)


def _sentidos(tags):
    """(ida, volta): em que sentidos a via pode ser percorrida, na ordem dos
    nós dela."""
    mao = str(tags.get("oneway") or "").lower()
    if mao in ("yes", "true", "1"):
        return True, False
    if mao in ("-1", "reverse"):
        return False, True
    if mao == "no":
        return True, True
    # Rotatória e rodovia são mão única mesmo sem a tag.
    if tags.get("junction") in ("roundabout", "circular") or tags.get("highway") == "motorway":
        return True, False
    return True, True


def _velocidade_kmh(tags):
    padrao = _VELOCIDADE_KMH.get(tags.get("highway"), _VELOCIDADE_PADRAO_KMH)
    bruto = str(tags.get("maxspeed") or "").split(";")[0].strip().lower()
    try:
        kmh = float(bruto.split()[0])
    except (ValueError, IndexError):
        return padrao
    if "mph" in bruto:
        kmh *= 1.609
    return kmh if 5 <= kmh <= 130 else padrao


def _maior_componente_forte(quantidade, arestas):
    """Lista de bool: o vértice está na maior componente fortemente conexa.

    Kosaraju, com as duas buscas em profundidade iterativas (a recursão
    estouraria a pilha do Python com dezenas de milhares de vértices):
    1. DFS no grafo, anotando a ordem em que cada vértice termina;
    2. DFS no grafo transposto, em ordem decrescente de término. Cada árvore
       dessa segunda busca é uma componente."""
    saida = [[] for _ in range(quantidade)]
    entrada = [[] for _ in range(quantidade)]
    for origem, destino, _s, _m in arestas:
        saida[origem].append(destino)
        entrada[destino].append(origem)

    visitado = bytearray(quantidade)
    ordem = []
    for raiz in range(quantidade):
        if visitado[raiz]:
            continue
        visitado[raiz] = 1
        pilha = [(raiz, 0)]
        while pilha:
            v, proxima = pilha[-1]
            if proxima < len(saida[v]):
                pilha[-1] = (v, proxima + 1)
                w = saida[v][proxima]
                if not visitado[w]:
                    visitado[w] = 1
                    pilha.append((w, 0))
            else:
                pilha.pop()
                ordem.append(v)

    componente = [-1] * quantidade
    tamanhos = []
    for raiz in reversed(ordem):
        if componente[raiz] != -1:
            continue
        numero = len(tamanhos)
        componente[raiz] = numero
        pilha = [raiz]
        tamanho = 0
        while pilha:
            v = pilha.pop()
            tamanho += 1
            for w in entrada[v]:
                if componente[w] == -1:
                    componente[w] = numero
                    pilha.append(w)
        tamanhos.append(tamanho)

    maior = max(range(len(tamanhos)), key=tamanhos.__getitem__)
    return [c == maior for c in componente]


def montar_grafo(elementos, centro):
    """Os dados do grafo (o dict que vai para o cache e para Grafo), a partir
    dos elementos devolvidos por baixar_elementos."""
    coordenadas = {}
    vias = []
    for elemento in elementos:
        tipo = elemento.get("type")
        if tipo == "node" and "lat" in elemento:
            coordenadas[elemento["id"]] = (elemento["lat"], elemento["lon"])
        elif tipo == "way" and len(elemento.get("nodes") or ()) >= 2:
            vias.append(elemento)

    vertice_de = {}
    lat, lon = [], []
    arestas = []
    velocidade_maxima_kmh = 0.0
    for via in vias:
        tags = via.get("tags") or {}
        ida, volta = _sentidos(tags)
        kmh = _velocidade_kmh(tags)
        velocidade_maxima_kmh = max(velocidade_maxima_kmh, kmh)
        velocidade = kmh / 3.6
        anterior = None
        for id_osm in via["nodes"]:
            ponto = coordenadas.get(id_osm)
            if ponto is None:
                anterior = None
                continue
            v = vertice_de.get(id_osm)
            if v is None:
                v = vertice_de[id_osm] = len(lat)
                lat.append(ponto[0])
                lon.append(ponto[1])
            if anterior is not None and anterior != v:
                metros = _distancia_m(lat[anterior], lon[anterior], lat[v], lon[v])
                segundos = metros / velocidade
                if ida:
                    arestas.append((anterior, v, segundos, metros))
                if volta:
                    arestas.append((v, anterior, segundos, metros))
            anterior = v

    if not arestas:
        raise ErroRota("O mapa não trouxe nenhuma rua perto da pizzaria.")

    manter = _maior_componente_forte(len(lat), arestas)
    novo = [-1] * len(lat)
    lat_final, lon_final = [], []
    for v, fica in enumerate(manter):
        if fica:
            novo[v] = len(lat_final)
            lat_final.append(round(lat[v], 7))
            lon_final.append(round(lon[v], 7))
    arestas = sorted(
        (novo[origem], novo[destino], segundos, metros)
        for origem, destino, segundos, metros in arestas
        if manter[origem] and manter[destino]
    )

    quantidade = len(lat_final)
    inicio = [0] * (quantidade + 1)
    for origem, _d, _s, _m in arestas:
        inicio[origem + 1] += 1
    for v in range(quantidade):
        inicio[v + 1] += inicio[v]

    return {
        "versao": VERSAO_CACHE,
        "centro": [centro[0], centro[1]],
        "baixadoEm": time.time(),
        "velocidadeMaxima": velocidade_maxima_kmh / 3.6,
        "lat": lat_final,
        "lon": lon_final,
        "inicio": inicio,
        "destino": [d for _o, d, _s, _m in arestas],
        "segundos": [round(s, 2) for _o, _d, s, _m in arestas],
        "metros": [round(m, 1) for _o, _d, _s, m in arestas],
    }


# ---------- Cache ----------

def _caminho_cache():
    return os.path.join(caminhos.pasta_sincronizacao(), "grafo_ruas.json")


def ler_cache(lat, lon):
    """O Grafo do cache, ou None se não há cache, se ele é de outra versão ou
    lugar, ou se está velho."""
    try:
        dados = caminhos.carregar_json(_caminho_cache(), _ROTULO)
    except Exception:
        return None
    if not isinstance(dados, dict) or dados.get("versao") != VERSAO_CACHE:
        return None
    try:
        centro = dados["centro"]
        if _distancia_m(centro[0], centro[1], lat, lon) > _DESLOCAMENTO_MAXIMO_M:
            return None
        if time.time() - float(dados["baixadoEm"]) > _IDADE_MAXIMA_S:
            return None
        return Grafo(dados)
    except (KeyError, TypeError, ValueError, IndexError):
        return None


def salvar_cache(dados):
    os.makedirs(os.path.dirname(_caminho_cache()), exist_ok=True)
    caminhos.salvar_json(_caminho_cache(), dados, _ROTULO, compacto=True)


# ---------- Consulta ----------

class Grafo:
    def __init__(self, dados):
        self.lat = dados["lat"]
        self.lon = dados["lon"]
        self.inicio = dados["inicio"]
        self.destino = dados["destino"]
        self.segundos = dados["segundos"]
        self.metros = dados["metros"]
        self.velocidade_maxima = float(dados["velocidadeMaxima"])
        if len(self.inicio) != len(self.lat) + 1 or not (len(self.destino) == len(self.segundos) == len(self.metros)):
            raise ValueError("grafo inconsistente")
        # Índice espacial: célula da grade → vértices dentro dela.
        self._grade = {}
        for v, (la, lo) in enumerate(zip(self.lat, self.lon)):
            chave = (math.floor(la / _CELULA_GRAUS), math.floor(lo / _CELULA_GRAUS))
            self._grade.setdefault(chave, []).append(v)

    def __len__(self):
        return len(self.lat)

    def encaixar(self, lat, lon):
        """(vértice, distância em metros) do vértice mais próximo do ponto, ou
        (None, distância) se ele passa de RAIO_MAXIMO_ENCAIXE_M. A distância é
        infinita quando nem as células vizinhas têm vértice."""
        linha, coluna = math.floor(lat / _CELULA_GRAUS), math.floor(lon / _CELULA_GRAUS)
        fator_x = _METROS_POR_GRAU * math.cos(math.radians(lat))
        # Células vizinhas suficientes para cobrir o raio (em longitude elas
        # são mais estreitas que em latitude).
        alcance = math.ceil(RAIO_MAXIMO_ENCAIXE_M / (_CELULA_GRAUS * fator_x))
        melhor, melhor_quadrado = None, math.inf
        for dl in range(-alcance, alcance + 1):
            for dc in range(-alcance, alcance + 1):
                for v in self._grade.get((linha + dl, coluna + dc), ()):
                    dy = (self.lat[v] - lat) * _METROS_POR_GRAU
                    dx = (self.lon[v] - lon) * fator_x
                    quadrado = dx * dx + dy * dy
                    if quadrado < melhor_quadrado:
                        melhor, melhor_quadrado = v, quadrado
        distancia = math.sqrt(melhor_quadrado)
        if melhor is None or distancia > RAIO_MAXIMO_ENCAIXE_M:
            return None, distancia
        return melhor, distancia

    def caminho(self, origem, destino):
        """(segundos, metros, [vértices]) do caminho mais rápido de origem até
        destino, ou None se não existe. É o A*."""
        lat, lon = self.lat, self.lon
        inicio, destinos, segundos = self.inicio, self.destino, self.segundos
        lat_destino, lon_destino = lat[destino], lon[destino]
        fator_y = _METROS_POR_GRAU
        fator_x = _METROS_POR_GRAU * math.cos(math.radians(lat_destino))
        # Estimativa = linha reta ÷ velocidade máxima. O 0,99 é margem para os
        # arredondamentos do cache: a estimativa precisa ficar abaixo do tempo
        # real para o caminho sair ótimo.
        inverso_velocidade = 0.99 / self.velocidade_maxima

        custo = {origem: 0.0}
        anterior = {origem: -1}
        fila = [(0.0, 0.0, origem)]
        while fila:
            _estimado, g, v = heapq.heappop(fila)
            if v == destino:
                break
            if g > custo[v]:
                continue  # entrada velha: v já saiu da fila com custo menor
            for i in range(inicio[v], inicio[v + 1]):
                w = destinos[i]
                novo = g + segundos[i]
                if novo < custo.get(w, math.inf):
                    custo[w] = novo
                    anterior[w] = v
                    dx = (lon[w] - lon_destino) * fator_x
                    dy = (lat[w] - lat_destino) * fator_y
                    heapq.heappush(fila, (novo + math.sqrt(dx * dx + dy * dy) * inverso_velocidade, novo, w))
        else:
            return None

        vertices = []
        v = destino
        while v != -1:
            vertices.append(v)
            v = anterior[v]
        vertices.reverse()
        metros = sum(self._metros_do_trecho(a, b) for a, b in zip(vertices, vertices[1:]))
        return custo[destino], metros, vertices

    def _metros_do_trecho(self, origem, destino):
        # Entre dois vértices pode haver mais de uma aresta (duas vias
        # sobrepostas no mapa): vale a mais rápida, a mesma que o A* usou.
        melhor_segundos, melhor_metros = math.inf, 0.0
        for i in range(self.inicio[origem], self.inicio[origem + 1]):
            if self.destino[i] == destino and self.segundos[i] < melhor_segundos:
                melhor_segundos, melhor_metros = self.segundos[i], self.metros[i]
        return melhor_metros

    def plano(self, vertices):
        """[lat, lon, lat, lon, ...] dos vértices: o traçado que o QML desenha."""
        saida = []
        for v in vertices:
            saida.append(self.lat[v])
            saida.append(self.lon[v])
        return saida


def comparar_entregas(grafo, pizzaria, entrega_a, entrega_b):
    """Duas viagens (P→A→P e P→B→P) contra uma só, na melhor das duas ordens.
    Cada ponto é (lat, lon). Devolve o dict que o Maps.qml mostra; levanta
    ErroRota se um ponto cai fora do mapa."""
    pontos = (("P", "A pizzaria", pizzaria), ("A", "A entrega A", entrega_a), ("B", "A entrega B", entrega_b))
    vertice = {}
    for letra, nome, (lat, lon) in pontos:
        v, distancia = grafo.encaixar(lat, lon)
        if v is None:
            if math.isinf(distancia):
                raise ErroRota(f"{nome} fica fora da área do mapa de ruas.")
            raise ErroRota(f"{nome} fica a {distancia:.0f} m da rua mais próxima do mapa.")
        vertice[letra] = v

    trechos = {}
    for par in ("PA", "AP", "PB", "BP", "AB", "BA"):
        resultado = grafo.caminho(vertice[par[0]], vertice[par[1]])
        if resultado is None:
            raise ErroRota(f"Não há caminho de {par[0]} até {par[1]} pelo mapa de ruas.")
        trechos[par] = resultado

    def somar(pares, campo):
        return sum(trechos[p][campo] for p in pares)

    def tracado(pares):
        vertices = list(trechos[pares[0]][2])
        for par in pares[1:]:
            vertices.extend(trechos[par][2][1:])
        return grafo.plano(vertices)

    separadas = ("PA", "AP", "PB", "BP")
    ordens = {"AB": ("PA", "AB", "BP"), "BA": ("PB", "BA", "AP")}
    melhor = min(ordens, key=lambda ordem: somar(ordens[ordem], 0))
    outra = "BA" if melhor == "AB" else "AB"
    primeira, segunda = melhor[0], melhor[1]

    # Quanto a segunda entrega chega mais tarde por passar antes na primeira.
    direta = trechos["P" + segunda][0]
    desvio = max(0.0, trechos["P" + primeira][0] + trechos[primeira + segunda][0] - direta)
    limite = max(TOLERANCIA_DESVIO_S, TOLERANCIA_DESVIO_FRACAO * direta)

    segundos_separadas = somar(separadas, 0)
    segundos_juntas = somar(ordens[melhor], 0)
    return {
        "separadas": {
            "segundos": segundos_separadas,
            "metros": somar(separadas, 1),
            "rotaA": tracado(("PA", "AP")),
            "rotaB": tracado(("PB", "BP")),
        },
        "juntas": {
            "segundos": segundos_juntas,
            "metros": somar(ordens[melhor], 1),
            "ordem": melhor,
            "rota": tracado(ordens[melhor]),
        },
        "outraOrdem": {
            "segundos": somar(ordens[outra], 0),
            "metros": somar(ordens[outra], 1),
            "ordem": outra,
        },
        "desvio": {"segundos": desvio, "limite": limite, "primeira": primeira, "segunda": segunda},
        "aCaminho": desvio <= limite,
        "economiaSegundos": segundos_separadas - segundos_juntas,
    }
