"""Os pedidos começados e não finalizados, para a faixa no topo de Balcão e
Entrega (ver services/rascunhosPedido.py e qml/components/FaixaRascunhos.qml).

Controller próprio, e não slots enfiados no BalcaoController ou no
EntregaController: a faixa é UMA só, compartilhada — a tela de Balcão mostra
também os rascunhos de Entrega e vice-versa, para o atendente ver de qualquer
lugar tudo que está pendurado. Pendurar isso num dos dois faria o outro
depender do controller de uma tela sem relação nenhuma com ele; é o mesmo
raciocínio escrito no topo de controllers/usuariosController.py.

Não há sincronização com a malha aqui, e é de propósito — ver o topo de
services/rascunhosPedido.py."""

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services import comandaTextoService as texto
from services import rascunhosPedido


def _valor_total_itens(itens):
    """Soma o valor dos itens do rascunho. Mesma conta de
    salaoController._valor_total_itens, com o mesmo valor_para_float — o total
    do card tem de bater com o que a comanda vai imprimir."""
    total = 0.0
    for item in itens or []:
        if isinstance(item, dict):
            total += texto.valor_para_float(item.get("valor", ""))
    return total


class RascunhosController(QObject):
    # Emitido quando a lista muda por algo que NÃO foi a chamada que a tela
    # acabou de fazer — hoje só a poda por idade, que acontece dentro de
    # listarRascunhos. Uma gravação feita pela tela devolve o id pelo próprio
    # slot, e ela reage ao retorno; emitir nos dois casos faria a faixa
    # recarregar duas vezes por tecla digitada.
    rascunhosAtualizados = pyqtSignal()

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarRascunhos(self):
        """Um resumo por rascunho, do mais recente para o mais antigo — só o
        que o card da faixa mostra, sem os itens inteiros. A faixa recarrega a
        cada autosave, e mandar o pedido completo de cada rascunho pela ponte
        QML a cada três segundos seria pagar caro por dados que ninguém lê ali.

        "temConteudo" vem calculado daqui porque depende de olhar os itens, que
        é justamente o que o resumo não carrega."""
        resumos = []
        for registro in rascunhosPedido.listar():
            dados = registro.get("dados") or {}
            itens = dados.get("itens") or []
            resumos.append({
                "id": registro.get("id", ""),
                "tipo": registro.get("tipo", ""),
                "cliente": dados.get("cliente", ""),
                "quantidadeItens": len([i for i in itens if isinstance(i, dict) and (i.get("pedido") or "").strip()]),
                "valorTotal": _valor_total_itens(itens),
                # Os dois: "criadoEm" é o que ORDENA a faixa (ver
                # rascunhosPedido.listar), "atualizadoEm" é o que a poda por
                # idade olha. Confundir os dois foi o que fazia a fila se
                # remexer sozinha.
                "criadoEm": registro.get("criadoEm", ""),
                "atualizadoEm": registro.get("atualizadoEm", ""),
            })
        return resumos

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
    def carregarRascunho(self, id_rascunho):
        """O rascunho inteiro, pronto para repovoar o formulário. {} quando ele
        não existe mais — apagado por outra aba desta máquina, ou podado por
        idade enquanto a tela estava aberta."""
        return rascunhosPedido.obter(id_rascunho) or {}

    @pyqtSlot("QVariantMap", result=str)
    @protegido("")
    def salvarRascunho(self, registro):
        """Grava e devolve o id (novo, se o registro veio sem um). "" quando a
        gravação falha — a tela usa o retorno para saber com que id continuar
        salvando, então um "" ali significa "tente de novo no próximo ciclo",
        não "perdeu"."""
        return rascunhosPedido.salvar(registro)

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def excluirRascunho(self, id_rascunho):
        return rascunhosPedido.apagar(id_rascunho)
