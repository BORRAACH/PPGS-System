import os
import re
import shutil
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
    except FileNotFoundError:
        print(f"[printer/linux] Comando '{comando[0]}' não encontrado (CUPS/cups-client instalado?).")
        return ""
    except subprocess.TimeoutExpired:
        print(f"[printer/linux] Comando {comando} expirou (timeout de 10s).")
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


def _uri_normalizada(uri_dispositivo):
    """Remove a query string ("?serial=...", "?baud=...") de uma URI de
    dispositivo — só o necessário pra comparar "é o mesmo dispositivo",
    já que pequenas variações nesses parâmetros entre duas leituras (ex:
    o CUPS reencontrando o mesmo dispositivo depois de um replug) não
    mudam qual porta/aparelho é."""
    return (uri_dispositivo or "").split("?", 1)[0]


def _dispositivos_conectados_agora():
    """URIs (normalizadas) dos dispositivos que o CUPS enxerga fisicamente
    presentes AGORA, via `lpinfo -v` — diferente de `lpstat -v`, que só
    lista a porta configurada na fila (e continua listando mesmo com o
    aparelho desconectado, porque é config, não um scan ao vivo). `lpinfo
    -v` é o comando que faz o scan de verdade (usb/serial/rede), o mesmo
    usado normalmente pra achar impressoras na hora de instalar uma nova.

    Retorna None (distinto de um set vazio) se o utilitário `lpinfo` não
    está disponível — quem chama (coletar_impressoras) trata None como
    "não deu pra confirmar a liveness" e assume disponível por padrão, em
    vez de um set vazio genuíno (que significa "confirmado: nada
    conectado agora")."""
    if shutil.which("lpinfo") is None:
        return None

    saida = _executar(["lpinfo", "-v"])
    uris = set()
    for linha in saida.splitlines():
        m = re.match(r"\S+\s+(\S+)", linha.strip())
        if m:
            uris.add(_uri_normalizada(m.group(1)))
    return uris


def _descricao_e_status(nome_impressora):
    """Extrai (descricao/modelo, status, habilitada, caminho_ppd) via
    `lpstat -l -p <nome>`.

    `habilitada` é o mesmo "enabled"/"disabled" que já compunha `status`,
    mas como bool solto — usado por coletar_impressoras() como proxy tanto
    de "fila habilitada" quanto de "impressora ligada agora": o CUPS
    desabilita a fila sozinho quando um job de verdade falha no backend
    (ex: "Unable to open serial port" com a impressora desligada — ver
    _garantir_fila_habilitada), então uma fila "disabled" é o sinal mais
    barato disponível sem sondar a porta ou tentar imprimir de propósito só
    pra checar. Default True quando a regex não bate (saída vazia/CUPS
    fora do ar) — não dá pra confirmar desabilitada, então não assume."""
    saida = _executar(["lpstat", "-l", "-p", nome_impressora])
    descricao = ""
    status = ""
    habilitada = True
    caminho_ppd = ""

    # O texto muda de formato conforme o estado: uma fila habilitada tem um
    # motivo antes ("is idle.  enabled since ..."), mas uma desabilitada
    # não ("disabled since ..." — sem nada antes do "disabled"). O grupo
    # do motivo é opcional pra cobrir os dois formatos; sem isso, uma fila
    # desabilitada não batia com a regex nenhuma e o status ficava vazio
    # (escondendo justamente o estado que mais importa diagnosticar).
    m = re.search(r"^printer \S+ (?:(.+?)\.\s*)?(enabled|disabled)", saida, re.MULTILINE)
    if m:
        motivo = m.group(1)
        status = f"{motivo.strip()} ({m.group(2)})" if motivo else m.group(2)
        habilitada = m.group(2) == "enabled"

    m = re.search(r"Description:\s*(.+)", saida)
    if m:
        descricao = m.group(1).strip()

    m = re.search(r"Interface:\s*(\S+\.ppd)", saida)
    if m:
        caminho_ppd = m.group(1).strip()

    return descricao, status, habilitada, caminho_ppd


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


