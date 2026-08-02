"""Identificador estável e único desta máquina na malha — gerado uma vez
(uuid4) na primeira execução e persistido em disco pra nunca mudar entre
reinícios.

Existe porque nem hostname (platform.node(), usado por
services/rede/relogio.py e services/rede/impressoraFixada.py) nem o id de
instância de RedeService (uuid4 novo a cada execução) servem como chave de
"uma entrada por máquina física" em services/rede/registroMaquinas.py: duas
máquinas podem ter o MESMO hostname (visto em produção — duas máquinas
chamadas "Terminal01"), o que colapsava as duas na mesma entrada da tabela
de ordem de entrada e fazia as duas ganharem a MESMA letra no código da
comanda (ver services/comandaSequencialService.py). Um uuid gerado
localmente por máquina, e nunca a partir de hostname/rede, não tem como
colidir.

Guardado em pedidos/.sync/identidade_maquina.json — mesmo local de
services/rede/registroMaquinas.py, mas o conteúdo em si nunca é lido de
outra máquina: só esta o gera e o usa como sua própria chave. Apagar o
arquivo faz esta máquina "entrar de novo" na malha como se fosse uma
máquina nova (perde a posição/letra antiga, ganha uma nova)."""

import os
import uuid

from services.rede import caminhos

_ROTULO = "identidadeMaquina"


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "identidade_maquina.json")


def id_local() -> str:
    """Id desta máquina, gerando e persistindo um novo (uuid4().hex) na
    primeira chamada. Estável entre reinícios enquanto o arquivo existir."""
    dados = caminhos.carregar_json(_caminho_arquivo(), _ROTULO)
    id_existente = dados.get("id")
    if id_existente:
        return id_existente

    novo = uuid.uuid4().hex
    caminhos.salvar_json(_caminho_arquivo(), {"id": novo}, _ROTULO)
    return novo
