"""Registro de qual máquina entrou na malha local primeiro, segunda, etc. —
usado por services/comandaSequencialService.py para dar a cada máquina uma
letra estável (A, B, C...) por ORDEM DE ENTRADA, em vez da inicial do
hostname (que colide quando duas máquinas começam com a mesma letra).

Cada máquina, na primeira vez que aparece, ganha um id de
services/rede/relogio.py (novo_id()) como "prova de quando entrou" — o
próprio formato do id (timestamp físico + hostname) já serve pra isso, não
precisa de nada além. Esse id é persistido aqui pra sempre (nunca
regenerado enquanto o arquivo existir, o que é o que torna a letra estável
entre reinícios) e propagado pra malha via handshake (ver
services/rede/redeService.py:_mensagem_identificar/_processar_mensagem),
mesmo mecanismo já usado por "nomeMaquinaFixada" — não gossip nem
anti-entropy, porque a malha é sempre full-mesh e o handshake já roda a
cada conexão/reconexão, então basta pra espalhar a tabela inteira.

Guardado em pedidos/.sync/registro_maquinas.json (ver
services/rede/caminhos.py) — dado de sincronização entre máquinas, não
configuração local (por isso não fica em Config/, ao contrário de
impressoraFixada.py)."""

import os
import platform

from services.rede import caminhos, relogio

_ROTULO = "registroMaquinas"


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "registro_maquinas.json")


def _carregar():
    return caminhos.carregar_json(_caminho_arquivo(), _ROTULO)


def _salvar(dados):
    caminhos.salvar_json(_caminho_arquivo(), dados, _ROTULO)


def todos() -> dict:
    """{"nome_maquina": idEntrada, ...} de toda máquina já conhecida por
    esta — usado tanto para montar o payload do handshake quanto para
    calcular a ordem em letra()."""
    return _carregar()


def registrar_local() -> str:
    """Garante que esta máquina (platform.node()) tem uma entrada, criando
    uma com relogio.novo_id() na primeira vez. Idempotente — chamado tanto
    por RedeService.__init__ quanto por letra(), pra funcionar mesmo se a
    rede nunca for iniciada."""
    nome_local = platform.node() or "maquina-desconhecida"
    dados = _carregar()
    if nome_local not in dados:
        dados[nome_local] = relogio.novo_id()
        _salvar(dados)
    return dados[nome_local]


def mesclar(recebidos: dict) -> list:
    """Aplica entradas aprendidas de um peer (payload "registrosMaquinas"
    do handshake, ver services/rede/redeService.py). Máquina nova ->
    adiciona. Máquina já conhecida com id diferente -> fica com o mais
    antigo dos dois (relogio.mais_novo é o único comparador do projeto) —
    cobre o caso raro de uma máquina perder o arquivo local e se registrar
    de novo com um id mais recente; a malha corrige sozinha assim que ela
    reconectar em qualquer peer que ainda lembre do id antigo. Devolve os
    nomes que eram novidade aqui, só para log (mesmo padrão de
    tombstones.mesclar)."""
    if not recebidos:
        return []

    for id_recebido in recebidos.values():
        relogio.observar(id_recebido)

    dados = _carregar()
    novos = []
    mudou = False
    for nome, id_recebido in recebidos.items():
        if not nome or not id_recebido:
            continue
        atual = dados.get(nome)
        if atual is None:
            dados[nome] = id_recebido
            novos.append(nome)
            mudou = True
        elif id_recebido != atual and relogio.mais_novo(atual, id_recebido):
            # O que já tínhamos é mais novo que o recebido -> o recebido é
            # o registro histórico mais antigo e verdadeiro, fica com ele.
            dados[nome] = id_recebido
            mudou = True

    if mudou:
        _salvar(dados)
    return novos


def letra(nome_maquina: str = None) -> str:
    """Letra (A, B, C...) desta máquina (ou de `nome_maquina`, se passado)
    por ordem de entrada na malha: a primeira máquina que já existiu na
    malha (menor id, ou seja, mais antigo) é "A", a segunda "B", etc.
    Chama registrar_local() antes de tudo, então funciona mesmo se
    RedeService nunca tiver rodado (offline/standalone) — sempre lê o
    estado local, nunca espera resposta de rede."""
    nome_maquina = nome_maquina or platform.node() or "maquina-desconhecida"
    registrar_local()

    # Comparar os ids como string aqui é válido por construção: o próprio
    # relogio.py preenche fisico/logico com zeros à esquerda (ver
    # _LARGURA_FISICO/_LARGURA_LOGICO) justamente pra que a ordem
    # alfabética das strings seja a mesma ordem cronológica dos eventos.
    nomes_em_ordem = [nome for nome, _id in sorted(todos().items(), key=lambda par: par[1])]
    try:
        indice = nomes_em_ordem.index(nome_maquina)
    except ValueError:
        return "?"
    return chr(ord("A") + indice)
