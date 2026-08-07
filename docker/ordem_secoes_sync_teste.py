"""Verifica manualmente a sincronização da ORDEM dos campos da comanda
(ordem_secoes, ver services/comandaEstiloService.py) entre "máquinas" — sobe
a malha, espera ter ao menos 1 peer, e:

- Com --editar: joga o campo "status" pra primeira posição da ordem (bem
  diferente da ordem padrão) e salva via
  ComandaEstiloController.salvarConfiguracaoCompleta, publicando o evento
  pra rede.
- Sem --editar: só fica observando e imprimindo ordem_secoes a cada 3s,
  esperando a nova ordem chegar da outra "máquina".

Uso (a partir da raiz do projeto, depois de docker compose build):
  docker compose -f docker/docker-compose.yml exec maquina-b \
      python3 docker/ordem_secoes_sync_teste.py
  docker compose -f docker/docker-compose.yml exec maquina-a \
      python3 docker/ordem_secoes_sync_teste.py --editar
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt6.QtCore import QTimer
from PyQt6.QtGui import QGuiApplication

from services.rede import rede
from services.comandaEstiloService import ComandaEstiloController

app = QGuiApplication(sys.argv)
rede.iniciar()
controller = ComandaEstiloController()

editar = "--editar" in sys.argv
ja_editou = False


def tick():
    global ja_editou
    config = controller.obterConfiguracao()
    ordem = config.get("ordem_secoes", [])
    print(
        f"[ordem_secoes] peers={rede.quantidadeConectados} idEvento={config.get('idEvento')!r} "
        f"ordem={ordem}",
        flush=True,
    )

    if editar and not ja_editou and rede.quantidadeConectados > 0:
        ja_editou = True
        novo = controller.obterConfiguracao()
        ordem_nova = list(novo.get("ordem_secoes", []))
        if "status" in ordem_nova:
            ordem_nova.remove("status")
        ordem_nova.insert(0, "status")
        novo["ordem_secoes"] = ordem_nova
        controller.salvarConfiguracaoCompleta(novo)
        print(f"[ordem_secoes] >>> editei e salvei (status na posição 0): {ordem_nova}", flush=True)


timer = QTimer()
timer.timeout.connect(tick)
timer.start(3000)
tick()
sys.exit(app.exec())
