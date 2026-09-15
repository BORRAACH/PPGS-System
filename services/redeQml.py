"""User-Agent nos pedidos de rede feitos pelo QML.

O engine QML baixa imagens (`Image { source: "https://..." }`) e atende os
XMLHttpRequest pelo próprio QNetworkAccessManager, e no QML não há como pôr
cabeçalho num Image. Sem User-Agent, o tile.openstreetmap.org responde aos
blocos do mapa (qml/pages/mapa/Maps.qml) com a imagem "Access blocked": a
política de uso dos servidores do OSM exige que a aplicação se identifique.

Esta fábrica entrega ao engine um gerenciador que acrescenta o mesmo
User-Agent das requisições feitas pelo Python (services/requisicaoHttp.py) a
todo pedido que ainda não tenha um.
"""

from PyQt6 import sip
from PyQt6.QtNetwork import QNetworkAccessManager, QNetworkRequest
from PyQt6.QtQml import QQmlNetworkAccessManagerFactory

from services.requisicaoHttp import USER_AGENT

_CABECALHO = b"User-Agent"
_VALOR = USER_AGENT.encode()

# A fábrica instalada no engine. O engine não fica dono dela, então é esta
# referência que a mantém viva enquanto o app roda.
_fabrica = None


class _GerenciadorComUserAgent(QNetworkAccessManager):
    def createRequest(self, operacao, requisicao, dados=None):
        if not requisicao.hasRawHeader(_CABECALHO):
            # A requisição chega como referência constante: quem leva o
            # cabeçalho é a cópia.
            requisicao = QNetworkRequest(requisicao)
            requisicao.setRawHeader(_CABECALHO, _VALOR)
        return super().createRequest(operacao, requisicao, dados)


class FabricaRedeQml(QQmlNetworkAccessManagerFactory):
    def __init__(self):
        super().__init__()
        # Segura o lado Python de cada gerenciador. Sem isto o PyQt o coleta
        # logo que create() retorna, e o objeto C++ que fica com o engine perde
        # o createRequest acima: os pedidos voltam a sair sem User-Agent.
        self._gerenciadores = []

    # O engine chama create() uma vez por thread que faz rede (a da interface
    # e a que carrega imagens em segundo plano), então a lista fica pequena.
    def create(self, pai):
        gerenciador = _GerenciadorComUserAgent(pai)
        # Criado pelo Python, o gerenciador seria apagado pelo Python quando a
        # lista acima sumisse, mesmo com o engine ainda usando o objeto
        # (segfault ao fechar o app). Com a posse passada ao lado C++, só o Qt
        # o destrói, junto com o pai.
        sip.transferto(gerenciador, None)
        self._gerenciadores.append(gerenciador)
        return gerenciador


def instalar(engine):
    """Liga a fábrica ao engine. Chamar antes de carregar qualquer QML."""
    global _fabrica
    _fabrica = FabricaRedeQml()
    engine.setNetworkAccessManagerFactory(_fabrica)
