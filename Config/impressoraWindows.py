"""Automatiza, no Windows, a configuração da impressora térmica Bematech
MP-4200 TH conectada via USB, pra ela ficar pronta pro app usar sem
intervenção manual — chamado automaticamente por main.py a cada início do
app (ver garantir_impressora_bematech()).

Por que isso não é automático sozinho pelo Windows: a MP-4200 TH se
anuncia na USB inteira como um dispositivo CDC-ACM (modem/serial virtual),
não como impressora USB classe 7 — mesmo hardware e mesma causa raiz do
script equivalente pro Linux (ver configurar_impressora_bematech.py, que
detalha isso a fundo). No Windows isso se desdobra assim:

  1. O Windows já traz embutido o driver genérico de porta serial USB
     (usbser.sys) e cria uma porta COM sozinho quando a impressora é
     plugada — normalmente NÃO precisa instalar um driver de verdade pra
     isso (diferente do Linux, que não tem esse problema de permissão/modo
     raw, mas tem os outros três descritos no script do Linux).
  2. Só que o Windows não sabe que "COM5 é uma impressora" — Plug and Play
     não cria uma fila de impressão (objeto "Printer") em cima dessa porta
     sozinho. Sem uma fila apontando pra ela, a impressora não aparece em
     "Dispositivos e Impressoras" e o app (services/printer/windows.py)
     nunca a encontra, mesmo com o Windows já reconhecendo o hardware.

Este módulo cobre o passo 2: acha a porta COM correspondente ao VID/PID da
Bematech via WMI, e cria (ou corrige, se a porta mudou num replug) uma
fila de impressão Windows apontando pra ela, usando o driver "Generic /
Text Only" que já vem embutido no Windows (nenhum arquivo de driver novo
precisa ser baixado/instalado — só registrado no spooler de impressão).

Depois disso, ainda configura os parâmetros seriais da porta COM (baud,
paridade, controle de fluxo — ver _configurar_porta_serial()). Isso é
necessário mesmo sendo uma porta USB "virtual": se o Windows deixar
controle de fluxo por hardware ligado por padrão (o comum) e a impressora
nunca assinalar CTS de volta (comum em conversores USB-serial simples),
a escrita fica represada no driver da porta — sem erro nenhum visível pro
app — e é exatamente o sintoma de "impressora reconhecida/instalada, mas
nada sai no papel". Mesmo baud usado no script equivalente pro Linux
(configurar_impressora_bematech.py: 9600, também sensível a isso por
outros motivos).

Melhor esforço, silencioso e nunca fatal: se a impressora não for
encontrada, se faltar permissão (criar impressora/porta local costuma
exigir Administrador), ou qualquer outro passo falhar, apenas loga um
aviso claro e deixa o app seguir normalmente — a tela de Configurações
mostra "impressora não encontrada" do jeito de sempre (ver
BalcaoController.consultarImpressoraAtual, que também chama
garantir_impressora_bematech() antes de procurar a impressora, pra
tentar se auto-curar caso o usuário conecte a impressora depois do app já
ter iniciado).
"""

import json
import shutil
import subprocess
import sys

VENDOR_ID = "0B1B"
PRODUCT_ID = "0003"
NOME_IMPRESSORA = "Bematech MP-4200 TH"
NOME_DRIVER = "Generic / Text Only"

_TIMEOUT_PS = 30

