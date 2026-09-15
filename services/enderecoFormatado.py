"""Comparação de endereços e grafia formatada: reconhece que o endereço salvo
("RUA SAO VICENTE DE PAULA", bairro "VILA DAS GRACAS") é o mesmo que o
índice de ruas e o Photon escrevem ("Rua São Vicente de Paula", bairro "Vila
Nossa Senhora das Graças"), e devolve a grafia formatada.

COMPARAÇÃO. `normalizar_endereco` vai além de buscaCardapio.normalizar
(minúsculas, sem acento): pontuação vira espaço ("Arco-Iris" = "Arco Iris") e
as abreviações comuns viram a palavra inteira ("R." = "Rua", "Jd." =
"Jardim", "N. Sra." = "Nossa Senhora"). Tipo de via e de bairro só são
expandidos na primeira palavra: no meio, "R." é inicial de nome ("Rua José R.
Silva").

BAIRRO. Bairro escrito de outro jeito ("ARCO IRIS" e "Parque Arco Íris",
"Vila das Graças" e "Vila Nossa Senhora das Graças") só é considerado o mesmo
contra os bairros que o índice conhece PARA AQUELA RUA. Ignorar o prefixo na
cidade inteira juntaria lugares diferentes: em Taubaté, "Jardim Paulista" e
"Vila Paulista", "Parque São Jorge" e "Vila São Jorge". E um bairro vizinho
que o OSM associa à rua (a Rua Antônio Romero fica a 232 m do "Jardim
Garcez") não é apelido do oficial: vira o oficial só o bairro que casa com o
próprio nome oficial.

CHAVES. Nada aqui muda as chaves gravadas (historicoEnderecos.chave,
indiceRuas.chave_rua): elas são replicadas pela malha, e máquinas em versões
diferentes discordariam delas para sempre. Isto vale para comparar, exibir e
escolher a grafia que é gravada."""

import re

from services.buscaCardapio import normalizar

_APOSTROFO = re.compile(r"['’`´]")
_PONTUACAO = re.compile(r"[-.,/;:()]+")

# Só na primeira palavra.
_TIPOS_VIA = {
    "r": "rua", "av": "avenida", "al": "alameda", "pc": "praca", "pca": "praca",
    "rod": "rodovia", "tv": "travessa", "trav": "travessa", "est": "estrada",
}
_TIPOS_BAIRRO = {
    "jd": "jardim", "jdm": "jardim", "vl": "vila", "pq": "parque", "res": "residencial",
    "cj": "conjunto", "conj": "conjunto", "ch": "chacara", "chac": "chacara",
    "lot": "loteamento", "cond": "condominio",
}
# Em qualquer posição.
_TITULOS = {
    "dr": "doutor", "dra": "doutora", "prof": "professor", "profa": "professora",
    "sto": "santo", "sta": "santa", "pe": "padre", "cel": "coronel", "mal": "marechal",
    "eng": "engenheiro", "pres": "presidente", "sr": "senhor", "sra": "senhora",
}

# Palavras que não distinguem um bairro de outro com o mesmo nome.
_PALAVRAS_DE_TIPO = {
    "jardim", "vila", "parque", "residencial", "conjunto", "habitacional", "chacara",
    "chacaras", "loteamento", "condominio", "nucleo", "recanto", "sitio", "estancia",
}
_PARTICULAS = {"de", "da", "das", "do", "dos", "e"}


def normalizar_endereco(texto):
    """Forma comparável de rua ou bairro: sem caixa, acento e pontuação, e com
    as abreviações comuns por extenso."""
    base = _PONTUACAO.sub(" ", normalizar(_APOSTROFO.sub("", str(texto or ""))))
    saida = []
    for posicao, palavra in enumerate(base.split()):
        if posicao == 0 and palavra in _TIPOS_VIA:
            saida.append(_TIPOS_VIA[palavra])
            continue
        if posicao == 0 and palavra in _TIPOS_BAIRRO:
            saida.append(_TIPOS_BAIRRO[palavra])
            continue
        if palavra == "ns":
            saida.extend(("nossa", "senhora"))
            continue
        palavra = _TITULOS.get(palavra, palavra)
        if palavra == "senhora" and saida and saida[-1] in ("n", "nsa"):
            saida[-1] = "nossa"
        saida.append(palavra)
    return " ".join(saida)


