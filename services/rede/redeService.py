import base64
import json
import os
import platform
import threading
import time
import uuid

from PyQt6.QtCore import QObject, QByteArray, QTimer, pyqtProperty, pyqtSignal, pyqtSlot
from PyQt6.QtNetwork import QHostAddress, QTcpServer, QTcpSocket

from services.printerService import PrinterService
from services.rede import impressoraFixada
from services.rede.descoberta import criar_descoberta
from services.rede.eventos import BarramentoEventos

_INTERVALO_CHECAGEM_IMPRESSORA_MS = 30000
_TIMEOUT_IMPRESSAO_MS = 10000


class RedeService(QObject):
    """Compartilha pedidos entre instâncias deste app na mesma rede local, e
    elege/anuncia qual máquina da malha imprime as comandas.

    Topologia em malha completa: como há no máximo poucas máquinas (4), cada
    instância se conecta diretamente a todas as outras que descobrir na rede
    (ver services/rede/descoberta.py) — na prática um evento publicado (ver
    abaixo) já chega em 1 salto em todo mundo, mas o protocolo por trás não
    depende disso continuar sendo verdade.

    Além de bytes entrando e saindo (quem grava/apaga os .txt em disco são os
    sinais conectados pelos controllers, ver main.py), esta classe também
    decide, de forma determinística e independente em cada instância, qual
    máquina da malha está com a impressora física conectada — ver
    _recalcular_maquina_impressora — e roteia os pedidos de impressão
    (solicitar_impressao) só pra ela, em vez de cada máquina imprimir na sua
    própria impressora local.

    A propagação de "avisos pra malha inteira" (comanda nova, comanda
    apagada, cardápio alterado...) não vive aqui — é toda feita por
    services/rede/eventos.py (BarramentoEventos), que implementa o
    protocolo de gossip (id único + dedup + repassar adiante). Esta classe
    só liga esse barramento aos sockets (ver _propagar_evento) e traduz
    entre "chegou um evento de tipo X" e os sinais Qt que os controllers
    escutam (ver _ao_receber_evento_pedido_novo/_ao_receber_evento_pedido_apagado)
    — CardapioController usa o mesmo barramento diretamente, via
    publicarEvento/registrarEvento, para o tipo "cardapio_alterado", sem
    que esta classe precise saber nada sobre cardápio."""

    pedidoRecebido = pyqtSignal(str, QByteArray)
    pedidoRemovidoRemoto = pyqtSignal(str)
    peersMudaram = pyqtSignal(int)
    # Emitido quando o resultado de um pedido de impressão é conhecido
    # (sucesso, nome da máquina que imprimiu ou motivo da falha).
    impressaoResultado = pyqtSignal(bool, str)
    # Emitido sempre que a máquina eleita pra imprimir (ou os dados da
    # impressora dela) pode ter mudado — Rede.qml usa pra reconsultar
    # impressoraPrincipal() e atualizar o painel sozinho.
    impressoraPrincipalMudou = pyqtSignal()
    # Uso interno: repassa o resultado da checagem da impressora local (rodada
    # numa thread, porque PrinterService.localizar_impressora() executa
    # lpstat/PowerShell) de volta pra thread principal — mesmo padrão de
    # BalcaoController.infoImpressoraPronta.
    _impressoraLocalVerificada = pyqtSignal(bool, object)
    # Uso interno: repassa o resultado de um job de impressão pedido por
    # OUTRA máquina (mensagem "imprimir", ver _processar_mensagem) de volta
    # pra thread principal — a impressão em si roda numa thread à parte
    # (pode levar vários segundos e não pode bloquear a UI nem o
    # processamento de outras mensagens da malha), mas o envio da resposta
    # de volta pelo socket (QTcpSocket) só é seguro a partir da thread que
    # o criou. Carrega id_remetente (pra achar o socket atual do peer,
    # ver _peers) em vez do próprio socket, porque a conexão pode já ter
    # caído por outro motivo enquanto a impressão ainda rodava.
    _imprimirRemotoConcluido = pyqtSignal(str, str, bool, str)

    def __init__(self):
        super().__init__()
        self._id = uuid.uuid4().hex
        self._nome_local = platform.node() or "Máquina desconhecida"
        self._peers = {}  # id da instância -> QTcpSocket
        self._info_peers = {}  # id da instância -> {"nome", "endereco", "conectadoEm", "temImpressora", "infoImpressora"}
        self._buffers = {}  # QTcpSocket -> bytearray (linhas JSON incompletas)
        self._iniciado = False

        self._printer_service = PrinterService()
        self._tem_impressora = False
        # {"nome", "modelo", "fabricante", "tipoPorta", "porta"} da
        # impressora local, ou None — só preenchido quando _tem_impressora.
        self._info_impressora_local = None
        # Id da máquina (pode ser self._id) escolhida pra receber comandas de
        # impressão; None = nenhuma máquina conhecida tem impressora agora.
        self._id_maquina_impressora = None
        # Nome (platform.node(), estável entre execuções — diferente de
        # id_maquina/self._id, que é gerado do zero a cada processo) da
        # máquina fixada manualmente como impressora principal pela tela
        # Rede.qml, ou None pra eleição automática (ver
        # _recalcular_maquina_impressora/fixarImpressoraPrincipal).
        # Carregado do disco aqui pra sobreviver a um restart do app;
        # propagado/atualizado depois via gossip (evento "impressora_fixada").
        self._nome_maquina_fixada = impressoraFixada.carregar_nome_fixado()
        self._jobs_impressao = {}  # job_id -> {"timer": QTimer, "concluido": bool}

        self._tcp_server = QTcpServer(self)
        self._timer_impressora = QTimer(self)
        self._descoberta = criar_descoberta(self)

        self._eventos = BarramentoEventos(self._propagar_evento)
        self._eventos.registrar("pedido_novo", self._ao_receber_evento_pedido_novo)
        self._eventos.registrar("pedido_apagado", self._ao_receber_evento_pedido_apagado)
        self._eventos.registrar("impressora_fixada", self._ao_receber_evento_impressora_fixada)

        self._impressoraLocalVerificada.connect(self._ao_verificar_impressora_local)
        self._imprimirRemotoConcluido.connect(self._ao_concluir_imprimir_remoto)
        self._descoberta.peerDescoberto.connect(self._ao_descobrir_peer)

    @pyqtProperty(int, notify=peersMudaram)
    def quantidadeConectados(self):
        return len(self._peers)

    @pyqtProperty(str, constant=True)
    def nomeLocal(self):
        return self._nome_local

    @pyqtSlot(result="QVariantList")
    def listarPeers(self):
        """Máquinas atualmente conectadas na malha, mais recente primeiro."""
        peers = list(self._info_peers.values())
        peers.sort(key=lambda peer: peer["conectadoEm"], reverse=True)
        return peers

    def iniciar(self):
        """Abre os sockets e começa a anunciar/descobrir peers. Precisa ser
        chamado depois que QGuiApplication já existe."""
        if self._iniciado:
            return
        self._iniciado = True

        self._tcp_server.newConnection.connect(self._ao_conectar_entrada)
        if not self._tcp_server.listen(QHostAddress.SpecialAddress.Any, 0):
            print("RedeService: falha ao abrir porta TCP para a malha local")
            return

        # A porta TCP é sorteada pelo sistema (listen na porta 0), então só
        # dá pra anunciá-la depois que o servidor está de pé.
        self._descoberta.iniciar(self._id, self._tcp_server.serverPort())

        # Detecta a impressora local uma vez já ao iniciar, e depois
        # periodicamente — cobre o caso de a impressora ser plugada com o
        # app já aberto.
        self._detectar_impressora_local()
        self._timer_impressora.timeout.connect(self._detectar_impressora_local)
        self._timer_impressora.start(_INTERVALO_CHECAGEM_IMPRESSORA_MS)

    # ---------- Descoberta ----------

    def _ao_descobrir_peer(self, id_remoto: str, endereco: str, porta_tcp: int):
        """Uma instância apareceu na rede (ver services/rede/descoberta.py).
        A descoberta avisa de tudo que encontra, inclusive desta própria
        máquina e de peers repetidos — filtrar é aqui, que é quem sabe com
        quem já existe conexão aberta."""
        if id_remoto == self._id or id_remoto in self._peers:
            return

        # Só quem tem o id "menor" disca — evita os dois lados abrirem
        # conexão um pro outro ao mesmo tempo.
        if self._id < id_remoto:
            self._conectar_a(QHostAddress(endereco), porta_tcp)

    # ---------- Conexões TCP (malha) ----------

    def _conectar_a(self, endereco: QHostAddress, porta: int):
        socket = QTcpSocket(self)
        self._preparar_socket(socket)
        socket.connectToHost(endereco, porta)

    def _ao_conectar_entrada(self):
        while self._tcp_server.hasPendingConnections():
            socket = self._tcp_server.nextPendingConnection()
            self._preparar_socket(socket)

    def _mensagem_identificar(self):
        return {
            "tipo": "identificar",
            "id": self._id,
            "nome": self._nome_local,
            "temImpressora": self._tem_impressora,
            "infoImpressora": self._info_impressora_local,
            # Vai junto no handshake (não só no evento de gossip
            # "impressora_fixada") pra uma máquina que conecta/reconecta
            # DEPOIS de a fixação já ter sido escolhida em outra máquina
            # também ficar sabendo — sem isso, só quem já estava conectado
            # no exato momento da escolha recebia o evento (ver
            # BarramentoEventos.publicar, que só manda pra quem está
            # conectado agora); uma máquina nova nunca aprendia a fixação
            # existente por nenhum outro caminho, nem reiniciando (nada
            # disso fica salvo no disco DELA até ela mesma receber o aviso
            # ao menos uma vez — ver _ao_receber_identificar_fixacao).
            "nomeMaquinaFixada": self._nome_maquina_fixada,
        }

    def _preparar_socket(self, socket: QTcpSocket):
        self._buffers[socket] = bytearray()
        socket.readyRead.connect(lambda: self._ao_ler(socket))
        socket.disconnected.connect(lambda: self._ao_desconectar(socket))
        socket.errorOccurred.connect(lambda _erro: socket.close())
        # Handshake: cada lado se identifica (id + nome da máquina + se tem
        # impressora agora) assim que a conexão abre. Montada sob demanda (em
        # vez de um dict fixo) porque _tem_impressora pode só ficar
        # conhecido depois que o socket já foi preparado.
        socket.connected.connect(lambda: self._enviar(socket, self._mensagem_identificar()))
        if socket.state() == QTcpSocket.SocketState.ConnectedState:
            self._enviar(socket, self._mensagem_identificar())

    def _ao_desconectar(self, socket: QTcpSocket):
        # Tudo aqui pode falhar com RuntimeError se a desconexão chegar
        # durante o encerramento do app (o objeto Qt em C++ por trás do
        # socket, ou o próprio RedeService, já pode ter sido destruído) —
        # nesse ponto não há mais nada útil a fazer, então só ignora.
        try:
            self._buffers.pop(socket, None)
            id_removido = None
            for id_peer, sock in list(self._peers.items()):
                if sock is socket:
                    id_removido = id_peer
                    del self._peers[id_peer]
            socket.deleteLater()
            if id_removido is not None:
                self._info_peers.pop(id_removido, None)
                self.peersMudaram.emit(len(self._peers))
                # Se a máquina que caiu era a eleita pra imprimir, reeleger
                # (ou ficar sem impressora) na hora, sem esperar nada.
                self._recalcular_maquina_impressora()
        except RuntimeError:
            pass

    def _id_do_socket(self, socket: QTcpSocket):
        for id_peer, sock in self._peers.items():
            if sock is socket:
                return id_peer
        return None

    # ---------- Protocolo (JSON delimitado por "\n") ----------

    def _enviar(self, socket: QTcpSocket, mensagem: dict):
        if socket.state() != QTcpSocket.SocketState.ConnectedState:
            return
        socket.write(json.dumps(mensagem).encode("utf-8") + b"\n")

    def _ao_ler(self, socket: QTcpSocket):
        buffer = self._buffers.setdefault(socket, bytearray())
        buffer.extend(bytes(socket.readAll()))

        while b"\n" in buffer:
            linha, _, resto = buffer.partition(b"\n")
            del buffer[: len(linha) + 1]
            if not linha.strip():
                continue
            try:
                mensagem = json.loads(linha.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                continue
            self._processar_mensagem(socket, mensagem)

    def _processar_mensagem(self, socket: QTcpSocket, mensagem: dict):
        tipo = mensagem.get("tipo")

        if tipo == "identificar":
            id_remoto = mensagem.get("id")
            if not id_remoto:
                socket.close()
                return
            if id_remoto in self._peers:
                # Conexão redundante com um peer que já temos — descarta.
                socket.close()
                return
            self._peers[id_remoto] = socket
            self._info_peers[id_remoto] = {
                "id": id_remoto,
                "nome": mensagem.get("nome") or "Máquina desconhecida",
                "endereco": socket.peerAddress().toString(),
                "conectadoEm": time.time(),
                "temImpressora": bool(mensagem.get("temImpressora")),
                "infoImpressora": mensagem.get("infoImpressora"),
            }
            adotou_fixacao = self._ao_receber_identificar_fixacao(mensagem.get("nomeMaquinaFixada"))
            self.peersMudaram.emit(len(self._peers))
            self._recalcular_maquina_impressora()
            if adotou_fixacao:
                # _recalcular_maquina_impressora só emite impressoraPrincipalMudou
                # se o candidato eleito mudar — mas Rede.qml também depende
                # desse sinal pra atualizar nomeMaquinaFixada/candidatosImpressora
                # (ver fixarImpressoraPrincipal, mesmo motivo documentado lá).
                self.impressoraPrincipalMudou.emit()
            # Assim que os dois se identificam, trocam a lista de arquivos
            # locais pra resolver o catch-up de quem ficou offline.
            self._enviar(socket, {"tipo": "meus_arquivos", "arquivos": self._listar_arquivos_locais()})

        elif tipo == "meus_arquivos":
            arquivos_remotos = set(mensagem.get("arquivos", []))
            faltando = arquivos_remotos - set(self._listar_arquivos_locais())
            for nome in faltando:
                self._enviar(socket, {"tipo": "pedir_arquivo", "arquivo": nome})

        elif tipo == "pedir_arquivo":
            nome = mensagem.get("arquivo", "")
            conteudo = self._ler_arquivo_local(nome)
            if conteudo is not None:
                self._enviar(socket, {
                    "tipo": "pedido",
                    "arquivo": nome,
                    "conteudo_b64": base64.b64encode(conteudo).decode("ascii"),
                })

        elif tipo == "pedido":
            # Resposta direta ao catch-up pedido em "pedir_arquivo" — não
            # passa pelo barramento de eventos: não é um anúncio pra malha
            # inteira, é a resposta a UM pedido específico de UMA máquina
            # que acabou de reconectar e está preenchendo o que perdeu.
            self._emitir_pedido_recebido(mensagem.get("arquivo", ""), mensagem.get("conteudo_b64", ""))

        elif tipo == "evento":
            self._eventos.receber(mensagem, socket)

        elif tipo == "status_impressora":
            id_remoto = self._id_do_socket(socket)
            if id_remoto is not None and id_remoto in self._info_peers:
                self._info_peers[id_remoto]["temImpressora"] = bool(mensagem.get("temImpressora"))
                self._info_peers[id_remoto]["infoImpressora"] = mensagem.get("infoImpressora")
                self._recalcular_maquina_impressora()

        elif tipo == "imprimir":
            job_id = mensagem.get("job_id", "")
            conteudo_b64 = mensagem.get("conteudo_b64", "")
            if not conteudo_b64:
                return
            try:
                conteudo = base64.b64decode(conteudo_b64)
            except ValueError:
                return
            # A impressão em si (chamada bloqueante ao spooler/CUPS, pode
            # levar vários segundos) roda numa thread à parte — processar
            # esta mensagem síncrono aqui travaria a UI desta máquina (e o
            # processamento de qualquer outra mensagem da malha) até o job
            # terminar. O resultado volta pela thread principal via sinal
            # (ver _imprimirRemotoConcluido/_ao_concluir_imprimir_remoto) —
            # QTcpSocket não é seguro pra escrever a partir de outra thread.
            id_remetente = self._id_do_socket(socket) or ""
            threading.Thread(
                target=self._imprimir_remoto_em_thread,
                args=(conteudo, job_id, id_remetente),
                daemon=True,
            ).start()

        elif tipo == "imprimir_resultado":
            job_id = mensagem.get("job_id", "")
            job = self._jobs_impressao.get(job_id)
            if job is None or job["concluido"]:
                return
            job["concluido"] = True
            job["timer"].stop()
            job["timer"].deleteLater()
            del self._jobs_impressao[job_id]
            if mensagem.get("sucesso"):
                self.impressaoResultado.emit(True, mensagem.get("maquina") or "outra máquina")
            else:
                self.impressaoResultado.emit(False, mensagem.get("erro") or "Falha ao imprimir na máquina remota.")

    # ---------- Barramento de eventos (gossip) ----------

    def _propagar_evento(self, evento, socket_origem):
        """Ponte entre BarramentoEventos e os sockets reais: manda `evento`
        pra todo peer conectado, exceto `socket_origem` (None numa
        publicação local — nesse caso manda pra todo mundo)."""
        mensagem = {"tipo": "evento", **evento}
        for socket in self._peers.values():
            if socket is socket_origem:
                continue
            self._enviar(socket, mensagem)

    def _emitir_pedido_recebido(self, nome_arquivo, conteudo_b64):
        if not nome_arquivo or not conteudo_b64:
            return
        try:
            conteudo = base64.b64decode(conteudo_b64)
        except ValueError:
            return
        self.pedidoRecebido.emit(nome_arquivo, QByteArray(conteudo))

    def _ao_receber_evento_pedido_novo(self, payload):
        payload = payload or {}
        self._emitir_pedido_recebido(payload.get("arquivo", ""), payload.get("conteudo_b64", ""))

    def _ao_receber_evento_pedido_apagado(self, payload):
        nome = (payload or {}).get("arquivo", "")
        if nome:
            self.pedidoRemovidoRemoto.emit(nome)

    def publicarEvento(self, tipo_evento: str, payload: dict):
        """Anuncia `payload` (precisa ser serializável em JSON) pra malha
        inteira sob o tipo `tipo_evento`, pelo mesmo barramento de gossip
        usado internamente para pedido_novo/pedido_apagado — ver
        services/rede/eventos.py. Usado por quem tem uma mudança pra
        avisar às outras máquinas sem que esta classe precise saber o que
        ela significa (ver CardapioController, tipo "cardapio_alterado")."""
        self._eventos.publicar(tipo_evento, payload)

    def registrarEvento(self, tipo_evento: str, callback):
        """Registra `callback(payload)` pra rodar sempre que um evento
        `tipo_evento` chegar de outra máquina — ver
        services/rede/eventos.py:BarramentoEventos.registrar."""
        self._eventos.registrar(tipo_evento, callback)

    # ---------- Impressora local e eleição da máquina que imprime ----------

    @pyqtSlot()
    def verificarImpressoraLocal(self):
        """Força uma nova checagem da impressora local agora, em vez de
        esperar o próximo tique de _timer_impressora (30s) — usado pelo
        botão "Atualizar" de Rede.qml, pro caso comum de acabar de plugar a
        Bematech na USB e querer que ESTA máquina já seja reeleita a
        principal, sem esperar. O resultado (e a reeleição, se mudar
        alguma coisa) chega do mesmo jeito assíncrono de sempre — ver
        _ao_verificar_impressora_local/_recalcular_maquina_impressora — e
        Rede.qml já está escutando impressoraPrincipalMudou pra atualizar
        sozinha quando isso acontecer."""
        self._detectar_impressora_local()

    def _detectar_impressora_local(self):
        threading.Thread(target=self._detectar_impressora_em_thread, daemon=True).start()

    def _detectar_impressora_em_thread(self):
        try:
            impressora = self._printer_service.localizar_impressora()
        except Exception as erro:
            # Qualquer falha aqui (SO não suportado, CUPS/PowerShell com
            # saída inesperada etc.) vira "sem impressora" em vez de
            # propagar — isto roda fora da thread principal.
            print(f"[RedeService] Falha ao checar impressora local: {erro}")
            impressora = None

        # Só conta pra eleição de rede se for uma porta física/de rede de
        # verdade (usb/serial/rede) — "desconhecido" cobre impressoras
        # virtuais do Windows (Microsoft Print to PDF, Fax etc.) que
        # aparecem como "salvas"/padrão mas não são a térmica de verdade —
        # E se estiver de fato disponível agora (ver InfoImpressora.
        # disponivel/services/printer/windows.py e linux.py): uma
        # impressora usb/serial instalada uma vez continua com esse
        # tipo_porta pra sempre no SO, mesmo depois de desconectada de
        # verdade, então sem checar "disponivel" também, uma máquina sem
        # nenhuma impressora física conectada no momento podia ficar presa
        # como a eleita da malha (sticky, ver _recalcular_maquina_impressora)
        # e nunca devolver a vaga pra outra máquina que chegasse depois
        # com a impressora usb de verdade conectada.
        # PrinterService/Rede.qml continuam mostrando qualquer impressora
        # encontrada normalmente; esse filtro vale só pra decidir quem
        # recebe os pedidos de impressão da malha.
        tem_impressora_valida = (
            impressora is not None
            and impressora.tipo_porta != "desconhecido"
            and impressora.disponivel
        )
        if impressora is not None and impressora.tipo_porta == "desconhecido":
            print(f"[RedeService] Impressora local '{impressora.nome}' encontrada, mas com porta não identificada (tipo_porta='{impressora.tipo_porta}') — não conta pra eleição de rede.")
        elif impressora is not None and not impressora.disponivel:
            print(f"[RedeService] Impressora local '{impressora.nome}' está instalada (tipo_porta='{impressora.tipo_porta}'), mas não parece conectada/disponível agora — não conta pra eleição de rede.")

        info = None
        if tem_impressora_valida:
            info = {
                "nome": impressora.nome,
                "modelo": impressora.modelo,
                "fabricante": impressora.fabricante,
                "tipoPorta": impressora.tipo_porta,
                "porta": impressora.porta,
            }
        self._impressoraLocalVerificada.emit(tem_impressora_valida, info)

    def _ao_verificar_impressora_local(self, tem_impressora: bool, info):
        if tem_impressora == self._tem_impressora and info == self._info_impressora_local:
            return
        self._tem_impressora = tem_impressora
        self._info_impressora_local = info
        self._recalcular_maquina_impressora()
        mensagem = {"tipo": "status_impressora", "temImpressora": self._tem_impressora, "infoImpressora": info}
        for socket in self._peers.values():
            self._enviar(socket, mensagem)

    def _maquina_impressora_valida(self, id_maquina):
        """Se `id_maquina` ainda é uma candidata legítima agora (continua
        conectada — ou é esta máquina — e continua anunciando impressora)."""
        if id_maquina == self._id:
            return self._tem_impressora
        info = self._info_peers.get(id_maquina)
        return bool(info and info.get("temImpressora"))

    def _resolver_id_por_nome(self, nome_maquina):
        """Converte um nome de máquina (estável — ver _nome_maquina_fixada)
        no id_maquina correspondente agora (efêmero — um novo por
        execução), procurando entre esta máquina e os peers conectados.
        None se nenhuma máquina conhecida agora tem esse nome (offline, ou
        nome nunca visto nesta malha)."""
        if nome_maquina == self._nome_local:
            return self._id
        for id_peer, info in self._info_peers.items():
            if info.get("nome") == nome_maquina:
                return id_peer
        return None

    # Prioridade da eleição por tipo de porta — número menor vence. usb/
    # serial é a impressora fisicamente ligada nesta máquina; "rede" cobre
    # impressoras salvas/compartilhadas (ex: a mesma Bematech instalada
    # como impressora de rede/padrão em outra máquina, apontando de volta
    # pra quem tem ela na USB). "desconhecido" nem chega a virar candidata
    # (ver _detectar_impressora_em_thread), então não precisa de entrada
    # aqui — o .get() abaixo cai no default.
    _PRIORIDADE_TIPO_PORTA = {"usb": 0, "serial": 0, "rede": 1}

    def _prioridade_candidato(self, id_maquina):
        if id_maquina == self._id:
            info = self._info_impressora_local
        else:
            peer = self._info_peers.get(id_maquina)
            info = peer.get("infoImpressora") if peer else None
        tipo_porta = (info or {}).get("tipoPorta", "")
        return self._PRIORIDADE_TIPO_PORTA.get(tipo_porta, 1)

    def _recalcular_maquina_impressora(self):
        """Eleição "sticky com prioridade": entre máquinas do mesmo nível de
        prioridade, quem já está eleito continua sendo a prioridade mesmo
        que outra máquina do mesmo nível passe a anunciar impressora depois
        — evita uma impressora "salva" instável roubando a vaga toda hora.

        Mas usb/serial (impressora fisicamente conectada) sempre tem
        prioridade sobre rede: se a eleita atual só tem impressora de rede
        e uma candidata usb/serial aparece — inclusive a própria máquina
        que tinha a impressora antes, voltando pra malha depois de
        desconectar — a eleição troca na hora. Sem essa checagem de
        prioridade, a máquina com a impressora física de verdade nunca
        reassumia depois de reconectar: ela virava só mais uma candidata do
        mesmo desempate por id, perdendo pro sticky de quem já estava
        eleito.

        Se houver uma máquina fixada manualmente (ver
        fixarImpressoraPrincipal/_nome_maquina_fixada) e ela ainda for uma
        candidata válida agora, ela vence direto — ignora prioridade e
        sticky. Se a fixação existir mas apontar pra uma máquina offline ou
        sem impressora no momento, cai de volta pro algoritmo automático
        abaixo (a fixação continua guardada e volta a valer sozinha assim
        que essa máquina reconectar com impressora)."""
        candidatos = []
        if self._tem_impressora:
            candidatos.append(self._id)
        candidatos.extend(id_peer for id_peer, info in self._info_peers.items() if info.get("temImpressora"))

        if not candidatos:
            if self._id_maquina_impressora is not None:
                self._id_maquina_impressora = None
                self.impressoraPrincipalMudou.emit()
            return

        melhor_candidato = None
        if self._nome_maquina_fixada is not None:
            id_fixado = self._resolver_id_por_nome(self._nome_maquina_fixada)
            if id_fixado is not None and self._maquina_impressora_valida(id_fixado):
                melhor_candidato = id_fixado

        if melhor_candidato is None:
            # Empate (mesma prioridade) é resolvido de forma determinística
            # pelo id — toda máquina da malha vê o mesmo conjunto de
            # candidatos e infoImpressora (gossiped por "identificar"/
            # "status_impressora"), então chega à mesma conclusão.
            melhor_candidato = min(candidatos, key=lambda id_maquina: (self._prioridade_candidato(id_maquina), id_maquina))

            if (
                self._id_maquina_impressora is not None
                and self._maquina_impressora_valida(self._id_maquina_impressora)
                and self._prioridade_candidato(self._id_maquina_impressora) <= self._prioridade_candidato(melhor_candidato)
            ):
                return

        if melhor_candidato != self._id_maquina_impressora:
            self._id_maquina_impressora = melhor_candidato
            self.impressoraPrincipalMudou.emit()

    # ---------- Seleção manual da impressora principal (Rede.qml) ----------

    @pyqtProperty(str, notify=impressoraPrincipalMudou)
    def nomeMaquinaFixada(self):
        """Nome da máquina fixada manualmente (ver fixarImpressoraPrincipal),
        ou "" quando a eleição está no modo automático — usado por
        Rede.qml pra pré-selecionar o item certo no combo."""
        return self._nome_maquina_fixada or ""

    @pyqtSlot(result="QVariantList")
    def candidatosImpressora(self):
        """Máquinas que anunciam impressora agora (esta + peers) — as
        opções disponíveis pra fixar manualmente em Rede.qml. Mesmo filtro
        de candidatos usado por _recalcular_maquina_impressora."""
        candidatos = []
        if self._tem_impressora and self._info_impressora_local:
            candidatos.append({
                "nomeMaquina": self._nome_local,
                "nomeImpressora": self._info_impressora_local.get("nome", ""),
                "local": True,
            })
        for info in self._info_peers.values():
            if info.get("temImpressora") and info.get("infoImpressora"):
                candidatos.append({
                    "nomeMaquina": info.get("nome") or "Máquina desconhecida",
                    "nomeImpressora": info["infoImpressora"].get("nome", ""),
                    "local": False,
                })
        return candidatos

    @pyqtSlot(str)
    def fixarImpressoraPrincipal(self, nomeMaquina: str):
        """Fixa manualmente `nomeMaquina` como a máquina que imprime pra
        malha inteira (string vazia = volta pra eleição automática por
        prioridade de porta). Persiste localmente, propaga a escolha pra
        todas as outras instâncias por gossip (mesmo barramento genérico
        usado por publicarEvento) e recalcula a eleição na hora — publicar()
        não roda os manipuladores locais (ver BarramentoEventos.publicar),
        então quem chamou precisa aplicar o efeito por conta própria."""
        self._nome_maquina_fixada = nomeMaquina or None
        impressoraFixada.salvar_nome_fixado(self._nome_maquina_fixada)
        self._eventos.publicar("impressora_fixada", {"nomeMaquina": self._nome_maquina_fixada})
        # Emite mesmo que a máquina eleita não mude (ex: fixar a mesma que
        # já estava eleita automaticamente) — Rede.qml usa esse sinal pra
        # atualizar nomeMaquinaFixada/o selo "selecionada manualmente", que
        # dependem de _nome_maquina_fixada e não só de quem está eleito.
        self._recalcular_maquina_impressora()
        self.impressoraPrincipalMudou.emit()

    def _ao_receber_identificar_fixacao(self, nome_maquina_fixada_do_peer):
        """Chamado ao processar o handshake "identificar" de um peer que
        acabou de conectar — se esta máquina ainda não conhece nenhuma
        fixação (nunca escolheu nada e nunca recebeu o evento de gossip
        "impressora_fixada" até agora), mas o peer que chegou já conhece
        uma, adota ela. Cobre o caso de uma máquina conectar/reconectar
        DEPOIS que a escolha já foi feita em outro lugar — o evento de
        gossip original (BarramentoEventos.publicar) só alcança quem já
        estava conectado no momento; sem isso aqui, quem chega depois
        nunca ficava sabendo, nem reiniciando (não tinha nada salvo no
        disco dela pra recarregar).

        Não sobrescreve uma fixação que ESTA máquina já tenha (mesmo que
        diferente da do peer) — presume que uma escolha já feita aqui foi
        deliberada e não deve ser silenciosamente trocada só por causa de
        outro peer reconectando."""
        if self._nome_maquina_fixada is not None or not nome_maquina_fixada_do_peer:
            return False
        self._nome_maquina_fixada = nome_maquina_fixada_do_peer
        impressoraFixada.salvar_nome_fixado(nome_maquina_fixada_do_peer)
        return True

    def _ao_receber_evento_impressora_fixada(self, payload):
        """Reação a um "impressora_fixada" publicado por OUTRA máquina —
        replica o mesmo efeito de fixarImpressoraPrincipal nesta instância
        (persistir localmente também, pra esta máquina já lembrar a última
        escolha conhecida se reabrir sozinha antes de qualquer peer)."""
        nome_maquina = (payload or {}).get("nomeMaquina") or None
        self._nome_maquina_fixada = nome_maquina
        impressoraFixada.salvar_nome_fixado(nome_maquina)
        self._recalcular_maquina_impressora()
        self.impressoraPrincipalMudou.emit()

    @pyqtSlot(result="QVariantMap")
    def impressoraPrincipal(self):
        """Info da impressora que a malha está usando pra imprimir agora (a
        máquina eleita por _recalcular_maquina_impressora) — pra exibir em
        Rede.qml. Devolve {} se nenhuma máquina conhecida tem impressora."""
        if self._id_maquina_impressora is None:
            return {}

        if self._id_maquina_impressora == self._id:
            nome_maquina = self._nome_local
            info = self._info_impressora_local
            local = True
        else:
            peer = self._info_peers.get(self._id_maquina_impressora)
            if not peer:
                return {}
            nome_maquina = peer.get("nome") or "Máquina desconhecida"
            info = peer.get("infoImpressora")
            local = False

        if not info:
            return {}

        return {
            "maquina": nome_maquina,
            "local": local,
            "fixadoManualmente": self._nome_maquina_fixada is not None,
            "nome": info.get("nome", ""),
            "modelo": info.get("modelo", ""),
            "fabricante": info.get("fabricante", ""),
            "tipoPorta": info.get("tipoPorta", ""),
            "porta": info.get("porta", ""),
        }

    def _tentar_imprimir_localmente(self, conteudo_bytes: bytes):
        try:
            self._printer_service.imprimir(conteudo_bytes)
            return True, ""
        except RuntimeError as erro:
            print(f"[RedeService] Não foi possível imprimir nesta máquina: {erro}")
            return False, str(erro)
        except Exception as erro:
            # Além de RuntimeError (falha "esperada" documentada em
            # PrinterService.imprimir): qualquer outra exceção também vira
            # falha reportada em vez de propagar — isto roda dentro de uma
            # thread de impressão (ver solicitar_impressao/
            # _imprimir_remoto_em_thread); deixar escapar mataria a thread
            # silenciosamente sem que ninguém soubesse que o job falhou.
            print(f"[RedeService] Falha inesperada ao imprimir nesta máquina: {erro}")
            return False, str(erro)

    def _imprimir_localmente_e_notificar(self, conteudo_bytes: bytes):
        """Roda em thread própria (ver solicitar_impressao) — a impressão
        (spooler/CUPS) pode levar vários segundos e não pode bloquear quem
        pediu (ex: SalaoController.fecharMesa, BalcaoController.enviarPedido),
        senão popups/telas que dependem do controle voltar rápido ficariam
        "presos" até o job terminar. impressaoResultado é seguro de emitir
        de qualquer thread — o Qt entrega o sinal na thread principal."""
        sucesso, erro = self._tentar_imprimir_localmente(conteudo_bytes)
        self.impressaoResultado.emit(sucesso, self._nome_local if sucesso else (erro or "Falha ao imprimir nesta máquina."))

    def _imprimir_remoto_em_thread(self, conteudo_bytes: bytes, job_id: str, id_remetente: str):
        """Roda em thread própria (ver o handler de "imprimir" em
        _processar_mensagem) — mesmo motivo de _imprimir_localmente_e_notificar,
        mas aqui a resposta precisa voltar por um QTcpSocket específico, o
        que só é seguro a partir da thread que o criou (thread principal);
        por isso o resultado é repassado por sinal em vez de chamar
        _enviar() direto daqui."""
        sucesso, erro = self._tentar_imprimir_localmente(conteudo_bytes)
        self._imprimirRemotoConcluido.emit(id_remetente, job_id, sucesso, erro)

    def _ao_concluir_imprimir_remoto(self, id_remetente: str, job_id: str, sucesso: bool, erro: str):
        socket_remetente = self._peers.get(id_remetente) if id_remetente else None
        if socket_remetente is None:
            # Quem pediu já desconectou enquanto a impressão rodava — não
            # há mais pra onde mandar a resposta. Quem pediu trata isso pelo
            # próprio timeout do job (ver _finalizar_job_impressao).
            return
        self._enviar(socket_remetente, {
            "tipo": "imprimir_resultado",
            "job_id": job_id,
            "sucesso": sucesso,
            "erro": erro,
            "maquina": self._nome_local,
        })

    # ---------- Chamadas dos controllers (saída) ----------

    def transmitir_pedido(self, nome_arquivo: str, conteudo_bytes: bytes):
        self._eventos.publicar("pedido_novo", {
            "arquivo": nome_arquivo,
            "conteudo_b64": base64.b64encode(conteudo_bytes).decode("ascii"),
        })

    def transmitir_exclusao(self, nome_arquivo: str):
        self._eventos.publicar("pedido_apagado", {"arquivo": nome_arquivo})

    def solicitar_impressao(self, conteudo_bytes: bytes):
        """Pede a impressão da comanda na máquina eleita da malha (ver
        _recalcular_maquina_impressora) — nunca em broadcast pra todo mundo.
        O resultado (sucesso ou falha, de qualquer origem) chega pelo sinal
        impressaoResultado, de forma assíncrona."""
        if self._id_maquina_impressora == self._id:
            # Em thread própria: a impressão em si (spooler/CUPS) pode levar
            # vários segundos, e quem chamou solicitar_impressao (ex:
            # BalcaoController.enviarPedido, SalaoController.fecharMesa)
            # precisa voltar rápido — é chamado direto de um slot QML, e um
            # popup que acabou de fechar (ver PopupComandaTeste.qml) só
            # renderiza como fechado depois que a thread principal volta
            # pro loop de eventos. O resultado chega do mesmo jeito
            # assíncrono de sempre, pelo sinal impressaoResultado.
            threading.Thread(
                target=self._imprimir_localmente_e_notificar,
                args=(conteudo_bytes,),
                daemon=True,
            ).start()
            return

        socket_destino = self._peers.get(self._id_maquina_impressora) if self._id_maquina_impressora else None
        if socket_destino is None:
            self.impressaoResultado.emit(False, "Nenhuma máquina da rede está com impressora conectada.")
            return

        job_id = uuid.uuid4().hex
        self._enviar(socket_destino, {
            "tipo": "imprimir",
            "job_id": job_id,
            "conteudo_b64": base64.b64encode(conteudo_bytes).decode("ascii"),
        })

        timer = QTimer(self)
        timer.setSingleShot(True)
        timer.timeout.connect(lambda: self._finalizar_job_impressao(job_id))
        self._jobs_impressao[job_id] = {"timer": timer, "concluido": False}
        timer.start(_TIMEOUT_IMPRESSAO_MS)

    def _finalizar_job_impressao(self, job_id):
        job = self._jobs_impressao.pop(job_id, None)
        if job is None or job["concluido"]:
            return
        job["timer"].deleteLater()
        self.impressaoResultado.emit(False, "A máquina da impressora não respondeu a tempo.")

    # ---------- Auxiliares de arquivo (usados só pra responder o catch-up) ----------

    def _pasta_pedidos(self):
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        return os.path.join(base_dir, "pedidos")

    def _listar_arquivos_locais(self):
        pasta = self._pasta_pedidos()
        if not os.path.isdir(pasta):
            return []
        return [nome for nome in os.listdir(pasta) if nome.endswith(".txt")]

    def _ler_arquivo_local(self, nome_arquivo: str):
        nome_arquivo = os.path.basename(nome_arquivo)
        caminho = os.path.join(self._pasta_pedidos(), nome_arquivo)
        try:
            with open(caminho, "rb") as arquivo:
                return arquivo.read()
        except OSError:
            return None


# Singleton de módulo — mesmo padrão usado pelos demais services do projeto.
rede = RedeService()
