"""Persistência da escolha manual de qual máquina da malha imprime (ver
RedeService.fixarImpressoraPrincipal/qml/pages/rede/Rede.qml).

Guardado por NOME da máquina (platform.node()), nunca pelo id da instância
de RedeService (esse id é gerado do zero — uuid4 — a cada execução do app,
então persistir por ele quebraria a escolha a cada restart).

Persistido em Config/impressora_fixada.json — fora do git (é preferência
de rede local, não código-fonte), igual a Config/estilo_impressao.json
(ver services/comandaEstiloService.py)."""

import json
import os


def _raiz_projeto():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _caminho_arquivo():
    return os.path.join(_raiz_projeto(), "Config", "impressora_fixada.json")


def carregar_nome_fixado():
    """Nome da máquina fixada manualmente como impressora principal, ou
    None se nunca foi escolhida (ou a escolha foi revertida pra
    automático)."""
    caminho = _caminho_arquivo()
    if not os.path.isfile(caminho):
        return None

    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            dados = json.load(arquivo)
    except (OSError, json.JSONDecodeError) as erro:
        print(f"[impressoraFixada] Falha ao ler {caminho}: {erro} — assumindo eleição automática.")
        return None

    nome = dados.get("nomeMaquina")
    return nome or None


def salvar_nome_fixado(nome):
    """Grava `nome` (string) como a máquina fixada, ou apaga o arquivo
    quando `nome` for None/vazio (volta pra eleição automática)."""
    caminho = _caminho_arquivo()

    if not nome:
        try:
            os.remove(caminho)
        except FileNotFoundError:
            pass
        except OSError as erro:
            print(f"[impressoraFixada] Falha ao remover {caminho}: {erro}")
        return

    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
        with open(caminho, "w", encoding="utf-8") as arquivo:
            json.dump({"nomeMaquina": nome}, arquivo, indent=2, ensure_ascii=False)
    except OSError as erro:
        print(f"[impressoraFixada] Falha ao gravar {caminho}: {erro}")
