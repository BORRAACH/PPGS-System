import base64
import hashlib
import json
import os
import platform
import random
import threading
import time
import uuid
from datetime import datetime

from PyQt6.QtCore import QObject, QByteArray, QTimer, pyqtProperty, pyqtSignal, pyqtSlot
from PyQt6.QtNetwork import QHostAddress, QTcpServer, QTcpSocket

from Config.logConfig import protegido
from services.printerService import PrinterService
from services.rede import caminhos, historicoEventos, impressoraFixada, indicePedidos, relogio, seguranca, sequenciaComandas, servidorDesignado, tombstones
from services.rede.descoberta import criar_descoberta
from services.rede.eventos import BarramentoEventos

# Tipo de evento de gossip que anuncia um número de comanda reservado (ver
# reservar_numero_comanda e services/rede/sequenciaComandas.py).
_EVENTO_COMANDA_NUMERADA = "comanda_numerada"
# Anuncia à malha qual máquina passa a hospedar o ppgs_server (ver
# designarServidor/services/rede/servidorDesignado.py).
_EVENTO_SERVIDOR_DESIGNADO = "servidor_designado"

_INTERVALO_CHECAGEM_IMPRESSORA_MS = 30000
_TIMEOUT_IMPRESSAO_MS = 10000
# Quanto se espera um socket fechar o handshake da malha (ver
# services/rede/seguranca.py) antes de desistir dele. Cobre dois casos
# reais e indistinguíveis do lado de cá: uma máquina ainda rodando a
# versão antiga do sistema (que nunca vai mandar o frame 'ola'), e um
# scanner de portas que abre a conexão e fica calado. Sem isto, os dois
# deixariam um socket e uma sessão vivos para sempre.
_TIMEOUT_HANDSHAKE_MS = 8000
# Teto de espera de uma requisição HTTP encaminhada pela malha até o
# ppgs_server da máquina hospedeira (ver solicitar_servidor). Mais folgado
# que os 5s que o cliente HTTP usava contra a LAN: agora há dois saltos
# (malha até a hospedeira, e loopback dela até o servidor), e a hospedeira
# é uma máquina de balcão que pode estar imprimindo no mesmo instante.
_TIMEOUT_SERVIDOR_MS = 12000
# De quanto em quanto tempo se tenta reconectar a um peer que a descoberta
# já anunciou mas com quem não há conexão aberta agora (ver
# _tentar_reconectar). Sem isto, uma única tentativa de conexão que falhe
# (endereço de bridge Docker/VPN, firewall ainda fechado, app do outro lado
# ainda subindo) só era refeita se o zeroconf reemitisse o anúncio — o que
# pode demorar muito ou não acontecer, deixando as duas máquinas
# permanentemente sem se falar.
# Base curta de propósito: além de refazer tentativas que falharam, este
# timer é o que libera o lado de id MAIOR a discar (ver
# _tentar_conectar_a_peer), então ele define quanto tempo a malha demora a se
# formar quando a descoberta só funciona num sentido. O backoff exponencial
# abaixo é o que impede que uma base curta vire tráfego/log constante contra
# peers que não respondem.
_INTERVALO_RECONEXAO_MS = 5000
# Teto do backoff entre tentativas pro mesmo peer. Nem todo anúncio que a
# descoberta entrega corresponde a uma instância que ainda existe: cada
# execução do app tem um id novo, então processos curtos (os scripts de
# docker/) e reinícios deixam para trás anúncios de instâncias mortas. Sem
# backoff, cada um desses vira uma tentativa de conexão a cada 20s pra
# sempre — sockets desperdiçados e, pior, uma linha de erro a cada tentativa
# afogando o logs/app.log justamente onde se procura problema de rede.
# Continuar tentando (em vez de desistir de vez) é o certo: quem "sumiu"
# pode voltar, e o anúncio antigo pode ser o único registro do endereço
# dele.
_BACKOFF_MAXIMO_SEGUNDOS = 300
# Intervalo do ciclo de anti-entropy (ver registrarDominioSincronizado/
# _disparar_reconciliacao) — a rede de segurança que corrige o que o
# gossip (services/rede/eventos.py) perdeu por causa de uma máquina
# offline no momento de um evento, ou uma mensagem perdida durante uma
# conexão contínua. Não afeta a velocidade normal de sincronização
# (gossip continua quase instantâneo quando as máquinas estão online ao
# mesmo tempo) — só o tempo até uma divergência se autocorrigir. Variável
# de ambiente só pra acelerar os testes em docker/, não pensada pra uso em
# produção.
_INTERVALO_RECONCILIACAO_MS = int(os.environ.get("PIZZARIA_RECONCILIACAO_MS", "120000"))


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

    # (nome do arquivo, bytes, idEvento de origem, máquina de origem) — os
    # dois últimos vêm de quem criou a comanda e são regravados como estão
    # do outro lado, nunca gerados de novo: é o que faz as máquinas
    # concordarem sobre onde cada comanda está na linha do tempo comum.
    pedidoRecebido = pyqtSignal(str, QByteArray, str, str)
    # (nome do arquivo, idEvento do tombstone)
    pedidoRemovidoRemoto = pyqtSignal(str, str)
    peersMudaram = pyqtSignal(int)
    # Emitido quando o resultado de um pedido de impressão é conhecido
    # (sucesso, nome da máquina que imprimiu ou motivo da falha).
    impressaoResultado = pyqtSignal(bool, str)
    # Emitido sempre que a máquina eleita pra imprimir (ou os dados da
    # impressora dela) pode ter mudado — Rede.qml usa pra reconsultar
    # impressoraPrincipal() e atualizar o painel sozinho.
    impressoraPrincipalMudou = pyqtSignal()
    # (id_req, status HTTP, corpo) — resposta de uma requisição encaminhada
    # ao ppgs_server. status 0 significa que ela não chegou a ser respondida
    # (sem hospedeira, timeout, socket caído).
    respostaServidor = pyqtSignal(str, int, QByteArray)
    # A máquina que hospeda o ppgs_server mudou (ou o preparo dela mudou de
    # estado) — a tela Rede e o cliente HTTP reagem a isto.
    servidorDesignadoMudou = pyqtSignal()
    # (nome da máquina hospedeira, servidor no ar nela) — o aviso DIRETO que a
    # hospedeira manda no instante em que o ppgs_server dela sobe ou cai, mais
    # o que ela conta de si mesma no handshake. Existe porque o único jeito de
    # um terminal descobrir isso antes era perguntando de 30 em 30 segundos
    # (ver services/pizzeriaServerService.py): o servidor subia e o balcão
    # ficava até meio minuto sem autofill de endereço, sem nada acontecendo na
    # rede além da espera.
    servidorNoArMudou = pyqtSignal(str, bool)
    # Uso interno: uma requisição encaminhada terminou nesta máquina e
    # precisa voltar pro socket de origem a partir da thread dele.
    _servidorRespostaLocal = pyqtSignal(str, str, int, QByteArray)
    # Uso interno: o ServidorLocalService avisa que o processo do servidor
    # subiu/caiu de dentro da thread de preparo dele, e anunciar isso escreve
    # em QTcpSocket — só seguro na thread que os criou. Mesmo motivo (e mesmo
    # desenho) de _servidorRespostaLocal acima.
    _servidorLocalNoAr = pyqtSignal(bool)
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
        # Marca de "quando este PROCESSO entrou na malha" (ver letraLocal
        # abaixo) — nunca persistida em disco, fixada uma vez aqui e nunca
        # regenerada depois: é o próprio reinício do processo (desligar e
        # ligar a máquina, ou fechar e reabrir o app) que dá uma marca nova
        # e mais recente, empurrando a letra pro fim da fila — não dá pra
        # basear isso em "os peers desta máquina zeraram", porque uma
        # máquina que nunca saiu do ar também fica com zero peers sempre que
        # TODAS as outras é que estão fora (ex.: só ela ligada no momento),
        # e nesse caso ela não "reentrou" em lugar nenhum.
        self._id_entrada = relogio.novo_id()
        self._nome_local = platform.node() or "Máquina desconhecida"
        self._peers = {}  # id da instância -> QTcpSocket
        self._info_peers = {}  # id da instância -> {"nome", "endereco", "conectadoEm", "temImpressora", "infoImpressora"}
        self._buffers = {}  # QTcpSocket -> bytearray (frames incompletos)
        # Criptografia por socket: QTcpSocket -> seguranca.SessaoSegura.
        # Um socket só entra em _peers depois que a sessão dele fecha o
        # handshake, então nada que chegue antes disso é processado como
        # protocolo.
        self._sessoes = {}
        # Peers que apareceram mas foram recusados no handshake — endereço ->
        # motivo. Com a chave igual em toda máquina, o que sobra aqui é
        # incompatibilidade de versão: uma máquina atualizada e outra não se
        # recusam explicitamente em vez de travar num frame que a outra não
        # sabe ler. Existe pra tela Rede poder dizer qual é o motivo — sem
        # isso, "a outra máquina não aparece" é indistinguível de a rede estar
        # fora do ar, que foi exatamente a confusão que este projeto já pagou
        # caro uma vez (ver architecture/EXPLAIN.md, "Observabilidade").
        self._recusados = {}
        # A chave que assina o handshake e alimenta o HKDF. Hoje é uma
        # constante igual em toda máquina (ver seguranca.CHAVE_PADRAO); segue
        # guardada num campo porque é assim que ela chega em cada SessaoSegura,
        # e porque é o ponto que volta a variar por instalação no dia em que a
        # rede da pizzaria deixar de ser confiável.
        self._chave_malha = seguranca.carregar_chave()
        # Tudo que a descoberta já anunciou, conectado ou não — id da
        # instância -> {"enderecos": [str], "porta": int, "tentativas": int}.
        # É o que permite reconectar sem depender de o zeroconf reemitir o
        # anúncio (ver _tentar_reconectar).
        self._peers_conhecidos = {}
        self._iniciado = False

        self._printer_service = PrinterService()
        # Guarda contra ciclos de detecção sobrepostos (ver
        # _detectar_impressora_local) — leitura/escrita de bool é atômica
        # no CPython (GIL), não precisa de lock pra essa checagem simples
        # de "pula este ciclo se o anterior ainda não terminou".
        self._detectando_impressora_local = False
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
        # Requisições HTTP encaminhadas pela malha, esperando resposta —
        # id_req -> {"timer": QTimer, "concluido": bool}. Mesmo desenho dos
        # jobs de impressão acima.
        self._jobs_servidor = {}
        # Máquina que hospeda o ppgs_server, por nome, e o idEvento da
        # decisão (ver services/rede/servidorDesignado.py). Lido do disco
        # aqui pra uma máquina que liga sozinha já saber que é ela;
        # atualizado depois por gossip.
        self._nome_servidor, self._id_evento_servidor = servidorDesignado.carregar()
        # Preenchido pelo ServidorLocalService desta máquina quando ela é a
        # hospedeira — encaminhar requisições exige o token, e só ele sabe
        # se o processo já subiu.
        self._encaminhar_para_servidor_local = None
        # O ppgs_server desta máquina está no ar? Só chega a ser verdadeiro na
        # hospedeira, e é isto que ela anuncia aos peers e conta no handshake
        # (ver anunciar_servidor_no_ar).
        self._servidor_no_ar_local = False

        # Domínios de estado inscritos na camada de anti-entropy periódica
        # (ver registrarDominioSincronizado) — nome -> {"resumo", "obter",
        # "aplicar", "apagar"}. RedeService nunca sabe o que cada domínio
        # significa, só itera genericamente (mesma separação de
        # responsabilidade documentada em services/rede/eventos.py).
        self._dominios_sincronizados = {}

        self._tcp_server = QTcpServer(self)
        self._timer_impressora = QTimer(self)
        self._timer_reconciliacao = QTimer(self)
        self._timer_reconexao = QTimer(self)
        self._descoberta = criar_descoberta(self)

        self._eventos = BarramentoEventos(self._propagar_evento)
        self._eventos.registrar("pedido_novo", self._ao_receber_evento_pedido_novo)
        self._eventos.registrar("pedido_apagado", self._ao_receber_evento_pedido_apagado)
        self._eventos.registrar("impressora_fixada", self._ao_receber_evento_impressora_fixada)
        self._eventos.registrar(_EVENTO_COMANDA_NUMERADA, self._ao_receber_evento_comanda_numerada)
        self._eventos.registrar(_EVENTO_SERVIDOR_DESIGNADO, self._ao_receber_evento_servidor_designado)
        self._servidorRespostaLocal.connect(self._responder_servidor_ao_peer)
        self._servidorLocalNoAr.connect(self._ao_mudar_servidor_local)

        # Histórico da malha: eventos são imutáveis, então a reconciliação é a
        # união dos dois lados e não existe "apagar" (a retenção é local, ver
        # historicoEventos._purgados). É este registro que faz uma máquina que
        # entra na malha receber o histórico acumulado por quem já estava lá.
        self.registrarDominioSincronizado(
            "historico",
            historicoEventos.resumo,
            historicoEventos.obter,
            historicoEventos.aplicar,
        )

        # Números de comanda já reservados (ver
        # services/rede/sequenciaComandas.py). Conjunto que só cresce dentro
        # de cada dia, então reconciliar é a união dos dois lados e não existe
        # "apagar" — mesma forma do domínio "historico" acima.
        self.registrarDominioSincronizado(
            "sequencia",
            self._resumo_sequencia,
            self._obter_sequencia_reconciliacao,
            self._aplicar_sequencia_reconciliacao,
        )

        # Republica as reservas de hoje quando um peer NOVO entra — fecha a
        # janela do arranque, em que a anti-entropy ainda não rodou (ela só
        # começa depois de um jitter de 0-10s, ver iniciar()) e uma máquina
        # recém-aberta numeraria a partir do zero. Mesmo padrão e mesma
        # justificativa de SalaoController._ao_peers_mudarem.
        self._ultima_quantidade_peers = 0
        self.peersMudaram.connect(self._ao_peers_mudarem_sequencia)

        self._impressoraLocalVerificada.connect(self._ao_verificar_impressora_local)
        self._imprimirRemotoConcluido.connect(self._ao_concluir_imprimir_remoto)
        self._descoberta.peerDescoberto.connect(self._ao_descobrir_peer)

    @pyqtProperty(int, notify=peersMudaram)
    def quantidadeConectados(self):
        return len(self._peers)

    @pyqtProperty(str, constant=True)
    def nomeLocal(self):
        return self._nome_local

    @pyqtProperty(str, notify=peersMudaram)
    def letraLocal(self):
        """Letra (A, B, C...) desta máquina por ordem de entrada dos
        PROCESSOS atualmente na malha (ver
        services/comandaSequencialService.py) — a mesma que sai impressa no
        código da comanda. Calculada ao vivo a partir de self._id_entrada
        (marca de quando ESTE processo nasceu, ver __init__) e do
        "idEntrada" que cada peer conectado mandou no handshake (ver
        _processar_mensagem), nunca de um histórico persistido: desligar e
        religar uma máquina (ou fechar e reabrir o app) cria um processo
        novo, com uma self._id_entrada mais recente, que entra de novo no
        fim da fila em vez de reter a posição de antes da queda. Como
        depende de quem está conectado agora, pode mudar sem esta própria
        máquina reiniciar — ex.: se a máquina "A" cai de vez, as demais
        recalculam suas letras uma posição acima — por isso notifica em
        peersMudaram em vez de constant=True."""
        entradas = [(self._id, self._id_entrada)]
        for id_remoto, info in self._info_peers.items():
            id_entrada = info.get("idEntrada")
            if id_entrada:
                entradas.append((id_remoto, id_entrada))
        entradas.sort(key=lambda par: par[1])
        return chr(ord("A") + [id_ for id_, _ in entradas].index(self._id))

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarPeers(self):
        """Máquinas atualmente conectadas na malha, mais recente primeiro."""
        peers = list(self._info_peers.values())
        peers.sort(key=lambda peer: peer["conectadoEm"], reverse=True)
        return peers

    @pyqtSlot(int, result="QVariantList")
    @protegido([])
    def listarHistorico(self, limite=200):
        """Histórico da malha para a tela de Rede, mais recente primeiro (ver
        services/rede/historicoEventos.py)."""
        return historicoEventos.listar(limite)

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def categoriasHistorico(self):
        """Categorias existentes, para montar o filtro da tela sem repetir a
        lista no QML."""
        return [
            {"chave": chave, "rotulo": rotulo}
            for chave, rotulo in historicoEventos.ROTULOS_CATEGORIAS.items()
        ]

    def iniciar(self):
        """Abre os sockets e começa a anunciar/descobrir peers. Precisa ser
        chamado depois que QGuiApplication já existe."""
        if self._iniciado:
            return

        # Antes de abrir qualquer porta: sem a biblioteca de criptografia não
        # há malha. Subir "por enquanto em claro" e endurecer depois seria o
        # pior dos dois mundos — a rede pareceria funcionar, ninguém voltaria
        # pra terminar, e as comandas e endereços dos clientes iriam pelo ar
        # legíveis pra quem estivesse ouvindo. O app continua inteiro: comandas
        # são salvas e impressas localmente; só a sincronização espera.
        motivo = self._motivo_para_nao_iniciar()
        if motivo:
            from services.statusInicializacaoService import status

            print(f"[RedeService] Malha não iniciada: {motivo}")
            status.falhou("rede", motivo)
            return

        self._iniciado = True

        self._tcp_server.newConnection.connect(self._ao_conectar_entrada)
        if not self._tcp_server.listen(QHostAddress.SpecialAddress.Any, 0):
            print("[RedeService] Falha ao abrir porta TCP para a malha local — esta máquina não vai sincronizar comandas.")
            return

        # A porta TCP é sorteada pelo sistema (listen na porta 0), então só
        # dá pra anunciá-la depois que o servidor está de pé.
        print(f"[RedeService] Esta máquina é '{self._nome_local}' (instância {self._id[:8]}), ouvindo na porta {self._tcp_server.serverPort()}.")
        # Repassado à tela: a descoberta sobe numa thread (leva ~1,6s) e
        # iniciar() volta antes dela ficar pronta, então "a malha está no ar"
        # é uma resposta que só ela pode dar.
        self._descoberta.iniciada.connect(self._ao_iniciar_descoberta)
        self._descoberta.iniciar(self._id, self._tcp_server.serverPort())

        # Rede de segurança da conexão: refaz sozinho as tentativas que
        # falharam, sem depender de a descoberta reanunciar o peer.
        self._timer_reconexao.timeout.connect(self._tentar_reconectar)
        self._timer_reconexao.start(_INTERVALO_RECONEXAO_MS)

        # Detecta a impressora local uma vez já ao iniciar, e depois
        # periodicamente — cobre o caso de a impressora ser plugada com o
        # app já aberto.
        self._detectar_impressora_local()
        self._timer_impressora.timeout.connect(self._detectar_impressora_local)
        self._timer_impressora.start(_INTERVALO_CHECAGEM_IMPRESSORA_MS)

        # Anti-entropy: começa com um atraso aleatório (0-10s) só no
        # arranque, pra várias máquinas ligadas juntas (ex: todas no início
        # do expediente) não disparem o primeiro ciclo exatamente no mesmo
        # instante — o intervalo entre disparos depois disso continua fixo.
        self._timer_reconciliacao.timeout.connect(self._disparar_reconciliacao)
        QTimer.singleShot(
            random.randint(0, 10000),
            lambda: self._timer_reconciliacao.start(_INTERVALO_RECONCILIACAO_MS),
        )

    def _motivo_para_nao_iniciar(self) -> str:
        """Texto pronto pra tela, ou "" se está tudo certo pra subir.

        Sobrou um motivo só. A falta de chave não é mais um deles: ela agora é
        uma constante do código (ver seguranca.CHAVE_PADRAO), então toda
        máquina tem a mesma e a malha sobe sozinha, como era antes de a chave
        por instalação existir."""
        if not seguranca.DISPONIVEL:
            return "Falta a biblioteca 'cryptography' — rede local desativada"
        return ""

    @pyqtProperty(str, notify=peersMudaram)
    def motivoMalhaParada(self) -> str:
        return self._motivo_para_nao_iniciar() if not self._iniciado else ""

    @pyqtProperty(str, notify=peersMudaram)
    def peersRecusados(self) -> str:
        """Resumo dos peers que apareceram e foram recusados. A tela mostra
        isto porque o sintoma de um peer recusado — "a outra máquina não
        aparece" — é idêntico ao de um cabo solto, e sem esta linha o usuário
        não teria como distinguir os dois."""
        if not self._recusados:
            return ""
        motivos = set(self._recusados.values())
        return f"{len(self._recusados)} máquina(s) recusada(s): {'; '.join(sorted(motivos))}"

    # ---------- Descoberta ----------

    def _ao_iniciar_descoberta(self, ok: bool):
        from services.statusInicializacaoService import status

        if ok:
            status.concluida("rede", "Rede local no ar")
        else:
            status.falhou("rede", "Rede local indisponível")

    def _ao_descobrir_peer(self, id_remoto: str, enderecos: list, porta_tcp: int):
        """Uma instância apareceu na rede (ver services/rede/descoberta.py).
        A descoberta avisa de tudo que encontra, inclusive desta própria
        máquina e de peers repetidos — filtrar é aqui, que é quem sabe com
        quem já existe conexão aberta."""
        if id_remoto == self._id or not enderecos or not porta_tcp:
            return

        conhecido = self._peers_conhecidos.get(id_remoto)
        novidade = (
            conhecido is None
            or conhecido["enderecos"] != list(enderecos)
            or conhecido["porta"] != porta_tcp
        )
        if novidade:
            print(f"[RedeService] Peer descoberto: instância {id_remoto[:8]} em {', '.join(enderecos)}:{porta_tcp}.")

        self._peers_conhecidos[id_remoto] = {
            "enderecos": list(enderecos),
            "porta": porta_tcp,
            "tentativas": 0 if novidade or conhecido is None else conhecido["tentativas"],
            # Um anúncio novo é indício de que o peer está vivo agora, então
            # zera o backoff e volta a tentar imediatamente.
            "falhas": 0 if novidade else conhecido["falhas"],
            "proximaTentativa": 0.0,
        }

        if id_remoto in self._peers:
            return

        self._tentar_conectar_a_peer(id_remoto)

    def _tentar_reconectar(self):
        """Tenta de novo todo peer que a descoberta já anunciou mas com quem
        não há conexão aberta agora, respeitando o backoff de cada um. Roda a
        cada _INTERVALO_RECONEXAO_MS."""
        agora = time.time()
        for id_remoto, conhecido in list(self._peers_conhecidos.items()):
            if id_remoto in self._peers or agora < conhecido["proximaTentativa"]:
                continue

            self._tentar_conectar_a_peer(id_remoto)

            conhecido["falhas"] += 1
            espera = min(
                (_INTERVALO_RECONEXAO_MS / 1000) * (2 ** (conhecido["falhas"] - 1)),
                _BACKOFF_MAXIMO_SEGUNDOS,
            )
            conhecido["proximaTentativa"] = agora + espera

    def _tentar_conectar_a_peer(self, id_remoto: str):
        """Abre uma conexão para CADA endereço anunciado pelo peer.

        Dois lados podem acabar discando um pro outro, e um mesmo peer pode
        receber várias conexões desta máquina (uma por endereço) — as
        sobrando são fechadas pelo tratamento de "identificar", que descarta
        conexão redundante com um peer já conhecido. Desperdiçar alguns
        sockets é muito mais barato que o modo de falha oposto: duas
        máquinas que se enxergam na descoberta e nunca trocam uma comanda.

        A regra "só quem tem o id menor disca" continua valendo na primeira
        passada, porque no caminho feliz ela evita a conexão dupla. Mas ela
        deixa de ser absoluta: a partir da segunda tentativa o lado de id
        maior também disca. Sem isso, bastava a descoberta funcionar num
        sentido só (comum quando um dos lados tem firewall bloqueando mDNS
        de entrada) pra malha nunca se formar, já que o único lado autorizado
        a discar era justamente o que não enxergava ninguém."""
        conhecido = self._peers_conhecidos.get(id_remoto)
        if conhecido is None:
            return

        conhecido["tentativas"] += 1
        if self._id > id_remoto and conhecido["tentativas"] == 1:
            return

        for endereco in conhecido["enderecos"]:
            self._conectar_a(QHostAddress(endereco), conhecido["porta"], id_remoto)

    # ---------- Conexões TCP (malha) ----------

    def _conectar_a(self, endereco: QHostAddress, porta: int, id_remoto: str = ""):
        socket = QTcpSocket(self)
        self._preparar_socket(socket, f"{endereco.toString()}:{porta}", id_remoto)
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
            # Marca de quando ESTA máquina entrou na malha atual (ver
            # letraLocal) — só a própria, não uma tabela de todo mundo:
            # como a malha é sempre full-mesh, cada peer já manda a dele
            # diretamente pra todo mundo, não precisa repassar de terceiros.
            "idEntrada": self._id_entrada,
            # Pelo mesmo motivo de nomeMaquinaFixada logo acima: quem conecta
            # DEPOIS de o servidor já ter subido não recebeu o aviso da hora
            # (ver _ao_mudar_servidor_local, que só alcança quem estava
            # conectado naquele instante) e ficaria esperando o próximo tique
            # de verificação para descobrir o que a hospedeira já sabia.
            "servidorNoAr": self._servidor_no_ar_local,
            # QUEM hospeda, não só se está no ar — e pelo mesmo motivo de
            # nomeMaquinaFixada. A designação só viajava no evento de gossip
            # publicado no instante do clique em "Rodar aqui", que alcança
            # exclusivamente quem estava conectado NAQUELE momento. A máquina
            # que abre o app depois (o balcão que liga às 18h, a máquina nova,
            # a que foi reinstalada) nunca aprendia por caminho nenhum: ficava
            # com _nome_servidor vazio, e aí solicitar_servidor responde 0 sem
            # nem sair da máquina — a tela de Rede dizia "Servidor central
            # inacessível" para sempre, com o servidor de pé e anunciado ao
            # lado. O idEvento vai junto porque é ele que arbitra duas
            # designações em disputa (ver _aplicar_designacao).
            "nomeMaquinaServidor": self._nome_servidor,
            "idEventoServidor": self._id_evento_servidor,
        }

    def _preparar_socket(self, socket: QTcpSocket, destino: str = "", id_remoto: str = ""):
        self._buffers[socket] = bytearray()
        socket.readyRead.connect(lambda: self._ao_ler(socket))
        socket.disconnected.connect(lambda: self._ao_desconectar(socket))
        socket.errorOccurred.connect(lambda erro: self._ao_falhar_socket(socket, erro, destino, id_remoto))

        try:
            self._sessoes[socket] = seguranca.SessaoSegura(self._chave_malha, self._id)
        except seguranca.ErroSeguranca as erro:
            print(f"[RedeService] Não foi possível abrir sessão segura: {erro}")
            socket.close()
            return

        # Duas etapas agora, onde antes havia uma: primeiro o handshake de
        # criptografia (frame 'ola', em claro — ele carrega só chave pública
        # e nonce, nada sigiloso), e só quando ele fecha é que o
        # 'identificar' sai, já selado. É o que garante que nenhum peer sem a
        # chave chegue a ver quem somos, que impressora temos ou qualquer
        # comanda.
        socket.connected.connect(lambda: self._abrir_handshake(socket))
        if socket.state() == QTcpSocket.SocketState.ConnectedState:
            self._abrir_handshake(socket)

        # Um socket que abre e nunca fecha o handshake (versão antiga do
        # sistema do outro lado, ou alguém varrendo portas) seria um vazamento
        # permanente sem este corte.
        QTimer.singleShot(_TIMEOUT_HANDSHAKE_MS, lambda: self._cortar_handshake_pendente(socket, destino))

    def _abrir_handshake(self, socket: QTcpSocket):
        sessao = self._sessoes.get(socket)
        if sessao is None:
            return
        socket.write(sessao.frame_inicial())

    def _cortar_handshake_pendente(self, socket: QTcpSocket, destino: str):
        try:
            sessao = self._sessoes.get(socket)
            if sessao is None or sessao.pronta:
                return
            onde = destino or socket.peerAddress().toString()
            print(f"[RedeService] Handshake da malha não fechou em {_TIMEOUT_HANDSHAKE_MS // 1000}s com {onde} — pode ser uma máquina com a versão antiga do sistema.")
            self._recusar_socket(socket, "handshake não concluído", onde)
        except RuntimeError:
            pass

    def _recusar_socket(self, socket: QTcpSocket, motivo: str, onde: str = ""):
        """Fecha e registra. O registro é o ponto: uma máquina recusada (hoje,
        na prática, uma rodando outra versão do protocolo) precisa aparecer na
        tela como recusada, não simplesmente sumir."""
        try:
            onde = onde or socket.peerAddress().toString()
            if onde:
                self._recusados[onde] = motivo
            self._sessoes.pop(socket, None)
            self._buffers.pop(socket, None)
            socket.close()
            socket.deleteLater()
            self.peersMudaram.emit(len(self._peers))
        except RuntimeError:
            pass

    def _ao_falhar_socket(self, socket: QTcpSocket, erro, destino: str, id_remoto: str):
        """Um socket que nunca chegou a conectar não emite `disconnected`,
        então `_ao_desconectar` nunca roda pra ele: antes disto, cada
        tentativa frustrada deixava para trás uma entrada em `_buffers` e um
        QTcpSocket vivo. Como agora se tenta um socket por endereço
        anunciado, e de novo a cada ciclo de reconexão, isso vazaria rápido.

        Loga só a PRIMEIRA falha de cada peer (ver o campo "falhas" em
        _peers_conhecidos, zerado assim que uma conexão dá certo): o
        diagnóstico útil é "não consegui falar com esta máquina", e repetir
        isso a cada ciclo de retry, pra cada endereço anunciado, encheria o
        log sem acrescentar nada. Também não loga falha de peer que já está
        conectado por outro endereço — com vários endereços anunciados, é
        esperado que só um funcione."""
        try:
            ja_conectado = bool(id_remoto) and id_remoto in self._peers
            conhecido = self._peers_conhecidos.get(id_remoto) if id_remoto else None
            primeira_falha = conhecido is None or conhecido["falhas"] <= 1
            if not ja_conectado and destino and primeira_falha:
                print(f"[RedeService] Não foi possível conectar em {destino}: {socket.errorString()} ({erro.name if hasattr(erro, 'name') else erro}).")
            self._buffers.pop(socket, None)
            self._sessoes.pop(socket, None)
            socket.close()
            socket.deleteLater()
        except RuntimeError:
            # Desconexão chegando durante o encerramento do app — o objeto
            # C++ por trás do socket já pode ter sido destruído.
            pass

    def _ao_desconectar(self, socket: QTcpSocket):
        # Tudo aqui pode falhar com RuntimeError se a desconexão chegar
        # durante o encerramento do app (o objeto Qt em C++ por trás do
        # socket, ou o próprio RedeService, já pode ter sido destruído) —
        # nesse ponto não há mais nada útil a fazer, então só ignora.
        try:
            self._buffers.pop(socket, None)
            self._sessoes.pop(socket, None)
            id_removido = None
            for id_peer, sock in list(self._peers.items()):
                if sock is socket:
                    id_removido = id_peer
                    del self._peers[id_peer]
            socket.deleteLater()
            if id_removido is not None:
                nome = (self._info_peers.pop(id_removido, None) or {}).get("nome", "máquina desconhecida")
                print(f"[RedeService] Peer '{nome}' desconectou — {len(self._peers)} peer(s) na malha. Vai ser rediscado a cada {_INTERVALO_RECONEXAO_MS // 1000}s.")
                historicoEventos.registrar_local("maquina_desconectada", {"nome": nome})
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

    # ---------- Protocolo (JSON selado, em frames com prefixo de tamanho) ----------
    #
    # Era JSON delimitado por "\n". Um frame selado é binário e pode conter
    # 0x0A em qualquer posição, então a delimitação passou a ser o prefixo de
    # 4 bytes de seguranca.enquadrar/desenquadrar. O formato das mensagens em
    # si não mudou — quem lê _processar_mensagem continua vendo os mesmos
    # dicts de sempre.

    def _enviar(self, socket: QTcpSocket, mensagem: dict):
        if socket.state() != QTcpSocket.SocketState.ConnectedState:
            return
        sessao = self._sessoes.get(socket)
        if sessao is None or not sessao.pronta:
            # Não há fila de espera de propósito: tudo que este serviço manda
            # ou é resposta a algo que chegou pela sessão (logo, ela já está
            # pronta), ou é um broadcast que percorre self._peers — e um
            # socket só entra ali depois do handshake.
            return
        try:
            socket.write(sessao.selar(json.dumps(mensagem).encode("utf-8")))
        except seguranca.ErroSeguranca as erro:
            print(f"[RedeService] Falha ao selar mensagem: {erro}")
            socket.close()

    def _ao_ler(self, socket: QTcpSocket):
        buffer = self._buffers.setdefault(socket, bytearray())
        buffer.extend(bytes(socket.readAll()))

        sessao = self._sessoes.get(socket)
        if sessao is None:
            return

        try:
            frames = seguranca.desenquadrar(buffer)
        except seguranca.ErroSeguranca as erro:
            print(f"[RedeService] Enquadramento inválido: {erro}")
            self._recusar_socket(socket, "enquadramento inválido")
            return

        for frame in frames:
            if not sessao.pronta:
                if not self._avancar_handshake(socket, sessao, frame):
                    return
                continue
            try:
                mensagem = json.loads(sessao.abrir(frame).decode("utf-8"))
            except seguranca.ErroSeguranca as erro:
                print(f"[RedeService] Frame não autenticou: {erro}")
                self._recusar_socket(socket, "frame não autenticado")
                return
            except (ValueError, UnicodeDecodeError):
                # Frame autenticou (veio mesmo de quem tem a chave) mas o
                # conteúdo não é JSON — versão futura mandando algo que esta
                # não entende. Ignorar um e seguir é melhor que derrubar a
                # conexão inteira.
                continue
            self._processar_mensagem(socket, mensagem)

    def _avancar_handshake(self, socket: QTcpSocket, sessao, frame: bytes) -> bool:
        """Devolve False quando o socket foi recusado e não se deve continuar
        lendo os frames restantes dele."""
        try:
            respostas = sessao.receber(frame)
        except seguranca.ErroSeguranca as erro:
            onde = socket.peerAddress().toString()
            print(f"[RedeService] Handshake recusado com {onde}: {erro}")
            historicoEventos.registrar_local("maquina_recusada", {"motivo": str(erro), "endereco": onde})
            self._recusar_socket(socket, str(erro), onde)
            return False

        for resposta in respostas or []:
            socket.write(resposta)

        if sessao.pronta:
            # A partir daqui o fio está cifrado e autenticado nos dois
            # sentidos — só agora o 'identificar' (nome da máquina,
            # impressora, fixação) pode sair.
            self._recusados.pop(socket.peerAddress().toString(), None)
            self._enviar(socket, self._mensagem_identificar())
        return True

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
                "idEntrada": mensagem.get("idEntrada"),
                "servidorNoAr": bool(mensagem.get("servidorNoAr")),
            }
            print(f"[RedeService] Conectado a '{self._info_peers[id_remoto]['nome']}' ({self._info_peers[id_remoto]['endereco']}) — {len(self._peers)} peer(s) na malha.")
            # Entrada/saída de máquina não passa pelo barramento de eventos
            # (é estado de socket, não uma mudança de dado a propagar), então
            # é anotada no histórico à mão. Fica local a quem observou: cada
            # máquina enxerga as conexões pelo seu próprio ponto de vista.
            historicoEventos.registrar_local(
                "maquina_conectada", {"nome": self._info_peers[id_remoto]["nome"]}
            )
            # Handshake concluído: o peer está vivo, então o backoff de
            # reconexão dele volta ao início (importante pra uma queda futura
            # ser tratada rápido, e não herdar a espera longa de uma
            # indisponibilidade antiga).
            conhecido = self._peers_conhecidos.get(id_remoto)
            if conhecido is not None:
                conhecido["falhas"] = 0
                conhecido["proximaTentativa"] = 0.0
            adotou_fixacao = self._ao_receber_identificar_fixacao(mensagem.get("nomeMaquinaFixada"))
            self.peersMudaram.emit(len(self._peers))
            self._recalcular_maquina_impressora()
            if adotou_fixacao:
                # _recalcular_maquina_impressora só emite impressoraPrincipalMudou
                # se o candidato eleito mudar — mas Rede.qml também depende
                # desse sinal pra atualizar nomeMaquinaFixada/candidatosImpressora
                # (ver fixarImpressoraPrincipal, mesmo motivo documentado lá).
                self.impressoraPrincipalMudou.emit()
            # Quem hospeda o servidor, aprendido do peer. ANTES do aviso de
            # "servidor no ar" logo abaixo, e não depois: aquele aviso faz o
            # PizzeriaServerService conferir a conexão na hora, e uma conferência
            # feita sem saber para qual máquina mandar a requisição falha na
            # porta de casa — o balcão passaria mais 30s dizendo "inacessível"
            # com tudo já no lugar.
            self._aplicar_designacao(
                mensagem.get("nomeMaquinaServidor") or "",
                mensagem.get("idEventoServidor") or "",
            )
            # O peer pode estar com o servidor no ar há horas: para quem
            # acabou de entrar na malha, o handshake é o "aviso de que o
            # servidor subiu" — e é aqui que ele passa a valer.
            if self._info_peers[id_remoto]["servidorNoAr"]:
                self.servidorNoArMudou.emit(self._info_peers[id_remoto]["nome"], True)
            # Assim que os dois se identificam, trocam a lista de arquivos
            # locais pra resolver o catch-up de quem ficou offline.
            self._enviar(socket, {"tipo": "meus_arquivos", "arquivos": self._listar_arquivos_locais()})

        elif tipo == "meus_arquivos":
            arquivos_remotos = set(mensagem.get("arquivos", []))
            # Subtrai também os arquivos com tombstone local: sem isso, um
            # peer com uma cópia desatualizada (estava offline quando o
            # arquivo foi apagado aqui) reintroduzia o arquivo de volta —
            # o catch-up só olhava "o peer tem um arquivo que eu não
            # tenho", nunca "eu já tive esse arquivo e apaguei de
            # propósito" (ver services/rede/tombstones.py).
            apagados_localmente = set(tombstones.carregar("pedidos"))
            faltando = arquivos_remotos - set(self._listar_arquivos_locais()) - apagados_localmente
            print(f"[RedeService] Catch-up: o peer tem {len(arquivos_remotos)} comanda(s); {len(faltando)} faltam aqui.")
            for nome in faltando:
                self._enviar(socket, {"tipo": "pedir_arquivo", "arquivo": nome})

        elif tipo == "pedir_arquivo":
            nome = os.path.basename(mensagem.get("arquivo", ""))
            conteudo = self._ler_arquivo_local(nome)
            if conteudo is not None:
                self._enviar(socket, {
                    "tipo": "pedido",
                    "arquivo": nome,
                    "conteudo_b64": base64.b64encode(conteudo).decode("ascii"),
                    # Vai junto pra comanda chegar do outro lado com o mesmo
                    # lugar na linha do tempo que ela tem aqui, em vez de
                    # ganhar um id novo de quem recebe — que faria as duas
                    # máquinas discordarem sobre a mesma comanda.
                    "idEvento": indicePedidos.id_evento(nome),
                    "maquina": indicePedidos.maquina(nome),
                })

        elif tipo == "pedido":
            # Resposta direta ao catch-up pedido em "pedir_arquivo" — não
            # passa pelo barramento de eventos: não é um anúncio pra malha
            # inteira, é a resposta a UM pedido específico de UMA máquina
            # que acabou de reconectar e está preenchendo o que perdeu.
            self._emitir_pedido_recebido(
                mensagem.get("arquivo", ""),
                mensagem.get("conteudo_b64", ""),
                mensagem.get("idEvento", ""),
                mensagem.get("maquina", ""),
            )

        elif tipo == "evento":
            self._eventos.receber(mensagem, socket)

        elif tipo == "status_impressora":
            id_remoto = self._id_do_socket(socket)
            if id_remoto is not None and id_remoto in self._info_peers:
                self._info_peers[id_remoto]["temImpressora"] = bool(mensagem.get("temImpressora"))
                self._info_peers[id_remoto]["infoImpressora"] = mensagem.get("infoImpressora")
                self._recalcular_maquina_impressora()

        elif tipo == "servidor_requisicao":
            # Esta máquina hospeda o ppgs_server e um peer quer falar com ele.
            # O peer já provou ter a chave da malha (senão esta mensagem nem
            # teria sido aberta), que é justamente a condição de acesso.
            id_req = mensagem.get("id_req", "")
            if not id_req:
                return
            id_remetente = self._id_do_socket(socket)
            if id_remetente is None:
                return
            try:
                corpo = base64.b64decode(mensagem.get("corpo_b64") or "")
            except ValueError:
                return
            self._encaminhar_local(
                id_req,
                mensagem.get("metodo", "GET"),
                mensagem.get("caminho", "/"),
                corpo,
                # A resposta pode chegar de outra thread (o cliente HTTP do
                # encaminhador é assíncrono), e escrever num QTcpSocket só é
                # seguro na thread que o criou — daí o sinal, entregue pelo
                # Qt na thread principal. Mesmo motivo de
                # _imprimirRemotoConcluido logo abaixo.
                lambda status, dados, _id=id_req, _rem=id_remetente: self._servidorRespostaLocal.emit(
                    _rem, _id, status, QByteArray(dados)
                ),
            )

        elif tipo == "servidor_resposta":
            id_req = mensagem.get("id_req", "")
            job = self._jobs_servidor.pop(id_req, None)
            if job is None or job["concluido"]:
                return
            job["concluido"] = True
            job["timer"].stop()
            job["timer"].deleteLater()
            try:
                corpo = base64.b64decode(mensagem.get("corpo_b64") or "")
            except ValueError:
                corpo = b""
            self.respostaServidor.emit(id_req, int(mensagem.get("status") or 0), QByteArray(corpo))

        elif tipo == "servidor_status":
            # A máquina hospedeira avisando que o ppgs_server dela acabou de
            # subir (ou de sair do ar). Não passa pelo barramento de eventos
            # de propósito: isto não é um dado a guardar e reconciliar, é
            # estado de um processo que só vale enquanto aquela máquina está
            # conectada — exatamente o caso do "status_impressora" acima.
            id_remoto = self._id_do_socket(socket)
            if id_remoto is None or id_remoto not in self._info_peers:
                return
            no_ar = bool(mensagem.get("noAr"))
            self._info_peers[id_remoto]["servidorNoAr"] = no_ar
            nome_peer = self._info_peers[id_remoto].get("nome") or ""
            print(f"[RedeService] '{nome_peer}' avisou que o servidor central "
                  f"{'subiu' if no_ar else 'saiu do ar'} lá.")
            self.servidorNoArMudou.emit(nome_peer, no_ar)

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

        elif tipo == "reconciliar_resumo":
            self._ao_receber_reconciliar_resumo(socket, mensagem.get("dominios") or {})

        elif tipo == "reconciliar_pedir":
            self._ao_receber_reconciliar_pedir(socket, mensagem.get("dominio", ""), mensagem.get("chaves") or [])

        elif tipo == "reconciliar_dados":
            self._ao_receber_reconciliar_dados(mensagem.get("dominio", ""), mensagem.get("itens") or {})

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

    def _emitir_pedido_recebido(self, nome_arquivo, conteudo_b64, id_evento="", maquina=""):
        if not nome_arquivo or not conteudo_b64:
            return
        try:
            conteudo = base64.b64decode(conteudo_b64)
        except ValueError:
            return
        self.pedidoRecebido.emit(nome_arquivo, QByteArray(conteudo), id_evento, maquina)

    def _ao_receber_evento_pedido_novo(self, payload):
        payload = payload or {}
        self._emitir_pedido_recebido(
            payload.get("arquivo", ""),
            payload.get("conteudo_b64", ""),
            payload.get("idEvento", ""),
            payload.get("maquina", ""),
        )

    def _ao_receber_evento_pedido_apagado(self, payload):
        payload = payload or {}
        nome = payload.get("arquivo", "")
        if nome:
            self.pedidoRemovidoRemoto.emit(nome, payload.get("idEvento", ""))

    def _ao_receber_evento_comanda_numerada(self, payload):
        """Aprende reservas de número feitas em outra máquina. É este caminho
        — não a anti-entropy, que só roda a cada 2 min — que faz a próxima
        comanda lançada AQUI continuar a sequência da malha em vez de repetir
        o número que o peer acabou de usar.

        O payload carrega um MAPA (`{"data", "reservas"}`), e não uma reserva
        avulsa, pra este mesmo evento servir ao anúncio normal (mapa de um
        elemento) e ao catch-up de _ao_peers_mudarem_sequencia (o dia inteiro
        numa mensagem só, em vez de uma por número reservado)."""
        payload = payload or {}
        sequenciaComandas.mesclar_dia(payload.get("data", ""), payload.get("reservas") or {})

    def _ao_peers_mudarem_sequencia(self, quantidade):
        """Quando um peer NOVO entra na malha (a quantidade aumentou, não só
        mudou), republica as reservas de número que esta máquina conhece de
        hoje — pega carona no fan-out do próprio gossip pra o
        recém-chegado ficar sabendo do estado atual sem esperar o primeiro
        ciclo de anti-entropy. Sem isto, uma máquina aberta no começo do
        expediente lançaria as primeiras comandas numerando a partir do 1,
        repetindo o que as outras já imprimiram (ver
        SalaoController._ao_peers_mudarem, mesmo padrão)."""
        aumentou = quantidade > self._ultima_quantidade_peers
        self._ultima_quantidade_peers = quantidade
        if not aumentou:
            return

        # Só HOJE: o número reinicia a cada dia, então uma reserva de ontem
        # não muda o próximo número de ninguém. A anti-entropy cobre os dias
        # anteriores, que só interessam pra conferência.
        hoje = datetime.now().strftime("%Y-%m-%d")
        reservas = sequenciaComandas.dia(hoje)
        if reservas:
            self._eventos.publicar(_EVENTO_COMANDA_NUMERADA, {"data": hoje, "reservas": reservas})

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

    # ---------- Anti-entropy (reconciliação periódica) ----------

    def registrarDominioSincronizado(self, nome_dominio: str, resumo, obter, aplicar, apagar=None, comparar=None):
        """Inscreve um domínio de estado (pedidos, mesas, cardápio,
        fechamento...) na camada de anti-entropy periódica — a rede de
        segurança que corrige o que o gossip (BarramentoEventos) perdeu
        porque uma máquina estava offline no momento de um evento, ou uma
        mensagem se perdeu no meio de uma conexão contínua. Gossip continua
        sendo o caminho rápido pra quando todo mundo está online ao mesmo
        tempo; esta camada só entra em ação quando ele já deveria ter
        sincronizado algo e não sincronizou. Espelha registrarEvento/
        publicarEvento: quem chama não precisa saber nada de sockets, só
        descrever o próprio estado.

        - `resumo()` -> {"itens": {chave: versao}, "apagados": {chave:
          isoApagadoEm}} — chamado a cada ciclo (ver
          _disparar_reconciliacao); "versao" pode ser um hash de conteúdo
          ou qualquer string que mude quando o item muda. "apagados" pode
          ser omitido (ou {}) em domínios sem exclusão.
        - `obter(chave)` -> payload serializável em JSON pra mandar a um
          peer que pediu aquela chave, ou None se ela não existir mais
          (corrida entre o resumo ter sido montado e o pedido chegar).
        - `aplicar(chave, payload)` -> grava localmente o que um peer
          mandou.
        - `apagar(chave)` -> aplica uma exclusão aprendida de um peer.
          None (padrão) em domínios sem exclusão — cardápio e fechamento
          nunca apagam, só reescrevem.
        - `comparar(chave, versao_local, versao_peer)` -> True se o item do
          peer deve ser puxado. None (padrão) usa `versao_local !=
          versao_peer`, que é "a versão do peer sempre ganha da minha se for
          diferente" — a política certa pra cardápio e fechamento, onde o
          próprio payload carrega um idEvento e quem aplica arbitra o
          conflito (ver CardapioController._ao_receber_cardapio_remoto).
          Comandas precisam de política própria: elas são imutáveis e nunca
          devem ser sobrescritas, então o domínio "pedidos" só puxa o que
          não existe aqui e registra o resto como conflito, pra decisão
          manual (ver ConsultaController._comparar_pedido_reconciliacao)."""
        self._dominios_sincronizados[nome_dominio] = {
            "resumo": resumo,
            "obter": obter,
            "aplicar": aplicar,
            "apagar": apagar,
            "comparar": comparar,
        }

    def _disparar_reconciliacao(self):
        """Um ciclo de anti-entropy: monta o resumo atual de cada domínio
        registrado e manda pra cada peer conectado agora. Cada máquina
        dispara isso sozinha e periodicamente — não é um protocolo de
        pergunta/resposta com estado, então não precisa de nenhuma
        coordenação entre as máquinas: a convergência nos dois sentidos
        acontece naturalmente em no máximo ~2 ciclos."""
        tombstones.purgar_antigos()

        if not self._peers or not self._dominios_sincronizados:
            return

        dominios_msg = {}
        for nome, dominio in self._dominios_sincronizados.items():
            try:
                dominios_msg[nome] = dominio["resumo"]()
            except Exception as erro:
                print(f"[RedeService] Falha ao montar resumo de '{nome}' para reconciliação: {erro}")

        if not dominios_msg:
            return

        mensagem = {"tipo": "reconciliar_resumo", "dominios": dominios_msg}
        for socket in self._peers.values():
            self._enviar(socket, mensagem)

    def _ao_receber_reconciliar_resumo(self, socket: QTcpSocket, dominios_recebidos: dict):
        """Compara o resumo recebido de um peer com o estado local de cada
        domínio: aplica direto qualquer exclusão nova que o peer conheça
        (ver tombstones.mesclar) e pede (reconciliar_pedir) qualquer item
        que esteja faltando ou desatualizado localmente — exceto o que já
        tem tombstone aqui, pra não reintroduzir algo apagado de
        propósito."""
        for nome, resumo_peer in dominios_recebidos.items():
            dominio = self._dominios_sincronizados.get(nome)
            if dominio is None:
                continue

            resumo_peer = resumo_peer or {}
            apagados_peer = resumo_peer.get("apagados") or {}
            if apagados_peer and dominio["apagar"] is not None:
                novos = tombstones.mesclar(nome, apagados_peer)
                for chave in novos:
                    try:
                        dominio["apagar"](chave)
                    except Exception as erro:
                        print(f"[RedeService] Falha ao aplicar exclusão de '{nome}'/{chave} vinda de reconciliação: {erro}")
                if novos:
                    print(f"[RedeService] Reconciliação: {len(novos)} exclusão(ões) de '{nome}' aprendidas de um peer.")

            itens_peer = resumo_peer.get("itens") or {}
            if not itens_peer:
                continue

            tombstones_locais = tombstones.carregar(nome) if dominio["apagar"] is not None else {}
            try:
                itens_locais = (dominio["resumo"]() or {}).get("itens") or {}
            except Exception as erro:
                print(f"[RedeService] Falha ao montar resumo local de '{nome}' para comparação: {erro}")
                continue

            comparar = dominio["comparar"] or (lambda _chave, versao_local, versao_peer: versao_local != versao_peer)
            faltando = []
            for chave, versao in itens_peer.items():
                if chave in tombstones_locais:
                    continue
                try:
                    if comparar(chave, itens_locais.get(chave), versao):
                        faltando.append(chave)
                except Exception as erro:
                    print(f"[RedeService] Falha ao comparar '{nome}'/{chave} na reconciliação: {erro}")

            if faltando:
                print(f"[RedeService] Reconciliação: pedindo {len(faltando)} item(ns) de '{nome}' a um peer.")
                self._enviar(socket, {"tipo": "reconciliar_pedir", "dominio": nome, "chaves": faltando})

    def _ao_receber_reconciliar_pedir(self, socket: QTcpSocket, nome_dominio: str, chaves: list):
        dominio = self._dominios_sincronizados.get(nome_dominio)
        if dominio is None or not chaves:
            return

        itens = {}
        for chave in chaves:
            try:
                payload = dominio["obter"](chave)
            except Exception as erro:
                print(f"[RedeService] Falha ao obter '{nome_dominio}'/{chave} para reconciliação: {erro}")
                continue
            if payload is not None:
                itens[chave] = payload

        if itens:
            self._enviar(socket, {"tipo": "reconciliar_dados", "dominio": nome_dominio, "itens": itens})

    def _ao_receber_reconciliar_dados(self, nome_dominio: str, itens: dict):
        dominio = self._dominios_sincronizados.get(nome_dominio)
        if dominio is None:
            return

        for chave, payload in itens.items():
            try:
                dominio["aplicar"](chave, payload)
            except Exception as erro:
                print(f"[RedeService] Falha ao aplicar '{nome_dominio}'/{chave} recebido por reconciliação: {erro}")

        if itens:
            print(f"[RedeService] Reconciliação: {len(itens)} item(ns) de '{nome_dominio}' recebidos de um peer.")

    # ---------- Anti-entropy do domínio "sequencia" ----------
    # Muito mais simples que o domínio "pedidos" porque as reservas de número
    # só crescem e nunca revertem (ver services/rede/sequenciaComandas.py):
    # não há o que arbitrar, nenhuma reserva pode ser sobrescrita por outra e
    # nada vira conflito manual. Sem "apagados" pelo mesmo motivo — a purga
    # por idade é local e igual em toda máquina.
    #
    # A chave é o DIA e o payload é o mapa inteiro daquele dia (algumas
    # centenas de pares no pior caso): mandar número a número faria o resumo
    # crescer com o movimento do dia, sem nenhum ganho — quem está
    # desatualizado num dia quase sempre está desatualizado em vários números
    # dele.

    def _resumo_sequencia(self):
        """Anuncia um hash por dia, só dos dias dentro da janela de retenção.
        A janela anunciada é a MESMA de sequenciaComandas.purgar_antigos de
        propósito: anunciar um dia que a purga já apagou faria as máquinas
        reintroduzi-lo uma na outra a cada ciclo, pra sempre (mesmo cuidado de
        FechamentoController._resumo_baixas)."""
        sequenciaComandas.purgar_antigos()

        itens = {}
        for data_iso, reservas in sequenciaComandas.dias_recentes().items():
            serializado = json.dumps(reservas, sort_keys=True)
            itens[data_iso] = hashlib.sha256(serializado.encode("utf-8")).hexdigest()[:16]
        return {"itens": itens}

    def _obter_sequencia_reconciliacao(self, data_iso):
        reservas = sequenciaComandas.dia(data_iso)
        return {"reservas": reservas} if reservas else None

    def _aplicar_sequencia_reconciliacao(self, data_iso, payload):
        sequenciaComandas.mesclar_dia(data_iso, (payload or {}).get("reservas") or {})

    # ---------- Impressora local e eleição da máquina que imprime ----------

    @pyqtSlot()
    @protegido()
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
        # Evita empilhar detecções concorrentes: lpstat/PowerShell (ver
        # services/printer/linux.py e windows.py) têm timeout de até 10-20s
        # cada, e numa máquina fraca a checagem inteira pode facilmente
        # passar do intervalo de 30s do próprio timer — sem essa trava, cada
        # tique perdido soma mais uma thread concorrente brigando por CPU
        # (e todas fazendo praticamente o mesmo trabalho), o tipo de coisa
        # que trava um computador fraco em vez de só deixar a informação
        # alguns segundos desatualizada.
        if self._detectando_impressora_local:
            print("[RedeService] Detecção de impressora local anterior ainda em andamento — pulando este ciclo.")
            return
        self._detectando_impressora_local = True
        threading.Thread(target=self._detectar_impressora_em_thread, daemon=True).start()

    def _detectar_impressora_em_thread(self):
        try:
            self._detectar_impressora_em_thread_interno()
        finally:
            self._detectando_impressora_local = False

    def _detectar_impressora_em_thread_interno(self):
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
    @protegido([])
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
    @protegido()
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
    @protegido({})
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

    def reservar_numero_comanda(self, data_iso: str) -> int:
        """Reserva e devolve o próximo número de comanda de `data_iso` na
        linha de eventos da malha — os dois últimos dígitos do código impresso
        (ver services/comandaSequencialService.py).

        Mesma forma de transmitir_pedido: um ponto só onde o fato nasce
        localmente e é anunciado à malha logo em seguida. E, como ele, NUNCA
        espera resposta de ninguém — a reserva é uma leitura e uma gravação em
        disco local, e o anúncio é assíncrono. Lançar uma comanda não pode
        travar porque a rede está fora.

        A consequência aceita disso: uma máquina particionada numera a partir
        do que ela conhece e pode repetir um número que outra já usou. A letra
        da máquina (letraLocal) continua no código, então o código impresso
        segue único mesmo aí — ver a docstring de
        services/rede/sequenciaComandas.py."""
        numero, id_evento = sequenciaComandas.reservar(data_iso)
        self._eventos.publicar(
            _EVENTO_COMANDA_NUMERADA,
            {"data": data_iso, "reservas": {str(numero): id_evento}},
        )
        return numero

    def transmitir_pedido(self, nome_arquivo: str, conteudo_bytes: bytes):
        """Anuncia à malha uma comanda recém-criada NESTA máquina.

        O registro no índice de eventos acontece aqui, e não em cada
        controller, porque este é o único ponto por onde os três caminhos de
        criação (Balcão, Entrega, Salão) passam — deixar a chamada em cada
        um deles significaria que um caminho novo de venda poderia nascer
        sem id de linha do tempo, e a comanda ficaria invisível pra toda a
        arbitragem de conflito sem nada indicar o porquê."""
        id_evento, maquina = indicePedidos.registrar_local(nome_arquivo)
        self._eventos.publicar("pedido_novo", {
            "arquivo": nome_arquivo,
            "conteudo_b64": base64.b64encode(conteudo_bytes).decode("ascii"),
            "idEvento": id_evento,
            "maquina": maquina,
        })

    def transmitir_exclusao(self, nome_arquivo: str, id_evento: str = ""):
        """`id_evento` é o id do tombstone gravado por quem apagou (ver
        tombstones.registrar) — vai junto pra que todas as máquinas gravem a
        exclusão com o MESMO lugar na linha do tempo, e consigam responder
        "esta comanda foi criada antes ou depois de ter sido apagada?"."""
        self._eventos.publicar("pedido_apagado", {"arquivo": nome_arquivo, "idEvento": id_evento})

    # ---------- ppgs_server encaminhado pela malha ----------
    #
    # O servidor deixou de escutar na LAN: ele só aceita conexões em
    # 127.0.0.1, na máquina que o hospeda. As outras chegam nele por aqui,
    # dentro da sessão já autenticada e cifrada da malha. Isso troca uma
    # regra que se pode contornar ("confie em quem está nesta faixa de IP")
    # por uma que não se contorna: sem a chave da malha não há sessão, e sem
    # sessão não há como sequer falar com a porta — ela não existe fora da
    # máquina hospedeira.

    @pyqtProperty(str, notify=servidorDesignadoMudou)
    def maquinaServidor(self) -> str:
        """Nome da máquina que hospeda o ppgs_server, ou "" se nenhuma foi
        escolhida ainda."""
        return self._nome_servidor

    @pyqtProperty(bool, notify=servidorDesignadoMudou)
    def servidorAqui(self) -> bool:
        return bool(self._nome_servidor) and self._nome_servidor == self._nome_local

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def maquinasDisponiveis(self) -> list:
        """Máquinas que podem hospedar o servidor: esta e os peers conectados.
        Alimenta a lista de escolha em Rede.qml."""
        maquinas = [{
            "nome": self._nome_local,
            "local": True,
            "hospeda": self.servidorAqui,
        }]
        vistos = {self._nome_local}
        for info in self._info_peers.values():
            nome = info.get("nome") or ""
            if not nome or nome in vistos:
                continue
            vistos.add(nome)
            maquinas.append({"nome": nome, "local": False, "hospeda": nome == self._nome_servidor})
        return maquinas

    @pyqtSlot(str)
    @protegido(None)
    def designarServidor(self, nome_maquina: str):
        """Escolhe (nesta máquina e em toda a malha) quem hospeda o servidor.
        Chamado pelo botão "Rodar aqui" de Rede.qml."""
        if not nome_maquina:
            return
        id_evento = relogio.novo_id()
        self._aplicar_designacao(nome_maquina, id_evento)
        self._eventos.publicar(_EVENTO_SERVIDOR_DESIGNADO, {"nome": nome_maquina, "idEvento": id_evento})
        historicoEventos.registrar_local("servidor_designado", {"nome": nome_maquina})

    def _ao_receber_evento_servidor_designado(self, payload: dict, _socket=None):
        self._aplicar_designacao(payload.get("nome") or "", payload.get("idEvento") or "")

    def _aplicar_designacao(self, nome: str, id_evento: str):
        """Última decisão vence, pelo relógio lógico. Comparar (e não apenas
        aceitar) importa: sem isso, uma designação antiga que chega atrasada
        pela reconciliação desfaria uma troca recente, e o servidor ficaria
        pingando entre duas máquinas — exatamente o ping-pong que o cache de
        fechamento já sofreu uma vez (ver architecture/EXPLAIN.md)."""
        if not nome:
            return
        # `mais_novo` devolve BOOL, não o id vencedor. Comparar o retorno com
        # `self._id_evento_servidor` (uma string) dava sempre False, então esta
        # guarda nunca guardou nada: qualquer designação que chegasse era
        # aplicada, inclusive uma antiga chegando atrasada — exatamente o
        # ping-pong que o parágrafo acima diz evitar. Passou a importar de
        # verdade agora que a designação viaja em todo handshake: sem isto, uma
        # máquina com a escolha velha empurraria a escolha velha para a malha
        # inteira a cada reconexão.
        #
        # Adota só o que for ESTRITAMENTE mais novo. idEvento vazio (registro
        # antigo, ou peer de uma versão sem este campo) conta como mais velho
        # que qualquer id real — ver relogio.mais_novo —, então não derruba uma
        # escolha datada.
        if self._id_evento_servidor and not relogio.mais_novo(id_evento, self._id_evento_servidor):
            return
        if nome == self._nome_servidor and id_evento == self._id_evento_servidor:
            return
        self._nome_servidor = nome
        self._id_evento_servidor = id_evento
        servidorDesignado.salvar(nome, id_evento)
        print(f"[RedeService] ppgs_server designado para a máquina '{nome}'.")
        self.servidorDesignadoMudou.emit()

    def registrar_encaminhador_local(self, funcao):
        """Ligado pelo ServidorLocalService desta máquina. `funcao(metodo,
        caminho, corpo, responder)` fala com o ppgs_server em 127.0.0.1 e
        chama `responder(status, corpo)` quando a resposta chegar.

        A inversão existe pra manter a fronteira que este módulo já respeita
        em todo o resto: RedeService cuida de sockets e protocolo, e não sabe
        o que é um token HTTP nem se o processo do servidor está de pé."""
        self._encaminhar_para_servidor_local = funcao

    def anunciar_servidor_no_ar(self, no_ar: bool):
        """Avisa a malha inteira que o ppgs_server DESTA máquina subiu (ou
        caiu). Chamado pelo ServidorLocalService a cada mudança de estado,
        inclusive de dentro da thread de preparo — daí o sinal interno: o
        anúncio em si só acontece na thread dona dos sockets."""
        self._servidorLocalNoAr.emit(bool(no_ar))

    def _ao_mudar_servidor_local(self, no_ar: bool):
        """Manda o aviso a todo peer conectado agora. Quem conectar depois
        recebe a mesma informação no handshake (ver _mensagem_identificar), e
        quem estiver fora do ar neste instante não perde nada: ao voltar, o
        handshake conta a situação já atualizada.

        Só age na mudança de fato: o estado do servidor é recalculado a cada
        passo do preparo, e repetir "continua no ar" a cada um deles viraria
        tráfego (e uma linha de histórico) sem informação nenhuma."""
        if no_ar == self._servidor_no_ar_local:
            return
        self._servidor_no_ar_local = no_ar

        for socket in self._peers.values():
            self._enviar(socket, {"tipo": "servidor_status", "noAr": no_ar})
        print(f"[RedeService] Avisando {len(self._peers)} peer(s): o servidor central "
              f"{'subiu' if no_ar else 'parou'} nesta máquina.")

        # Registrado só aqui, na hospedeira, e não em cada máquina que recebe
        # o aviso: subir e cair é um fato ÚNICO, do servidor — diferente de
        # "maquina_conectada", que é o ponto de vista de cada uma. A
        # reconciliação do domínio "historico" leva esta linha às demais.
        historicoEventos.registrar_local(
            "servidor_no_ar" if no_ar else "servidor_fora_do_ar",
            {"nome": self._nome_local},
        )

        # A hospedeira também é cliente do próprio servidor (ver o atalho em
        # solicitar_servidor), então o aviso vale para ela na mesma hora.
        self.servidorNoArMudou.emit(self._nome_local, no_ar)

    def solicitar_servidor(self, metodo: str, caminho: str, corpo: bytes = b"") -> str:
        """Manda uma requisição ao ppgs_server, onde quer que ele esteja, e
        devolve o id pra casar com a resposta que virá pelo sinal
        respostaServidor. Nunca bloqueia."""
        id_req = uuid.uuid4().hex

        if not self._nome_servidor:
            QTimer.singleShot(0, lambda: self.respostaServidor.emit(id_req, 0, QByteArray(b"")))
            return id_req

        if self.servidorAqui:
            # Atalho: sem volta pela malha quando o servidor é local.
            self._encaminhar_local(id_req, metodo, caminho, corpo,
                                   lambda status, dados: self.respostaServidor.emit(id_req, status, QByteArray(dados)))
            return id_req

        socket_destino = self._socket_da_maquina(self._nome_servidor)
        if socket_destino is None:
            QTimer.singleShot(0, lambda: self.respostaServidor.emit(id_req, 0, QByteArray(b"")))
            return id_req

        self._enviar(socket_destino, {
            "tipo": "servidor_requisicao",
            "id_req": id_req,
            "metodo": metodo,
            "caminho": caminho,
            "corpo_b64": base64.b64encode(corpo or b"").decode("ascii"),
        })

        timer = QTimer(self)
        timer.setSingleShot(True)
        timer.timeout.connect(lambda: self._finalizar_job_servidor(id_req))
        self._jobs_servidor[id_req] = {"timer": timer, "concluido": False}
        timer.start(_TIMEOUT_SERVIDOR_MS)
        return id_req

    def _socket_da_maquina(self, nome: str):
        for id_peer, info in self._info_peers.items():
            if info.get("nome") == nome:
                return self._peers.get(id_peer)
        return None

    def _encaminhar_local(self, id_req: str, metodo: str, caminho: str, corpo: bytes, responder):
        """Entrega ao ppgs_server desta máquina. `responder(status, bytes)`."""
        encaminhar = self._encaminhar_para_servidor_local
        if encaminhar is None:
            # Esta máquina é a designada, mas o processo do servidor ainda
            # não subiu (preparo em andamento, ou falhou). 503 e não 0: a
            # diferença importa pro cliente, que trata 0 como "não achei a
            # máquina" e 503 como "achei, mas ela não está pronta".
            responder(503, b"")
            return
        encaminhar(metodo, caminho, corpo, responder)

    def _responder_servidor_ao_peer(self, id_remetente: str, id_req: str, status: int, corpo: QByteArray):
        """Devolve ao peer o que o ppgs_server local respondeu. Procura o
        socket pelo id do peer (e não guarda o socket) porque a conexão pode
        ter caído enquanto a requisição rodava — mesmo cuidado de
        _imprimirRemotoConcluido."""
        socket = self._peers.get(id_remetente)
        if socket is None:
            return
        self._enviar(socket, {
            "tipo": "servidor_resposta",
            "id_req": id_req,
            "status": int(status),
            "corpo_b64": base64.b64encode(bytes(corpo)).decode("ascii"),
        })

    def _finalizar_job_servidor(self, id_req: str):
        job = self._jobs_servidor.pop(id_req, None)
        if job is None or job["concluido"]:
            return
        job["timer"].deleteLater()
        self.respostaServidor.emit(id_req, 0, QByteArray(b""))

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

    def _listar_arquivos_locais(self):
        pasta = caminhos.pasta_pedidos()
        if not os.path.isdir(pasta):
            # Não deveria acontecer com um caminho correto — e quando
            # acontecia (ver services/rede/caminhos.py) a lista vazia fazia
            # o catch-up falhar em silêncio. Agora avisa.
            print(f"[RedeService] Pasta de comandas não encontrada em '{pasta}' — o catch-up não tem o que oferecer aos peers.")
            return []
        return [nome for nome in os.listdir(pasta) if nome.endswith(".txt")]

    def _ler_arquivo_local(self, nome_arquivo: str):
        nome_arquivo = os.path.basename(nome_arquivo)
        caminho = os.path.join(caminhos.pasta_pedidos(), nome_arquivo)
        try:
            with open(caminho, "rb") as arquivo:
                return arquivo.read()
        except OSError:
            return None


# Singleton de módulo — mesmo padrão usado pelos demais services do projeto.
rede = RedeService()
