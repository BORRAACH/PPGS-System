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

import re

from PyQt6.QtCore import QThread
from PyQt6.QtGui import QColor, QFont, QFontDatabase, QFontMetricsF, QGuiApplication, QImage, QPainter

from services import comandaEstiloService as estilo
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

    Devolve uma lista de linhas físicas, cada uma uma lista de
    (caractere, x, tamanho_px, negrito, sublinhado, reverso). Com as posições já
    resolvidas, desenhar vira um laço burro — e a altura de cada linha pode ser
    medida antes de existir imagem nenhuma, que é o que permite dimensionar o
    QImage de uma vez só."""
    fisicas = []

    for trechos in linhas_logicas:
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

    return fisicas


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


def _desenhar(fisicas, familia, largura_dots, altura_dots):
    """Desenha o cupom inteiro e devolve o QImage em tons de cinza.

    Fundo branco e tinta preta: o papel é branco, e o que for preto na imagem é
    onde o cabeçote térmico queima.

    Cada caractere é centrado na sua célula da grade — é o que mantém a coluna
    "|" e o ljust da tabela de itens alinhados mesmo numa fonte proporcional
    (ver o cabeçalho do módulo).

    A base do texto fica no fundo da linha menos uma folga de um oitavo da
    altura: sem ela, as letras com descida (g, p, q) encostam na linha de baixo,
    e é justamente onde ficam os nomes dos sabores."""
    imagem = QImage(largura_dots, altura_dots, QImage.Format.Format_Grayscale8)
    imagem.fill(255)

    pintor = QPainter(imagem)
    pintor.setRenderHint(QPainter.RenderHint.TextAntialiasing, True)

    # As fontes e suas métricas são caras de montar e se repetem muito (uma
    # comanda inteira costuma usar duas ou três combinações), então cada uma é
    # montada na primeira vez que aparece e reaproveitada daí em diante.
    fontes = {}

    topo = 0
    for glifos in fisicas:
        altura = _altura_da_linha(glifos)
        base = topo + altura - max(1, altura // 8)

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

    pintor.end()
    return imagem


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

    if _familias_locais is None:
        if QThread.currentThread() != aplicacao.thread():
            return []
        _familias_locais = list(QFontDatabase.families())

    return _familias_locais


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
    ESC/POS, desenhada na fonte `familia`.

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
        fisicas = _quebrar_em_linhas_fisicas(_linhas_com_estilo(conteudo), largura_dots)
        altura = sum(_altura_da_linha(glifos) for glifos in fisicas)
        if altura <= 0:
            return None

        imagem = _desenhar(fisicas, familia, largura_dots, altura)
        empacotado, bytes_por_linha = _empacotar(imagem)
        return _comandos_raster(empacotado, bytes_por_linha, altura)
    except Exception as erro:
        # Melhor esforço, como em Config/fontes.py: qualquer falha aqui vira
        # aviso no log e a comanda sai em texto. Isto roda dentro da thread de
        # impressão, onde uma exceção que escapa mata o job em silêncio.
        print(f"[comandaImagemService] Falha ao desenhar a comanda em '{familia}': {erro}")
        return None
