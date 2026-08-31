"""Desenha a comanda numa imagem (QImage) e a converte em ESC/POS raster, pra
que ela possa sair impressa numa fonte TTF escolhida pelo dono em vez das
fontes gravadas dentro da impressora.

POR QUE ISTO EXISTE: no caminho normal, o que viaja até a impressora é TEXTO —
os controllers montam as linhas, embutem os comandos de estilo (ver
comandaEstiloService.formatar_campo) e mandam bytes cp850; quem desenha as
letras é a própria impressora, com a Fonte A (12x24) que ela tem de fábrica.
Nenhuma fonte do computador chega lá. O único jeito de escolher a tipografia é
parar de mandar texto e mandar uma IMAGEM já desenhada.

É um caminho PARALELO, não um substituto: só entra em cena quando há uma fonte
configurada (ver comandaEstiloService.fonte_impressao). Sem ela, a comanda sai
como sempre saiu, byte a byte.

ONDE ISTO É CHAMADO, E POR QUÊ ALI: no último instante possível, dentro de
PrinterService.imprimir — depois de a comanda já ter sido gravada em pedidos/
*.txt e replicada na malha. O .txt é o REGISTRO da comanda: ConsultaController
reabre e edita, FechamentoController tira dele o caixa do dia,
comandaComparacaoService compara máquina a máquina, e a reimpressão reenvia o
arquivo byte a byte. Tudo isso lê texto cp850. Rasterizar mais cedo — dentro dos
controllers, onde o mesmo `conteudo_bytes` serve pra gravar, replicar E imprimir
— derrubaria os quatro de uma vez.

HÁ DOIS MODELOS DE DESENHO, escolhidos na tela de Configurações (ver
comandaEstiloService.MODELOS_IMPRESSAO):

* "clássico" — o padrão, descrito no parágrafo abaixo: a comanda inteira numa
  grade de células de largura fixa, igual ao cupom de texto de sempre.
* "rascunho" — igual ao clássico em tudo, menos a tabela de itens, que sai em
  três colunas (Pedido / Observação / Valor) como a lista de itens das telas de
  Balcão, Entrega e Salão. Ver _desenhar_modelo_rascunho.

Um modelo novo é sempre um caminho PARALELO, e qualquer tropeço nele cai de
volta no clássico em vez de derrubar a impressão — é o que permite testar
disposições numa pizzaria em funcionamento.

O ALINHAMENTO É EM GRADE, e essa é a decisão de desenho mais importante daqui.
O texto que chega já foi montado numa régua de COLUNAS_PAPEL caracteres: o
ljust da tabela de itens, a coluna "|", as linhas de traço e o MARCADOR_ITENS
só fecham porque todo caractere ocupa a mesma largura. Uma fonte proporcional
(Figtree, Arial) desmancharia isso na primeira linha. Por isso cada caractere é
desenhado no CENTRO de uma célula de largura fixa, e não em fluxo: a comanda sai
com o mesmo alinhamento de hoje em qualquer família escolhida. O preço é o
espaçamento levemente artificial das proporcionais — que é o preço certo a
pagar, porque uma coluna de valores desalinhada é erro de cupom, e letra com
folga estranha é só questão de gosto.
"""

import math
import re

from PyQt6.QtCore import QRectF, Qt, QThread
from PyQt6.QtGui import QColor, QFont, QFontDatabase, QFontMetricsF, QGuiApplication, QImage, QPainter

from services import comandaEstiloService as estilo
from services import comandaParserService as parser
from services import comandaTextoService as texto

_ESC = "\x1b"
_GS = "\x1d"

# Largura de um caractere da Fonte A (12x24 dots), que é a que a impressora usa
# hoje. A grade é montada em cima dela de propósito: assim a comanda em imagem
# ocupa exatamente o mesmo espaço no papel que a comanda em texto, e a única
# coisa que muda ao ligar a fonte é o desenho das letras. Facilita comparar os
# dois cupons lado a lado, que é justamente o que se quer num teste.
LARGURA_CELULA_DOTS = 12
ALTURA_LINHA_DOTS = 24

# A mesma régua de 40 colunas de comandaTextoService, agora em dots. Precisa ser
# múltiplo de 8: o raster manda 1 bit por pixel, então cada linha da imagem vira
# um número inteiro de bytes.
LARGURA_PAPEL_DOTS = texto.COLUNAS_PAPEL * LARGURA_CELULA_DOTS

# Quantas linhas de imagem vão em cada comando de raster. A imagem inteira num
# comando só depende de a impressora ter buffer pra ela — e uma comanda comprida
# tem uns dois mil pontos de altura. Fatiar é o que garante que o cupom não sai
# pela metade numa impressora com buffer curto; o papel não vê diferença, as
# faixas saem coladas uma na outra.
FAIXA_MAX_LINHAS = 128

# Espessura, em dots, do traço que separa um item do outro na lista de pedidos.
# Um dot é a menor marca que o cabeçote térmico consegue fazer: fino o bastante
# pra não disputar atenção com as linhas de "=" que cercam a tabela, e ainda
# assim contínuo no papel.
_ESPESSURA_SEPARADOR_DOTS = 1

# ESC/POS "GS v 0" — imprime a imagem raster que vem logo depois.
#
# CUIDADO: NÃO é o "GS V 0" de printerService._COMANDO_CORTE, que corta o papel.
# A diferença entre os dois é a caixa da letra (v = 0x76, V = 0x56) e não têm
# nada a ver um com o outro. Escrever um no lugar do outro dá um erro difícil de
# enxergar: a impressora corta o papel e trata a imagem inteira como texto,
# cuspindo metros de lixo.
_COMANDO_RASTER = b"\x1d\x76\x30"

# Ponto de corte entre preto e branco ao converter a imagem (tons de cinza) em 1
# bit por pixel. O QPainter desenha com antialiasing, então as bordas dos glifos
# saem acinzentadas; 128 é o meio da escala, e é o que dá a espessura mais
# parecida com a da fonte na tela. Subir deixa a letra mais gorda (mais cinza
# vira preto), descer deixa mais magra.
_LIMIAR_PRETO = 128

