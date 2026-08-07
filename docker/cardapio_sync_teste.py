"""Verifica manualmente a sincronização do cardápio entre "máquinas", em
especial das bordas e dos adicionais (data/cardapio/adicionais.json e
adicionaisLanches.json).

Esses dois arquivos passaram a ser sincronizados quando viraram categorias
editáveis pela tela de Cardápio (ver services/cardapioService.CATEGORIAS):
antes disso ninguém os anunciava à malha, então uma alteração de preço de
borda ficava só na máquina onde foi feita. Este script existe para conferir
justamente esse caminho.

Também cobre o caso de duas categorias dividirem um arquivo: bordas e
adicionais de pizza moram no mesmo adicionais.json, e salvar uma não pode
apagar a outra.

Uso (a partir da raiz do projeto, depois de docker compose build):

  # observador
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name obs maquina-a \
      python3 docker/cardapio_sync_teste.py

  # editor
  docker compose -f docker/docker-compose.yml run --rm --no-deps --name editor maquina-b \
      python3 docker/cardapio_sync_teste.py --editar
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PyQt6.QtCore import QTimer
from PyQt6.QtGui import QGuiApplication

from services.cardapioService import CardapioController, carregar
from services.rede import rede

app = QGuiApplication(sys.argv)
rede.iniciar()
controller = CardapioController()

editar = "--editar" in sys.argv
ja_editou = False

# Valores de teste, escolhidos para não se confundirem com preço de verdade.
PRECO_TESTE = "77,00"
BORDA_NOVA = "Borda de Teste"


def resumo(chave):
    itens = carregar(chave)
    return f"{len(itens)} itens" + (f" | 1º: {itens[0]['nome']}={itens[0]['valor']}" if itens else "")


def tick():
    global ja_editou

    print(
        f"[cardapio] peers={rede.quantidadeConectados}\n"
        f"    bordas de pizza      : {resumo('pizzaBordas')}\n"
        f"    adicionais de pizza  : {resumo('pizzaAdicionais')}\n"
        f"    adicionais de lanche : {resumo('lanchesAdicionais')}",
        flush=True,
    )

    if editar and not ja_editou and rede.quantidadeConectados > 0:
        ja_editou = True

        bordas = carregar("pizzaBordas")
        if bordas:
            bordas[0]["valor"] = PRECO_TESTE
        if not any(b["nome"] == BORDA_NOVA for b in bordas):
            bordas.append({"nome": BORDA_NOVA, "valor": "33,00"})
        print("[cardapio] >>> salvar bordas:", repr(controller.salvarItens("pizzaBordas", bordas)), flush=True)

        # Logo depois das bordas, de propósito: as duas categorias dividem
        # adicionais.json, e é aqui que uma sobrescrevendo a outra apareceria.
        adicionais = carregar("pizzaAdicionais")
        if adicionais:
            adicionais[0]["valor"] = PRECO_TESTE
        print("[cardapio] >>> salvar adicionais:", repr(controller.salvarItens("pizzaAdicionais", adicionais)), flush=True)

        lanches = carregar("lanchesAdicionais")
        if lanches:
            lanches[0]["valor"] = PRECO_TESTE
        print("[cardapio] >>> salvar adic. lanche:", repr(controller.salvarItens("lanchesAdicionais", lanches)), flush=True)


timer = QTimer()
timer.timeout.connect(tick)
timer.start(3000)
tick()
sys.exit(app.exec())
