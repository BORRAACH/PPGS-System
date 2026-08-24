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

# (nome do pacote a instalar via pip, módulos usados para checar se já
# importam de verdade, valor de sys.platform exigido ou None se vale para
# qualquer SO)
#
# Vale a pena listar TODOS os submódulos que o app importa, não só um: as
# distribuições Linux quebram o PyQt6 em vários pacotes (no Debian/Ubuntu o
# `python3-pyqt6` traz QtCore/QtGui/QtWidgets, mas QtQml/QtQuick só vêm no
# `python3-pyqt6.qtquick`). Checando só PyQt6.QtCore, uma instalação parcial
# dessas passa batido aqui e o app só morre depois, no import do main.py.
_DEPENDENCIAS_PIP = [
    (
        "PyQt6",
        (
            "PyQt6.QtCore",
            "PyQt6.QtGui",
            "PyQt6.QtNetwork",
            "PyQt6.QtQml",
            "PyQt6.QtQuick",
            "PyQt6.QtWidgets",
        ),
        None,
    ),
    ("pywin32", ("win32print",), "win32"),
    # Ícones (Font Awesome, Material Design Icons...) expostos ao QML por
    # services/iconProvider.py — ver qml/components/Icone.qml.
    ("qtawesome", ("qtawesome",), None),
    # Descoberta das outras máquinas na rede local via mDNS/DNS-SD — ver
    # services/rede/descoberta.py. Sem ela o app ainda abre e a rede cai no
    # broadcast UDP de reserva, então continua sendo melhor esforço como o
    # resto desta lista.
    ("zeroconf", ("zeroconf",), None),
    # Criptografia da malha (ver services/rede/seguranca.py) e as chaves
    # derivadas que o ppgs_server usa. Diferente do resto desta lista, esta
    # NÃO é melhor esforço: sem ela a malha simplesmente não sobe
    # (RedeService._motivo_para_nao_iniciar). Entrar na malha voltou a ser
    # aberto, mas o tráfego dela segue cifrado, e cair para um modo em claro
    # poria as comandas e os endereços dos clientes no ar pra quem estivesse
    # ouvindo o wi-fi — sem nada na tela denunciando isso.
    ("cryptography", ("cryptography",), None),
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

# Nome do pacote pip -> nome equivalente no gerenciador de cada distro. Usado
# só para sugerir um comando quando a instalação via pip não deu certo: no
# Linux o PyQt6 da distro já vem casado com as libs Qt do sistema, então é o
# caminho mais confiável. Só o PyQt6 está mapeado porque é o único pesado/
# nativo; o resto instala sem dor pelo pip.
_PACOTES_DISTRO = {
    "PyQt6": {
        "apt-get": "python3-pyqt6",
        "dnf": "python3-pyqt6",
        "yum": "python3-pyqt6",
        "pacman": "python-pyqt6",
        "zypper": "python3-qt6",
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


def _erro_de_import(modulo: str) -> str | None:
    """Tenta importar de verdade (não só checar se existe no disco) — pega
    também instalações quebradas/parciais, não só o módulo ausente. Devolve
    None quando importa, ou a mensagem do erro (que distingue "módulo não
    existe" de "existe mas falta uma lib do sistema", ex: libGL.so.1)."""
    # O módulo pode ter sido instalado agora há pouco, neste mesmo processo:
    # sem invalidar os caches de import o Python continua enxergando o
    # site-packages como estava quando começou a rodar, e o import falha
    # mesmo com o pacote já no disco.
    importlib.invalidate_caches()
    try:
        importlib.import_module(modulo)
        return None
    except ImportError as erro:
        return str(erro)


def _importa(modulo: str) -> bool:
    return _erro_de_import(modulo) is None


def _em_ambiente_virtual() -> bool:
    return sys.prefix != sys.base_prefix


def _comandos_de_instalacao(pacote: str):
    """Formas de instalar `pacote`, na ordem em que devem ser tentadas."""
    tentativas = [([sys.executable, "-m", "pip", "install", pacote], "pip")]

    # venvs criados com "uv venv" (ver .venv/pyvenv.cfg: "uv = ...") não
    # vêm com o módulo pip instalado de propósito — o uv espera "uv pip
    # install" no lugar de "python -m pip".
    uv = shutil.which("uv")
    if uv:
        tentativas.append(
            ([uv, "pip", "install", "--python", sys.executable, pacote], "uv pip")
        )

    if not _em_ambiente_virtual():
        # PEP 668: as distribuições Linux atuais (Arch, Debian 12+, Ubuntu
        # 23.04+, Fedora 38+) marcam o Python do sistema como "externally
        # managed" e o pip se RECUSA a instalar nele — é por isso que a
        # instalação automática falha em toda máquina Linux recém-formatada,
        # mesmo com internet e com o pip presente.
        #
        # "--user" instala em ~/.local (que já está no sys.path), sem tocar
        # em nenhum arquivo gerenciado pela distro; "--break-system-packages"
        # só desliga a recusa do PEP 668 — combinados, o nome assusta mais do
        # que o efeito real.
        tentativas.append(
            (
                [sys.executable, "-m", "pip", "install", "--user",
                 "--break-system-packages", pacote],
                "pip --user",
            )
        )

    return tentativas


def _instalar_pip(pacote: str) -> bool:
    print(f"[preConfig] Instalando dependência Python ausente: {pacote}...")

    for comando, nome in _comandos_de_instalacao(pacote):
        try:
            subprocess.run(comando, check=True)
            return True
        except (subprocess.CalledProcessError, OSError) as erro:
            print(f"[preConfig] Instalação de {pacote} via {nome} não deu certo ({erro}).")

    return False


def _dica_pacote_da_distro(pacote: str) -> str:
    """Comando do gerenciador da distro para instalar `pacote`, quando faz
    sentido sugerir — em Linux, instalar o PyQt6 pela distro costuma ser mais
    confiável do que pelo pip, porque já traz as libs Qt do sistema junto."""
    pacotes_distro = _PACOTES_DISTRO.get(pacote)
    if not pacotes_distro or not sys.platform.startswith("linux"):
        return ""

    for gerenciador, comando_base in _GERENCIADORES_LINUX:
        nome_distro = pacotes_distro.get(gerenciador)
        if nome_distro and shutil.which(gerenciador):
            # comando_base começa com ["sudo", "-n", ...]; o "-n" só existe
            # pra não travar esperando senha — na dica manual ele atrapalha.
            return " ".join(["sudo", *comando_base[2:], nome_distro])

    return ""


def _garantir_modulo(pacote: str, modulos) -> None:
    faltando = {modulo: erro for modulo in modulos if (erro := _erro_de_import(modulo))}
    if not faltando:
        return

    if _instalar_pip(pacote):
        faltando = {modulo: erro for modulo in modulos if (erro := _erro_de_import(modulo))}
        if not faltando:
            return

    print(f"[preConfig] Aviso: não consegui garantir a dependência '{pacote}' automaticamente.")
    for modulo, erro in faltando.items():
        print(f"[preConfig]   - {modulo}: {erro}")

    dica_distro = _dica_pacote_da_distro(pacote)
    if dica_distro:
        print(f"[preConfig] Instale pela distribuição (recomendado no Linux): {dica_distro}")
    print(
        f"[preConfig] Ou, num ambiente virtual: python -m venv .venv && "
        f".venv/bin/pip install {pacote}"
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
        (pacote, modulos)
        for pacote, modulos, plataforma in _DEPENDENCIAS_PIP
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
    faltando = [
        (pacote, modulos)
        for pacote, modulos in dependencias
        if not all(_importa(modulo) for modulo in modulos)
    ]

    if not faltando:
        print("[preConfig] Todas as dependências Python já estão instaladas — nada para fazer, iniciando o app.")
    else:
        nomes = ", ".join(pacote for pacote, _ in faltando)
        print(f"[preConfig] Dependência(s) ausente(s) ou incompleta(s): {nomes}. Instalando...")
        for pacote, modulos in faltando:
            _garantir_modulo(pacote, modulos)

    _garantir_programas_sistema()


if __name__ == "__main__":
    garantir_dependencias()
