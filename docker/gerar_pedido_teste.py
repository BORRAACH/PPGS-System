"""Simula alguém tirando um pedido no Balcão desta "máquina" (container),
usando o BalcaoController de verdade — o mesmo caminho que Balcao.qml chama.

Uso (de dentro de um container do docker-compose.yml, com o app já rodando
nele): `python3 docker/gerar_pedido_teste.py`

Roda seu próprio RedeService (o `docker compose exec` abre um processo novo,
separado do `main.py` que já está rodando como processo principal do
container) — por isso espera alguns segundos para descobrir os peers antes
de criar o pedido, e continua rodando mais um pouco depois para dar tempo do
envio de fato sair pela rede antes do processo terminar.
"""

import os
import socket
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt6.QtCore import QTimer
from PyQt6.QtGui import QGuiApplication

from controllers.balcaoController import BalcaoController
from services.rede import rede

app = QGuiApplication(sys.argv)
rede.iniciar()
controller = BalcaoController()


def criar_pedido():
    print(f"Peers encontrados antes de criar o pedido: {rede.quantidadeConectados}")
    ok = controller.enviarPedido({
        "cliente": f"Pedido de teste ({socket.gethostname()})",
        "itens": [{"pedido": "Pizza de Teste", "observacao": "", "valor": "10,00"}],
        "formaPagamento": "Pix",
        "troco": "",
        "statusPagamento": "NP",
    })
    print("Pedido criado:", ok)


# Dá tempo da descoberta na rede + handshake TCP terminarem antes de criar o
# pedido (senão ele só chega às outras máquinas depois, via catch-up, e não
# na hora); e continua rodando mais um pouco depois pra garantir que os
# bytes realmente saem pela rede antes do processo morrer.
QTimer.singleShot(3000, criar_pedido)
QTimer.singleShot(6000, app.quit)
sys.exit(app.exec())
