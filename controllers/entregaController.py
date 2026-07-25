import os
import re
import uuid
from datetime import datetime

from PyQt6.QtCore import QObject, pyqtSlot

from services.redeService import rede

# Separador usado em Pizzas.qml (nomesArray.join(" / ")) para pizzas meio a meio.
# Tem espaço dos dois lados, o que o distingue de nomes como "Atum c/ Cebola".
SEPARADOR_SABORES = " / "

# Comandos ESC/POS para negrito. A Bematech MP-4200 TH entende esses comandos
# quando configurada em modo de emulação ESC/POS (padrão em impressoras térmicas
# de cupom). O arquivo precisa ser enviado à impressora em modo RAW (bytes puros),
# não impresso via um editor de texto comum, senão esses códigos não são interpretados.
ESC = "\x1b"
NEGRITO_LIGA = ESC + "E" + "\x01"
NEGRITO_DESLIGA = ESC + "E" + "\x00"

# Codepage que a Bematech usa para acentuação (ç, ã, é...) em modo ESC/POS.
# Não é UTF-8: se salvar como UTF-8, os acentos saem corrompidos no cupom impresso.
CODEPAGE_IMPRESSORA = "cp850"


def _negrito(texto):
    """Envolve o texto com os códigos ESC/POS de negrito ligado/desligado."""
    return f"{NEGRITO_LIGA}{texto}{NEGRITO_DESLIGA}"


def _dividir_sabores(pedido_texto):
    """Separa um pedido em (lista_de_sabores, tamanho).

    "Atum c/ Cebola / Bacon c/ Ovos (Grande)" vira
    (["Atum c/ Cebola", "Bacon c/ Ovos"], "Grande").
    """
    tamanho = None
    corpo = pedido_texto

    match = re.match(r"^(.*)\s\(([^)]+)\)$", pedido_texto)
    if match:
        corpo = match.group(1)
        tamanho = match.group(2)

    sabores = [s.strip() for s in corpo.split(SEPARADOR_SABORES) if s.strip()]
    return sabores, tamanho


