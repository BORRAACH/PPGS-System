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

# A PROPORÇÃO de um caractere da Fonte A (12 dots de largura para 24 de
# altura), que é a fonte da impressora no caminho de texto. Continua sendo a
# referência de FORMATO da célula, e a unidade em que as medidas do modelo
# rascunho estão escritas — mas não é mais a largura final de uma coluna, que
# hoje sai de _LARGURA_COLUNA_DOTS, logo abaixo.
LARGURA_CELULA_DOTS = 12
ALTURA_LINHA_DOTS = 24

# Largura útil do cabeçote da Bematech MP-4200 TH (ver printerService): 72mm a
# 203 dpi dão 576 dots, ou 48 colunas de Fonte A.
#
# A comanda, porém, é montada numa régua de 40 colunas (comandaTextoService.
# COLUNAS_PAPEL) — e era daí que vinha a sobra à direita: 40 colunas de 12 dots
# pintam 480, deixando 96 dots (uns 12mm) de papel em branco na beirada com o
# texto todo empurrado pra esquerda. No cupom de TEXTO essa sobra também
# existe, mas ali não há como mexer: quem escolhe a largura do caractere é a
# impressora. Aqui, desenhando, dá — e é o que _LARGURA_COLUNA_DOTS faz.
#
# Múltiplo de 8 de propósito: o raster manda 1 bit por pixel, então cada linha
# da imagem tem que virar um número inteiro de bytes (576 / 8 = 72).
LARGURA_PAPEL_DOTS = 576

# Margem lateral do CONTEÚDO, em dots, de cada lado. Só o texto a respeita: as
# linhas divisórias atravessam o papel inteiro, de beirada a beirada (ver
# _desenhar_separador) — é a divisa que precisa parecer um corte no papel, e
# uma que parasse antes da borda pareceria um sublinhado comprido.
_MARGEM_LATERAL_DOTS = 5

# O que sobra pro conteúdo depois das duas margens.
LARGURA_UTIL_DOTS = LARGURA_PAPEL_DOTS - 2 * _MARGEM_LATERAL_DOTS

# A régua de 40 colunas esticada sobre a largura útil: uma coluna deixa de
# medir 12 dots e passa a medir 14,15. É o que faz a comanda ocupar o papel
# inteiro em vez de cinco sextos dele.
#
# A régua continua sendo de COLUNAS_PAPEL colunas, e é isso que importa: o
# ljust da tabela de itens, a coluna "|" e as linhas de traço fecham porque
# todas as colunas têm a MESMA largura, não porque essa largura seja 12. O que
# muda no papel é só o espaçamento entre as letras, que ficam com um pouco mais
# de folga dentro da célula — o corpo delas continua vindo do tamanho de fonte
# configurado.
_LARGURA_COLUNA_DOTS = LARGURA_UTIL_DOTS / texto.COLUNAS_PAPEL

# Quantas linhas de imagem vão em cada comando de raster. A imagem inteira num
# comando só depende de a impressora ter buffer pra ela — e uma comanda comprida
# tem uns dois mil pontos de altura. Fatiar é o que garante que o cupom não sai
# pela metade numa impressora com buffer curto; o papel não vê diferença, as
# faixas saem coladas uma na outra.
FAIXA_MAX_LINHAS = 128

# Espessura, em dots, de cada traço horizontal da comanda. Os três desenham a
# HIERARQUIA do cupom pela grossura: o marcador que cerca a tabela de itens é o
# corte mais forte, a divisória entre campos vem depois, e a divisa entre dois
# itens é a mais leve — está dentro da tabela, e não pode competir com a
# moldura dela.
#
# Todos cabem dentro da altura da linha que substituem, então nenhum custa
# papel: o cupom sai com o mesmo comprimento de antes.
_ESPESSURA_MARCADOR_ITENS_DOTS = 7
_ESPESSURA_SEPARADOR_CAMPOS_DOTS = 5
_ESPESSURA_ENTRE_ITENS_DOTS = 3

# A linha de traços que separa um campo do outro, como comandaTextoService a
# monta ("-" * COLUNAS_PAPEL, ver montar_linhas_por_ordem). Comparada inteira,
# e não por "só tem hífens", pra que um "---" digitado numa observação continue
# saindo como texto — o que vira traço é a divisória que o app gerou.
_LINHA_SEPARADORA_CAMPOS = "-" * texto.COLUNAS_PAPEL

