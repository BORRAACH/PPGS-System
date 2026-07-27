import json
import re
import shutil
import socket
import subprocess

from .modelos import InfoImpressora, eh_bematech_mp4200th

# Timeout das checagens de rede "cruas" (socket direto, sem passar pela
# fila do spooler — ver _verificar_conexao_tcp/_consultar_status_esc_pos_tcp).
# Mais curto que o da sondagem via spooler porque aqui é só um connect/send/
# recv direto, sem overhead de StartDocPrinter/StartPagePrinter.
_TIMEOUT_REDE_S = 1.5

# Porta TCP/IP padrão de fato pra impressoras térmicas ESC/POS em modo
# JetDirect/RAW, usada quando o Windows não expõe PortNumber (Get-PrinterPort
# nem sempre preenche essa propriedade dependendo de como a porta foi criada).
_PORTA_TCP_PADRAO = 9100

# PortName costuma bastar para classificar o tipo de porta no Windows:
# "COM3" (serial), "USB001" (usb), "192.168.0.50" ou "IP_192.168.0.50"/"WSD-..." (rede).
_PADROES_TIPO_PORTA = (
    (re.compile(r"^COM\d+", re.IGNORECASE), "serial"),
    (re.compile(r"USB", re.IGNORECASE), "usb"),
    (re.compile(r"^\d{1,3}(\.\d{1,3}){3}"), "rede"),
    (re.compile(r"IP_|WSD|TCP", re.IGNORECASE), "rede"),
)

# Host de porta de rede em formato IPv4 puro — usado pra decidir se vale a
# pena tentar um socket TCP direto (ver _verificar_conexao_tcp). Portas WSD
# ou baseadas em hostname não garantem um simples socket TCP/IP na porta
# reportada, então ficam de fora dessa checagem extra.
_PADRAO_IPV4 = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")

# Consulta Win32_Printer (impressoras instaladas) e complementa com
# Get-PrinterPort/Get-PrinterDriver para pegar host de rede e fabricante do
# driver, e Get-Printer (módulo PrintManagement, nativo desde Windows 8/
# Server 2012) só para o PrinterStatus amigável — é o único lugar que
# expõe "Paused" como string pronta; o PrinterStatus do Win32_Printer é um
# enum numérico diferente (Idle/Printing/.../Offline), sem noção de fila
# pausada pelo administrador.
_SCRIPT_PS = r"""
$impressoras = Get-CimInstance -ClassName Win32_Printer | ForEach-Object {
    $printer = $_
    $porta = Get-PrinterPort -Name $printer.PortName -ErrorAction SilentlyContinue
    $driver = Get-PrinterDriver -Name $printer.DriverName -ErrorAction SilentlyContinue
    $gerenciada = Get-Printer -Name $printer.Name -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Nome              = $printer.Name
        Driver            = $printer.DriverName
        PortName          = $printer.PortName
        PortaHost         = $porta.PrinterHostAddress
        PortaNumero       = $porta.PortNumber
        PortaDescricao    = $porta.Description
        Status            = $printer.PrinterStatus
        ForaDeLinha       = [bool]$printer.WorkOffline
        Pausada           = ($gerenciada.PrinterStatus -eq "Paused")
        Padrao            = [bool]$printer.Default
        Local             = [bool]$printer.Local
        Rede              = [bool]$printer.Network
        Compartilhada     = [bool]$printer.Shared
        Comentario        = $printer.Comment
        Localizacao       = $printer.Location
        DriverFabricante  = $driver.Manufacturer
        DriverVersaoMaior = $driver.MajorVersion
    }
}
$impressoras | ConvertTo-Json -Depth 4
"""


def _executavel_powershell():
    for candidato in ("powershell", "powershell.exe", "pwsh", "pwsh.exe"):
        caminho = shutil.which(candidato)
        if caminho:
            return caminho
    return None


def _executar_powershell():
    executavel = _executavel_powershell()
    if not executavel:
        print("[printer/windows] Nenhum executável de PowerShell encontrado (powershell/pwsh) no PATH.")
        return ""
    try:
        resultado = subprocess.run(
            [executavel, "-NoProfile", "-NonInteractive", "-Command", _SCRIPT_PS],
            capture_output=True,
            text=True,
            timeout=20,
        )
        if resultado.returncode != 0:
            print(f"[printer/windows] PowerShell terminou com returncode={resultado.returncode}: {resultado.stderr.strip()}")
        return resultado.stdout
    except subprocess.TimeoutExpired:
        print("[printer/windows] PowerShell expirou (timeout de 20s) ao consultar Win32_Printer.")
        return ""


def _classificar_porta(nome_porta, host_porta=""):
    alvo = nome_porta or ""
    for padrao, tipo in _PADROES_TIPO_PORTA:
        if padrao.search(alvo):
            return tipo
    if host_porta:
        return "rede"
    return "desconhecido"


