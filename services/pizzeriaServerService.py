"""Cliente do pizzeria-server (backend Rust): o autofill de endereço por
telefone usado por Entrega.qml (ver buscarPorTelefone/salvarEndereco) e o
envio do resumo do dia quando o caixa é fechado (ver enviarFechamento).

O TRANSPORTE mudou; a interface para o QML, não. Antes, cada terminal fazia
HTTP direto contra um IP fixo da LAN (`PIZZERIA_SERVER_URL`), e o servidor
escutava em 0.0.0.0 sem exigir autenticação nenhuma — qualquer aparelho no
wi-fi da pizzaria conseguia baixar a lista inteira de clientes.

Agora o servidor roda numa das máquinas do balcão, escutando só em 127.0.0.1,
e as requisições vão pela malha (RedeService.solicitar_servidor), dentro da
sessão já autenticada e cifrada entre as máquinas. Some o IP para configurar,
some a porta exposta, e "quem pode falar com o servidor" passa a ser
exatamente "quem tem a chave da malha".

Continua tudo assíncrono, só que o resultado agora chega pelo sinal
`respostaServidor` do RedeService em vez do `finished` do
QNetworkAccessManager — daí o `_pendentes`, que casa cada id de requisição com
o que fazer quando a resposta dela voltar."""

import json

from PyQt6.QtCore import QObject, QTimer, pyqtProperty, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services.rede.redeService import rede

# Mesma ordem de grandeza da checagem de impressora da malha local (ver
# _INTERVALO_CHECAGEM_IMPRESSORA_MS em services/rede/redeService.py) — dá pra
# tela de Rede.qml notar uma queda do pizzeria-server sem exagerar no
# tráfego numa rede que já tem o gossip da malha rodando.
_INTERVALO_VERIFICACAO_CONEXAO_MS = 30000

# Espera antes de reenviar um fechamento que não subiu (ver
# _agendar_reenvio). Tem que ser confortavelmente maior que o intervalo
# mínimo do rate limiter do pizzeria-server (RATE_LIMIT_MIN_INTERVAL, 200ms
# por IP em src/main.rs): o gatilho natural do reenvio é a resposta da
# verificação periódica de conexão, e disparar o POST ali na hora significaria
# duas requisições do mesmo IP no mesmo milissegundo — o servidor recusaria a
# segunda com 429 e a retentativa nunca sairia do lugar.
_INTERVALO_REENVIO_FECHAMENTO_MS = 5000


def _normalizar_telefone(telefone):
    return "".join(c for c in telefone if c.isdigit())


