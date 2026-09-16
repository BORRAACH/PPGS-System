"""Cadastro Nacional de Endereços para Fins Estatísticos (CNEFE) do Censo 2022,
do IBGE — os endereços da cidade da pizzaria, um por um, guardados nesta
máquina (ver o uso em services/validacaoEndereco.py e
controllers/validacaoEnderecoController.py).

POR QUE EXISTE. O OpenStreetMap (Photon, Nominatim, Overpass) conhece mal as
ruas de bairro: faltam ruas novas, e o bairro que ele dá é um palpite. O CNEFE
é a lista dos endereços que os recenseadores visitaram em 2022: em Taubaté,
155 mil, cada um com rua, número, CEP, localidade (o bairro) e coordenada. Com
ele, "Rua Goiás, 196" já sai com o bairro, o CEP e o ponto da casa, sem
internet e sem esperar o Photon.

DE ONDE VEM. Um .zip por município no FTP público do IBGE
(Arquivos_CNEFE/CSV/Municipio/<código da UF>_<UF>/<código>_<NOME>.zip), com um
CSV em ASCII (sem acento, em maiúsculas), separado por ";". O código do
município sai da API de localidades do IBGE, pelo nome da cidade e pela UF do
índice de ruas (services/rede/indiceRuas.py).

O QUE FICA. Um SQLite em pedidos/.sync/cnefe.sqlite, montado uma vez por
cidade (os dados do Censo não mudam), e não replicado pela malha: cada máquina
baixa o seu, ~3 MB para Taubaté. Duas tabelas:

- `casas`: um registro por rua e número, com o CEP e o bairro mais frequentes
  entre os domicílios daquele número, a coordenada média (só das de nível 1 a
  4 — ver _NIVEL_MAXIMO_COORDENADA) e se há mais de uma unidade (bloco,
  apartamento, casa 2), que é a pista de que falta o complemento;
- `trechos`: por rua, bairro e CEP, quantos endereços e de que número a que
  número — o que dá os bairros de uma rua quando o número ainda não foi
  digitado.

As ruas ficam também em memória (umas 3 mil em Taubaté) para a busca por
começo de palavra, que roda a cada tecla.

THREADS. A montagem roda numa thread (ver garantir). As consultas podem vir de
qualquer thread: cada uma abre a sua conexão, só de leitura, e a lista de ruas
em memória é trocada inteira sob uma trava."""

import collections
import csv
import io
import os
import re
import sqlite3
import threading
import time
import zipfile

from services import requisicaoHttp
from services.buscaCardapio import normalizar
from services.enderecoFormatado import normalizar_endereco, termos_de_busca
from services.rede import caminhos

_ROTULO = "cnefe"

# Muda quando o formato do banco muda: um banco de outra versão é refeito.
VERSAO_FORMATO = 1

_URL_MUNICIPIOS = "https://servicodados.ibge.gov.br/api/v1/localidades/estados/{uf}/municipios"
_URL_PASTA = (
    "https://ftp.ibge.gov.br/Cadastro_Nacional_de_Enderecos_para_Fins_Estatisticos/"
    "Censo_Demografico_2022/Arquivos_CNEFE/CSV/Municipio/{pasta}/"
)
_TIMEOUT_S = 60
# O zip de Taubaté tem 3,2 MB; o da capital paulista passa de 100 MB e
# levaria horas para virar banco na máquina fraca do balcão.
_LIMITE_ZIP_BYTES = 60 * 1_000_000

# NV_GEO_COORD: 1 a 3 são coordenadas do próprio endereço (original, ajustada
# entre apartamentos do mesmo número, estimada); 4 é a face de quadra; 5 e 6,
# a localidade e o setor inteiros — longe demais para a zona de entrega.
_NIVEL_MAXIMO_COORDENADA = 4
_NIVEL_MAXIMO_CASA = 3
# Complementos que indicam mais de uma unidade no mesmo número.
_COMPLEMENTOS_DE_UNIDADE = {"APARTAMENTO", "BLOCO", "EDIFICIO", "TORRE", "PREDIO", "CASA", "SALA", "LOJA", "CONJUNTO"}
# Número vizinho que ainda serve de estimativa (casa construída depois de 2022).
_DISTANCIA_MAXIMA_VIZINHO = 30
# De quantas em quantas linhas do CSV a montagem cede a vez à interface.
_LINHAS_POR_PAUSA = 5000

