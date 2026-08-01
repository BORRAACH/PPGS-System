#!/usr/bin/env python3
"""Automatiza, num Linux novo, toda a configuração necessária para a
impressora térmica Bematech MP-4200 TH (conectada via USB) funcionar com a
fila CUPS que `services/printer/linux.py` usa (envio raw via `lp -o raw`).

Por que isso não é trivial: a MP-4200 TH se anuncia na USB inteira como um
dispositivo CDC-ACM (modem virtual), não como impressora USB classe 7. Isso
tem três consequências que, sem tratar, fazem a comanda nunca sair mesmo
sem nenhum erro visível na aplicação:

  1. O kernel carrega o driver `cdc_acm` e cria `/dev/ttyACM*`, o que
     trava para sempre o backend `usb://` do CUPS (baseado em libusb) — ele
     nunca consegue reivindicar uma interface que o kernel já reivindicou.
     Fix: apontar a fila para `serial:/dev/ttyACM*?baud=...` em vez de
     `usb://...`.
  2. `/dev/ttyACM*` só é acessível por padrão a root e ao grupo `uucp`, mas
     o backend `serial` do CUPS não roda como root — dá "Permission
     denied" e o CUPS desabilita a fila sozinho.
     Fix: regra de udev liberando o nó pelo vendor/product ID.
  3. Um tty novo nasce em modo "cooked" (icanon/opost/onlcr ativos), que
     reescreve bytes do fluxo binário ESC/POS (ex: 0x0A vira 0x0D 0x0A),
     corrompendo os comandos antes de chegarem na impressora — a fila
     processa o job sem erro, mas nada sai no papel.
     Fix: forçar modo raw (`stty raw -echo`) toda vez que o dispositivo
     aparece, via a mesma regra de udev (RUN+=).

Só usa a biblioteca padrão do Python — precisa rodar antes de qualquer
dependência do projeto estar instalada, e como root (mexe em
/etc/udev/rules.d e administra a fila do CUPS).

Uso:
    sudo python3 Config/configurar_impressora_bematech.py
    sudo python3 Config/configurar_impressora_bematech.py --sem-teste
    sudo python3 Config/configurar_impressora_bematech.py --vendor 0b1b --produto 0003 --fila Bematech4200TH
"""

import argparse
import glob
import os
import shutil
import subprocess
import sys
import time

CAMINHO_REGRA_UDEV = "/etc/udev/rules.d/99-bematech-mp4200th.rules"

# (gerenciador, comando base de instalação não-interativa, pacotes a
# instalar) — nessa ordem de preferência; o primeiro que existir no
# sistema é o usado. cups-client só existe separado em bases Debian/Ubuntu;
# nas demais o pacote "cups" já traz lp/lpstat/lpadmin junto.
_GERENCIADORES_LINUX = [
    ("apt-get", ["apt-get", "install", "-y"], ["cups", "cups-client"]),
    ("dnf", ["dnf", "install", "-y"], ["cups"]),
    ("yum", ["yum", "install", "-y"], ["cups"]),
    ("pacman", ["pacman", "-S", "--noconfirm", "--needed"], ["cups"]),
    ("zypper", ["zypper", "install", "-y"], ["cups"]),
]


def log(mensagem: str) -> None:
    print(f"[config-impressora] {mensagem}", flush=True)


def executar(comando, **kwargs):
    """subprocess.run com defaults sensatos para este script (texto,
    captura de saída, sem levantar exceção sozinho — quem chama decide o
    que fazer com o returncode)."""
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    # Nome de fila/impressora com acento fora da tabela do locale levantaria
    # UnicodeDecodeError na thread de leitura do pipe, longe de qualquer
    # try/except deste script — ver services/printer/linux.py:_rodar.
    kwargs.setdefault("errors", "replace")
    return subprocess.run(comando, **kwargs)


def exigir_root() -> None:
    if os.geteuid() != 0:
        log("Este script precisa rodar como root (mexe em /etc/udev/rules.d e na fila do CUPS).")
        log("Rode de novo com: sudo python3 configurar_impressora_bematech.py")
        sys.exit(1)


def encontrar_stty() -> str:
    caminho = shutil.which("stty")
    if not caminho:
        log("Comando 'stty' não encontrado (deveria vir com coreutils/util-linux). Abortando.")
        sys.exit(1)
    return caminho