# Roda inteiro num único script PowerShell (em vez de várias chamadas
# separadas) pra evitar N subprocessos (cada um leva ~1s só pra o
# PowerShell subir) e pra decidir "criar vs corrigir vs já está ok" com um
# único snapshot consistente do estado — consultar em chamadas Python
# separadas arriscaria uma corrida (ex: porta muda entre a consulta e a
# criação, num replug bem na hora errada).
_SCRIPT_PS = r"""
$ErrorActionPreference = 'Stop'
$vendorId = '{vendor_id}'
$productId = '{product_id}'
$nomeImpressora = '{nome_impressora}'
$nomeDriver = '{nome_driver}'

$resultado = [ordered]@{{
    dispositivoEncontrado = $false
    portaCom              = $null
    statusDispositivo     = $null
    impressoraJaExistia   = $false
    impressoraCriada      = $false
    impressoraCorrigida   = $false
    erro                  = $null
}}

try {{
    $dispositivo = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
        Where-Object {{ $_.PNPDeviceID -match "VID_$vendorId.*PID_$productId" }} |
        Select-Object -First 1

    if (-not $dispositivo) {{
        $resultado.erro = 'dispositivo_nao_encontrado'
        $resultado | ConvertTo-Json
        exit 0
    }}

    $resultado.dispositivoEncontrado = $true
    $resultado.statusDispositivo = $dispositivo.Status

    if ($dispositivo.Name -notmatch '\(COM(\d+)\)') {{
        $resultado.erro = 'sem_porta_com'
        $resultado | ConvertTo-Json
        exit 0
    }}

    $portaCom = 'COM' + $Matches[1]
    $resultado.portaCom = $portaCom

    $impressora = Get-Printer -Name $nomeImpressora -ErrorAction SilentlyContinue

    if ($impressora -and $impressora.PortName -eq $portaCom) {{
        $resultado.impressoraJaExistia = $true
        $resultado | ConvertTo-Json
        exit 0
    }}

    if (-not (Get-PrinterPort -Name $portaCom -ErrorAction SilentlyContinue)) {{
        Add-PrinterPort -Name $portaCom
    }}

    if (-not (Get-PrinterDriver -Name $nomeDriver -ErrorAction SilentlyContinue)) {{
        Add-PrinterDriver -Name $nomeDriver
    }}

    if ($impressora) {{
        # Impressora já existia (provavelmente criada numa porta COM
        # antiga, de antes de um replug) — só reaponta pra porta atual.
        Set-Printer -Name $nomeImpressora -PortName $portaCom
        $resultado.impressoraCorrigida = $true
    }} else {{
        Add-Printer -Name $nomeImpressora -DriverName $nomeDriver -PortName $portaCom
        $resultado.impressoraCriada = $true
    }}
}} catch {{
    $resultado.erro = $_.Exception.Message
}}

$resultado | ConvertTo-Json
""".format(
    vendor_id=VENDOR_ID,
    product_id=PRODUCT_ID,
    nome_impressora=NOME_IMPRESSORA,
    nome_driver=NOME_DRIVER,
)


def _log(mensagem: str) -> None:
    print(f"[impressoraWindows] {mensagem}", flush=True)


def _executavel_powershell():
    for candidato in ("powershell", "powershell.exe", "pwsh", "pwsh.exe"):
        caminho = shutil.which(candidato)
        if caminho:
            return caminho
    return None


def _logar_resultado(dados: dict) -> None:
    erro = dados.get("erro")

    if erro == "dispositivo_nao_encontrado":
        _log(f"Nenhuma {NOME_IMPRESSORA} encontrada nas portas USB — seguindo sem impressora.")
        return

    if erro == "sem_porta_com":
        _log(
            f"{NOME_IMPRESSORA} encontrada (status: {dados.get('statusDispositivo')}), "
            "mas o Windows ainda não atribuiu uma porta COM a ela. Normalmente resolve "
            "sozinho em alguns segundos após conectar; se persistir, confira em "
            "Gerenciador de Dispositivos se ela aparece com algum erro."
        )
        return

    if erro:
        _log(
            f"Falha ao configurar a {NOME_IMPRESSORA} automaticamente "
            f"(porta detectada: {dados.get('portaCom') or '?'}): {erro} "
            "Isso costuma acontecer por falta de permissão — tente rodar o "
            "app como Administrador uma vez, ou configure manualmente em "
            "Painel de Controle > Dispositivos e Impressoras."
        )
        return

    porta = dados.get("portaCom")
    if dados.get("impressoraCriada"):
        _log(f"{NOME_IMPRESSORA} configurada com sucesso em {porta}.")
    elif dados.get("impressoraCorrigida"):
        _log(f"{NOME_IMPRESSORA} já existia, porta corrigida para {porta} (provavelmente por um replug).")
    elif dados.get("impressoraJaExistia"):
        _log(f"{NOME_IMPRESSORA} já estava configurada corretamente em {porta}.")


