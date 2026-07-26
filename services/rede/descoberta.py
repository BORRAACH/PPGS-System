"""Acha as outras instâncias deste app rodando na rede local.

Separado de redeService.py porque são dois problemas independentes: aqui
só entra "quem está na rede e em que endereço", enquanto a malha TCP, o
protocolo de mensagens e a eleição da máquina que imprime ficam do outro
lado. Quem usa este módulo só precisa de `criar_descoberta()`, do sinal
`peerDescoberto` e de `iniciar()`/`parar()`.

A descoberta padrão é por mDNS/DNS-SD, via zeroconf — o mesmo mecanismo
que faz impressoras e Chromecasts aparecerem sozinhos na rede. Ele
substitui o broadcast UDP caseiro que existia antes, que tinha três
problemas: precisava de uma porta fixa (45551) livre em todas as
máquinas, era repetido a cada 5s mesmo sem nada mudar, e broadcast é
descartado por padrão em boa parte dos roteadores/APs de Wi-Fi, o que
fazia máquinas no mesmo escritório simplesmente não se enxergarem.

O broadcast continua aqui como plano B, usado só quando o zeroconf não
está instalado — sem ele, uma falha na instalação da dependência mataria
a rede local inteira em vez de degradar.
"""

import json
import socket
import threading

from PyQt6.QtCore import QCoreApplication, QObject, QTimer, pyqtSignal
from PyQt6.QtNetwork import QHostAddress, QUdpSocket

try:
    from zeroconf import ServiceBrowser, ServiceInfo, ServiceStateChange, Zeroconf

    _ZEROCONF_DISPONIVEL = True
except ImportError:
    _ZEROCONF_DISPONIVEL = False

# Tipo de serviço DNS-SD deste app. É o que separa nossas instâncias do
# resto do que se anuncia na rede (impressoras, TVs, outros programas) —
# só respondemos a este tipo, então nada mais aparece como peer.
_TIPO_SERVICO = "_pizzaria-rede._tcp.local."

# Assinatura embutida em todo anúncio: no zeroconf é redundante com o tipo
# de serviço acima e serve só de conferência, mas no broadcast UDP é a
# única coisa que distingue nossos datagramas do resto do tráfego da rede.
_ASSINATURA = "PIZZARIA_REDE_V1"

_PORTA_DESCOBERTA = 45551
_INTERVALO_BROADCAST_MS = 5000
# Tempo máximo esperando o zeroconf resolver endereço/porta de um serviço
# recém-anunciado. Roda numa thread à parte, então não segura nada.
_TIMEOUT_RESOLVER_MS = 3000


