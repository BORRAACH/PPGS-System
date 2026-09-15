"""Validação do endereço de entrega pelo CEP, para o campo único de endereço da
Entrega (qml/components/DeliveryAddressValidator.qml).

FLUXO de validar(), cada consulta com TEMPO_LIMITE_S de espera:

1. Photon: o ponto do endereço. Quando o OSM tem a casa (a Rua Goiás tem o 229)
   vem a coordenada dela e, muitas vezes, o CEP; na maioria das ruas só existe
   a rua, e o ponto é o dela.
2. Nominatim reverse no ponto: o CEP de onde o ponto caiu. Só vale se a rua do
   reverse for a mesma: em Taubaté, um ponto poucos metros fora trouxe a
   Avenida Marechal Deodoro e o CEP dela.
3. ViaCEP por logradouro (UF/cidade/rua): os CEPs da rua sem depender do
   ponto. Rua com mais de um CEP traz a faixa de números de cada um no
   "complemento" ("até 766/767", "de 768/769 a 1750/1751", "de 1752/1753 ao
   fim"), e o número digitado escolhe (ver cep_da_rua).
4. ViaCEP pelo CEP: a confirmação oficial de logradouro, bairro, cidade e UF.
   CEP que não bate — de OUTRA rua, inexistente, o geral da cidade, ou de outra
   faixa de números da mesma rua — é trocado sozinho pelo CEP certo da rua, com
   um aviso do que foi corrigido. O conflito só fica para o atendente quando a
   rua não tem um CEP único para aquele número.
   O ViaCEP NÃO devolve número: o número é o digitado, e ganha o selo
   "confirmado no mapa" quando o Photon achou a casa.
5. Zona de entrega: tempo de rota de carro da pizzaria até o ponto, pelo grafo
   de ruas (services/grafoRuas.py), contra o limite da tela Rede.

Falha de rede não derruba nada: o resultado sai com o que deu para descobrir e
o status "atencao" ("Serviço indisponível — dados parciais").

Nada aqui toca em QObject: roda numa thread do ValidacaoEnderecoController. O
HTTP sai por services/requisicaoHttp.py, só com o Python (no Windows, o HTTPS
pelo Qt travava sem resposta)."""

import math
import re
import threading
import time
import unicodedata
import urllib.parse
from datetime import datetime, timezone

from services import requisicaoHttp
from services.buscaCardapio import normalizar
from services.enderecoFormatado import bairros_equivalentes, normalizar_endereco

_URL_PHOTON = "https://photon.komoot.io/api/"
_URL_NOMINATIM_REVERSE = "https://nominatim.openstreetmap.org/reverse"
_URL_VIACEP_CEP = "https://viacep.com.br/ws/{cep}/json/"
_URL_VIACEP_LOGRADOURO = "https://viacep.com.br/ws/{uf}/{cidade}/{logradouro}/json/"

# Espera máxima de cada consulta (conectar e cada leitura).
TEMPO_LIMITE_S = 5
LIMITE_ENTREGA_PADRAO_MIN = 25
LIMITE_SUGESTOES = 5
# Política de uso do Nominatim: no máximo uma requisição por segundo.
_INTERVALO_NOMINATIM_S = 1.0
_trava_nominatim = threading.Lock()
_ultimo_nominatim = [0.0]

STATUS_ERRO = "erro"
STATUS_INCOMPLETO = "incompleto"
STATUS_ATENCAO = "atencao"
STATUS_VALIDADO = "validado"

_PADRAO_NUMERO = re.compile(r"^\d{1,5}[A-Za-z]?$")
_SEM_NUMERO = ("s/n", "sn", "s n", "sem numero")
_PALAVRAS_CONDOMINIO = ("condominio", "residencial", "edificio", "bloco", "apto", "apartamento", "torre")
# Tipos de via ignorados ao comparar ruas: "Goiás" digitado é a "Rua Goiás".
_TIPOS_VIA = {"rua", "avenida", "travessa", "alameda", "praca", "rodovia", "estrada", "largo", "viela"}
# Estado por extenso, como a descrição da localização da pizzaria o traz
# ("Avenida dos Bombeiros, Areão, Taubaté, São Paulo"), para a UF.
_UF_POR_ESTADO = {
    "acre": "AC", "alagoas": "AL", "amapa": "AP", "amazonas": "AM", "bahia": "BA", "ceara": "CE",
    "distrito federal": "DF", "espirito santo": "ES", "goias": "GO", "maranhao": "MA",
    "mato grosso": "MT", "mato grosso do sul": "MS", "minas gerais": "MG", "para": "PA",
    "paraiba": "PB", "parana": "PR", "pernambuco": "PE", "piaui": "PI", "rio de janeiro": "RJ",
    "rio grande do norte": "RN", "rio grande do sul": "RS", "rondonia": "RO", "roraima": "RR",
    "santa catarina": "SC", "sao paulo": "SP", "sergipe": "SE", "tocantins": "TO",
}


