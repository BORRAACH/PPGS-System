import os
import threading
import uuid
from datetime import datetime

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config import impressoraWindows
from Config.logConfig import protegido
from services import comandaEstiloService as estilo
from services import comandaSequencialService as sequencial
from services import comandaTextoService as texto
from services.printerService import PrinterService
from services.rede import rede

CODEPAGE_IMPRESSORA = texto.CODEPAGE_IMPRESSORA

# Marca impressa no topo e no rodapé de uma comanda de teste (ver
# _salvarComanda) — em negrito direto via comandaEstiloService, não como um
# "campo" configurável em EstiloImpressora.qml, porque é um aviso fixo pra
# quem for tirar a comanda da impressora, não um dado do pedido.
_MARCA_COMANDA_TESTE = f"{estilo.NEGRITO_LIGA}*** COMANDA DE TESTE ***{estilo.NEGRITO_DESLIGA}"


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
        # Nome do último .txt gravado — ver ultimoArquivoSalvo().
        self._ultimo_arquivo = ""

    def _salvarComanda(self, dados):
        """Monta o texto da comanda, grava o .txt e propaga para a rede
        local. Não imprime nada — usado tanto por enviarPedido() quanto por
        lancarPedido(). Retorna (sucesso, conteudo_bytes); conteudo_bytes
        vem vazio quando sucesso é False.

        Se dados["teste"] vier True (comanda em branco confirmada como
        teste pelo popup de Balcao.qml), o cliente vira "Teste", o cupom
        sai marcado no topo/rodapé, e a comanda NÃO é gravada em disco nem
        propagada pela rede — não deve aparecer na Consulta. conteudo_bytes
        ainda volta preenchido, porque enviarPedido() precisa dele pra
        pedir a impressão mesmo nesse caso."""
        # Zerado já na entrada, não só em caso de erro: comanda de teste
        # devolve sucesso sem gravar nada, e deixar aqui o nome da comanda
        # anterior faria ultimoArquivoSalvo() apontar pra uma comanda que não
        # tem nada a ver com esta chamada.
        self._ultimo_arquivo = ""

        teste = bool(dados.get("teste", False))
        cliente = "Teste" if teste else dados.get("cliente", "")
        usuario = "" if teste else str(dados.get("usuario", "") or "").strip()
        itens = dados.get("itens", [])
        forma_pagamento = dados.get("formaPagamento", "")
        troco = dados.get("troco", "")
        status_pagamento = dados.get("statusPagamento", "NP")

        grupos = texto.montar_grupos(itens)
        valor_total = sum(texto.valor_para_float(item.get("valor", "")) for item in itens)

        agora = datetime.now()
        # Sufixo aleatório curto: com várias máquinas gravando pedidos ao
        # mesmo tempo na rede local, dois pedidos no mesmo segundo teriam o
        # mesmo nome de arquivo e um sobrescreveria o outro ao sincronizar.
        nome_arquivo = f"pedido_{agora.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}.txt"
        caminho_arquivo = os.path.join(self.pasta_pedidos, nome_arquivo)

        codigo_pedido = ""
        if not teste:
            # Só consome um número da sequência diária pra comanda de
            # verdade — uma comanda de teste não deve "furar" a numeração
            # que o dono acompanha (ver docstring desta função).
            codigo_pedido = sequencial.gerar_codigo_pedido(agora)

        dinheiro_com_troco = forma_pagamento == "Dinheiro" and troco
        valor_total_formatado = f"R$ {valor_total:.2f}".replace(".", ",")
        troco_a_dar_formatado = ""
        if dinheiro_com_troco:
            troco_a_dar_formatado = f"R$ {(texto.valor_para_float(troco) - valor_total):.2f}".replace(".", ",")

        renderizadores = {
            # A marca de comanda de teste (ver _MARCA_COMANDA_TESTE) toma o
            # lugar do ID sempre no topo/rodapé, fora da ordem configurável
            # (ver abaixo) — não faz sentido reordenar um aviso pros dois
            # extremos do cupom.
            "id_pedido": None if teste else [f"ID: {estilo.formatar_campo(codigo_pedido, 'id_pedido')}"],
            "cliente": [f"Cliente: {estilo.formatar_campo(cliente, 'cliente')}"],
            "data": [f"Data: {estilo.formatar_campo(agora.strftime('%d/%m/%Y %H:%M:%S'), 'data')}"],
            # Quem autorizou o lançamento (ver components/PopupAutorizacao.qml).
            # None quando vem vazio — comanda de teste, ou ninguém cadastrado
            # ainda —, e montar_linhas_por_ordem pula a chave sem conteúdo, de
            # modo que a comanda sai exatamente como saía antes.
            "usuario": [f"Usuário: {estilo.formatar_campo(usuario, 'usuario')}"] if usuario else None,
            "itens": texto.formatar_tabela(grupos),
            "forma_pagamento": [f"Forma de pagamento: {estilo.formatar_campo(forma_pagamento, 'forma_pagamento')}"] if forma_pagamento else None,
            "troco_para": [f"Troco para: {estilo.formatar_campo(troco, 'troco_para')}"] if dinheiro_com_troco else None,
            "status": [f"Status: {estilo.formatar_campo(status_pagamento, 'status')}"],
            "valor_total": [f"Valor do pedido: {estilo.formatar_campo(valor_total_formatado, 'valor_total')}"],
            "troco_a_dar": [f"Troco a dar: {estilo.formatar_campo(troco_a_dar_formatado, 'troco_a_dar')}"] if dinheiro_com_troco else None,
        }
        linhas_arquivo = []
        if teste:
            linhas_arquivo.append(_MARCA_COMANDA_TESTE)
            linhas_arquivo.extend(estilo.linhas_espacamento_secoes())
        linhas_arquivo.extend(texto.montar_linhas_por_ordem(estilo.ordem_secoes(), renderizadores))
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
        self._ultimo_arquivo = nome_arquivo
        rede.transmitir_pedido(nome_arquivo, conteudo_bytes)

        return True, conteudo_bytes

    @pyqtSlot(result=str)
    def ultimoArquivoSalvo(self):
        """Nome do .txt gravado pela última chamada bem-sucedida de
        enviarPedido/lancarPedido.

        Existe porque os dois devolvem só um bool, e quem edita uma comanda
        já baixada precisa do nome NOVO pra transferir a baixa pra ele (ver
        Balcao.qml:prosseguirLancar): editar é apagar-e-recriar, então o
        arquivo resultante tem outro nome, que a QML não teria como adivinhar.

        Vazio quando a última comanda foi de teste (não é gravada em disco) ou
        quando nada foi salvo ainda nesta sessão."""
        return self._ultimo_arquivo

    @pyqtSlot("QVariantMap", result=bool)
    @pyqtSlot("QVariantMap", int, result=bool)
    @protegido(False)
    def enviarPedido(self, dados, copias=1):
        """Gera o arquivo .txt do pedido e pede a impressão pela malha local
        `copias` vezes (padrão 1) — a comanda é salva uma única vez (ver
        _salvarComanda), só o pedido de impressão se repete, pros casos em
        que o balcão precisa de mais de uma via da mesma comanda (ex: uma
        pra cozinha, uma pro cliente). Retorna True assim que o arquivo é
        salvo — a QML usa esse retorno para decidir se limpa a tela para um
        próximo pedido; a confirmação de cada impressão chega depois,
        separadamente (ver rede.impressaoResultado, um sinal por cópia)."""
        sucesso, conteudo_bytes = self._salvarComanda(dados)
        if not sucesso:
            return False

        # A impressão em si não acontece mais aqui: é pedida pela malha
        # local (rede.solicitar_impressao), que roteia pra máquina que
        # estiver com a impressora conectada — pode ser esta ou outra. O
        # resultado chega depois, de forma assíncrona, pelo sinal
        # rede.impressaoResultado.
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

    @pyqtSlot()
    @protegido()
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
        # Repete aqui (não só uma vez no início do app, em main.py) pra
        # cobrir o caso de a Bematech ser conectada DEPOIS do app já estar
        # aberto — como isto já roda fora da thread principal, a tela
        # Rede.qml continua respondendo normalmente enquanto isso (ver
        # Config/impressoraWindows.py; não faz nada fora do Windows).
        impressoraWindows.garantir_impressora_bematech()

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
            "disponivel": impressora.disponivel,
        })