def garantir_cups_instalado() -> None:
    if shutil.which("lpadmin") and shutil.which("lp") and shutil.which("lpstat"):
        log("CUPS (lpadmin/lp/lpstat) já está instalado.")
        return

    log("CUPS não encontrado — tentando instalar...")
    for gerenciador, comando_base, pacotes in _GERENCIADORES_LINUX:
        if not shutil.which(gerenciador):
            continue
        log(f"Instalando {', '.join(pacotes)} via {gerenciador}...")
        resultado = executar([*comando_base, *pacotes], timeout=300)
        if resultado.returncode != 0:
            log(f"Falha ao instalar via {gerenciador}: {resultado.stderr.strip()}")
            sys.exit(1)
        break
    else:
        log("Nenhum gerenciador de pacotes conhecido (apt-get/dnf/yum/pacman/zypper) encontrado.")
        log("Instale o CUPS manualmente (pacote 'cups', e em Debian/Ubuntu também 'cups-client') e rode de novo.")
        sys.exit(1)

    if not (shutil.which("lpadmin") and shutil.which("lp") and shutil.which("lpstat")):
        log("CUPS foi instalado mas lpadmin/lp/lpstat continuam ausentes do PATH. Abortando.")
        sys.exit(1)
    log("CUPS instalado com sucesso.")


def garantir_cups_rodando() -> None:
    if shutil.which("systemctl"):
        executar(["systemctl", "enable", "--now", "cups"], timeout=30)
        for _ in range(10):
            if executar(["systemctl", "is-active", "cups"], timeout=10).stdout.strip() == "active":
                log("Serviço cups está ativo.")
                return
            time.sleep(1)
        log("Aviso: não consegui confirmar que o serviço cups ficou ativo via systemctl.")
        return

    if shutil.which("service"):
        executar(["service", "cups", "start"], timeout=30)
        log("Comando 'service cups start' executado (sem systemctl para confirmar o status).")
        return

    log("Aviso: nenhum 'systemctl' nem 'service' encontrado — confirme manualmente que o cupsd está rodando.")


def encontrar_dispositivo_tty(vendor_id: str, product_id: str) -> str | None:
    """Varre /sys/class/tty/ttyACM* e /sys/class/tty/ttyUSB* procurando o
    dispositivo USB (idVendor/idProduct) associado a cada um, subindo na
    árvore de /sys até achar esses atributos (ficam no nível do
    dispositivo USB, não da interface serial em si)."""
    candidatos = sorted(glob.glob("/sys/class/tty/ttyACM*") + glob.glob("/sys/class/tty/ttyUSB*"))

    for caminho_tty in candidatos:
        link_dispositivo = os.path.join(caminho_tty, "device")
        if not os.path.exists(link_dispositivo):
            continue

        atual = os.path.realpath(link_dispositivo)
        for _ in range(6):
            caminho_vendor = os.path.join(atual, "idVendor")
            caminho_product = os.path.join(atual, "idProduct")
            if os.path.isfile(caminho_vendor) and os.path.isfile(caminho_product):
                with open(caminho_vendor) as arquivo:
                    vendor_encontrado = arquivo.read().strip()
                with open(caminho_product) as arquivo:
                    product_encontrado = arquivo.read().strip()

                if vendor_encontrado.lower() == vendor_id.lower() and product_encontrado.lower() == product_id.lower():
                    return "/dev/" + os.path.basename(caminho_tty)
                break

            pai = os.path.dirname(atual)
            if pai == atual:
                break
            atual = pai

    return None


def instalar_regra_udev(vendor_id: str, product_id: str, baud: int, caminho_stty: str) -> None:
    conteudo = (
        f'SUBSYSTEM=="tty", ATTRS{{idVendor}}=="{vendor_id}", ATTRS{{idProduct}}=="{product_id}", '
        f'MODE="0666", ENV{{ID_MM_DEVICE_IGNORE}}="1", '
        f'RUN+="{caminho_stty} -F /dev/%k raw -echo {baud}"\n'
    )

    anterior = ""
    if os.path.exists(CAMINHO_REGRA_UDEV):
        with open(CAMINHO_REGRA_UDEV) as arquivo:
            anterior = arquivo.read()

    if anterior == conteudo:
        log(f"Regra de udev já está correta em {CAMINHO_REGRA_UDEV}.")
        return

    with open(CAMINHO_REGRA_UDEV, "w") as arquivo:
        arquivo.write(conteudo)
    log(f"Regra de udev escrita em {CAMINHO_REGRA_UDEV}:\n{conteudo.strip()}")

    executar(["udevadm", "control", "--reload-rules"], timeout=15)
    executar(["udevadm", "trigger", "--subsystem-match=tty"], timeout=15)
    executar(["udevadm", "settle"], timeout=15)
    log("Regras de udev recarregadas e disparadas de novo para o dispositivo já conectado.")