def _configurar_porta_serial(porta_com: str) -> None:
    """Configura baud/paridade/bits/controle-de-fluxo da porta COM virtual
    via `mode` (utilitário padrão do Windows, sem precisar do módulo
    PrintManagement nem de permissão elevada). "octs=off" ignora CTS
    (controle de fluxo por hardware de entrada) e "rts=on"/"dtr=on" mantêm
    essas linhas sempre "ligadas" — sem isso, se o Windows decidir esperar
    a impressora assinalar CTS antes de liberar a escrita (e ela nunca
    assinalar, por ser uma porta serial virtual sem handshake de verdade),
    os bytes ficam represados no driver de porta e nunca chegam na
    impressora. Roda mesmo se a criação da fila acima falhou por
    permissão — configurar a porta em si normalmente não exige
    Administrador."""
    try:
        resultado = subprocess.run(
            [
                "mode",
                f"{porta_com}:",
                "baud=9600",
                "parity=n",
                "data=8",
                "stop=1",
                "xon=off",
                "octs=off",
                "dtr=on",
                "rts=on",
            ],
            capture_output=True,
            text=True,
            errors="replace",
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired) as erro:
        _log(f"Falha ao rodar 'mode' para configurar {porta_com}: {erro}")
        return

    if resultado.returncode != 0:
        _log(f"'mode' retornou erro ao configurar {porta_com}: {(resultado.stderr or '').strip() or (resultado.stdout or '').strip()}")
        return

    _log(f"Porta {porta_com} configurada em 9600 8N1, sem controle de fluxo por hardware.")


def garantir_impressora_bematech() -> None:
    """Localiza a Bematech MP-4200 TH nas portas USB e garante que existe
    uma fila de impressão Windows configurada pra ela. Não faz nada fora
    do Windows. Nunca levanta exceção — qualquer falha vira só um aviso no
    console, e a função retorna normalmente (main.py e
    BalcaoController.consultarImpressoraAtual seguem em frente do mesmo
    jeito, com ou sem impressora encontrada)."""
    if sys.platform != "win32":
        return

    executavel = _executavel_powershell()
    if not executavel:
        _log("Nenhum executável de PowerShell encontrado (powershell/pwsh) — não dá pra configurar a impressora automaticamente.")
        return

    try:
        resultado = subprocess.run(
            [executavel, "-NoProfile", "-NonInteractive", "-Command", _SCRIPT_PS],
            capture_output=True,
            text=True,
            # Um byte fora da codepage do locale levantaria
            # UnicodeDecodeError dentro da thread de leitura do pipe, longe
            # deste try/except — ver o comentário em
            # services/printer/windows.py:_executar_powershell.
            errors="replace",
            timeout=_TIMEOUT_PS,
        )
    except (subprocess.TimeoutExpired, OSError) as erro:
        _log(f"Falha ao rodar o PowerShell ({erro}) — seguindo sem configurar a impressora.")
        return

    saida = (resultado.stdout or "").strip()
    if not saida:
        _log(f"PowerShell não retornou nada (stderr: {resultado.stderr.strip()!r}) — seguindo sem configurar a impressora.")
        return

    try:
        dados = json.loads(saida)
    except json.JSONDecodeError as erro:
        _log(f"Saída inesperada do PowerShell ({erro}): {saida[:300]!r}")
        return

    _logar_resultado(dados)

    porta = dados.get("portaCom")
    if porta:
        _configurar_porta_serial(porta)


if __name__ == "__main__":
    garantir_impressora_bematech()