# O ícone de cada forma de pagamento, pelo nome do qtawesome. É a MESMA lista
# de qml/components/ComboBoxPagamento.qml (iconesPagamento), e de propósito: o
# ícone que a pessoa escolheu na tela é o que ela espera reencontrar no papel.
# Mudar lá sem mudar aqui não quebra nada — só afasta os dois, e aí o cupom
# passa a mostrar um desenho que não é o do botão que foi clicado.
#
# Uma forma fora da lista (opção nova, comanda antiga) simplesmente não ganha
# ícone. O combo da tela cai num "fa6s.receipt" genérico nesse caso, porque lá
# a linha ficaria torta sem nenhum; no papel um ícone que não diz nada é só
# tinta, e a palavra ao lado já diz tudo.
_ICONES_PAGAMENTO = {
    "Pix": "fa6b.pix",
    "Crédito": "fa6s.credit-card",
    "Débito": "fa6s.money-check-dollar",
    "Dinheiro": "fa6s.money-bill-wave",
}

# A linha do cupom que leva o ícone: a ESCOLHA da forma de pagamento, como
# balcaoController e entregaController a montam. O mesmo texto que
# comandaParserService.PADRAO_FORMA_PAGAMENTO lê de volta — e que continua
# intacto, porque o ícone é desenhado ao lado, sem tocar num byte do cupom.
_PADRAO_FORMA_PAGAMENTO = re.compile(r"^Forma de pagamento:\s*(.+?)\s*$")

# Vão entre o fim da palavra e o ícone, como fração da altura do texto — assim
# ele acompanha o tamanho de fonte configurado pro campo em vez de encostar na
# palavra num tamanho e ficar perdido no outro.
#
# É um vão PREFERIDO, não fixo: quem manda na linha é o ícone, que sai sempre
# do tamanho do texto (ver _desenhar_icone), e o vão cede o que for preciso pra
# ele caber. Numa linha folgada vale este valor inteiro.
_FOLGA_ICONE = 0.35

# O vão mínimo, em dots, abaixo do qual o ícone estaria encostado na palavra —
# aí ele parece parte dela em vez de um símbolo ao lado. Quando nem isto cabe,
# a linha sai sem ícone.
#
# Três dots parece pouco e não é: o vão VISÍVEL é maior, porque a última letra
# não preenche a célula dela até a borda (a grade dá a cada caractere a largura
# de uma coluna, e a maioria dos glifos ocupa menos). É este valor que faz
# caber a linha mais cheia desta comanda — "Forma de pagamento: Dinheiro" com o
# campo em 50px, onde sobram 3,2 dots depois do ícone.
_FOLGA_MINIMA_ICONE_DOTS = 3

# {forma de pagamento: (família da fonte, caractere do glifo)}, preenchido pelo
# aquecimento (ver aquecer_icones_pagamento). Vazio = sem ícone nenhum, e a
# comanda sai como sempre saiu.
_icones_pagamento = {}

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

    Uma linha em tamanho NORMAL ocupa exatamente as COLUNAS_PAPEL colunas de
    sempre — só que agora essas colunas cobrem a largura útil do papel inteiro
    (ver _LARGURA_COLUNA_DOTS) em vez dos 480 dots da Fonte A. Um campo maior
    cresce nas duas direções junto, como cresceria na impressora, e é por isso
    que a conta continua sendo uma proporção do tamanho e não um valor fixo:
    uma linha em fonte dobrada segue cabendo em metade das colunas."""
    return tamanho_px * _LARGURA_COLUNA_DOTS / ALTURA_LINHA_DOTS


def _quebrar_em_linhas_fisicas(linhas_logicas, largura_dots):
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

    Devolve (linhas físicas, {índice físico: espessura do traço}). Cada linha
    física é uma lista de (caractere, x, tamanho_px, negrito, sublinhado,
    reverso). Com as posições já resolvidas, desenhar vira um laço burro — e a
    altura de cada linha pode ser medida antes de existir imagem nenhuma, que é
    o que permite dimensionar o QImage de uma vez só.

    Devolve junto o mapa {índice lógico: índice da ÚLTIMA linha física dele},
    que é o que permite traduzir qualquer marcação feita sobre o texto do cupom
    (traços, ícones) para a linha de papel correspondente — só aqui se sabe em
    quantas linhas cada linha do cupom se quebrou. Ver _por_linha_fisica."""
    fisicas = []
    ultima_fisica = {}

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
        # A ÚLTIMA das linhas físicas desta linha lógica. É a que interessa às
        # duas marcações: uma linha de traço nunca chega perto de quebrar (é
        # sempre a única), e o ícone vai depois do fim do texto, que é onde a
        # última linha acaba.
        ultima_fisica[indice] = len(fisicas) - 1

    return fisicas, ultima_fisica


