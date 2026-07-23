import os
import re
import subprocess

from .modelos import InfoImpressora


def _executar(comando):
    """Roda um comando externo forçando locale C, para saída em inglês
    (evita ter que lidar com "impressora"/"printer" dependendo do idioma
    do sistema). Retorna "" se o comando não existir ou falhar."""
    ambiente = os.environ.copy()
    ambiente["LC_ALL"] = "C"
    try:
        resultado = subprocess.run(
            comando,
            capture_output=True,
            text=True,
            env=ambiente,
            timeout=10,
        )
        return resultado.stdout
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""


def _classificar_porta(uri_dispositivo):
    if not uri_dispositivo:
        return "desconhecido"
    uri = uri_dispositivo.lower()
    if uri.startswith("usb:"):
        return "usb"
    if uri.startswith("serial:") or "/dev/tty" in uri:
        return "serial"
    if uri.startswith(("socket://", "ipp://", "ipps://", "http://", "https://", "lpd://", "dnssd://")):
        return "rede"
    return "desconhecido"


def _extrair_porta(uri_dispositivo):
    """Extrai um valor de porta legível a partir da URI de dispositivo do CUPS.

    Ex: "serial:/dev/ttyUSB0?baud=9600" -> "/dev/ttyUSB0"
        "usb://Bematech/MP-4200%20TH?serial=123" -> mantém a URI inteira
        "socket://192.168.0.50:9100" -> mantém a URI inteira
    """
    if not uri_dispositivo:
        return ""
    if uri_dispositivo.startswith("serial:"):
        return uri_dispositivo.split("serial:", 1)[1].split("?", 1)[0]
    return uri_dispositivo


def _dispositivos_por_impressora():
    """Mapa {nome_impressora: uri_dispositivo}, via `lpstat -v`."""
    saida = _executar(["lpstat", "-v"])
    dispositivos = {}
    for linha in saida.splitlines():
        m = re.match(r"device for ([^:]+):\s*(.+)", linha.strip())
        if m:
            dispositivos[m.group(1).strip()] = m.group(2).strip()
    return dispositivos


def _nomes_impressoras():
    """Lista de nomes de impressoras instaladas, via `lpstat -p`."""
    saida = _executar(["lpstat", "-p"])
    nomes = []
    for linha in saida.splitlines():
        m = re.match(r"printer (\S+)", linha.strip())
        if m:
            nomes.append(m.group(1))
    return nomes


def _destino_padrao():
    saida = _executar(["lpstat", "-d"])
    m = re.search(r"system default destination:\s*(\S+)", saida)
    return m.group(1) if m else None


def _descricao_e_status(nome_impressora):
    """Extrai (descricao/modelo, status, caminho_ppd) via `lpstat -l -p <nome>`."""
    saida = _executar(["lpstat", "-l", "-p", nome_impressora])
    descricao = ""
    status = ""
    caminho_ppd = ""

    m = re.search(r"^printer \S+ (.+?)\.\s*(enabled|disabled)", saida, re.MULTILINE)
    if m:
        status = f"{m.group(1).strip()} ({m.group(2)})"

    m = re.search(r"Description:\s*(.+)", saida)
    if m:
        descricao = m.group(1).strip()

    m = re.search(r"Interface:\s*(\S+\.ppd)", saida)
    if m:
        caminho_ppd = m.group(1).strip()

    return descricao, status, caminho_ppd


def _fabricante_e_modelo_do_ppd(caminho_ppd):
    """Lê `*Manufacturer` e `*NickName`/`*ModelName` de um PPD, se legível.

    O PPD nem sempre é legível pelo usuário comum dependendo da distro —
    nesse caso retorna ("", "") em vez de falhar.
    """
    if not caminho_ppd or not os.path.isfile(caminho_ppd):
        return "", ""
    try:
        with open(caminho_ppd, "r", encoding="utf-8", errors="replace") as arquivo:
            conteudo = arquivo.read()
    except (OSError, PermissionError):
        return "", ""

    fabricante, modelo = "", ""

    m = re.search(r'\*Manufacturer:\s*"([^"]+)"', conteudo)
    if m:
        fabricante = m.group(1)

    m = re.search(r'\*NickName:\s*"([^"]+)"', conteudo) or re.search(r'\*ModelName:\s*"([^"]+)"', conteudo)
    if m:
        modelo = m.group(1)

    return fabricante, modelo


def coletar_impressoras():
    """Coleta informações das impressoras instaladas no CUPS (lpstat + PPD).

    Requer que o serviço `cups` esteja rodando e os utilitários `lpstat`
    disponíveis (padrão em praticamente toda distro com suporte a impressão).
    Se o CUPS não estiver rodando, retorna lista vazia.
    """
    nomes = _nomes_impressoras()
    dispositivos = _dispositivos_por_impressora()
    padrao = _destino_padrao()

    impressoras = []
    for nome in nomes:
        uri_dispositivo = dispositivos.get(nome, "")
        descricao, status, caminho_ppd = _descricao_e_status(nome)
        fabricante, modelo_ppd = _fabricante_e_modelo_do_ppd(caminho_ppd)

        impressoras.append(
            InfoImpressora(
                nome=nome,
                modelo=modelo_ppd or descricao,
                fabricante=fabricante,
                driver=caminho_ppd,
                porta=_extrair_porta(uri_dispositivo),
                tipo_porta=_classificar_porta(uri_dispositivo),
                status=status,
                padrao=(nome == padrao),
                bruto={
                    "uri_dispositivo": uri_dispositivo,
                    "descricao_cups": descricao,
                    "caminho_ppd": caminho_ppd,
                },
            )
        )

    return impressoras
