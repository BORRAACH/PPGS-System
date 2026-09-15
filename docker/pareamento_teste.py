"""Verifica o pareamento (entrada aprovada na rede) e o cadastro de clientes
replicado entre "máquinas" — ver services/rede/seguranca.py (SessaoPareamento),
RedeService.pedirEntrada/aceitarPedido e services/rede/clientes.py.

O que só dá para conferir com máquinas de verdade, cada uma na sua pilha de
rede:

1. **Os dois lados mostram o mesmo código.** A que pede e a que aprova chegam
   ao mesmo número de 6 dígitos por conta própria.
2. **A aprovada entra na malha sem reiniciar** e recebe o que a rede já tem.
3. **O cliente salvo numa máquina chega na outra**, e no disco dela o cadastro
   não tem telefone, nome nem rua em claro.
4. **Uma máquina recusada não entra**: fica sem chave e nunca recebe o cliente.

Três papéis, um por container (a rede é criada do zero a cada execução, porque
a chave fica em Config/ e o cofre local no HOME, ambos dentro do container):

  --cria               cria a rede, aprova o PRIMEIRO pedido de entrada e
                       recusa os seguintes; espera o cliente chegar.
  --pede MAQUINA       pede para entrar na rede de MAQUINA (o hostname) e,
                       aprovada, salva um cliente de teste.
  --intruso MAQUINA    pede para entrar depois; deve ser recusada.

Uso (a partir da raiz do projeto, depois de docker compose build), cada um num
terminal, nesta ordem e com alguns segundos entre eles:

  docker compose -f docker/docker-compose.yml run --rm --no-deps --name par-a maquina-a \\
      python3 docker/pareamento_teste.py --cria
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name par-b maquina-b \\
      python3 docker/pareamento_teste.py --pede maquina-a
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name par-c maquina-c \\
      python3 docker/pareamento_teste.py --intruso maquina-a

As linhas "RESULTADO" são o que conferir; "--segundos N" encerra sozinho
(padrão 150).
"""

import os
import platform
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
# O container não tem chaveiro do sistema: a chave local vai para o arquivo,
# e é assim que o cofre deve se comportar aqui (ver services/cofreLocal.py).

from PyQt6.QtCore import QTimer
from PyQt6.QtGui import QGuiApplication

from controllers.clientesController import ClientesController
from services.rede import caminhos, rede

app = QGuiApplication(sys.argv)
rede.iniciar()
controller = ClientesController()

TELEFONE = "(12) 99999-0001"
NOME = "Cliente Teste"
RUA = "Rua do Teste Replicado"


def _argumento(opcao, padrao=""):
    try:
        return sys.argv[sys.argv.index(opcao) + 1]
    except (ValueError, IndexError):
        return padrao


papel = next((p for p in ("--cria", "--pede", "--intruso") if p in sys.argv), "")
if not papel:
    print(__doc__)
    sys.exit(2)
alvo = _argumento(papel)
limite = time.monotonic() + int(_argumento("--segundos", "150"))
estado = {"criou": False, "pedidos": 0, "pediu": False, "codigo": False, "fim": False,
          "pareada": False, "salvou": False, "recebeu": False}


def log(mensagem):
    print(f"[pareamento {platform.node()}] {mensagem}", flush=True)


def ao_pedido_de_entrada(id_remoto, nome, codigo):
    estado["pedidos"] += 1
    log(f"CODIGO_APROVA {nome} {codigo}")
    if estado["pedidos"] == 1:
        QTimer.singleShot(1500, lambda: log(f"RESULTADO aceitou {nome}: {rede.aceitarPedido(id_remoto)}"))
    else:
        QTimer.singleShot(1500, lambda: (rede.recusarPedido(id_remoto), log(f"RESULTADO recusou {nome}")))


rede.pedidoEntradaRecebido.connect(ao_pedido_de_entrada)


def ao_mudar_pareamento():
    # Pelo sinal, e não pelo tique: a aprovação chega em ~1,5 s, e o estado
    # "aguardando" pode começar e acabar entre dois tiques de 2 s.
    saida = rede.pareamentoSaida
    if saida.get("estado") == "aguardando" and not estado["codigo"]:
        estado["codigo"] = True
        log(f"CODIGO_PEDE {saida.get('nome')} {saida.get('codigo')}")


rede.pareamentoMudou.connect(ao_mudar_pareamento)


def tick():
    if time.monotonic() > limite:
        log("FIM")
        app.quit()
        return

    log(f"pareada={rede.pareada} peers={rede.quantidadeConectados} pedidos={len(rede.pedidosEntrada)} "
        f"saida={rede.pareamentoSaida.get('estado', '-')}")

    if papel == "--cria":
        if not estado["criou"]:
            estado["criou"] = True
            erro = rede.criarRede()
            log(f"RESULTADO criou_rede {'ok' if not erro else erro}")
        cliente = controller.buscarPorTelefone(TELEFONE)
        if cliente and not estado["recebeu"]:
            estado["recebeu"] = True
            log(f"RESULTADO cliente_recebido {cliente.get('nome')} / {cliente.get('rua')}")
            caminho = os.path.join(caminhos.pasta_sincronizacao(), "clientes.bin")
            with open(caminho, "rb") as arquivo:
                bruto = arquivo.read()
            em_claro = [pedaco for pedaco in (b"99999", NOME.encode(), RUA.encode()) if pedaco in bruto]
            log(f"RESULTADO disco_sem_texto_claro {not em_claro}")
        return

    if not rede.pareada:
        saida = rede.pareamentoSaida
        if not estado["pediu"]:
            candidatos = [m for m in rede.maquinasParaParear if m["nome"] == alvo]
            if candidatos:
                estado["pediu"] = True
                log(f"pedirEntrada {alvo}: {rede.pedirEntrada(candidatos[0]['id'])}")
        elif saida.get("estado") in ("recusado", "expirado", "falhou") and not estado["fim"]:
            estado["fim"] = True
            log(f"RESULTADO pedido_{saida.get('estado')} {saida.get('mensagem', '')}")
            if papel == "--intruso":
                log(f"RESULTADO intruso_sem_chave {not rede.pareada}")
                log(f"RESULTADO intruso_sem_cliente {not controller.buscarPorTelefone(TELEFONE)}")
        return

    if not estado["pareada"]:
        estado["pareada"] = True
        log("RESULTADO pareada")
    if papel == "--pede" and rede.quantidadeConectados > 0 and not estado["salvou"]:
        estado["salvou"] = True
        ok = controller.salvarCliente({
            "telefone": TELEFONE, "cliente": NOME, "endereco": RUA,
            "numero": "10", "bairro": "Centro", "observacaoGeral": "",
        })
        log(f"RESULTADO cliente_salvo {ok}")
    if papel == "--intruso":
        log("RESULTADO intruso_entrou_na_rede (NÃO devia)")


timer = QTimer()
timer.timeout.connect(tick)
timer.start(2000)
tick()
sys.exit(app.exec())
