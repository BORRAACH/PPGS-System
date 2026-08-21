"""Registro das reservas de número de comanda do dia — o que faz os dois
últimos dígitos do código impresso (ver services/comandaSequencialService.py)
seguirem a linha de eventos da MALHA, e não a ordem de chegada dentro de uma
máquina só.

Antes, cada máquina contava sozinha num arquivo local: numa noite normal todas
elas imprimiam 01, depois 02, depois 03 — o número dizia respeito ao terminal,
não à loja. Aqui o número sai de um registro compartilhado: reservar é ler o
maior número que ESTA máquina conhece do dia, somar 1, gravar e anunciar.

Continua valendo o princípio de que lançar uma comanda NUNCA espera a rede
responder (mesmo motivo de RedeService.solicitar_impressao ser assíncrono): a
reserva é uma leitura e uma gravação locais, sem nenhum round-trip. O que
sincroniza é o registro, não a operação — o gossip (services/rede/eventos.py)
leva a reserva às outras máquinas em ~1 salto, bem antes de alguém conseguir
digitar a comanda seguinte.

Guardado em `pedidos/.sync/sequencia.json` (mesmo endereço de baixas.json/
contagem.json, ver services/rede/caminhos.py):
`{dataIso: {"1": idEvento, "2": idEvento, ...}}` — número -> id de
services/rede/relogio.py. Guardar o id (e não um `true`) sai de graça e diz
qual máquina reservou aquele número e em que ordem, justamente o que se quer
saber quando duas colidem.

**O conjunto só cresce e nunca reverte**, dentro de cada dia — é isso que torna
a sincronização livre de conflito por construção, mesmo raciocínio (e mesmo
desenho) de services/rede/baixaComandas.py: duas máquinas que reservem números
de forma independente convergem pela simples união dos dois mapas, sem ninguém
precisar arbitrar nada.

O que ISSO NÃO garante, deliberadamente: unicidade absoluta do número. Uma
máquina que esteja particionada da malha (cabo caiu, acabou de abrir) numera a
partir do que ela conhece, e pode repetir um número que outra já usou — travar
a venda até a rede responder seria pior. A letra da máquina continua no código
(ver RedeService.letraLocal), então o código impresso nunca fica idêntico mesmo
nesse caso. É exatamente a garantia que já existia antes deste módulo; a
diferença é que a colisão virou exceção (só em partição) em vez de regra."""

import os
from datetime import datetime, timedelta

from services.rede import caminhos, relogio

_ROTULO = "sequenciaComandas"

# Dias mantidos no arquivo. Uma reserva de ontem não pode mais ser reemitida
# (o dia é a chave, e o contador reinicia a cada dia), então guardá-la só
# gastaria disco.
#
# ATENÇÃO: esta janela e a que o resumo de anti-entropy anuncia (ver
# RedeService._resumo_sequencia) TÊM que ser a mesma. Anunciar um dia que a
# purga já apagou faz as máquinas se reintroduzirem o dia uma na outra a cada
# ciclo, para sempre — mesmo cuidado documentado em
# FechamentoController._resumo_baixas.
JANELA_DIAS = 7

# Maior número já devolvido por reservar() NESTE processo, por dia. O registro
# em disco é a fonte da verdade, mas ele pode voltar atrás (arquivo corrompido
# -> caminhos.carregar_json devolve {}), e devolver de novo um número já
# impresso em papel é pior que pular um. Só cresce, nunca é lido de disco.
_marca_dagua = {}


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "sequencia.json")


def carregar():
    """`{dataIso: {numero_str: idEvento}}` de todos os dias que esta máquina
    conhece — os que ela mesma reservou e os que aprendeu de outras."""
    return caminhos.carregar_json(_caminho_arquivo(), _ROTULO)


def _salvar(dados):
    caminhos.salvar_json(_caminho_arquivo(), dados, _ROTULO)


def dia(data_iso):
    """`{numero_str: idEvento}` reservados em `data_iso`, ou {} se o dia ainda
    não teve nenhuma comanda."""
    reservas = carregar().get(data_iso)
    return reservas if isinstance(reservas, dict) else {}


