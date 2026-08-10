#!/usr/bin/env python3
"""Garante que nenhum QML fora de qml/estilo/ traga valor de estilo cru.

Cor, raio, tamanho de fonte e espessura de borda moram todos em
qml/estilo/Estilo.qml, como design tokens. Sem uma checagem automática, o
próximo componente escrito reintroduz um "#ffffff" solto e a erosão recomeça —
foi assim que o projeto acumulou 700 cores hardcoded antes da tokenização.

Uso:
    python scripts/verifica_tokens.py          # falha (saída 1) se achar algo
    python scripts/verifica_tokens.py --lista  # só lista, sempre sai 0
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
QML = RAIZ / "qml"
# A pasta dos tokens é a única que pode conter valores crus: é a definição deles.
PASTA_TOKENS = QML / "estilo"

# (regex, explicação de qual token usar no lugar)
REGRAS: list[tuple[re.Pattern[str], str]] = [
    (
        re.compile(r'"#[0-9a-fA-F]{3,8}"'),
        "cor em hex — use Estilo.global.*, Estilo.action.*, Estilo.status.*, "
        "Estilo.screen.* ou Estilo.category.*",
    ),
    (
        re.compile(r'"(white|black|red|green|blue|gray|grey|yellow|orange|purple)"'),
        "cor por nome — use um token de Estilo.*",
    ),
    (
        re.compile(r"font\.pixelSize:\s*\d"),
        "tamanho de fonte cru — use Estilo.global.fontSize.{xs,sm,md,lg,xl,xxl,title,display}",
    ),
    (
        re.compile(r"(?<![.\w])radius:\s*\d"),
        "raio cru — use Estilo.global.radius.{xs,sm,md,lg,xl,pill}",
    ),
    (
        re.compile(r"border\.width:\s*\d"),
        "espessura de borda crua — use Estilo.global.borderWidth.{hairline,thick,focus}",
    ),
]

# "transparent" é ausência de cor, não uma cor da paleta: segue permitido.


def verifica() -> list[str]:
    achados = []
    for arquivo in sorted(QML.rglob("*.qml")):
        if PASTA_TOKENS in arquivo.parents:
            continue
        for numero, linha in enumerate(
            arquivo.read_text(encoding="utf-8").splitlines(), start=1
        ):
            for regex, dica in REGRAS:
                achado = regex.search(linha)
                if achado:
                    rel = arquivo.relative_to(RAIZ)
                    achados.append(
                        f"{rel}:{numero}: {achado.group(0)} — {dica}\n"
                        f"    {linha.strip()}"
                    )
                    break
    return achados


def main() -> int:
    achados = verifica()
    if not achados:
        print("Nenhum valor de estilo cru fora de qml/estilo/.")
        return 0

    for achado in achados:
        print(achado)
    print(f"\n{len(achados)} ocorrência(s) a tokenizar.")
    return 0 if "--lista" in sys.argv else 1


if __name__ == "__main__":
    raise SystemExit(main())