# ---------- Texto ----------

def _limpo(texto):
    return " ".join(str(texto or "").split())


def _sem_acento(texto):
    decomposto = unicodedata.normalize("NFD", str(texto or ""))
    return "".join(c for c in decomposto if unicodedata.category(c) != "Mn")


def _float(valor):
    try:
        numero = float(valor)
    except (TypeError, ValueError):
        return None
    return numero if math.isfinite(numero) else None


def numero_valido(numero):
    numero = _limpo(numero)
    return numero.upper() == "S/N" or bool(_PADRAO_NUMERO.match(numero))


def cep_digitos(cep):
    return re.sub(r"\D", "", str(cep or ""))


def formatar_cep(cep):
    """"12062-130" a partir de qualquer grafia com 8 dígitos; "" se não tiver."""
    digitos = cep_digitos(cep)
    return f"{digitos[:5]}-{digitos[5:]}" if len(digitos) == 8 else ""


def _cep_util(cep):
    """CEP com 8 dígitos. O final -000 NÃO é descartado: em Taubaté 12080-000 e
    12031-000 são CEPs de rua (Marechal Deodoro, Independência). CEP de outra
    rua é pego e corrigido na confirmação pelo ViaCEP (ver validar)."""
    return len(cep_digitos(cep)) == 8


def _sem_tipo(rua_normalizada):
    palavras = rua_normalizada.split()
    return " ".join(palavras[1:]) if len(palavras) > 1 and palavras[0] in _TIPOS_VIA else rua_normalizada


def mesma_rua(a, b):
    """A mesma rua escrita de dois jeitos, com ou sem o tipo de via."""
    na, nb = normalizar_endereco(a), normalizar_endereco(b)
    if not na or not nb:
        return False
    return na == nb or _sem_tipo(na) == _sem_tipo(nb)


def _mesma_cidade(nome, cidade):
    return bool(cidade) and normalizar(nome) == normalizar(cidade)


def _tem_pista_de_condominio(*textos):
    normalizado = " " + normalizar_endereco(" ".join(_limpo(t) for t in textos)) + " "
    return any(f" {palavra} " in normalizado for palavra in _PALAVRAS_CONDOMINIO)


# CEP no meio do texto: "12062-130", "12062130", "CEP 12062-130".
_PADRAO_CEP_NO_TEXTO = re.compile(r"(?:\bcep\b\s*:?\s*)?\b(\d{5})-?(\d{3})\b", re.IGNORECASE)


def interpretar(texto):
    """{rua, numero, bairro, cep, pistaCondominio} do que foi digitado:
    "Rua Goiás, 196, Jardim Califórnia", "rua goias 196", "Rua Goiás, S/N", ou
    o endereço inteiro num campo só, no estilo do Google Maps: "Rua São Vicente
    de Paula, 311, Centro, 12020-000" — o CEP em qualquer parte, com ou sem
    hífen ou "CEP" na frente."""
    bruto = _limpo(texto)
    cep = ""
    achado = _PADRAO_CEP_NO_TEXTO.search(bruto)
    if achado:
        cep = f"{achado.group(1)}-{achado.group(2)}"
        bruto = _limpo(bruto[:achado.start()] + " " + bruto[achado.end():])
    partes = [_limpo(p) for p in bruto.split(",") if _limpo(p)]
    rua = partes[0] if partes else ""
    numero = ""
    bairro = ""

    for parte in partes[1:]:
        if not numero and (numero_valido(parte) or parte.lower() in _SEM_NUMERO):
            numero = parte
        elif not bairro:
            bairro = parte

    # Número colado no fim da rua, sem vírgula. A rua precisa sobrar com duas
    # palavras ou mais: "Rua 7" é o nome da rua, não a Rua de número 7.
    if not numero:
        colado = re.match(r"^(.*\D)\s+(\d{1,5}[A-Za-z]?)$", rua)
        if colado and len(colado.group(1).split()) >= 2:
            rua, numero = colado.group(1).strip(), colado.group(2)

    if numero.lower() in _SEM_NUMERO:
        numero = "S/N"
    return {
        "rua": rua,
        "numero": numero.upper(),
        "bairro": bairro,
        "cep": cep,
        "pistaCondominio": _tem_pista_de_condominio(bruto),
    }


