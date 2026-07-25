"""Expõe os ícones do pacote `qtawesome` (Font Awesome, Material Design
Icons etc.) para o QML.

QtAwesome foi feito para QWidgets (`qta.icon(...)` vira um `QIcon`), então
pra usar em QML (que só entende URLs de imagem) o caminho é registrar um
`QQuickImageProvider`: o QML pede "image://qtaicon/<nome>?color=<cor>" (ver
qml/components/Icone.qml) e este provider renderiza o ícone na hora, do
tamanho e cor pedidos — sem precisar gerar arquivos PNG na mão.
"""

from urllib.parse import parse_qs, urlparse

import qtawesome as qta
from PyQt6.QtGui import QPixmap
from PyQt6.QtQuick import QQuickImageProvider

_TAMANHO_PADRAO = 64

# O qtawesome calcula o tamanho da fonte só a partir da ALTURA do canvas
# pedido (ver iconic_font.py: draw_size = 0.875 * rect.height() * scale_factor)
# e desenha o glifo centralizado — pra ícones "deitados" (mais largos que
# altos, ex: fa6s.motorcycle, fa6s.bag-shopping) isso faz o desenho
# ultrapassar a largura do canvas e ser cortado nas bordas. Encolher um
# pouco o glifo (em vez do padrão 1.0) dá folga suficiente pra nenhum dos
# ícones usados no app cortar, mesmo no menor tamanho usado (22px).
_ESCALA_GLIFO = 0.8


class IconProvider(QQuickImageProvider):
    # QIcon.pixmap() (usado por qtawesome) precisa rodar na thread da GUI —
    # QPixmap não é thread-safe. Provedores do tipo "Image" são chamados
    # pelo Qt numa thread separada (o que crasha aqui); o tipo "Pixmap" é
    # sempre chamado na thread principal, então é o certo para este caso.
    def __init__(self):
        super().__init__(QQuickImageProvider.ImageType.Pixmap)

    def requestPixmap(self, id, requestedSize):
        # "id" chega como "<nome-do-icone>?color=<cor-hex-com-%23>", ex:
        # "fa6s.house?color=%232c3e50" — nome no formato do qtawesome
        # (prefixo.nome, ver https://github.com/spyder-ide/qtawesome).
        partes = urlparse(id)
        nome = partes.path
        cor = parse_qs(partes.query).get("color", [None])[0]

        largura = requestedSize.width() if requestedSize.width() > 0 else _TAMANHO_PADRAO
        altura = requestedSize.height() if requestedSize.height() > 0 else _TAMANHO_PADRAO

        try:
            opcoes = [{"scale_factor": _ESCALA_GLIFO}]
            icone = qta.icon(nome, color=cor, options=opcoes) if cor else qta.icon(nome, options=opcoes)
            pixmap = icone.pixmap(largura, altura)
        except Exception as erro:
            # Nome de ícone inválido/inexistente não pode derrubar o app —
            # mostra uma imagem transparente do tamanho pedido no lugar.
            print(f"[iconProvider] Falha ao carregar o ícone '{nome}': {erro}")
            pixmap = QPixmap(largura, altura)
            pixmap.fill(0x00000000)

        return pixmap, pixmap.size()