def aplicar_modo_raw_imediatamente(caminho_stty: str, dispositivo: str, baud: int) -> None:
    """Redundância de segurança: já aplica o modo raw agora, sem esperar
    o próximo evento de udev (útil se o gatilho do trigger não tiver
    alcançado o dispositivo por algum motivo)."""
    resultado = executar([caminho_stty, "-F", dispositivo, "raw", "-echo", str(baud)], timeout=10)
    if resultado.returncode != 0:
        log(f"Aviso: falha ao forçar modo raw em {dispositivo} agora: {resultado.stderr.strip()}")
    else:
        log(f"Modo raw aplicado imediatamente em {dispositivo}.")


def configurar_fila_cups(nome_fila: str, dispositivo: str, baud: int) -> None:
    uri = f"serial:{dispositivo}?baud={baud}"
    resultado = executar(
        ["lpadmin", "-p", nome_fila, "-E", "-v", uri, "-m", "raw", "-o", "auth-info-required=none"],
        timeout=30,
    )
    if resultado.returncode != 0:
        log(f"Falha ao configurar a fila '{nome_fila}': {resultado.stderr.strip()}")
        sys.exit(1)
    log(f"Fila '{nome_fila}' configurada com device-uri='{uri}'.")

    executar(["cupsenable", nome_fila], timeout=15)
    executar(["cupsaccept", nome_fila], timeout=15)
    log(f"Fila '{nome_fila}' habilitada e aceitando jobs.")


def enviar_teste(nome_fila: str) -> bool:
    conteudo = (
        b"\x1b\x40"
        + f"Teste automatico - configurar_impressora_bematech.py\nFila: {nome_fila}\n".encode("ascii", "replace")
        + b"\n\n\n"
        + b"\x1d\x56\x00"
    )

    log(f"Enviando teste de {len(conteudo)} bytes para '{nome_fila}' via 'lp -o raw'...")
    resultado = executar(["lp", "-d", nome_fila, "-o", "raw"], input=conteudo.decode("latin-1"), timeout=20)
    if resultado.returncode != 0:
        log(f"'lp' falhou: {resultado.stderr.strip()}")
        return False

    time.sleep(3)
    fila_pendente = executar(["lpstat", "-o", nome_fila], timeout=10).stdout.strip()
    if fila_pendente:
        log(f"Job ainda pendente na fila após o envio — provavelmente não imprimiu:\n{fila_pendente}")
        log(f"Verifique 'lpstat -l -p {nome_fila}' para o motivo.")
        return False

    log("Fila esvaziou sem erro — confira fisicamente se o papel saiu.")
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--vendor", default="0b1b", help="idVendor USB da impressora (padrão: 0b1b, Bematech)")
    parser.add_argument("--produto", default="0003", help="idProduct USB da impressora (padrão: 0003, MP-4200 TH)")
    parser.add_argument("--fila", default="Bematech4200TH", help="Nome da fila CUPS a criar/atualizar")
    parser.add_argument("--baud", type=int, default=9600, help="Baud rate da porta serial virtual (padrão: 9600)")
    parser.add_argument("--sem-teste", action="store_true", help="Não envia impressão de teste ao final")
    args = parser.parse_args()

    exigir_root()
    caminho_stty = encontrar_stty()

    log("1/5 — Garantindo que o CUPS está instalado...")
    garantir_cups_instalado()

    log("2/5 — Garantindo que o serviço cups está rodando...")
    garantir_cups_rodando()

    log(f"3/5 — Procurando impressora USB {args.vendor}:{args.produto}...")
    dispositivo = encontrar_dispositivo_tty(args.vendor, args.produto)
    if not dispositivo:
        log(f"Nenhum /dev/ttyACM*/ttyUSB* encontrado para {args.vendor}:{args.produto}.")
        log("Confira se a impressora está ligada e conectada via USB (comando 'lsusb' deve listá-la) e rode de novo.")
        sys.exit(1)
    log(f"Impressora encontrada em {dispositivo}.")

    log("4/5 — Instalando regra de udev (permissão + modo raw automático)...")
    instalar_regra_udev(args.vendor, args.produto, args.baud, caminho_stty)
    aplicar_modo_raw_imediatamente(caminho_stty, dispositivo, args.baud)

    log(f"5/5 — Configurando a fila CUPS '{args.fila}'...")
    configurar_fila_cups(args.fila, dispositivo, args.baud)

    if args.sem_teste:
        log("Configuração concluída (teste de impressão pulado por --sem-teste).")
        return

    if enviar_teste(args.fila):
        log("Configuração concluída com sucesso.")
    else:
        log("Configuração aplicada, mas o teste não confirmou a impressão — investigue com os logs do CUPS.")
        sys.exit(1)


if __name__ == "__main__":
    main()