def _ip_local() -> str:
    """Endereço IP desta máquina na interface que ela usa pra falar com a
    rede local. O connect() num socket UDP não envia pacote nenhum nem
    exige que o destino exista — só faz o sistema escolher a interface de
    saída, que é justamente a que queremos anunciar. Bem mais confiável
    que resolver o hostname, que em muita máquina Linux devolve
    127.0.0.1."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        sock.close()


class Descoberta(QObject):
    """Interface comum das estratégias de descoberta.

    Emite `peerDescoberto` para cada instância encontrada, incluindo a
    própria máquina e repetindo peers já conhecidos — filtrar isso é
    responsabilidade de quem recebe (RedeService), que é quem sabe com
    quem já está conectado."""

    # (id da instância remota, endereço IP, porta TCP da malha)
    peerDescoberto = pyqtSignal(str, str, int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._id_local = ""
        self._porta_tcp = 0
        self._iniciado = False

    def iniciar(self, id_local: str, porta_tcp: int) -> None:
        """Começa a anunciar esta instância e a procurar as outras.
        `porta_tcp` é a porta onde a malha aceita conexões — é o que os
        peers precisam saber pra discar de volta."""
        if self._iniciado:
            return

        self._id_local = id_local
        self._porta_tcp = porta_tcp
        self._iniciado = True

        # Anúncio na rede precisa ser retirado ao sair, senão as outras
        # máquinas continuam tentando discar pra uma instância morta até o
        # registro expirar sozinho. Ligado aqui, e não no chamador, pra que
        # esquecer de chamar parar() não vire um bug de rede.
        app = QCoreApplication.instance()
        if app is not None:
            app.aboutToQuit.connect(self.parar)

        self._iniciar()

    def parar(self) -> None:
        if not self._iniciado:
            return
        self._iniciado = False
        self._parar()

    def _iniciar(self) -> None:
        raise NotImplementedError

    def _parar(self) -> None:
        pass


class DescobertaZeroconf(Descoberta):
    """Descoberta por mDNS/DNS-SD: anuncia esta instância como um serviço
    `_pizzaria-rede._tcp` e observa os anúncios das outras."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._zeroconf = None
        self._info_servico = None
        self._browser = None

    def _iniciar(self) -> None:
        try:
            self._zeroconf = Zeroconf()
        except OSError as erro:
            # Porta 5353 ocupada por outro daemon mDNS em modo exclusivo,
            # rede indisponível no boot etc.
            print(f"[descoberta] Não foi possível iniciar o zeroconf ({erro}) — a rede local ficará sem descoberta.")
            return

        # O nome do serviço e o do host precisam ser únicos POR INSTÂNCIA, não
        # por máquina: os scripts de teste em docker/ (e um eventual segundo
        # app aberto) rodam duas instâncias no mesmo computador, e o padrão do
        # zeroconf — o hostname da máquina — faria uma sobrescrever o anúncio
        # da outra. O id da instância já é um uuid, então serve para os dois.
        self._info_servico = ServiceInfo(
            _TIPO_SERVICO,
            f"{self._id_local}.{_TIPO_SERVICO}",
            addresses=[socket.inet_aton(_ip_local())],
            port=self._porta_tcp,
            properties={"assinatura": _ASSINATURA, "id": self._id_local},
            server=f"{self._id_local}.local.",
        )

        try:
            self._zeroconf.register_service(self._info_servico)
        except OSError as erro:
            print(f"[descoberta] Falha ao anunciar esta máquina via zeroconf: {erro}")

        self._browser = ServiceBrowser(self._zeroconf, _TIPO_SERVICO, handlers=[self._ao_mudar_servico])
        print(f"[descoberta] Anunciando '{_TIPO_SERVICO}' na porta {self._porta_tcp} e procurando outras máquinas.")

    def _ao_mudar_servico(self, zeroconf, service_type, name, state_change) -> None:
        if state_change not in (ServiceStateChange.Added, ServiceStateChange.Updated):
            return

        # get_service_info() faz I/O e espera resposta: chamado direto daqui
        # ele bloquearia a própria thread do zeroconf que precisa processar
        # essa resposta. Resolver numa thread à parte é o padrão recomendado
        # pela biblioteca.
        threading.Thread(
            target=self._resolver_servico,
            args=(zeroconf, service_type, name),
            daemon=True,
        ).start()

    def _resolver_servico(self, zeroconf, service_type, name) -> None:
        try:
            info = zeroconf.get_service_info(service_type, name, timeout=_TIMEOUT_RESOLVER_MS)
        except OSError:
            return
        if info is None:
            return

        propriedades = info.properties or {}
        if propriedades.get(b"assinatura") != _ASSINATURA.encode("utf-8"):
            return

        id_remoto = (propriedades.get(b"id") or b"").decode("utf-8", "ignore")
        enderecos = info.parsed_addresses()
        if not id_remoto or not enderecos or not info.port:
            return

        # Emitido de dentro desta thread; como o objeto vive na thread
        # principal, o Qt entrega o sinal lá (conexão em fila), então quem
        # recebe pode mexer nos sockets sem se preocupar com thread.
        self.peerDescoberto.emit(id_remoto, enderecos[0], info.port)

    def _parar(self) -> None:
        if self._zeroconf is None:
            return
        try:
            if self._info_servico is not None:
                self._zeroconf.unregister_service(self._info_servico)
            self._zeroconf.close()
        except OSError:
            pass
        self._zeroconf = None
        self._browser = None


class DescobertaBroadcast(Descoberta):
    """Plano B de quando o zeroconf não está instalado: anuncia a instância
    repetindo um datagrama UDP em broadcast a cada poucos segundos.

    Funciona sem dependência nenhuma, mas depende de a rede repassar
    broadcast — o que muito roteador/AP de Wi-Fi não faz."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._udp = None
        self._timer = None

    def _iniciar(self) -> None:
        self._udp = QUdpSocket(self)
        self._udp.bind(
            _PORTA_DESCOBERTA,
            QUdpSocket.BindFlag.ShareAddress | QUdpSocket.BindFlag.ReuseAddressHint,
        )
        self._udp.readyRead.connect(self._ao_receber_datagrama)

        self._timer = QTimer(self)
        self._timer.timeout.connect(self._anunciar)
        self._timer.start(_INTERVALO_BROADCAST_MS)
        self._anunciar()

    def _anunciar(self) -> None:
        mensagem = json.dumps({
            "assinatura": _ASSINATURA,
            "id": self._id_local,
            "porta_tcp": self._porta_tcp,
        }).encode("utf-8")
        self._udp.writeDatagram(
            mensagem,
            QHostAddress(QHostAddress.SpecialAddress.Broadcast),
            _PORTA_DESCOBERTA,
        )

    def _ao_receber_datagrama(self) -> None:
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
            if not id_remoto or not porta_tcp:
                continue

            self.peerDescoberto.emit(id_remoto, endereco.toString(), int(porta_tcp))

    def _parar(self) -> None:
        if self._timer is not None:
            self._timer.stop()
        if self._udp is not None:
            self._udp.close()


def criar_descoberta(parent=None) -> Descoberta:
    """Melhor estratégia de descoberta disponível nesta máquina."""
    if _ZEROCONF_DISPONIVEL:
        return DescobertaZeroconf(parent)

    print("[descoberta] zeroconf não está instalado — usando broadcast UDP, que muita rede Wi-Fi bloqueia.")
    return DescobertaBroadcast(parent)
