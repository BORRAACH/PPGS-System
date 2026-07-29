"""Mostra quais outras "máquinas" (containers) esta instância enxerga na
malha local, depois de dar um tempo para a descoberta na rede + handshake TCP
terminarem.

Uso: `python3 docker/listar_peers_teste.py`
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


def mostrar():
    print(f"Esta máquina: {rede.nomeLocal}")
    peers = rede.listarPeers()
    print(f"Peers conectados: {len(peers)}")
    for peer in peers:
        print(f"  - {peer['nome']} ({peer['endereco']})")
    app.quit()


# Espera mais que a descoberta + handshake puros: quando esta instância tem
# o id maior que a do peer, ela só disca depois do primeiro ciclo do timer de
# reconexão (ver RedeService._tentar_conectar_a_peer), então uma janela curta
# demais mediria "0 peers" sem que houvesse nada de errado com a malha.
QTimer.singleShot(12000, mostrar)
sys.exit(app.exec())