def _maior_numero(reservas):
    """Maior número de um mapa de reservas, ignorando chaves que não sejam
    inteiros — um payload de uma máquina com versão diferente, ou um arquivo
    editado à mão, não pode derrubar o lançamento de uma comanda."""
    maior = 0
    for chave in reservas:
        try:
            numero = int(chave)
        except (TypeError, ValueError):
            continue
        maior = max(maior, numero)
    return maior


def reservar(data_iso):
    """Reserva e devolve `(numero, idEvento)` — o próximo número de `data_iso`
    do ponto de vista desta máquina.

    Local e síncrono de propósito: nunca abre socket, nunca espera resposta.
    Quem chama (RedeService.reservar_numero_comanda) é que anuncia a reserva à
    malha depois — o mesmo desenho de transmitir_pedido, onde o fato nasce
    localmente num ponto só e é publicado logo em seguida."""
    dados = carregar()
    reservas = dados.get(data_iso)
    reservas = reservas if isinstance(reservas, dict) else {}

    numero = max(_maior_numero(reservas), _marca_dagua.get(data_iso, 0)) + 1
    id_evento = relogio.novo_id()

    reservas[str(numero)] = id_evento
    dados[data_iso] = reservas
    _marca_dagua[data_iso] = numero
    _salvar(dados)
    return numero, id_evento


def mesclar_dia(data_iso, reservas_recebidas):
    """Une o mapa de um dia vindo de outra máquina com o local. Devolve True
    só se aprendeu algo.

    Porta de entrada única do que vem de fora — serve tanto ao gossip (uma
    reserva só, um mapa de um elemento) quanto à anti-entropy e à
    republicação de catch-up (o dia inteiro). Um caminho só porque a operação
    é a mesma nos três casos: união pura, sem arbitrar nada. O conjunto só
    cresce, então depois de um ciclo em cada sentido as duas máquinas têm
    exatamente o mesmo mapa.

    Números que já existem aqui NÃO são regravados: trocar o id de quem
    realmente reservou por outro faria as duas máquinas anunciarem valores
    diferentes pra mesma reserva, e elas ficariam pedindo o mesmo dia uma pra
    outra a cada ciclo — mesmo cuidado de baixaComandas.registrar."""
    if not data_iso or not isinstance(reservas_recebidas, dict) or not reservas_recebidas:
        return False

    for id_evento in reservas_recebidas.values():
        relogio.observar(id_evento)

    dados = carregar()
    reservas = dados.get(data_iso)
    reservas = reservas if isinstance(reservas, dict) else {}

    novas = {}
    for chave, valor in reservas_recebidas.items():
        # Normaliza a chave (o JSON pode trazê-la como int) e descarta o que
        # não for número — um payload de uma versão diferente do app não pode
        # sujar o arquivo nem confundir _maior_numero.
        try:
            chave = str(int(chave))
        except (TypeError, ValueError):
            continue
        if chave not in reservas:
            novas[chave] = valor or relogio.novo_id()
    if not novas:
        return False

    reservas.update(novas)
    dados[data_iso] = reservas
    _salvar(dados)
    return True


def dias_recentes():
    """Os dias dentro da JANELA_DIAS, os únicos que valem anunciar/reconciliar.
    Um dia fora dela já foi purgado (ou está prestes a ser) em toda máquina."""
    limite = (datetime.now() - timedelta(days=JANELA_DIAS)).strftime("%Y-%m-%d")
    return {data_iso: reservas for data_iso, reservas in carregar().items() if data_iso >= limite}


def purgar_antigos():
    """Descarta os dias mais velhos que JANELA_DIAS. Chamado uma vez por ciclo
    de reconciliação (ver RedeService._resumo_sequencia), como
    baixaComandas.purgar_apagadas."""
    limite = (datetime.now() - timedelta(days=JANELA_DIAS)).strftime("%Y-%m-%d")
    dados = carregar()
    velhos = [data_iso for data_iso in dados if data_iso < limite]
    if not velhos:
        return

    for data_iso in velhos:
        del dados[data_iso]
    _salvar(dados)