_PARTICULAS = {"de", "da", "das", "do", "dos", "e", "a", "o", "em"}
# I a XLIX: "Pio XII", "Dom Pedro II". Estrito, para "Civil" não virar "CIVIL".
_ROMANO = re.compile(r"^(?=[ivxl])(xl|l?x{0,3})(ix|iv|v?i{0,3})$")


def caminho_banco():
    return os.path.join(caminhos.pasta_sincronizacao(), "cnefe.sqlite")


def formatar_nome(texto):
    """"RUA SAO VICENTE DE PAULA" → "Rua Sao Vicente de Paula". O CSV não tem
    acento; quem põe é enderecoFormatado.formatar_endereco, com a grafia do
    índice de ruas quando é a mesma rua."""
    palavras = []
    for posicao, palavra in enumerate(" ".join(str(texto or "").split()).lower().split()):
        if posicao > 0 and palavra in _PARTICULAS:
            palavras.append(palavra)
        elif _ROMANO.match(palavra):
            palavras.append(palavra.upper())
        else:
            palavras.append(palavra[:1].upper() + palavra[1:])
    return " ".join(palavras)


def _sem_tipo(chave):
    """A chave comparável sem o tipo de via: "Goiás" digitado é a "Rua Goiás"."""
    palavras = chave.split()
    tipos = {"rua", "avenida", "travessa", "alameda", "praca", "rodovia", "estrada", "largo", "viela", "via", "caminho", "acesso"}
    return " ".join(palavras[1:]) if len(palavras) > 1 and palavras[0] in tipos else chave


# ---------- Download e montagem (numa thread) ----------

class ErroCnefe(Exception):
    pass


def codigo_municipio(cidade, uf):
    """O código IBGE de 7 dígitos da cidade, pela API de localidades."""
    try:
        municipios = requisicaoHttp.obter_json(_URL_MUNICIPIOS.format(uf=uf.lower()), timeout=_TIMEOUT_S)
    except requisicaoHttp.ErroRequisicao as erro:
        raise ErroCnefe(f"IBGE indisponível ({erro})") from erro
    alvo = normalizar(cidade)
    for municipio in municipios if isinstance(municipios, list) else []:
        if isinstance(municipio, dict) and normalizar(municipio.get("nome")) == alvo:
            return str(municipio.get("id") or "")
    raise ErroCnefe(f"{cidade}/{uf} não encontrada na lista de municípios do IBGE")


def url_do_arquivo(codigo, uf):
    """O endereço do .zip do município. O nome do arquivo leva o nome da
    cidade como o IBGE o escreve ("3554102_TAUBATE.zip"); em vez de adivinhar
    a grafia, ele é procurado na listagem da pasta da UF."""
    pasta = f"{codigo[:2]}_{uf.upper()}"
    url = _URL_PASTA.format(pasta=pasta)
    try:
        listagem = requisicaoHttp.obter_texto(url, timeout=_TIMEOUT_S)
    except requisicaoHttp.ErroRequisicao as erro:
        raise ErroCnefe(f"FTP do IBGE indisponível ({erro})") from erro
    achado = re.search(rf'href="({re.escape(codigo)}_[^"/]+\.zip)"', listagem, re.IGNORECASE)
    if not achado:
        raise ErroCnefe(f"arquivo do município {codigo} não encontrado no FTP do IBGE")
    return url + achado.group(1)