def _valor_para_float(valor_texto):
    """Converte "R$ 45,00" em 45.0. Retorna 0.0 se não conseguir interpretar."""
    if not valor_texto:
        return 0.0

    limpo = valor_texto.replace("R$", "").strip()
    limpo = limpo.replace(".", "").replace(",", ".")
    try:
        return float(limpo)
    except ValueError:
        return 0.0


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
        vem vazio quando sucesso é False."""
        cliente = dados.get("cliente", "")
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

        grupos = self._montarGrupos(itens)
        valor_total = sum(_valor_para_float(item.get("valor", "")) for item in itens) + _valor_para_float(taxa_entrega)

        agora = datetime.now()
        # Sufixo aleatório curto: com várias máquinas gravando pedidos ao
        # mesmo tempo na rede local, dois pedidos no mesmo segundo teriam o
        # mesmo nome de arquivo e um sobrescreveria o outro ao sincronizar.
        nome_arquivo = f"entrega_{agora.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}.txt"
        caminho_arquivo = os.path.join(self.pasta_pedidos, nome_arquivo)

        endereco_completo = f"{endereco}, {numero}" if numero else endereco

        linhas_arquivo = [
            f"Cliente: {cliente}",
            f"Telefone: {telefone}",
            f"Endereço: {endereco_completo}",
            f"Bairro: {bairro}",
            f"Data: {agora.strftime('%d/%m/%Y %H:%M:%S')}",
            "",
            "-" * 40,
            "",
            *self._formatarTabela(grupos),
            "",
            "-" * 40,
            "",
        ]
        if observacaoGeral:
            linhas_arquivo.append(f"Observação: {observacaoGeral}")
            linhas_arquivo.append("")
            linhas_arquivo.append("-" * 40)
            linhas_arquivo.append("")
        linhas_arquivo.append(f"Forma de pagamento: {forma_pagamento}")
        if forma_pagamento == "Dinheiro" and troco:
            linhas_arquivo.append(f"Troco para: {troco}")
        linhas_arquivo.append(f"Status: {status_pagamento}")
        linhas_arquivo.append("")
        linhas_arquivo.append("-" * 40)
        linhas_arquivo.append("")
        if taxa_entrega:
            linhas_arquivo.append(f"Taxa de entrega: {taxa_entrega}")
        linhas_arquivo.append(f"Valor do pedido: R$ {valor_total:.2f}".replace(".", ","))
        if forma_pagamento == "Dinheiro" and troco:
            troco_a_dar = _valor_para_float(troco) - valor_total
            linhas_arquivo.append(f"Troco a dar: R$ {troco_a_dar:.2f}".replace(".", ","))

        conteudo = "\n".join(linhas_arquivo) + "\n"
        # Modo binário: o texto vira bytes em cp850 e os códigos ESC/POS de
        # negrito são preservados como estão, sem reinterpretação de encoding.
        conteudo_bytes = conteudo.encode(CODEPAGE_IMPRESSORA, errors="replace")

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
    def enviarPedido(self, dados):
        """Gera o arquivo .txt do pedido de entrega e pede a impressão pela
        malha local. Retorna True assim que o arquivo é salvo — a QML usa
        esse retorno para decidir se limpa a tela para um próximo pedido; a
        confirmação da impressão em si chega depois, separadamente (ver
        rede.impressaoResultado)."""
        sucesso, conteudo_bytes = self._salvarComanda(dados)
        if not sucesso:
            return False

        # A impressão em si não acontece mais aqui: é pedida pela malha
        # local (rede.solicitar_impressao), que roteia pra máquina que
        # estiver com a impressora conectada — pode ser esta ou outra.
        rede.solicitar_impressao(conteudo_bytes)
        return True

    @pyqtSlot("QVariantMap", result=bool)
    def lancarPedido(self, dados):
        """Igual a enviarPedido, mas nunca tenta imprimir — usado pelo botão
        'Lançar', que só grava o .txt e propaga para a rede local."""
        sucesso, _conteudo_bytes = self._salvarComanda(dados)
        return sucesso

    @staticmethod
    def _montarGrupos(itens):
        """Converte os itens do pedido em grupos de linhas (coluna_pedido, observacao, valor).

        Cada item vira um grupo (uma pizza meio a meio gera várias linhas, mas
        continua sendo um único grupo), para que se possa separar os grupos
        com uma linha em branco depois de formatados.
        """
        grupos = []
        for item in itens:
            # Nome do item e observação saem em caixa alta no cupom impresso.
            pedido = item.get("pedido", "").upper()
            observacao = item.get("observacao", "").upper()
            valor = item.get("valor", "")

            sabores, tamanho = _dividir_sabores(pedido)

            if len(sabores) <= 1:
                grupos.append([(f"- {pedido}", observacao, valor)])
                continue

            # Pizza meio a meio: cada sabor ocupa "1/N" da pizza.
            total = len(sabores)
            grupo = []
            for indice, sabor in enumerate(sabores):
                nome_sabor = f"{sabor} ({tamanho})" if indice == 0 and tamanho else sabor
                coluna_pedido = f"1/{total} - {nome_sabor}"
                if indice == 0:
                    grupo.append((coluna_pedido, observacao, valor))
                else:
                    grupo.append((coluna_pedido, "", ""))
            grupos.append(grupo)

        return grupos

    @staticmethod
    def _formatarTabela(grupos):
        """Alinha pedido e valor em uma coluna "|" e separa cada grupo com uma
        linha em branco. A observação (quando houver) vai numa linha própria,
        recuada e em negrito, depois de TODAS as frações do grupo — mesmo
        numa pizza meio a meio (ou dividida em mais partes), a observação sai
        só ao final, abaixo do nome completo, nunca entre uma fração e outra."""
        linhas = [linha for grupo in grupos for linha in grupo]
        if not linhas:
            return []

        largura_pedido = max(len(l[0]) for l in linhas)

        texto_linhas = []
        for indice, grupo in enumerate(grupos):
            if indice > 0:
                texto_linhas.append("")

            observacao_grupo = ""
            for coluna_pedido, observacao, valor in grupo:
                # Alinha primeiro com o texto puro, e só então aplica os
                # códigos de negrito — assim os bytes de controle (invisíveis
                # na impressão) não contam como largura na coluna.
                coluna_pedido_fmt = _negrito(coluna_pedido.ljust(largura_pedido))
                texto_linhas.append(f"{coluna_pedido_fmt} | {valor}")
                if observacao:
                    observacao_grupo = observacao

            if observacao_grupo:
                texto_linhas.append(f"  {_negrito(observacao_grupo)}")

        return texto_linhas
