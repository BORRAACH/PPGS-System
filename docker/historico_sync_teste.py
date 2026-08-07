"""Verifica manualmente o histórico de eventos da malha
(services/rede/historicoEventos.py) — se ele é gravado, se sincroniza entre as
"máquinas" e, principalmente, se uma máquina que entra DEPOIS recebe o que
aconteceu enquanto ela estava fora.

Esse último ponto é a razão do histórico ser um domínio sincronizado e não um
log local: sem a reconciliação, cada máquina só saberia do que passou por ela.

Uso (a partir da raiz do projeto, depois de docker compose build):

  # observador: fica imprimindo o histórico que ele enxerga
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name obs maquina-a \
      python3 docker/historico_sync_teste.py

  # gerador: publica alguns eventos de categorias diferentes
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name ger maquina-b \
      python3 docker/historico_sync_teste.py --gerar

Para o caso "entrou depois", suba o gerador primeiro, deixe-o terminar, e só
então suba o observador: ele começa com o histórico vazio e deve terminar
mostrando os eventos que a outra máquina gerou antes de ele existir.
"""

import os
import socket
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt6.QtCore import QTimer
from PyQt6.QtGui import QGuiApplication

from services.rede import historicoEventos, rede

app = QGuiApplication(sys.argv)
rede.iniciar()

gerar = "--gerar" in sys.argv
ja_gerou = False

# Uma de cada categoria, para conferir que todas atravessam a malha — e que um
# tipo desconhecido (o último) não some no caminho, já que uma máquina pode
# estar rodando uma versão mais nova do app que publique eventos que esta aqui
# ainda não conhece.
EVENTOS_DE_TESTE = [
    ("pedido_novo", {"arquivo": f"pedido_teste_{socket.gethostname()}.txt"}),
    ("cardapio_alterado", {"categoria": "pizzas"}),
    ("comanda_baixada", {"arquivo": f"baixa_teste_{socket.gethostname()}.txt"}),
    ("estilo_impressao_alterado", {}),
    ("tipo_ainda_desconhecido", {"qualquer": "coisa"}),
]


def tick():
    global ja_gerou

    eventos = historicoEventos.listar(limite=20)
    print(
        f"[historico] peers={rede.quantidadeConectados} eventos={len(eventos)}",
        flush=True,
    )
    for evento in eventos:
        print(
            f"    {evento['rotuloCategoria']:<20} {evento['rotulo']:<38} "
            f"{evento['detalhe'][:32]:<32} {evento['maquina']}",
            flush=True,
        )

    if gerar and not ja_gerou and rede.quantidadeConectados > 0:
        ja_gerou = True
        for tipo_evento, payload in EVENTOS_DE_TESTE:
            rede.publicarEvento(tipo_evento, payload)
        print(f"[historico] >>> publiquei {len(EVENTOS_DE_TESTE)} evento(s) na malha", flush=True)


timer = QTimer()
timer.timeout.connect(tick)
timer.start(3000)
tick()
sys.exit(app.exec())
