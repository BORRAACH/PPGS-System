"""Cadastro de clientes da Entrega: busca por telefone (o autofill) e
gravação, replicados pela malha (ver services/rede/clientes.py).

Toma o lugar do cliente HTTP do ppgs_server (services/pizzeriaServerService.py,
removido). A diferença que muda a tela: a busca é LOCAL, então é síncrona —
o slot devolve o cliente na hora, sem sinal de resposta, sem fila de envio e
sem "servidor fora do ar". Quem garante que as outras máquinas também têm o
cliente é a malha, pelo gossip na gravação e pela reconciliação depois.

Sem rede (máquina ainda não pareada) não há chave de índice, e o cadastro fica
indisponível: buscar devolve vazio e salvar devolve False, e a Entrega diz ao
atendente que é preciso entrar numa rede pela tela Rede."""

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services.enderecoFormatado import formatar_endereco
from services.rede import clientes, rede

_EVENTO_CLIENTE_SALVO = "cliente_salvo"


class ClientesController(QObject):
    # Um cliente chegou de OUTRA máquina. Nenhuma tela precisa reagir hoje (a
    # Entrega busca na hora em que o telefone é digitado), mas o sinal fica
    # para quem listar clientes um dia — mesmo contrato dos outros controllers.
    clientesAtualizados = pyqtSignal()

    def __init__(self):
        super().__init__()
        rede.registrarEvento(_EVENTO_CLIENTE_SALVO, self._ao_receber_cliente_remoto)
        rede.registrarDominioSincronizado(
            clientes.DOMINIO,
            clientes.resumo,
            clientes.obter,
            self._aplicar_reconciliacao,
        )

    # ---------- Malha ----------

    def _ao_receber_cliente_remoto(self, payload, _socket=None):
        payload = payload or {}
        if clientes.aplicar_remoto(payload.get("chave", ""), payload, rede.chave_indice_clientes()):
            self.clientesAtualizados.emit()

    def _aplicar_reconciliacao(self, chave, payload):
        if clientes.aplicar_remoto(chave, payload, rede.chave_indice_clientes()):
            self.clientesAtualizados.emit()

    # ---------- Entrega ----------

    @pyqtSlot(result=bool)
    def disponivel(self):
        """O cadastro só funciona com a máquina numa rede (ver o topo)."""
        return bool(rede.chave_indice_clientes())

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
    def buscarPorTelefone(self, telefone):
        """O cliente deste telefone ({"telefone", "nome", "rua", "numero",
        "bairro", "observacao"}), ou {} quando não há cadastro — ou rede."""
        chave_indice = rede.chave_indice_clientes()
        if not chave_indice:
            return {}
        cliente = clientes.buscar(telefone, chave_indice) or {}
        if cliente.get("rua"):
            # O autofill já mostra a grafia do índice; o cadastro antigo em
            # maiúsculas é regravado formatado no próximo salvar.
            cliente["rua"], cliente["bairro"] = formatar_endereco(cliente["rua"], cliente.get("bairro"))
        return cliente

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def existe(self, telefone):
        return bool(self.buscarPorTelefone(telefone))

    @pyqtSlot("QVariantMap", result=bool)
    @protegido(False)
    def salvarCliente(self, dados):
        """Cria ou sobrescreve o cliente com os dados da comanda de Entrega
        (cliente, telefone, endereco, numero, bairro, observacaoGeral) e avisa
        a malha. False sem rede, sem telefone válido ou sem rua."""
        chave_indice = rede.chave_indice_clientes()
        if not chave_indice:
            return False
        dados = dados or {}
        rua, bairro = formatar_endereco(dados.get("endereco", ""), dados.get("bairro", ""))
        resultado = clientes.salvar({
            "telefone": dados.get("telefone", ""),
            "nome": dados.get("cliente", ""),
            "rua": rua,
            "numero": dados.get("numero", ""),
            "bairro": bairro,
            "observacao": dados.get("observacaoGeral", ""),
        }, chave_indice)
        if resultado is None:
            return False
        chave, registro = resultado
        rede.publicarEvento(_EVENTO_CLIENTE_SALVO, dict(registro, chave=chave))
        return True
