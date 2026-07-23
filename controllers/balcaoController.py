import os
import re
from datetime import datetime

from PyQt6.QtCore import QObject, pyqtSlot

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


class BalcaoController(QObject):
    def __init__(self):
        super().__init__()
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.pasta_pedidos = os.path.join(base_dir, "pedidos")
        os.makedirs(self.pasta_pedidos, exist_ok=True)

    @pyqtSlot("QVariantMap", result=bool)
    def enviarPedido(self, dados):
        """Gera o arquivo .txt do pedido. Retorna True em caso de sucesso,
        False se algo falhar — a QML usa esse retorno para decidir se limpa
        a tela para um próximo pedido."""
        cliente = dados.get("cliente", "")
        itens = dados.get("itens", [])

        grupos = self._montarGrupos(itens)
        valor_total = sum(_valor_para_float(item.get("valor", "")) for item in itens)

        agora = datetime.now()
        nome_arquivo = f"pedido_{agora.strftime('%Y%m%d_%H%M%S')}.txt"
        caminho_arquivo = os.path.join(self.pasta_pedidos, nome_arquivo)

        linhas_arquivo = [
            f"Cliente: {cliente}",
            f"Data: {agora.strftime('%d/%m/%Y %H:%M:%S')}",
            "-" * 40,
            *self._formatarTabela(grupos),
            "-" * 40,
            f"Valor do pedido: R$ {valor_total:.2f}".replace(".", ","),
        ]
        conteudo = "\n".join(linhas_arquivo) + "\n"

        try:
            # Modo binário: o texto vira bytes em cp850 e os códigos ESC/POS de
            # negrito são preservados como estão, sem reinterpretação de encoding.
            with open(caminho_arquivo, "wb") as arquivo:
                arquivo.write(conteudo.encode(CODEPAGE_IMPRESSORA, errors="replace"))
        except OSError as erro:
            print(f"Falha ao salvar o pedido em {caminho_arquivo}: {erro}")
            return False

        print(f"Pedido salvo em: {caminho_arquivo}")
        return True

    @staticmethod
    def _montarGrupos(itens):
        """Converte os itens do pedido em grupos de linhas (coluna_pedido, observacao, valor).

        Cada item vira um grupo (uma pizza meio a meio gera várias linhas, mas
        continua sendo um único grupo), para que se possa separar os grupos
        com uma linha em branco depois de formatados.
        """
        grupos = []
        for item in itens:
            pedido = item.get("pedido", "")
            observacao = item.get("observacao", "")
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
        """Alinha as colunas em barras "|" verticais e separa cada grupo com uma linha em branco."""
        linhas = [linha for grupo in grupos for linha in grupo]
        if not linhas:
            return []

        largura_pedido = max(len(l[0]) for l in linhas)
        largura_observacao = max(len(l[1]) for l in linhas)

        texto_linhas = []
        for indice, grupo in enumerate(grupos):
            if indice > 0:
                texto_linhas.append("")
            for coluna_pedido, observacao, valor in grupo:
                # Alinha primeiro com o texto puro, e só então aplica os
                # códigos de negrito — assim os bytes de controle (invisíveis
                # na impressão) não contam como largura na coluna.
                coluna_pedido_fmt = _negrito(coluna_pedido.ljust(largura_pedido))
                observacao_fmt = _negrito(observacao.ljust(largura_observacao))
                texto_linhas.append(f"{coluna_pedido_fmt} | {observacao_fmt} | {valor}")

        return texto_linhas
