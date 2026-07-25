import base64
import json
import os
import platform
import threading
import time
import uuid

from PyQt6.QtCore import QObject, QByteArray, QTimer, pyqtProperty, pyqtSignal, pyqtSlot
from PyQt6.QtNetwork import QHostAddress, QTcpServer, QTcpSocket, QUdpSocket

from services.printerService import PrinterService

# Assinatura embutida em todo datagrama de descoberta: só instâncias deste
# app respondem a ela, então o resto do tráfego broadcast da rede local
# (outros dispositivos, outros programas) é ignorado.
_ASSINATURA = "PIZZARIA_REDE_V1"
_PORTA_DESCOBERTA = 45551
_INTERVALO_BROADCAST_MS = 5000
_INTERVALO_CHECAGEM_IMPRESSORA_MS = 30000
_TIMEOUT_IMPRESSAO_MS = 10000


class RedeService(QObject):
    """Compartilha pedidos entre instâncias deste app na mesma rede local, e
    elege/anuncia qual máquina da malha imprime as comandas.

    Topologia em malha completa: como há no máximo poucas máquinas (4), cada
    instância se conecta diretamente a todas as outras que descobrir via
    broadcast UDP, então uma mensagem nunca precisa ser retransmitida — quem
    cria/apaga um pedido manda direto pra cada peer conectado.

    Além de bytes entrando e saindo (quem grava/apaga os .txt em disco são os
    sinais conectados pelos controllers, ver main.py), esta classe também
    decide, de forma determinística e independente em cada instância, qual
    máquina da malha está com a impressora física conectada — ver
    _recalcular_maquina_impressora — e roteia os pedidos de impressão
    (solicitar_impressao) só pra ela, em vez de cada máquina imprimir na sua
    própria impressora local."""

    pedidoRecebido = pyqtSignal(str, QByteArray)
    pedidoRemovidoRemoto = pyqtSignal(str)
    peersMudaram = pyqtSignal(int)
    # Emitido quando o resultado de um pedido de impressão é conhecido
    # (sucesso, nome da máquina que imprimiu ou motivo da falha).
    impressaoResultado = pyqtSignal(bool, str)
    # Uso interno: repassa o resultado da checagem da impressora local (rodada
    # numa thread, porque PrinterService.localizar_impressora() executa
    # lpstat/PowerShell) de volta pra thread principal — mesmo padrão de
    # BalcaoController.infoImpressoraPronta.
    _impressoraLocalVerificada = pyqtSignal(bool)

    def __init__(self):
        super().__init__()
        self._id = uuid.uuid4().hex
        self._nome_local = platform.node() or "Máquina desconhecida"
        self._peers = {}  # id da instância -> QTcpSocket
        self._info_peers = {}  # id da instância -> {"nome", "endereco", "conectadoEm", "temImpressora"}
        self._buffers = {}  # QTcpSocket -> bytearray (linhas JSON incompletas)
        self._iniciado = False

        self._printer_service = PrinterService()
        self._tem_impressora = False
        # Id da máquina (pode ser self._id) escolhida pra receber comandas de
        # impressão; None = nenhuma máquina conhecida tem impressora agora.
        self._id_maquina_impressora = None
        self._jobs_impressao = {}  # job_id -> {"timer": QTimer, "concluido": bool}

        self._udp = QUdpSocket(self)
        self._tcp_server = QTcpServer(self)
        self._timer_broadcast = QTimer(self)
        self._timer_impressora = QTimer(self)

        self._impressoraLocalVerificada.connect(self._ao_verificar_impressora_local)

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

        self._udp.bind(
            _PORTA_DESCOBERTA,
            QUdpSocket.BindFlag.ShareAddress | QUdpSocket.BindFlag.ReuseAddressHint,
        )
        self._udp.readyRead.connect(self._ao_receber_datagrama)

        self._tcp_server.newConnection.connect(self._ao_conectar_entrada)
        if not self._tcp_server.listen(QHostAddress.SpecialAddress.Any, 0):
            print("RedeService: falha ao abrir porta TCP para a malha local")
            return

        self._timer_broadcast.timeout.connect(self._anunciar)
        self._timer_broadcast.start(_INTERVALO_BROADCAST_MS)
        self._anunciar()

        # Detecta a impressora local uma vez já ao iniciar, e depois
        # periodicamente — cobre o caso de a impressora ser plugada com o
        # app já aberto.
        self._detectar_impressora_local()
        self._timer_impressora.timeout.connect(self._detectar_impressora_local)
        self._timer_impressora.start(_INTERVALO_CHECAGEM_IMPRESSORA_MS)

    # ---------- Descoberta ----------

    def _anunciar(self):
        mensagem = json.dumps({
            "assinatura": _ASSINATURA,
            "id": self._id,
            "porta_tcp": self._tcp_server.serverPort(),
        }).encode("utf-8")
        self._udp.writeDatagram(mensagem, QHostAddress(QHostAddress.SpecialAddress.Broadcast), _PORTA_DESCOBERTA)

    def _ao_receber_datagrama(self):
        while self._udp.hasPendingDatagrams():
            datagrama, endereco, _porta = self._udp.readDatagram(self._udp.pendingDatagramSize())
            try:
                dados = json.loads(bytes(datagrama).decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                continue

            if dados.get("assinatura") != _ASSINATURA:
                continue

            id_remoto = dados.get("id")
            porta_tcp = dados.get("porta_tcp")
            if not id_remoto or not porta_tcp or id_remoto == self._id:
                continue
            if id_remoto in self._peers:
                continue

            # Só quem tem o id "menor" disca — evita os dois lados abrirem
            # conexão um pro outro ao mesmo tempo.
            if self._id < id_remoto:
                self._conectar_a(endereco, porta_tcp)

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
        return {"tipo": "identificar", "id": self._id, "nome": self._nome_local, "temImpressora": self._tem_impressora}

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
            }
            self.peersMudaram.emit(len(self._peers))
            self._recalcular_maquina_impressora()
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
            nome = mensagem.get("arquivo", "")
            conteudo_b64 = mensagem.get("conteudo_b64", "")
            if not nome or not conteudo_b64:
                return
            try:
                conteudo = base64.b64decode(conteudo_b64)
            except ValueError:
                return
            self.pedidoRecebido.emit(nome, QByteArray(conteudo))

        elif tipo == "apagar":
            nome = mensagem.get("arquivo", "")
            if nome:
                self.pedidoRemovidoRemoto.emit(nome)

        elif tipo == "status_impressora":
            id_remoto = self._id_do_socket(socket)
            if id_remoto is not None and id_remoto in self._info_peers:
                self._info_peers[id_remoto]["temImpressora"] = bool(mensagem.get("temImpressora"))
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
            sucesso, erro = self._tentar_imprimir_localmente(conteudo)
            self._enviar(socket, {
                "tipo": "imprimir_resultado",
                "job_id": job_id,
                "sucesso": sucesso,
                "erro": erro,
                "maquina": self._nome_local,
            })

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

    # ---------- Impressora local e eleição da máquina que imprime ----------

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
        self._impressoraLocalVerificada.emit(impressora is not None)

    def _ao_verificar_impressora_local(self, tem_impressora: bool):
        if tem_impressora == self._tem_impressora:
            return
        self._tem_impressora = tem_impressora
        self._recalcular_maquina_impressora()
        mensagem = {"tipo": "status_impressora", "temImpressora": self._tem_impressora}
        for socket in self._peers.values():
            self._enviar(socket, mensagem)

    def _recalcular_maquina_impressora(self):
        """Prioriza esta máquina se ela tiver impressora; senão, entre os
        peers que anunciaram ter, escolhe sempre o de menor id — assim toda
        máquina da malha calcula, de forma independente, a mesma resposta
        pra "quem imprime agora", sem precisar de coordenador."""
        if self._tem_impressora:
            self._id_maquina_impressora = self._id
            return
        candidatos = [id_peer for id_peer, info in self._info_peers.items() if info.get("temImpressora")]
        self._id_maquina_impressora = min(candidatos) if candidatos else None

    def _tentar_imprimir_localmente(self, conteudo_bytes: bytes):
        try:
            self._printer_service.imprimir(conteudo_bytes)
            return True, ""
        except RuntimeError as erro:
            print(f"[RedeService] Não foi possível imprimir nesta máquina: {erro}")
            return False, str(erro)

    # ---------- Chamadas dos controllers (saída) ----------

    def transmitir_pedido(self, nome_arquivo: str, conteudo_bytes: bytes):
        mensagem = {
            "tipo": "pedido",
            "arquivo": nome_arquivo,
            "conteudo_b64": base64.b64encode(conteudo_bytes).decode("ascii"),
        }
        for socket in self._peers.values():
            self._enviar(socket, mensagem)

    def transmitir_exclusao(self, nome_arquivo: str):
        mensagem = {"tipo": "apagar", "arquivo": nome_arquivo}
        for socket in self._peers.values():
            self._enviar(socket, mensagem)

    def solicitar_impressao(self, conteudo_bytes: bytes):
        """Pede a impressão da comanda na máquina eleita da malha (ver
        _recalcular_maquina_impressora) — nunca em broadcast pra todo mundo.
        O resultado (sucesso ou falha, de qualquer origem) chega pelo sinal
        impressaoResultado, de forma assíncrona."""
        if self._id_maquina_impressora == self._id:
            sucesso, erro = self._tentar_imprimir_localmente(conteudo_bytes)
            self.impressaoResultado.emit(sucesso, self._nome_local if sucesso else (erro or "Falha ao imprimir nesta máquina."))
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
