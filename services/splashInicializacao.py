"""Janela de carregamento mostrada enquanto o sistema abre.

Por que existe. Entre o duplo clique e a janela principal aparecer há um
intervalo em que nada acontece na tela — e ele não é curto: a checagem de
atualizações sozinha leva ~1,6s (até 15s com internet ruim, ver
Config/atualizador._TIMEOUT_GIT) e roda de propósito antes de tudo, para que um
update aceito valha já nesta execução. Sem nada visível, abrir o sistema numa
máquina fraca parecia que o clique não tinha funcionado, e o usuário clicava de
novo.

O mais cedo que dá para mostrar qualquer coisa é aqui: depois de
preConfig.garantir_dependencias() (é ele que garante que o PyQt6 existe) e antes
de todo o resto. Daí este módulo criar a QApplication — a mesma que o app inteiro
vai usar depois, já que só pode existir uma por processo.

QApplication (QtWidgets) e não QGuiApplication: a janela é um widget, e o
QMessageBox que o atualizador abre para perguntar sobre a atualização também. Não
é dependência nova — o atualizador já criava uma QApplication por conta própria
quando precisava perguntar.

NÃO usa QSplashScreen, que seria o widget óbvio para isto: medido, o show() dele
leva ~1s (sempre — não é inicialização de backend, e acontece igual em offscreen
e minimal), enquanto um QWidget com a mesma flag Qt.SplashScreen aparece em ~1ms.
Uma tela de carregamento que atrasa a abertura em um segundo derrota o próprio
propósito, então aqui é um QWidget comum com o desenho num QLabel.

O desenho é feito em código, sem arquivo de imagem: o projeto não tem nenhum, e
depender de um arquivo em disco criaria um jeito novo de a abertura falhar bem no
ponto em que ainda não há como avisar o usuário direito.
"""

import sys

# Mesmas cores do resto do app (ver qml/estilo/Estilo.qml) — repetidas aqui
# porque isto roda antes de existir QML.
_FUNDO = "#ffffff"
_BORDA = "#e0e0e0"
_TITULO = "#d32f2f"
_TEXTO_SECUNDARIO = "#7f8c8d"

_LARGURA = 420
_ALTURA = 200


class _SemSplash:
    """Objeto de mentira usado quando não deu para criar a janela (sem
    ambiente gráfico, PyQt6 incompleto). Deixa quem chama seguir chamando
    mensagem()/encerrar() sem precisar checar None a cada uso — abrir o
    sistema nunca pode falhar por causa da tela de carregamento."""

    def mensagem(self, texto):
        pass

    def encerrar(self, janela=None):
        pass


class _Splash:
    def __init__(self, app, janela, rotulo_status):
        self._app = app
        self._janela = janela
        self._rotulo_status = rotulo_status

    def mensagem(self, texto):
        """Troca a linha de status e redesenha na hora.

        O processEvents() é o ponto todo: nesta fase da abertura ninguém
        chegou ao loop de eventos ainda, e sem ele a janela ficaria congelada
        no primeiro texto (ou nem apareceria) enquanto o `git fetch` roda."""
        self._rotulo_status.setText(texto)
        self._app.processEvents()

    def encerrar(self, janela=None):
        """Fecha a tela de carregamento.

        `janela` (a janela principal, uma QWindow do QML) não é usada para
        esperar nada: a QWindow já está visível quando engine.load() volta, e
        o QSplashScreen.finish() — que faria essa espera — é justamente o que
        não dá para usar aqui. Fica no parâmetro para quem chama não precisar
        saber disso."""
        self._janela.close()
        self._app.processEvents()


def _desenhar():
    from PyQt6.QtCore import Qt
    from PyQt6.QtGui import QColor, QFont, QPainter, QPixmap

    pixmap = QPixmap(_LARGURA, _ALTURA)
    pixmap.fill(QColor(_FUNDO))

    pintor = QPainter(pixmap)
    pintor.setRenderHint(QPainter.RenderHint.Antialiasing)

    pintor.setPen(QColor(_BORDA))
    pintor.drawRect(0, 0, _LARGURA - 1, _ALTURA - 1)

    fonte = QFont()
    fonte.setPointSize(20)
    fonte.setBold(True)
    pintor.setFont(fonte)
    pintor.setPen(QColor(_TITULO))
    pintor.drawText(0, 62, _LARGURA, 34, Qt.AlignmentFlag.AlignHCenter, "PPGS-SYSTEM")

    # Só a linha do título é fixa. A de baixo é o rótulo de status, escrito
    # por cima (ver iniciar()) — duas frases fixas, uma genérica e outra
    # mudando, competiam entre si sem dizer nada a mais.
    pintor.setPen(QColor(_BORDA))
    pintor.drawLine(140, 108, _LARGURA - 140, 108)

    pintor.end()
    return pixmap


def iniciar():
    """Cria a QApplication do processo e mostra a tela de carregamento.

    Devolve (app, splash). `app` é a instância que main.py deve reaproveitar —
    criar uma segunda levantaria exceção. Se qualquer coisa der errado, devolve
    (None, _SemSplash()) e a abertura segue sem tela de carregamento: ela é
    conforto, não requisito, e o bloco de imports de main.py logo abaixo já tem
    a mensagem clara para o caso de o PyQt6 estar mesmo quebrado."""
    try:
        from PyQt6.QtCore import Qt
        from PyQt6.QtGui import QColor, QPalette
        from PyQt6.QtWidgets import QApplication, QLabel, QWidget
    except ImportError as erro:
        print(f"[splash] PyQt6 indisponível ({erro}) — abrindo sem tela de carregamento.")
        return None, _SemSplash()

    try:
        app = QApplication.instance() or QApplication(sys.argv)

        janela = QWidget()
        janela.setWindowFlags(Qt.WindowType.SplashScreen | Qt.WindowType.FramelessWindowHint)
        janela.setFixedSize(_LARGURA, _ALTURA)

        imagem = QLabel(janela)
        imagem.setPixmap(_desenhar())
        imagem.setGeometry(0, 0, _LARGURA, _ALTURA)

        rotulo_status = QLabel("Iniciando...", janela)
        rotulo_status.setAlignment(Qt.AlignmentFlag.AlignCenter)
        rotulo_status.setGeometry(0, 126, _LARGURA, 24)
        paleta = rotulo_status.palette()
        paleta.setColor(QPalette.ColorRole.WindowText, QColor(_TEXTO_SECUNDARIO))
        rotulo_status.setPalette(paleta)

        # No centro da tela: sem gerenciador de janelas para posicionar uma
        # janela sem moldura, ela cairia no canto superior esquerdo.
        tela = app.primaryScreen()
        if tela is not None:
            centro = tela.availableGeometry().center()
            janela.move(centro.x() - _LARGURA // 2, centro.y() - _ALTURA // 2)

        janela.show()
        app.processEvents()
    except Exception as erro:
        # Falhas do lado Python (tema quebrado, primaryScreen indisponível).
        # NÃO cobre "não existe ambiente gráfico": nesse caso o Qt aborta o
        # processo por conta própria, dentro do QApplication(), sem passar por
        # except nenhum. Isso já era assim antes desta tela existir — o
        # QGuiApplication que o main.py criava aborta igual, só um pouco mais
        # tarde na abertura.
        print(f"[splash] Não foi possível mostrar a tela de carregamento: {erro}")
        return None, _SemSplash()

    return app, _Splash(app, janela, rotulo_status)
