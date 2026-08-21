"""Reserva um número de comanda nesta "máquina" (container) e mostra o
registro de reservas do dia — o mesmo caminho que
services/comandaSequencialService.gerar_codigo_pedido usa, sem precisar montar
uma comanda inteira.

Serve pra conferir que a numeração segue a linha de eventos da MALHA e não a
ordem interna de cada máquina (ver services/rede/sequenciaComandas.py):
alternando containers, os números têm que crescer 1, 2, 3... atravessando as
máquinas.

Uso (de dentro de um container do docker-compose.yml, com o app já rodando
nele): `python3 docker/sequencia_teste.py`

Roda seu próprio RedeService (o `docker compose exec` abre um processo novo,
separado do `main.py` que já está rodando como processo principal do
container) — por isso espera alguns segundos pra descobrir os peers e receber
as reservas que eles já anunciaram, e continua rodando mais um pouco depois
pra dar tempo do anúncio da própria reserva sair pela rede.
"""

import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt6.QtCore import QTimer
from PyQt6.QtGui import QGuiApplication

from services import comandaSequencialService as sequencial
from services.rede import rede, sequenciaComandas

app = QGuiApplication(sys.argv)
rede.iniciar()

hoje = datetime.now().strftime("%Y-%m-%d")


def reservar():
    print(f"Peers encontrados antes de reservar: {rede.quantidadeConectados}")
    print(f"Reservas conhecidas de {hoje} ANTES: {sorted(sequenciaComandas.dia(hoje), key=int)}")

    agora = datetime.now()
    codigo = sequencial.gerar_codigo_pedido(agora)
    print(f"Código gerado nesta máquina ({rede.nomeLocal}, letra {rede.letraLocal}): {codigo}")

    print(f"Reservas conhecidas de {hoje} DEPOIS: {sorted(sequenciaComandas.dia(hoje), key=int)}")


# Mesmos tempos de docker/gerar_pedido_teste.py, e pelo mesmo motivo: a
# descoberta + handshake TCP precisam terminar antes (senão esta máquina
# reserva sem saber o que as outras já reservaram, que é exatamente o cenário
# de partição que o teste NÃO quer medir aqui), e o processo não pode morrer
# antes do anúncio sair.
QTimer.singleShot(3000, reservar)
QTimer.singleShot(6000, app.quit)
sys.exit(app.exec())
