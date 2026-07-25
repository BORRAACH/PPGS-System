import os
import re

from PyQt6.QtCore import QByteArray, QObject, pyqtSignal, pyqtSlot

from services.redeService import rede

# Mesma codepage usada por balcaoController/entregaController para salvar os
# .txt das comandas — precisa decodificar com o mesmo codec, senão os
# caracteres acentuados saem corrompidos.
CODEPAGE_IMPRESSORA = "cp850"

ESC = "\x1b"
# Remove os códigos ESC/POS de negrito (ESC E 0x01 / ESC E 0x00) embutidos no
# .txt pelos controllers de venda — só fazem sentido para a impressora
# térmica, não para exibição em tela.
_PADRAO_NEGRITO = re.compile(re.escape(ESC) + r"E[\x00\x01]")

# Extraem os campos do cabeçalho do cupom (ver balcaoController/
# entregaController) para montar o título exibido na Consulta e para
# reconstruir os dados ao editar, sem depender do nome do arquivo.
_PADRAO_CLIENTE = re.compile(r"^Cliente:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_DATA = re.compile(r"^Data:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_TELEFONE = re.compile(r"^Telefone:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_ENDERECO = re.compile(r"^Endereço:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_BAIRRO = re.compile(r"^Bairro:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_OBSERVACAO_GERAL = re.compile(r"^Observação:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_FORMA_PAGAMENTO = re.compile(r"^Forma de pagamento:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_TROCO = re.compile(r"^Troco para:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_TAXA_ENTREGA = re.compile(r"^Taxa de entrega:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_STATUS_PAGAMENTO = re.compile(r"^Status:[ \t]*(.*)$", re.MULTILINE)
# balcaoController imprime o status colado no fim da linha do valor total
# (ex: "Valor do pedido: R$ 45,00 [PG]") em vez de uma linha "Status:"
# própria como o entregaController — precisa de um padrão à parte para
# reconstruir.
_PADRAO_STATUS_PAGAMENTO_INLINE = re.compile(r"^Valor do pedido:.*\[(NP|PG)\][ \t]*$", re.MULTILINE)

# Linha de um item na tabela do cupom: "coluna_pedido | valor". A observação
# (quando houver) vem numa linha própria logo abaixo, recuada com 2 espaços
# (ver balcaoController/entregaController._formatarTabela).
_PADRAO_LINHA_TABELA = re.compile(r"^(.*)\|(.*)$")
_PADRAO_LINHA_OBSERVACAO = re.compile(r"^  (.+)$")
# Fração de sabor de pizza meio a meio: "1/3 - Nome do Sabor".
_PADRAO_FRACAO_SABOR = re.compile(r"^\d+/\d+ - (.+)$")
# Sufixo de tamanho no primeiro sabor: "Nome do Sabor (Grande)".
_PADRAO_SUFIXO_TAMANHO = re.compile(r"^(.*)\s\(([^)]+)\)$")
# balcaoController/entregaController agora imprimem o nome do item em caixa
# alta (ex: "(GRANDE)"), então a comparação precisa ignorar maiúsculas/
# minúsculas para continuar reconhecendo o sufixo em comandas antigas e novas.
_TAMANHOS_VALIDOS = ("Grande", "Broto", "Mini")
_TAMANHOS_VALIDOS_UPPER = tuple(t.upper() for t in _TAMANHOS_VALIDOS)


def _limpar_codigos_impressora(texto):
    return _PADRAO_NEGRITO.sub("", texto)


def _extrair_campo(padrao, texto):
    match = padrao.search(texto)
    return match.group(1).strip() if match else ""


def _extrair_status_pagamento(texto):
    """Tenta primeiro a linha "Status:" própria (entregaController); se não
    encontrar, tenta o formato colado na linha do valor total
    (balcaoController)."""
    status = _extrair_campo(_PADRAO_STATUS_PAGAMENTO, texto)
    if status:
        return status

    match = _PADRAO_STATUS_PAGAMENTO_INLINE.search(texto)
    return match.group(1) if match else ""


def _dividir_endereco_numero(endereco_completo):
    """Desfaz o "Endereço, Número" montado por entregaController.enviarPedido."""
    if not endereco_completo:
        return "", ""

    partes = endereco_completo.rsplit(",", 1)
    if len(partes) == 2 and partes[1].strip():
        return partes[0].strip(), partes[1].strip()

    return endereco_completo.strip(), ""


def _reconstruir_itens(linhas_tabela):
    """Desfaz balcaoController._montarGrupos/_formatarTabela: volta das
    linhas já formatadas do cupom para a lista de itens (pedido, observação,
    valor) como ficavam em modeloPedidos antes de imprimir."""
    itens = []
    grupo_atual = []

    def fechar_grupo():
        if not grupo_atual:
            return

        if len(grupo_atual) == 1:
            coluna_pedido, observacao, valor = grupo_atual[0]
            pedido = coluna_pedido[2:] if coluna_pedido.startswith("- ") else coluna_pedido
            itens.append({"pedido": pedido, "observacao": observacao, "valor": valor})
        else:
            sabores = []
            tamanho = ""
            observacao_final = ""
            valor_final = ""
            for indice, (coluna_pedido, observacao, valor) in enumerate(grupo_atual):
                match_fracao = _PADRAO_FRACAO_SABOR.match(coluna_pedido)
                nome = match_fracao.group(1) if match_fracao else coluna_pedido
                if indice == 0:
                    match_tamanho = _PADRAO_SUFIXO_TAMANHO.match(nome)
                    if match_tamanho and match_tamanho.group(2).strip().upper() in _TAMANHOS_VALIDOS_UPPER:
                        nome = match_tamanho.group(1)
                        tamanho = match_tamanho.group(2)
                    valor_final = valor
                # A observação do grupo agora é impressa depois de TODAS as
                # frações (ver _formatarTabela), então fica anexada à última
                # fração lida, não necessariamente à primeira.
                if observacao:
                    observacao_final = observacao
                sabores.append(nome)

            pedido = " / ".join(sabores)
            if tamanho:
                pedido += f" ({tamanho})"
            itens.append({"pedido": pedido, "observacao": observacao_final, "valor": valor_final})

        grupo_atual.clear()

    for linha in linhas_tabela:
        if linha.strip() == "":
            fechar_grupo()
            continue

        # Linha de observação (recuada), pertence ao pedido imediatamente
        # acima dela dentro do grupo atual.
        match_observacao = _PADRAO_LINHA_OBSERVACAO.match(linha)
        if match_observacao and grupo_atual:
            coluna_pedido, _observacao_antiga, valor = grupo_atual[-1]
            grupo_atual[-1] = (coluna_pedido, match_observacao.group(1).strip(), valor)
            continue

        match_linha = _PADRAO_LINHA_TABELA.match(linha)
        if not match_linha:
            continue

        coluna_pedido, valor = (g.strip() for g in match_linha.groups())
        grupo_atual.append((coluna_pedido, "", valor))

    fechar_grupo()
    return itens


class ConsultaController(QObject):
    # Emitido quando um pedido chega/some pela rede (ver aplicarPedidoRemoto/
    # removerPedidoRemoto) — Consulta.qml se conecta a este sinal para
    # recarregar a lista sozinha, sem precisar do botão "Atualizar".
    comandasAtualizadas = pyqtSignal()

    def __init__(self):
        super().__init__()
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.pasta_pedidos = os.path.join(base_dir, "pedidos")

    @pyqtSlot(result="QVariantList")
    def listarComandas(self):
        """Lê todos os .txt salvos em pedidos/ e retorna seus dados já
        prontos para exibição (sem os códigos de controle da impressora),
        mais recentes primeiro."""
        os.makedirs(self.pasta_pedidos, exist_ok=True)

        comandas = []
        for nome_arquivo in os.listdir(self.pasta_pedidos):
            if not nome_arquivo.endswith(".txt"):
                continue

            caminho = os.path.join(self.pasta_pedidos, nome_arquivo)
            try:
                with open(caminho, "rb") as arquivo:
                    conteudo_bytes = arquivo.read()
                modificado_em = os.path.getmtime(caminho)
            except OSError as erro:
                print(f"Falha ao ler {caminho}: {erro}")
                continue

            conteudo = conteudo_bytes.decode(CODEPAGE_IMPRESSORA, errors="replace")
            conteudo = _limpar_codigos_impressora(conteudo).strip("\n")
            tipo = "Entrega" if nome_arquivo.startswith("entrega_") else "Balcão"

            comandas.append({
                "arquivo": nome_arquivo,
                "tipo": tipo,
                "conteudo": conteudo,
                "cliente": _extrair_campo(_PADRAO_CLIENTE, conteudo),
                "dataHora": _extrair_campo(_PADRAO_DATA, conteudo),
                "modificadoEm": modificado_em,
            })

        comandas.sort(key=lambda c: c["modificadoEm"], reverse=True)
        return comandas

    @pyqtSlot(str, result="QVariantMap")
    def reconstruirComanda(self, nome_arquivo):
        """Lê uma comanda já salva e desfaz a formatação de impressão,
        devolvendo os campos prontos para preencher de novo o formulário de
        Balcão ou Entrega (usado pela opção "Editar" da Consulta)."""
        nome_arquivo = os.path.basename(nome_arquivo)
        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)

        try:
            with open(caminho, "rb") as arquivo:
                conteudo_bytes = arquivo.read()
        except OSError as erro:
            print(f"Falha ao ler {caminho}: {erro}")
            return {}

        conteudo = conteudo_bytes.decode(CODEPAGE_IMPRESSORA, errors="replace")
        conteudo = _limpar_codigos_impressora(conteudo)
        linhas = conteudo.split("\n")

        divisorias = [i for i, linha in enumerate(linhas) if linha.startswith("----")]
        if len(divisorias) < 2:
            return {}

        linhas_tabela = linhas[divisorias[0] + 1:divisorias[1]]
        endereco_completo = _extrair_campo(_PADRAO_ENDERECO, conteudo)
        endereco, numero = _dividir_endereco_numero(endereco_completo)

        return {
            "arquivo": nome_arquivo,
            "tipo": "Entrega" if nome_arquivo.startswith("entrega_") else "Balcão",
            "cliente": _extrair_campo(_PADRAO_CLIENTE, conteudo),
            "telefone": _extrair_campo(_PADRAO_TELEFONE, conteudo),
            "endereco": endereco,
            "numero": numero,
            "bairro": _extrair_campo(_PADRAO_BAIRRO, conteudo),
            "observacaoGeral": _extrair_campo(_PADRAO_OBSERVACAO_GERAL, conteudo),
            "formaPagamento": _extrair_campo(_PADRAO_FORMA_PAGAMENTO, conteudo),
            "troco": _extrair_campo(_PADRAO_TROCO, conteudo),
            "taxaEntrega": _extrair_campo(_PADRAO_TAXA_ENTREGA, conteudo),
            "statusPagamento": _extrair_status_pagamento(conteudo),
            "itens": _reconstruir_itens(linhas_tabela),
        }

    @pyqtSlot(str, result=bool)
    def apagarComanda(self, nome_arquivo):
        """Remove o .txt da comanda. Retorna True em caso de sucesso."""
        nome_arquivo = os.path.basename(nome_arquivo)
        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)

        try:
            os.remove(caminho)
        except OSError as erro:
            print(f"Falha ao apagar {caminho}: {erro}")
            return False

        rede.transmitir_exclusao(nome_arquivo)
        return True

    @pyqtSlot(str, QByteArray)
    def aplicarPedidoRemoto(self, nome_arquivo, conteudo):
        """Grava localmente um pedido recebido de outra máquina da rede e
        avisa a tela de Consulta para recarregar a lista."""
        nome_arquivo = os.path.basename(nome_arquivo)
        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)
        os.makedirs(self.pasta_pedidos, exist_ok=True)

        try:
            with open(caminho, "wb") as arquivo:
                arquivo.write(bytes(conteudo))
        except OSError as erro:
            print(f"Falha ao salvar pedido recebido da rede em {caminho}: {erro}")
            return

        self.comandasAtualizadas.emit()

    @pyqtSlot(str)
    def removerPedidoRemoto(self, nome_arquivo):
        """Apaga localmente um pedido removido em outra máquina da rede e
        avisa a tela de Consulta para recarregar a lista."""
        nome_arquivo = os.path.basename(nome_arquivo)
        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)

        try:
            os.remove(caminho)
        except OSError:
            pass

        self.comandasAtualizadas.emit()