class PizzeriaServerService(QObject):
    # Carrega os campos do endereço salvo no servidor (id, telefone, rua,
    # numero, complemento, bairro, observacao, nome) — Entrega.qml só lê os
    # que tem campo correspondente na tela.
    enderecoEncontrado = pyqtSignal("QVariantMap")
    enderecoNaoEncontrado = pyqtSignal()
    enderecoSalvo = pyqtSignal(bool, str)
    # Emitido só quando o estado de fato muda (ver _tratar_verificacao_conexao)
    # — Rede.qml usa isso pra mostrar se este balcão está ou não enxergando o
    # ppgs_server rodando na máquina designada da malha.
    conexaoMudou = pyqtSignal(bool)
    # (ok, mensagem) do envio do resumo do dia ao fechar o caixa — Fechamento
    # .qml transforma isso na notificação da tela.
    fechamentoEnviado = pyqtSignal(bool, str)

    def __init__(self):
        super().__init__()
        # id da requisição -> função que trata a resposta. O RedeService
        # devolve tudo por um sinal só (respostaServidor), então é aqui que
        # cada resposta reencontra quem a pediu.
        self._pendentes = {}
        rede.respostaServidor.connect(self._ao_responder)
        # A máquina que hospeda pode mudar em tempo de execução (a tela Rede
        # permite trocar): quando isso acontece, o estado de conexão anterior
        # não vale mais nada.
        rede.servidorDesignadoMudou.connect(self.verificarConexao)
        # None até a primeira resposta chegar — diferente de False, que já
        # afirmaria "desconectado" antes de qualquer tentativa real.
        self._conectado = None
        # Resumos de fechamento que o servidor ainda não confirmou, por data —
        # só o mais recente de cada dia, porque é ele que predomina lá (ver
        # enviarFechamento). Fica só em memória de propósito: o caso que isto
        # cobre é "a máquina Alpine estava fora do ar por alguns minutos", não
        # "o balcão foi desligado" — nesse segundo caso o dono fecha o caixa
        # de novo, que é o gesto que reenvia tudo mesmo.
        self._fechamentos_pendentes = {}

        self._timer_reenvio = QTimer(self)
        self._timer_reenvio.setSingleShot(True)
        self._timer_reenvio.timeout.connect(self._reenviar_fechamentos_pendentes)

        self._timer_conexao = QTimer(self)
        self._timer_conexao.timeout.connect(self.verificarConexao)
        self._timer_conexao.start(_INTERVALO_VERIFICACAO_CONEXAO_MS)
        self.verificarConexao()

    @pyqtProperty(bool, notify=conexaoMudou)
    def conectado(self):
        # None (ainda não verificado) também cai aqui como False — a QML só
        # precisa de "conectado" ou "não", o estado transitório inicial não
        # tem representação própria na tela.
        return bool(self._conectado)

    @pyqtProperty(str, notify=conexaoMudou)
    def maquinaServidor(self):
        """Nome da máquina que hospeda o servidor — substitui a antiga
        `urlServidor`. Não há mais URL para mostrar nem para configurar: o
        endereço do servidor deixou de ser algo que alguém digita."""
        return rede.maquinaServidor

    # ---------- Transporte (tudo passa por aqui) ----------

    def _pedir(self, metodo, caminho, corpo=b"", tratador=None):
        """Manda uma requisição ao servidor pela malha e registra quem trata a
        resposta. Nunca bloqueia."""
        id_req = rede.solicitar_servidor(metodo, caminho, corpo)
        self._pendentes[id_req] = tratador

    def _ao_responder(self, id_req, status, corpo):
        tratador = self._pendentes.pop(id_req, None)
        if tratador is None:
            return
        # status 0 = a requisição não chegou a ser respondida (sem máquina
        # hospedeira, timeout da malha, socket caído).
        tratador(int(status), bytes(corpo))

    @pyqtSlot()
    @protegido(None)
    def verificarConexao(self):
        """Confirma que o servidor está de pé. Vai pela mesma rota de tudo o
        mais (malha → máquina hospedeira → 127.0.0.1), então ela testa o
        caminho inteiro, e não só se a máquina responde ping. Chamado pelo
        timer periódico e pelo botão "Testar agora" de Rede.qml."""
        self._pedir("GET", "/enderecos", b"", self._tratar_verificacao_conexao)

    def _tratar_verificacao_conexao(self, status, _corpo):
        # Só 200 conta como conectado, e não "qualquer status != 0" como antes.
        # A diferença importa muito: quando o servidor não está rodando, quem
        # responde é o encaminhador da máquina hospedeira, com 503 — e tratar
        # isso como sucesso fazia a tela anunciar "Servidor central conectado"
        # exatamente enquanto o autofill não funcionava, que é a pior
        # combinação possível (o usuário confia no que a tela diz e procura o
        # problema em outro lugar). 401 e 429 também não são "conectado": em
        # nenhum dos dois o endereço do cliente vai aparecer na Entrega.
        novo_estado = status == 200

        # Antes do early-return de "nada mudou": o servidor pode ter voltado
        # entre dois ticks sem que este balcão tenha notado a queda, e é a
        # confirmação de que ele está de pé que dá a deixa pra reenviar o que
        # ficou pendente.
        if novo_estado and self._fechamentos_pendentes:
            self._agendar_reenvio()

        if novo_estado == self._conectado:
            return
        self._conectado = novo_estado
        self.conexaoMudou.emit(self._conectado)

    @pyqtSlot(str)
    @protegido(None)
    def buscarPorTelefone(self, telefone):
        """Consulta o servidor por um endereço já salvo para este telefone.
        Emite enderecoEncontrado(dados) ou enderecoNaoEncontrado() quando a
        resposta chegar (a chamada em si não bloqueia)."""
        digitos = _normalizar_telefone(telefone)
        if len(digitos) < 10:
            self.enderecoNaoEncontrado.emit()
            return

        self._pedir("GET", f"/enderecos/telefone/{digitos}", b"", self._tratar_busca)

    def _tratar_busca(self, status, corpo):
        if status != 200:
            # 404 (não cadastrado) e falha de transporte levam ao mesmo lugar
            # do ponto de vista da tela: não há endereço pra preencher.
            if status not in (0, 404):
                print(f"[pizzeriaServerService] Falha ao consultar endereco: HTTP {status}")
            self.enderecoNaoEncontrado.emit()
            return

        try:
            dados = json.loads(corpo.decode("utf-8", errors="replace"))
        except json.JSONDecodeError:
            print(f"[pizzeriaServerService] Resposta invalida do servidor: {corpo[:120]!r}")
            self.enderecoNaoEncontrado.emit()
            return

        self.enderecoEncontrado.emit(dados)

    @pyqtSlot("QVariantMap")
    @protegido(None)
    def salvarEndereco(self, dados):
        """Cadastra/atualiza (upsert por telefone) o endereço no servidor.
        Espera as mesmas chaves de coletarDadosPedido() em Entrega.qml
        (cliente, telefone, endereco, numero, bairro, observacaoGeral)."""
        digitos = _normalizar_telefone(dados.get("telefone", ""))
        if len(digitos) < 10:
            self.enderecoSalvo.emit(False, "Telefone invalido para salvar o endereco.")
            return

        payload = {
            "id": None,
            "telefone": digitos,
            "rua": dados.get("endereco", ""),
            "numero": dados.get("numero", ""),
            "complemento": None,
            "bairro": dados.get("bairro", ""),
            "observacao": dados.get("observacaoGeral") or None,
            "nome": dados.get("cliente") or None,
        }

        self._pedir("POST", "/enderecos", json.dumps(payload).encode("utf-8"), self._tratar_salvamento)

    def _tratar_salvamento(self, status, _corpo):
        if status != 201:
            print(f"[pizzeriaServerService] Falha ao salvar endereco: HTTP {status}")
            self.enderecoSalvo.emit(False, "Nao foi possivel salvar o endereco no servidor.")
            return

        self.enderecoSalvo.emit(True, "Endereco salvo no servidor.")

    # ---------- Resumo do dia, enviado ao fechar o caixa ----------

    @pyqtSlot("QVariantMap")
    @protegido(None)
    def enviarFechamento(self, payload):
        """Manda pro servidor central o resumo do dia montado por
        FechamentoController._montar_payload_servidor (número de vendas,
        totais por origem/forma de pagamento e produtos vendidos).

        Reenviar o mesmo dia é normal e esperado — é o que acontece quando o
        caixa é fechado mais de uma vez. Quem decide qual versão vale é o
        servidor, comparando o "id_evento" (relógio lógico da malha, ver
        services/rede/relogio.py): o maior ganha, então um envio que chega
        fora de ordem não desfaz um fechamento posterior."""
        data = payload.get("data") or ""
        if not data:
            self.fechamentoEnviado.emit(False, "Fechamento sem data — nada enviado ao servidor.")
            return

        # Guardado ANTES de tentar: se a tentativa falhar, o retry da
        # verificação periódica de conexão já encontra o payload aqui. Como a
        # chave é a data, um segundo fechamento do mesmo dia substitui o
        # pendente do primeiro — mandar o antigo depois só desperdiçaria uma
        # requisição que o servidor descartaria pelo id_evento.
        self._fechamentos_pendentes[data] = payload
        self._postar_fechamento(payload)

    def _agendar_reenvio(self):
        """Marca uma nova tentativa dos fechamentos pendentes. Não faz nada se
        já houver uma marcada — o timer é único e de disparo único, então
        várias chamadas seguidas (uma por tick de conexão, uma por falha)
        continuam valendo uma tentativa só."""
        if not self._timer_reenvio.isActive():
            self._timer_reenvio.start(_INTERVALO_REENVIO_FECHAMENTO_MS)

    def _reenviar_fechamentos_pendentes(self):
        for payload in list(self._fechamentos_pendentes.values()):
            self._postar_fechamento(payload)

    def _postar_fechamento(self, payload):
        self._pedir(
            "POST",
            "/fechamentos",
            json.dumps(payload).encode("utf-8"),
            lambda status, corpo: self._tratar_envio_fechamento(status, payload),
        )

    def _tratar_envio_fechamento(self, status, payload):
        data = payload.get("data") or ""

        if status != 200:
            print(f"[pizzeriaServerService] Falha ao enviar fechamento de {data}: HTTP {status}")
            self._agendar_reenvio()
            self.fechamentoEnviado.emit(
                False,
                "Não foi possível enviar o fechamento ao servidor central — será reenviado automaticamente.",
            )
            return

        # Só sai da fila o payload que de fato foi confirmado: entre o post e
        # esta resposta o caixa pode ter sido fechado de novo, e aí o pendente
        # daquela data já é outro (mais novo), que ainda precisa subir.
        if self._fechamentos_pendentes.get(data) is payload:
            del self._fechamentos_pendentes[data]

        # 200 com "aplicado": false significa que o servidor já tinha um
        # fechamento mais recente deste dia (outra máquina fechou depois). Pra
        # quem mandou, o resultado é o mesmo: o servidor está em dia.
        self.fechamentoEnviado.emit(True, "Fechamento enviado ao servidor central.")


# Singleton de módulo — mesmo padrão usado pelos demais services do projeto
# (ver services/rede/redeService.py:`rede = RedeService()`).
pizzeria_server = PizzeriaServerService()
