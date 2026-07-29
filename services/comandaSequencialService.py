"""Código curto impresso no cabeçalho de cada comanda (ver
controllers/balcaoController.py, entregaController.py, salaoController.py)
— não é o identificador de verdade de uma comanda (isso continua sendo o
nome do arquivo, único por timestamp+sufixo aleatório, ver cada
controller), é só um código fácil de ler/falar/anotar em papel.

Cada caractere carrega uma informação (ver gerar_codigo_pedido): a máquina
onde o pedido foi lançado, o dia e a hora, e por último a ordem de chegada
do pedido NESTA MÁQUINA no dia — reiniciada a cada dia novo.

Deliberadamente NÃO sincronizado pela rede nem coordenado entre máquinas:
um contador realmente único pra loja inteira (contando junto pedidos de
Balcão/Entrega/Salão não importa em qual máquina) exigiria uma máquina
"líder" distribuindo cada número pela rede — e lançar uma comanda não pode
ficar esperando isso responder (mesmo princípio de
RedeService.solicitar_impressao ser assíncrono: uma operação local nunca
deve travar por causa da rede). Como a letra da máquina já entra no
código, dois pedidos nunca saem com o código idêntico mesmo que a
"ordem do dia" numérica coincida.

Persistido na pasta de cache do SO (QStandardPaths), mesmo lugar/motivo de
services/rede/fechamentoCache.py — dado local e descartável (reinicia
sozinho a cada dia), não configuração nem comanda de verdade."""

import json
import os
import platform
from datetime import date

from PyQt6.QtCore import QStandardPaths


def _caminho_arquivo():
    base = QStandardPaths.writableLocation(QStandardPaths.StandardLocation.CacheLocation)
    return os.path.join(base, "sequencia_comandas.json")


def _carregar():
    caminho = _caminho_arquivo()
    if not os.path.isfile(caminho):
        return {}
    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            dados = json.load(arquivo)
    except (OSError, json.JSONDecodeError) as erro:
        print(f"[comandaSequencialService] Falha ao ler {caminho}: {erro} — reiniciando contagem do dia.")
        return {}
    return dados if isinstance(dados, dict) else {}


def _salvar(dados):
    caminho = _caminho_arquivo()
    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
        with open(caminho, "w", encoding="utf-8") as arquivo:
            json.dump(dados, arquivo)
    except OSError as erro:
        print(f"[comandaSequencialService] Falha ao gravar {caminho}: {erro}")


def _proximo_numero_do_dia(data_referencia):
    """Incrementa e devolve o número de sequência desta máquina para
    `data_referencia` (um date) — reinicia em 1 sempre que o dia salvo por
    último for diferente do de hoje (arquivo de uma linha só, não precisa
    purgar histórico de dias antigos)."""
    dados = _carregar()
    data_iso = data_referencia.isoformat()
    numero = dados.get("numero", 0) + 1 if dados.get("data") == data_iso else 1
    _salvar({"data": data_iso, "numero": numero})
    return numero


def gerar_codigo_pedido(agora):
    """Código de 7 caracteres pro cabeçalho da comanda impressa, a partir
    do `agora` (datetime) já usado por quem chama para o campo "Data:" —
    recebido como parâmetro em vez de chamar datetime.now() de novo aqui,
    pra nunca poder divergir do horário realmente impresso na comanda:

    - 1 letra: início do nome desta máquina (platform.node()).
    - 2 dígitos: dia do mês.
    - 2 dígitos: hora (24h).
    - 2 dígitos: ordem de chegada do pedido nesta máquina hoje (01, 02...).

    Ex: "C291401" = máquina começando com "C", dia 29, 14h, 1º pedido
    lançado nesta máquina no dia."""
    maquina = (platform.node() or "?")[:1].upper()
    numero = _proximo_numero_do_dia(agora.date())
    return f"{maquina}{agora.day:02d}{agora.hour:02d}{numero:02d}"