def _por_linha_fisica(marcas, ultima_fisica):
    """As marcas de _tracos_da_comanda/_icones_da_comanda, que vêm indexadas
    por linha LÓGICA, reindexadas por linha FÍSICA (ver
    _quebrar_em_linhas_fisicas)."""
    return {
        ultima_fisica[indice]: marca
        for indice, marca in marcas.items()
        if indice in ultima_fisica
    }


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
    """Uma folha em branco com `largura_dots` de conteúdo mais as duas margens
    laterais, e o pintor já configurado.

    Fundo branco e tinta preta: o papel é branco, e o que for preto na imagem é
    onde o cabeçote térmico queima.

    A ORIGEM DO PINTOR FICA NA MARGEM, não na borda do papel. É o que permite
    todo o resto do módulo continuar medindo e posicionando de 0 até a largura
    ÚTIL, sem carregar um deslocamento em cada conta: quem desenha texto não
    precisa saber que existe margem. Quem precisa atravessá-la é só o traço
    divisório, que desenha a partir de x negativo (ver _desenhar_separador)."""
    imagem = QImage(
        int(largura_dots) + 2 * _MARGEM_LATERAL_DOTS,
        altura_dots,
        QImage.Format.Format_Grayscale8,
    )
    imagem.fill(255)

    pintor = QPainter(imagem)
    pintor.setRenderHint(QPainter.RenderHint.TextAntialiasing, True)
    pintor.translate(_MARGEM_LATERAL_DOTS, 0)
    return imagem, pintor


def _desenhar_separador(pintor, topo, altura, largura_dots, espessura):
    """Um traço de `espessura` dots cortando o papel de ponta a ponta, centrado
    na faixa que vai de `topo` a `topo + altura`.

    Centrado, e não colado numa das bordas, porque a faixa é o respiro entre
    dois itens: encostar o traço em cima ou embaixo o faria parecer sublinhado
    de um dos dois em vez de divisa entre eles.

    COMEÇA EM X NEGATIVO e mede a largura útil mais as duas margens: a origem
    do pintor está na margem esquerda (ver _nova_imagem), então -_MARGEM_
    LATERAL_DOTS é a beirada do papel. É a única coisa do desenho que sai de
    dentro das margens, e de propósito — o traço tem que cortar a comanda de
    ponta a ponta."""
    y = int(topo + (altura - espessura) / 2)
    pintor.fillRect(
        -_MARGEM_LATERAL_DOTS,
        y,
        int(largura_dots) + 2 * _MARGEM_LATERAL_DOTS,
        espessura,
        QColor(0, 0, 0),
    )


