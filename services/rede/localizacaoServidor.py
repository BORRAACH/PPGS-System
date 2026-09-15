"""Persistência de onde fica a pizzaria — o centro da região a que as
sugestões de endereço da Entrega se limitam (ver services/sugestoesEndereco.py).

Qualquer máquina a define — pela conexão de internet, quando nenhuma é
conhecida ainda, ou pelo endereço digitado na tela Rede — e a malha espalha a
escolha: evento de gossip mais campo no handshake, arbitrados por idEvento (ver
RedeService._aplicar_localizacao). Assim uma instalação nova, em outra
cidade, passa a sugerir as ruas da cidade dela sem ninguém mexer em código.

Por que ela importa tanto: sem um retângulo de busca, o Photon devolve
"Jardim Garcez" de Olímpia e a Rodovia Dutra para quem digitou "rua jose" em
Taubaté. O viés de proximidade dele sozinho não segura a região; o `bbox`
segura.

O arquivo local existe para uma máquina que liga sozinha ainda saber onde
está. Fica em Config/ (e na lista
de ignorados do dev_watch.py)."""

import math
import os

from services.rede import caminhos

_ARQUIVO = "localizacao_servidor.json"

_ROTULO = "localizacao servidor"

# Meia largura do retângulo de busca, em graus. 0.15° de latitude são ~16 km:
# cobre a cidade e o entorno imediato com folga, e ainda fica longe o
# bastante da cidade vizinha para ela não disputar as primeiras posições.
MEIA_LARGURA_BBOX = 0.15

_ORIGENS = ("manual", "ip")

# Até quantos minutos de carro a pizzaria entrega: a zona de entrega que o
# validador de endereço confere (ver services/validacaoEndereco.py). Definido na
# tela Rede e viajando junto com a localização.
LIMITE_ENTREGA_PADRAO_MIN = 25
LIMITE_ENTREGA_MINIMO_MIN = 5
LIMITE_ENTREGA_MAXIMO_MIN = 120


def _limite_entrega(valor) -> int:
    try:
        minutos = int(float(valor))
    except (TypeError, ValueError):
        return LIMITE_ENTREGA_PADRAO_MIN
    return max(LIMITE_ENTREGA_MINIMO_MIN, min(LIMITE_ENTREGA_MAXIMO_MIN, minutos))


def _caminho_arquivo() -> str:
    return os.path.join(caminhos.raiz_projeto(), "Config", _ARQUIVO)


def normalizar_registro(dados) -> dict:
    """O registro validado, ou {} se ele não servir (sem coordenadas finitas
    dentro do globo, ou sem idEvento para arbitrar). Tudo o que entra — do
    disco, de um peer, da detecção — passa por aqui antes de valer."""
    if not isinstance(dados, dict):
        return {}
    try:
        lat = float(dados.get("lat"))
        lon = float(dados.get("lon"))
    except (TypeError, ValueError):
        return {}
    if not (math.isfinite(lat) and math.isfinite(lon) and -90 <= lat <= 90 and -180 <= lon <= 180):
        return {}
    id_evento = str(dados.get("idEvento") or "")
    if not id_evento:
        return {}
    origem = dados.get("origem")
    return {
        # O que foi digitado na tela Rede ("" quando veio da detecção por IP).
        "endereco": str(dados.get("endereco") or ""),
        # Como o lugar é mostrado: "Avenida dos Bombeiros, Areão, Taubaté, São Paulo".
        "descricao": str(dados.get("descricao") or ""),
        "cidade": str(dados.get("cidade") or ""),
        "lat": lat,
        "lon": lon,
        "origem": origem if origem in _ORIGENS else "manual",
        # Registro de uma versão anterior (sem o campo) fica com o padrão.
        "limiteEntregaMin": _limite_entrega(dados.get("limiteEntregaMin")),
        "idEvento": id_evento,
    }


def carregar() -> dict:
    return normalizar_registro(caminhos.carregar_json(_caminho_arquivo(), _ROTULO))


def salvar(registro: dict) -> None:
    caminhos.salvar_json(_caminho_arquivo(), registro, _ROTULO)


def bbox(registro) -> str:
    """"minLon,minLat,maxLon,maxLat" em volta da localização, no formato do
    parâmetro `bbox` do Photon — ou "" sem localização conhecida."""
    registro = normalizar_registro(registro)
    if not registro:
        return ""
    lat, lon, d = registro["lat"], registro["lon"], MEIA_LARGURA_BBOX
    return f"{lon - d:.4f},{lat - d:.4f},{lon + d:.4f},{lat + d:.4f}"