# Um trecho da linha com um estilo só, já resolvido: o texto e os quatro
# atributos que os comandos ESC/POS embutidos ligam/desligam.
#
# A varredura é o inverso exato de comandaEstiloService.formatar_campo — os
# mesmos quatro comandos que ela emite (ESC E, ESC -, GS B, GS !), cada um
# seguido de um byte de parâmetro. comandaParserService._PADRAO_ESTILO descreve
# esses mesmos pares pra DESCARTÁ-los ao ler uma comanda salva; aqui eles são
# interpretados, que é a diferença entre imprimir o negrito e perdê-lo.
_PADRAO_COMANDO = re.compile(
    r"(?:" + re.escape(_ESC) + r"[E\-]|" + re.escape(_GS) + r"[B!])[\s\S]"
    r"|" + re.escape(estilo.MARCA_TAMANHO_PX) + r"\d{3}"
)


class _Estilo:
    """Estado de estilo corrente durante a varredura de uma linha.

    Vive numa classe, e não numa tupla que se recria a cada comando, porque os
    comandos NÃO são aninhados no texto: um "ESC E 1" vale dali pra frente até
    aparecer um "ESC E 0", atravessando quantos outros comandos vierem no meio.
    """

    def __init__(self):
        self.negrito = False
        self.sublinhado = False
        self.reverso = False
        self.tamanho_px = estilo.TAMANHO_FONTE_BASE_PX

    def aplicar(self, comando):
        """Liga/desliga o atributo que `comando` controla."""
        marca, parametro = comando[:2], comando[2:]

        if marca == estilo.MARCA_TAMANHO_PX:
            # O tamanho EXATO, quando ele veio (ver
            # comandaEstiloService.MARCA_TAMANHO_PX). Tem a última palavra
            # sobre o "GS !" que vem ao lado: aquele é o mesmo tamanho já
            # arredondado pro que a impressora saberia fazer, e aqui não há
            # esse limite. A ordem entre os dois no fluxo não importa — o
            # marcador só aparece quando há fonte escolhida, e nesse caso é
            # sempre ele que vale.
            self.tamanho_px = estilo.limitar_tamanho_fonte(int(parametro))
            return

        ligado = ord(parametro) != 0
        if marca == _ESC + "E":
            self.negrito = ligado
        elif marca == _ESC + "-":
            self.sublinhado = ligado
        elif marca == _GS + "B":
            self.reverso = ligado
        elif marca == _GS + "!":
            # "GS !" traz altura nos bits 0-2 e largura nos bits 4-6, cada uma
            # como (multiplicador - 1) — ver comandaEstiloService.
            # _comando_tamanho_fonte, que monta os dois iguais. Lê-se o maior
            # dos dois pra que um valor montado à mão, com altura e largura
            # diferentes, ainda saia legível em vez de espremido.
            valor = ord(parametro)
            altura = (valor & 0x07) + 1
            largura = ((valor >> 4) & 0x07) + 1
            self.tamanho_px = estilo.TAMANHO_FONTE_BASE_PX * max(1, altura, largura)

    def copia(self):
        return (self.negrito, self.sublinhado, self.reverso, self.tamanho_px)


def _trechos_da_linha(linha, estilo):
    """Quebra uma linha do cupom em [(texto, negrito, sublinhado, reverso,
    tamanho_px)], consumindo os comandos de estilo embutidos.

    `estilo` entra e sai mutado de propósito: um campo pode ligar o negrito numa
    linha e a linha seguinte continuar dentro dele (é o que acontece com um
    campo de várias linhas), então o estado atravessa as linhas em vez de zerar
    em cada uma."""
    trechos = []
    posicao = 0

    for comando in _PADRAO_COMANDO.finditer(linha):
        if comando.start() > posicao:
            trechos.append((linha[posicao:comando.start()],) + estilo.copia())
        estilo.aplicar(comando.group())
        posicao = comando.end()

    if posicao < len(linha):
        trechos.append((linha[posicao:],) + estilo.copia())

    return trechos


def _linhas_com_estilo(conteudo):
    """O cupom inteiro como lista de linhas, cada uma já quebrada em trechos
    estilizados (ver _trechos_da_linha)."""
    estilo = _Estilo()
    return [_trechos_da_linha(linha, estilo) for linha in conteudo.split("\n")]


def _largura_celula(tamanho_px):
    """A largura da célula da grade para um texto de `tamanho_px` de altura.

    Mantém a proporção da Fonte A (12 dots de largura para 24 de altura), que é
    a régua em que a comanda foi montada — assim uma linha em tamanho normal
    ocupa exatamente as COLUNAS_PAPEL colunas de sempre, e um campo maior
    cresce nas duas direções junto, como cresceria na impressora."""
    return tamanho_px * LARGURA_CELULA_DOTS / ALTURA_LINHA_DOTS


def _quebrar_em_linhas_fisicas(linhas_logicas, largura_dots, separadoras=()):
    """Transforma as linhas do cupom em linhas FÍSICAS de papel, quebrando o
    que não cabe na largura, e resolve a posição de cada caractere.

    POR QUE PRECISA EXISTIR: uma linha do cupom nem sempre é uma linha de papel.
    Um campo em fonte maior gasta mais espaço por caractere, então
    "Cliente: MARIA DAS GRACAS" passa da largura e a impressora joga o resto pra
    linha de baixo sozinha. A imagem não tem esse reflexo: sem quebrar aqui, o
    que passa da largura é simplesmente cortado fora e some do papel — e o que
    some primeiro é o fim do nome do cliente, do endereço e do sabor da pizza.

    A conta é feita em DOTS, e não em colunas inteiras, porque o tamanho da
    fonte pode ser qualquer valor em pixels quando a comanda é desenhada (ver
    comandaEstiloService.MARCA_TAMANHO_PX) — "quantas colunas este caractere
    ocupa" deixa de ser um número inteiro. Em tamanho normal a conta dá no
    mesmo: 40 células de 12 dots.

    Devolve (linhas físicas, índices das que são divisa entre itens). Cada
    linha física é uma lista de (caractere, x, tamanho_px, negrito, sublinhado,
    reverso). Com as posições já resolvidas, desenhar vira um laço burro — e a
    altura de cada linha pode ser medida antes de existir imagem nenhuma, que é
    o que permite dimensionar o QImage de uma vez só.

    `separadoras` traz índices de linhas LÓGICAS (ver _linhas_entre_itens); a
    tradução pra índices FÍSICOS tem que acontecer aqui dentro, porque é só
    aqui que se sabe quantas linhas de papel cada linha do cupom virou."""
    fisicas = []
    separadores = set()

    for indice, trechos in enumerate(linhas_logicas):
        atual = []
        x = 0.0
        for conteudo, negrito, sublinhado, reverso, tamanho_px in trechos:
            largura_celula = _largura_celula(tamanho_px)
            for caractere in conteudo:
                if x + largura_celula > largura_dots:
                    fisicas.append(atual)
                    atual = []
                    x = 0.0
                atual.append((caractere, x, tamanho_px, negrito, sublinhado, reverso))
                x += largura_celula
        # Mesmo vazia a linha entra: são as linhas em branco do espaçamento
        # entre seções (ver comandaEstiloService.linhas_espacamento_secoes), e
        # engoli-las grudaria as seções umas nas outras.
        fisicas.append(atual)
        # A última linha física desta linha lógica — que numa divisa, sendo ela
        # vazia, é também a única.
        if indice in separadoras:
            separadores.add(len(fisicas) - 1)

    return fisicas, separadores