def uf_da_localizacao(localizacao):
    """A UF do estabelecimento. O campo "uf" vem do índice de ruas, que nem
    sempre já está em memória; sem ele, sai da descrição da localização
    ("…, Taubaté, São Paulo") ou do endereço digitado na tela Rede ("… - SP").
    Sem UF o ViaCEP por logradouro não roda, e a Rua Goiás 196 (sem a casa no
    mapa) ficaria sem CEP."""
    localizacao = localizacao or {}
    uf = _limpo(localizacao.get("uf")).upper()
    if len(uf) == 2:
        return uf
    siglas = set(_UF_POR_ESTADO.values())
    for campo in ("descricao", "endereco"):
        texto = _limpo(localizacao.get(campo))
        if not texto:
            continue
        sigla = re.search(r"[-/,]\s*([A-Za-z]{2})\s*$", texto)
        if sigla and sigla.group(1).upper() in siglas:
            return sigla.group(1).upper()
        # De trás para frente: o estado é a última parte da descrição, e o
        # nome de uma cidade ou bairro igual ao de um estado vem antes.
        for parte in reversed(texto.split(",")):
            estado = " ".join(_sem_acento(parte).lower().split())
            if estado in _UF_POR_ESTADO:
                return _UF_POR_ESTADO[estado]
    return ""


def limite_entrega(localizacao):
    try:
        return int((localizacao or {}).get("limiteEntregaMin") or LIMITE_ENTREGA_PADRAO_MIN)
    except (TypeError, ValueError):
        return LIMITE_ENTREGA_PADRAO_MIN


# ---------- Consultas ----------

def _photon(consulta, localizacao, limite, camadas=()):
    """[(properties, [lon, lat])] do Photon, perto do estabelecimento."""
    parametros = [("q", consulta), ("limit", str(limite)), ("lang", "default")]
    lat, lon = _float((localizacao or {}).get("lat")), _float((localizacao or {}).get("lon"))
    if lat is not None and lon is not None:
        d = 0.15
        parametros += [
            ("lat", f"{lat:.6f}"),
            ("lon", f"{lon:.6f}"),
            ("bbox", f"{lon - d:.4f},{lat - d:.4f},{lon + d:.4f},{lat + d:.4f}"),
        ]
    parametros += [("layer", camada) for camada in camadas]
    dados = requisicaoHttp.obter_json(_URL_PHOTON, parametros, timeout=TEMPO_LIMITE_S)
    saida = []
    for feature in (dados or {}).get("features") or []:
        props = feature.get("properties") if isinstance(feature, dict) else None
        coordenadas = ((feature or {}).get("geometry") or {}).get("coordinates") or []
        if isinstance(props, dict) and len(coordenadas) >= 2:
            saida.append((props, coordenadas))
    return saida


def _nominatim_reverse(lat, lon):
    """O "address" do Nominatim no ponto. Respeita 1 requisição por segundo
    entre todas as threads."""
    with _trava_nominatim:
        espera = _INTERVALO_NOMINATIM_S - (time.monotonic() - _ultimo_nominatim[0])
        if espera > 0:
            time.sleep(espera)
        try:
            dados = requisicaoHttp.obter_json(
                _URL_NOMINATIM_REVERSE,
                {"lat": f"{lat:.7f}", "lon": f"{lon:.7f}", "zoom": "18", "format": "jsonv2",
                 "addressdetails": "1", "accept-language": "pt-BR"},
                timeout=TEMPO_LIMITE_S,
            )
        finally:
            _ultimo_nominatim[0] = time.monotonic()
    return (dados or {}).get("address") or {}


def _viacep_cep(cep):
    """O endereço oficial do CEP, ou None quando o ViaCEP não o conhece.
    CEP mal formatado sobe como ErroRequisicao com status 400."""
    dados = requisicaoHttp.obter_json(_URL_VIACEP_CEP.format(cep=cep_digitos(cep)), timeout=TEMPO_LIMITE_S)
    if not isinstance(dados, dict) or dados.get("erro"):
        return None
    return dados


def _viacep_logradouro(uf, cidade, rua):
    """Os CEPs que o ViaCEP conhece para a rua na cidade. A resposta traz toda
    rua que CONTÉM o termo; só ficam as de nome igual."""
    if len(normalizar(rua)) < 3:
        return []
    url = _URL_VIACEP_LOGRADOURO.format(
        uf=urllib.parse.quote(uf),
        cidade=urllib.parse.quote(_sem_acento(cidade)),
        logradouro=urllib.parse.quote(_sem_acento(rua), safe=""),
    )
    try:
        dados = requisicaoHttp.obter_json(url, timeout=TEMPO_LIMITE_S)
    except requisicaoHttp.ErroRequisicao as erro:
        if erro.status == 400:
            return []
        raise
    if not isinstance(dados, list):
        return []
    return [d for d in dados if isinstance(d, dict) and mesma_rua(d.get("logradouro"), rua)]


