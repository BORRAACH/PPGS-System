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
    # Emitido quando o CONJUNTO de rascunhos muda — um nasceu ou foi embora —,
    # e não a cada gravação. Quem grava recebe o id pelo próprio slot e
    # recarrega a própria faixa; emitir no autosave também faria a faixa da
    # tela ativa recarregar duas vezes a cada três segundos.
    #
    # Existe por causa da faixa da OUTRA tela, e da ordem em que o StackView
    # troca de página (ver qml/components/LateralBar.qml, replace(null, ...)):
    #
    #   1. a página nova é criada     -> a faixa dela LÊ a lista
    #   2. a página velha desativa    -> só agora o rascunho dela é GRAVADO
    #   3. a página velha é destruída -> e às vezes a gravação é só aqui
    #
    # Sem este aviso, o rascunho começado no Balcão e interrompido por uma
    # troca de tela ficava gravado em disco mas fora da faixa da tela nova:
    # ele só reaparecia quando aquela página fosse criada de novo, e para quem
    # está no balcão isso é indistinguível de "o rascunho se perdeu". Quem
    # nasce depois do aviso não precisa dele — já lê a lista completa.
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
        não "perdeu".

        Avisa a malha de faixas só quando o rascunho NASCE aqui (ver
        rascunhosAtualizados). "Nasce" é medido olhando o disco, não só o id
        que veio da tela: um id que já não tem arquivo (apagado noutra tela, ou
        podado por idade enquanto o formulário estava aberto) volta a ser um
        card novo para quem está olhando a faixa."""
        id_informado = str((registro or {}).get("id") or "").strip()
        nasceu_agora = rascunhosPedido.obter(id_informado) is None

        id_rascunho = rascunhosPedido.salvar(registro)
        if id_rascunho and nasceu_agora:
            self.rascunhosAtualizados.emit()
        return id_rascunho

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def excluirRascunho(self, id_rascunho):
        """Descarta o rascunho — pelo × do card, ou porque ele virou comanda
        (ver limparFormularioPedido nas telas de Balcão e Entrega).

        Avisa pelo mesmo motivo de salvarRascunho, e o caso é o espelho dele.
        Aqui isso vale até para a faixa da PRÓPRIA tela: limparFormularioPedido
        apaga o rascunho e zera os campos, e a faixa só recarregava dentro de
        uma gravação — que a partir daí não acontece mais, porque o formulário
        vazio não tem o que gravar. O card ficava na tela apontando para um
        arquivo que já não existe, e clicar nele prendia o formulário a um id
        morto, que o autosave seguinte ressuscitava com o pedido de outra
        pessoa."""
        removido = rascunhosPedido.apagar(id_rascunho)
        if removido:
            self.rascunhosAtualizados.emit()
        return removido
