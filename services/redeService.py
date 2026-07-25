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
    # Emitido sempre que a máquina eleita pra imprimir (ou os dados da
    # impressora dela) pode ter mudado — Rede.qml usa pra reconsultar
    # impressoraPrincipal() e atualizar o painel sozinho.
    impressoraPrincipalMudou = pyqtSignal()
    # Uso interno: repassa o resultado da checagem da impressora local (rodada
    # numa thread, porque PrinterService.localizar_impressora() executa
    # lpstat/PowerShell) de volta pra thread principal — mesmo padrão de
    # BalcaoController.infoImpressoraPronta.
    _impressoraLocalVerificada = pyqtSignal(bool, object)

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
        return {
            "tipo": "identificar",
            "id": self._id,
            "nome": self._nome_local,
            "temImpressora": self._tem_impressora,
            "infoImpressora": self._info_impressora_local,
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

        # Só conta pra eleição de rede se for uma porta física/de rede de
        # verdade (usb/serial/rede) — "desconhecido" cobre impressoras
        # virtuais do Windows (Microsoft Print to PDF, Fax etc.) que
        # aparecem como "salvas"/padrão mas não são a térmica de verdade.
        # PrinterService/Rede.qml continuam mostrando qualquer impressora
        # encontrada normalmente; esse filtro vale só pra decidir quem
        # recebe os pedidos de impressão da malha.
        tem_impressora_valida = impressora is not None and impressora.tipo_porta != "desconhecido"
        if impressora is not None and not tem_impressora_valida:
            print(f"[RedeService] Impressora local '{impressora.nome}' encontrada, mas com porta não identificada (tipo_porta='{impressora.tipo_porta}') — não conta pra eleição de rede.")

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

    def _recalcular_maquina_impressora(self):
        """Eleição "sticky": quem já está eleito continua sendo a
        prioridade mesmo que outra máquina passe a anunciar impressora
        depois (inclusive esta própria máquina) — só reelege quando a
        atual eleita perde a impressora ou desconecta da malha. Sem isso,
        uma impressora "salva" (padrão do Windows, por exemplo, mas não
        necessariamente a que está fisicamente conectada e em uso) que
        aparece depois roubaria a prioridade de quem já estava servindo —
        exatamente o cenário que esse "sticky" evita: a primeira máquina a
        entrar na malha já com a impressora conectada continua sendo pra
        quem tudo é mandado imprimir, mesmo que outras máquinas cheguem
        depois também "com impressora"."""
        if self._id_maquina_impressora is not None and self._maquina_impressora_valida(self._id_maquina_impressora):
            return

        candidatos = []
        if self._tem_impressora:
            candidatos.append(self._id)
        candidatos.extend(id_peer for id_peer, info in self._info_peers.items() if info.get("temImpressora"))
        # Empate (ex: duas máquinas anunciam impressora praticamente ao
        # mesmo tempo, antes de qualquer uma virar a eleita) é resolvido de
        # forma determinística pelo id — toda máquina da malha vê o mesmo
        # conjunto de candidatos e chega à mesma conclusão.
        self._id_maquina_impressora = min(candidatos) if candidatos else None
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
