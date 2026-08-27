"""Verifica manualmente a sincronização do cadastro de usuários entre
"máquinas" — quem pode autorizar as ações destrutivas do app (ver
services/rede/usuarios.py e controllers/usuariosController.py).

Três coisas que só dá para conferir com duas máquinas de verdade:

1. **Um usuário cadastrado numa máquina existe nas outras.** É o pedido
   original da feature.
2. **Um usuário removido NÃO ressuscita.** Se a máquina que estava desligada
   na hora da remoção voltar e empurrar o cadastro de volta, a demissão não
   pegou — e ninguém fica sabendo. É o que o tombstone existe para impedir,
   e é o teste que mais importa aqui.
3. **Duas máquinas particionadas podem cadastrar o mesmo código de dois
   dígitos.** Os dois cadastros são válidos e nenhum pode sumir: ao
   religarem, as duas precisam mostrar as duas pessoas, marcadas como
   duplicadas. Ver o comentário sobre colisão no topo de
   services/rede/usuarios.py.

Uso (a partir da raiz do projeto, depois de docker compose build):

  # observador
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name obs maquina-a \
      python3 docker/usuarios_sync_teste.py

  # cadastra uma vez, assim que enxergar alguém na malha
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name cad maquina-b \
      python3 docker/usuarios_sync_teste.py --cadastrar Ana 07

  # remove o primeiro usuário que aprender de outra máquina
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name rem maquina-b \
      python3 docker/usuarios_sync_teste.py --apagar

  # colisão: rodar nas DUAS máquinas enquanto elas não se enxergam, e só
  # então deixá-las se encontrar
  docker compose -f docker/docker-compose.yml run --rm --no-deps maquina-a \
      python3 docker/usuarios_sync_teste.py --duplicar

Roteiros que valem a pena rodar:

- *básico*: `--cadastrar Ana 07` na maquina-b, observador na maquina-a. A
  linha de Ana aparece do outro lado em segundos (gossip) ou no próximo
  ciclo de reconciliação.
- *entrou depois*: cadastre com a maquina-a sozinha, encerre, e suba a
  maquina-c do zero. Ela recebe a lista inteira pela reconciliação, sem
  ninguém ter republicado nada.
- *exclusão*: `--apagar` numa, observador na outra. Some das duas e
  continua sumido depois de dois ciclos — se voltar, o tombstone falhou.
- *colisão*: `--duplicar` nas duas máquinas isoladas e depois religue. As
  duas devem terminar mostrando DOIS usuários com o mesmo código, ambos
  marcados `duplicado`.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import platform

from PyQt6.QtCore import QTimer
from PyQt6.QtGui import QGuiApplication

from controllers.usuariosController import UsuariosController
from services.rede import rede

app = QGuiApplication(sys.argv)
rede.iniciar()
controller = UsuariosController()

# Código de teste escolhido para não se confundir com um cadastro de verdade
# — quem estiver conferindo à mão reconhece o 99 como "isto é do script".
CODIGO_DUPLICADO = "99"

cadastrar = "--cadastrar" in sys.argv
apagar = "--apagar" in sys.argv
duplicar = "--duplicar" in sys.argv
ja_agiu = False


def _argumentos_do_cadastro():
    """Nome e código depois de --cadastrar, com padrão para quem esquecer."""
    try:
        indice = sys.argv.index("--cadastrar")
        return sys.argv[indice + 1], sys.argv[indice + 2]
    except (ValueError, IndexError):
        return "Teste", "42"


def tick():
    global ja_agiu

    usuarios_conhecidos = controller.listarUsuarios()
    print(f"[usuarios] peers={rede.quantidadeConectados} usuarios={len(usuarios_conhecidos)}", flush=True)
    for usuario in usuarios_conhecidos:
        marca = "  <-- CÓDIGO DUPLICADO" if usuario.get("duplicado") else ""
        print(f"    {usuario.get('codigo', '??')} | {usuario.get('nome', '')} | {usuario.get('id', '')}{marca}", flush=True)

    if ja_agiu:
        return

    # --duplicar não espera peer nenhum: o teste de colisão depende justamente
    # de as duas máquinas cadastrarem SEM se enxergarem.
    if duplicar:
        ja_agiu = True
        nome = f"Fulano de {platform.node()}"
        print("[usuarios] >>> cadastrar duplicado:", repr(controller.cadastrarUsuario(nome, CODIGO_DUPLICADO)), flush=True)
        return

    if rede.quantidadeConectados == 0:
        return

    if cadastrar:
        ja_agiu = True
        nome, codigo = _argumentos_do_cadastro()
        print("[usuarios] >>> cadastrar:", repr(controller.cadastrarUsuario(nome, codigo)), flush=True)
        return

    if apagar and usuarios_conhecidos:
        ja_agiu = True
        alvo = usuarios_conhecidos[0]
        print(f"[usuarios] >>> apagar {alvo.get('nome')} ({alvo.get('codigo')}):",
              repr(controller.excluirUsuario(alvo["id"])), flush=True)


timer = QTimer()
timer.timeout.connect(tick)
timer.start(3000)
tick()
sys.exit(app.exec())
