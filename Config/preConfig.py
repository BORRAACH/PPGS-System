"""Garante que tudo que main.py precisa para rodar — bibliotecas Python e
programas de sistema — está instalado antes dele seguir em frente, tanto no
Windows quanto no Linux.

Só usa a biblioteca padrão do Python — não pode depender de nada que ainda
não esteja instalado, senão vira um problema de ovo-e-galinha. Por isso
precisa ser importado e chamado ANTES de qualquer import de terceiros
(PyQt6, etc.) em main.py: se PyQt6 for importado primeiro e não estiver
instalado, o processo já morre com ModuleNotFoundError antes deste script
ter a chance de rodar.

Mantenha a lista `_DEPENDENCIAS_PIP` abaixo em sincronia com `dependencies`
em pyproject.toml.
"""

import importlib
import os
import shutil
import subprocess
import sys

# (nome do pacote a instalar via pip, módulo usado para checar se já
# importa de verdade, valor de sys.platform exigido ou None se vale para
# qualquer SO)
_DEPENDENCIAS_PIP = [
    ("PyQt6", "PyQt6.QtCore", None),
    ("pywin32", "win32print", "win32"),
    # Ícones (Font Awesome, Material Design Icons...) expostos ao QML por
    # services/iconProvider.py — ver qml/components/Icone.qml.
    ("qtawesome", "qtawesome", None),
]

# Programas de sistema (não pacotes Python) exigidos só no Linux, e o nome
# do pacote que os instala em cada gerenciador conhecido. No Windows não há
# equivalente: a impressão usa o spooler e o PowerShell, que já vêm com o
# sistema operacional.
_PROGRAMAS_LINUX = {
    # "lp"/"lpstat" (services/printer/linux.py) — enviar e listar
    # impressoras via CUPS.
    "lp": {
        "apt-get": "cups",
        "dnf": "cups",
        "yum": "cups",
        "pacman": "cups",
        "zypper": "cups",
    },
}

# (gerenciador, comando base de instalação não-interativa) — nessa ordem de
# preferência; o primeiro que existir no sistema é o usado.
_GERENCIADORES_LINUX = [
    ("apt-get", ["sudo", "-n", "apt-get", "install", "-y"]),
    ("dnf", ["sudo", "-n", "dnf", "install", "-y"]),
    ("yum", ["sudo", "-n", "yum", "install", "-y"]),
    ("pacman", ["sudo", "-n", "pacman", "-S", "--noconfirm"]),
    ("zypper", ["sudo", "-n", "zypper", "install", "-y"]),
]


def _importa(modulo: str) -> bool:
    """Tenta importar de verdade (não só checar se existe no disco) — pega
    também instalações quebradas/parciais, não só o módulo ausente."""
    try:
        importlib.import_module(modulo)
        return True
    except ImportError:
        return False


def _instalar_pip(pacote: str) -> bool:
    print(f"[preConfig] Instalando dependência Python ausente: {pacote}...")
    try:
        subprocess.run([sys.executable, "-m", "pip", "install", pacote], check=True)
        return True
    except (subprocess.CalledProcessError, OSError) as erro:
        print(f"[preConfig] pip indisponível/falhou ({erro}); tentando via uv...")

    # venvs criados com "uv venv" (ver .venv/pyvenv.cfg: "uv = ...") não
    # vêm com o módulo pip instalado de propósito — o uv espera "uv pip
    # install" no lugar de "python -m pip". Só entra aqui se o pip acima
    # não deu certo, e só se o uv estiver disponível no PATH.
    uv = shutil.which("uv")
    if not uv:
        return False

    try:
        subprocess.run([uv, "pip", "install", "--python", sys.executable, pacote], check=True)
        return True
    except (subprocess.CalledProcessError, OSError) as erro:
        print(f"[preConfig] Falha ao instalar {pacote} via uv: {erro}")
        return False


def _garantir_modulo(pacote: str, modulo: str) -> None:
    if _importa(modulo):
        return

    if _instalar_pip(pacote) and _importa(modulo):
        return

    print(
        f"[preConfig] Aviso: não consegui garantir a dependência '{pacote}' "
        f"automaticamente. Tente instalar manualmente: pip install {pacote}"
    )