def _linhas_do_zip(caminho_zip):
    with zipfile.ZipFile(caminho_zip) as pacote:
        nomes = [n for n in pacote.namelist() if n.lower().endswith(".csv")]
        if not nomes:
            raise ErroCnefe("o arquivo do IBGE não tem CSV")
        with pacote.open(nomes[0]) as bruto:
            # ASCII na prática; latin-1 nunca falha, se algum dia vier acento.
            texto = io.TextIOWrapper(bruto, encoding="latin-1", newline="")
            yield from csv.DictReader(texto, delimiter=";")


def _inteiro(texto):
    try:
        return int(texto)
    except (TypeError, ValueError):
        return 0


def _float(texto):
    try:
        return float(texto)
    except (TypeError, ValueError):
        return None


def montar_banco(caminho_zip, destino, dados_meta, cancelado):
    """Lê o CSV de dentro do zip e grava o SQLite em `destino` (por um
    temporário, trocado no fim). Devolve quantos endereços foram lidos."""
    casas = {}
    trechos = {}
    total = 0
    for linha in _linhas_do_zip(caminho_zip):
        total += 1
        if total % _LINHAS_POR_PAUSA == 0:
            if cancelado.is_set():
                raise ErroCnefe("cancelado")
            time.sleep(0.001)
        rua = " ".join(p for p in (linha.get("NOM_TIPO_SEGLOGR"), linha.get("NOM_TITULO_SEGLOGR"), linha.get("NOM_SEGLOGR")) if p)
        rua = " ".join(rua.split())
        if not rua:
            continue
        bairro = " ".join(str(linha.get("DSC_LOCALIDADE") or "").split())
        cep = re.sub(r"\D", "", str(linha.get("CEP") or ""))
        cep = cep if len(cep) == 8 else ""
        numero = _inteiro(linha.get("NUM_ENDERECO"))
        sem_numero = numero <= 0 or str(linha.get("DSC_MODIFICADOR") or "").upper() in ("SN", "S/N")

        trecho = trechos.setdefault((rua, bairro, cep), [0, None, None])
        trecho[0] += 1
        if sem_numero:
            continue
        trecho[1] = numero if trecho[1] is None else min(trecho[1], numero)
        trecho[2] = numero if trecho[2] is None else max(trecho[2], numero)

        casa = casas.get((rua, numero))
        if casa is None:
            casa = casas[(rua, numero)] = {"n": 0, "nivel": 99, "lat": 0.0, "lon": 0.0, "pontos": 0,
                                          "ceps": collections.Counter(), "bairros": collections.Counter(), "unidade": False}
        casa["n"] += 1
        if cep:
            casa["ceps"][cep] += 1
        if bairro:
            casa["bairros"][bairro] += 1
        if str(linha.get("NOM_COMP_ELEM1") or "").upper() in _COMPLEMENTOS_DE_UNIDADE:
            casa["unidade"] = True
        nivel = _inteiro(linha.get("NV_GEO_COORD")) or 99
        lat, lon = _float(linha.get("LATITUDE")), _float(linha.get("LONGITUDE"))
        if lat is None or lon is None or nivel > _NIVEL_MAXIMO_COORDENADA or nivel > casa["nivel"]:
            continue
        if nivel < casa["nivel"]:
            casa["nivel"], casa["lat"], casa["lon"], casa["pontos"] = nivel, 0.0, 0.0, 0
        casa["lat"] += lat
        casa["lon"] += lon
        casa["pontos"] += 1

    if not casas:
        raise ErroCnefe("o arquivo do IBGE não trouxe nenhum endereço")

    temporario = f"{destino}.{os.getpid()}.tmp"
    try:
        os.remove(temporario)
    except OSError:
        pass
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    conexao = sqlite3.connect(temporario)
    try:
        conexao.executescript("""
            CREATE TABLE meta (chave TEXT PRIMARY KEY, valor TEXT);
            CREATE TABLE ruas (id INTEGER PRIMARY KEY, nome TEXT NOT NULL, chave TEXT NOT NULL, enderecos INTEGER NOT NULL);
            CREATE TABLE casas (rua INTEGER NOT NULL, numero INTEGER NOT NULL, cep TEXT, bairro TEXT,
                                lat REAL, lon REAL, nivel INTEGER, unidades INTEGER NOT NULL, condominio INTEGER NOT NULL,
                                PRIMARY KEY (rua, numero)) WITHOUT ROWID;
            CREATE TABLE trechos (rua INTEGER NOT NULL, bairro TEXT, cep TEXT, enderecos INTEGER NOT NULL,
                                  numero_min INTEGER, numero_max INTEGER);
            CREATE INDEX trechos_rua ON trechos (rua);
        """)
        ids = {}
        contagem = collections.Counter()
        for (rua, _bairro, _cep), (quantos, _minimo, _maximo) in trechos.items():
            contagem[rua] += quantos
        for rua, quantos in contagem.items():
            nome = formatar_nome(rua)
            ids[rua] = len(ids) + 1
            conexao.execute("INSERT INTO ruas VALUES (?, ?, ?, ?)", (ids[rua], nome, normalizar_endereco(nome), quantos))
        conexao.executemany(
            "INSERT INTO trechos VALUES (?, ?, ?, ?, ?, ?)",
            ((ids[rua], formatar_nome(bairro), cep, quantos, minimo, maximo)
             for (rua, bairro, cep), (quantos, minimo, maximo) in trechos.items()),
        )
        conexao.executemany(
            "INSERT INTO casas VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            ((ids[rua], numero,
              casa["ceps"].most_common(1)[0][0] if casa["ceps"] else "",
              formatar_nome(casa["bairros"].most_common(1)[0][0]) if casa["bairros"] else "",
              casa["lat"] / casa["pontos"] if casa["pontos"] else None,
              casa["lon"] / casa["pontos"] if casa["pontos"] else None,
              casa["nivel"] if casa["pontos"] else None,
              casa["n"], int(casa["unidade"] and casa["n"] > 1))
             for (rua, numero), casa in casas.items()),
        )
        conexao.executemany(
            "INSERT INTO meta VALUES (?, ?)",
            [(k, str(v)) for k, v in dict(dados_meta, versao=VERSAO_FORMATO, enderecos=total, montadoEm=int(time.time())).items()],
        )
        conexao.commit()
    finally:
        conexao.close()
    try:
        os.replace(temporario, destino)
    except OSError:
        try:
            os.remove(temporario)
        except OSError:
            pass
        raise
    return total