# ---------- CEP pela faixa de números ----------

_PADRAO_DE_A = re.compile(r"\bde\s+(\d+)(?:/(\d*))?\s+a\s+(\d+)(?:/(\d*))?")
_PADRAO_ATE = re.compile(r"\bate\s+(\d+)(?:/(\d*))?")
_PADRAO_DE = re.compile(r"\bde\s+(\d+)")
_PADRAO_UNICO = re.compile(r"^(\d+)$")


def _fim_do_par(primeiro, segundo):
    """Onde termina "766/767" (o lado par e o ímpar da mesma altura): no 767.
    O ViaCEP corta o complemento, e "1698/169" ou "1698/" chegam pela metade:
    aí o fim é o primeiro mais um. Sem barra, o próprio número."""
    inicio = int(primeiro)
    if segundo is None:
        return inicio
    if segundo and int(segundo) >= inicio:
        return int(segundo)
    return inicio + 1


def faixa_de_numeros(complemento):
    """(início, fim, lado) dos números que um CEP de rua atende, lido do
    "complemento" do ViaCEP. fim None = até o fim da rua; lado "par", "impar"
    ou None. Complemento vazio é a rua inteira: (0, None, None). None quando
    o texto não dá para ler — o fim cortado no meio ("de 791 a 120")."""
    texto = " ".join(_sem_acento(complemento).lower().split())
    # "(Bosque Flamboyant) - de 791 a 1209": o nome entre parênteses não é faixa.
    texto = re.sub(r"\([^)]*\)?", " ", texto).strip(" -")
    lado = "par" if re.search(r"\blado par\b", texto) else ("impar" if re.search(r"\blado impar\b", texto) else None)
    if not texto or re.fullmatch(r"lado (par|impar)", texto):
        return (0, None, lado)
    achado = _PADRAO_DE_A.search(texto)
    if achado:
        inicio, fim = int(achado.group(1)), _fim_do_par(achado.group(3), achado.group(4))
        return (inicio, fim, lado) if fim >= inicio else None
    achado = _PADRAO_ATE.search(texto)
    if achado:
        return (0, _fim_do_par(achado.group(1), achado.group(2)), lado)
    achado = _PADRAO_DE.search(texto)
    if achado:
        # "de 2221 ao fim", ou cortado antes do fim ("de 1700/1701").
        return (int(achado.group(1)), None, lado)
    achado = _PADRAO_UNICO.match(texto)
    if achado:
        # Um número só: CEP de grande usuário, naquele endereço exato.
        return (int(achado.group(1)), int(achado.group(1)), lado)
    return None


def _numero_na_faixa(numero, faixa):
    inicio, fim, lado = faixa
    if numero < inicio or (fim is not None and numero > fim):
        return False
    return lado is None or (numero % 2 == 0) == (lado == "par")


def cep_da_rua(candidatos, numero="", bairro=""):
    """O CEP da rua para o número, entre os `candidatos` do ViaCEP por
    logradouro (_viacep_logradouro), ou "" quando não dá para decidir sozinho.

    O único que a rua tem; senão o da faixa que contém o número — a mais
    estreita quando mais de uma contém ("1700" antes de "de 1700/1701 ao
    fim"), e, entre as abertas até o fim, a que começa mais perto ("de 2221
    ao fim" antes de "de 1700/1701"); no empate, ou sem número, o bairro."""
    ceps = {}
    for candidato in candidatos or []:
        cep = formatar_cep(candidato.get("cep"))
        if cep:
            ceps.setdefault(cep, candidato)
    if len(ceps) <= 1:
        return next(iter(ceps), "")

    def do_bairro(opcoes):
        iguais = [cep for cep, candidato in opcoes if bairro and bairros_equivalentes(bairro, candidato.get("bairro"))]
        return iguais[0] if len(iguais) == 1 else ""

    digitos = re.match(r"\d+", _limpo(numero))
    if digitos:
        n = int(digitos.group(0))
        na_faixa = []
        for cep, candidato in ceps.items():
            faixa = faixa_de_numeros(candidato.get("complemento"))
            if faixa is not None and _numero_na_faixa(n, faixa):
                largura = (faixa[1] if faixa[1] is not None else math.inf) - faixa[0]
                na_faixa.append(((largura, -faixa[0]), cep, candidato))
        if na_faixa:
            melhor = min(chave for chave, _, _ in na_faixa)
            empatados = [(cep, candidato) for chave, cep, candidato in na_faixa if chave == melhor]
            return empatados[0][0] if len(empatados) == 1 else do_bairro(empatados)
    return do_bairro(ceps.items())


# ---------- Sugestões ----------

