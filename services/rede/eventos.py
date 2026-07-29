"""Propagação de eventos entre as máquinas da malha, por gossip: qualquer
mudança que as outras máquinas precisem saber — uma comanda nova, uma
comanda apagada, uma alteração no cardápio, ou qualquer evento futuro —
publica aqui uma vez, e quem recebe repassa adiante pra quem ainda não viu.

Separado de RedeService (que só cuida de sockets/descoberta/handshake) de
propósito: RedeService nunca precisa saber o que significa um "pedido_novo"
ou um "cardapio_alterado" — só carrega bytes de um lado pro outro. Quem
publica e quem escuta cada tipo de evento é sempre código de fora (ver
CardapioController.salvarItens/__init__, controllers/balcaoController.py,
controllers/consultaController.py), registrado pelo RedeService.publicarEvento/
registrarEvento (services/rede/redeService.py). Isso deixa "avisar a rede
de um tipo de mudança novo" uma questão de publicar/registrar aqui, sem
tocar em código de socket.

A malha hoje é sempre full-mesh (poucas máquinas — no máximo 4 — cada uma
conectada direto com todas as outras, ver RedeService), então um evento
publicado chega em 1 salto na prática. O protocolo de gossip abaixo (id
único + dedup + repassar pra quem ainda não viu, exceto de volta pra quem
acabou de mandar) continua correto mesmo assim — só significa que a mesma
mensagem às vezes chega por dois caminhos e a segunda é descartada — e
continua correto se a malha um dia deixar de ser full-mesh (ex: duas
máquinas que não conseguem abrir conexão direta uma com a outra, mas ambas
alcançam uma terceira)."""

import time

from services.rede import relogio

# Tempo que um id de evento fica guardado só pra descartar reentregas (a
# mesma mensagem chegando por dois caminhos na malha) — não precisa durar
# mais que alguns minutos: depois disso, se o id "reaparecesse" seria uma
# mensagem nova de verdade (dois ids de relogio.novo_id() colidirem de
# propósito não é uma preocupação real aqui).
_TTL_VISTOS_SEGUNDOS = 10 * 60


class BarramentoEventos:
    """`enviar_para_peers(evento, socket_excluido)` é injetado por quem
    monta este objeto (RedeService) — este módulo não sabe nada de
    QTcpSocket nem do protocolo JSON por linha, só de publicar/repassar
    dicts. `socket_excluido` pode ser None (publicação local: manda pra
    todo mundo que estiver conectado)."""

    def __init__(self, enviar_para_peers):
        self._enviar_para_peers = enviar_para_peers
        self._manipuladores = {}  # tipo do evento -> [callback(payload), ...]
        self._vistos = {}  # id do evento -> timestamp de quando foi visto

    def registrar(self, tipo_evento, callback):
        """`callback(payload)` roda toda vez que um evento `tipo_evento`
        chega de outra máquina (nunca para os que esta própria máquina
        publica — ver publicar())."""
        self._manipuladores.setdefault(tipo_evento, []).append(callback)

    def publicar(self, tipo_evento, payload):
        """Anuncia um evento novo, desta máquina, pra malha inteira. Não
        chama os manipuladores locais: quem publica já sabe o que
        aconteceu (foi quem fez acontecer) — os manipuladores existem só
        para reagir a eventos que vieram de fora.

        O "id" do evento é gerado por relogio.novo_id() (ver
        services/rede/relogio.py) em vez de um uuid aleatório — serve tanto
        pra dedup de gossip (papel que um uuid já cumpria) quanto pra dar a
        cada mudança de estado um lugar na linha do tempo comum da malha,
        sem que quem chama publicar() precise pensar nisso."""
        evento = {"id": relogio.novo_id(), "tipoEvento": tipo_evento, "payload": payload}
        self._marcar_visto(evento["id"])
        self._enviar_para_peers(evento, None)

    def receber(self, mensagem, socket_origem):
        """Chamado por RedeService quando uma mensagem `{"tipo": "evento",
        ...}` chega de um peer. Ignora reentregas (mesmo id já visto —
        inevitável numa malha onde mais de um caminho leva à mesma
        máquina) e repassa pra quem ainda não viu, exceto de volta pra
        quem acabou de mandar."""
        id_evento = mensagem.get("id")
        tipo_evento = mensagem.get("tipoEvento")
        if not id_evento or not tipo_evento:
            return

        # Mantém o relógio lógico desta máquina alinhado com QUALQUER
        # evento visto na malha, mesmo tipos que este módulo não conhece e
        # mesmo reentregas (idempotente) — é o que garante que o próximo
        # id gerado localmente (relogio.novo_id()) nunca fique "atrás" de
        # algo que esta máquina já sabe que aconteceu em outro lugar.
        relogio.observar(id_evento)

        self._purgar_vistos_antigos()
        if id_evento in self._vistos:
            return
        self._marcar_visto(id_evento)

        payload = mensagem.get("payload")
        for callback in self._manipuladores.get(tipo_evento, []):
            callback(payload)

        evento = {"id": id_evento, "tipoEvento": tipo_evento, "payload": payload}
        self._enviar_para_peers(evento, socket_origem)

    def _marcar_visto(self, id_evento):
        self._vistos[id_evento] = time.time()

    def _purgar_vistos_antigos(self):
        limite = time.time() - _TTL_VISTOS_SEGUNDOS
        expirados = [id_evento for id_evento, quando in self._vistos.items() if quando < limite]
        for id_evento in expirados:
            del self._vistos[id_evento]
