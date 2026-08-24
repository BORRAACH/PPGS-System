"""Persistência de qual máquina da malha hospeda o ppgs_server.

Mesmo desenho de services/rede/impressoraFixada.py, e pelo mesmo motivo:
guardado por NOME da máquina (`platform.node()`), nunca pelo id da instância
de RedeService — esse id é um uuid4 novo a cada execução, então persistir por
ele perderia a escolha no primeiro restart.

Diferente da impressora, a escolha aqui carrega junto um `idEvento` do
relógio lógico (services/rede/relogio.py). A impressora tolera divergência
temporária: se duas máquinas discordarem por alguns segundos sobre quem
imprime, no pior caso um cupom sai no lugar errado. Duas máquinas rodando o
servidor ao mesmo tempo é outra coisa — seriam dois bancos de endereços
divergindo em silêncio, cada um recebendo metade dos cadastros, sem nada na
tela denunciando. O idEvento resolve isso: quem receber duas designações
fica com a mais nova, e todas as máquinas chegam à mesma conclusão.

O arquivo local existe pra uma máquina que liga sozinha (as outras
desligadas, ou ela é a primeira do expediente) ainda saber que é ela quem
hospeda — sem isso o servidor só subiria depois que alguém mais aparecesse
na malha."""

import os

from services.rede import caminhos

_ARQUIVO = "servidor_designado.json"


def _caminho_arquivo() -> str:
    return os.path.join(caminhos.raiz_projeto(), "Config", _ARQUIVO)


def carregar() -> tuple[str, str]:
    """Devolve (nomeMaquina, idEvento). ("", "") quando ninguém foi
    designado ainda."""
    dados = caminhos.carregar_json(_caminho_arquivo(), "servidor designado")
    if not isinstance(dados, dict):
        return "", ""
    return dados.get("nomeMaquina") or "", dados.get("idEvento") or ""


def salvar(nome: str, id_evento: str) -> None:
    caminhos.salvar_json(
        _caminho_arquivo(),
        {"nomeMaquina": nome or "", "idEvento": id_evento or ""},
        "servidor designado",
    )