def _sugestao(rua, numero, bairro, cidade, cep="", lat=None, lon=None, fonte="", condominio=False, casa=False):
    """Formato do ListaSugestoes: "nome" é a linha principal e "bairro" a de
    baixo; os dados de verdade vão nos outros campos."""
    titulo = f"{rua}, {numero}" if numero else rua
    return {
        "nome": titulo,
        "bairro": " • ".join(p for p in (bairro, cidade) if p),
        "rua": rua,
        "numero": numero,
        "bairroNome": bairro,
        "cidade": cidade,
        "cep": formatar_cep(cep),
        "latitude": lat,
        "longitude": lon,
        "fonte": fonte,
        "pistaCondominio": bool(condominio),
        "numeroNoMapa": bool(casa),
    }


def sugestoes_locais(texto, localizacao, locais):
    """As sugestões do histórico/índice de ruas (sem internet), com o número e
    as pistas do que foi digitado. `locais`: [{"nome", "bairro"}] de
    SugestoesEnderecoService._enderecos_locais, já com a grafia do índice —
    quem formata é o controller, na thread da interface (o índice só é lido
    nela; ver enderecoFormatado.formatar_endereco)."""
    info = interpretar(texto)
    cidade = _limpo((localizacao or {}).get("cidade"))
    saida = []
    vistos = set()
    for local in locais or []:
        chave = normalizar_endereco(local.get("nome")) + "|" + normalizar_endereco(local.get("bairro"))
        if not local.get("nome") or chave in vistos:
            continue
        vistos.add(chave)
        saida.append(_sugestao(local["nome"], info["numero"], local.get("bairro", ""), cidade,
                               fonte="local", condominio=info["pistaCondominio"]))
    return saida


def sugestoes(texto, localizacao, locais=(), limite=LIMITE_SUGESTOES):
    """(sugestões, aviso): as locais primeiro, depois as do Photon na cidade do
    estabelecimento, sem repetir rua+bairro. Sem internet, só as locais e o
    aviso."""
    info = interpretar(texto)
    cidade = _limpo((localizacao or {}).get("cidade"))
    saida = sugestoes_locais(texto, localizacao, locais)
    vistos = {normalizar_endereco(s["rua"]) + "|" + normalizar_endereco(s["bairroNome"]) for s in saida}
    aviso = ""

    if len(normalizar(info["rua"])) >= 3:
        numero_consulta = info["numero"] if info["numero"] and info["numero"] != "S/N" else ""
        consulta = " ".join(p for p in (info["rua"], numero_consulta, cidade) if p)
        try:
            features = _photon(consulta, localizacao, 15, ("street", "house"))
        except requisicaoHttp.ErroRequisicao as erro:
            features = []
            aviso = f"Busca de endereços indisponível ({erro}). Mostrando só os endereços já usados."
        for props, coordenadas in features:
            if cidade and not _mesma_cidade(props.get("city") or props.get("county"), cidade):
                continue
            casa = str(props.get("housenumber") or "").upper()
            rua = props.get("street") or (props.get("name") if props.get("osm_key") == "highway" else "")
            if not rua or (casa and casa != info["numero"]):
                continue
            bairro = props.get("district") or props.get("locality") or ""
            chave = normalizar_endereco(rua) + "|" + normalizar_endereco(bairro)
            if chave in vistos:
                continue
            vistos.add(chave)
            saida.append(_sugestao(
                rua, casa or info["numero"], bairro, cidade, props.get("postcode", ""),
                float(coordenadas[1]), float(coordenadas[0]), "photon",
                info["pistaCondominio"] or _tem_pista_de_condominio(props.get("name")) or props.get("osm_value") == "apartments",
                bool(casa),
            ))
    elif not saida:
        aviso = ""

    return saida[:limite], aviso


# ---------- Zona de entrega ----------

def tempo_de_rota_s(grafo, localizacao, lat, lon):
    """Segundos de carro da pizzaria até o ponto, ou None quando o ponto fica
    fora do mapa de ruas carregado (longe demais) ou não há caminho."""
    origem, _ = grafo.encaixar(float(localizacao["lat"]), float(localizacao["lon"]))
    destino, _ = grafo.encaixar(lat, lon)
    if origem is None or destino is None:
        return None
    resultado = grafo.caminho(origem, destino)
    return resultado[0] if resultado else None


# ---------- Validação ----------