def baixar_e_montar(cidade, uf, cancelado):
    """Baixa o CNEFE de `cidade`/`uf` e monta o banco. Bloqueante — rode numa
    thread. Devolve a meta do banco novo; levanta ErroCnefe."""
    codigo = codigo_municipio(cidade, uf)
    url = url_do_arquivo(codigo, uf)
    destino = caminho_banco()
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    caminho_zip = f"{destino}.{os.getpid()}.zip"
    try:
        try:
            requisicaoHttp.baixar_arquivo(url, caminho_zip, timeout=_TIMEOUT_S, limite_bytes=_LIMITE_ZIP_BYTES, cancelado=cancelado)
        except requisicaoHttp.ErroRequisicao as erro:
            raise ErroCnefe(str(erro) if str(erro) == "cancelado" else f"download do IBGE falhou ({erro})") from erro
        try:
            montar_banco(caminho_zip, destino, {"cidade": cidade, "uf": uf.upper(), "municipio": codigo}, cancelado)
        except (zipfile.BadZipFile, csv.Error, sqlite3.Error) as erro:
            raise ErroCnefe(f"arquivo do IBGE ilegível ({erro})") from erro
    finally:
        try:
            os.remove(caminho_zip)
        except OSError:
            pass
    _descartar_cache()
    return meta()


# ---------- Consulta (qualquer thread) ----------

_trava = threading.Lock()
# (marca do arquivo, meta, [(chave, id, nome, enderecos)], {chave: [ids]}, {chave sem tipo: [ids]})
_cache = None


