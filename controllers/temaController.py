"""Qual tema visual está valendo nesta máquina (ver qml/estilo/Estilo.qml).

Preferência por máquina, guardada no QSettings do app (arquivo de configuração
no Linux, registro no Windows) — não vai pela malha: cada terminal pode
experimentar o tema que quiser sem mudar o das outras."""

from PyQt6.QtCore import QObject, QSettings, pyqtProperty, pyqtSignal, pyqtSlot

from Config.logConfig import protegido

TEMAS = ("forno", "secundario")
_PADRAO = "forno"
_CHAVE = "aparencia/tema"


class TemaController(QObject):
    nomeMudou = pyqtSignal()

    def __init__(self):
        super().__init__()
        valor = str(QSettings().value(_CHAVE, _PADRAO))
        self._nome = valor if valor in TEMAS else _PADRAO

    @pyqtProperty(str, notify=nomeMudou)
    def nome(self):
        return self._nome

    @pyqtSlot(str)
    @protegido()
    def definir(self, nome):
        if nome not in TEMAS or nome == self._nome:
            return
        self._nome = nome
        QSettings().setValue(_CHAVE, nome)
        self.nomeMudou.emit()