def _garantir_fila_habilitada(nome_impressora: str) -> None:
    """Reabilita `nome_impressora` se o CUPS a tiver desabilitado (pausada)
    — normalmente por causa de uma falha transitória do backend (ex: a
    porta serial não existia por um instante durante o boot ou um replug
    da USB, "Unable to open serial port"). O CUPS desabilita a fila
    sozinho após uma falha do tipo, mas NUNCA a reabilita sozinho mesmo
    com o problema já resolvido — sem isso, os jobs continuam sendo
    aceitos e enfileirados normalmente (`lp` retorna sucesso, o app "acha"
    que imprimiu), mas nunca chegam a sair no papel, ficando presos na
    fila pra sempre. Melhor esforço: se `cupsenable` falhar por qualquer
    motivo (ex: sem permissão), só loga um aviso — quem chama segue com o
    envio do job do mesmo jeito, exatamente como já fazia antes."""
    saida = _executar(["lpstat", "-p", nome_impressora])
    if not re.search(r"\bdisabled\b", saida):
        return

    print(f"[printer/linux] Fila '{nome_impressora}' está desabilitada — tentando reabilitar (cupsenable)...")
    try:
        resultado = subprocess.run(["cupsenable", nome_impressora], capture_output=True, text=True, timeout=10)
    except (FileNotFoundError, subprocess.TimeoutExpired) as erro:
        print(f"[printer/linux] Falha ao rodar 'cupsenable {nome_impressora}': {erro}")
        return

    if resultado.returncode == 0:
        print(f"[printer/linux] Fila '{nome_impressora}' reabilitada com sucesso.")
    else:
        print(f"[printer/linux] 'cupsenable {nome_impressora}' falhou: {resultado.stderr.strip()}")


def imprimir(nome_impressora: str, conteudo: bytes) -> None:
    """Envia `conteudo` (bytes crus, já formatados em ESC/POS) para a fila de
    impressão `nome_impressora` via CUPS, em modo raw (`lp -o raw`, sem
    reprocessamento pelo filtro do driver).

    Requer o utilitário `lp` (pacote cups-client) disponível. Levanta
    `RuntimeError` se o comando não existir, expirar ou a impressão falhar.
    """
    _garantir_fila_habilitada(nome_impressora)

    print(f"[printer/linux] Enviando {len(conteudo)} bytes para '{nome_impressora}' via 'lp -d {nome_impressora} -o raw'...")
    try:
        resultado = subprocess.run(
            ["lp", "-d", nome_impressora, "-o", "raw"],
            input=conteudo,
            capture_output=True,
            timeout=20,
        )
    except FileNotFoundError as erro:
        print("[printer/linux] Utilitário 'lp' não encontrado — o CUPS está instalado?")
        raise RuntimeError("Utilitário 'lp' não encontrado — o CUPS está instalado?") from erro
    except subprocess.TimeoutExpired as erro:
        print(f"[printer/linux] Tempo esgotado (20s) ao enviar para '{nome_impressora}'.")
        raise RuntimeError(f"Tempo esgotado ao enviar para a impressora '{nome_impressora}'.") from erro

    saida = resultado.stdout.decode(errors="replace").strip()
    mensagem = resultado.stderr.decode(errors="replace").strip()
    print(
        f"[printer/linux] 'lp' terminou com returncode={resultado.returncode}"
        + (f" stdout='{saida}'" if saida else "")
        + (f" stderr='{mensagem}'" if mensagem else "")
    )

    if resultado.returncode != 0:
        raise RuntimeError(f"Falha ao imprimir em '{nome_impressora}': {mensagem}")

    print(f"[printer/linux] Job aceito pela fila '{nome_impressora}' (id: {saida or 'desconhecido'}).")

    # 'lp' só confirma que o CUPS aceitou o job na fila — o envio de fato ao
    # backend (usb/socket/smb) acontece depois, de forma assíncrona. Se o
    # backend falhar (ex: credencial SMB inválida, impressora desligada), o
    # job fica preso como "pending"/"processing" sem que 'lp' veja isso; daí
    # a checagem abaixo logo em seguida, pra dar uma pista imediata.
    status_fila = _executar(["lpstat", "-o", nome_impressora])
    if status_fila.strip():
        print(f"[printer/linux] Fila '{nome_impressora}' logo após o envio:\n{status_fila.strip()}")


