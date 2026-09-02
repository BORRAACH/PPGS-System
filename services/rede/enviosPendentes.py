"""Fila em disco das escritas destinadas ao ppgs_server que ainda não foram
confirmadas por ele.

Existe por causa de uma perda de dado real e silenciosa: o endereço do cliente
digitado na Entrega só era gravado se o servidor estivesse de pé NAQUELE
instante. Com a máquina hospedeira desligada (ou com o app dela fechado — o
servidor era filho do app), o cadastro simplesmente não acontecia, e o único
sinal disso era uma notificação passageira no canto da tela. A fila de reenvio
que existia vivia só na memória do PizzeriaServerService, então fechar o sistema
apagava junto tudo o que ainda não tinha subido.

Guardado em `pedidos/.sync/` (ver caminhos.pasta_sincronizacao) e não em
`Config/`: isto é dado em trânsito, não configuração da máquina — e aquela
pasta já está fora do git e fora de todos os scans de comanda.

A chave de cada item é o que deduplica a fila POR ENTIDADE, e não por
tentativa: dois salvamentos do mesmo telefone (o cliente corrigiu o número da
casa) viram um item só, o último. Isso só é correto porque toda rota usada aqui
é idempotente do lado do servidor:

- `POST /enderecos` é upsert por telefone (ver upsert_endereco_por_telefone em
  src/database/enderecos.rs do PPGS-Server);
- `POST /fechamentos` decide pelo `id_evento` do relógio lógico qual das versões
  do dia predomina (ver salvar_fechamento lá).

Reenviar um item já aplicado, portanto, converge para o mesmo estado em vez de
duplicar — é o que torna seguro tentar de novo sem levar registro de quais
tentativas já saíram.
"""

import os
import time

from services.rede import caminhos

_ARQUIVO = "envios_servidor.json"
_ROTULO = "enviosPendentes"


def _caminho_arquivo() -> str:
    return os.path.join(caminhos.pasta_sincronizacao(), _ARQUIVO)


def chave_endereco(telefone: str) -> str:
    """Um item por telefone: o cadastro é upsert, então só a versão mais nova
    de cada cliente precisa subir."""
    return f"endereco:{telefone}"


def chave_fechamento(data_iso: str) -> str:
    """Um item por dia, pelo mesmo motivo — quem arbitra duas versões do mesmo
    dia é o `id_evento`, já dentro do corpo."""
    return f"fechamento:{data_iso}"


def carregar() -> dict:
    """Tudo o que está esperando para subir, na forma
    `{chave: {"metodo", "caminho", "corpo", "criadoEm"}}`.

    Nunca levanta: um arquivo corrompido devolve fila vazia (ver
    caminhos.carregar_json). Perder a fila é ruim, mas travar o arranque do
    sistema por causa dela seria pior."""
    dados = caminhos.carregar_json(_caminho_arquivo(), _ROTULO)
    return {chave: item for chave, item in dados.items() if isinstance(item, dict)}


def _salvar(fila: dict) -> None:
    caminhos.salvar_json(_caminho_arquivo(), fila, _ROTULO)


def enfileirar(chave: str, metodo: str, caminho: str, corpo: str) -> None:
    """Grava (ou substitui) o item `chave`. `corpo` é o JSON já serializado —
    guardar o texto, e não o dict, mantém byte a byte o que vai ser postado, sem
    depender de o json.dumps de amanhã produzir a mesma coisa."""
    fila = carregar()
    fila[chave] = {
        "metodo": metodo,
        "caminho": caminho,
        "corpo": corpo,
        # Só para diagnóstico: nada aqui expira por idade. Um endereço que
        # esperou a noite inteira continua sendo o endereço do cliente.
        "criadoEm": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    _salvar(fila)


def remover(chave: str, corpo_confirmado: str | None = None) -> None:
    """Tira o item da fila depois de o servidor confirmar.

    `corpo_confirmado` existe para não apagar o item errado: entre o POST e a
    resposta dele, a mesma chave pode ter sido reenfileirada com dados mais
    novos (o caixa corrigiu o endereço enquanto a primeira requisição estava a
    caminho). Confirmar o corpo antigo não confirma o novo — sem esta guarda,
    a correção sumiria da fila sem nunca ter subido."""
    fila = carregar()
    item = fila.get(chave)
    if item is None:
        return
    if corpo_confirmado is not None and item.get("corpo") != corpo_confirmado:
        return
    del fila[chave]
    _salvar(fila)


def itens() -> list:
    """Os pendentes como `(chave, metodo, caminho, corpo)`, prontos para
    reenvio. Lista (e não iterador sobre o dict vivo) de propósito: quem drena
    a fila remove itens dela durante o percurso."""
    return [
        (chave, item.get("metodo") or "POST", item.get("caminho") or "", item.get("corpo") or "")
        for chave, item in carregar().items()
        if item.get("caminho")
    ]


def quantidade() -> int:
    return len(carregar())
