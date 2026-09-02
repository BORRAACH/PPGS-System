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
o que fazer quando a resposta dela voltar.

TODA ESCRITA passa antes por uma fila em disco (services/rede/enviosPendentes.py)
e só sai dela quando o servidor confirma. Antes, um endereço digitado com o
servidor fora do ar não era gravado em lugar nenhum: a Entrega nem chegava a
oferecer o salvamento, e o que já estava a caminho vivia numa fila em memória
que morria junto com o app. O POST imediato daqui virou, portanto, só o caminho
rápido — o que garante a gravação é a fila, não ele."""

import json

from PyQt6.QtCore import QObject, QTimer, pyqtProperty, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services.rede import enviosPendentes
from services.rede.redeService import rede

# Mesma ordem de grandeza da checagem de impressora da malha local (ver
# _INTERVALO_CHECAGEM_IMPRESSORA_MS em services/rede/redeService.py) — dá pra
# tela de Rede.qml notar uma queda do pizzeria-server sem exagerar no
# tráfego numa rede que já tem o gossip da malha rodando.
_INTERVALO_VERIFICACAO_CONEXAO_MS = 30000

# Enquanto NÃO há conexão, a mesma checagem acontece bem mais de perto. Os dois
# estados não custam a mesma coisa nem valem a mesma coisa: confirmar pela
# milésima vez um servidor que está de pé há horas não informa nada, enquanto
# reencontrar um que acabou de voltar libera de imediato o autofill da Entrega e
# a drenagem da fila de envios. Meio minuto parado nesse segundo caso é uma
# eternidade no balcão.
_INTERVALO_VERIFICACAO_SEM_CONEXAO_MS = 5000

# Espera entre um item da fila e o próximo (ver _agendar_reenvio). Tem que ser
# confortavelmente maior que o intervalo mínimo do rate limiter do
# pizzeria-server (RATE_LIMIT_MIN_INTERVAL, 200ms por IP em src/main.rs): o
# gatilho natural do reenvio é a resposta da verificação periódica de conexão, e
# disparar o POST ali na hora significaria duas requisições do mesmo IP no mesmo
# milissegundo — o servidor recusaria a segunda com 429.
#
# Deliberadamente NÃO é 5000 nem 30000, os dois intervalos da verificação de
# conexão. Com os três valores iguais (ou múltiplos), os timers batiam juntos e o
# 429 deixava de ser azar para virar regra: o reenvio saía sempre no mesmo
# milissegundo de uma verificação, e a fila não andava nunca.
_INTERVALO_REENVIO_MS = 1500


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
        # Aviso direto da máquina hospedeira: o servidor acabou de subir (ou
        # de cair) lá — ver RedeService.servidorNoArMudou. Sem isto, um
        # servidor que sobe às 18h02 só era notado neste balcão no tique
        # seguinte de _INTERVALO_VERIFICACAO_CONEXAO_MS, e até lá a Entrega
        # ficava sem autofill de endereço com o servidor já de pé.
        rede.servidorNoArMudou.connect(self._ao_avisar_servidor)
        # None até a primeira resposta chegar — diferente de False, que já
        # afirmaria "desconectado" antes de qualquer tentativa real.
        self._conectado = None

        self._timer_reenvio = QTimer(self)
        self._timer_reenvio.setSingleShot(True)
        self._timer_reenvio.timeout.connect(self._reenviar_pendentes)

        self._timer_conexao = QTimer(self)
        self._timer_conexao.timeout.connect(self.verificarConexao)
        # Começa no ritmo apertado: até a primeira resposta, este balcão está
        # justamente no estado "não sei se há servidor" que o intervalo curto
        # existe para encurtar.
        self._timer_conexao.start(_INTERVALO_VERIFICACAO_SEM_CONEXAO_MS)
        self.verificarConexao()

        # O que sobrou da sessão anterior não precisa de gatilho próprio: a
        # verificação de conexão acima já vai chamar o reenvio assim que
        # confirmar que há servidor. Registrar em log, porém, vale — é a única
        # pista de que existe cadastro esperando para subir.
        pendentes = enviosPendentes.quantidade()
        if pendentes:
            print(f"[pizzeriaServerService] {pendentes} envio(s) pendente(s) da sessão anterior — serão reenviados quando houver servidor.")

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

    def _ao_avisar_servidor(self, _maquina, _no_ar):
        """Acata o aviso conferindo, em vez de simplesmente acreditar nele: a
        verificação percorre o caminho inteiro (malha → hospedeira →
        127.0.0.1) e é ela que dá o veredito — inclusive reenviando os
        fechamentos que ficaram pendentes enquanto o servidor esteve fora (ver
        _tratar_verificacao_conexao). Confiar no aviso e só marcar "conectado"
        anunciaria conexão para um caminho que pode não existir deste balcão
        até lá, que é o pior erro possível nesta tela.

        Não filtra pela máquina avisada de propósito: a designação e o aviso
        chegam quase juntos numa máquina que acabou de entrar na malha, e
        descartar o aviso porque a designação ainda não chegou adiaria a
        reconexão justamente no caso que ele existe para resolver. Uma
        verificação a mais custa uma requisição."""
        self.verificarConexao()

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
        if novo_estado and enviosPendentes.quantidade():
            self._agendar_reenvio()

        if novo_estado == self._conectado:
            return
        self._conectado = novo_estado
        # O ritmo da verificação acompanha o estado: apertado enquanto não há
        # servidor (é quando reencontrá-lo vale alguma coisa), folgado depois de
        # confirmado. Trocar o intervalo aqui, e não em outro lugar, é o que
        # mantém isto num ponto só — este método já é o único que decide se há
        # ou não conexão.
        self._timer_conexao.start(
            _INTERVALO_VERIFICACAO_CONEXAO_MS if novo_estado else _INTERVALO_VERIFICACAO_SEM_CONEXAO_MS
        )
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
        (cliente, telefone, endereco, numero, bairro, observacaoGeral).

        Não depende de haver servidor agora. O endereço vai primeiro para a
        fila em disco e só sai dela quando o servidor confirmar — a tela pode
        oferecer o salvamento sempre, e o caixa que clica "Salvar" com a
        hospedeira desligada não perde o cadastro do cliente."""
        digitos = _normalizar_telefone(dados.get("telefone", ""))
        if len(digitos) < 10:
            self.enderecoSalvo.emit(False, "Telefone inválido para salvar o endereço.")
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

        self._postar_enfileirado(
            enviosPendentes.chave_endereco(digitos),
            "/enderecos",
            json.dumps(payload),
            self._tratar_salvamento,
        )

    def _tratar_salvamento(self, chave, corpo_enviado, status, _corpo):
        if status != 201:
            print(f"[pizzeriaServerService] Endereço não subiu agora (HTTP {status}) — fica na fila.")
            self._agendar_reenvio()
            # `True` de propósito, e não a notificação vermelha de antes: do
            # ponto de vista de quem clicou, o endereço FOI guardado — está no
            # disco desta máquina e sobe sozinho. Pintar isso de erro ensinaria
            # o caixa a redigitar um cadastro que já existe.
            #
            # Status 0 é "não houve com quem falar"; qualquer outro (429 do rate
            # limiter, um 5xx passageiro) veio de um servidor que está lá, e
            # dizer "assim que ele voltar" ali seria mentira — a fila vai
            # resolver em segundos.
            self.enderecoSalvo.emit(True, (
                "Sem servidor agora — o endereço foi guardado e será salvo assim que ele voltar."
                if status == 0 else
                "O endereço foi guardado e será salvo no servidor em instantes."
            ))
            return

        enviosPendentes.remover(chave, corpo_enviado)
        self.enderecoSalvo.emit(True, "Endereço salvo no servidor.")

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

        self._postar_enfileirado(
            enviosPendentes.chave_fechamento(data),
            "/fechamentos",
            json.dumps(payload),
            self._tratar_envio_fechamento,
        )

    def _tratar_envio_fechamento(self, chave, corpo_enviado, status, _corpo):
        if status != 200:
            print(f"[pizzeriaServerService] Fechamento não subiu agora (HTTP {status}) — fica na fila.")
            self._agendar_reenvio()
            self.fechamentoEnviado.emit(
                False,
                "Sem servidor agora — o fechamento ficou guardado e será enviado assim que ele voltar.",
            )
            return

        enviosPendentes.remover(chave, corpo_enviado)
        # 200 com "aplicado": false significa que o servidor já tinha um
        # fechamento mais recente deste dia (outra máquina fechou depois). Pra
        # quem mandou, o resultado é o mesmo: o servidor está em dia.
        self.fechamentoEnviado.emit(True, "Fechamento enviado ao servidor central.")

    # ---------- Fila de envios (ver services/rede/enviosPendentes.py) ----------

    def _postar_enfileirado(self, chave, caminho, corpo, tratador):
        """Grava na fila e tenta subir na hora. A ordem importa: enfileirar
        DEPOIS do POST deixaria uma janela em que uma queda do app entre os dois
        perderia a escrita — exatamente o buraco que esta fila existe pra
        fechar."""
        enviosPendentes.enfileirar(chave, "POST", caminho, corpo)
        self._pedir(
            "POST",
            caminho,
            corpo.encode("utf-8"),
            lambda status, resposta: tratador(chave, corpo, status, resposta),
        )

    def _agendar_reenvio(self):
        """Marca uma nova tentativa da fila. Não faz nada se já houver uma
        marcada — o timer é único e de disparo único, então várias chamadas
        seguidas (uma por tick de conexão, uma por falha) continuam valendo uma
        tentativa só."""
        if not self._timer_reenvio.isActive():
            self._timer_reenvio.start(_INTERVALO_REENVIO_MS)

    def _reenviar_pendentes(self):
        """Manda UM item da fila. O próximo sai quando a resposta deste chegar
        (ver _tratar_reenvio), e assim por diante até a fila esvaziar.

        Um por vez, e não a fila inteira de uma vez, por causa do rate limiter
        do pizzeria-server: ele recusa com 429 duas requisições do mesmo IP em
        menos de 200ms (RATE_LIMIT_MIN_INTERVAL, src/main.rs). Disparando a fila
        em rajada, o primeiro item subia e TODOS os outros voltavam 429 —
        ficavam na fila, e a rajada seguinte repetia o mesmo resultado. Uma fila
        de dez endereços nunca chegaria ao fim.

        Reenvio é silencioso de propósito: o tratador aqui não emite
        `enderecoSalvo`/`fechamentoEnviado`. Aqueles sinais respondem a um
        gesto do usuário ("cliquei em Salvar", "fechei o caixa"), e disparar uma
        notificação minutos depois, sem ninguém ter pedido nada, encheria a tela
        de avisos sobre coisas que o caixa já esqueceu."""
        itens = enviosPendentes.itens()
        if not itens:
            return
        chave, metodo, caminho, corpo = itens[0]
        print(f"[pizzeriaServerService] Reenviando '{chave}' ({len(itens)} na fila).")
        self._pedir(
            metodo,
            caminho,
            corpo.encode("utf-8"),
            lambda status, _resposta: self._tratar_reenvio(chave, corpo, int(status)),
        )

    def _tratar_reenvio(self, chave, corpo_enviado, status):
        # Os dois sucessos possíveis das rotas enfileiradas: 201 (endereço
        # criado/atualizado) e 200 (fechamento aplicado ou preterido por um mais
        # novo — nos dois casos o servidor está em dia sobre aquele dia).
        if status in (200, 201):
            enviosPendentes.remover(chave, corpo_enviado)
            self._agendar_reenvio()
            return
        # 422 e 400 são o único caso em que insistir não adianta: o corpo está
        # errado e vai continuar errado a cada tentativa. Sair da fila aqui
        # evita um item imortal que reenvia para sempre.
        if status in (400, 422):
            print(f"[pizzeriaServerService] '{chave}' recusado pelo servidor (HTTP {status}) — descartado da fila.")
            enviosPendentes.remover(chave, corpo_enviado)
            self._agendar_reenvio()
            return
        # 429 é o servidor dizendo "devagar", não "não". Ele só acontece com o
        # servidor de pé e alcançável, então tentar de novo daqui a pouco é a
        # resposta certa — e não fecha laço nenhum, porque a fila anda a cada
        # item aceito.
        if status == 429:
            self._agendar_reenvio()
            return
        # Sobrou o que significa "não há servidor" (status 0, 5xx): NÃO reagenda
        # daqui. Quem marca a próxima tentativa é a verificação periódica de
        # conexão, e só quando ela confirma 200 (ver _tratar_verificacao_conexao).
        # Reagendar aqui fecharia um laço que, com o servidor fora do ar a noite
        # toda, tentaria milhares de vezes sem nunca poder dar certo.


# Singleton de módulo — mesmo padrão usado pelos demais services do projeto
# (ver services/rede/redeService.py:`rede = RedeService()`).
pizzeria_server = PizzeriaServerService()
