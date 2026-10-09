"""Taxa de entrega por bairro: a Entrega consulta ao preencher o bairro e grava
quando o atendente confirma a taxa. A replicação mora em
services/rede/taxasBairro.py; aqui ficam a ponte com a malha e os slots do QML."""

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services.rede import rede, taxasBairro

_EVENTO_TAXA_ALTERADA = "taxa_bairro_alterada"


class TaxasBairroController(QObject):
    # Como nos outros controllers, só para o que chega de OUTRA máquina: a
    # Entrega reaplica a taxa se o bairro dela acabou de ganhar um valor.
    taxasAtualizadas = pyqtSignal()

    def __init__(self):
        super().__init__()
        rede.registrarEvento(_EVENTO_TAXA_ALTERADA, self._ao_receber_remoto)
        rede.registrarDominioSincronizado(
            taxasBairro.DOMINIO,
            taxasBairro.resumo,
            taxasBairro.obter,
            self._aplicar_reconciliacao,
        )

    def _ao_receber_remoto(self, payload, _socket=None):
        payload = payload or {}
        if taxasBairro.aplicar_remoto(payload.get("chave", ""), payload):
            self.taxasAtualizadas.emit()

    def _aplicar_reconciliacao(self, chave, payload):
        if taxasBairro.aplicar_remoto(chave, payload):
            self.taxasAtualizadas.emit()

    @pyqtSlot(str, result=str)
    @protegido("")
    def taxaDoBairro(self, bairro):
        """"R$ 8,00" quando o bairro tem taxa guardada; "" caso contrário."""
        return taxasBairro.taxa_do_bairro(bairro)

    @pyqtSlot(str, str, result=bool)
    @protegido(False)
    def salvarTaxa(self, bairro, taxa):
        """Guarda e publica a taxa do bairro. False quando não havia o que
        guardar (bairro ou taxa vazios, ou a taxa já era essa)."""
        resultado = taxasBairro.definir(bairro, taxa)
        if resultado is None:
            return False
        chave, registro = resultado
        rede.publicarEvento(_EVENTO_TAXA_ALTERADA, dict(registro, chave=chave))
        return True
