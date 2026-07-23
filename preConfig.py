"""Garante que as dependências do projeto (declaradas em pyproject.toml)
estão instaladas antes de rodar main.py.

Só usa a biblioteca padrão do Python — não pode depender de nada que ainda
não esteja instalado, senão vira um problema de ovo-e-galinha. Por isso
precisa ser importado e chamado ANTES de qualquer import de terceiros
(PyQt6, etc.) em main.py: se PyQt6 for importado primeiro e não estiver
instalado, o processo já morre com ModuleNotFoundError antes deste script
ter a chance de rodar.

Mantenha a lista `_DEPENDENCIAS` abaixo em sincronia com `dependencies` em
pyproject.toml.
"""

import importlib.util
import subprocess
import sys

# (nome do pacote a instalar via pip, módulo usado para checar se já está
# instalado, valor de sys.platform exigido ou None se vale para qualquer SO)
_DEPENDENCIAS = [
    ("PyQt6", "PyQt6.QtCore", None),
    ("pywin32", "win32print", "win32"),
]


def _instalada(modulo: str) -> bool:
    return importlib.util.find_spec(modulo) is not None


def _instalar(pacote: str) -> None:
    print(f"[preConfig] Instalando dependência ausente: {pacote}...")
    subprocess.run([sys.executable, "-m", "pip", "install", pacote], check=True)


def garantir_dependencias() -> None:
    """Verifica cada dependência do projeto e instala a que estiver faltando."""
    for pacote, modulo, plataforma in _DEPENDENCIAS:
        if plataforma and sys.platform != plataforma:
            continue
        if not _instalada(modulo):
            _instalar(pacote)


if __name__ == "__main__":
    garantir_dependencias()