def _verificar_conexao_tcp(host: str, porta: int, timeout: float = _TIMEOUT_REDE_S) -> bool:
    """Tenta abrir de verdade um socket TCP em `host:porta` — diferente de
    `tipo_porta`/`WorkOffline`, que são só metadado/config reportados pelo
    Windows, isto é uma tentativa real de conexão. Usado pra confirmar (ou
    desmentir) o status que o spooler reporta pra impressoras de rede, cujo
    WorkOffline costuma ficar desatualizado (ver coletar_impressoras)."""
    try:
        with socket.create_connection((host, porta), timeout=timeout):
            return True
    except OSError as erro:
        print(f"[printer/windows] Conexão TCP para {host}:{porta} falhou: {erro}")
        return False


def _consultar_status_esc_pos_tcp(host: str, porta: int, timeout: float = _TIMEOUT_REDE_S):
    """Igual a `_consultar_status_esc_pos`, mas manda "DLE EOT 1" direto por
    um socket TCP cru (host:porta), sem passar pela fila do spooler — não
    depende do estado que o Windows reporta (WorkOffline/Paused), então
    continua funcionando mesmo quando esse status está desatualizado.

    Mesma semântica de retorno da função irmã: True (online), False (a
    impressora respondeu que está offline) ou None quando não dá pra
    confirmar (timeout, conexão recusada, resposta vazia) — None nunca
    piora a disponibilidade já calculada, só confirma quando decide algo.
    """
    try:
        with socket.create_connection((host, porta), timeout=timeout) as conexao:
            conexao.settimeout(timeout)
            conexao.sendall(b"\x10\x04\x01")
            dados = conexao.recv(8)
    except OSError as erro:
        print(f"[printer/windows] Consulta de status ESC/POS via TCP para {host}:{porta} falhou: {erro}")
        return None

    if not dados:
        print(f"[printer/windows] {host}:{porta} não respondeu à consulta de status ESC/POS via TCP.")
        return None

    byte_status = dados[0]
    offline = bool(byte_status & 0x08)
    print(f"[printer/windows] Status ESC/POS via TCP de {host}:{porta}: byte=0x{byte_status:02x} {'OFFLINE' if offline else 'online'}.")
    return not offline


def imprimir(nome_impressora: str, conteudo: bytes) -> None:
    """Envia `conteudo` (bytes crus, já formatados em ESC/POS) para a fila de
    impressão `nome_impressora`, em modo RAW (sem reprocessamento pelo driver).

    Requer o pacote `pywin32` instalado (Windows apenas). Levanta `RuntimeError`
    se a impressora não puder ser aberta ou o job falhar.
    """
    import pywintypes
    import win32print

    print(f"[printer/windows] Abrindo impressora '{nome_impressora}'...")
    try:
        handle = win32print.OpenPrinter(nome_impressora)
    except pywintypes.error as erro:
        print(f"[printer/windows] Não foi possível abrir '{nome_impressora}': {erro}")
        raise RuntimeError(f"Não foi possível abrir a impressora '{nome_impressora}': {erro}") from erro

    try:
        print(f"[printer/windows] Enviando {len(conteudo)} bytes em modo RAW para '{nome_impressora}'...")
        win32print.StartDocPrinter(handle, 1, ("Pedido", None, "RAW"))
        try:
            win32print.StartPagePrinter(handle)
            try:
                win32print.WritePrinter(handle, conteudo)
            finally:
                win32print.EndPagePrinter(handle)
        finally:
            win32print.EndDocPrinter(handle)
        print(f"[printer/windows] Job enviado com sucesso para '{nome_impressora}'.")
    except pywintypes.error as erro:
        print(f"[printer/windows] Falha ao enviar o job para '{nome_impressora}': {erro}")
        raise RuntimeError(f"Falha ao enviar o job para '{nome_impressora}': {erro}") from erro
    finally:
        win32print.ClosePrinter(handle)


def _consultar_status_esc_pos(nome_impressora: str):
    """Confirmação extra de status ESC/POS via spooler — DESATIVADA.

    A ideia era mandar "DLE EOT 1" (0x10 0x04 0x01 — "transmit printer
    status") pela fila do spooler e ler 1 byte de volta pelo mesmo handle,
    igual a `_consultar_status_esc_pos_tcp` faz por socket cru para
    impressoras de rede. Só que, diferente do socket, o Win32 Print API
    não tem como ler de volta pelo mesmo handle de um job: `win32print`
    (pywin32) nunca expôs um `ReadPrinter` — é chamada inexistente, não um
    detalhe de versão (confirmado em produção: AttributeError "module
    'win32print' has no attribute 'ReadPrinter'"). Cada tentativa batia em
    WritePrinter (que já manda os 3 bytes de verdade pela fila da
    impressora física) e só depois quebrava na leitura — ou seja, ficava
    enfileirando um job real a cada ciclo de detecção (30s) sem nunca
    completar a checagem.

    Sem uma forma real de ler bidirecionalmente por aqui (precisaria abrir
    a porta serial/COM diretamente, fora do spooler, com pyserial ou
    equivalente — não implementado), esta função não faz mais nada:
    sempre devolve None ("não verificado"), e quem chama já trata None
    como "mantém a disponibilidade calculada por WorkOffline/Pausada",
    exatamente como antes desta tentativa de confirmação existir."""
    return None


