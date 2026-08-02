"""Registro de qual máquina entrou na malha local primeiro, segunda, etc. —
usado por services/comandaSequencialService.py para dar a cada máquina uma
letra estável (A, B, C...) por ORDEM DE ENTRADA.

Chaveado pelo id de services/rede/identidadeMaquina.py (um uuid gerado e
persistido localmente na primeira execução), não por hostname
(platform.node()): duas máquinas reais já apareceram na malha com o MESMO
hostname ("Terminal01" em ambas) — indexar por hostname colapsaria as duas
na mesma entrada, e as duas sairiam com a mesma letra, que é justamente o
tipo de colisão que este módulo existe pra evitar (a versão anterior só
evitava colidir a INICIAL do hostname, não o hostname inteiro).

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

from services.rede import caminhos, identidadeMaquina, relogio

_ROTULO = "registroMaquinas"


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "registro_maquinas.json")


def _carregar():
    return caminhos.carregar_json(_caminho_arquivo(), _ROTULO)


def _salvar(dados):
    caminhos.salvar_json(_caminho_arquivo(), dados, _ROTULO)


def todos() -> dict:
    """{"idMaquina": idEntrada, ...} de toda máquina já conhecida por
    esta — usado tanto para montar o payload do handshake quanto para
    calcular a ordem em letra(). "idMaquina" é o uuid de
    services/rede/identidadeMaquina.py, não hostname."""
    return _carregar()


def registrar_local() -> str:
    """Garante que esta máquina (identidadeMaquina.id_local()) tem uma
    entrada, criando uma com relogio.novo_id() na primeira vez. Idempotente
    — chamado tanto por RedeService.__init__ quanto por letra(), pra
    funcionar mesmo se a rede nunca for iniciada."""
    id_local = identidadeMaquina.id_local()
    dados = _carregar()
    if id_local not in dados:
        dados[id_local] = relogio.novo_id()
        _salvar(dados)
    return dados[id_local]


def mesclar(recebidos: dict) -> list:
    """Aplica entradas aprendidas de um peer (payload "registrosMaquinas"
    do handshake, ver services/rede/redeService.py). Máquina nova ->
    adiciona. Máquina já conhecida com id diferente -> fica com o mais
    antigo dos dois (relogio.mais_novo é o único comparador do projeto) —
    cobre o caso raro de uma máquina perder o arquivo local e se registrar
    de novo com um id mais recente; a malha corrige sozinha assim que ela
    reconectar em qualquer peer que ainda lembre do id antigo. Devolve os
    ids que eram novidade aqui, só para log (mesmo padrão de
    tombstones.mesclar)."""
    if not recebidos:
        return []

    for id_recebido in recebidos.values():
        relogio.observar(id_recebido)

    dados = _carregar()
    novos = []
    mudou = False
    for id_maquina, id_recebido in recebidos.items():
        if not id_maquina or not id_recebido:
            continue
        atual = dados.get(id_maquina)
        if atual is None:
            dados[id_maquina] = id_recebido
            novos.append(id_maquina)
            mudou = True
        elif id_recebido != atual and relogio.mais_novo(atual, id_recebido):
            # O que já tínhamos é mais novo que o recebido -> o recebido é
            # o registro histórico mais antigo e verdadeiro, fica com ele.
            dados[id_maquina] = id_recebido
            mudou = True

    if mudou:
        _salvar(dados)
    return novos


def letra(id_maquina: str = None) -> str:
    """Letra (A, B, C...) desta máquina (ou de `id_maquina`, se passado)
    por ordem de entrada na malha: a primeira máquina que já existiu na
    malha (menor id, ou seja, mais antigo) é "A", a segunda "B", etc.
    Chama registrar_local() antes de tudo, então funciona mesmo se
    RedeService nunca tiver rodado (offline/standalone) — sempre lê o
    estado local, nunca espera resposta de rede."""
    id_maquina = id_maquina or identidadeMaquina.id_local()
    registrar_local()

    # Comparar os ids como string aqui é válido por construção: o próprio
    # relogio.py preenche fisico/logico com zeros à esquerda (ver
    # _LARGURA_FISICO/_LARGURA_LOGICO) justamente pra que a ordem
    # alfabética das strings seja a mesma ordem cronológica dos eventos.
    ids_em_ordem = [id_ for id_, _id_entrada in sorted(todos().items(), key=lambda par: par[1])]
    try:
        indice = ids_em_ordem.index(id_maquina)
    except ValueError:
        return "?"
    return chr(ord("A") + indice)
