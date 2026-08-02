"""Fica rodando e imprimindo a letra desta "máquina" a cada 3s — usado só
manualmente pra observar ao vivo o efeito de subir/derrubar containers em
docker-compose.yml sobre RedeService.letraLocal (ver
services/rede/redeService.py). Não é chamado por nada do app de verdade.

Uso: `docker compose -f docker/docker-compose.yml run --rm <serviço>
python3 docker/malha_loop_teste.py`
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt6.QtCore import QTimer
from PyQt6.QtGui import QGuiApplication

from services.rede import rede

app = QGuiApplication(sys.argv)
rede.iniciar()


def tick():
    print(f"[loop] {rede.nomeLocal} letra={rede.letraLocal} peers={rede.quantidadeConectados}", flush=True)


timer = QTimer()
timer.timeout.connect(tick)
timer.start(3000)
tick()
sys.exit(app.exec())
