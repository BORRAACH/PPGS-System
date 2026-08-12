"""Expõe os ícones do pacote `qtawesome` (Font Awesome, Material Design
Icons etc.) para o QML.

QtAwesome foi feito para QWidgets (`qta.icon(...)` vira um `QIcon`), então
pra usar em QML (que só entende URLs de imagem) o caminho é registrar um
`QQuickImageProvider`: o QML pede "image://qtaicon/<nome>?color=<cor>" (ver
qml/components/Icone.qml) e este provider renderiza o ícone na hora, do
tamanho e cor pedidos — sem precisar gerar arquivos PNG na mão.
"""

from collections import OrderedDict
from urllib.parse import parse_qs, urlparse

import qtawesome as qta
from PyQt6.QtGui import QPixmap
from PyQt6.QtQuick import QQuickImageProvider

_TAMANHO_PADRAO = 64

# Quantos pixmaps já rasterizados manter em memória. Ver o comentário do cache
# em requestPixmap(). O app inteiro usa algumas dezenas de ícones distintos
# (contando cada combinação de cor e tamanho), então este teto é folgado o
# bastante para nunca descartar nada em uso normal e, mesmo cheio, custa
# poucos megabytes.
_LIMITE_CACHE = 256

# QML pede o ícone no tamanho LÓGICO (ex: 14px), mas em telas com escala
# >100% (HiDPI) isso corresponde a mais pixels físicos — sem isso, o Qt
# fica esticando esse bitmap pequeno pra cobrir a tela real, borrando e
# distorcendo o ícone. Renderiza numa resolução maior (supersampling) e
# marca o devicePixelRatio correspondente, pra o Qt reduzir de volta ao
# tamanho lógico com qualidade em vez de esticar um bitmap pequeno.
_FATOR_SUPERAMOSTRAGEM = 3

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
        # Chave -> QPixmap pronto, do mais antigo para o mais recente.
        #
        # Este provider é do tipo "Pixmap", o que significa que o Qt chama
        # requestPixmap() SINCRONAMENTE na thread da interface: enquanto ele
        # não devolve, nada é desenhado. E qta.icon() não é barato — monta um
        # QIcon com um engine de fonte por chamada, e o pixmap ainda sai
        # rasterizado em 3x (ver _FATOR_SUPERAMOSTRAGEM).
        #
        # Sem cache, isso acontecia de novo a cada vez que um <Icone> era
        # criado — ou seja, a cada troca de página (que destrói e recria a tela
        # inteira, ver components/LateralBar.qml), para todos os ícones dela.
        # Numa tela como a de Fechamento são treze rasterizações em série antes
        # do primeiro pixel aparecer, toda vez. Com o cache, só a primeira
        # abertura paga; as seguintes devolvem o pixmap pronto.
        self._cache = OrderedDict()

    def requestPixmap(self, id, requestedSize):
        # "id" chega como "<nome-do-icone>?color=<cor-hex-com-%23>", ex:
        # "fa6s.house?color=%232c3e50" — nome no formato do qtawesome
        # (prefixo.nome, ver https://github.com/spyder-ide/qtawesome).
        partes = urlparse(id)
        nome = partes.path
        cor = parse_qs(partes.query).get("color", [None])[0]

        largura = requestedSize.width() if requestedSize.width() > 0 else _TAMANHO_PADRAO
        altura = requestedSize.height() if requestedSize.height() > 0 else _TAMANHO_PADRAO

        # O tamanho entra na chave junto com nome e cor: o mesmo ícone pedido
        # em 14px e em 22px são dois bitmaps diferentes, e devolver um pelo
        # outro deixaria o ícone borrado.
        chave = (nome, cor, largura, altura)
        emCache = self._cache.get(chave)
        if emCache is not None:
            # Recém-usado volta para o fim da fila, então o que for descartado
            # ao estourar o limite é sempre o ícone parado há mais tempo.
            self._cache.move_to_end(chave)
            return emCache, emCache.size()

        try:
            opcoes = [{"scale_factor": _ESCALA_GLIFO}]
            icone = qta.icon(nome, color=cor, options=opcoes) if cor else qta.icon(nome, options=opcoes)
            pixmap = icone.pixmap(largura * _FATOR_SUPERAMOSTRAGEM, altura * _FATOR_SUPERAMOSTRAGEM)
            pixmap.setDevicePixelRatio(_FATOR_SUPERAMOSTRAGEM)
        except Exception as erro:
            # Nome de ícone inválido/inexistente não pode derrubar o app —
            # mostra uma imagem transparente do tamanho pedido no lugar.
            print(f"[iconProvider] Falha ao carregar o ícone '{nome}': {erro}")
            pixmap = QPixmap(largura, altura)
            pixmap.fill(0x00000000)

        # O placeholder transparente do except também entra no cache, de
        # propósito: um nome de ícone errado é errado para sempre, e sem isto
        # ele pagaria a exceção do qtawesome (mais um print no log) a cada
        # criação de tela.
        self._cache[chave] = pixmap
        if len(self._cache) > _LIMITE_CACHE:
            self._cache.popitem(last=False)

        return pixmap, pixmap.size()