def _altura_da_linha(glifos):
    """Altura em dots de uma linha física: a do MAIOR texto que aparece nela —
    do mesmo jeito que a impressora empurra a linha inteira pra baixo quando um
    trecho sai em fonte ampliada."""
    if not glifos:
        return ALTURA_LINHA_DOTS
    return max(glifo[2] for glifo in glifos)


def _fonte(familia, tamanho_px, negrito, sublinhado):
    fonte = QFont(familia)
    # Em pixels, não em pontos: a imagem é medida em dots do cabeçote, e um
    # tamanho em pontos passaria pelo DPI da tela, que não tem nada a ver com o
    # papel — a mesma comanda sairia de tamanhos diferentes em cada máquina.
    fonte.setPixelSize(tamanho_px)
    fonte.setBold(negrito)
    fonte.setUnderline(sublinhado)
    return fonte


def _nova_imagem(largura_dots, altura_dots):
    """Uma folha em branco do tamanho pedido, com o pintor já configurado.

    Fundo branco e tinta preta: o papel é branco, e o que for preto na imagem é
    onde o cabeçote térmico queima."""
    imagem = QImage(largura_dots, altura_dots, QImage.Format.Format_Grayscale8)
    imagem.fill(255)

    pintor = QPainter(imagem)
    pintor.setRenderHint(QPainter.RenderHint.TextAntialiasing, True)
    return imagem, pintor


def _desenhar_separador(pintor, topo, altura, largura_dots):
    """Um traço fino cortando o papel de ponta a ponta, centrado na faixa que
    vai de `topo` a `topo + altura`.

    Centrado, e não colado numa das bordas, porque a faixa é o respiro entre
    dois itens: encostar o traço em cima ou embaixo o faria parecer sublinhado
    de um dos dois em vez de divisa entre eles."""
    y = int(topo + (altura - _ESPESSURA_SEPARADOR_DOTS) / 2)
    pintor.fillRect(0, y, int(largura_dots), _ESPESSURA_SEPARADOR_DOTS, QColor(0, 0, 0))