def _descartar_cache():
    global _cache
    with _trava:
        _cache = None


def _conectar():
    return sqlite3.connect(f"file:{caminho_banco()}?mode=ro", uri=True)


def _carregado():
    """O cache das ruas, relido quando o arquivo muda; None sem banco."""
    global _cache
    try:
        marca = os.stat(caminho_banco()).st_mtime_ns
    except OSError:
        return None
    with _trava:
        if _cache is not None and _cache[0] == marca:
            return _cache
    try:
        conexao = _conectar()
        try:
            dados_meta = dict(conexao.execute("SELECT chave, valor FROM meta"))
            ruas = conexao.execute("SELECT chave, id, nome, enderecos FROM ruas ORDER BY enderecos DESC").fetchall()
        finally:
            conexao.close()
    except sqlite3.Error as erro:
        print(f"[{_ROTULO}] Banco ilegível ({erro}) — ignorado até ser montado de novo.")
        return None
    if _inteiro(dados_meta.get("versao")) != VERSAO_FORMATO:
        return None
    por_chave = collections.defaultdict(list)
    por_sem_tipo = collections.defaultdict(list)
    for chave, id_rua, _nome, _enderecos in ruas:
        por_chave[chave].append(id_rua)
        por_sem_tipo[_sem_tipo(chave)].append(id_rua)
    novo = (marca, dados_meta, ruas, dict(por_chave), dict(por_sem_tipo))
    with _trava:
        _cache = novo
    return novo


def meta():
    """{"cidade", "uf", "municipio", "enderecos", ...} do banco, ou {}."""
    carregado = _carregado()
    return dict(carregado[1]) if carregado else {}


def disponivel_para(cidade, uf):
    """Há banco, do formato atual, e da cidade dada."""
    dados = meta()
    return bool(dados) and normalizar(dados.get("cidade")) == normalizar(cidade) and str(dados.get("uf", "")).upper() == str(uf or "").upper()


def _casa_termo(chave, termo):
    return f" {termo}" in f" {chave}"


def buscar_ruas(termo, limite=8):
    """[{"id", "nome"}] das ruas cujo nome casa com `termo` por começo de
    palavra; primeiro as que começam pelo termo (sem contar o tipo de via),
    depois as com mais endereços."""
    carregado = _carregado()
    termos = termos_de_busca(termo)
    if not carregado or not termos:
        return []
    comecam, outras = [], []
    for chave, id_rua, nome, _enderecos in carregado[2]:
        if not any(_casa_termo(chave, t) for t in termos):
            continue
        sem_tipo = _sem_tipo(chave)
        destino = comecam if any(chave.startswith(t) or sem_tipo.startswith(t) for t in termos) else outras
        destino.append({"id": id_rua, "nome": nome})
        if len(comecam) >= limite:
            break
    return (comecam + outras)[:limite]


def ids_da_rua(rua):
    """Os ids da rua com esse nome: pelo nome inteiro, ou sem o tipo de via
    quando o inteiro não casa ("Goiás" → "Rua Goiás")."""
    carregado = _carregado()
    chave = normalizar_endereco(rua)
    if not carregado or not chave:
        return []
    return carregado[3].get(chave) or carregado[4].get(_sem_tipo(chave)) or []


def bairros_da_rua(id_rua):
    """[{"bairro", "cep", "enderecos", "numeroMin", "numeroMax"}] de uma rua,
    do bairro com mais endereços para o com menos — um por bairro, com o CEP
    mais comum dele."""
    if not _carregado():
        return []
    conexao = _conectar()
    try:
        linhas = conexao.execute(
            "SELECT bairro, cep, enderecos, numero_min, numero_max FROM trechos WHERE rua = ? ORDER BY enderecos DESC",
            (id_rua,),
        ).fetchall()
    finally:
        conexao.close()
    saida = {}
    for bairro, cep, enderecos, minimo, maximo in linhas:
        if not bairro:
            continue
        atual = saida.get(bairro)
        if atual is None:
            saida[bairro] = {"bairro": bairro, "cep": cep or "", "enderecos": enderecos, "numeroMin": minimo, "numeroMax": maximo}
            continue
        atual["enderecos"] += enderecos
        if minimo is not None:
            atual["numeroMin"] = minimo if atual["numeroMin"] is None else min(atual["numeroMin"], minimo)
            atual["numeroMax"] = maximo if atual["numeroMax"] is None else max(atual["numeroMax"], maximo)
    return sorted(saida.values(), key=lambda b: b["enderecos"], reverse=True)


