import os
import re
import threading
import uuid
from datetime import datetime

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from services import comandaEstiloService as estilo
from services.printerService import PrinterService
from services.redeService import rede

# Separador usado em Pizzas.qml (nomesArray.join(" / ")) para pizzas meio a meio.
# Tem espaço dos dois lados, o que o distingue de nomes como "Atum c/ Cebola".
SEPARADOR_SABORES = " / "

# Codepage que a Bematech usa para acentuação (ç, ã, é...) em modo ESC/POS.
# Não é UTF-8: se salvar como UTF-8, os acentos saem corrompidos no cupom impresso.
CODEPAGE_IMPRESSORA = "cp850"


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
    # Emitido quando a consulta disparada por consultarImpressoraAtual()
    # termina (ver o método) — carrega o mesmo formato de dict que
    # infoImpressoraAtual() devolvia antes de virar assíncrono.
    infoImpressoraPronta = pyqtSignal("QVariantMap")

    def __init__(self):
        super().__init__()
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.pasta_pedidos = os.path.join(base_dir, "pedidos")
        os.makedirs(self.pasta_pedidos, exist_ok=True)
        self.printer_service = PrinterService()

    def _salvarComanda(self, dados):
        """Monta o texto da comanda, grava o .txt e propaga para a rede
        local. Não imprime nada — usado tanto por enviarPedido() quanto por
        lancarPedido(). Retorna (sucesso, conteudo_bytes); conteudo_bytes
        vem vazio quando sucesso é False."""
        cliente = dados.get("cliente", "")
        itens = dados.get("itens", [])
        forma_pagamento = dados.get("formaPagamento", "")
        troco = dados.get("troco", "")
        status_pagamento = dados.get("statusPagamento", "NP")

        grupos = self._montarGrupos(itens)
        valor_total = sum(_valor_para_float(item.get("valor", "")) for item in itens)

        agora = datetime.now()
        # Sufixo aleatório curto: com várias máquinas gravando pedidos ao
        # mesmo tempo na rede local, dois pedidos no mesmo segundo teriam o
        # mesmo nome de arquivo e um sobrescreveria o outro ao sincronizar.
        nome_arquivo = f"pedido_{agora.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}.txt"
        caminho_arquivo = os.path.join(self.pasta_pedidos, nome_arquivo)

        linhas_arquivo = [
            f"Cliente: {estilo.formatar_campo(cliente, 'cliente')}",
            f"Data: {estilo.formatar_campo(agora.strftime('%d/%m/%Y %H:%M:%S'), 'data')}",
            *estilo.linhas_espacamento_secoes(),
            "-" * 40,
            *estilo.linhas_espacamento_secoes(),
            *self._formatarTabela(grupos),
            *estilo.linhas_espacamento_secoes(),
            "-" * 40,
            *estilo.linhas_espacamento_secoes(),
        ]
        if forma_pagamento:
            linhas_arquivo.append(f"Forma de pagamento: {estilo.formatar_campo(forma_pagamento, 'forma_pagamento')}")
            if forma_pagamento == "Dinheiro" and troco:
                linhas_arquivo.append(f"Troco para: {estilo.formatar_campo(troco, 'troco_para')}")
            linhas_arquivo.extend(estilo.linhas_espacamento_secoes())
            linhas_arquivo.append("-" * 40)
            linhas_arquivo.extend(estilo.linhas_espacamento_secoes())
        # Status (NP/PG) logo depois do valor total, na mesma linha — não
        # como uma linha separada acima, diferente do formato usado em
        # EntregaController.
        valor_total_formatado = f"R$ {valor_total:.2f}".replace(".", ",")
        linhas_arquivo.append(
            f"Valor do pedido: {estilo.formatar_campo(valor_total_formatado, 'valor_total')} "
            f"[{estilo.formatar_campo(status_pagamento, 'status')}]"
        )
        if forma_pagamento == "Dinheiro" and troco:
            troco_a_dar = _valor_para_float(troco) - valor_total
            troco_a_dar_formatado = f"R$ {troco_a_dar:.2f}".replace(".", ",")
            linhas_arquivo.append(f"Troco a dar: {estilo.formatar_campo(troco_a_dar_formatado, 'troco_a_dar')}")
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
        """Gera o arquivo .txt do pedido e pede a impressão pela malha local.
        Retorna True assim que o arquivo é salvo — a QML usa esse retorno
        para decidir se limpa a tela para um próximo pedido; a confirmação
        da impressão em si chega depois, separadamente (ver
        rede.impressaoResultado)."""
        sucesso, conteudo_bytes = self._salvarComanda(dados)
        if not sucesso:
            return False

        # A impressão em si não acontece mais aqui: é pedida pela malha
        # local (rede.solicitar_impressao), que roteia pra máquina que
        # estiver com a impressora conectada — pode ser esta ou outra. O
        # resultado chega depois, de forma assíncrona, pelo sinal
        # rede.impressaoResultado.
        rede.solicitar_impressao(conteudo_bytes)
        return True

    @pyqtSlot("QVariantMap", result=bool)
    def lancarPedido(self, dados):
        """Igual a enviarPedido, mas nunca tenta imprimir — usado pelo botão
        'Lançar', que só grava o .txt e propaga para a rede local."""
        sucesso, _conteudo_bytes = self._salvarComanda(dados)
        return sucesso

    @pyqtSlot()
    def consultarImpressoraAtual(self):
        """Dispara em segundo plano a busca pela impressora que esta
        máquina usaria para imprimir agora (a configurada em
        PrinterService, ou a padrão do sistema) — usado por Rede.qml para
        mostrar a que impressora esta máquina está conectada.

        A busca em si (services/printer/*) roda comandos externos
        (lpstat/PowerShell) que podem levar até alguns segundos; rodar numa
        thread evita travar a interface (e a própria abertura da tela
        Rede.qml) enquanto isso. O resultado chega pelo sinal
        infoImpressoraPronta, emitido de dentro da thread — o Qt entrega o
        sinal de volta na thread principal automaticamente."""
        threading.Thread(target=self._consultarImpressoraEmThread, daemon=True).start()

    def _consultarImpressoraEmThread(self):
        try:
            impressora = self.printer_service.localizar_impressora()
        except Exception as erro:
            # Qualquer falha aqui (SO não suportado, PowerShell/CUPS com
            # saída inesperada, etc.) precisa virar "não encontrada" em vez
            # de propagar — isto roda fora da thread principal, e uma
            # exceção Python sem tratamento aqui derrubaria o app inteiro.
            print(f"[balcaoController] Falha ao consultar a impressora: {erro}")
            self.infoImpressoraPronta.emit({"encontrada": False, "erro": str(erro)})
            return

        if impressora is None:
            self.infoImpressoraPronta.emit({"encontrada": False, "erro": ""})
            return

        self.infoImpressoraPronta.emit({
            "encontrada": True,
            "nome": impressora.nome,
            "modelo": impressora.modelo,
            "fabricante": impressora.fabricante,
            "porta": impressora.porta,
            "tipoPorta": impressora.tipo_porta,
            "status": impressora.status,
            "padrao": impressora.padrao,
        })

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
        recuada e com o estilo configurado para o campo "observacao_item" (ver
        services/comandaEstiloService.py), depois de TODAS as frações do
        grupo — mesmo numa pizza meio a meio (ou dividida em mais partes), a
        observação sai só ao final, abaixo do nome completo, nunca entre uma
        fração e outra."""
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
                # Alinha primeiro com o texto puro, e só então aplica o
                # estilo configurado — assim os bytes de controle (invisíveis
                # na impressão) não contam como largura na coluna.
                coluna_pedido_fmt = estilo.formatar_campo(coluna_pedido.ljust(largura_pedido), "pedido")
                texto_linhas.append(f"{coluna_pedido_fmt} | {valor}")
                if observacao:
                    observacao_grupo = observacao

            if observacao_grupo:
                texto_linhas.append(f"  {estilo.formatar_campo(observacao_grupo, 'observacao_item')}")

        return texto_linhas