def validar(escolha, numero, localizacao, obter_grafo=None):
    """O endereço estruturado e o veredito. `escolha`: a sugestão escolhida
    (ou {rua, bairro, cep} digitados; "cepDigitado" quando o CEP veio do
    atendente, e não da sugestão; "semZona" para não conferir a zona de
    entrega, no painel de rotas); `numero`: o do campo Número; `obter_grafo`:
    função que devolve o grafo de ruas já carregado, ou None."""
    escolha = dict(escolha or {})
    localizacao = dict(localizacao or {})
    cidade_est = _limpo(localizacao.get("cidade"))
    uf_est = uf_da_localizacao(localizacao)

    r = {
        "rua": _limpo(escolha.get("rua")),
        "numero": _limpo(numero) or _limpo(escolha.get("numero")),
        "bairro": _limpo(escolha.get("bairroNome") or escolha.get("bairro")),
        "cidade": cidade_est,
        "uf": uf_est,
        "cep": formatar_cep(escolha.get("cep")),
        "latitude": _float(escolha.get("latitude")),
        "longitude": _float(escolha.get("longitude")),
        "numeroConfirmadoNoMapa": False,
        "complementoObrigatorio": bool(escolha.get("pistaCondominio")),
        "tempoRotaMin": None,
        "zona": "nao_verificada",
        "limiteEntregaMin": limite_entrega(localizacao),
        "status": "",
        "mensagens": [],
        "validadoEm": "",
    }
    erros, faltas, atencoes, informacoes = [], [], [], []
    fora_do_ar = []
    achou_algo = r["latitude"] is not None
    # CEP que o atendente digitou: corrigido, ganha aviso; sem correção
    # possível, vira conflito para ele decidir. O que veio do mapa ou da
    # sugestão é trocado ou descartado em silêncio — ninguém o informou.
    cep_digitado = bool(escolha.get("cepDigitado")) and bool(r["cep"])
    cep_descartado = False

    if not r["rua"]:
        erros.append("Informe a rua do endereço de entrega.")
        return _fechar(r, erros, faltas, atencoes, informacoes)

    # --- Número (o ViaCEP não tem; é o digitado) ---
    if not r["numero"]:
        faltas.append("Por favor, informe o número da residência.")
    elif r["numero"].lower() in _SEM_NUMERO or r["numero"].upper() == "S/N":
        r["numero"] = "S/N"
    elif not numero_valido(r["numero"]):
        erros.append(f'Número "{r["numero"]}" inválido. Use só algarismos, com letra opcional (ex.: 196, 196A) ou S/N.')
    else:
        r["numero"] = r["numero"].upper()

    numero_para_mapa = r["numero"] if r["numero"] and r["numero"] != "S/N" and numero_valido(r["numero"]) else ""

    # --- 1. Photon: ponto da casa (ou da rua) ---
    try:
        casa = rua_do_mapa = None
        consulta = " ".join(p for p in (r["rua"], numero_para_mapa, cidade_est) if p)
        for props, coordenadas in _photon(consulta, localizacao, 8):
            if cidade_est and not _mesma_cidade(props.get("city") or props.get("county"), cidade_est):
                continue
            rua = props.get("street") or (props.get("name") if props.get("osm_key") == "highway" else "")
            if not mesma_rua(rua, r["rua"]):
                continue
            achou_algo = True
            numero_casa = str(props.get("housenumber") or "").upper()
            if numero_para_mapa and numero_casa == numero_para_mapa:
                casa = casa or (props, coordenadas)
            elif not numero_casa:
                rua_do_mapa = rua_do_mapa or (props, coordenadas)
        escolhido = casa or rua_do_mapa
        if escolhido:
            props, coordenadas = escolhido
            if casa or r["latitude"] is None:
                r["latitude"], r["longitude"] = float(coordenadas[1]), float(coordenadas[0])
            if casa:
                r["numeroConfirmadoNoMapa"] = True
                if _tem_pista_de_condominio(props.get("name")) or props.get("osm_value") == "apartments":
                    r["complementoObrigatorio"] = True
            if not r["cep"] and _cep_util(props.get("postcode")):
                r["cep"] = formatar_cep(props.get("postcode"))
            if not r["bairro"]:
                r["bairro"] = _limpo(props.get("district") or props.get("locality"))
    except requisicaoHttp.ErroRequisicao:
        fora_do_ar.append("mapa")

    # --- 2. Nominatim reverse no ponto ---
    if not r["cep"] and r["latitude"] is not None:
        try:
            endereco = _nominatim_reverse(r["latitude"], r["longitude"])
            if mesma_rua(endereco.get("road"), r["rua"]) and _cep_util(endereco.get("postcode")):
                r["cep"] = formatar_cep(endereco.get("postcode"))
        except requisicaoHttp.ErroRequisicao:
            fora_do_ar.append("Nominatim")

    # --- 3. ViaCEP pela rua ---
    # Os CEPs da rua são consultados uma vez só: o passo 4 os reaproveita para
    # corrigir um CEP que não bate.
    candidatos_rua = None

    def ceps_da_rua():
        nonlocal candidatos_rua
        if candidatos_rua is None:
            # Vazio antes da consulta: se ela cair, a correção não tenta de novo.
            candidatos_rua = []
            if uf_est and cidade_est:
                candidatos_rua = _viacep_logradouro(uf_est, cidade_est, r["rua"])
        return candidatos_rua

    def corrigir_cep(motivo):
        """Troca r["cep"] pelo CEP certo da rua para o número. Devolve o
        registro oficial do CEP novo, ou None quando a rua não tem um CEP
        único para aquele número (aí o conflito fica para o atendente)."""
        try:
            certo = cep_da_rua(ceps_da_rua(), r["numero"], r["bairro"])
            if not certo or certo == r["cep"]:
                return None
            novo = _viacep_cep(certo)
        except requisicaoHttp.ErroRequisicao:
            fora_do_ar.append("ViaCEP")
            return None
        if novo is None or not mesma_rua(novo.get("logradouro"), r["rua"]):
            return None
        if cep_digitado:
            informacoes.append(f"CEP corrigido para {certo}: o {motivo}")
        r["cepCorrigidoDe"] = r["cep"]
        r["cep"] = certo
        return novo

    if not r["cep"] and uf_est and cidade_est:
        try:
            candidatos = ceps_da_rua()
            if candidatos:
                achou_algo = True
            r["cep"] = cep_da_rua(candidatos, r["numero"], r["bairro"])
            if not r["cep"] and len({formatar_cep(c.get("cep")) for c in candidatos}) > 1:
                faltas.append("Esta rua tem mais de um CEP e o número não indica qual. Informe o CEP do endereço.")
        except requisicaoHttp.ErroRequisicao:
            fora_do_ar.append("ViaCEP")

    # --- 4. ViaCEP pelo CEP: a confirmação oficial ---
    # CEP que não bate não vira pergunta: o CEP certo da rua, pela faixa de
    # números, entra no lugar (ver corrigir_cep).
    confirmado_viacep = False
    if r["cep"]:
        try:
            oficial = _viacep_cep(r["cep"])
            # CEP de outra rua que não deu para corrigir: rua e bairro dele
            # não servem, ficam os que já se tinha.
            conflito = False
            if oficial is None:
                oficial = corrigir_cep(f"{r['cep']} não existe nos Correios.")
                if oficial is None and cep_digitado:
                    erros.append(f"CEP {r['cep']} não encontrado nos Correios. Confira o CEP.")
                elif oficial is None:
                    r["cep"], cep_descartado = "", True
            else:
                logradouro = _limpo(oficial.get("logradouro"))
                complemento_cep = _limpo(oficial.get("complemento"))
                faixa = faixa_de_numeros(complemento_cep) if logradouro else None
                digitos = re.match(r"\d+", r["numero"])
                if logradouro and not mesma_rua(logradouro, r["rua"]):
                    novo = corrigir_cep(f"{r['cep']} é da {logradouro}.")
                    if novo is None and cep_digitado:
                        conflito = True
                        atencoes.append(f"O CEP {r['cep']} é da {logradouro}, não da {r['rua']}, e não foi possível descobrir o CEP certo. Revise a rua ou o CEP.")
                    elif novo is None:
                        oficial, r["cep"], cep_descartado = None, "", True
                    else:
                        oficial = novo
                elif not logradouro:
                    # CEP geral da cidade, sem rua. Em cidade de CEP único não
                    # há outro, corrigir_cep devolve None, e ele fica.
                    novo = corrigir_cep(f"{r['cep']} é o CEP geral de {_limpo(oficial.get('localidade')) or 'da cidade'}.")
                    if novo is not None:
                        oficial = novo
                elif faixa is not None and digitos and not _numero_na_faixa(int(digitos.group(0)), faixa):
                    novo = corrigir_cep(f"{r['cep']} atende outra faixa de números da {logradouro} ({complemento_cep}).")
                    if novo is None and cep_digitado:
                        atencoes.append(f"O CEP {r['cep']} atende {complemento_cep} da {logradouro}, e o número {r['numero']} fica fora. Confira o número ou o CEP.")
                    elif novo is None:
                        oficial, r["cep"], cep_descartado = None, "", True
                    else:
                        oficial = novo
            if oficial is not None:
                confirmado_viacep = True
                achou_algo = True
                if not conflito:
                    if _limpo(oficial.get("logradouro")):
                        r["rua"] = _limpo(oficial.get("logradouro"))
                    if _limpo(oficial.get("bairro")):
                        r["bairro"] = _limpo(oficial.get("bairro"))
                localidade = _limpo(oficial.get("localidade"))
                if localidade:
                    if cidade_est and not _mesma_cidade(localidade, cidade_est):
                        atencoes.append(f"Este endereço fica em {localidade}, fora de {cidade_est}.")
                    r["cidade"] = localidade
                uf = _limpo(oficial.get("uf")).upper()
                if uf:
                    if uf_est and uf != uf_est:
                        atencoes.append(f"Este endereço fica em {uf}, fora de {uf_est}.")
                    r["uf"] = uf
        except requisicaoHttp.ErroRequisicao as erro:
            if erro.status == 400:
                erros.append(f"CEP {r['cep']} inválido.")
            else:
                fora_do_ar.append("ViaCEP")
        # O CEP do mapa não era desta rua e a rua não tem um CEP único para o
        # número. Sem número, a falta dele já está pedida — é o número que
        # decide o CEP na próxima validação.
        if cep_descartado and r["numero"] and not any("CEP" in f for f in faltas):
            faltas.append(f"Não foi possível descobrir o CEP da {r['rua']} para o número {r['numero']}. Informe o CEP do endereço.")
    elif not any("CEP" in f for f in faltas):
        if not achou_algo and not fora_do_ar:
            erros.append("Endereço não encontrado. Verifique a digitação, tente \"Rua, Bairro\" ou informe o CEP.")
        else:
            faltas.append("Não foi possível descobrir o CEP. Informe o CEP do endereço.")

    # --- 5. Zona de entrega ---
    if r["latitude"] is not None and obter_grafo is not None and localizacao.get("lat") is not None and not escolha.get("semZona"):
        grafo = obter_grafo()
        if grafo is not None:
            segundos = tempo_de_rota_s(grafo, localizacao, r["latitude"], r["longitude"])
            if segundos is None:
                r["zona"] = "fora"
                atencoes.append("Fora da zona de entrega: o endereço fica fora do mapa de ruas da região.")
            else:
                r["tempoRotaMin"] = round(segundos / 60, 1)
                if r["tempoRotaMin"] > r["limiteEntregaMin"]:
                    r["zona"] = "fora"
                    atencoes.append(f"Fora da zona de entrega: {r['tempoRotaMin']:.0f} min de carro (limite {r['limiteEntregaMin']} min).")
                else:
                    r["zona"] = "dentro"
        else:
            informacoes.append("Zona de entrega ainda não verificada (mapa de ruas carregando).")

    if fora_do_ar:
        atencoes.append("Serviço indisponível (" + ", ".join(dict.fromkeys(fora_do_ar)) + "). Dados parciais — revise antes de confirmar.")
    elif not confirmado_viacep and not erros and not faltas:
        atencoes.append("Endereço não validado oficialmente. Revise os dados.")
    if r["complementoObrigatorio"]:
        informacoes.append("Parece condomínio: informe o apartamento ou o bloco.")
    if r["numeroConfirmadoNoMapa"]:
        informacoes.append("Número confirmado no mapa.")

    return _fechar(r, erros, faltas, atencoes, informacoes)


