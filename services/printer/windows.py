import json
import re
import shutil
import subprocess

from .modelos import InfoImpressora

# PortName costuma bastar para classificar o tipo de porta no Windows:
# "COM3" (serial), "USB001" (usb), "192.168.0.50" ou "IP_192.168.0.50"/"WSD-..." (rede).
_PADROES_TIPO_PORTA = (
    (re.compile(r"^COM\d+", re.IGNORECASE), "serial"),
    (re.compile(r"USB", re.IGNORECASE), "usb"),
    (re.compile(r"^\d{1,3}(\.\d{1,3}){3}"), "rede"),
    (re.compile(r"IP_|WSD|TCP", re.IGNORECASE), "rede"),
)

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

        impressoras.append(
            InfoImpressora(
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
        )

    return impressoras
