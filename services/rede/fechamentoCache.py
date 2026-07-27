"""Persistência do resumo de fechamento de caixa — um JSON por dia, na
pasta de cache do sistema operacional (via QStandardPaths, já embutido no
Qt — sem dependência nova).

Fora da pasta do projeto de propósito (diferente de Config/*.json e
pedidos/*.txt): fechamento é um snapshot recalculável a qualquer momento
(ver FechamentoController), não configuração de máquina nem dado primário
— o dado primário continua sendo pedidos/*.txt; isto aqui é só cache.

Um arquivo por dia (nome = a própria data) é o que dá O(1) tanto pra
carregar quanto pra salvar um dia específico — nunca precisa listar
diretório nem tocar em nenhum outro dia, mesmo depois de anos de uso.

Depende de main.py já ter chamado QGuiApplication.setApplicationName(...)/
setOrganizationName(...) antes de qualquer chamada aqui — sem isso,
QStandardPaths.writableLocation() cai num caminho baseado no nome do
executável (ex: "python3", "-c"), inconsistente entre execuções."""

import json
import os

from PyQt6.QtCore import QStandardPaths


def _pasta_fechamentos():
    base = QStandardPaths.writableLocation(QStandardPaths.StandardLocation.CacheLocation)
    return os.path.join(base, "fechamentos")


def _caminho_arquivo(data_iso):
    return os.path.join(_pasta_fechamentos(), f"{data_iso}.json")


def carregar(data_iso):
    """Resumo já salvo para `data_iso` ("AAAA-MM-DD"), ou None se esse dia
    nunca foi calculado/salvo antes nesta máquina (primeira vez que alguém
    abre esse dia, ou cache limpo pelo SO)."""
    caminho = _caminho_arquivo(data_iso)
    if not os.path.isfile(caminho):
        return None

    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            return json.load(arquivo)
    except (OSError, json.JSONDecodeError) as erro:
        print(f"[fechamentoCache] Falha ao ler {caminho}: {erro}")
        return None


def salvar(data_iso, resumo):
    caminho = _caminho_arquivo(data_iso)
    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
        with open(caminho, "w", encoding="utf-8") as arquivo:
            json.dump(resumo, arquivo, indent=2, ensure_ascii=False)
    except OSError as erro:
        print(f"[fechamentoCache] Falha ao gravar {caminho}: {erro}")
        return False
    return True