def coletar_impressoras():
    """Coleta informações das impressoras instaladas via PowerShell (Win32_Printer).

    Precisa do PowerShell (padrão em qualquer Windows atual). Se não
    encontrar o executável, ou a chamada falhar/retornar algo que não seja
    JSON válido, retorna lista vazia.
    """
    saida = _executar_powershell()
    if not saida.strip():
        print("[printer/windows] Consulta ao Win32_Printer via PowerShell não retornou nada.")
        return []

    try:
        dados = json.loads(saida)
    except json.JSONDecodeError as erro:
        print(f"[printer/windows] Saída do PowerShell não é JSON válido ({erro}): {saida[:300]!r}")
        return []

    # Get-CimInstance com resultado único vira objeto solto, não lista.
    if isinstance(dados, dict):
        dados = [dados]

    print(f"[printer/windows] {len(dados)} impressora(s) encontrada(s) via Win32_Printer.")

    impressoras = []
    for item in dados:
        nome_porta = item.get("PortName") or ""
        host_porta = item.get("PortaHost") or ""
        # WorkOffline é o Windows quem mantém, não este script: pra
        # impressoras Plug-and-Play (que é o caso de usb/serial), o
        # spooler detecta o dispositivo físico sumir e marca a fila como
        # "fora de linha" sozinho — diferente de tipo_porta, que só olha o
        # nome da porta e por isso continua "usb" pra sempre, mesmo com o
        # cabo desconectado (a porta em si, "USB001", não desaparece só
        # porque o dispositivo não está mais nela agora).
        fora_de_linha = bool(item.get("ForaDeLinha"))
        # Pausada (fila parada pelo administrador) é um sinal separado de
        # ForaDeLinha (dispositivo Plug-and-Play sumiu) — os dois deixam a
        # impressora incapaz de imprimir agora, então ambos entram em
        # "disponivel".
        pausada = bool(item.get("Pausada"))
        print(f"[printer/windows] '{item.get('Nome', '')}': PortName='{nome_porta}' PortaHost='{host_porta}' Status='{item.get('Status', '')}' ForaDeLinha={fora_de_linha} Pausada={pausada}")

        impressora = InfoImpressora(
            nome=item.get("Nome", ""),
            modelo=item.get("Driver", ""),
            fabricante=item.get("DriverFabricante") or "",
            driver=item.get("Driver", ""),
            porta=host_porta or nome_porta,
            tipo_porta=_classificar_porta(nome_porta, host_porta),
            status=str(item.get("Status", "")),
            padrao=bool(item.get("Padrao")),
            disponivel=not fora_de_linha and not pausada,
            bruto=item,
        )

        # Checagem real de porta pra impressoras de rede: WorkOffline/
        # Pausada são só o que o spooler reporta, e pra portas de rede esse
        # status costuma ficar desatualizado (o spooler não faz polling
        # constante do socket) — um socket TCP real em host_porta:porta_tcp
        # é uma confirmação muito mais confiável de que a impressora está
        # de fato ligada/acessível agora. Só tentado quando host_porta é um
        # IPv4 literal — portas WSD/hostname não garantem um simples socket
        # TCP/IP na porta reportada.
        if impressora.tipo_porta == "rede" and _PADRAO_IPV4.match(host_porta):
            porta_tcp = item.get("PortaNumero") or _PORTA_TCP_PADRAO
            porta_aberta = _verificar_conexao_tcp(host_porta, porta_tcp)
            if porta_aberta:
                if not impressora.disponivel:
                    print(f"[printer/windows] '{impressora.nome}': porta TCP {host_porta}:{porta_tcp} respondeu à conexão apesar do spooler reportar indisponível — revertendo para disponível.")
                impressora.disponivel = True
                if eh_bematech_mp4200th(impressora):
                    status_esc_pos = _consultar_status_esc_pos_tcp(host_porta, porta_tcp)
                    if status_esc_pos is False:
                        impressora.disponivel = False
            else:
                if impressora.disponivel:
                    print(f"[printer/windows] '{impressora.nome}': porta TCP {host_porta}:{porta_tcp} não respondeu — marcando indisponível apesar do spooler reportar disponível.")
                impressora.disponivel = False

        # Consulta de status ESC/POS via spooler: só vale a pena tentar se
        # já passou nos sinais baratos (conectada, não pausada, incluindo a
        # checagem de rede acima) e for uma impressora ESC/POS de verdade
        # (ver eh_bematech_mp4200th — mandar DLE EOT pra qualquer outra
        # coisa é efeito indefinido). Não roda de novo pra quem já foi
        # confirmada via TCP acima (tipo_porta == "rede"), pra não sondar a
        # mesma impressora duas vezes. "False" aqui deixa disponivel=False;
        # "None" (não deu pra confirmar) mantém o que já estava — nunca
        # piora um resultado que a consulta extra simplesmente não suporta.
        if impressora.disponivel and impressora.tipo_porta != "rede" and eh_bematech_mp4200th(impressora):
            status_esc_pos = _consultar_status_esc_pos(impressora.nome)
            if status_esc_pos is False:
                impressora.disponivel = False

        impressoras.append(impressora)

    return impressoras