def _desenhar_icone(pintor, glifos, base, largura_dots, familia, icone):
    """Desenha `icone` logo depois do último caractere da linha, no tamanho do
    texto dele.

    NO TAMANHO DO TEXTO, e não num tamanho fixo: o dono configura o corpo da
    forma de pagamento (pode estar em 50px), e um ícone de tamanho fixo ao lado
    de uma palavra dessas ficaria uma miniatura perdida. Assim ele acompanha a
    palavra em qualquer configuração.

    Na mesma BASE das letras, também: o glifo do Font Awesome é desenhado sobre
    a linha de base como qualquer caractere, então usar a base da linha é o que
    o deixa assentado junto da palavra em vez de flutuando.

    O TAMANHO É SEMPRE O DO TEXTO. Quem cede pra ele caber é o VÃO até a
    palavra, e não o ícone: um ícone menor que a palavra ao lado sai como uma
    nota de rodapé do campo, quando ele é o próprio campo dito em desenho.
    Numa linha folgada o vão vale _FOLGA_ICONE inteiro; numa linha apertada
    encolhe até _FOLGA_MINIMA_ICONE_DOTS, e é isso que faz caber a linha mais
    cheia que esta comanda tem — "Forma de pagamento: Dinheiro" com o campo em
    50px ocupa quase a régua toda.

    E QUANDO NEM ASSIM CABE, o ícone avança sobre a margem lateral — só ele, e
    só o quanto precisar. É uma exceção deliberada à margem de
    _MARGEM_LATERAL_DOTS, e existe porque sem ela o recurso quase não
    apareceria: medido nas comandas gravadas, "Forma de pagamento: Dinheiro"
    com o campo em 48px (que é a configuração desta casa, e 278 das 300 últimas
    comandas) fica 2 dots mais larga que a área de conteúdo. Perder o ícone em
    93% dos cupons pra preservar 2 dots de margem é o troco errado.

    Nesse caso o vão fica no mínimo, e não no preferido: assim o ícone avança o
    mínimo possível e sobra o máximo de papel depois dele.

    Passando da borda do PAPEL, aí sim a linha sai sem ícone — melhor perdê-lo
    do que imprimi-lo cortado."""
    ultimo = None
    for glifo in glifos:
        if glifo[0].strip():
            ultimo = glifo

    if ultimo is None:
        return

    caractere, x, tamanho_px, negrito, sublinhado, _reverso = ultimo

    # O fim do DESENHO da última letra, não o fim da célula dela. A grade dá a
    # cada caractere a largura de uma coluna e o desenha centrado (ver
    # _pintar_linhas), então entre o fim do traço da letra e a borda da célula
    # sempre sobra um pedaço — medir da borda contaria esse pedaço duas vezes e
    # afastaria o ícone mais do que o pedido, além de gastar largura que numa
    # linha cheia faz falta.
    metrica_texto = QFontMetricsF(_fonte(familia, tamanho_px, negrito, sublinhado))
    largura_celula = _largura_celula(tamanho_px)
    fim_do_texto = x + (largura_celula + metrica_texto.horizontalAdvance(caractere)) / 2

    familia_icone, caractere_icone = icone
    fonte_icone = QFont(familia_icone)
    fonte_icone.setPixelSize(tamanho_px)
    avanco = QFontMetricsF(fonte_icone).horizontalAdvance(caractere_icone)

    sobra_util = largura_dots - fim_do_texto
    if sobra_util >= avanco + _FOLGA_MINIMA_ICONE_DOTS:
        folga = min(tamanho_px * _FOLGA_ICONE, sobra_util - avanco)
    else:
        # A margem direita, em coordenadas do pintor: a origem dele está na
        # margem esquerda (ver _nova_imagem), então a borda do papel fica em
        # largura útil + uma margem.
        sobra_papel = largura_dots + _MARGEM_LATERAL_DOTS - fim_do_texto
        if sobra_papel < avanco + _FOLGA_MINIMA_ICONE_DOTS:
            return
        folga = _FOLGA_MINIMA_ICONE_DOTS

    esquerda = fim_do_texto + folga

    pintor.setFont(fonte_icone)
    pintor.setPen(QColor(0, 0, 0))
    pintor.drawText(int(round(esquerda)), int(base), caractere_icone)


