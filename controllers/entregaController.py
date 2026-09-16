import os
import uuid
from datetime import datetime

from PyQt6.QtCore import QObject, pyqtSlot

from Config.logConfig import protegido
from services import comandaEstiloService as estilo
from services import comandaSequencialService as sequencial
from services import comandaTextoService as texto
from services.rede import rede
from services.sugestoesEndereco import sugestoes_endereco

CODEPAGE_IMPRESSORA = texto.CODEPAGE_IMPRESSORA

# Marca impressa no topo e no rodapé de uma comanda de teste (ver
# _salvarComanda) — em negrito direto via comandaEstiloService, não como um
# "campo" configurável em EstiloImpressora.qml, porque é um aviso fixo pra
# quem for tirar a comanda da impressora, não um dado do pedido.
_MARCA_COMANDA_TESTE = f"{estilo.NEGRITO_LIGA}*** COMANDA DE TESTE ***{estilo.NEGRITO_DESLIGA}"


def _endereco_para_qr(rua, numero, bairro, cidade, uf, cep):
    """"Rua Goiás, 196 - Jardim dos Estados, Taubaté - SP, 12062-130" para o QR
    Code, ou "" quando o endereço não passou pelo validador (sem CEP nem
    cidade): aí o QR continua saindo das linhas Endereço:/Bairro:, como antes."""
    rua = " ".join(str(rua or "").split())
    if not rua or not (cep or cidade):
        return ""
    endereco = f"{rua}, {numero}" if numero else rua
    if bairro:
        endereco += f" - {bairro}"
    local = " - ".join(p for p in (cidade, uf) if p)
    return ", ".join(p for p in (endereco, local, cep) if p)


class EntregaController(QObject):
    def __init__(self):
        super().__init__()
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.pasta_pedidos = os.path.join(base_dir, "pedidos")
        os.makedirs(self.pasta_pedidos, exist_ok=True)
        # Nome do último .txt gravado — ver ultimoArquivoSalvo().
        self._ultimo_arquivo = ""

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
        # Zerado já na entrada, não só em caso de erro: comanda de teste
        # devolve sucesso sem gravar nada, e deixar aqui o nome da comanda
        # anterior faria ultimoArquivoSalvo() apontar pra uma comanda que não
        # tem nada a ver com esta chamada.
        self._ultimo_arquivo = ""

        teste = bool(dados.get("teste", False))
        cliente = "Teste" if teste else dados.get("cliente", "")
        usuario = "" if teste else str(dados.get("usuario", "") or "").strip()
        telefone = dados.get("telefone", "")
        endereco = dados.get("endereco", "")
        numero = dados.get("numero", "")
        bairro = dados.get("bairro", "")
        # Endereço validado (ver qml/components/DeliveryAddressValidator.qml).
        # O complemento sai no papel; CEP, cidade e UF só vão para o QR Code
        # (ver _endereco_para_qr). Ponto de referência vai na Observação.
        complemento = " ".join(str(dados.get("complemento", "") or "").split())
        cep = str(dados.get("cep", "") or "").strip()
        cidade = str(dados.get("cidade", "") or "").strip()
        uf = str(dados.get("uf", "") or "").strip()
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
            "telefone": [f"Telefone: {estilo.formatar_campo(telefone, 'telefone')}"],
            "endereco": [f"Endereço: {estilo.formatar_campo(endereco_completo, 'endereco')}"],
            "bairro": [f"Bairro: {estilo.formatar_campo(bairro, 'bairro')}"],
            # Só com conteúdo: sem complemento a linha some do cupom.
            "complemento_entrega": [f"Complemento: {estilo.formatar_campo(complemento, 'complemento_entrega')}"] if complemento else None,
            "data": [f"Data: {estilo.formatar_campo(agora.strftime('%d/%m/%Y %H:%M:%S'), 'data')}"],
            # Quem autorizou o lançamento (ver components/PopupAutorizacao.qml).
            # None quando vem vazio — comanda de teste, ou ninguém cadastrado
            # ainda —, e montar_linhas_por_ordem pula a chave sem conteúdo, de
            # modo que a comanda sai exatamente como saía antes.
            "usuario": [f"Usuário: {estilo.formatar_campo(usuario, 'usuario')}"] if usuario else None,
            "itens": texto.formatar_tabela(grupos),
            "observacao_entrega": [f"Observação: {estilo.formatar_campo(observacaoGeral, 'observacao_entrega')}"] if observacaoGeral else None,
            "forma_pagamento": [f"Forma de pagamento: {estilo.formatar_campo(forma_pagamento, 'forma_pagamento')}"],
            "troco_para": [f"Troco para: {estilo.formatar_campo(troco, 'troco_para')}"] if dinheiro_com_troco else None,
            "status": [f"Status: {estilo.formatar_campo(status_pagamento, 'status')}"],
            "taxa_entrega": [f"Taxa de entrega: {estilo.formatar_campo(taxa_entrega, 'taxa_entrega')}"] if taxa_entrega else None,
            "valor_total": [f"Valor do pedido: {estilo.formatar_campo(valor_total_formatado, 'valor_total')}"],
            "troco_a_dar": [f"Troco a dar: {estilo.formatar_campo(troco_a_dar_formatado, 'troco_a_dar')}"] if dinheiro_com_troco else None,
        }
        # O título da modalidade abre a comanda, antes até da marca de teste.
        linhas_arquivo = texto.linhas_modalidade("Entrega")
        if teste:
            linhas_arquivo.append(_MARCA_COMANDA_TESTE)
            linhas_arquivo.extend(estilo.linhas_espacamento_secoes())
        linhas_arquivo.extend(texto.montar_linhas_por_ordem(estilo.ordem_secoes(), renderizadores))
        if teste:
            linhas_arquivo.extend(estilo.linhas_espacamento_secoes())
            linhas_arquivo.append(_MARCA_COMANDA_TESTE)

        # O endereço completo, só para o QR Code do Maps: a linha interna não sai
        # no papel (ver comandaEstiloService.MARCA_ENDERECO_QR).
        linha_qr = estilo.linha_endereco_qr(_endereco_para_qr(endereco, numero, bairro, cidade, uf, cep))
        if linha_qr:
            linhas_arquivo.append(linha_qr)

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
        Entrega.qml:prosseguirLancar): editar é apagar-e-recriar, então o
        arquivo resultante tem outro nome, que a QML não teria como adivinhar.

        Vazio quando a última comanda foi de teste (não é gravada em disco) ou
        quando nada foi salvo ainda nesta sessão."""
        return self._ultimo_arquivo

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
        self._aprenderEndereco(dados)
        return True

    @pyqtSlot("QVariantMap", result=bool)
    @protegido(False)
    def lancarPedido(self, dados):
        """Igual a enviarPedido, mas nunca tenta imprimir — usado pelo botão
        'Lançar', que só grava o .txt e propaga para a rede local."""
        sucesso, _conteudo_bytes = self._salvarComanda(dados)
        if sucesso:
            self._aprenderEndereco(dados)
        return sucesso

    def _aprenderEndereco(self, dados):
        """Conta o endereço da comanda no histórico que alimenta as sugestões
        da Entrega (ver services/sugestoesEndereco.py). Comanda de teste não
        ensina nada — costuma levar endereço inventado.

        registrarUso é @protegido: uma falha ali fica no log e não chega a
        virar o False que faria a tela acusar erro numa comanda já salva — e o
        atendente lançar o pedido de novo."""
        if dados.get("teste"):
            return
        sugestoes_endereco.registrarUso(
            dados.get("endereco", ""), dados.get("bairro", ""), dados.get("numero", ""), dados.get("cep", "")
        )