def coletar_impressoras():
    """Coleta informações das impressoras instaladas no CUPS (lpstat + PPD).

    Requer que o serviço `cups` esteja rodando e os utilitários `lpstat`
    disponíveis (padrão em praticamente toda distro com suporte a impressão).
    Se o CUPS não estiver rodando, retorna lista vazia.
    """
    nomes = _nomes_impressoras()
    if not nomes:
        print("[printer/linux] 'lpstat -p' não retornou nenhuma impressora instalada (CUPS rodando? impressora cadastrada?).")
        return []

    dispositivos = _dispositivos_por_impressora()
    padrao = _destino_padrao()
    # None = "lpinfo" indisponível, não deu pra confirmar liveness nenhuma
    # (ver _dispositivos_conectados_agora) — distinto de um set vazio, que
    # significa "confirmado: nenhum dispositivo usb/serial visto agora".
    dispositivos_vivos = _dispositivos_conectados_agora()
    print(f"[printer/linux] {len(nomes)} impressora(s) encontrada(s) via CUPS: {', '.join(nomes)} (padrão: {padrao or 'nenhuma'}).")

    impressoras = []
    for nome in nomes:
        uri_dispositivo = dispositivos.get(nome, "")
        descricao, status, habilitada, caminho_ppd = _descricao_e_status(nome)
        fabricante, modelo_ppd = _fabricante_e_modelo_do_ppd(caminho_ppd)
        tipo_porta = _classificar_porta(uri_dispositivo)

        # Só usb/serial precisam de confirmação de liveness: o tipo de
        # porta sozinho não muda quando o cabo é desconectado (a fila
        # continua configurada pra "usb://..."/"serial:/dev/ttyUSB0"),
        # então sem isso uma impressora usb instalada uma vez e nunca mais
        # conectada continuaria contando como candidata pra eleição de
        # rede (ver RedeService._detectar_impressora_em_thread).
        if tipo_porta == "serial":
            # Checagem real e sem exigir privilégio nenhum: o nó de
            # dispositivo (ex: /dev/ttyACM0/ttyUSB0) só existe enquanto o
            # cabo estiver conectado — o kernel/udev remove o nó na hora da
            # desconexão. Muito mais confiável que lpinfo -v aqui: como
            # usuário comum (sem root/lpadmin), lpinfo -v não sonda
            # dispositivos seriais/usb ao vivo de verdade — só devolve os
            # backends de rede sempre disponíveis ("network beh/http/.../
            # smb"), fazendo qualquer impressora serial de verdade plugada
            # parecer sempre desconectada (era exatamente esse o sintoma:
            # CUPS mostrando "enabled"/idle, mas disponivel sempre False).
            caminho_dispositivo = _extrair_porta(uri_dispositivo)
            conectada_agora = bool(caminho_dispositivo) and os.path.exists(caminho_dispositivo)
        elif tipo_porta == "usb" and dispositivos_vivos is not None:
            conectada_agora = _uri_normalizada(uri_dispositivo) in dispositivos_vivos
        else:
            conectada_agora = True

        # `habilitada` entra na mesma conta: além de conectada, a fila
        # precisa estar habilitada no CUPS — ver _descricao_e_status pra
        # como isso também funciona como proxy de "impressora ligada".
        disponivel = conectada_agora and habilitada

        print(f"[printer/linux] '{nome}': device-uri='{uri_dispositivo}' status='{status}' conectada_agora={conectada_agora} habilitada={habilitada} disponivel={disponivel}")

        impressoras.append(
            InfoImpressora(
                nome=nome,
                modelo=modelo_ppd or descricao,
                fabricante=fabricante,
                driver=caminho_ppd,
                porta=_extrair_porta(uri_dispositivo),
                tipo_porta=tipo_porta,
                status=status,
                padrao=(nome == padrao),
                disponivel=disponivel,
                bruto={
                    "uri_dispositivo": uri_dispositivo,
                    "descricao_cups": descricao,
                    "caminho_ppd": caminho_ppd,
                },
            )
        )

    return impressoras
