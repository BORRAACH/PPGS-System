"""Verifica manualmente a sincronização de Config/estilo_impressao.json
entre "máquinas" (ver services/comandaEstiloService.py) — sobe a malha,
espera ter ao menos 1 peer, e:

- Com --editar: muda um valor de teste (campo "cliente": negrito + tamanho
  99) e salva via ComandaEstiloController.salvarConfiguracaoCompleta,
  publicando o evento pra rede.
- Sem --editar: só fica observando e imprimindo o campo "cliente" a cada
  3s, esperando o valor de teste chegar da outra "máquina".

Uso (a partir da raiz do projeto, depois de docker compose build):
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name obs maquina-a \
      python3 docker/estilo_sync_teste.py
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name editor maquina-b \
      python3 docker/estilo_sync_teste.py --editar
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
    campo = config.get("campos", {}).get("cliente", {})
    print(
        f"[estilo] peers={rede.quantidadeConectados} idEvento={config.get('idEvento')!r} "
        f"cliente.negrito={campo.get('negrito')} cliente.tamanho_fonte={campo.get('tamanho_fonte')}",
        flush=True,
    )

    if editar and not ja_editou and rede.quantidadeConectados > 0:
        ja_editou = True
        novo = controller.obterConfiguracao()
        novo["campos"]["cliente"]["negrito"] = True
        novo["campos"]["cliente"]["tamanho_fonte"] = 99
        controller.salvarConfiguracaoCompleta(novo)
        print("[estilo] >>> editei e salvei (negrito=True, tamanho_fonte=99)", flush=True)


timer = QTimer()
timer.timeout.connect(tick)
timer.start(3000)
tick()
sys.exit(app.exec())
