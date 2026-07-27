"""Simula apagar a comanda mais recente desta "máquina" (container), usando
o ConsultaController de verdade — o mesmo caminho que Consulta.qml chama ao
clicar em "Apagar". Serve para testar a propagação de exclusão (tombstone +
gossip "pedido_apagado" + reconciliação periódica, ver
services/rede/tombstones.py).

Uso (de dentro de um container do docker-compose.yml, com o app já rodando
nele): `python3 docker/apagar_pedido_teste.py`

Mesmo padrão de tempo/processo de gerar_pedido_teste.py (ver lá) — roda seu
próprio RedeService à parte do main.py já em execução no container.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt6.QtCore import QTimer
from PyQt6.QtGui import QGuiApplication

from controllers.consultaController import ConsultaController
from services.rede import rede

app = QGuiApplication(sys.argv)
rede.iniciar()
controller = ConsultaController()


def apagar_mais_recente():
    comandas = controller.listarComandas()
    if not comandas:
        print("Nenhuma comanda encontrada para apagar.")
        return

    nome_arquivo = comandas[0]["arquivo"]
    ok = controller.apagarComanda(nome_arquivo)
    print(f"Apagando '{nome_arquivo}': {ok}")


# Mesmo raciocínio de gerar_pedido_teste.py: dá tempo da descoberta + do
# handshake terminarem antes de agir, e continua rodando mais um pouco
# depois pra garantir que o evento de exclusão realmente saiu pela rede
# antes do processo morrer.
QTimer.singleShot(3000, apagar_mais_recente)
QTimer.singleShot(6000, app.quit)
sys.exit(app.exec())
