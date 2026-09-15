"""Uma vez por abertura: encerra o ppgs_server que a versão anterior do sistema
deixou rodando nesta máquina.

O servidor separado foi removido — os clientes agora moram nas próprias
máquinas (services/rede/clientes.py). Mas ele foi feito para sobreviver ao
fechamento do app (subia destacado e era adotado na abertura seguinte), então
a máquina que o hospedava continuaria com o processo de pé depois de atualizar,
segurando uma porta e memória para nada.

Só encerra o processo cujo PID o próprio sistema gravou em
`…/PPGS/dados/servidor.pid`, e só se o executável daquele PID ainda for o do
servidor: um PID reaproveitado pelo sistema operacional pode ser qualquer outro
programa.

NÃO apaga nada. O `pizzeria.db` fica onde está (os clientes dele não foram
migrados, por decisão), e o atalho de inicialização do Windows continua abrindo
o sistema."""

import os
import signal
import subprocess

_NOME_BINARIO = "pizzeria-server.exe" if os.name == "nt" else "pizzeria-server"
_ROTULO = "limpezaServidorAntigo"


def _pasta_base() -> str:
    """A mesma pasta que services/servidor/preparo.py usava."""
    if os.name == "nt":
        raiz = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    else:
        raiz = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(raiz, "PPGS")


def _caminho_pid() -> str:
    return os.path.join(_pasta_base(), "dados", "servidor.pid")


def _nome_do_processo(pid: int) -> str:
    if os.name == "nt":
        try:
            resultado = subprocess.run(
                ["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
                capture_output=True,
                text=True,
                timeout=15,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
        except (OSError, subprocess.TimeoutExpired):
            return ""
        primeira = (resultado.stdout or "").strip().splitlines()[:1]
        # Sem processo o tasklist responde uma frase ("INFO: ..."), não CSV.
        if not primeira or not primeira[0].startswith('"'):
            return ""
        return primeira[0].split('","')[0].strip('"')
    try:
        with open(f"/proc/{pid}/comm", "r", encoding="utf-8") as arquivo:
            return arquivo.read().strip()
    except OSError:
        return ""


def _eh_o_servidor(nome: str) -> bool:
    # /proc/<pid>/comm corta o nome em 15 caracteres: compara pelo começo.
    return len(nome) >= 8 and _NOME_BINARIO.lower().startswith(nome.lower())


def executar():
    caminho = _caminho_pid()
    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            pid = int((arquivo.read() or "").strip())
    except (OSError, ValueError):
        return

    try:
        if pid > 0 and _eh_o_servidor(_nome_do_processo(pid)):
            print(f"[{_ROTULO}] Encerrando o ppgs_server da versão anterior (PID {pid}) — "
                  "os clientes agora ficam nas próprias máquinas.")
            if os.name == "nt":
                subprocess.run(
                    ["taskkill", "/PID", str(pid), "/T", "/F"],
                    capture_output=True,
                    timeout=30,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                )
            else:
                os.kill(pid, signal.SIGTERM)
    except Exception as erro:  # melhor esforço: nunca atrapalha a abertura
        print(f"[{_ROTULO}] Não foi possível encerrar o servidor antigo (PID {pid}): {erro}")
    finally:
        try:
            os.remove(caminho)
        except OSError:
            pass