def casa(id_rua, numero):
    """O endereço de um número: {"numero", "cep", "bairro", "latitude",
    "longitude", "exato", "condominio"}. Sem o número exato no cadastro, o
    vizinho mais próximo (do mesmo lado da rua, se houver) a até
    _DISTANCIA_MAXIMA_VIZINHO, com "exato" False. None sem nada perto."""
    digitos = re.match(r"\d+", str(numero or "").strip())
    if not digitos or not _carregado():
        return None
    n = int(digitos.group(0))
    conexao = _conectar()
    try:
        linhas = conexao.execute(
            "SELECT numero, cep, bairro, lat, lon, nivel, condominio FROM casas WHERE rua = ? AND numero BETWEEN ? AND ?",
            (id_rua, n - _DISTANCIA_MAXIMA_VIZINHO, n + _DISTANCIA_MAXIMA_VIZINHO),
        ).fetchall()
    finally:
        conexao.close()
    if not linhas:
        return None
    # Exato primeiro; depois o mesmo lado da rua; depois o mais perto.
    numero_casa, cep, bairro, lat, lon, nivel, condominio = min(
        linhas, key=lambda l: (l[0] != n, (l[0] - n) % 2 != 0, abs(l[0] - n))
    )
    exato = numero_casa == n
    return {
        "numero": numero_casa,
        "cep": cep or "",
        "bairro": bairro or "",
        "latitude": lat,
        "longitude": lon,
        "exato": exato and nivel is not None and nivel <= _NIVEL_MAXIMO_CASA,
        "condominio": bool(condominio) and exato,
    }


def endereco(rua, numero):
    """casa() da rua pelo nome. Rua com mais de um registro de mesmo nome
    (a "Rua X" e a "Travessa X" digitadas só como "X"): vale a que tem o
    número exato, e só se for uma."""
    ids = ids_da_rua(rua)
    achados = [c for c in (casa(i, numero) for i in ids) if c]
    if len(achados) == 1:
        return achados[0]
    exatos = [c for c in achados if c["exato"]]
    return exatos[0] if len(exatos) == 1 else None


# ---------- Montagem em segundo plano ----------

_montando = threading.Event()


def garantir(cidade, uf, cancelado, ao_terminar):
    """Monta o banco da cidade numa thread, se ainda não há um dela.
    `ao_terminar(erro)` é chamado na thread da montagem ("" quando deu certo) —
    quem chama leva para a thread da interface. Devolve True quando começou."""
    if not cidade or len(str(uf or "")) != 2 or disponivel_para(cidade, uf) or _montando.is_set():
        return False
    _montando.set()

    def trabalho():
        erro = ""
        try:
            dados = baixar_e_montar(cidade, uf, cancelado)
            print(f"[{_ROTULO}] Cadastro do IBGE montado: {dados.get('enderecos')} endereços de {cidade}/{uf}.")
        except ErroCnefe as falha:
            erro = "" if str(falha) == "cancelado" else str(falha)
        except Exception as falha:  # a thread não pode morrer calada
            erro = repr(falha)
        finally:
            _montando.clear()
        if erro:
            print(f"[{_ROTULO}] Cadastro do IBGE não montado: {erro}")
        ao_terminar(erro)

    threading.Thread(target=trabalho, name="cnefe", daemon=True).start()
    return True


def montando():
    return _montando.is_set()