def _pintar_linhas(pintor, fisicas, familia, topo, largura_dots, tracos=None, icones=None):
    """Pinta as linhas físicas de `fisicas` a partir de `topo` e devolve o topo
    logo abaixo da última — é o desenho em GRADE, usado pelo modelo clássico e
    também pelos trechos fora da tabela de itens no modelo rascunho.

    `tracos` diz quais linhas saem como um traço de ponta a ponta em vez de
    texto, e com que espessura (ver _tracos_de_texto e _linhas_entre_itens). O
    traço ocupa o espaço que já era da linha, então a comanda não fica um dot
    mais comprida por causa dele.

    `icones` diz quais linhas ganham um ícone depois do texto (ver
    _icones_da_comanda). Os dois mapas são indexados por linha FÍSICA, já
    traduzidos por quem chama.

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
    tracos = tracos or {}
    icones = icones or {}

    for indice, glifos in enumerate(fisicas):
        altura = _altura_da_linha(glifos)
        base = topo + altura - max(1, altura // 8)

        espessura = tracos.get(indice)
        if espessura:
            _desenhar_separador(pintor, topo, altura, largura_dots, espessura)
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

            # Nunca à esquerda da margem: num campo configurado em fonte bem
            # maior que a base, o caractere fica MAIS LARGO que a própria
            # célula, a folga vira negativa e o glifo da primeira coluna
            # invadiria a margem — encostando na beirada do papel. No meio da
            # linha a folga negativa segue valendo (é o que faz os caracteres
            # se sobreporem de leve, como já se sobrepunham); só a saída pela
            # borda é que não pode acontecer.
            pintor.drawText(max(0, int(round(x + folga))), int(base), caractere)

        icone = icones.get(indice)
        if icone:
            _desenhar_icone(pintor, glifos, base, largura_dots, familia, icone)

        topo += altura

    return topo


def _texto_visivel(trechos):
    """A linha como ela sai no papel: os trechos concatenados, já sem os
    comandos de estilo (que _trechos_da_linha consumiu)."""
    return "".join(conteudo for conteudo, *_atributos in trechos)


def _espessura_do_traco(visivel):
    """A espessura do traço que substitui esta linha, ou None se ela é texto.

    As duas linhas que o cupom monta com caracteres repetidos saem desenhadas:
    o MARCADOR_ITENS ("=" * 40) que cerca a tabela e a divisória de campos
    ("-" * 40). Desenhadas ficam contínuas e com a grossura escolhida; em
    caracteres elas saíam com a falha entre um glifo e o outro, e o "=", que é
    de dois riscos, saía como uma linha DUPLA — que é o que se via em cima do
    primeiro item e embaixo do último."""
    if visivel == texto.MARCADOR_ITENS:
        return _ESPESSURA_MARCADOR_ITENS_DOTS
    if visivel == _LINHA_SEPARADORA_CAMPOS:
        return _ESPESSURA_SEPARADOR_CAMPOS_DOTS
    return None


def _tracos_de_texto(logicas):
    """{índice: espessura} das linhas que o próprio texto do cupom já diz serem
    traço (ver _espessura_do_traco).

    Vale pra qualquer pedaço da comanda, porque cada linha se explica sozinha —
    é o que permite chamá-la também sobre os recortes de antes e depois da
    tabela no modelo rascunho."""
    espessuras = {}
    for indice, trechos in enumerate(logicas):
        espessura = _espessura_do_traco(_texto_visivel(trechos).strip())
        if espessura:
            espessuras[indice] = espessura
    return espessuras


def _linhas_entre_itens(logicas):
    """Índices das linhas lógicas que separam um item do outro dentro da tabela
    de itens — as que viram traço em vez de espaço em branco.

    São as linhas em BRANCO entre os dois MARCADOR_ITENS: comandaTextoService.
    formatar_tabela põe exatamente uma delas antes de cada grupo a partir do
    segundo, e é justamente a divisa que se quer marcar. Procurar pelo branco,
    em vez de contar itens, é o que dispensa reler a comanda com o parser —
    e o que faz a conta continuar certa quando um item ocupa três linhas de
    extras e o seguinte, nenhuma.

    SÓ ENTRE DOIS ITENS, e é por isso que a conta não é simplesmente "toda
    linha em branco entre os marcadores". Dentro da moldura também entra o
    espaçamento de seção (comandaEstiloService.linhas_espacamento_secoes, que
    pode ser 2 ou mais), logo depois do marcador de cima e logo antes do de
    baixo — aquilo é o respiro da tabela inteira, não divisa entre itens, e
    marcá-lo punha um traço grudado em cada marcador, DOBRADO quando o
    espaçamento era de duas linhas. Por isso os brancos das duas pontas ficam
    de fora, contando a partir do primeiro item e até o último.

    Uma CORRIDA de brancos vale um traço só, pelo mesmo motivo: dois traços
    empilhados não separam melhor que um, só engordam a divisa.

    Fora da moldura da tabela não se marca nada: um traço no espaçamento do
    cabeçalho cortaria o cupom no meio do endereço. Sem as duas bordas —
    recibo de extra, de fechamento, comanda antiga — não há tabela e não há
    divisa: devolve vazio."""
    divisorias = [
        indice for indice, trechos in enumerate(logicas)
        if _texto_visivel(trechos) == texto.MARCADOR_ITENS
    ]
    if len(divisorias) < 2:
        return set()

    inicio, fim = divisorias[0], divisorias[1]
    com_conteudo = [
        indice for indice in range(inicio + 1, fim)
        if _texto_visivel(logicas[indice]).strip()
    ]
    if len(com_conteudo) < 2:
        # Zero ou um item: não há nada que separar.
        return set()

    divisas = set()
    branca_anterior = False
    for indice in range(com_conteudo[0] + 1, com_conteudo[-1]):
        branca = not _texto_visivel(logicas[indice]).strip()
        if branca and not branca_anterior:
            divisas.add(indice)
        branca_anterior = branca

    return divisas


def _icones_da_comanda(logicas):
    """{índice: (família, caractere)} das linhas que levam um ícone ao lado.

    Hoje é uma só: a linha da forma de pagamento escolhida (ver
    _PADRAO_FORMA_PAGAMENTO). Uma forma sem ícone no mapa não entra, e a linha
    sai como sempre saiu."""
    marcas = {}
    if not _icones_pagamento:
        return marcas

    for indice, trechos in enumerate(logicas):
        casou = _PADRAO_FORMA_PAGAMENTO.match(_texto_visivel(trechos).strip())
        if not casou:
            continue

        icone = _icones_pagamento.get(casou.group(1).strip())
        if icone:
            marcas[indice] = icone

    return marcas


def _tracos_da_comanda(logicas):
    """{índice: espessura} de todos os traços do cupom — os que o texto já
    trazia e as divisas entre itens."""
    espessuras = _tracos_de_texto(logicas)
    for indice in _linhas_entre_itens(logicas):
        espessuras[indice] = _ESPESSURA_ENTRE_ITENS_DOTS
    return espessuras


def _desenhar_modelo_classico(conteudo, familia, largura_dots):
    """A comanda inteira na grade de células, que é o cupom de sempre com
    outras letras. Devolve o QImage, ou None se não sobrou nada a desenhar."""
    logicas = _linhas_com_estilo(conteudo)
    fisicas, ultima_fisica = _quebrar_em_linhas_fisicas(logicas, largura_dots)
    tracos = _por_linha_fisica(_tracos_da_comanda(logicas), ultima_fisica)
    icones = _por_linha_fisica(_icones_da_comanda(logicas), ultima_fisica)
    altura = sum(_altura_da_linha(glifos) for glifos in fisicas)
    if altura <= 0:
        return None

    imagem, pintor = _nova_imagem(largura_dots, altura)
    try:
        _pintar_linhas(pintor, fisicas, familia, 0, largura_dots, tracos, icones)
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
_LARGURA_VALOR_MAXIMA_DOTS = LARGURA_UTIL_DOTS // 3

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
    # Só _tracos_de_texto nos dois recortes: as divisas ENTRE ITENS ficam
    # todas dentro da tabela, que aqui é redesenhada em colunas e não passa por
    # eles — mas o marcador de cada ponta e as divisórias de campo do cabeçalho
    # e do rodapé estão justamente aqui, e continuam saindo desenhados.
    fatia_antes = logicas[:inicio + 1]
    fatia_depois = logicas[fim:]
    antes, ultima_antes = _quebrar_em_linhas_fisicas(fatia_antes, largura_dots)
    depois, ultima_depois = _quebrar_em_linhas_fisicas(fatia_depois, largura_dots)
    tracos_antes = _por_linha_fisica(_tracos_de_texto(fatia_antes), ultima_antes)
    tracos_depois = _por_linha_fisica(_tracos_de_texto(fatia_depois), ultima_depois)
    # A forma de pagamento sai no rodapé, então na prática o ícone cai sempre
    # no recorte de depois — mas os dois passam pela mesma regra, que é o que
    # mantém isto valendo se a ordem das seções mudar (ela é configurável, ver
    # comandaEstiloService.ordem_secoes).
    icones_antes = _por_linha_fisica(_icones_da_comanda(fatia_antes), ultima_antes)
    icones_depois = _por_linha_fisica(_icones_da_comanda(fatia_depois), ultima_depois)
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
        topo = _pintar_linhas(pintor, antes, familia, 0, largura_dots, tracos_antes, icones_antes)
        for altura_faixa, celulas, divisa in tabela:
            if divisa:
                _desenhar_separador(
                    pintor, topo, altura_faixa, largura_dots, _ESPESSURA_ENTRE_ITENS_DOTS
                )
            for celula in celulas:
                celula.pintar(pintor, topo)
            topo += altura_faixa
        _pintar_linhas(pintor, depois, familia, topo, largura_dots, tracos_depois, icones_depois)
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


def aquecer_icones_pagamento():
    """Resolve, AGORA e na thread da interface, a fonte e o caractere de cada
    ícone de forma de pagamento (ver _ICONES_PAGAMENTO), pra que a thread de
    impressão só precise montar um QFont depois.

    POR QUE AQUI, E NÃO NA HORA DE DESENHAR: o qtawesome carrega os arquivos de
    fonte na primeira vez que é chamado, e mexer na QFontDatabase fora da
    thread da interface tem o mesmo problema documentado em familias_locais —
    com o agravante de que este módulo desenha dentro da thread de impressão.
    Resolvido uma vez na subida, o que sobra pro desenho é (família,
    caractere), que são só dados.

    O ÍCONE VIRA UM GLIFO DE TEXTO, e não uma imagem: qta.icon() devolveria um
    QIcon, e dele sai QPixmap — que não é seguro fora da thread da GUI, a mesma
    restrição que fez este módulo inteiro ser QImage/QPainter (ver
    para_raster). Desenhado como caractere de uma fonte, o ícone passa pelo
    mesmo QPainter das letras e some o problema.

    Melhor esforço: sem qtawesome instalado, ou sem interface viva, o cupom sai
    sem ícone — que é exatamente como ele saía antes disto existir."""
    global _icones_pagamento

    try:
        import qtawesome as qta

        icones = {}
        for forma, nome in _ICONES_PAGAMENTO.items():
            prefixo = nome.split(".")[0]
            icones[forma] = (qta.font(prefixo, 24).family(), qta.charmap(nome))
        _icones_pagamento = icones
    except Exception as erro:
        print(f"[comandaImagemService] Sem ícones de forma de pagamento no cupom: {erro}")
        return {}

    print(f"[comandaImagemService] {len(_icones_pagamento)} ícone(s) de forma de pagamento prontos pro cupom.")
    return _icones_pagamento


def aquecer_familias():
    """Lê a lista de fontes agora, pra que as threads de detecção e de
    impressão a encontrem pronta depois (ver familias_locais). Chamado na
    subida do app, na thread da interface, depois de Config/fontes.aplicar —
    que é o que põe a Figtree embarcada dentro da QFontDatabase.

    Aproveita e resolve os ícones de forma de pagamento, que precisam da mesma
    thread e do mesmo momento (ver aquecer_icones_pagamento)."""
    familias = familias_locais()
    print(f"[comandaImagemService] {len(familias)} família(s) de fonte disponíveis pra desenhar a comanda.")
    aquecer_icones_pagamento()
    return familias


def fonte_disponivel(familia):
    """Se `familia` pode ser usada pra desenhar nesta máquina.

    Existe porque o estilo é sincronizado entre as máquinas da malha: o dono
    escolhe uma fonte numa, e a máquina que de fato imprime pode não ter essa
    fonte. Sem esta checagem, o Qt substituiria calado por uma parecida e a
    comanda sairia numa tipografia que ninguém escolheu — melhor cair no texto
    de sempre."""
    return bool(familia) and familia in familias_locais()


def para_raster(conteudo_bytes, familia, largura_dots=LARGURA_UTIL_DOTS):
    """Converte uma comanda em texto ESC/POS na mesma comanda em imagem
    ESC/POS, desenhada na fonte `familia` e na disposição escolhida em
    Configurações (ver _desenho_do_modelo).

    `largura_dots` é a largura do CONTEÚDO; a imagem sai com as duas margens
    laterais somadas a ela (ver _nova_imagem), ocupando o cabeçote inteiro.

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
