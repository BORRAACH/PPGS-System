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
    #
    # Os dois últimos: o nome da máquina e se ela já está numa rede. Uma
    # máquina sem chave usa os dois para listar a quem pode pedir entrada, e
    # as pareadas para não discarem para quem ainda não tem chave (ver
    # RedeService._ao_descobrir_peer). Anúncio de versão anterior ao
    # pareamento chega sem nome e contado como pareado.
    peerDescoberto = pyqtSignal(str, list, int, str, bool)

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
        self._nome_local = ""
        self._pareada = False
        self._iniciado = False

    def iniciar(self, id_local: str, porta_tcp: int, nome_local: str = "", pareada: bool = False) -> None:
        """Começa a anunciar esta instância e a procurar as outras.
        `porta_tcp` é a porta onde a malha aceita conexões — é o que os
        peers precisam saber pra discar de volta."""
        if self._iniciado:
            return

        self._id_local = id_local
        self._porta_tcp = porta_tcp
        self._nome_local = nome_local
        self._pareada = bool(pareada)
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

    def definir_pareada(self, pareada: bool) -> None:
        """A máquina entrou numa rede: o anúncio passa a dizer isso, para as
        pareadas começarem a discar para ela."""
        if bool(pareada) == self._pareada:
            return
        self._pareada = bool(pareada)
        if self._iniciado:
            self._reanunciar()

    def _propriedades(self) -> dict:
        return {
            "assinatura": _ASSINATURA,
            "id": self._id_local,
            "nome": self._nome_local,
            "pareada": "1" if self._pareada else "0",
        }

    def _iniciar(self) -> None:
        raise NotImplementedError

    def _reanunciar(self) -> None:
        pass

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
        self._enderecos = []
        # O anúncio muda depois do registro inicial (a máquina entra numa rede,
        # ver definir_pareada), e as duas coisas acontecem em threads
        # diferentes. Sem esta trava a atualização corria no meio do
        # register_service: o zeroconf recusava o registro, a thread dele
        # morria com uma exceção, e a máquina podia ficar sem anúncio nenhum.
        # Acontecia com quem criasse a rede no primeiro segundo do app aberto.
        self._trava_anuncio = threading.Lock()
        self._registrado = False
        self._propriedades_anunciadas = None

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
        with self._trava_anuncio:
            self._enderecos = enderecos
            self._propriedades_anunciadas = self._propriedades()
            self._info_servico = self._montar_info(self._propriedades_anunciadas)

        # Segunda checagem: construir o Zeroconf() acima é justamente a parte
        # demorada, e o app pode ter sido fechado nesse meio-tempo.
        if not self._iniciado:
            self._zeroconf.close()
            self._zeroconf = None
            return

        try:
            with self._trava_anuncio:
                self._zeroconf.register_service(self._info_servico)
                self._registrado = True
        except Exception as erro:
            # OSError de rede e as exceções do próprio zeroconf (nome repetido,
            # laço de eventos ocupado): nenhuma pode matar esta thread calada.
            print(f"[descoberta] Falha ao anunciar esta máquina via zeroconf: {erro!r}")

        self._browser = ServiceBrowser(self._zeroconf, _TIPO_SERVICO, handlers=[self._ao_mudar_servico])
        # O endereço anunciado entra no log de propósito: quando a malha não
        # forma, é a primeira coisa que se quer conferir — e era exatamente
        # o que faltava pra diagnosticar o caso do 127.0.0.1.
        print(
            f"[descoberta] Anunciando '{_TIPO_SERVICO}' em {', '.join(enderecos)} "
            f"na porta {self._porta_tcp} e procurando outras máquinas."
        )
        self.iniciada.emit(True)
        # A máquina pode ter entrado numa rede enquanto o registro acontecia.
        self._atualizar_anuncio()

    def _montar_info(self, propriedades):
        return ServiceInfo(
            _TIPO_SERVICO,
            f"{self._id_local}.{_TIPO_SERVICO}",
            addresses=[socket.inet_aton(endereco) for endereco in self._enderecos],
            port=self._porta_tcp,
            properties=propriedades,
            server=f"{self._id_local}.local.",
        )

    def _reanunciar(self) -> None:
        # Numa thread pelo mesmo motivo de _iniciar: é I/O de rede do zeroconf.
        threading.Thread(target=self._atualizar_anuncio, daemon=True).start()

    def _atualizar_anuncio(self) -> None:
        """Republica o anúncio se o que ele diz (nome, pareada) mudou. Antes de
        o registro inicial terminar não faz nada: o fim do registro chama isto
        de novo."""
        with self._trava_anuncio:
            if self._zeroconf is None or not self._registrado:
                return
            propriedades = self._propriedades()
            if propriedades == self._propriedades_anunciadas:
                return
            info = self._montar_info(propriedades)
            try:
                self._zeroconf.update_service(info)
            except Exception as erro:
                print(f"[descoberta] Falha ao atualizar o anúncio desta máquina: {erro!r}")
                return
            self._info_servico = info
            self._propriedades_anunciadas = propriedades

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
        nome = (propriedades.get(b"nome") or b"").decode("utf-8", "ignore")
        pareada = propriedades.get(b"pareada") != b"0"

        # Emitido de dentro desta thread; como o objeto vive na thread
        # principal, o Qt entrega o sinal lá (conexão em fila), então quem
        # recebe pode mexer nos sockets sem se preocupar com thread.
        self.peerDescoberto.emit(id_remoto, list(enderecos), info.port, nome, pareada)

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

    def _reanunciar(self) -> None:
        self._anunciar()

    def _anunciar(self) -> None:
        mensagem = json.dumps(dict(self._propriedades(), porta_tcp=self._porta_tcp)).encode("utf-8")
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
            self.peerDescoberto.emit(
                id_remoto, [endereco.toString()], int(porta_tcp),
                str(dados.get("nome") or ""), dados.get("pareada") != "0",
            )

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
