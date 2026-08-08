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
from PyQt6.QtNetwork import QAbstractSocket, QHostAddress, QNetworkInterface, QUdpSocket

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


def _ip_por_rota() -> str:
    """Endereço IP desta máquina na interface que o sistema usaria pra sair
    da rede. O connect() num socket UDP não envia pacote nenhum nem exige
    que o destino exista — só faz o sistema escolher a interface de saída.
    Bem mais confiável que resolver o hostname, que em muita máquina Linux
    devolve 127.0.0.1.

    Devolve "" quando não há rota nenhuma. Isso NÃO quer dizer "sem
    internet": o connect() só precisa de rota, não de alcance, então um
    roteador configurado mas sem link com a operadora continua devolvendo o
    IP certo. O caso em que falha é o de não existir rota default alguma —
    switch sem roteador, IP fixo sem gateway, DHCP sem a opção router —
    que é justamente como se monta uma rede só pra ligar as máquinas entre
    si. Quem chama precisa cair pra _ips_das_interfaces()."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]
    except OSError:
        return ""
    finally:
        sock.close()


def _ips_das_interfaces() -> list:
    """Todo IPv4 não-loopback das interfaces ativas, direto do sistema —
    não depende de rota nenhuma.

    Usa QNetworkInterface (já vem no QtNetwork, que a malha inteira usa) em
    vez de resolver o hostname, que costuma devolver 127.0.0.1/127.0.1.1.

    O filtro por IsRunning (e não só IsUp) descarta interface configurada
    mas sem cabo/link — inclusive as pontes virtuais que o Docker/VirtualBox
    deixam pra trás, cujo IP não leva a lugar nenhum e só faria os peers
    tentarem discar pro endereço errado."""
    enderecos = []
    for interface in QNetworkInterface.allInterfaces():
        flags = interface.flags()
        if flags & QNetworkInterface.InterfaceFlag.IsLoopBack:
            continue
        if not (flags & QNetworkInterface.InterfaceFlag.IsUp):
            continue
        if not (flags & QNetworkInterface.InterfaceFlag.IsRunning):
            continue
        for entrada in interface.addressEntries():
            ip = entrada.ip()
            if ip.protocol() != QAbstractSocket.NetworkLayerProtocol.IPv4Protocol:
                continue
            if ip.isLoopback():
                continue
            texto = ip.toString()
            if texto not in enderecos:
                enderecos.append(texto)
    return enderecos


def enderecos_para_anunciar() -> list:
    """IPv4 que esta máquina publica no mDNS pros peers discarem de volta,
    do mais provável pro menos.

    Anuncia TODOS os endereços ativos, não só um: numa máquina com cabo e
    Wi-Fi ao mesmo tempo (ou com VPN), a interface que sai pra internet não
    é necessariamente a que enxerga as outras máquinas da pizzaria —
    anunciar só uma delas deixava metade da malha sem conseguir conectar.
    O endereço escolhido pela rota vai na frente por ser o mais provável, e
    é o que os peers tentam primeiro.

    Loopback só entra se não houver absolutamente mais nada, e com aviso no
    log: um 127.0.0.1 anunciado faz cada máquina dizer "me procure no meu
    próprio loopback", e o peer que tentar discar conecta nele mesmo. Ele
    ainda serve pra duas instâncias no MESMO computador se acharem (o caso
    dos scripts em docker/), então não vale remover — mas passar por aqui
    calado era a metade mais cara do problema: a malha não formava e não
    havia nada no logs/app.log explicando por quê."""
    enderecos = _ips_das_interfaces()

    preferido = _ip_por_rota()
    if preferido and not preferido.startswith("127."):
        if preferido in enderecos:
            enderecos.remove(preferido)
        enderecos.insert(0, preferido)

    if enderecos:
        return enderecos

    print(
        "[descoberta] AVISO: nenhuma interface de rede ativa com IPv4 — anunciando 127.0.0.1. "
        "As outras máquinas NÃO vão conseguir se conectar a esta. Confira cabo/Wi-Fi e o IP da máquina."
    )
    return ["127.0.0.1"]


class Descoberta(QObject):
    """Interface comum das estratégias de descoberta.

    Emite `peerDescoberto` para cada instância encontrada, incluindo a
    própria máquina e repetindo peers já conhecidos — filtrar isso é
    responsabilidade de quem recebe (RedeService), que é quem sabe com
    quem já está conectado."""

    # (id da instância remota, endereços IP anunciados, porta TCP da malha)
    #
    # É uma LISTA de endereços, não um só: enderecos_para_anunciar() publica
    # todas as interfaces ativas justamente porque a que sai pra internet não
    # é necessariamente a que enxerga as outras máquinas da pizzaria — mas o
    # consumidor tentava só o primeiro, então uma máquina cujo primeiro
    # endereço fosse o de uma bridge do Docker/VirtualBox ou de uma VPN
    # ficava inalcançável mesmo anunciando o endereço bom logo em seguida.
    # Quem recebe tenta todos (ver RedeService._tentar_conectar_a_peer).
    peerDescoberto = pyqtSignal(str, list, int)

    # A descoberta terminou de subir (True) ou desistiu (False). Existe porque
    # a estratégia zeroconf leva ~1,6s e passou a fazer isso numa thread, com
    # a interface já na tela: sem este aviso, nada saberia dizer quando a
    # máquina de fato começou a ser vista pelas outras (ver
    # services/statusInicializacaoService.py).
    iniciada = pyqtSignal(bool)

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
        # Numa thread porque construir o Zeroconf() e registrar o serviço leva
        # ~1,6s (medido), e isto é chamado de RedeService.iniciar(), na thread
        # da interface — era o maior peso da abertura do app, com a janela
        # ainda por desenhar. Nada aqui toca objeto Qt preso a uma thread: é
        # tudo zeroconf puro, e o resultado só sai daqui pelo sinal
        # peerDescoberto, que o Qt entrega na thread certa sozinho.
        threading.Thread(target=self._iniciar_em_thread, daemon=True).start()

    def _iniciar_em_thread(self) -> None:
        # Fechar o app nos primeiros ~1,6s chega aqui com parar() já
        # executado: sem esta checagem a thread seguiria e registraria o
        # serviço depois, deixando um anúncio órfão que ninguém vai
        # desregistrar — as outras máquinas ficariam discando para uma
        # instância morta até o registro expirar sozinho.
        if not self._iniciado:
            return

        try:
            self._zeroconf = Zeroconf()
        except OSError as erro:
            # Porta 5353 ocupada por outro daemon mDNS em modo exclusivo,
            # rede indisponível no boot etc.
            print(f"[descoberta] Não foi possível iniciar o zeroconf ({erro}) — a rede local ficará sem descoberta.")
            self.iniciada.emit(False)
            return

        # O nome do serviço e o do host precisam ser únicos POR INSTÂNCIA, não
        # por máquina: os scripts de teste em docker/ (e um eventual segundo
        # app aberto) rodam duas instâncias no mesmo computador, e o padrão do
        # zeroconf — o hostname da máquina — faria uma sobrescrever o anúncio
        # da outra. O id da instância já é um uuid, então serve para os dois.
        enderecos = enderecos_para_anunciar()
        self._info_servico = ServiceInfo(
            _TIPO_SERVICO,
            f"{self._id_local}.{_TIPO_SERVICO}",
            addresses=[socket.inet_aton(endereco) for endereco in enderecos],
            port=self._porta_tcp,
            properties={"assinatura": _ASSINATURA, "id": self._id_local},
            server=f"{self._id_local}.local.",
        )

        # Segunda checagem: construir o Zeroconf() acima é justamente a parte
        # demorada, e o app pode ter sido fechado nesse meio-tempo.
        if not self._iniciado:
            self._zeroconf.close()
            self._zeroconf = None
            return

        try:
            self._zeroconf.register_service(self._info_servico)
        except OSError as erro:
            print(f"[descoberta] Falha ao anunciar esta máquina via zeroconf: {erro}")

        self._browser = ServiceBrowser(self._zeroconf, _TIPO_SERVICO, handlers=[self._ao_mudar_servico])
        # O endereço anunciado entra no log de propósito: quando a malha não
        # forma, é a primeira coisa que se quer conferir — e era exatamente
        # o que faltava pra diagnosticar o caso do 127.0.0.1.
        print(
            f"[descoberta] Anunciando '{_TIPO_SERVICO}' em {', '.join(enderecos)} "
            f"na porta {self._porta_tcp} e procurando outras máquinas."
        )
        self.iniciada.emit(True)

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
        self.peerDescoberto.emit(id_remoto, list(enderecos), info.port)

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
        # Este caminho é síncrono e rápido (só abre um socket UDP), mas quem
        # escuta não deve precisar saber qual estratégia está em uso.
        self.iniciada.emit(True)

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

            # Aqui só existe um endereço mesmo — o de origem do datagrama —,
            # mas o sinal é uma lista pra ter a mesma forma nas duas
            # estratégias de descoberta.
            self.peerDescoberto.emit(id_remoto, [endereco.toString()], int(porta_tcp))

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
