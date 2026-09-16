"""Montagem do texto de comandas (tabela de itens, valores) compartilhada por
balcaoController.py, entregaController.py e salaoController.py — extraído de
dentro dos dois primeiros (que tinham essas mesmas funções duplicadas
byte-a-byte) quando salaoController.py apareceu como um terceiro consumidor.
"""

import re

from services import comandaEstiloService as estilo

# Separador usado em Pizzas.qml (nomesArray.join(" / ")) para pizzas meio a meio.
# Tem espaço dos dois lados, o que o distingue de nomes como "Atum c/ Cebola".
SEPARADOR_SABORES = " / "

# Codepage que a Bematech usa para acentuação (ç, ã, é...) em modo ESC/POS.
# Não é UTF-8: se salvar como UTF-8, os acentos saem corrompidos no cupom impresso.
CODEPAGE_IMPRESSORA = "cp850"

# Linha usada para delimitar a tabela de itens, e só ela — distinta do
# separador genérico ("-" * 40) usado entre os demais campos por
# montar_linhas_por_ordem. Como a posição da tabela de itens na comanda
# agora é configurável (ver comandaEstiloService.ordem_secoes), ela precisa
# de um marcador só dela para que consultaController.reconstruirComanda
# consiga achá-la de volta não importa onde esteja — contar "a 1ª e a 2ª
# linha de traços do arquivo" só funcionava enquanto a tabela de itens tinha
# posição fixa. Visualmente, no papel, é só mais uma linha de traços (o "="
# não chama atenção nem confunde quem lê o cupom).
# Largura do papel, em caracteres. É a régua de tudo que se alinha no cupom:
# as divisórias, o marcador da tabela de itens e a decisão de descer o tamanho
# da pizza para a linha de baixo (ver _acomodar_tamanho).
#
# Vale para a fonte BASE. Um campo configurado com fonte ampliada ocupa o dobro
# (ou mais) por caractere, e aí a impressora quebra onde quiser — isso já valia
# antes e continua valendo; a régua aqui é a mesma que o resto do módulo sempre
# assumiu.
COLUNAS_PAPEL = 40

MARCADOR_ITENS = "=" * COLUNAS_PAPEL

# As modalidades de pedido que abrem a comanda com um título (ver
# linhas_modalidade). Os mesmos nomes de comandaEstiloService.TIPOS_COMANDA —
# Extras e Fechamento ficam de fora porque não são pedido.
MODALIDADES = ("Balcão", "Entrega", "Mesa")

# Estilo FIXO do título: negrito e o dobro do tamanho base. Grande o bastante
# para ser a primeira coisa lida no papel, perto dos campos principais, e
# pequeno o bastante para "ENTREGA" com o ícone caber folgado na largura.
_ATRIBUTOS_MODALIDADE = {"negrito": True, "tamanho_fonte": 48}

# O que separa a coluna do pedido da coluna do valor em formatar_tabela.
_SEPARADOR_COLUNA = " | "


