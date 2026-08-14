"""Roda main.py num subprocesso e reinicia automaticamente sempre que um
arquivo do projeto for criado, alterado ou removido — útil durante o
desenvolvimento, para não precisar reiniciar manualmente a cada mudança.

Só usa a biblioteca padrão (sem nova dependência em pyproject.toml).
Detecta mudanças por polling (mtime), o que é suficiente para um projeto
deste tamanho e evita depender de bibliotecas externas (ex: watchdog) só
para uma comodidade de desenvolvimento.

Uso: .venv/bin/python -u dev_watch.py
(os mesmos argumentos que você passaria para main.py podem vir depois)
"""

import json
import os
import shutil
import signal
import subprocess
import sys
import time

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
MAIN_SCRIPT = os.path.join(BASE_DIR, "main.py")

# No Hyprland, uma janela nova sempre abre no workspace atualmente focado —
# ao reiniciar o app enquanto se está trabalhando em outro workspace, ele
# "pula" para perto de você em vez de voltar para onde estava. Usamos o
# hyprctl (se disponível) para devolvê-lo ao workspace de onde saiu.
HYPRLAND_ATIVO = bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")) and shutil.which("hyprctl") is not None
TENTATIVAS_ESPERAR_JANELA = 25  # ~5s (ver INTERVALO_ESPERAR_JANELA)
INTERVALO_ESPERAR_JANELA = 0.2

# Diretórios que nunca devem disparar reinício: ambiente virtual, controle de
# versão, cache de bytecode e a pasta de comandas salvas em tempo de execução
# (senão toda impressão de pedido reiniciaria o app).
IGNORAR_DIRS = {".venv", ".git", "__pycache__", "pedidos", ".claude"}
# Só observa extensões relevantes ao código/recursos do app.
EXTENSOES_OBSERVADAS = {".py", ".qml", ".json", ".qmldir"}
# Arquivos de estado/preferência gerados pelo próprio app em tempo de
# execução (não código) — ficam dentro de Config/, que por sua vez PRECISA
# continuar sendo observada (tem .py de verdade). Sem essa lista, salvar uma
# preferência (ex: marcar um checkbox em Configurações) reiniciaria o app a
# cada clique, porque o arquivo .json muda de mtime igual a um arquivo de
# código editado. Caminho relativo a partir de BASE_DIR.
ARQUIVOS_IGNORADOS = {
    os.path.join("Config", "estilo_impressao.json"),
    os.path.join("Config", ".versao"),
    # Escolha de qual máquina da malha imprime (ver
    # services/rede/impressoraFixada.py). É gravado/apagado sozinho quando
    # um peer entra na rede anunciando uma fixação — ou seja, o app se
    # reiniciava sozinho, no meio do uso, sem ninguém ter tocado em código.
    os.path.join("Config", "impressora_fixada.json"),
}
# Pastas inteiras de dados que o app grava em tempo de execução. Diferente de
# IGNORAR_DIRS, que casa por NOME de pasta em qualquer nível, aqui o casamento
# é pelo início do caminho relativo — "cardapio" é um nome genérico demais
# para ser ignorado em qualquer lugar do projeto.
#
# data/cardapio é editada pela própria tela de Cardápio (ver
# services/cardapioService.salvar) e pela sincronização da malha. Sem isto,
# cadastrar um item reiniciava o app no meio do cadastro — mesmo problema que
# ARQUIVOS_IGNORADOS resolveu para as preferências de Config/.
PREFIXOS_IGNORADOS = (
    os.path.join("data", "cardapio"),
)

INTERVALO_POLL = 0.5  # segundos entre verificações


def _arquivos_observados():
    """Retorna {caminho: mtime} de todos os arquivos relevantes do projeto."""
    estado = {}
    for raiz, dirs, arquivos in os.walk(BASE_DIR):
        dirs[:] = [d for d in dirs if d not in IGNORAR_DIRS]
        for nome in arquivos:
            if os.path.splitext(nome)[1] not in EXTENSOES_OBSERVADAS:
                continue
            caminho = os.path.join(raiz, nome)
            relativo = os.path.relpath(caminho, BASE_DIR)
            if relativo in ARQUIVOS_IGNORADOS:
                continue
            if relativo.startswith(PREFIXOS_IGNORADOS):
                continue
            try:
                estado[caminho] = os.path.getmtime(caminho)
            except OSError:
                pass
    return estado


def _iniciar_processo():
    print("[dev_watch] Iniciando main.py...")
    return subprocess.Popen([sys.executable, "-u", MAIN_SCRIPT, *sys.argv[1:]])


def _workspace_da_janela(pid):
    """Consulta o Hyprland pela janela do processo com esse pid e devolve o
    id do workspace em que ela está agora, ou None se não encontrar."""
    try:
        saida = subprocess.run(
            ["hyprctl", "-j", "clients"], capture_output=True, text=True, timeout=2, check=True
        )
        clientes = json.loads(saida.stdout)
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
        return None

    for cliente in clientes:
        if cliente.get("pid") == pid:
            return (cliente.get("workspace") or {}).get("id")

    return None


def _esperar_workspace_da_janela(pid):
    """Espera a janela do processo aparecer no Hyprland (pode levar um
    instante depois do processo iniciar) e devolve seu workspace atual."""
    for _ in range(TENTATIVAS_ESPERAR_JANELA):
        workspace_id = _workspace_da_janela(pid)
        if workspace_id is not None:
            return workspace_id
        time.sleep(INTERVALO_ESPERAR_JANELA)

    return None


def _mover_janela_para_workspace(pid, workspace_id):
    try:
        subprocess.run(
            ["hyprctl", "dispatch", "movetoworkspacesilent", f"{workspace_id},pid:{pid}"],
            capture_output=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def _encerrar_processo(processo):
    if processo.poll() is not None:
        return
    processo.terminate()
    try:
        processo.wait(timeout=5)
    except subprocess.TimeoutExpired:
        processo.kill()
        processo.wait()


def main():
    processo = _iniciar_processo()
    estado_anterior = _arquivos_observados()

    # SIGTERM (ex: "kill <pid>", ou o processo pai sendo encerrado) não é
    # capturado por "except KeyboardInterrupt" — sem isso, um "kill" no
    # dev_watch deixaria o main.py órfão, ainda rodando sozinho.
    def _ao_receber_sigterm(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, _ao_receber_sigterm)

    try:
        while True:
            time.sleep(INTERVALO_POLL)

            if processo.poll() is not None:
                # main.py encerrou sozinho (ex: janela fechada) — encerra o
                # watcher junto, em vez de ficar rodando à toa.
                print(f"[dev_watch] main.py encerrou (código {processo.returncode}), saindo.")
                sys.exit(processo.returncode)

            estado_atual = _arquivos_observados()
            if estado_atual != estado_anterior:
                print("[dev_watch] Mudança detectada, reiniciando main.py...")
                estado_anterior = estado_atual

                workspace_anterior = _workspace_da_janela(processo.pid) if HYPRLAND_ATIVO else None

                _encerrar_processo(processo)
                processo = _iniciar_processo()

                if workspace_anterior is not None:
                    workspace_novo = _esperar_workspace_da_janela(processo.pid)
                    if workspace_novo is not None and workspace_novo != workspace_anterior:
                        _mover_janela_para_workspace(processo.pid, workspace_anterior)
    except KeyboardInterrupt:
        print("\n[dev_watch] Interrompido, encerrando main.py...")
        _encerrar_processo(processo)


if __name__ == "__main__":
    main()