def _pintar_linhas(pintor, fisicas, familia, topo, largura_dots, separadores=()):
    """Pinta as linhas físicas de `fisicas` a partir de `topo` e devolve o topo
    logo abaixo da última — é o desenho em GRADE, usado pelo modelo clássico e
    também pelos trechos fora da tabela de itens no modelo rascunho.

    As linhas cujo índice está em `separadores` saem como um traço de ponta a
    ponta em vez de texto (ver _desenhar_separador): são as linhas em branco
    que separam um item do outro, e o traço ocupa o espaço que já era delas —
    a comanda não fica um dot mais comprida por causa dele.

    Cada caractere é centrado na sua célula da grade — é o que mantém a coluna
    "|" e o ljust da tabela de itens alinhados mesmo numa fonte proporcional
    (ver o cabeçalho do módulo).

    A base do texto fica no fundo da linha menos uma folga de um oitavo da
    altura: sem ela, as letras com descida (g, p, q) encostam na linha de baixo,
    e é justamente onde ficam os nomes dos sabores."""
    # As fontes e suas métricas são caras de montar e se repetem muito (uma
    # comanda inteira costuma usar duas ou três combinações), então cada uma é
    # montada na primeira vez que aparece e reaproveitada daí em diante.
    fontes = {}

    for indice, glifos in enumerate(fisicas):
        altura = _altura_da_linha(glifos)
        base = topo + altura - max(1, altura // 8)

        if indice in separadores:
            _desenhar_separador(pintor, topo, altura, largura_dots)
            topo += altura
            continue

        for caractere, x, tamanho_px, negrito, sublinhado, reverso in glifos:
            chave = (tamanho_px, negrito, sublinhado)
            if chave not in fontes:
                fonte = _fonte(familia, tamanho_px, negrito, sublinhado)
                fontes[chave] = (fonte, QFontMetricsF(fonte))
            fonte, metrica = fontes[chave]
            pintor.setFont(fonte)

            largura_celula = _largura_celula(tamanho_px)
            if reverso:
                # Modo reverso (GS B): tinta no fundo e papel na letra. O
                # retângulo cobre a célula inteira, e não só o glifo, pra que a
                # faixa preta saia contínua ao longo do campo, como sai na
                # impressora.
                # Arredondado pelas BORDAS, não pela largura: duas células
                # vizinhas de largura fracionária arredondadas cada uma por si
                # deixariam uma fresta branca de um dot entre elas, e a faixa
                # preta do campo sairia listrada.
                esquerda = int(round(x))
                direita = int(round(x + largura_celula))
                pintor.fillRect(esquerda, int(topo), direita - esquerda, int(altura), QColor(0, 0, 0))
                pintor.setPen(QColor(255, 255, 255))
            else:
                pintor.setPen(QColor(0, 0, 0))

            folga = (largura_celula - metrica.horizontalAdvance(caractere)) / 2
            pintor.drawText(int(round(x + folga)), int(base), caractere)

        topo += altura

    return topo


def _texto_visivel(trechos):
    """A linha como ela sai no papel: os trechos concatenados, já sem os
    comandos de estilo (que _trechos_da_linha consumiu)."""
    return "".join(conteudo for conteudo, *_atributos in trechos)


def _linhas_entre_itens(logicas):
    """Índices das linhas lógicas que separam um item do outro dentro da tabela
    de itens — as que viram traço em vez de espaço em branco.

    São as linhas em BRANCO entre os dois MARCADOR_ITENS: comandaTextoService.
    formatar_tabela põe exatamente uma delas antes de cada grupo a partir do
    segundo, e é justamente a divisa que se quer marcar. Procurar pelo branco,
    em vez de contar itens, é o que dispensa reler a comanda com o parser —
    e o que faz a conta continuar certa quando um item ocupa três linhas de
    extras e o seguinte, nenhuma.

    Fora da moldura da tabela não se marca nada: linha em branco também é o
    espaçamento entre as seções do cabeçalho e do rodapé (ver comandaEstilo
    Service.linhas_espacamento_secoes), e um traço ali cortaria o cupom no meio
    do endereço. Sem as duas bordas — recibo de extra, de fechamento, comanda
    antiga — não há tabela e não há divisa: devolve vazio."""
    divisorias = [
        indice for indice, trechos in enumerate(logicas)
        if _texto_visivel(trechos) == texto.MARCADOR_ITENS
    ]
    if len(divisorias) < 2:
        return set()

    inicio, fim = divisorias[0], divisorias[1]
    return {
        indice for indice in range(inicio + 1, fim)
        if not _texto_visivel(logicas[indice]).strip()
    }


def _desenhar_modelo_classico(conteudo, familia, largura_dots):
    """A comanda inteira na grade de células, que é o cupom de sempre com
    outras letras. Devolve o QImage, ou None se não sobrou nada a desenhar."""
    logicas = _linhas_com_estilo(conteudo)
    fisicas, separadores = _quebrar_em_linhas_fisicas(
        logicas, largura_dots, _linhas_entre_itens(logicas)
    )
    altura = sum(_altura_da_linha(glifos) for glifos in fisicas)
    if altura <= 0:
        return None

    imagem, pintor = _nova_imagem(largura_dots, altura)
    try:
        _pintar_linhas(pintor, fisicas, familia, 0, largura_dots, separadores)
    finally:
        pintor.end()

    return imagem


# --------------------------------------------------------------------------
# MODELO "RASCUNHO": a tabela de itens em três colunas, como na tela
# --------------------------------------------------------------------------
#
# A ideia: no papel, hoje, um item é "nome ................ | R$ 45,00" e a
# observação dele desce recuada na linha de baixo. Nas telas de Balcão, Entrega
# e Salão o mesmo item é UMA linha com três colunas — Pedido, Observação e
# Valor — e é essa disposição que este modelo leva pro cupom: quem monta o
# pedido na tela e quem lê o papel na cozinha passam a ver a mesma coisa no
# mesmo lugar.
#
# SÓ A TABELA MUDA. Cabeçalho (data, cliente, endereço) e rodapé (forma de
# pagamento, total, status) continuam desenhados na grade do modelo clássico:
# são linhas montadas com ljust/rjust sobre a régua de COLUNAS_PAPEL, e
# redesenhá-las em texto proporcional desalinharia exatamente o que elas
# alinham.
#
# DE ONDE SAEM OS ITENS: da própria comanda em texto, relida por
# comandaParserService.reconstruir_itens — o mesmo caminho que a Consulta usa
# pra reabrir uma comanda gravada. Não há como recebê-los prontos: o que chega
# aqui é o cupom em bytes (ver o cabeçalho do módulo sobre por que a
# rasterização acontece no último instante), e as frações de uma pizza meio a
# meio só voltam a ser um item só depois dessa leitura — que é justamente a
# forma como a tela mostra ("GÊNOVA / FRANGO BACON", uma linha).
#
# QUANDO NÃO DÁ, CAI NO CLÁSSICO: recibo de extra e fechamento não têm tabela
# de itens, uma comanda antiga pode não ter o MARCADOR_ITENS, e um cupom
# montado à mão pode não ser relido. Nesses casos _desenhar_modelo_rascunho
# devolve None e quem chama desenha no modelo de sempre — nunca há cupom que
# deixa de sair por causa da disposição escolhida.

# Proporção entre as colunas Pedido e Observação. São os mesmos números de
# qml/estilo/Responsivo.qml (gradePedido), que é o que faz a tabela impressa
# ter a cara da lista da tela. Mudar lá sem mudar aqui não quebra nada — só
# afasta os dois.
_PROPORCAO_PEDIDO = 0.41
_PROPORCAO_OBSERVACAO = 0.37

# A coluna do Valor NÃO segue a proporção da tela (os 22% que sobram lá), e
# essa é a única liberdade que este modelo toma em relação ao original.
#
# Por quê: a tela tem uns 600 pixels de largura pra três colunas e uma fonte de
# 14; o papel tem 480 dots e uma fonte de 24. Na mesma proporção, o Valor
# ficaria com 100 dots — e "R$ 1.234,56" mede 124 na Figtree em 24px. O preço
# quebraria em duas linhas na comanda de qualquer pedido de três dígitos, que é
# o dado que menos pode sair ambíguo num cupom.
#
# Então a coluna do Valor é MEDIDA: recebe a largura do maior valor da tabela,
# e Pedido/Observação dividem o que sobra na proporção acima. Os limites abaixo
# impedem os dois extremos — uma coluna estreita demais pra caber "R$ 0,00" e
# uma que, por um valor absurdo, coma o nome do item.
_LARGURA_VALOR_MINIMA_DOTS = 6 * LARGURA_CELULA_DOTS
_LARGURA_VALOR_MAXIMA_DOTS = LARGURA_PAPEL_DOTS // 3

# Folga depois do maior valor, pra ele não encostar na borda do papel.
_FOLGA_VALOR_DOTS = LARGURA_CELULA_DOTS // 2

# Vão entre uma coluna e a seguinte, em dots. Uma célula da grade (um
# caractere da Fonte A) é o vão que a tabela clássica usa entre o nome e o
# valor (" | "), e aqui ele faz o mesmo serviço sem a barra.
_VAO_COLUNAS_DOTS = LARGURA_CELULA_DOTS

# O cabeçalho "Pedido / Observação / Valor" sai menor que os itens, como na
# tela (fontSize.sm contra md): ele é rótulo, não conteúdo, e disputar o mesmo
# corpo do nome do sabor só roubaria linha de papel.
_ESCALA_CABECALHO = 0.75

# Recuo das sub-linhas de adicional/borda, em dots — o equivalente aos dois
# espaços que a tabela clássica usa (ver comandaTextoService.formatar_tabela).
_RECUO_EXTRAS_DOTS = 2 * LARGURA_CELULA_DOTS

# Respiro entre um item e o próximo. Na tela é o spacing da ListView; no papel
# é o que impede que duas pizzas com nome comprido virem um bloco só de texto.
_ESPACO_ENTRE_ITENS_DOTS = ALTURA_LINHA_DOTS // 2

# Quebra de linha dentro da célula, em duas versões — e elas NÃO se somam.
#
# Testado neste Qt: pedir as duas juntas (TextWordWrap | TextWrapAnywhere) dá o
# comportamento da segunda sozinha, quebrando no meio da palavra mesmo quando
# havia um espaço logo antes — "SEM CEBOLA, BEM ASSADA" numa coluna estreita
# saía "SEM CEBOLA / , BEM ASSAD / A". Por isso a escolha é uma OU outra, feita
# célula a célula em _Celula._medir: quebra nas palavras por padrão, e só quem
# tem uma palavra mais larga que a própria coluna (nome de sabor colado, código
# comprido) cai na quebra em qualquer letra — que é feia, mas é melhor que o
# texto vazar por cima da coluna vizinha.
_FLAGS_POR_PALAVRA = int(
    Qt.TextFlag.TextWordWrap
    | Qt.AlignmentFlag.AlignLeft
    | Qt.AlignmentFlag.AlignTop
)
_FLAGS_EM_QUALQUER_LETRA = int(
    Qt.TextFlag.TextWrapAnywhere
    | Qt.AlignmentFlag.AlignLeft
    | Qt.AlignmentFlag.AlignTop
)

# Altura de sobra dada ao retângulo de medição. Não limita nada: é só um teto
# alto o bastante pra qualquer célula, já que o que interessa na medida é a
# altura que o texto REALMENTE ocupou dentro dela.
_ALTURA_MEDICAO_DOTS = 10000


def _estilo_de_campo(familia, campo, escala=1.0, negrito=None):
    """(fonte, reverso) para desenhar `campo` neste modelo, a partir dos
    atributos configurados na tela de Configurações.

    O TAMANHO É LIMITADO AO NORMAL (TAMANHO_FONTE_BASE_PX) dentro da tabela, e
    é isso que faz este modelo continuar parecido com a tela em qualquer
    configuração. Dois motivos, que se somam:

    * cabimento — um campo ampliado (o dono pode pedir até 8x) ocupa uns 20
      caracteres por linha na régua inteira do papel, mas só uns quatro numa
      coluna de 40% dela: o nome do sabor viraria uma torre de sílabas;
    * semelhança — na tela de pedidos os três campos têm o mesmo tamanho, e é
      essa a disposição que este modelo copia. Um adicional saindo maior que o
      nome do item não é o que se vê no Balcão.

    Reduções passam intactas: pedir uma observação menor que o normal cabe
    melhor numa coluna, não pior. E a ampliação continua valendo integral no
    modelo clássico, que é onde ela tem a largura do papel inteiro pra usar."""
    atributos = estilo.atributos_campo(campo)
    tamanho_px = min(
        estilo.limitar_tamanho_fonte(atributos.get("tamanho_fonte")),
        estilo.TAMANHO_FONTE_BASE_PX,
    )

    fonte = _fonte(
        familia,
        max(1, int(round(tamanho_px * escala))),
        bool(atributos.get("negrito")) if negrito is None else negrito,
        bool(atributos.get("sublinhado")),
    )
    return fonte, bool(atributos.get("fundo_preto"))


class _Celula:
    """Um pedaço de texto a desenhar num retângulo: o texto, a fonte dele e
    onde ele fica na largura do papel.

    A altura é medida na construção, e não na hora de pintar, porque o QImage
    precisa nascer com a altura total da comanda já sabida — o mesmo motivo
    pelo qual o modelo clássico resolve as posições antes de desenhar (ver
    _quebrar_em_linhas_fisicas)."""

    def __init__(self, texto, x, largura, fonte, reverso=False):
        self.texto = texto
        self.x = x
        self.largura = largura
        self.fonte = fonte
        self.reverso = reverso
        self.flags = _FLAGS_POR_PALAVRA
        self.altura = self._medir()

    def _medir(self):
        """A altura que este texto ocupa na coluna, decidindo de passagem como
        ele vai quebrar (ver _FLAGS_POR_PALAVRA).

        A conta é a mesma que o QPainter refaz ao desenhar, com as mesmas
        flags — é isso que garante que a faixa reservada na imagem seja
        exatamente a que o texto vai ocupar."""
        if not self.texto:
            return 0.0

        metrica = QFontMetricsF(self.fonte)
        caixa = metrica.boundingRect(
            QRectF(0, 0, self.largura, _ALTURA_MEDICAO_DOTS), self.flags, self.texto
        )
        if caixa.width() > self.largura:
            # Quebrando só nas palavras, alguma delas não coube na coluna e
            # vazou. Refaz partindo qualquer letra: a medida devolvida é a
            # largura REALMENTE usada, então esta comparação é o jeito de
            # descobrir o vazamento sem ter que procurar a palavra comprida.
            self.flags = _FLAGS_EM_QUALQUER_LETRA
            caixa = metrica.boundingRect(
                QRectF(0, 0, self.largura, _ALTURA_MEDICAO_DOTS), self.flags, self.texto
            )
        return caixa.height()

    def pintar(self, pintor, topo):
        if not self.texto:
            return

        destino = QRectF(self.x, topo, self.largura, self.altura)
        if self.reverso:
            # Mesma tinta invertida do modo reverso da grade (GS B), aqui
            # cobrindo a célula inteira em vez de caractere a caractere.
            pintor.fillRect(destino, QColor(0, 0, 0))
            pintor.setPen(QColor(255, 255, 255))
        else:
            pintor.setPen(QColor(0, 0, 0))

        pintor.setFont(self.fonte)
        pintor.drawText(destino, self.flags, self.texto)


def _colunas_rascunho(largura_dots, largura_valor):
    """(x, largura) de cada uma das três colunas, em dots, dada a largura já
    medida da coluna do Valor (ver _LARGURA_VALOR_MINIMA_DOTS)."""
    largura_valor = int(max(_LARGURA_VALOR_MINIMA_DOTS, min(_LARGURA_VALOR_MAXIMA_DOTS, largura_valor)))
    util = largura_dots - 2 * _VAO_COLUNAS_DOTS - largura_valor
    # Normalizado entre as duas: elas dividem o que sobra, mantendo entre si a
    # mesma relação que têm na tela.
    pedido = int(round(util * _PROPORCAO_PEDIDO / (_PROPORCAO_PEDIDO + _PROPORCAO_OBSERVACAO)))
    observacao = util - pedido
    return (
        (0, pedido),
        (pedido + _VAO_COLUNAS_DOTS, observacao),
        (pedido + observacao + 2 * _VAO_COLUNAS_DOTS, largura_valor),
    )


def _texto_adicional(adicional, varios_sabores):
    """"+ BACON (R$ 5,00)", e com o sabor no fim quando a pizza tem mais de um
    — senão, numa meio a meio, o adicional não diria em qual metade entra.

    Mesmo formato de components/ResumoComanda.qml (_extrasDoItem), que é o
    resumo de uma linha por item mostrado ao lado do formulário: é a tela que
    este modelo copia, então o extra tem que sair escrito como sai lá."""
    nome = (adicional.get("nome") or "").strip()
    if not nome:
        return ""

    sabor = (adicional.get("sabor") or "").strip()
    # Adicional sem sabor numa pizza dividida é o que vale pra pizza inteira, e
    # isso PRECISA sair escrito: é a diferença entre bacon em tudo e bacon numa
    # metade. O cupom clássico marca com o mesmo sufixo (ver
    # comandaTextoService._extras_adicionais), e a Consulta o lê de volta.
    if varios_sabores and not sabor:
        nome += texto.SUFIXO_ADICIONAL_INTEIRA

    valor = (adicional.get("valor") or "").strip()
    linha = f"{texto.PREFIXO_ADICIONAL}{nome}" + (f" ({valor})" if valor else "")
    return f"{linha} — {sabor}" if varios_sabores and sabor else linha


def _texto_borda(borda):
    """"* BORDA CATUPIRY (R$ 8,00)" — mesmo prefixo do cupom clássico."""
    if not borda:
        return ""

    nome = (borda.get("nome") or "").strip()
    if not nome:
        return ""

    valor = (borda.get("valor") or "").strip()
    return f"{texto.PREFIXO_BORDA}{nome}" + (f" ({valor})" if valor else "")


def _largura_da_coluna_valor(itens, fonte_valor, fonte_cabecalho):
    """A largura que a coluna do Valor precisa ter: a do maior valor da tabela
    (ou do rótulo "Valor", se ele for mais largo), com uma folga.

    Medido item a item, e não estimado por um número de caracteres, porque a
    largura de um dígito muda com a família escolhida — a mesma tabela pede 124
    dots na Figtree e 146 na DejaVu Sans."""
    metrica_valor = QFontMetricsF(fonte_valor)
    larguras = [QFontMetricsF(fonte_cabecalho).horizontalAdvance("Valor")]
    larguras.extend(
        metrica_valor.horizontalAdvance((item.get("valor") or "").strip())
        for item in itens
    )
    return math.ceil(max(larguras)) + _FOLGA_VALOR_DOTS


def _bloco_tabela_rascunho(itens, familia, largura_dots):
    """A tabela inteira como uma lista de faixas [(altura, [células],
    divisa?)], já medida. Quem chama soma as alturas pra dimensionar a imagem e
    depois pinta faixa a faixa — desenhando um traço nas faixas marcadas como
    divisa, que são o respiro entre um item e o seguinte."""
    # O valor do item não tem campo de estilo próprio nem no cupom clássico
    # (ver comandaTextoService.formatar_tabela, que o concatena cru depois do
    # "|") — sai na fonte base, como lá.
    fonte_valor, reverso_valor = _estilo_de_campo(familia, "")
    fonte_cabecalho, _reverso_cabecalho = _estilo_de_campo(
        familia, "", escala=_ESCALA_CABECALHO, negrito=True
    )
    fonte_pedido, reverso_pedido = _estilo_de_campo(familia, "pedido")
    fonte_obs, reverso_obs = _estilo_de_campo(familia, "observacao_item")
    fonte_adicional, reverso_adicional = _estilo_de_campo(familia, "adicional_item")
    fonte_borda, reverso_borda = _estilo_de_campo(familia, "borda_item")

    colunas = _colunas_rascunho(largura_dots, _largura_da_coluna_valor(itens, fonte_valor, fonte_cabecalho))
    (x_pedido, larg_pedido), (x_obs, larg_obs), (x_valor, larg_valor) = colunas
    faixas = []

    def faixa(celulas):
        altas = [celula for celula in celulas if celula.texto]
        if not altas:
            return
        faixas.append((max(celula.altura for celula in altas), altas, False))

    # Cabeçalho das colunas, uma vez só no topo da tabela — é ele que faz a
    # disposição se explicar sozinha pra quem pega o papel. Sem campo de estilo
    # próprio: os rótulos não são conteúdo da comanda, não há por que deixá-los
    # configuráveis junto com o nome do item.
    faixa([
        _Celula("Pedido", x_pedido, larg_pedido, fonte_cabecalho),
        _Celula("Observação", x_obs, larg_obs, fonte_cabecalho),
        _Celula("Valor", x_valor, larg_valor, fonte_cabecalho),
    ])

    largura_extras = largura_dots - _RECUO_EXTRAS_DOTS
    for indice, item in enumerate(itens):
        if indice > 0:
            # O respiro entre os itens, agora com o traço no meio dele: a
            # divisa vem de graça em altura, e é o que impede que os extras
            # recuados de um item pareçam pertencer ao próximo.
            faixas.append((_ESPACO_ENTRE_ITENS_DOTS, [], True))

        pedido = (item.get("pedido") or "").strip()
        # O tamanho da pizza ("(BROTO)") sai junto do nome, no estilo do nome:
        # aqui o item é uma célula só de texto corrido, e não a linha em
        # segmentos da grade, então o campo "pedido_tamanho" não tem onde
        # entrar. É a única configuração de estilo que este modelo não honra.
        faixa([
            _Celula(pedido, x_pedido, larg_pedido, fonte_pedido, reverso_pedido),
            _Celula((item.get("observacao") or "").strip(), x_obs, larg_obs, fonte_obs, reverso_obs),
            _Celula((item.get("valor") or "").strip(), x_valor, larg_valor, fonte_valor, reverso_valor),
        ])

        # Adicionais e borda ocupam a largura toda, recuados sob o item: são
        # texto livre que não caberia numa coluna de 40% do papel, e na tela
        # eles também não vivem dentro das três colunas.
        sabores, _tamanho = texto.dividir_sabores(pedido)
        varios_sabores = len(sabores) > 1
        for adicional in item.get("adicionais") or []:
            faixa([_Celula(
                _texto_adicional(adicional, varios_sabores),
                _RECUO_EXTRAS_DOTS, largura_extras, fonte_adicional, reverso_adicional,
            )])

        faixa([_Celula(
            _texto_borda(item.get("borda")),
            _RECUO_EXTRAS_DOTS, largura_extras, fonte_borda, reverso_borda,
        )])

    return faixas


def _desenhar_modelo_rascunho(conteudo, familia, largura_dots):
    """A comanda com a tabela de itens em três colunas, ou None quando este
    cupom não tem tabela que possa ser relida — aí quem chama desenha no
    modelo clássico.

    As linhas de FORA da tabela são as mesmas do modelo clássico, e vêm da
    varredura de estilo feita sobre o cupom INTEIRO (e não sobre cada pedaço
    separadamente): os comandos ESC/POS valem dali pra frente, e reiniciar o
    estado no meio da comanda perderia um negrito que tivesse sido ligado
    antes da tabela."""
    linhas_limpas = parser.limpar_codigos_impressora(conteudo).split("\n")
    divisorias = [i for i, linha in enumerate(linhas_limpas) if linha == texto.MARCADOR_ITENS]
    if len(divisorias) < 2:
        # Sem as duas bordas da tabela não há o que recortar: é o caso dos
        # recibos de extra e de fechamento, que não têm itens, e das comandas
        # gravadas antes do MARCADOR_ITENS existir.
        #
        # De propósito NÃO se usa aqui o segundo critério de
        # comandaParserService.linhas_tabela_itens ("a 1ª e a 2ª linha de
        # traços do arquivo"), que serve justamente pras comandas antigas. A
        # diferença é o que se faz com o resultado: lá ele é LIDO, e um recorte
        # errado vira um formulário que a pessoa confere na tela; aqui ele é
        # REDESENHADO, e um recorte errado transformaria calado o cabeçalho ou
        # o rodapé do cupom numa tabela de itens inventada. Reimpressão de
        # comanda antiga sai no modelo clássico — igualzinha à que saiu na
        # primeira vez, que é o que se espera de uma segunda via.
        return None

    inicio, fim = divisorias[0], divisorias[1]
    itens = parser.reconstruir_itens(linhas_limpas[inicio + 1:fim])
    if not itens:
        return None

    logicas = _linhas_com_estilo(conteudo)
    # As linhas de marcador ficam com os blocos em grade, uma de cada lado: são
    # a moldura da tabela, e a Consulta as procura de volta no arquivo (que não
    # muda) — no papel elas continuam sendo as duas linhas de "=" de sempre.
    # Sem separadoras nos dois trechos: as divisas entre itens ficam todas
    # dentro da tabela, que aqui é redesenhada em colunas e não passa por eles.
    antes, _antes_sep = _quebrar_em_linhas_fisicas(logicas[:inicio + 1], largura_dots)
    depois, _depois_sep = _quebrar_em_linhas_fisicas(logicas[fim:], largura_dots)
    tabela = _bloco_tabela_rascunho(itens, familia, largura_dots)

    altura = (
        sum(_altura_da_linha(glifos) for glifos in antes)
        + sum(altura_faixa for altura_faixa, _celulas, _divisa in tabela)
        + sum(_altura_da_linha(glifos) for glifos in depois)
    )
    altura_total = int(math.ceil(altura))
    if altura_total <= 0:
        return None

    imagem, pintor = _nova_imagem(largura_dots, altura_total)
    try:
        topo = _pintar_linhas(pintor, antes, familia, 0, largura_dots)
        for altura_faixa, celulas, divisa in tabela:
            if divisa:
                _desenhar_separador(pintor, topo, altura_faixa, largura_dots)
            for celula in celulas:
                celula.pintar(pintor, topo)
            topo += altura_faixa
        _pintar_linhas(pintor, depois, familia, topo, largura_dots)
    finally:
        pintor.end()

    return imagem


def _desenho_do_modelo(conteudo, familia, largura_dots):
    """A comanda desenhada no modelo escolhido em Configurações, com o clássico
    como rede de proteção.

    Um modelo que não sabe desenhar ESTE cupom (o rascunho, num recibo de
    fechamento, que não tem tabela de itens) devolve None e cai aqui no
    clássico. Uma chave desconhecida — vinda pela malha de uma máquina em
    versão mais nova, ver comandaEstiloService.modelo_impressao — também. A
    escolha do dono nunca pode ser motivo pra um pedido não sair no papel."""
    modelo = estilo.modelo_impressao()

    if modelo == estilo.MODELO_RASCUNHO:
        imagem = _desenhar_modelo_rascunho(conteudo, familia, largura_dots)
        if imagem is not None:
            return imagem
        print("[comandaImagemService] Modelo 'rascunho' não se aplica a esta comanda (sem tabela de itens) — desenhando no clássico.")

    return _desenhar_modelo_classico(conteudo, familia, largura_dots)


# Tradução de um byte de cinza pro caractere "0"/"1" do bit correspondente:
# abaixo do limiar é tinta (1), do limiar pra cima é papel (0). Feita com
# bytes.translate porque ela roda uma vez por PIXEL — uma comanda de meio metro
# tem mais de um milhão deles, e um laço em Python por pixel levaria segundos.
_TABELA_BITS = bytes(ord("1") if i < _LIMIAR_PRETO else ord("0") for i in range(256))


def _empacotar(imagem):
    """A imagem em 1 bit por pixel, no formato que o GS v 0 espera: linha por
    linha, 8 pixels por byte, o bit mais significativo à esquerda."""
    largura = imagem.width()
    passo = imagem.bytesPerLine()
    ponteiro = imagem.constBits()
    ponteiro.setsize(imagem.sizeInBytes())
    cinza = bytes(ponteiro)

    bytes_por_linha = largura // 8
    empacotado = bytearray()
    for y in range(imagem.height()):
        # O passo (bytesPerLine) costuma ser maior que a largura por causa do
        # alinhamento interno do Qt — fatiar pela LARGURA, não pelo passo, é o
        # que evita levar o preenchimento junto e entortar a imagem.
        linha = cinza[y * passo:y * passo + largura]
        empacotado += int(linha.translate(_TABELA_BITS), 2).to_bytes(bytes_por_linha, "big")

    return bytes(empacotado), bytes_por_linha


def _comandos_raster(empacotado, bytes_por_linha, altura):
    """Os comandos GS v 0, um por faixa de FAIXA_MAX_LINHAS linhas.

    Formato: GS v 0 m xL xH yL yH + dados, com m=0 (densidade normal), a largura
    em BYTES e a altura em LINHAS, ambas em dois bytes little-endian."""
    comandos = bytearray()
    for inicio in range(0, altura, FAIXA_MAX_LINHAS):
        linhas = min(FAIXA_MAX_LINHAS, altura - inicio)
        comandos += _COMANDO_RASTER
        comandos += b"\x00"
        comandos += bytes_por_linha.to_bytes(2, "little")
        comandos += linhas.to_bytes(2, "little")
        comandos += empacotado[inicio * bytes_por_linha:(inicio + linhas) * bytes_por_linha]

    return bytes(comandos)


# As famílias de fonte desta máquina, lidas uma vez só. None = ainda não lidas.
_familias_locais = None


def familias_locais():
    """As famílias de fonte que ESTA máquina tem — instaladas no sistema mais as
    embarcadas no repositório (ver Config/fontes.py, que registra a Figtree; as
    duas entram na mesma QFontDatabase).

    Lida uma vez e guardada, por dois motivos que se somam:

    1. Só a thread da interface pode consultar o banco de fontes com segurança,
       e quem precisa desta lista quase sempre está em OUTRA thread — a
       detecção de impressora (RedeService._detectar_impressora_em_thread) e a
       impressão (RedeService.solicitar_impressao) rodam ambas em threads
       próprias. Por isso a leitura acontece só quando a chamada vem da thread
       da GUI; fora dela, devolve-se o que já foi lido.
    2. Sem QGuiApplication viva, tocar na QFontDatabase não levanta exceção — o
       Qt ABORTA o processo. Num app gráfico isso nunca acontece, mas este
       código também é alcançado por scripts de linha de comando
       (Config/diagnosticar_impressora.py importa PrinterService sem subir tela
       nenhuma), e lá o processo morreria em vez de imprimir em texto.

    Quem garante que a lista esteja pronta antes das threads precisarem dela é
    o aquecimento na subida do app (ver aquecer_familias, chamado em main.py).
    Sem esse aquecimento a lista fica vazia e a impressão em imagem
    simplesmente não liga — nunca quebra."""
    global _familias_locais

    aplicacao = QGuiApplication.instance()
    if aplicacao is None:
        return []

    # Relida sempre que a chamada vem da thread da interface, e não só na
    # primeira vez: a lista muda depois do aquecimento. A Caprasimo embarcada
    # entra na QFontDatabase pelo FontLoader de qml/estilo/Estilo.qml, que só
    # roda quando a QML sobe — depois de main.py ter aquecido —, e uma fonte
    # instalada no sistema com o app aberto também não apareceria nunca. Quem
    # pergunta da thread da interface é a tela de Configurações montando o
    # seletor, e é justamente ela que precisa da lista certa; quem pergunta de
    # outra thread (detecção de impressora, impressão) recebe a última lida.
    if QThread.currentThread() == aplicacao.thread():
        _familias_locais = list(QFontDatabase.families())

    return _familias_locais or []


def aquecer_familias():
    """Lê a lista de fontes agora, pra que as threads de detecção e de
    impressão a encontrem pronta depois (ver familias_locais). Chamado na
    subida do app, na thread da interface, depois de Config/fontes.aplicar —
    que é o que põe a Figtree embarcada dentro da QFontDatabase."""
    familias = familias_locais()
    print(f"[comandaImagemService] {len(familias)} família(s) de fonte disponíveis pra desenhar a comanda.")
    return familias


def fonte_disponivel(familia):
    """Se `familia` pode ser usada pra desenhar nesta máquina.

    Existe porque o estilo é sincronizado entre as máquinas da malha: o dono
    escolhe uma fonte numa, e a máquina que de fato imprime pode não ter essa
    fonte. Sem esta checagem, o Qt substituiria calado por uma parecida e a
    comanda sairia numa tipografia que ninguém escolheu — melhor cair no texto
    de sempre."""
    return bool(familia) and familia in familias_locais()


def para_raster(conteudo_bytes, familia, largura_dots=LARGURA_PAPEL_DOTS):
    """Converte uma comanda em texto ESC/POS na mesma comanda em imagem
    ESC/POS, desenhada na fonte `familia` e na disposição escolhida em
    Configurações (ver _desenho_do_modelo).

    Devolve None quando não dá pra rasterizar — sem fonte escolhida, com uma
    fonte que não existe nesta máquina, sem QGuiApplication viva (o desenho de
    texto precisa do banco de fontes do Qt) ou se o desenho falhar. Quem chama
    trata None como "imprime o texto do jeito de sempre": um cupom na fonte
    errada é um contratempo, um cupom que não sai é um pedido perdido.

    Roda na thread de impressão, não na da interface (ver RedeService.
    solicitar_impressao). Por isso tudo aqui é QImage e QPainter, nunca QPixmap,
    que não é seguro fora da thread da GUI — a mesma restrição que
    services/iconProvider.py documenta."""
    if not fonte_disponivel(familia):
        return None

    try:
        conteudo = conteudo_bytes.decode(texto.CODEPAGE_IMPRESSORA, errors="replace")
        imagem = _desenho_do_modelo(conteudo, familia, largura_dots)
        if imagem is None:
            return None

        empacotado, bytes_por_linha = _empacotar(imagem)
        return _comandos_raster(empacotado, bytes_por_linha, imagem.height())
    except Exception as erro:
        # Melhor esforço, como em Config/fontes.py: qualquer falha aqui vira
        # aviso no log e a comanda sai em texto. Isto roda dentro da thread de
        # impressão, onde uma exceção que escapa mata o job em silêncio.
        print(f"[comandaImagemService] Falha ao desenhar a comanda em '{familia}': {erro}")
        return None
