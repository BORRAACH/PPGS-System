import base64
import os
import re
from datetime import datetime, timedelta

from PyQt6.QtCore import QByteArray, QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services import comandaParserService as parser
from services.comandaTextoService import PREFIXO_ADICIONAL, PREFIXO_BORDA
from services.rede import baixaComandas, indicePedidos, rede, relogio, tombstones

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

# Motivos de conflito gravados em pedidos/.sync/conflitos.json — ver
# services/rede/indicePedidos.py e a faixa amarela de PainelDetalhe.qml.
_CONFLITO_CONTEUDO = "conteudo_divergente"
_CONFLITO_APAGADA_FORA = "apagada_em_outra_maquina"

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
# "300 ML"/"500 ML"/"700 ML" são os tamanhos de Acai.qml (ver
# data/cardapio/acai.json) — sem eles aqui, os adicionais de um copo de
# açaí editado via Consulta perderiam a associação com o item ao reimprimir.
_TAMANHOS_VALIDOS = ("Grande", "Broto", "Mini", "300 ML", "500 ML", "700 ML")
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

        rede.registrarDominioSincronizado(
            "pedidos",
            self._resumo_pedidos,
            self._obter_pedido_reconciliacao,
            self._aplicar_pedido_reconciliacao,
            self._apagar_pedido_reconciliacao,
            self._comparar_pedido_reconciliacao,
        )

        self._migrar_atribuicoes_incorretas()

    def _codigo_impresso(self, nome_arquivo):
        """Só o código da linha "ID:" da comanda, sem o fallback pro sufixo
        do nome do arquivo que _codigo_comanda usa — aqui a primeira letra
        precisa ser mesmo a inicial da máquina que lançou a comanda (ver
        services/comandaSequencialService.py), e o sufixo aleatório não
        carrega essa informação."""
        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)
        try:
            with open(caminho, "rb") as arquivo:
                conteudo = arquivo.read()
        except OSError:
            return ""

        texto = conteudo.decode(parser.CODEPAGE_IMPRESSORA, errors="replace")
        return parser.extrair_campo(parser.PADRAO_ID_PEDIDO, parser.limpar_codigos_impressora(texto))

    def _migrar_atribuicoes_incorretas(self):
        """Descarta entradas do índice que dizem que esta máquina lançou uma
        comanda que na verdade veio de outra.

        Elas foram gravadas por uma versão em que receber uma comanda sem
        idEvento (de um peer ainda desatualizado) caía no mesmo caminho de
        criar uma comanda nova — ver indicePedidos.registrar_recebido. Além
        do rótulo errado na Consulta, o id inventado aqui não bate com o que
        a máquina de origem calcula pra mesma comanda: quando as duas
        versões se encontrarem, cada uma dessas comandas viraria um conflito
        falso, e o usuário teria que resolver na mão um por um.

        O critério é a inicial do código impresso, que identifica a máquina
        que lançou a comanda. Entradas sem código impresso (comandas
        antigas) ficam como estão — não há como julgar, e errar pro lado de
        preservar é o certo. Idempotente: rodar de novo não faz nada,
        porque o que sobra já é consistente."""
        indice = indicePedidos.carregar_indice()
        if not indice:
            return

        inicial_local = (rede.nomeLocal or "?")[:1].upper()
        incorretas = []
        for nome_arquivo, entrada in indice.items():
            if not isinstance(entrada, dict) or entrada.get("maquina") != rede.nomeLocal:
                continue
            codigo = self._codigo_impresso(nome_arquivo)
            if codigo and codigo[:1].upper() != inicial_local:
                incorretas.append(nome_arquivo)

        for nome_arquivo in incorretas:
            indicePedidos.remover(nome_arquivo)

        if incorretas:
            print(
                f"[ConsultaController] {len(incorretas)} comanda(s) estavam registradas como lançadas nesta "
                f"máquina mas vieram de outra — atribuição corrigida (ver indicePedidos.registrar_recebido)."
            )

    # ---------- Anti-entropy (ver services/rede/redeService.py:registrarDominioSincronizado) ----------

    def _nomes_comandas_locais(self):
        if not os.path.isdir(self.pasta_pedidos):
            return []
        return [nome for nome in os.listdir(self.pasta_pedidos) if nome.endswith(".txt")]

    def _resumo_pedidos(self):
        """A "versão" de cada comanda é o id de linha do tempo dela (ver
        services/rede/indicePedidos.py), não mais um hash do conteúdo: o
        hash só diz "igual ou diferente", e pra decidir um conflito é
        preciso saber qual das duas versões veio antes.

        A janela é recortada pela data embutida no NOME do arquivo, não pelo
        mtime. Com mtime, restaurar um backup, copiar a pasta sem preservar
        data ou um relógio errado deslocava a janela em silêncio — comandas
        de dias atrás voltavam a ser comparadas, e as de hoje podiam sair da
        janela."""
        nomes = self._nomes_comandas_locais()
        indicePedidos.purgar_ausentes(nomes)

        apagados = tombstones.carregar("pedidos")
        limite = (datetime.now() - timedelta(days=_JANELA_RECONCILIACAO_PEDIDOS_DIAS)).strftime("%Y%m%d")
        itens = {}
        for nome_arquivo in nomes:
            # Uma comanda pode existir em disco E ter tombstone: é o caso do
            # conflito "apagada em outra máquina, mas a versão daqui é mais
            # nova" (ver _aplicar_exclusao), em que o arquivo é mantido de
            # propósito à espera de decisão manual. Ela não entra no resumo
            # anunciado à malha — para a malha ela está apagada, e anunciar
            # as duas coisas ao mesmo tempo faria os peers ficarem pedindo e
            # reapagando a mesma chave a cada ciclo.
            if nome_arquivo in apagados:
                continue
            data = parser.data_arquivo_aaaammdd(nome_arquivo)
            if data is not None and data < limite:
                continue
            itens[nome_arquivo] = indicePedidos.id_evento(nome_arquivo)
        return {"itens": itens, "apagados": apagados}

    def _comparar_pedido_reconciliacao(self, nome_arquivo, id_local, id_peer):
        """Decide se vale puxar do peer a comanda `nome_arquivo`.

        Comanda é imutável: depois de salva, nunca é reescrita no lugar
        (editar pela Consulta apaga o arquivo e grava um novo, com outro
        nome — ver Balcao.qml/Entrega.qml). Então "o peer tem uma versão
        diferente da minha" nunca é uma atualização legítima, e sim uma
        divergência de verdade: as duas máquinas acham coisas diferentes
        sobre a mesma venda.

        Mesmo assim a versão divergente é puxada UMA vez — não pra
        sobrescrever nada (quem grava é aplicarPedidoRemoto, que se recusa a
        passar por cima de um arquivo existente), e sim pra ficar guardada
        junto do conflito: sem ela, a Consulta só poderia dizer "as duas
        máquinas discordam", sem mostrar o quê, e "adotar a versão da outra
        máquina" seria impossível. Depois de guardada, não se pede de novo —
        senão a cada 2 min a mesma comanda trafegaria pra sempre."""
        if id_local is None:
            return True

        if id_local == id_peer:
            return False

        conflito = indicePedidos.conflito(nome_arquivo)
        ja_guardada = (
            conflito is not None
            and conflito.get("idRemoto") == id_peer
            and bool(conflito.get("conteudoRemoto_b64"))
        )
        return not ja_guardada

    def _obter_pedido_reconciliacao(self, nome_arquivo):
        nome_arquivo = os.path.basename(nome_arquivo)
        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)
        try:
            with open(caminho, "rb") as arquivo:
                conteudo = arquivo.read()
        except OSError:
            return None
        return {
            "conteudo_b64": base64.b64encode(conteudo).decode("ascii"),
            "idEvento": indicePedidos.id_evento(nome_arquivo),
            "maquina": indicePedidos.maquina(nome_arquivo),
        }

    def _aplicar_pedido_reconciliacao(self, nome_arquivo, payload):
        payload = payload or {}
        conteudo_b64 = payload.get("conteudo_b64", "")
        if not conteudo_b64:
            return
        try:
            conteudo = base64.b64decode(conteudo_b64)
        except ValueError:
            return
        self.aplicarPedidoRemoto(
            nome_arquivo,
            QByteArray(conteudo),
            payload.get("idEvento", ""),
            payload.get("maquina", ""),
        )

    def _apagar_pedido_reconciliacao(self, nome_arquivo):
        # tombstones.mesclar já gravou o tombstone com o id de quem apagou
        # antes de chamar aqui, então dá pra lê-lo de volta e comparar com a
        # comanda local — é o que distingue "esta comanda foi apagada" de
        # "esta comanda foi criada DEPOIS da exclusão que acabei de aprender".
        quando = tombstones.carregar("pedidos").get(nome_arquivo, "")
        self._aplicar_exclusao(nome_arquivo, quando, ja_registrado=True)

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarComandas(self):
        """Lê todos os .txt salvos em pedidos/ e retorna seus dados já
        prontos para exibição (sem os códigos de controle da impressora),
        mais recentes primeiro."""
        os.makedirs(self.pasta_pedidos, exist_ok=True)

        conflitos = indicePedidos.carregar_conflitos()
        nomes_maquinas = self._nomes_maquinas_conhecidas()
        # Uma leitura só do mapa de baixas pra lista inteira — o mesmo
        # cuidado que já vale pra `conflitos` acima. Consultar
        # baixaComandas.esta_fechada() por comanda releria o JSON a cada
        # volta do laço.
        baixas = baixaComandas.carregar()

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
            codigo = parser.codigo_comanda(nome_arquivo, conteudo)
            conflito = conflitos.get(nome_arquivo) or {}
            cliente = parser.extrair_campo(parser.PADRAO_CLIENTE, conteudo)

            comandas.append({
                "arquivo": nome_arquivo,
                "tipo": tipo,
                "conteudo": conteudo,
                "cliente": cliente,
                "dataHora": parser.extrair_campo(parser.PADRAO_DATA, conteudo),
                "modificadoEm": modificado_em,
                "codigo": codigo,
                # Aberta (ainda não conferida, fora do caixa) x fechada (com
                # baixa dada, contando no fechamento do dia) — ver
                # services/rede/baixaComandas.py. Sem registro = aberta.
                "fechada": nome_arquivo in baixas,
                "maquinaOrigem": self._maquina_origem(nome_arquivo, codigo, nomes_maquinas),
                "emConflito": bool(conflito),
                "motivoConflito": conflito.get("motivo", ""),
                "maquinaConflito": conflito.get("maquinaRemota", ""),
                # Borda vermelha em ItemComandaDelegate.qml — ver
                # comandaParserService.eh_suspeita. Calculado independente
                # de aberta/fechada: um erro de digitação vale a pena
                # sinalizar assim que a comanda existe, não só depois de
                # baixada (diferente do fechamento, que só soma o que já
                # tem baixa).
                "suspeita": parser.eh_suspeita(
                    tipo,
                    cliente,
                    parser.extrair_campo(parser.PADRAO_FORMA_PAGAMENTO, conteudo),
                    parser.extrair_status_pagamento(conteudo),
                    parser.extrair_campo(parser.PADRAO_ENDERECO, conteudo),
                ),
            })

        comandas.sort(key=lambda c: c["modificadoEm"], reverse=True)
        return comandas

    def _nomes_maquinas_conhecidas(self):
        """Toda máquina que esta instância já viu na malha — não só as
        conectadas agora.

        Sai dos ids de linha do tempo já gravados em disco: todo id termina
        no nome da máquina que o gerou (ver services/rede/relogio.py), então
        o índice de comandas e o registro de exclusões, somados, são um
        histórico das máquinas que participaram desta malha. Isso importa
        porque a conferência manual entre duas máquinas costuma acontecer
        justamente quando uma delas está fora do ar — se a lista fosse só a
        dos peers conectados, a coluna "máquina de origem" ficaria vazia
        exatamente na hora em que ela é útil."""
        nomes = [rede.nomeLocal]

        def acrescentar(nome):
            if nome and nome not in nomes:
                nomes.append(nome)

        for peer in rede.listarPeers():
            acrescentar(peer.get("nome"))
        for entrada in indicePedidos.carregar_indice().values():
            if isinstance(entrada, dict):
                acrescentar(entrada.get("maquina"))
        for quando in tombstones.carregar("pedidos").values():
            acrescentar(relogio.maquina_do_id(quando))

        return nomes

    def _maquina_origem(self, nome_arquivo, codigo, nomes_maquinas):
        """Máquina onde a comanda foi lançada. Vem do índice de eventos
        quando existe; nas comandas antigas (anteriores ao índice) sobra a
        primeira letra do código impresso, que é justamente a inicial do
        nome da máquina (ver services/comandaSequencialService.py) — resolve
        enquanto essa inicial for única entre as máquinas conhecidas, e
        devolve "" quando for ambígua, em vez de chutar."""
        maquina = indicePedidos.maquina(nome_arquivo)
        if maquina:
            return maquina

        if not codigo:
            return ""

        inicial = codigo[:1].upper()
        candidatos = [nome for nome in nomes_maquinas if nome[:1].upper() == inicial]
        return candidatos[0] if len(candidatos) == 1 else ""

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
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
    @protegido(False)
    def apagarComanda(self, nome_arquivo):
        """Remove o .txt da comanda. Retorna True em caso de sucesso."""
        nome_arquivo = os.path.basename(nome_arquivo)
        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)

        try:
            os.remove(caminho)
        except OSError as erro:
            print(f"Falha ao apagar {caminho}: {erro}")
            return False

        # O id do tombstone viaja junto na exclusão pra que todas as
        # máquinas gravem a MESMA marca de tempo pra este apagamento — sem
        # isso, cada uma registraria "quando eu soube", e comparar a
        # exclusão com a criação da comanda (ver _aplicar_exclusao) daria
        # respostas diferentes em cada máquina.
        quando = tombstones.registrar("pedidos", nome_arquivo)
        indicePedidos.remover(nome_arquivo)
        indicePedidos.resolver_conflito(nome_arquivo)
        rede.transmitir_exclusao(nome_arquivo, quando)
        return True

    @pyqtSlot(str, QByteArray, str, str)
    @protegido()
    def aplicarPedidoRemoto(self, nome_arquivo, conteudo, id_evento="", maquina=""):
        """Grava localmente um pedido recebido de outra máquina da rede e
        avisa a tela de Consulta para recarregar a lista."""
        nome_arquivo = os.path.basename(nome_arquivo)

        # Uma comanda apagada aqui não pode voltar por um anúncio de um peer
        # que ainda não soube da exclusão — o mesmo cuidado que
        # SalaoController._ao_receber_mesa_remota já tinha e que faltava
        # aqui. Sem isto a comanda ressuscitava e a máquina ficava num
        # estado que nada corrigia: o arquivo de volta em pedidos/ (contando
        # no caixa do dia) e a chave ainda listada como apagada no resumo de
        # reconciliação, sem nenhum peer capaz de desempatar.
        if nome_arquivo in tombstones.carregar("pedidos"):
            print(f"[ConsultaController] Ignorando '{nome_arquivo}' recebido da rede: foi apagado aqui.")
            return

        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)
        os.makedirs(self.pasta_pedidos, exist_ok=True)

        # Comanda que já existe aqui com outro conteúdo não é sobrescrita:
        # vira conflito pra decisão manual (ver
        # _comparar_pedido_reconciliacao).
        if os.path.isfile(caminho):
            id_local = indicePedidos.id_evento(nome_arquivo)
            if id_evento and id_local and id_evento != id_local:
                indicePedidos.registrar_conflito(
                    nome_arquivo,
                    _CONFLITO_CONTEUDO,
                    id_local=id_local,
                    id_remoto=id_evento,
                    maquina_remota=maquina or relogio.maquina_do_id(id_evento),
                    conteudo_remoto_b64=base64.b64encode(bytes(conteudo)).decode("ascii"),
                )
                self.comandasAtualizadas.emit()
            return

        try:
            with open(caminho, "wb") as arquivo:
                arquivo.write(bytes(conteudo))
        except OSError as erro:
            print(f"Falha ao salvar pedido recebido da rede em {caminho}: {erro}")
            return

        indicePedidos.registrar_recebido(nome_arquivo, id_evento, maquina)
        self.comandasAtualizadas.emit()

    @pyqtSlot(str, str)
    @protegido()
    def removerPedidoRemoto(self, nome_arquivo, id_evento=""):
        """Apaga localmente um pedido removido em outra máquina da rede e
        avisa a tela de Consulta para recarregar a lista."""
        self._aplicar_exclusao(os.path.basename(nome_arquivo), id_evento)

    def _aplicar_exclusao(self, nome_arquivo, quando, ja_registrado=False):
        """Aplica uma exclusão aprendida de outra máquina, comparando-a com
        a comanda local pela linha do tempo comum.

        Se a comanda daqui é MAIS NOVA que a exclusão, apagar seria perder
        uma venda: significa que ela foi criada depois que aquela exclusão
        aconteceu (duas máquinas sortearam o mesmo nome de arquivo, ou uma
        delas estava com o relógio muito fora). Nesse caso o arquivo fica, e
        a comanda é marcada como conflito pra que alguém decida — nunca se
        apaga comanda automaticamente com base num empate duvidoso.

        O tombstone é registrado nos dois casos: todo nó que aprende de uma
        exclusão precisa lembrar dela (senão um terceiro nó desatualizado a
        reintroduz mais tarde através deste), e mantê-lo também impede que o
        mesmo conflito seja reprocessado a cada ciclo de anti-entropy."""
        if not ja_registrado:
            quando = tombstones.registrar("pedidos", nome_arquivo, quando or None)

        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)
        id_local = indicePedidos.id_evento(nome_arquivo) if os.path.isfile(caminho) else ""

        if id_local and relogio.mais_novo(id_local, quando):
            indicePedidos.registrar_conflito(
                nome_arquivo,
                _CONFLITO_APAGADA_FORA,
                id_local=id_local,
                id_remoto=quando,
                maquina_remota=relogio.maquina_do_id(quando),
            )
            self.comandasAtualizadas.emit()
            return

        try:
            os.remove(caminho)
        except OSError:
            pass

        indicePedidos.remover(nome_arquivo)
        indicePedidos.resolver_conflito(nome_arquivo)
        self.comandasAtualizadas.emit()

    # ---------- Resolução manual de conflito (ver PainelDetalhe.qml) ----------

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
    def detalheConflito(self, nome_arquivo):
        """Dados do conflito de uma comanda, pra faixa amarela da Consulta:
        motivo, máquina divergente, e — quando houver — a versão da outra
        máquina já legível em tela, pra dar pra comparar antes de decidir."""
        conflito = indicePedidos.conflito(os.path.basename(nome_arquivo))
        if conflito is None:
            return {}

        conteudo_remoto = ""
        b64 = conflito.get("conteudoRemoto_b64", "")
        if b64:
            try:
                bruto = base64.b64decode(b64)
            except ValueError:
                bruto = b""
            if bruto:
                texto = bruto.decode(parser.CODEPAGE_IMPRESSORA, errors="replace")
                conteudo_remoto = parser.limpar_codigos_impressora(texto).strip("\n")

        return {
            "arquivo": os.path.basename(nome_arquivo),
            "motivo": conflito.get("motivo", ""),
            "maquinaRemota": conflito.get("maquinaRemota", ""),
            "conteudoRemoto": conteudo_remoto,
            "temVersaoRemota": bool(conteudo_remoto),
        }

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def manterVersaoLocal(self, nome_arquivo):
        """Confirma a versão desta máquina e reanuncia a comanda à malha.

        No conflito de exclusão isso também desfaz o tombstone local: era
        ele que mantinha a comanda fora do resumo anunciado aos peers, e sem
        removê-lo a decisão do usuário não sairia daqui."""
        nome_arquivo = os.path.basename(nome_arquivo)
        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)

        try:
            with open(caminho, "rb") as arquivo:
                conteudo = arquivo.read()
        except OSError as erro:
            print(f"Falha ao reler {caminho} para manter a versão local: {erro}")
            return False

        tombstones.remover("pedidos", nome_arquivo)
        indicePedidos.resolver_conflito(nome_arquivo)
        rede.transmitir_pedido(nome_arquivo, conteudo)
        self.comandasAtualizadas.emit()
        return True

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def adotarVersaoRemota(self, nome_arquivo):
        """Aceita a versão da outra máquina no lugar da desta.

        Só faz sentido no conflito de conteúdo divergente, onde a versão
        remota foi guardada junto do registro do conflito. No conflito de
        exclusão não há conteúdo remoto nenhum — a "versão da outra máquina"
        é a comanda não existir —, então adotar equivale a apagar aqui, que
        é o que este caminho faz."""
        nome_arquivo = os.path.basename(nome_arquivo)
        conflito = indicePedidos.conflito(nome_arquivo)
        if conflito is None:
            return False

        b64 = conflito.get("conteudoRemoto_b64", "")
        if not b64:
            return self.apagarComanda(nome_arquivo)

        try:
            conteudo = base64.b64decode(b64)
        except ValueError:
            return False

        caminho = os.path.join(self.pasta_pedidos, nome_arquivo)
        try:
            with open(caminho, "wb") as arquivo:
                arquivo.write(conteudo)
        except OSError as erro:
            print(f"Falha ao gravar a versão remota em {caminho}: {erro}")
            return False

        indicePedidos.registrar_recebido(nome_arquivo, conflito.get("idRemoto", ""), conflito.get("maquinaRemota", ""))
        indicePedidos.resolver_conflito(nome_arquivo)
        self.comandasAtualizadas.emit()
        return True