def termos_de_busca(termo):
    """O termo digitado normalizado e, quando fica diferente, também com a
    abreviação resolvida ("jd gar" → "jardim gar"). Os dois, e não só o
    expandido: num começo de palavra a expansão erra ("pe" de "Pedro" viraria
    "padre")."""
    termos = []
    for candidato in (normalizar(termo), normalizar_endereco(termo)):
        if candidato and candidato not in termos:
            termos.append(candidato)
    return termos


def palavras_distintivas(texto):
    return frozenset(
        palavra for palavra in normalizar_endereco(texto).split()
        if palavra not in _PALAVRAS_DE_TIPO and palavra not in _PARTICULAS
    )


def bairros_equivalentes(a, b):
    """Mesmo bairro escrito de dois jeitos: iguais depois de normalizar, ou as
    palavras que distinguem um estão todas no outro ("Arco Iris" e "Parque
    Arco Íris"; "Vila das Graças" e "Vila Nossa Senhora das Graças"). Só faz
    sentido entre bairros da mesma rua (ver o topo)."""
    normal_a, normal_b = normalizar_endereco(a), normalizar_endereco(b)
    if not normal_a or not normal_b:
        return False
    if normal_a == normal_b:
        return True
    distintivas_a, distintivas_b = palavras_distintivas(a), palavras_distintivas(b)
    return bool(distintivas_a) and bool(distintivas_b) and (
        distintivas_a <= distintivas_b or distintivas_b <= distintivas_a
    )


def _unico_equivalente(bairro, candidatos):
    """O candidato equivalente a `bairro`, "" se nenhum, None se mais de um
    (ambíguo). Um igual depois de normalizar ganha dos que só casam por
    palavras."""
    casados = {}
    for candidato in candidatos:
        if candidato and bairros_equivalentes(bairro, candidato):
            casados.setdefault(normalizar_endereco(candidato), candidato)
    if not casados:
        return ""
    exato = casados.get(normalizar_endereco(bairro))
    if exato is not None:
        return exato
    return next(iter(casados.values())) if len(casados) == 1 else None


def escolher_bairro(bairro, oficiais=(), conhecidos=()):
    """A grafia formatada de `bairro` para uma rua cujos bairros oficiais
    (Correios) e conhecidos (OSM, Photon) são dados: o oficial equivalente;
    sem oficial equivalente, o conhecido equivalente; sem nenhum, ou com mais de
    um (avenida longa com vários bairros), o próprio `bairro`."""
    bairro = " ".join(str(bairro or "").split())
    if not bairro:
        return ""
    for grupo in (oficiais, conhecidos):
        escolhido = _unico_equivalente(bairro, grupo)
        if escolhido is None:
            return bairro
        if escolhido:
            return escolhido
    return bairro


def formatar_endereco(rua, bairro):
    """(rua, bairro) com a grafia do índice de ruas quando a rua está nele;
    sem índice em memória (ainda lendo na abertura) ou com a rua fora dele, os
    dois como vieram, só sem espaços sobrando. Roda na thread da interface,
    que é quem mexe no índice."""
    # Aqui dentro: o índice importa este módulo.
    from services.rede import indiceRuas

    rua = " ".join(str(rua or "").split())
    bairro = " ".join(str(bairro or "").split())
    if not rua or not indiceRuas.carregado():
        return rua, bairro
    referencia = indiceRuas.rua_equivalente(rua)
    if referencia is None:
        return rua, bairro
    return referencia["nome"], escolher_bairro(bairro, referencia["oficiais"], referencia["bairros"])
