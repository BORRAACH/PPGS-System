"""Verifica o aviso direto de que o ppgs_server subiu (ou caiu) numa das
máquinas — ver RedeService.anunciar_servidor_no_ar / servidorNoArMudou.

O que se está conferindo é o tempo: antes deste aviso, um terminal só
descobria que o servidor central voltou no próximo tique de 30s da
verificação periódica (services/pizzeriaServerService.py), e nesse intervalo
a Entrega ficava sem autofill de endereço com o servidor já de pé. Aqui o
aviso deve chegar no MESMO instante em que a hospedeira anuncia.

Três situações, todas cobertas por este script:

  1. o peer já está conectado quando o servidor sobe   -> recebe o aviso;
  2. o peer entra na malha DEPOIS                      -> aprende no handshake
     (ver "servidorNoAr" em RedeService._mensagem_identificar);
  3. o servidor cai                                    -> o aviso contrário.

Uso (a partir da raiz do projeto, depois de docker compose build):

  # ouvinte: fica esperando os avisos
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name ouv maquina-a \
      python3 docker/servidor_aviso_teste.py

  # hospedeira: finge que o servidor subiu e, depois, que caiu
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name hosp maquina-b \
      python3 docker/servidor_aviso_teste.py --hospedeira

Para o caso 2, suba a hospedeira primeiro e só depois o ouvinte: ele começa
sem saber de nada e deve anunciar o servidor já no primeiro segundo, sem que
a hospedeira tenha repetido o aviso.

Note que este script NÃO sobe o ppgs_server de verdade (isso é papel de
services/servidor/servidorLocal.py, que precisa do repositório e do binário):
ele chama o mesmo ponto de entrada que o servidor real chama ao mudar de
estado, que é o que esta parte da malha enxerga.
"""

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt6.QtCore import QTimer
from PyQt6.QtGui import QGuiApplication

from services.rede import rede

INICIO = time.monotonic()


def registrar(texto):
    print(f"[{time.monotonic() - INICIO:6.1f}s] {texto}", flush=True)


app = QGuiApplication(sys.argv)
rede.iniciar()
rede.servidorNoArMudou.connect(
    lambda maquina, no_ar: registrar(
        f"AVISO: o servidor central {'subiu' if no_ar else 'saiu do ar'} em '{maquina}'."
    )
)

if "--hospedeira" in sys.argv:
    # A janela antes do primeiro anúncio é a mesma do listar_peers_teste.py, e
    # pelo mesmo motivo: descoberta na rede + handshake, mais o ciclo do timer
    # de reconexão que libera o lado de id maior a discar.
    QTimer.singleShot(14000, lambda: (
        registrar("anunciando que o servidor subiu nesta máquina"),
        rede.anunciar_servidor_no_ar(True),
    ))
    # Repetido de propósito: "continua no ar" não é novidade nenhuma e não
    # pode virar tráfego — nada deve aparecer do outro lado.
    QTimer.singleShot(18000, lambda: (
        registrar("repetindo o mesmo anúncio (o outro lado não deve ver nada)"),
        rede.anunciar_servidor_no_ar(True),
    ))
    QTimer.singleShot(30000, lambda: (
        registrar("anunciando que o servidor caiu"),
        rede.anunciar_servidor_no_ar(False),
    ))
    QTimer.singleShot(36000, app.quit)
else:
    def tique():
        registrar(f"esperando... peers={rede.quantidadeConectados}")

    temporizador = QTimer()
    temporizador.timeout.connect(tique)
    temporizador.start(5000)
    QTimer.singleShot(45000, app.quit)

sys.exit(app.exec())
