"""Cliente HTTP do pizzeria-server (backend Rust separado, rodando na
máquina Alpine da pizzaria) — hoje só o autofill de endereço por telefone
usado por Entrega.qml (ver buscarPorTelefone/salvarEndereco).

As chamadas usam QNetworkAccessManager, que já é assíncrono por natureza:
get()/post() voltam na hora e o resultado chega depois pelo sinal
`finished`, entregue de volta na thread principal pelo event loop do Qt —
não precisa de threading.Thread aqui (diferente da consulta de impressora em
balcaoController.py, que É bloqueante porque chama lpstat/PowerShell)."""

import functools
import json
import os

from PyQt6.QtCore import QObject, QTimer, QUrl, pyqtProperty, pyqtSignal, pyqtSlot
from PyQt6.QtNetwork import QNetworkAccessManager, QNetworkRequest, QNetworkReply

from Config.logConfig import protegido

# Ajustável sem mexer no código: aponta pra máquina Alpine real da pizzaria
# via variável de ambiente; localhost:8080 é só o fallback de desenvolvimento.
PIZZERIA_SERVER_URL = os.environ.get("PIZZERIA_SERVER_URL", "http://localhost:8080").rstrip("/")

_CONTENT_TYPE_JSON = b"application/json"

# Mesma ordem de grandeza da checagem de impressora da malha local (ver
# _INTERVALO_CHECAGEM_IMPRESSORA_MS em services/rede/redeService.py) — dá pra
# tela de Rede.qml notar uma queda do pizzeria-server sem exagerar no
# tráfego numa rede que já tem o gossip da malha rodando.
_INTERVALO_VERIFICACAO_CONEXAO_MS = 30000
_TIMEOUT_CONEXAO_MS = 5000


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
    # servidor central (~/Documents/Program/ppgs_server) rodando na máquina
    # Alpine da pizzaria.
    conexaoMudou = pyqtSignal(bool)

    def __init__(self):
        super().__init__()
        self._gerenciador = QNetworkAccessManager(self)
        # None até a primeira resposta chegar — diferente de False, que já
        # afirmaria "desconectado" antes de qualquer tentativa real.
        self._conectado = None

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

    @pyqtProperty(str, constant=True)
    def urlServidor(self):
        return PIZZERIA_SERVER_URL

    @pyqtSlot()
    @protegido(None)
    def verificarConexao(self):
        """Dispara um GET leve na raiz do servidor só pra confirmar que ele
        está de pé — a rota não existe (routes::despachar em ppgs_server cai
        no 404 padrão), mas qualquer resposta HTTP já prova que a máquina
        Alpine está acessível e o processo está escutando. Chamado pelo timer
        periódico e pelo botão "Atualizar" de Rede.qml."""
        url = QUrl(f"{PIZZERIA_SERVER_URL}/")
        requisicao = QNetworkRequest(url)
        requisicao.setTransferTimeout(_TIMEOUT_CONEXAO_MS)
        resposta = self._gerenciador.get(requisicao)
        resposta.finished.connect(functools.partial(self._tratar_verificacao_conexao, resposta))

    def _tratar_verificacao_conexao(self, resposta):
        resposta.deleteLater()
        # Um status HTTP presente (mesmo 404/500) significa que a resposta
        # chegou de volta — o servidor está de pé. Erros de rede (recusado,
        # host inalcançável, timeout) nunca chegam a preencher este atributo.
        status = resposta.attribute(QNetworkRequest.Attribute.HttpStatusCodeAttribute)
        novo_estado = status is not None

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

        url = QUrl(f"{PIZZERIA_SERVER_URL}/enderecos/telefone/{digitos}")
        resposta = self._gerenciador.get(QNetworkRequest(url))
        resposta.finished.connect(functools.partial(self._tratar_busca, resposta))

    def _tratar_busca(self, resposta):
        resposta.deleteLater()
        status = resposta.attribute(QNetworkRequest.Attribute.HttpStatusCodeAttribute)
        corpo = bytes(resposta.readAll()).decode("utf-8", errors="replace")

        if resposta.error() != QNetworkReply.NetworkError.NoError and status != 404:
            print(f"[pizzeriaServerService] Falha ao consultar endereco: {resposta.errorString()}")
            self.enderecoNaoEncontrado.emit()
            return

        if status != 200:
            self.enderecoNaoEncontrado.emit()
            return

        try:
            dados = json.loads(corpo)
        except json.JSONDecodeError:
            print(f"[pizzeriaServerService] Resposta invalida do servidor: {corpo!r}")
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

        url = QUrl(f"{PIZZERIA_SERVER_URL}/enderecos")
        requisicao = QNetworkRequest(url)
        requisicao.setHeader(QNetworkRequest.KnownHeaders.ContentTypeHeader, _CONTENT_TYPE_JSON.decode())
        corpo = json.dumps(payload).encode("utf-8")

        resposta = self._gerenciador.post(requisicao, corpo)
        resposta.finished.connect(functools.partial(self._tratar_salvamento, resposta))

    def _tratar_salvamento(self, resposta):
        resposta.deleteLater()
        status = resposta.attribute(QNetworkRequest.Attribute.HttpStatusCodeAttribute)

        if resposta.error() != QNetworkReply.NetworkError.NoError or status != 201:
            mensagem = resposta.errorString() if resposta.error() != QNetworkReply.NetworkError.NoError else f"HTTP {status}"
            print(f"[pizzeriaServerService] Falha ao salvar endereco: {mensagem}")
            self.enderecoSalvo.emit(False, "Nao foi possivel salvar o endereco no servidor.")
            return

        self.enderecoSalvo.emit(True, "Endereco salvo no servidor.")


# Singleton de módulo — mesmo padrão usado pelos demais services do projeto
# (ver services/rede/redeService.py:`rede = RedeService()`).
pizzeria_server = PizzeriaServerService()