def linhas_modalidade(modalidade):
    """O título que abre a comanda de pedido ("ENTREGA", centralizado) e o
    espaçamento de seção logo abaixo dele.

    Centralizado com ESPAÇOS, e não com o comando de alinhamento da
    impressora, porque o mesmo arquivo tem três leitores: a impressora em
    modo texto (sem fonte escolhida), a Consulta, que mostra o texto limpo, e
    o desenho em imagem — que reconhece esta linha e a redesenha centralizada
    de verdade, com o ícone da modalidade ao lado (ver
    comandaImagemService._titulo_da_comanda). O recuo conta cada letra pelo
    tamanho ampliado: em 48 px, uma letra ocupa duas colunas."""
    rotulo = str(modalidade).upper()
    colunas = len(rotulo) * _ATRIBUTOS_MODALIDADE["tamanho_fonte"] / estilo.TAMANHO_FONTE_BASE_PX
    recuo = " " * max(0, int((COLUNAS_PAPEL - colunas) // 2))
    return [recuo + estilo.formatar_com_atributos(rotulo, _ATRIBUTOS_MODALIDADE)] + estilo.linhas_espacamento_secoes()


# Códigos de estilo embutidos no texto (ver comandaEstiloService.
# formatar_campo): são invisíveis no papel e não podem contar como largura na
# hora de quebrar a linha.
_ESC = "\x1b"
_GS = "\x1d"
_PADRAO_ESTILO = re.compile(
    r"(?:" + re.escape(_ESC) + r"[E\-]|" + re.escape(_GS) + r"[B!])[\s\S]"
    r"|" + re.escape(estilo.MARCA_TAMANHO_PX) + r"\d{3}"
)


def largura_visivel(linha):
    """Quantas colunas do papel a linha ocupa — o texto sem os códigos de
    estilo, que não imprimem nada."""
    return len(_PADRAO_ESTILO.sub("", linha))


def quebrar_linha(linha, largura=COLUNAS_PAPEL):
    """`linha` em uma ou mais linhas de até `largura` colunas, sem partir
    palavra: a que não couber vai inteira para a de baixo.

    POR QUE AQUI: o cupom sai numa régua de COLUNAS_PAPEL, e o que passa disso
    a impressora quebra onde a conta der — no meio de "(BROTO)", de
    "(PÃO FRANCÊS)" ou do nome do cliente. Quebrando na montagem, o papel sai
    igual nos dois caminhos (texto e imagem, ver
    comandaImagemService._quebrar_em_linhas_fisicas, que faz o mesmo em dots).

    Os códigos de estilo viajam grudados no caractere seguinte e não contam
    largura (ver largura_visivel). Eles não precisam ser repetidos na linha de
    baixo: um "liga negrito" vale até o "desliga", atravessando a quebra.

    A continuação entra recuada em dois espaços — o mesmo recuo dos adicionais
    e da observação —, para se ler de relance que aquilo ainda é a linha de
    cima. Palavra maior que a régua inteira é partida: não há para onde
    empurrá-la."""
    if largura_visivel(linha) <= largura:
        return [linha]

    recuo = "  "
    # Cada unidade é (códigos de estilo, caractere visível): o que é invisível
    # anda junto com a letra seguinte, para o negrito não se perder na quebra.
    unidades = []
    pendentes = ""
    posicao = 0
    for comando in _PADRAO_ESTILO.finditer(linha):
        for caractere in linha[posicao:comando.start()]:
            unidades.append((pendentes, caractere))
            pendentes = ""
        pendentes += comando.group()
        posicao = comando.end()
    for caractere in linha[posicao:]:
        unidades.append((pendentes, caractere))
        pendentes = ""

    linhas = []
    atual = ""
    visivel = 0
    palavra = []
    largura_maxima = largura

    def fechar_palavra():
        """Põe a palavra pendente na linha atual, descendo quando não couber."""
        nonlocal atual, visivel, palavra, largura_maxima
        if not palavra:
            return
        if visivel and visivel + len(palavra) > largura_maxima:
            linhas.append(atual)
            atual = recuo
            visivel = len(recuo)
            largura_maxima = largura
        for codigos, caractere in palavra:
            atual += codigos + caractere
            visivel += 1
        palavra = []

    for codigos, caractere in unidades:
        if caractere == " ":
            fechar_palavra()
            # Espaço que não cabe fecha a linha e não abre a próxima.
            if visivel + 1 > largura_maxima:
                linhas.append(atual)
                atual = recuo
                visivel = len(recuo)
                continue
            atual += codigos + " "
            visivel += 1
            continue

        # Palavra maior que a régua: parte, porque não cabe em linha nenhuma.
        if len(palavra) + 1 > largura - len(recuo):
            fechar_palavra()
            linhas.append(atual)
            atual = recuo
            visivel = len(recuo)
        palavra.append((codigos, caractere))

    fechar_palavra()
    if atual.strip() or not linhas:
        linhas.append(atual)
    # O ljust da tabela de itens deixa rabo de espaços na última linha.
    return [l.rstrip() if l.strip() else l for l in linhas]


def quebrar_linhas(linhas, largura=COLUNAS_PAPEL):
    """quebrar_linha aplicada a uma lista, na ordem."""
    quebradas = []
    for linha in linhas:
        quebradas.extend(quebrar_linha(linha, largura))
    return quebradas


def montar_linhas_por_ordem(ordem, renderizadores):
    """Monta a lista final de linhas da comanda (linhas_arquivo) a partir de
    `ordem` (lista de chaves, ver comandaEstiloService.ordem_secoes()) e
    `renderizadores` ({chave: lista_de_linhas ou None/[] se não aplicável a
    este pedido — ex: "troco_para" quando a forma de pagamento não é
    dinheiro}).

    Compartilhado por balcaoController/entregaController/salaoController
    para não reimplementar em cada um a mesma regra de espaçamento —
    mesmo motivo de existir montar_grupos/formatar_tabela acima.

    Regra de separador entre dois campos consecutivos e não vazios:
    - "itens" sempre entra cercado por MARCADOR_ITENS (antes e depois),
      não importa a categoria do campo vizinho — é o único jeito de
      localizá-lo de volta depois, com a posição configurável. Sempre uma
      linha só de cada lado (ver comandaEstiloService.linhas_separador_antes).
    - Nos demais pontos, quantas linhas "-" * 40 entram é decisão de
      comandaEstiloService.linhas_separador_antes: por padrão uma na troca de
      categoria e nenhuma dentro da mesma categoria (ex: Cliente logo seguido
      de Data), com a espessura e as exceções por campo que a tela de
      Configurações grava."""
    linhas = []
    categoria_anterior = None
    itens_anterior = False

    for chave in ordem:
        conteudo = renderizadores.get(chave)
        if not conteudo:
            continue

        eh_itens = chave == "itens"
        if eh_itens or itens_anterior:
            linhas.extend(estilo.linhas_espacamento_secoes())
            linhas.append(MARCADOR_ITENS)
            linhas.extend(estilo.linhas_espacamento_secoes())
        else:
            tracos = estilo.linhas_separador_antes(chave, categoria_anterior)
            if tracos:
                linhas.extend(estilo.linhas_espacamento_secoes())
                linhas.extend(["-" * COLUNAS_PAPEL] * tracos)
                linhas.extend(estilo.linhas_espacamento_secoes())

        # Quebra por palavra antes de ir ao papel: nenhum campo do cupom
        # (cliente, endereço, observação) sai com palavra partida no meio. A
        # tabela de itens chega pronta de formatar_tabela, que já quebra
        # respeitando a coluna "pedido | valor" — quebrá-la de novo aqui
        # desmancharia o alinhamento.
        linhas.extend(conteudo if eh_itens else quebrar_linhas(conteudo))

        categoria_anterior = estilo.categoria_campo(chave)
        itens_anterior = eh_itens

    if itens_anterior:
        linhas.extend(estilo.linhas_espacamento_secoes())
        linhas.append(MARCADOR_ITENS)

    return linhas


def dividir_sabores(pedido_texto):
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


def valor_para_float(valor_texto):
    """Converte "R$ 45,00" em 45.0. Retorna 0.0 se não conseguir interpretar."""
    if not valor_texto:
        return 0.0

    limpo = valor_texto.replace("R$", "").strip()
    limpo = limpo.replace(".", "").replace(",", ".")
    try:
        return float(limpo)
    except ValueError:
        return 0.0


# Prefixos que marcam as linhas extras impressas abaixo de um item (ver
# montar_grupos/formatar_tabela) — precisam ser reconhecíveis de volta por
# consultaController._reconstruir_itens, para não confundi-las com uma
# observação livre digitada pelo atendente.
PREFIXO_ADICIONAL = "+ "
PREFIXO_BORDA = "* "

# Sufixo do adicional que vale para a PIZZA INTEIRA, e não para uma das
# metades — "+ BACON INTEIRA".
#
# Ele tem dois papéis, e o segundo é o que o torna obrigatório. Para quem lê o
# papel, avisa a cozinha de que o bacon é na pizza toda: sem isso a linha sairia
# igual à de um adicional de metade, só que num lugar diferente da tabela, e
# "lugar diferente" não é distinção que alguém note com a fila andando. Para
# quem lê a comanda de volta (ver comandaParserService.reconstruir_itens), é a
# ÚNICA marca que sobrevive à impressão: um adicional de pizza inteira sai
# depois de todas as frações, exatamente onde sairia um adicional da última
# fração, e sem o sufixo os dois seriam indistinguíveis ao reabrir a comanda em
# Consulta > Editar.
#
# Guardado no item, o adicional de pizza inteira é o que tem "sabor" vazio — o
# sufixo é coisa do papel, posto na impressão e retirado na leitura, para que o
# nome do adicional no cardápio e no item continue sendo só "Bacon".
SUFIXO_ADICIONAL_INTEIRA = " INTEIRA"

# O que abre a linha de um item que não é pizza fracionada: a QUANTIDADE dele.
# Era um "- " de marcador de lista, que não dizia nada — e ficava estranho ao
# lado das frações logo acima/abaixo, que já abrem com número ("1/2 - ...").
# Hoje cada linha do formulário é uma unidade, então a quantidade é sempre 1;
# o dia em que o formulário ganhar um campo de quantidade, é aqui que ele entra.
#
# Tem o mesmo comprimento do "- " antigo de propósito: a coluna do pedido é
# alinhada por contagem de caracteres (ver formatar_tabela), e trocar a largura
# do prefixo mexeria no alinhamento de todo cupom.
PREFIXO_ITEM_UNICO = "1 "

# Tamanho que NÃO sai escrito no papel (ver _tamanho_impresso). O grande é a
# pizza que se pede quando não se diz nada, então repeti-lo em toda linha só
# gastava espaço numa coluna de 40 caracteres — o que precisa de aviso é a
# exceção: "(BROTO)" e "(MINI)" continuam saindo.
#
# A leitura do papel passa a ser por AUSÊNCIA: sem tamanho escrito, é grande.
TAMANHO_OMITIDO = "GRANDE"


def _tamanho_impresso(tamanho):
    """O tamanho como ele deve sair no papel, ou None quando não sai.

    Só o texto muda: `dividir_sabores` continua devolvendo o tamanho de
    verdade, e quem precisa dele para outra coisa (o parser da comanda, os
    adicionais por sabor) não é afetado."""
    if not tamanho or tamanho.strip().upper() == TAMANHO_OMITIDO:
        return None
    return tamanho


def _linhas_de_list_model(modelo):
    """Lê um ListModel da QML (que chega aqui como QAbstractListModel) linha
    a linha, devolvendo uma lista de dicts — ou None se `modelo` não for um.

    Só olha os métodos que precisa (duck typing), sem importar PyQt6: este
    módulo é usado também por scripts e testes que rodam sem Qt carregado."""
    try:
        contar = modelo.rowCount
        indice_de = modelo.index
        ler = modelo.data
        papeis = modelo.roleNames()
    except AttributeError:
        return None

    nomes = {numero: bytes(nome).decode("utf-8", errors="replace") for numero, nome in papeis.items()}
    linhas = []
    for i in range(contar()):
        indice = indice_de(i, 0)
        linhas.append({nome: ler(indice, numero) for numero, nome in nomes.items()})
    return linhas


def _como_lista_de_dicts(valor):
    """Normaliza o que a QML mandou num campo que deveria ser uma lista de
    objetos (hoje: "adicionais").

    Existe porque um array atribuído a um role de ListModel não continua
    sendo um array: vira um list-model aninhado, que chega no Python como
    QAbstractListModel. Iterar nisso levanta TypeError — e uma exceção
    escapando de um slot chamado pela QML derrubava o app inteiro (ver
    Config/logConfig.protegido). As telas de Balcão/Entrega/Salão evitam
    isso guardando os adicionais como string JSON no ListModel, mas essa
    convenção é fácil de esquecer numa tela nova, então a conversão é feita
    aqui também — assim o pior caso vira "os adicionais saem certos do
    mesmo jeito", não "a comanda inteira se perde"."""
    if not valor:
        return []

    if isinstance(valor, dict):
        return [valor]

    if not isinstance(valor, (list, tuple)):
        linhas = _linhas_de_list_model(valor)
        if linhas is None:
            print(f"[comandaTextoService] Campo de adicionais em formato inesperado ({type(valor).__name__}) — ignorado.")
            return []
        valor = linhas

    return [item for item in valor if isinstance(item, dict)]


def item_preenchido(item):
    """Se o item tem alguma coisa que mereça uma linha no papel.

    POR QUE PRECISA EXISTIR: o formulário de Balcão/Entrega/Salão sempre
    termina com uma linha em branco — o "+" cria uma e ela fica ali esperando
    ser preenchida. Ela viajava até aqui junto com as de verdade e saía
    impressa como um prefixo solto no meio dos itens (ver PREFIXO_ITEM_UNICO),
    com a coluna "|" e tudo.

    "Vazio" aqui é vazio de VERDADE: nada digitado no nome, na observação nem
    no valor, e nenhuma borda ou adicional escolhido. Uma linha com valor e sem
    nome NÃO é descartada — ela é um erro de digitação, e sumir com ela em
    silêncio tiraria dinheiro do cupom sem ninguém ver; saindo como uma linha
    sem nome, quem confere percebe na hora.

    É essa régua, também, que garante que filtrar não mexe no TOTAL: quem chama
    soma o "valor" de cada item (ver balcaoController._salvarComanda), e tudo
    que esta função rejeita tem valor vazio, que vale R$ 0,00. Afrouxar o
    critério daqui quebraria essa garantia — a tabela impressa passaria a não
    fechar com o total impresso, que é o pior tipo de erro num cupom."""
    if str(item.get("pedido") or "").strip():
        return True
    if str(item.get("observacao") or "").strip():
        return True
    if str(item.get("valor") or "").strip():
        return True
    if _formatar_borda(item.get("borda")):
        return True
    if _como_lista_de_dicts(item.get("adicionais")):
        return True
    return False


def montar_grupos(itens):
    """Converte os itens do pedido em grupos (um por item; uma pizza meio a
    meio gera várias linhas — uma por sabor/fração — mas continua sendo um
    único grupo), para que se possa separar os grupos com uma linha em
    branco depois de formatados.

    Cada grupo é um dict:
    {"linhas": [(coluna_pedido, valor, extras, tamanho)], ...},
    "adicionais_inteiros": linhas dos adicionais que valem para o item inteiro,
    "borda": texto da borda (nível do item/pizza inteira, "" se não houver),
    "observacao": texto da observação geral do item.

    "extras" (dentro de cada linha) é a lista de adicionais atribuídos
    especificamente àquele sabor (ver Pizzas.qml/PopupAdicionaisBordas.qml) —
    cada um sai numa linha própria, logo abaixo da fração correspondente.

    "adicionais_inteiros" é o resto: os que o atendente atribuiu à pizza toda
    em vez de a uma metade (ver SUFIXO_ADICIONAL_INTEIRA). Saem uma vez só,
    depois de todas as frações, no mesmo lugar da borda — que é onde já mora o
    que vale para o item inteiro.

    Linhas em branco do formulário não viram grupo nenhum (ver
    item_preenchido) — a filtragem mora AQUI, e não em cada controller, porque
    Balcão, Entrega e as duas comandas do Salão passam todos por esta função:
    filtrar em cada um significaria quatro lugares para lembrar, e o quarto
    ficaria para trás em silêncio.

    "tamanho" é o tamanho da pizza ("GRANDE", "BROTO", "MINI") quando ele
    aparece NAQUELA linha, e None quando não. Ele já está dentro de
    `coluna_pedido` — vai repetido aqui só para quem formata saber ONDE está,
    e conseguir estilizá-lo à parte do resto do nome do item (ver
    formatar_coluna_pedido). Numa pizza meio a meio o tamanho sai uma vez só,
    na primeira fração, então só ela o carrega."""
    grupos = []
    for item in (itens or []):
        if not item_preenchido(item):
            continue

        # Nome do item e observação saem em caixa alta no cupom impresso.
        pedido = item.get("pedido", "").upper()
        observacao = item.get("observacao", "").upper()
        valor = item.get("valor", "")
        adicionais = _como_lista_de_dicts(item.get("adicionais"))

        sabores, tamanho = dividir_sabores(pedido)

        # O tamanho de verdade continua servindo para casar os adicionais com
        # o sabor; o que muda é só o que vai para o papel.
        tamanho_no_papel = _tamanho_impresso(tamanho)

        if len(sabores) <= 1:
            sabor_unico = sabores[0] if sabores else pedido
            # Remontado a partir do sabor, e não reaproveitando `pedido` como
            # antes: é a remontagem que deixa o "(GRANDE)" de fora. Sem
            # tamanho, `sabores[0]` já é o `pedido` inteiro, então o resultado
            # é o mesmo de sempre para lanche, bebida e afins.
            nome = f"{sabor_unico} ({tamanho_no_papel})" if tamanho_no_papel else sabor_unico
            linhas = [(
                f"{PREFIXO_ITEM_UNICO}{nome}",
                valor,
                _extras_adicionais(adicionais, sabor_unico),
                tamanho_no_papel,
            )]
        else:
            # Pizza meio a meio: cada sabor ocupa "1/N" da pizza.
            total = len(sabores)
            linhas = []
            for indice, sabor in enumerate(sabores):
                tem_tamanho = indice == 0 and tamanho_no_papel
                nome_sabor = f"{sabor} ({tamanho_no_papel})" if tem_tamanho else sabor
                coluna_pedido = f"1/{total} - {nome_sabor}"
                valor_linha = valor if indice == 0 else ""
                linhas.append((
                    coluna_pedido,
                    valor_linha,
                    _extras_adicionais(adicionais, sabor),
                    tamanho_no_papel if tem_tamanho else None,
                ))

        grupos.append({
            "linhas": linhas,
            "adicionais_inteiros": _extras_adicionais(adicionais, "", inteira=True),
            "observacao": observacao,
            "borda": _formatar_borda(item.get("borda")),
        })

    return grupos


def _extras_adicionais(adicionais, sabor, inteira=False):
    """Linhas dos adicionais atribuídos a `sabor` (comparação sem diferenciar
    caixa — os nomes de sabor chegam em caixa alta do cupom, mas o adicional
    guarda o nome do sabor como veio de Pizzas.qml).

    Com `inteira`, junta os do outro tipo: os de sabor VAZIO, que são os que
    valem para o item inteiro, e que saem com SUFIXO_ADICIONAL_INTEIRA no nome.
    Os dois casos moram na mesma função porque a diferença entre eles é só o
    critério de casamento e o sufixo — separá-los em duas duplicaria a
    formatação do nome e do valor, que é onde um erro passaria despercebido.

    Um adicional cujo sabor não casa com nenhuma fração e não está vazio fica
    de fora dos dois, e isso é intencional: é um dado corrompido (nome de sabor
    editado à mão depois de o adicional ter sido atribuído), e imprimi-lo em
    algum lugar arbitrário seria pior do que a ausência."""
    extras = []
    for adicional in adicionais:
        sabor_adicional = (adicional.get("sabor") or "").strip()
        if inteira:
            if sabor_adicional:
                continue
        elif sabor_adicional.upper() != (sabor or "").strip().upper():
            continue
        nome = (adicional.get("nome") or "").upper()
        if inteira:
            nome += SUFIXO_ADICIONAL_INTEIRA
        valor_adicional = adicional.get("valor") or ""
        sufixo = f" ({valor_adicional})" if valor_adicional else ""
        extras.append(f"{PREFIXO_ADICIONAL}{nome}{sufixo}")
    return extras


def _formatar_borda(borda):
    if not borda:
        return ""

    if not isinstance(borda, dict):
        # Mesmo motivo de _como_lista_de_dicts: o que a QML manda nem sempre
        # é o dict simples que este código espera.
        print(f"[comandaTextoService] Campo de borda em formato inesperado ({type(borda).__name__}) — ignorado.")
        return ""

    nome = (borda.get("nome") or "").strip()
    if not nome:
        return ""

    valor_borda = borda.get("valor") or ""
    sufixo = f" ({valor_borda})" if valor_borda else ""
    return f"{PREFIXO_BORDA}{nome.upper()}{sufixo}"


def formatar_coluna_pedido(coluna, tamanho):
    """A coluna do item já estilizada, com o TAMANHO da pizza ("(GRANDE)") no
    campo próprio "pedido_tamanho" e o resto em "pedido".

    Existe porque o tamanho é parte da mesma string do nome do item (ver
    montar_grupos) e, até haver este campo, saía obrigatoriamente com o estilo
    do nome. Quem quisesse o "(GRANDE)" menor que o sabor, ou sem o negrito
    dele, não tinha como.

    Compartilhada por formatar_tabela e pela comanda do pizzaiolo
    (salaoController._linhas_itens_producao), que montam a tabela de formas
    diferentes mas precisam estilizar a coluna igual — se cada uma fizesse o
    seu, o tamanho sairia estilizado num papel e não no outro.

    Sem tamanho (lanche, bebida, ou uma linha de fração que não é a primeira),
    devolve a coluna inteira em "pedido", exatamente como antes.

    A busca é pela ÚLTIMA ocorrência: o tamanho vem no fim, e um sabor com
    parênteses no nome não pode roubar a marcação. Não achando (nome editado à
    mão, formato inesperado), estiliza tudo como "pedido" em vez de arriscar
    cortar a coluna no lugar errado."""
    if not tamanho:
        return estilo.formatar_campo(coluna, "pedido")

    marca = f"({tamanho})"
    posicao = coluna.rfind(marca)
    if posicao < 0:
        return estilo.formatar_campo(coluna, "pedido")

    antes = coluna[:posicao]
    depois = coluna[posicao + len(marca):]

    partes = []
    if antes:
        partes.append(estilo.formatar_campo(antes, "pedido"))
    partes.append(estilo.formatar_campo(marca, "pedido_tamanho"))
    # O que vem depois costuma ser só o preenchimento do ljust — vai como
    # "pedido" porque era assim que ele saía antes de o tamanho ter campo
    # proprio, e espaço em branco não muda de aparência mesmo.
    if depois:
        partes.append(estilo.formatar_campo(depois, "pedido"))
    return "".join(partes)


def _acomodar_tamanho(coluna, tamanho, valor, largura_pedido):
    """Decide se o "(BROTO)" cabe na linha do item ou tem de descer para a
    linha de baixo. Devolve (coluna, tamanho_na_coluna, tamanho_na_linha_de_baixo).

    O PROBLEMA: a linha do item é "pedido | valor", e quando ela passa das
    COLUNAS_PAPEL a impressora quebra onde a conta der — no meio do tamanho,
    saindo "(BRO" numa linha e "TO)" na outra. Um sabor comprido bastava para
    isso, e o que se perdia era justamente a informação que só aparece na
    exceção (grande não sai escrito, ver TAMANHO_OMITIDO).

    Desce o tamanho INTEIRO, em vez de tentar encurtar o nome do sabor: o nome
    é o que a cozinha lê primeiro, e abreviá-lo para caber um "(BROTO)" trocaria
    um problema por outro pior.

    A conta usa `largura_pedido` (a largura JÁ preenchida da coluna, comum a
    todas as linhas da tabela), e não o comprimento desta coluna: é ela que sai
    no papel. Uma linha curta ao lado de uma comprida é esticada até a mesma
    largura, e sem isso o tamanho dela quebraria mesmo com o nome curto."""
    if not tamanho:
        return coluna, None, None

    if largura_pedido + len(_SEPARADOR_COLUNA) + len(valor) <= COLUNAS_PAPEL:
        return coluna, tamanho, None

    marca = f" ({tamanho})"
    if not coluna.endswith(marca):
        # Formato inesperado (coluna montada de outro jeito, comanda antiga):
        # deixa como está em vez de cortar no lugar errado.
        return coluna, tamanho, None

    return coluna[:-len(marca)], None, tamanho


def _linhas_do_nome(coluna, largura_pedido, valor):
    """A coluna do item em uma ou mais linhas: a primeira alinhada com o valor,
    as seguintes (o nome que não coube) recuadas, quebradas por palavra.

    POR QUE NÃO BASTA O ljust: a régua do papel tem COLUNAS_PAPEL, e um nome
    comprido faz "pedido | valor" passar disso — aí a impressora quebra onde a
    conta der, no meio de "(BROTO)" ou de "(PÃO FRANCÊS)". Quebrando aqui, o
    nome desce por palavra e a coluna do valor continua onde sempre esteve."""
    if largura_visivel(coluna) <= largura_pedido:
        return [coluna.ljust(largura_pedido)], []

    # O recuo das linhas de continuação é o mesmo dos adicionais e da
    # observação: lê-se de relance que aquilo ainda é o item de cima.
    partes = quebrar_linha(coluna, largura_pedido)
    primeira = partes[0].ljust(largura_pedido)
    return [primeira], partes[1:]


def formatar_tabela(grupos):
    """Alinha pedido e valor em uma coluna "|" e separa cada grupo com uma
    linha em branco. Depois de cada fração vêm seus adicionais (se houver);
    depois de TODAS as frações do grupo vêm a borda (quando houver) e por
    último a observação — mesmo numa pizza meio a meio (ou dividida em mais
    partes), borda e observação saem só ao final, abaixo do nome completo,
    nunca entre uma fração e outra."""
    todas = [linha for grupo in grupos for linha in grupo["linhas"]]
    if not todas:
        return []

    # Dois passos porque a largura da coluna e a decisão de descer o tamanho
    # dependem uma da outra: mede-se com os tamanhos ainda no lugar, decide-se
    # quais descem, e só então se mede de novo. Descer um tamanho só ENCURTA a
    # coluna, então a segunda medida nunca desmente a primeira — no máximo
    # sobra espaço onde um tamanho já desceu, o que é o lado seguro de errar.
    largura_medida = max(len(coluna) for coluna, _valor, _extras, _tamanho in todas)

    preparados = []
    for grupo in grupos:
        preparados.append([
            _acomodar_tamanho(coluna, tamanho, valor, largura_medida) + (valor, extras)
            for coluna, valor, extras, tamanho in grupo["linhas"]
        ])

    # A coluna do pedido nunca passa do que sobra do papel depois do separador
    # e do maior valor: é isso que garante que "pedido | valor" caiba nas
    # COLUNAS_PAPEL, com ou sem nome comprido.
    maior_valor = max(len(valor) for _c, _t, _b, valor, _e in
                      [linha for linhas_grupo in preparados for linha in linhas_grupo])
    teto_pedido = COLUNAS_PAPEL - len(_SEPARADOR_COLUNA) - maior_valor
    largura_pedido = min(
        teto_pedido,
        max(len(coluna) for linhas_grupo in preparados for coluna, _t, _b, _v, _e in linhas_grupo),
    )

    texto_linhas = []
    for indice, grupo in enumerate(grupos):
        if indice > 0:
            texto_linhas.append("")

        for coluna_pedido, tamanho_na_coluna, tamanho_abaixo, valor, extras in preparados[indice]:
            # Alinha primeiro com o texto puro, e só então aplica o
            # estilo configurado — assim os bytes de controle (invisíveis
            # na impressão) não contam como largura na coluna.
            primeira, continuacao = _linhas_do_nome(coluna_pedido, largura_pedido, valor)
            coluna_pedido_fmt = formatar_coluna_pedido(primeira[0], tamanho_na_coluna)
            texto_linhas.append(f"{coluna_pedido_fmt}{_SEPARADOR_COLUNA}{valor}")
            # O resto do nome, que não coube ao lado do valor.
            for resto in continuacao:
                texto_linhas.append(formatar_coluna_pedido(resto, tamanho_na_coluna))
            # O tamanho que desceu vem colado no nome, ANTES dos adicionais:
            # ele é parte do item, não um extra dele.
            if tamanho_abaixo:
                texto_linhas.extend(quebrar_linha(f"  {estilo.formatar_campo(f'({tamanho_abaixo})', 'pedido_tamanho')}"))
            for extra in extras:
                texto_linhas.extend(quebrar_linha(f"  {estilo.formatar_campo(extra, 'adicional_item')}"))

        # Antes da borda, e depois de todas as frações: são adicionais, então
        # ficam perto dos outros adicionais; e valem para o item inteiro, então
        # não podem ficar colados numa fração só.
        for extra in grupo.get("adicionais_inteiros", []):
            texto_linhas.extend(quebrar_linha(f"  {estilo.formatar_campo(extra, 'adicional_item')}"))

        if grupo["borda"]:
            texto_linhas.extend(quebrar_linha(f"  {estilo.formatar_campo(grupo['borda'], 'borda_item')}"))
        if grupo["observacao"]:
            texto_linhas.extend(quebrar_linha(f"  {estilo.formatar_campo(grupo['observacao'], 'observacao_item')}"))

    return texto_linhas
