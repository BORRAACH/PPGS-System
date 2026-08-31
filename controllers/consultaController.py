import base64
import os
from datetime import datetime, timedelta

from PyQt6.QtCore import QByteArray, QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services import comandaComparacaoService as comparacao
from services import comandaParserService as parser
from services.rede import baixaComandas, historicoEventos, indicePedidos, rede, relogio, tombstones

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
        self._revalidar_conflitos()

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

    def _revalidar_conflitos(self):
        """Descarta os conflitos que a regra antiga gravou sem olhar conteúdo.

        Até aqui bastava o idEvento local diferir do recebido para a comanda
        ser marcada como divergente — e como `indicePedidos.id_evento` cai num
        id sintetizado do nome do arquivo quando não há registro em
        eventos.json, uma máquina com o id real e outra com o sintético
        marcavam como divergente uma comanda byte a byte idêntica. Só corrigir
        a regra não bastaria: os conflitos já gravados continuariam em disco, e
        a Consulta seguiria mostrando em amarelo comandas que nunca
        divergiram.

        Reexamina cada um comparando de verdade as duas versões (a local e a
        que ficou guardada junto do conflito) e apaga os que não têm diferença
        nenhuma. Os que têm ficam, para decisão manual — nenhuma comanda é
        alterada aqui, só o registro de conflito. Idempotente: rodar de novo
        não faz nada, porque o que sobra é conflito de verdade."""
        conflitos = indicePedidos.carregar_conflitos()
        if not conflitos:
            return

        resolvidos = 0
        for nome_arquivo, conflito in conflitos.items():
            if not isinstance(conflito, dict) or conflito.get("motivo") != _CONFLITO_CONTEUDO:
                continue

            conteudo_remoto_b64 = conflito.get("conteudoRemoto_b64", "")
            if not conteudo_remoto_b64:
                continue

            caminho = os.path.join(self.pasta_pedidos, nome_arquivo)
            try:
                with open(caminho, "rb") as arquivo:
                    conteudo_local = arquivo.read()
                conteudo_remoto = base64.b64decode(conteudo_remoto_b64)
            except (OSError, ValueError):
                continue

            if comparacao.diferencas_entre(conteudo_local, conteudo_remoto, nome_arquivo):
                continue

            indicePedidos.resolver_conflito(nome_arquivo)
            resolvidos += 1

        if resolvidos:
            print(
                f"[ConsultaController] {resolvidos} comanda(s) estavam marcadas como divergentes mas têm "
                f"conteúdo idêntico nas duas máquinas — marcação removida (ver comandaComparacaoService)."
            )

    # ---------- Anti-entropy (ver services/rede/redeService.py:registrarDominioSincronizado) ----------

    def _nomes_comandas_locais(self):
        if not os.path.isdir(self.pasta_pedidos):
            return []
        return [nome for nome in os.listdir(self.pasta_pedidos) if nome.endswith(".txt")]

    def _resumo_pedidos(self):
        """A "versão" de cada comanda é o id de linha do tempo dela MAIS a
        impressão digital do conteúdo (ver indicePedidos.versao).

        O id sozinho responde "qual veio antes", que é o que decide um
        conflito — mas não responde "o conteúdo é o mesmo?". Enquanto a
        versão era só o id, duas máquinas com o mesmo id e conteúdos
        diferentes se declaravam iguais, a reconciliação não puxava nada e a
        divergência ficava invisível. A impressão junto cobre esse caso sem
        perder a ordenação.

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
        # Uma leitura só do índice de eventos pra varredura inteira — sem
        # isto, indicePedidos.versao() releria eventos.json duas vezes por
        # comanda, e este laço roda a cada ciclo de anti-entropy (ver
        # indicePedidos.varredura). Mesmo cuidado que listarComandas já toma
        # com `conflitos` e `baixas`.
        with indicePedidos.varredura():
            for nome_arquivo in nomes:
                # Uma comanda pode existir em disco E ter tombstone: é o caso
                # do conflito "apagada em outra máquina, mas a versão daqui é
                # mais nova" (ver _aplicar_exclusao), em que o arquivo é
                # mantido de propósito à espera de decisão manual. Ela não
                # entra no resumo anunciado à malha — para a malha ela está
                # apagada, e anunciar as duas coisas ao mesmo tempo faria os
                # peers ficarem pedindo e reapagando a mesma chave a cada
                # ciclo.
                if nome_arquivo in apagados:
                    continue
                data = parser.data_arquivo_aaaammdd(nome_arquivo)
                if data is not None and data < limite:
                    continue
                itens[nome_arquivo] = indicePedidos.versao(nome_arquivo)
        return {"itens": itens, "apagados": apagados}

    def _comparar_pedido_reconciliacao(self, nome_arquivo, versao_local, versao_peer):
        """Decide se vale puxar do peer a comanda `nome_arquivo`.

        Só o transporte decide aqui; quem julga o que fazer com o conteúdo é
        aplicarPedidoRemoto. Versões diferentes (id ou impressão digital, ver
        indicePedidos.versao) significam que há algo a olhar — pode ser uma
        divergência real de valores, ou só um id fora de sincronia numa
        comanda idêntica, e não dá pra saber sem o conteúdo em mãos.

        A guarda contra repetir o download existe porque a anti-entropy roda
        a cada 2 min: uma vez que a versão do peer já está guardada junto do
        conflito, pedir de novo faria a mesma comanda trafegar para sempre."""
        if versao_local is None:
            return True

        if versao_local == versao_peer:
            return False

        id_peer, _impressao_peer = indicePedidos.partes_da_versao(versao_peer)
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

    # ---------- Listagem para a tela de Consulta ----------
    #
    # A tela abre mostrando só os últimos dias e deixa os anteriores como
    # caixinhas fechadas, que só leem o disco quando alguém as abre (ver
    # qml/pages/consulta/Consulta.qml, janelaCargaDias). Daí os três métodos
    # abaixo em vez de um `listarComandas()` só:
    #
    #   listarComandasRecentes  — o que a tela mostra de cara;
    #   listarDiasAnteriores    — só o rótulo e a contagem de cada dia velho;
    #   listarComandasDoDia     — o conteúdo de um dia, pedido no clique.
    #
    # O que torna isso possível é a data estar no NOME do arquivo
    # ("entrega_20260731_220856_28213d.txt", ver
    # comandaParserService.data_arquivo_aaaammdd): dá pra separar os dias, e
    # contar quantas comandas cada um tem, sem abrir arquivo nenhum. Só
    # `_montar_comandas` abre — e é ela que custa, porque por comanda são uma
    # leitura de disco, uma decodificação do cupom inteiro e meia dúzia de
    # regex sobre ele. Antes, abrir a Consulta pagava isso pelo acervo
    # INTEIRO, que só cresce e nunca diminui; agora paga por dois dias.

    def _limite_aaaammdd(self, dias):
        """A data mais antiga (como "AAAAMMDD") que ainda conta como recente.

        Mesma convenção da janela de busca em Consulta.qml: `dias` é quantos
        dias PARA TRÁS a janela alcança, então hoje mais eles — com dias=2,
        hoje, ontem e anteontem."""
        return (datetime.now() - timedelta(days=max(0, int(dias)))).strftime("%Y%m%d")

    def _dia_formatado(self, aaaammdd):
        """"20260731" -> "31/07/2026", o mesmo formato do cabeçalho do cupom
        (e o que Consulta.qml usa como chave de agrupamento)."""
        return f"{aaaammdd[6:8]}/{aaaammdd[4:6]}/{aaaammdd[0:4]}"

    def _eh_recente(self, nome_arquivo, limite):
        """Comanda sem data no nome (arquivo de origem desconhecida) conta
        como recente de propósito: não dá pra julgar a idade dela, e a pior
        das duas decisões é a que a esconde dentro de uma caixinha de dia que
        ninguém sabe qual é. Mesmo critério que a tela já aplica à comanda sem
        "Data:" no cabeçalho, jogando-a em "hoje"."""
        data = parser.data_arquivo_aaaammdd(nome_arquivo)
        return data is None or data >= limite

    @pyqtSlot(int, result="QVariantList")
    @protegido([])
    def listarComandasRecentes(self, dias):
        """As comandas dos últimos `dias` dias, mais recentes primeiro.

        É o que a Consulta carrega ao abrir, e também a janela que a barra de
        pesquisa alcança (com um `dias` maior, e só na primeira tecla
        digitada — ver Consulta.qml, _prepararIndiceBusca)."""
        limite = self._limite_aaaammdd(dias)
        return self._montar_comandas(
            [nome for nome in self._nomes_comandas_locais() if self._eh_recente(nome, limite)]
        )

    @pyqtSlot(int, result="QVariantList")
    @protegido([])
    def listarDiasAnteriores(self, dias):
        """Os dias mais antigos que a janela de `dias`, do mais recente pro
        mais antigo: [{"dia": "31/07/2026", "chave": "20260731",
        "quantidade": 12, "fechadas": 9}].

        Não abre comanda nenhuma — a data sai do nome do arquivo e as baixas
        de uma leitura só do mapa de fechadas. É o que deixa a tela desenhar a
        caixinha de cada dia (com a contagem certa, inclusive sob o filtro
        Abertas/Fechadas) sem pagar pelo conteúdo de nenhum deles."""
        limite = self._limite_aaaammdd(dias)
        baixas = baixaComandas.carregar()

        dias_antigos = {}
        for nome_arquivo in self._nomes_comandas_locais():
            if self._eh_recente(nome_arquivo, limite):
                continue
            data = parser.data_arquivo_aaaammdd(nome_arquivo)
            contagem = dias_antigos.setdefault(data, {"quantidade": 0, "fechadas": 0})
            contagem["quantidade"] += 1
            if nome_arquivo in baixas:
                contagem["fechadas"] += 1

        return [
            {
                "dia": self._dia_formatado(data),
                "chave": data,
                "quantidade": contagem["quantidade"],
                "fechadas": contagem["fechadas"],
            }
            for data, contagem in sorted(dias_antigos.items(), reverse=True)
        ]

    @pyqtSlot(str, result="QVariantList")
    @protegido([])
    def listarComandasDoDia(self, chave):
        """As comandas de UM dia ("AAAAMMDD", a `chave` que
        listarDiasAnteriores devolveu). Chamado quando a caixinha do dia é
        aberta na tela, e não antes."""
        return self._montar_comandas(
            [
                nome
                for nome in self._nomes_comandas_locais()
                if parser.data_arquivo_aaaammdd(nome) == chave
            ]
        )

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarComandas(self):
        """Todas as comandas de pedidos/, sem janela nenhuma.

        A tela NÃO usa mais este caminho (ver listarComandasRecentes) — ele
        ficou para quem precisa mesmo do acervo inteiro e não tem interface
        pra travar, como docker/apagar_pedido_teste.py."""
        return self._montar_comandas(self._nomes_comandas_locais())

    def _montar_comandas(self, nomes):
        """Lê os arquivos de `nomes` e devolve seus dados já prontos para
        exibição (sem os códigos de controle da impressora), mais recentes
        primeiro.

        Único lugar que abre comanda para a tela de Consulta, e o passo caro
        das três listagens acima — quem chama decide QUAIS arquivos valem o
        custo."""
        os.makedirs(self.pasta_pedidos, exist_ok=True)

        # Uma leitura só do índice de eventos pra lista inteira — sem isto,
        # _maquina_origem() releria eventos.json uma vez por comanda (ver
        # indicePedidos.varredura), que é o mesmo desperdício que os
        # carregamentos de `conflitos` e `baixas` logo abaixo já evitam.
        with indicePedidos.varredura():
            conflitos = indicePedidos.carregar_conflitos()
            nomes_maquinas = self._nomes_maquinas_conhecidas()
            # Uma leitura só do mapa de baixas pra lista inteira — o mesmo
            # cuidado que já vale pra `conflitos` acima. Consultar
            # baixaComandas.esta_fechada() por comanda releria o JSON a cada
            # volta do laço.
            baixas = baixaComandas.carregar()

            comandas = []
            for nome_arquivo in nomes:
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
                data_arquivo = parser.data_arquivo_aaaammdd(nome_arquivo)

                comandas.append({
                    "arquivo": nome_arquivo,
                    "tipo": tipo,
                    "conteudo": conteudo,
                    "cliente": cliente,
                    # Quem lançou o pedido, pro filtro por usuário da tela (ver
                    # ColunaEsquerda.qml). "" numa comanda sem a linha
                    # "Usuário:" — comanda de teste, ou gravada antes de o
                    # cadastro existir.
                    "usuario": parser.extrair_campo(parser.PADRAO_USUARIO, conteudo),
                    "dataHora": parser.extrair_campo(parser.PADRAO_DATA, conteudo),
                    # O dia pelo NOME do arquivo ("" quando ele não segue o
                    # padrão). É por ele que a tela agrupa, e não pelo "Data:"
                    # do cupom, pra que o dia de uma comanda já carregada seja
                    # sempre o mesmo que listarDiasAnteriores contaria pra ela
                    # — senão um cupom com data divergente do nome abriria uma
                    # caixinha duplicada, uma vinda de cada lado.
                    "dia": self._dia_formatado(data_arquivo) if data_arquivo else "",
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

        linhas_tabela = parser.linhas_tabela_itens(linhas)
        if linhas_tabela is None:
            return {}

        endereco_completo = parser.extrair_campo(parser.PADRAO_ENDERECO, conteudo)
        endereco, numero = parser.dividir_endereco_numero(endereco_completo)

        return {
            "arquivo": nome_arquivo,
            "tipo": parser.tipo_comanda(nome_arquivo),
            "cliente": parser.extrair_campo(parser.PADRAO_CLIENTE, conteudo),
            "telefone": parser.extrair_campo(parser.PADRAO_TELEFONE, conteudo),
            "endereco": endereco,
            "numero": numero,
            "bairro": parser.extrair_campo(parser.PADRAO_BAIRRO, conteudo),
            "observacaoGeral": parser.extrair_campo(parser.PADRAO_OBSERVACAO_GERAL, conteudo),
            "formaPagamento": parser.extrair_campo(parser.PADRAO_FORMA_PAGAMENTO, conteudo),
            "troco": parser.extrair_campo(parser.PADRAO_TROCO, conteudo),
            "taxaEntrega": parser.extrair_campo(parser.PADRAO_TAXA_ENTREGA, conteudo),
            "statusPagamento": parser.extrair_status_pagamento(conteudo),
            "itens": parser.reconstruir_itens(linhas_tabela),
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

        if os.path.isfile(caminho):
            self._conciliar_com_local(nome_arquivo, caminho, bytes(conteudo), id_evento, maquina)
            return

        try:
            with open(caminho, "wb") as arquivo:
                arquivo.write(bytes(conteudo))
        except OSError as erro:
            print(f"Falha ao salvar pedido recebido da rede em {caminho}: {erro}")
            return

        indicePedidos.registrar_recebido(nome_arquivo, id_evento, maquina)
        self.comandasAtualizadas.emit()

    def _conciliar_com_local(self, nome_arquivo, caminho, conteudo_remoto, id_remoto, maquina):
        """Decide o que fazer quando a comanda recebida JÁ existe aqui.

        Duas perguntas independentes, nesta ordem:

        1. É a mesma comanda? Sim quando os dois lados têm o mesmo id de linha
           do tempo — o id nasce na máquina que lançou a venda e viaja junto
           dela (ver indicePedidos.registrar_recebido), então id igual
           significa mesma origem e mesma venda.
        2. Os valores batem? Aí sim compara campo a campo
           (services/comandaComparacaoService.py).

        Mesma comanda com valores diferentes é a ÚNICA situação que vira
        conflito: as duas máquinas discordam sobre uma venda que deveria ser a
        mesma, e nenhuma regra automática pode decidir qual está certa sem
        arriscar mudar o caixa do dia. As diferenças ficam guardadas junto do
        conflito para a Consulta poder mostrar exatamente o que não bate.

        Ids diferentes NÃO são conflito: são duas versões numa linha do tempo,
        e a mais nova vence. Antes disto, qualquer id fora de sincronia virava
        destaque amarelo — inclusive o caso banal de uma máquina ter o id real
        e a outra o sintetizado do nome do arquivo, com a comanda idêntica dos
        dois lados."""
        id_local = indicePedidos.id_evento(nome_arquivo)

        if id_remoto and id_local and id_remoto == id_local:
            try:
                with open(caminho, "rb") as arquivo:
                    conteudo_local = arquivo.read()
            except OSError as erro:
                print(f"Falha ao ler {caminho} para comparar com a versão da rede: {erro}")
                return

            diferencas = comparacao.diferencas_entre(conteudo_local, conteudo_remoto, nome_arquivo)
            if not diferencas:
                return

            novo = indicePedidos.registrar_conflito(
                nome_arquivo,
                _CONFLITO_CONTEUDO,
                id_local=id_local,
                id_remoto=id_remoto,
                maquina_remota=maquina or relogio.maquina_do_id(id_remoto),
                conteudo_remoto_b64=base64.b64encode(conteudo_remoto).decode("ascii"),
                diferencas=diferencas,
            )
            # Só quando o conflito é novo: registrar_conflito é idempotente e
            # reencontra o mesmo caso a cada ciclo de anti-entropy — sem esta
            # guarda, o histórico encheria de linhas repetidas.
            if novo:
                historicoEventos.registrar_local("conflito_detectado", {"arquivo": nome_arquivo})
            self.comandasAtualizadas.emit()
            return

        # Ids diferentes: quem tem o id mais novo manda. A regra é a mesma nas
        # duas máquinas, então elas convergem sozinhas e param de trocar a
        # comanda a cada ciclo de anti-entropy.
        if not relogio.mais_novo(id_remoto, id_local):
            return

        try:
            with open(caminho, "rb") as arquivo:
                conteudo_local = arquivo.read()
        except OSError:
            conteudo_local = None

        # Conteúdo idêntico é o caso comum aqui (o id é que estava fora de
        # sincronia): basta alinhar o índice, sem reescrever o arquivo.
        if conteudo_local != conteudo_remoto:
            try:
                with open(caminho, "wb") as arquivo:
                    arquivo.write(conteudo_remoto)
            except OSError as erro:
                print(f"Falha ao gravar a versão mais nova de {nome_arquivo}: {erro}")
                return

        indicePedidos.registrar_recebido(nome_arquivo, id_remoto, maquina)
        indicePedidos.resolver_conflito(nome_arquivo)
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

        # "maquinaRemota" guarda de onde a COMANDA veio (o sufixo do idEvento,
        # ver indicePedidos), que não é necessariamente quem mandou a versão
        # divergente. Quando ela é esta própria máquina — o caso normal de uma
        # comanda lançada aqui e alterada noutro lugar — dizer o nome faria a
        # tela afirmar "esta comanda está diferente em <esta máquina>". Vazio
        # faz o painel cair em "outra máquina", que é vago mas verdadeiro.
        maquina_remota = conflito.get("maquinaRemota", "")
        if maquina_remota == rede.nomeLocal:
            maquina_remota = ""

        return {
            "arquivo": os.path.basename(nome_arquivo),
            "motivo": conflito.get("motivo", ""),
            "maquinaRemota": maquina_remota,
            "conteudoRemoto": conteudo_remoto,
            "temVersaoRemota": bool(conteudo_remoto),
            # Campo a campo, o que difere entre as duas versões (ver
            # services/comandaComparacaoService.comparar). Vazio em conflitos
            # gravados antes deste campo existir — a tela cai no cupom inteiro
            # nesse caso.
            "diferencas": conflito.get("diferencas") or [],
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
        historicoEventos.registrar_local(
            "conflito_resolvido", {"arquivo": nome_arquivo, "escolha": "versão desta máquina"}
        )
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
        historicoEventos.registrar_local(
            "conflito_resolvido",
            {"arquivo": nome_arquivo, "escolha": conflito.get("maquinaRemota", "") or "outra máquina"},
        )
        self.comandasAtualizadas.emit()
        return True
