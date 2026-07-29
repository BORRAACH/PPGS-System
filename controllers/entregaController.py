import os
import uuid
from datetime import datetime

from PyQt6.QtCore import QObject, pyqtSlot

from Config.logConfig import protegido
from services import comandaEstiloService as estilo
from services import comandaSequencialService as sequencial
from services import comandaTextoService as texto
from services.rede import rede

CODEPAGE_IMPRESSORA = texto.CODEPAGE_IMPRESSORA

# Marca impressa no topo e no rodapé de uma comanda de teste (ver
# _salvarComanda) — em negrito direto via comandaEstiloService, não como um
# "campo" configurável em EstiloImpressora.qml, porque é um aviso fixo pra
# quem for tirar a comanda da impressora, não um dado do pedido.
_MARCA_COMANDA_TESTE = f"{estilo.NEGRITO_LIGA}*** COMANDA DE TESTE ***{estilo.NEGRITO_DESLIGA}"


class EntregaController(QObject):
    def __init__(self):
        super().__init__()
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.pasta_pedidos = os.path.join(base_dir, "pedidos")
        os.makedirs(self.pasta_pedidos, exist_ok=True)

    def _salvarComanda(self, dados):
        """Monta o texto da comanda, grava o .txt e propaga para a rede
        local. Não imprime nada — usado tanto por enviarPedido() quanto por
        lancarPedido(). Retorna (sucesso, conteudo_bytes); conteudo_bytes
        vem vazio quando sucesso é False.

        Se dados["teste"] vier True (comanda em branco confirmada como
        teste pelo popup de Entrega.qml), o cliente vira "Teste", o cupom
        sai marcado no topo/rodapé, e a comanda NÃO é gravada em disco nem
        propagada pela rede — não deve aparecer na Consulta. conteudo_bytes
        ainda volta preenchido, porque enviarPedido() precisa dele pra
        pedir a impressão mesmo nesse caso."""
        teste = bool(dados.get("teste", False))
        cliente = "Teste" if teste else dados.get("cliente", "")
        telefone = dados.get("telefone", "")
        endereco = dados.get("endereco", "")
        numero = dados.get("numero", "")
        bairro = dados.get("bairro", "")
        observacaoGeral = dados.get("observacaoGeral", "")
        itens = dados.get("itens", [])
        forma_pagamento = dados.get("formaPagamento", "")
        troco = dados.get("troco", "")
        status_pagamento = dados.get("statusPagamento", "NP")
        taxa_entrega = dados.get("taxaEntrega", "")

        grupos = texto.montar_grupos(itens)
        valor_total = sum(texto.valor_para_float(item.get("valor", "")) for item in itens) + texto.valor_para_float(taxa_entrega)

        agora = datetime.now()
        # Sufixo aleatório curto: com várias máquinas gravando pedidos ao
        # mesmo tempo na rede local, dois pedidos no mesmo segundo teriam o
        # mesmo nome de arquivo e um sobrescreveria o outro ao sincronizar.
        nome_arquivo = f"entrega_{agora.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}.txt"
        caminho_arquivo = os.path.join(self.pasta_pedidos, nome_arquivo)

        endereco_completo = f"{endereco}, {numero}" if numero else endereco

        linhas_arquivo = []
        if teste:
            linhas_arquivo.append(_MARCA_COMANDA_TESTE)
            linhas_arquivo.extend(estilo.linhas_espacamento_secoes())
        else:
            # Só consome um número da sequência diária pra comanda de
            # verdade — uma comanda de teste não deve "furar" a numeração
            # que o dono acompanha (ver docstring desta função).
            codigo_pedido = sequencial.gerar_codigo_pedido(agora)
            linhas_arquivo.append(f"ID: {estilo.formatar_campo(codigo_pedido, 'id_pedido')}")
        linhas_arquivo.extend([
            f"Cliente: {estilo.formatar_campo(cliente, 'cliente')}",
            f"Telefone: {estilo.formatar_campo(telefone, 'telefone')}",
            f"Endereço: {estilo.formatar_campo(endereco_completo, 'endereco')}",
            f"Bairro: {estilo.formatar_campo(bairro, 'bairro')}",
            f"Data: {estilo.formatar_campo(agora.strftime('%d/%m/%Y %H:%M:%S'), 'data')}",
            *estilo.linhas_espacamento_secoes(),
            "-" * 40,
            *estilo.linhas_espacamento_secoes(),
            *texto.formatar_tabela(grupos),
            *estilo.linhas_espacamento_secoes(),
            "-" * 40,
            *estilo.linhas_espacamento_secoes(),
        ])
        if observacaoGeral:
            linhas_arquivo.append(f"Observação: {estilo.formatar_campo(observacaoGeral, 'observacao_entrega')}")
            linhas_arquivo.extend(estilo.linhas_espacamento_secoes())
            linhas_arquivo.append("-" * 40)
            linhas_arquivo.extend(estilo.linhas_espacamento_secoes())
        linhas_arquivo.append(f"Forma de pagamento: {estilo.formatar_campo(forma_pagamento, 'forma_pagamento')}")
        if forma_pagamento == "Dinheiro" and troco:
            linhas_arquivo.append(f"Troco para: {estilo.formatar_campo(troco, 'troco_para')}")
        linhas_arquivo.append(f"Status: {estilo.formatar_campo(status_pagamento, 'status')}")
        linhas_arquivo.extend(estilo.linhas_espacamento_secoes())
        linhas_arquivo.append("-" * 40)
        linhas_arquivo.extend(estilo.linhas_espacamento_secoes())
        if taxa_entrega:
            linhas_arquivo.append(f"Taxa de entrega: {estilo.formatar_campo(taxa_entrega, 'taxa_entrega')}")
        valor_total_formatado = f"R$ {valor_total:.2f}".replace(".", ",")
        linhas_arquivo.append(f"Valor do pedido: {estilo.formatar_campo(valor_total_formatado, 'valor_total')}")
        if forma_pagamento == "Dinheiro" and troco:
            troco_a_dar = texto.valor_para_float(troco) - valor_total
            troco_a_dar_formatado = f"R$ {troco_a_dar:.2f}".replace(".", ",")
            linhas_arquivo.append(f"Troco a dar: {estilo.formatar_campo(troco_a_dar_formatado, 'troco_a_dar')}")
        if teste:
            linhas_arquivo.extend(estilo.linhas_espacamento_secoes())
            linhas_arquivo.append(_MARCA_COMANDA_TESTE)

        conteudo = "\n".join(linhas_arquivo) + "\n"
        # Modo binário: o texto vira bytes em cp850 e os códigos ESC/POS de
        # negrito são preservados como estão, sem reinterpretação de encoding.
        conteudo_bytes = conteudo.encode(CODEPAGE_IMPRESSORA, errors="replace")

        if teste:
            # Comanda de teste: não grava em disco nem propaga pela rede —
            # não deve sobrar rastro nem aparecer na Consulta. conteudo_bytes
            # já basta pra enviarPedido() pedir a impressão.
            print("Comanda de teste (em branco) — não salva, não propagada.")
            return True, conteudo_bytes

        try:
            with open(caminho_arquivo, "wb") as arquivo:
                arquivo.write(conteudo_bytes)
        except OSError as erro:
            print(f"Falha ao salvar o pedido em {caminho_arquivo}: {erro}")
            return False, b""

        print(f"Pedido salvo em: {caminho_arquivo}")
        rede.transmitir_pedido(nome_arquivo, conteudo_bytes)

        return True, conteudo_bytes

    @pyqtSlot("QVariantMap", result=bool)
    @pyqtSlot("QVariantMap", int, result=bool)
    @protegido(False)
    def enviarPedido(self, dados, copias=1):
        """Gera o arquivo .txt do pedido de entrega e pede a impressão pela
        malha local `copias` vezes (padrão 1) — a comanda é salva uma única
        vez (ver _salvarComanda), só o pedido de impressão se repete: a
        tela de Entrega chama isto com 2 cópias por padrão (uma pro
        motoboy, uma pra cozinha/registro). Retorna True assim que o
        arquivo é salvo — a QML usa esse retorno para decidir se limpa a
        tela para um próximo pedido; a confirmação de cada impressão chega
        depois, separadamente (ver rede.impressaoResultado, um sinal por
        cópia)."""
        sucesso, conteudo_bytes = self._salvarComanda(dados)
        if not sucesso:
            return False

        # A impressão em si não acontece mais aqui: é pedida pela malha
        # local (rede.solicitar_impressao), que roteia pra máquina que
        # estiver com a impressora conectada — pode ser esta ou outra.
        for _ in range(max(1, copias)):
            rede.solicitar_impressao(conteudo_bytes)
        return True

    @pyqtSlot("QVariantMap", result=bool)
    @protegido(False)
    def lancarPedido(self, dados):
        """Igual a enviarPedido, mas nunca tenta imprimir — usado pelo botão
        'Lançar', que só grava o .txt e propaga para a rede local."""
        sucesso, _conteudo_bytes = self._salvarComanda(dados)
        return sucesso