def _instalar_programa_linux(comando: str, pacotes_por_gerenciador: dict) -> None:
    for gerenciador, comando_base in _GERENCIADORES_LINUX:
        pacote = pacotes_por_gerenciador.get(gerenciador)
        if not pacote or not shutil.which(gerenciador):
            continue

        print(f"[preConfig] Instalando programa ausente '{comando}' (pacote '{pacote}' via {gerenciador})...")
        # Comando real sem o "sudo -n" (que só existe pra não travar
        # esperando senha aqui) — é o que sugerimos pro usuário rodar à mão.
        comando_manual = " ".join(["sudo", *comando_base[2:], pacote])
        try:
            subprocess.run(comando_base + [pacote], check=True, timeout=300)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as erro:
            print(
                f"[preConfig] Não consegui instalar '{comando}' automaticamente ({erro}). "
                "Sem privilégio de root sem senha isso é esperado — o app "
                f"funciona normalmente mesmo assim, só a impressão fica "
                f"indisponível até '{comando}' ser instalado manualmente "
                f"(ex: {comando_manual})."
            )
        return

    print(
        f"[preConfig] Não encontrei um gerenciador de pacotes conhecido para "
        f"instalar '{comando}'. Sem isso, o app funciona normalmente, só a "
        f"impressão fica indisponível até instalar manualmente."
    )


def _configurar_estilo_qt_quick() -> None:
    """Evita o estilo *nativo* do QtQuick Controls (ex: "Windows" no
    Windows), que carrega um plugin em DLL/so específico da plataforma
    (`qtquickcontrols2windowsstyleimplplugin` etc.) — se essa DLL não
    conseguir carregar (falta o runtime do Visual C++, instalação do Qt
    incompleta/corrompida, antivírus bloqueando...), toda tela com
    TextField/ComboBox/etc. para de abrir com
    "QQmlComponent: Component is not ready" / "Type TextField unavailable".

    "Fusion" é implementado em C++/QML puro, sem plugin nativo por
    plataforma, e fica igual em qualquer sistema — evita esse problema de
    vez, em vez de depender do usuário instalar o runtime que falta.

    Só define se QT_QUICK_CONTROLS_STYLE não estiver configurada no
    ambiente (respeita a escolha de quem já tiver setado a variável)."""
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Fusion")


def _garantir_programas_sistema() -> None:
    if not sys.platform.startswith("linux"):
        return

    for comando, pacotes in _PROGRAMAS_LINUX.items():
        if shutil.which(comando):
            continue
        _instalar_programa_linux(comando, pacotes)


def _dependencias_aplicaveis():
    """_DEPENDENCIAS_PIP filtrada pela plataforma atual (ex: pywin32 só
    entra na lista se sys.platform == "win32")."""
    return [
        (pacote, modulo)
        for pacote, modulo, plataforma in _DEPENDENCIAS_PIP
        if not plataforma or sys.platform == plataforma
    ]


def garantir_dependencias() -> None:
    """Primeiro checa se as dependências Python já estão todas instaladas —
    se estiverem, não mexe em nada e devolve o controle pra main.py seguir
    direto pra rodar o programa. Só quando falta algo é que instala (best-
    effort: o que não conseguir resolver sozinho vira um aviso claro no
    console em vez de deixar main.py travar mais na frente com um erro sem
    contexto). Também configura o ambiente Qt para evitar plugins nativos
    problemáticos e, no Linux, garante os programas de sistema exigidos
    pela impressão."""
    _configurar_estilo_qt_quick()

    dependencias = _dependencias_aplicaveis()
    faltando = [(pacote, modulo) for pacote, modulo in dependencias if not _importa(modulo)]

    if not faltando:
        print("[preConfig] Todas as dependências Python já estão instaladas — nada para fazer, iniciando o app.")
    else:
        nomes = ", ".join(pacote for pacote, _ in faltando)
        print(f"[preConfig] Dependência(s) ausente(s): {nomes}. Instalando...")
        for pacote, modulo in faltando:
            _garantir_modulo(pacote, modulo)

    _garantir_programas_sistema()


if __name__ == "__main__":
    garantir_dependencias()
