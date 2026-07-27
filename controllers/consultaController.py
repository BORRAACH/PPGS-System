import base64
import hashlib
import os
import re
import time

from PyQt6.QtCore import QByteArray, QObject, pyqtSignal, pyqtSlot

from services import comandaParserService as parser
from services.comandaTextoService import PREFIXO_ADICIONAL, PREFIXO_BORDA
from services.rede import rede, tombstones

# Janela (em dias) que o resumo periódico de anti-entropy compara pra este
# domínio (ver _resumo_pedidos/RedeService.registrarDominioSincronizado) —
# cobre o caso de uma mensagem se perder durante uma conexão contínua
# (raro; TCP não perde mensagem no meio de uma conexão viva, mas um bug
# de aplicação pode). Histórico mais antigo continua garantido pelo
# catch-up de handshake existente (meus_arquivos/pedir_arquivo, sem
# limite de janela), que roda a cada reconexão, não só periodicamente —
# sem essa janela aqui, o resumo comparado a cada ciclo cresceria pra
# sempre conforme o volume de pedidos aumentasse ao longo dos anos.
_JANELA_RECONCILIACAO_PEDIDOS_DIAS = 7

# Extraem os campos do cabeçalho do cupom (ver balcaoController/
# entregaController) para reconstruir os dados ao editar, sem depender do
# nome do arquivo. Cliente/Data/Forma de pagamento/Status/Valor total vivem
# em services/comandaParserService.py (compartilhados com
# FechamentoController) — só os campos exclusivos de Entrega (usados apenas
# por reconstruirComanda, pra reabrir a comanda num formulário editável)
# continuam aqui.
_PADRAO_TELEFONE = re.compile(r"^Telefone:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_ENDERECO = re.compile(r"^Endereço:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_BAIRRO = re.compile(r"^Bairro:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_OBSERVACAO_GERAL = re.compile(r"^Observação:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_TROCO = re.compile(r"^Troco para:[ \t]*(.*)$", re.MULTILINE)
_PADRAO_TAXA_ENTREGA = re.compile(r"^Taxa de entrega:[ \t]*(.*)$", re.MULTILINE)

# Linha de um item na tabela do cupom: "coluna_pedido | valor". A observação
# (quando houver) vem numa linha própria logo abaixo, recuada com 2 espaços
# (ver balcaoController/entregaController._formatarTabela).
_PADRAO_LINHA_TABELA = re.compile(r"^(.*)\|(.*)$")
_PADRAO_LINHA_OBSERVACAO = re.compile(r"^  (.+)$")
# Linhas de adicional/borda (ver comandaTextoService.montar_grupos) — casadas
# ANTES de _PADRAO_LINHA_OBSERVACAO (que bateria com qualquer uma delas
# também, por ser só "recuo + texto"), senão um adicional/borda vira
# observação na reconstrução.
_PADRAO_LINHA_ADICIONAL = re.compile(r"^  " + re.escape(PREFIXO_ADICIONAL) + r"(.+?)(?: \((.+)\))?$")
_PADRAO_LINHA_BORDA = re.compile(r"^  " + re.escape(PREFIXO_BORDA) + r"(.+?)(?: \((.+)\))?$")
# Fração de sabor de pizza meio a meio: "1/3 - Nome do Sabor".
_PADRAO_FRACAO_SABOR = re.compile(r"^\d+/\d+ - (.+)$")
# Sufixo de tamanho no primeiro sabor: "Nome do Sabor (Grande)".
_PADRAO_SUFIXO_TAMANHO = re.compile(r"^(.*)\s\(([^)]+)\)$")
# balcaoController/entregaController agora imprimem o nome do item em caixa
# alta (ex: "(GRANDE)"), então a comparação precisa ignorar maiúsculas/
# minúsculas para continuar reconhecendo o sufixo em comandas antigas e novas.
_TAMANHOS_VALIDOS = ("Grande", "Broto", "Mini")
_TAMANHOS_VALIDOS_UPPER = tuple(t.upper() for t in _TAMANHOS_VALIDOS)


def _dividir_endereco_numero(endereco_completo):
    """Desfaz o "Endereço, Número" montado por entregaController.enviarPedido."""
    if not endereco_completo:
        return "", ""

    partes = endereco_completo.rsplit(",", 1)
    if len(partes) == 2 and partes[1].strip():
        return partes[0].strip(), partes[1].strip()

    return endereco_completo.strip(), ""


def _reconstruir_itens(linhas_tabela):
    """Desfaz comandaTextoService.montar_grupos/formatar_tabela: volta das
    linhas já formatadas do cupom para a lista de itens (pedido, observação,
    valor, borda, adicionais) como ficavam em modeloPedidos antes de
    imprimir."""
    itens = []
    grupo_atual = []
    # Borda é um extra de nível de grupo (a pizza inteira), não de uma fração
    # específica — por isso fica fora de grupo_atual, num estado à parte que
    # fechar_grupo() consome e reseta.
    borda_atual = {"nome": "", "valor": ""}

    def fechar_grupo():
        if not grupo_atual:
            return

        borda = {"nome": borda_atual["nome"], "valor": borda_atual["valor"]} if borda_atual["nome"] else None

        if len(grupo_atual) == 1:
            coluna_pedido, observacao, valor, adicionais = grupo_atual[0]
            pedido = coluna_pedido[2:] if coluna_pedido.startswith("- ") else coluna_pedido
            # O adicional foi salvo (em Pizzas.qml) com o nome do sabor SEM o
            # sufixo de tamanho — precisa desfazer o mesmo sufixo aqui para
            # que "sabor" volte a bater com o nome usado ao reimprimir.
            sabor_sem_tamanho = pedido
            match_tamanho = _PADRAO_SUFIXO_TAMANHO.match(pedido)
            if match_tamanho and match_tamanho.group(2).strip().upper() in _TAMANHOS_VALIDOS_UPPER:
                sabor_sem_tamanho = match_tamanho.group(1)
            for adicional in adicionais:
                adicional["sabor"] = sabor_sem_tamanho
            itens.append({
                "pedido": pedido,
                "observacao": observacao,
                "valor": valor,
                "borda": borda,
                "adicionais": adicionais,
            })
        else:
            sabores = []
            tamanho = ""
            observacao_final = ""
            valor_final = ""
            adicionais_totais = []
            for indice, (coluna_pedido, observacao, valor, adicionais) in enumerate(grupo_atual):
                match_fracao = _PADRAO_FRACAO_SABOR.match(coluna_pedido)
                nome = match_fracao.group(1) if match_fracao else coluna_pedido
                if indice == 0:
                    match_tamanho = _PADRAO_SUFIXO_TAMANHO.match(nome)
                    if match_tamanho and match_tamanho.group(2).strip().upper() in _TAMANHOS_VALIDOS_UPPER:
                        nome = match_tamanho.group(1)
                        tamanho = match_tamanho.group(2)
                    valor_final = valor
                # A observação do grupo agora é impressa depois de TODAS as
                # frações (ver formatar_tabela), então fica anexada à última
                # fração lida, não necessariamente à primeira.
                if observacao:
                    observacao_final = observacao
                for adicional in adicionais:
                    adicional["sabor"] = nome
                adicionais_totais.extend(adicionais)
                sabores.append(nome)

            pedido = " / ".join(sabores)
            if tamanho:
                pedido += f" ({tamanho})"
            itens.append({
                "pedido": pedido,
                "observacao": observacao_final,
                "valor": valor_final,
                "borda": borda,
                "adicionais": adicionais_totais,
            })

        grupo_atual.clear()
        borda_atual["nome"] = ""
        borda_atual["valor"] = ""

    for linha in linhas_tabela:
        if linha.strip() == "":
            fechar_grupo()
            continue

        # Adicional (recuado, "+ ..."), pertence à fração imediatamente
        # acima dele dentro do grupo atual.
        match_adicional = _PADRAO_LINHA_ADICIONAL.match(linha)
        if match_adicional and grupo_atual:
            _coluna_pedido, _observacao, _valor, adicionais = grupo_atual[-1]
            adicionais.append({
                "nome": match_adicional.group(1).strip(),
                "valor": (match_adicional.group(2) or "").strip(),
            })
            continue

        # Borda (recuada, "* ..."), pertence ao grupo inteiro — só pode
        # haver uma por pizza (ver PopupAdicionaisBordas.qml).
        match_borda = _PADRAO_LINHA_BORDA.match(linha)
        if match_borda and grupo_atual:
            borda_atual["nome"] = match_borda.group(1).strip()
            borda_atual["valor"] = (match_borda.group(2) or "").strip()
            continue

        # Linha de observação (recuada), pertence ao pedido imediatamente
        # acima dela dentro do grupo atual.
        match_observacao = _PADRAO_LINHA_OBSERVACAO.match(linha)
        if match_observacao and grupo_atual:
            coluna_pedido, _observacao_antiga, valor, adicionais = grupo_atual[-1]
            grupo_atual[-1] = (coluna_pedido, match_observacao.group(1).strip(), valor, adicionais)
            continue

        match_linha = _PADRAO_LINHA_TABELA.match(linha)
        if not match_linha:
            continue

        coluna_pedido, valor = (g.strip() for g in match_linha.groups())
        grupo_atual.append((coluna_pedido, "", valor, []))

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
        # Cache de hash por arquivo pra _resumo_pedidos não precisar reler e
        # rehashear todo pedido a cada ciclo de reconciliação — pedidos são
        # imutáveis (só criados ou apagados, nunca editados no lugar), então
        # (mtime, size) muda no máximo uma vez na vida do arquivo.
        self._cache_hash_pedidos = {}  # nome_arquivo -> ((mtime, size), hash)

        rede.registrarDominioSincronizado(
            "pedidos",
            self._resumo_pedidos,
            self._obter_pedido_reconciliacao,
            self._aplicar_pedido_reconciliacao,
            self._apagar_pedido_reconciliacao,
        )

    # ---------- Anti-entropy (ver services/rede/redeService.py:registrarDominioSincronizado) ----------

    def _resumo_pedidos(self):
        limite = time.time() - _JANELA_RECONCILIACAO_PEDIDOS_DIAS * 86400
        itens = {}
        if os.path.isdir(self.pasta_pedidos):
            for nome_arquivo in os.listdir(self.pasta_pedidos):
                if not nome_arquivo.endswith(".txt"):
                    continue
                caminho = os.path.join(self.pasta_pedidos, nome_arquivo)
                try:
                    info = os.stat(caminho)
                except OSError:
                    continue
                if info.st_mtime < limite:
                    continue
                itens[nome_arquivo] = self._hash_pedido(nome_arquivo, caminho, info)
        return {"itens": itens, "apagados": tombstones.carregar("pedidos")}

    def _hash_pedido(self, nome_arquivo, caminho, info):
        chave_cache = (info.st_mtime, info.st_size)
        em_cache = self._cache_hash_pedidos.get(nome_arquivo)
        if em_cache and em_cache[0] == chave_cache:
            return em_cache[1]

        try:
            with open(caminho, "rb") as arquivo:
                conteudo = arquivo.read()
        except OSError:
            return ""

        digest = hashlib.sha256(conteudo).hexdigest()[:16]
        self._cache_hash_pedidos[nome_arquivo] = (chave_cache, digest)
        return digest

    def _obter_pedido_reconciliacao(self, nome_arquivo):
        caminho = os.path.join(self.pasta_pedidos, os.path.basename(nome_arquivo))
        try:
            with open(caminho, "rb") as arquivo:
                conteudo = arquivo.read()
        except OSError:
            return None
        return {"conteudo_b64": base64.b64encode(conteudo).decode("ascii")}

    def _aplicar_pedido_reconciliacao(self, nome_arquivo, payload):
        conteudo_b64 = (payload or {}).get("conteudo_b64", "")
        if not conteudo_b64:
            return
        try:
            conteudo = base64.b64decode(conteudo_b64)
        except ValueError:
            return
        self.aplicarPedidoRemoto(nome_arquivo, QByteArray(conteudo))

    def _apagar_pedido_reconciliacao(self, nome_arquivo):
        self.removerPedidoRemoto(nome_arquivo)

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

            conteudo = conteudo_bytes.decode(parser.CODEPAGE_IMPRESSORA, errors="replace")
            conteudo = parser.limpar_codigos_impressora(conteudo).strip("\n")
            tipo = parser.tipo_comanda(nome_arquivo)

            comandas.append({
                "arquivo": nome_arquivo,
                "tipo": tipo,
                "conteudo": conteudo,
                "cliente": parser.extrair_campo(parser.PADRAO_CLIENTE, conteudo),
                "dataHora": parser.extrair_campo(parser.PADRAO_DATA, conteudo),
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

        conteudo = conteudo_bytes.decode(parser.CODEPAGE_IMPRESSORA, errors="replace")
        conteudo = parser.limpar_codigos_impressora(conteudo)
        linhas = conteudo.split("\n")

        divisorias = [i for i, linha in enumerate(linhas) if linha.startswith("----")]
        if len(divisorias) < 2:
            return {}

        linhas_tabela = linhas[divisorias[0] + 1:divisorias[1]]
        endereco_completo = parser.extrair_campo(_PADRAO_ENDERECO, conteudo)
        endereco, numero = _dividir_endereco_numero(endereco_completo)

        return {
            "arquivo": nome_arquivo,
            "tipo": parser.tipo_comanda(nome_arquivo),
            "cliente": parser.extrair_campo(parser.PADRAO_CLIENTE, conteudo),
            "telefone": parser.extrair_campo(_PADRAO_TELEFONE, conteudo),
            "endereco": endereco,
            "numero": numero,
            "bairro": parser.extrair_campo(_PADRAO_BAIRRO, conteudo),
            "observacaoGeral": parser.extrair_campo(_PADRAO_OBSERVACAO_GERAL, conteudo),
            "formaPagamento": parser.extrair_campo(parser.PADRAO_FORMA_PAGAMENTO, conteudo),
            "troco": parser.extrair_campo(_PADRAO_TROCO, conteudo),
            "taxaEntrega": parser.extrair_campo(_PADRAO_TAXA_ENTREGA, conteudo),
            "statusPagamento": parser.extrair_status_pagamento(conteudo),
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

        tombstones.registrar("pedidos", nome_arquivo)
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

        # Todo nó que APRENDE de uma exclusão precisa lembrar dela, não só
        # quem apagou originalmente (ver services/rede/tombstones.py) —
        # senão um terceiro nó ainda desatualizado pode reintroduzi-la mais
        # tarde através deste aqui.
        tombstones.registrar("pedidos", nome_arquivo)
        self.comandasAtualizadas.emit()
