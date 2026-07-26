"""Diagnóstico da impressão térmica configurada (Bematech MP-4200 TH ou
qualquer outra) — roda um teste real de ponta a ponta, passo a passo, pra
descobrir ONDE a impressão está travando quando "a impressora aparece
reconhecida, mas nada sai no papel" (sem nenhum erro visível no app).

O app inteiro só reporta o que os módulos de impressão (services/printer/*,
services/printerService.py) sabem: se o spooler ACEITOU o job. Isso não
garante que o job foi processado de verdade — ele pode ficar preso na
fila (pausada, com erro, ou a impressora "aceita" bytes que nunca chegam
de fato por causa de configuração errada da porta serial). Este script
cobre esse ponto cego consultando a fila (Win32_PrintJob, no Windows)
alguns segundos depois do envio.

Tudo que este script loga também vai para logs/app.log (ver
Config/logConfig.py), então dá pra rodar e depois conferir/mandar esse
arquivo pra quem for ajudar a diagnosticar.

Uso:
    python -m Config.diagnosticar_impressora
    python -m Config.diagnosticar_impressora --sem-teste
    python -m Config.diagnosticar_impressora --impressora "Bematech MP-4200 TH"
"""

import argparse
import shutil
import subprocess
import sys
import time

from Config import logConfig
from services.printer import coletar_informacoes_impressoras
from services.printerService import PrinterService


def log(mensagem: str) -> None:
    print(f"[diagnostico-impressora] {mensagem}")


def _payload_teste() -> bytes:
    """ESC @ (reset da impressora) + texto simples + linhas em branco +
    corte — não depende de comandaEstiloService/estilo configurado, pra
    isolar o teste de qualquer configuração da tela Configurações."""
    texto = (
        "\x1b@"
        "=== TESTE DE DIAGNOSTICO ===\n"
        f"Rodado em: {time.strftime('%d/%m/%Y %H:%M:%S')}\n"
        "Se isto saiu no papel, a impressao esta funcionando.\n"
        "\n\n\n"
    )
    conteudo = texto.encode("ascii", "replace")
    conteudo += b"\x1d\x56\x00"  # GS V 0 — corte total (ignorado por impressoras sem essa função).
    return conteudo


def listar_impressoras():
    """Loga cada impressora instalada no sistema operacional (nome, porta,
    tipo_porta...) — chamado tanto por main() (CLI) quanto por main.py na
    inicialização do app, para o diagnóstico de porta aparecer no console/
    logs/app.log sem precisar rodar este script à parte."""
    impressoras = coletar_informacoes_impressoras()
    if not impressoras:
        log("Nenhuma impressora instalada foi encontrada pelo sistema operacional.")
        return impressoras

    for impressora in impressoras:
        log(
            f"- '{impressora.nome}' | modelo='{impressora.modelo}' "
            f"fabricante='{impressora.fabricante}' porta='{impressora.porta}' "
            f"tipo_porta='{impressora.tipo_porta}' status='{impressora.status}' "
            f"padrao={impressora.padrao}"
        )
    return impressoras


def _executavel_powershell():
    for candidato in ("powershell", "powershell.exe", "pwsh", "pwsh.exe"):
        caminho = shutil.which(candidato)
        if caminho:
            return caminho
    return None


def _verificar_fila_windows(nome_impressora: str, espera_segundos: int = 3) -> None:
    """No Windows, consulta Win32_PrintJob logo após o envio pra saber se
    o job ficou PRESO na fila (pausada, com erro, offline) em vez de sair
    de fato — win32print.WritePrinter só confirma que o SPOOLER aceitou o
    job, não que a impressora física processou os bytes."""
    if sys.platform != "win32":
        log("4/4 — Checagem de fila pulada (só implementada para Windows).")
        return

    executavel = _executavel_powershell()
    if not executavel:
        log("4/4 — PowerShell não encontrado — não dá pra checar o estado da fila.")
        return

    log(f"4/4 — Aguardando {espera_segundos}s e conferindo a fila de impressão de '{nome_impressora}'...")
    time.sleep(espera_segundos)

    script = (
        "Get-CimInstance -ClassName Win32_PrintJob | "
        f"Where-Object {{ $_.Name -like '{nome_impressora}*' }} | "
        "Select-Object Document, JobStatus, TotalPages, PagesPrinted, Status | "
        "ConvertTo-Json"
    )
    try:
        resultado = subprocess.run(
            [executavel, "-NoProfile", "-NonInteractive", "-Command", script],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (subprocess.TimeoutExpired, OSError) as erro:
        log(f"Falha ao consultar a fila via PowerShell: {erro}")
        return

    saida = resultado.stdout.strip()
    if saida:
        log(
            f"Ainda há job(s) na fila de '{nome_impressora}' — ISSO GERALMENTE SIGNIFICA que a "
            f"impressora não está processando (offline, pausada, porta com configuração errada): {saida}"
        )
    else:
        log(f"Nenhum job pendente na fila de '{nome_impressora}' — o spooler já entregou/limpou o job (bom sinal).")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sem-teste", action="store_true", help="Só lista as impressoras instaladas, sem enviar nada")
    parser.add_argument("--impressora", default=None, help="Nome exato da impressora a testar (padrão: a configurada, ou a padrão do sistema)")
    args = parser.parse_args()

    logConfig.configurar_logging()

    log("=== Diagnóstico de impressão iniciado ===")
    log("1/4 — Listando impressoras instaladas no sistema operacional...")
    listar_impressoras()

    servico = PrinterService(args.impressora)

    log("2/4 — Localizando a impressora que o app usaria agora...")
    impressora = servico.localizar_impressora()
    if impressora is None:
        log("Nenhuma impressora foi selecionada — encerrando (nada para testar).")
        log("=== Diagnóstico de impressão concluído ===")
        return

    log(
        f"Impressora selecionada: '{impressora.nome}' "
        f"(porta: {impressora.porta}, tipo: {impressora.tipo_porta}, status: {impressora.status})."
    )

    if args.sem_teste:
        log("Teste de impressão pulado (--sem-teste). === Diagnóstico concluído ===")
        return

    conteudo = _payload_teste()
    log(f"3/4 — Enviando {len(conteudo)} bytes de teste para '{impressora.nome}'...")
    try:
        servico.imprimir(conteudo)
        log("PrinterService.imprimir() retornou sem levantar exceção (spooler aceitou o job).")
    except RuntimeError as erro:
        log(f"PrinterService.imprimir() FALHOU: {erro}")
        log("=== Diagnóstico de impressão concluído (com falha) ===")
        return

    _verificar_fila_windows(impressora.nome)
    log(f"=== Diagnóstico de impressão concluído — confira também {logConfig.caminho_arquivo_log()} ===")


if __name__ == "__main__":
    main()