def _fechar(r, erros, faltas, atencoes, informacoes):
    if erros:
        r["status"] = STATUS_ERRO
    elif faltas:
        r["status"] = STATUS_INCOMPLETO
    elif atencoes:
        r["status"] = STATUS_ATENCAO
    else:
        r["status"] = STATUS_VALIDADO
        r["validadoEm"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    r["mensagens"] = (
        [{"nivel": "erro", "texto": t} for t in erros]
        + [{"nivel": "incompleto", "texto": t} for t in faltas]
        + [{"nivel": "atencao", "texto": t} for t in atencoes]
        + [{"nivel": "info", "texto": t} for t in informacoes]
    )
    return r


def resultado_de_falha(escolha, numero, erro):
    """Resultado para uma falha inesperada (bug, não rede): o que foi digitado,
    com status de atenção, para o atendente conseguir seguir."""
    escolha = dict(escolha or {})
    r = {
        "rua": _limpo(escolha.get("rua")), "numero": _limpo(numero), "bairro": _limpo(escolha.get("bairroNome") or escolha.get("bairro")),
        "cidade": _limpo(escolha.get("cidade")), "uf": "", "cep": formatar_cep(escolha.get("cep")),
        "latitude": _float(escolha.get("latitude")), "longitude": _float(escolha.get("longitude")),
        "numeroConfirmadoNoMapa": False, "complementoObrigatorio": bool(escolha.get("pistaCondominio")),
        "tempoRotaMin": None, "zona": "nao_verificada", "limiteEntregaMin": LIMITE_ENTREGA_PADRAO_MIN,
        "validadoEm": "",
    }
    return _fechar(r, [], [], [f"Não foi possível validar agora ({erro}). Revise os dados."], [])
