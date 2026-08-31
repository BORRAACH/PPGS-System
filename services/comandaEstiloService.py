"""Configurações de estilo ESC/POS (negrito, sublinhado, fundo preto/modo
reverso, tamanho da fonte em pixels) aplicadas a campos específicos do texto
da comanda, espaçamento entre seções/antes do corte, e ordem em que os
campos aparecem na comanda impressa (ordem_secoes/CAMPOS_ORDENAVEIS) — tudo
editável pela tela Configurações
(qml/pages/configuracoes/impressora/EstiloImpressora.qml) e usado por
balcaoController.py/entregaController.py/salaoController.py (montagem do
texto, via comandaTextoService.montar_linhas_por_ordem), por
fechamentoController.py (recibo de diária e cupom de fechamento de caixa,
pelo mesmo montar_linhas_por_ordem) e printerService.py (espaçamento antes
do corte automático).

São TRÊS papéis impressos, não um: a comanda de venda, o recibo de
pagamento de diária e o cupom de fechamento de caixa (ver
DOCUMENTO_POR_TIPO). Todos moram na mesma configuração e obedecem às mesmas
regras de estilo/ordem/divisória — o que muda de um pro outro é só qual
subconjunto de chaves tem conteúdo na hora de imprimir.

Persistido em Config/estilo_impressao.json — fora do git (é preferência de
cada máquina/impressora, não código-fonte), igual a Config/.versao (ver
Config/atualizador.py).

Sincronizado entre as máquinas da malha pelo mesmo mecanismo de
services/cardapioService.py (gossip via RedeService.publicarEvento +
anti-entropy via RedeService.registrarDominioSincronizado, ver
ComandaEstiloController.__init__/_ao_receber_estilo_remoto abaixo) — o dono
edita numa máquina e o formato de impressão vale em todas, sem precisar
copiar o JSON à mão.

services.rede não é importado aqui no topo do arquivo, ao contrário de
cardapioService.py: este módulo é importado por printerService.py, que por
sua vez é importado por services/rede/redeService.py — um import de
"services.rede" no topo daria ciclo (redeService -> printerService ->
comandaEstiloService -> services.rede, ainda no meio de importar
redeService). Por isso relogio/rede são importados só dentro de cada
função/método que precisa deles, quando o pacote já está totalmente
carregado."""

import hashlib
import json
import math
import os

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido

# Comandos ESC/POS. A Bematech MP-4200 TH (e impressoras térmicas em geral)
# entendem esses comandos em modo de emulação ESC/POS/Epson — mesma base já
# usada para negrito e corte em balcaoController.py/printerService.py.
_ESC = "\x1b"
_GS = "\x1d"

NEGRITO_LIGA = _ESC + "E" + "\x01"
NEGRITO_DESLIGA = _ESC + "E" + "\x00"
SUBLINHADO_LIGA = _ESC + "-" + "\x01"
SUBLINHADO_DESLIGA = _ESC + "-" + "\x00"
# "GS B" liga/desliga o modo reverso (texto claro em fundo preto).
FUNDO_PRETO_LIGA = _GS + "B" + "\x01"
FUNDO_PRETO_DESLIGA = _GS + "B" + "\x00"

# ESC/POS não tem "tamanho em pixels" de verdade — "GS !" só aceita um
# multiplicador inteiro de 1x a 8x sobre o tamanho normal do caractere.
# TAMANHO_FONTE_BASE_PX é a altura aproximada (em pixels/dots) da Fonte A no
# tamanho normal (1x) numa impressora térmica ESC/POS típica — usado só pra
# converter o valor em pixels que a tela pede pro multiplicador mais
# próximo. Não é um valor exato de datasheet, é uma referência razoável.
TAMANHO_FONTE_BASE_PX = 24


def _multiplicador_fonte(tamanho_px):
    """Converte um tamanho em pixels no multiplicador ESC/POS mais próximo
    (1 a 8). 24px (TAMANHO_FONTE_BASE_PX) ou menos vira 1x (tamanho normal,
    sem comando nenhum — ver formatar_campo).

    Usa arredondamento para cima (não para o mais próximo): com "round",
    qualquer valor até 1.5x a base (ex: 30px sobre uma base de 24px, uma
    razão de 1.25x) arredondava de volta para 1x — o campo ficava do mesmo
    tamanho de sempre e a mudança parecia não ter feito nada. Como o
    ESC/POS só tem esses 8 multiplicadores inteiros, qualquer valor acima
    da base já deve virar ao menos 2x para a alteração ser perceptível."""
    if not tamanho_px or tamanho_px <= TAMANHO_FONTE_BASE_PX:
        return 1
    multiplicador = math.ceil(tamanho_px / TAMANHO_FONTE_BASE_PX)
    return max(1, min(8, multiplicador))


def _comando_tamanho_fonte(multiplicador):
    """"GS !" espera um byte: bits 0-2 = altura-1, bits 4-6 = largura-1 —
    aqui sempre usamos o mesmo multiplicador pros dois, então o texto
    aumenta proporcionalmente, não só fica mais largo ou mais alto."""
    n = ((multiplicador - 1) << 4) | (multiplicador - 1)
    return _GS + "!" + chr(n)


FONTE_NORMAL_DESLIGA = _GS + "!" + "\x00"

# Faixa aceita para o tamanho de fonte em pixels. O teto cobre os 8x do
# ESC/POS (8 x 24 = 192px), pra que nenhuma configuração já existente encolha
# ao passar por aqui; o piso é o menor tamanho ainda legível num cupom térmico.
TAMANHO_FONTE_MIN_PX = 8
TAMANHO_FONTE_MAX_PX = 200

# Marcador que carrega o tamanho EXATO em pixels de um campo, para quando a
# comanda é desenhada como imagem (ver services/comandaImagemService.py).
#
# POR QUE ELE PRECISA EXISTIR: o "GS !" do ESC/POS só sabe dizer "2x", "3x" —
# multiplicadores inteiros do tamanho normal. Quando quem desenha é a
# impressora, é só isso que existe e não há o que fazer. Quando quem desenha
# somos nós, num QImage, qualquer tamanho é possível — mas o desenho acontece
# na outra ponta, a partir dos bytes da comanda, e nesses bytes o tamanho já
# tinha virado multiplicador. O valor exato precisa de carona própria.
#
# O parâmetro vai como TRÊS DÍGITOS ASCII ("048"), e não como um byte de valor:
# o texto é codificado em cp850 antes de ir pro papel (ver
# comandaTextoService.CODEPAGE_IMPRESSORA), e um byte acima de 127 sairia
# traduzido pra outro no caminho — o tamanho chegaria mudado do outro lado.
# Dígitos são ASCII, atravessam qualquer codepage intactos, e ainda aparecem
# legíveis para quem for depurar um cupom com um visualizador de bytes.
#
# ESTE MARCADOR NUNCA CHEGA À IMPRESSORA: quem imprime em texto o remove antes
# de enviar (ver PrinterService._preparar_conteudo), e quem lê a comanda salva
# o remove junto com os outros códigos de estilo (ver
# comandaParserService._PADRAO_ESTILO). O "GS !" continua sendo emitido do lado
# dele, então uma comanda gravada com fonte escolhida continua sendo um cupom
# de texto válido, com o mesmo tamanho aproximado de antes, se acabar impressa
# pelo caminho de texto.
MARCA_TAMANHO_PX = _GS + "~"


def _comando_tamanho_px(tamanho_px):
    return f"{MARCA_TAMANHO_PX}{tamanho_px:03d}"


TAMANHO_PX_DESLIGA = _comando_tamanho_px(TAMANHO_FONTE_BASE_PX)


def limitar_tamanho_fonte(tamanho_px):
    """O tamanho em pixels dentro da faixa aceita, ou a base quando o valor não
    é um número. Mesma regra para o JSON em disco, o payload da malha e o que a
    tela manda — o motivo de estar aqui num lugar só é o mesmo de
    _mesclar_ajustes."""
    if not isinstance(tamanho_px, (int, float)):
        return TAMANHO_FONTE_BASE_PX
    return max(TAMANHO_FONTE_MIN_PX, min(TAMANHO_FONTE_MAX_PX, int(tamanho_px)))

# Campos da comanda que podem ter estilo configurado. Alguns só são usados
# por um dos dois tipos de pedido (ex: "taxa_entrega", "endereco" só saem em
# pedidos de Entrega) — ficam na mesma lista/tela mesmo assim; não fazem
# diferença nenhuma pro outro tipo, que nunca chama formatar_campo com esse
# nome.
#
# Os campos com prefixo "extra_"/"fech_" pertencem aos outros dois papéis que
# o app imprime além da comanda de venda — o recibo de pagamento de diária e
# o cupom de fechamento de caixa (ver
# controllers/fechamentoController._montar_recibo_extra/
# _montar_recibo_fechamento). Ficam na MESMA lista, com as mesmas regras de
# estilo/ordem/divisória, porque a tela de Configurações é uma só: o que
# separa um papel do outro é o DOCUMENTO (ver DOCUMENTO_POR_CAMPO), não uma
# segunda configuração paralela.
CAMPOS = [
    "id_pedido",
    "cliente",
    "mesa",
    "telefone",
    "endereco",
    "bairro",
    "data",
    "usuario",
    "pedido",
    "pedido_tamanho",
    "observacao_item",
    "borda_item",
    "adicional_item",
    "observacao_entrega",
    "forma_pagamento",
    "troco_para",
    "status",
    "taxa_entrega",
    "valor_total",
    "troco_a_dar",
    # --- Recibo de pagamento de diária (Fechamento > Extras) ---
    "extra_titulo",
    "extra_subtitulo",
    "extra_hora_data",
    "extra_recebi",
    "extra_valor",
    "extra_discriminacao_item",
    "extra_discriminacao_total",
    "extra_quitacao",
    "extra_assina_nome",
    "extra_assinatura",
    # --- Cupom de fechamento de caixa ---
    "fech_titulo",
    "fech_data",
    "fech_bruto",
    "fech_liquido",
    "fech_origem_titulo",
    "fech_origem_nome",
    "fech_origem_forma",
    "fech_diarias_titulo",
    "fech_diarias_item",
    "fech_edicoes_titulo",
    "fech_edicoes_item",
    "fech_edicoes_autor",
    "fech_lucro",
    "fech_lucro_real",
]
ATRIBUTOS_BOOLEANOS = ["negrito", "sublinhado", "fundo_preto"]

# Família de fonte usada pra DESENHAR a comanda, quando o dono escolhe uma.
#
# String vazia = nenhuma escolhida, que é o padrão e significa "deixa a
# impressora desenhar": sai o texto ESC/POS de sempre, com as fontes gravadas
# dentro dela. Com uma família escolhida, a comanda passa a ser rasterizada
# antes de ser enviada (ver services/comandaImagemService.py e
# PrinterService.imprimir) — é o único jeito de uma fonte do computador chegar
# ao papel, já que no modo texto quem desenha as letras é a impressora.
#
# É ajuste GLOBAL, não por campo: a fonte vale pro cupom inteiro. Misturar
# famílias numa comanda de 40 colunas não teria uso, e o desenho é feito de uma
# vez só, com a imagem inteira montada junto.
FONTE_DA_IMPRESSORA = ""

# --- MODELO DE DESENHO DA COMANDA ---
#
# Qual DISPOSIÇÃO é usada quando a comanda é desenhada como imagem. Só tem
# efeito no caminho de imagem (ver FONTE_DA_IMPRESSORA acima): sem fonte
# escolhida quem desenha é a impressora, que só sabe empilhar caracteres numa
# grade — não há disposição a escolher.
#
# POR QUE ISTO É UMA OPÇÃO, e não uma troca de código: mudar como a comanda sai
# no papel é uma decisão que se testa com o papel na mão, numa pizzaria em
# funcionamento, e que precisa poder ser desfeita na hora se a cozinha não
# gostar. O modelo clássico é o padrão e reproduz exatamente o cupom de sempre;
# qualquer modelo novo é um caminho paralelo, escolhido aqui, que nunca toca no
# arquivo gravado em pedidos/*.txt (esse continua sendo texto cp850, ver
# PrinterService._preparar_conteudo).
MODELO_CLASSICO = "classico"
MODELO_RASCUNHO = "rascunho"

# Catálogo oferecido pelo seletor da tela de Configurações. A descrição vai
# junto porque a diferença entre os modelos não cabe num rótulo de combo — e
# sem ela o dono teria que imprimir os dois pra descobrir qual é qual.
MODELOS_IMPRESSAO = (
    {
        "chave": MODELO_CLASSICO,
        "rotulo": "Clássico (mesma grade do cupom de texto)",
        "descricao": (
            "Cada caractere no centro de uma célula de largura fixa, como a "
            "impressora faria. O papel sai idêntico ao cupom de sempre — só as "
            "letras mudam de fonte."
        ),
    },
    {
        "chave": MODELO_RASCUNHO,
        "rotulo": "Rascunho (colunas da tela de pedidos)",
        "descricao": (
            "A tabela de itens sai em três colunas — Pedido, Observação e "
            "Valor — na mesma proporção da lista de itens do Balcão, da "
            "Entrega e do Salão. O resto da comanda continua igual ao modelo "
            "clássico."
        ),
    },
)

MODELO_PADRAO = MODELO_CLASSICO

RODULOS_CAMPOS = {
    "id_pedido": "Código do pedido",
    "cliente": "Nome do cliente",
    "mesa": "Número da mesa",
    "telefone": "Telefone",
    "endereco": "Endereço (com número)",
    "bairro": "Bairro",
    "data": "Data/hora do pedido",
    # Quem autorizou o lançamento no balcão (ver services/rede/usuarios.py e
    # components/PopupAutorizacao.qml). Sai em branco — e a linha some — nas
    # comandas gravadas antes disto existir, e enquanto ninguém estiver
    # cadastrado.
    "usuario": "Usuário que lançou",
    "pedido": "Nome do pedido",
    # O "(GRANDE)"/"(BROTO)"/"(MINI)" que vem colado no nome do item. Campo
    # próprio, mas SEM posição própria (fora de CAMPOS_ORDENAVEIS): ele sai no
    # meio da linha do item, não numa linha que dê para mover — ver
    # comandaTextoService.formatar_coluna_pedido.
    "pedido_tamanho": "Tamanho da pizza (Grande/Broto/Mini)",
    # Distintos de propósito: "observacao_item" é a observação de cada
    # sabor/item (ex: "sem cebola", digitada na tela de seleção de pizza);
    # "observacao_entrega" é a observação geral do pedido, que só existe na
    # tela de Entrega, perto dos dados de endereço.
    "observacao_item": "Observação do item (sabor)",
    "borda_item": "Borda da pizza",
    "adicional_item": "Adicional do sabor",
    "observacao_entrega": "Observação geral (perto do endereço)",
    "forma_pagamento": "Forma de pagamento",
    "troco_para": "Troco para",
    "status": "Status (pago/não pago)",
    "taxa_entrega": "Taxa de entrega",
    "valor_total": "Valor do pedido",
    "troco_a_dar": "Troco a dar",
    "extra_titulo": "Título do recibo",
    "extra_subtitulo": "Subtítulo do recibo",
    "extra_hora_data": "Hora e data do pagamento",
    "extra_recebi": "Linha \"Recebi de\"",
    "extra_valor": "Valor da diária",
    "extra_discriminacao_item": "Item da discriminação (linha)",
    "extra_discriminacao_total": "Total a receber",
    "extra_quitacao": "Texto de quitação",
    # CHAVES NOVAS, e não as duas antigas reaproveitadas ("extra_funcionario"
    # era o "Funcionário: ..." do cabeçalho e "extra_data" o "Data: ...").
    # As duas mudaram de POSIÇÃO no papel, não só de texto: o nome passou para
    # cima da linha de assinatura e a hora/data para o cabeçalho. Reaproveitar
    # a chave faria _mesclar_ordem preservar a posição salva — que era a certa
    # do campo antigo e a errada do novo, e o recibo sairia com o nome do
    # funcionário no meio do cabeçalho. Como chaves novas, elas se encaixam na
    # vizinhança padrão, e _mesclar_ordem descarta sozinho as antigas de quem
    # já tinha uma ordem gravada. O custo é perder o estilo que estivesse
    # configurado nas duas, que volta ao padrão.
    "extra_assina_nome": "Nome de quem assina",
    "extra_assinatura": "Linha de assinatura",
    "fech_titulo": "Título do fechamento",
    "fech_data": "Data do caixa",
    "fech_bruto": "Total bruto vendido",
    "fech_liquido": "Total líquido",
    "fech_origem_titulo": "Título \"Por origem\"",
    "fech_origem_nome": "Origem e seu total",
    "fech_origem_forma": "Forma de pagamento da origem",
    "fech_diarias_titulo": "Título \"Pagamentos de diária\"",
    "fech_diarias_item": "Pagamento de diária (linha)",
    # Comandas já fechadas que alguém corrigiu ou apagou depois (ver
    # services/rede/edicoesCaixa.py). Duas sub-linhas por alteração, como as
    # do bloco "Por origem": o que mudou, e quem mudou/quanto.
    "fech_edicoes_titulo": "Título \"Alterações após a baixa\"",
    "fech_edicoes_item": "Comanda alterada (linha)",
    "fech_edicoes_autor": "Autor e valores da alteração",
    # "fech_lucro" é o nome histórico da chave: o campo já foi o Lucro e
    # hoje imprime SOBROU/FALTOU. Renomeá-la sumiria com a seção no cupom de
    # quem já tem um estilo_impressao.json salvo, então o Lucro de verdade
    # (contagem menos diárias) entrou como uma chave nova ao lado.
    "fech_lucro": "Sobra/falta do caixa",
    "fech_lucro_real": "Lucro (contagem - diárias - despesas)",
}

RODULOS_ATRIBUTOS = {
    "negrito": "Negrito",
    "sublinhado": "Sublinhado",
    "fundo_preto": "Fundo preto",
}

# Campos que têm posição própria na comanda impressa (fora da tabela de
# itens) e por isso podem ser reordenados pela tela Configurações > Ordem
# dos campos. Reaproveita a maioria das chaves de CAMPOS (mesmo campo,
# estilo e posição são coisas independentes) mais dois "campos" que só
# existem como âncora de posição — "itens" (a tabela inteira, ver
# comandaTextoService.montar_linhas_por_ordem) e "divisao_conta" (bloco
# "DIVISÃO DA CONTA" de uma comanda de Mesa) — nenhum dos dois tem estilo
# próprio (não entram em CAMPOS/listarCampos), só posição.
#
# "pedido", "observacao_item", "borda_item" e "adicional_item" ficam de
# fora: são estilo de linhas DENTRO da tabela de itens, sem posição própria
# fora dela.
CAMPOS_ORDENAVEIS = [
    "usuario",
    "id_pedido",
    "cliente",
    "mesa",
    "telefone",
    "endereco",
    "bairro",
    "data",
    "itens",
    "observacao_entrega",
    "forma_pagamento",
    "troco_para",
    "status",
    "taxa_entrega",
    "valor_total",
    "troco_a_dar",
    "divisao_conta",
    # --- Recibo de pagamento de diária. "extra_discriminacao" é âncora de
    # posição (mesmo papel de "itens" e de "fech_por_origem"): o bloco
    # "SENDO..." inteiro se move junto, e quem tem estilo próprio são as
    # sub-linhas dele.
    "extra_titulo",
    "extra_subtitulo",
    "extra_hora_data",
    "extra_recebi",
    "extra_valor",
    "extra_discriminacao",
    "extra_quitacao",
    "extra_assina_nome",
    "extra_assinatura",
    # --- Cupom de fechamento de caixa. "fech_por_origem" e "fech_diarias"
    # são âncoras de posição (mesmo papel de "itens"): o bloco inteiro se
    # move junto, e quem tem estilo próprio são as sub-linhas dele.
    "fech_titulo",
    "fech_data",
    "fech_bruto",
    "fech_liquido",
    "fech_por_origem",
    "fech_diarias",
    "fech_edicoes",
    "fech_lucro",
    "fech_lucro_real",
]

# Chaves ordenáveis que NÃO têm estilo próprio — só posição. A tela de
# Configurações lê isto (ver listarCamposOrdenaveis/"estilizavel") para
# desabilitar o botão "Estilo…" nelas, em vez de repetir a lista no QML.
CAMPOS_ANCORA = [chave for chave in CAMPOS_ORDENAVEIS if chave not in CAMPOS]

RODULOS_CAMPOS_ORDENAVEIS = {
    **RODULOS_CAMPOS,
    "itens": "Tabela de itens do pedido",
    "divisao_conta": "Divisão da conta (Mesa)",
    "extra_discriminacao": "Bloco \"Sendo\" (discriminação)",
    "fech_por_origem": "Bloco \"Por origem\"",
    "fech_diarias": "Bloco \"Pagamentos de diária\"",
    "fech_edicoes": "Bloco \"Alterações após a baixa\"",
}

# Categoria de cada campo ordenável — usada só por
# comandaTextoService.montar_linhas_por_ordem para decidir quando inserir
# separador (linha de traços + espaçamento) entre dois campos consecutivos:
# campos da mesma categoria ficam colados, sem separador (ex: Cliente/Data
# hoje), igual entre categorias diferentes ganha separador. "itens" não
# aparece aqui porque é sempre tratado à parte (marcador próprio, ver
# comandaTextoService.MARCADOR_ITENS).
CATEGORIA_CAMPO = {
    "usuario": "cabecalho",
    "id_pedido": "cabecalho",
    "cliente": "cabecalho",
    "mesa": "cabecalho",
    "telefone": "cabecalho",
    "endereco": "cabecalho",
    "bairro": "cabecalho",
    "data": "cabecalho",
    "observacao_entrega": "observacao",
    "forma_pagamento": "pagamento",
    "troco_para": "pagamento",
    "status": "status",
    "taxa_entrega": "totais",
    "valor_total": "totais",
    "troco_a_dar": "totais",
    "divisao_conta": "divisao",
    # As categorias dos outros dois papéis são próprias deles (prefixadas):
    # como cada documento é impresso sozinho, nunca há um campo de pedido
    # como "anterior" de um campo de fechamento — mas prefixar deixa
    # explícito que a divisória entre "totais" e "fech_totais" nunca é
    # avaliada, em vez de parecer coincidência.
    # Uma divisória só no recibo, entre o cabeçalho (título, subtítulo,
    # hora/data) e todo o resto — é o desenho pedido pelo dono. Do "RECEBI DE"
    # até a linha de assinatura corre tudo colado, na mesma categoria: o nome
    # de quem assina tem de encostar na linha em que ele assina, e uma
    # divisória no meio disso separaria a assinatura da pessoa.
    "extra_titulo": "extra_cabecalho",
    "extra_subtitulo": "extra_cabecalho",
    "extra_hora_data": "extra_cabecalho",
    "extra_recebi": "extra_corpo",
    "extra_valor": "extra_corpo",
    "extra_discriminacao": "extra_corpo",
    "extra_quitacao": "extra_corpo",
    "extra_assina_nome": "extra_corpo",
    "extra_assinatura": "extra_corpo",
    "fech_titulo": "fech_cabecalho",
    "fech_data": "fech_cabecalho",
    "fech_bruto": "fech_totais",
    "fech_liquido": "fech_totais",
    "fech_por_origem": "fech_origem",
    "fech_diarias": "fech_diarias",
    "fech_edicoes": "fech_edicoes",
    "fech_lucro": "fech_lucro",
    "fech_lucro_real": "fech_lucro_real",
}

# Quais tipos de comanda imprimem cada campo. Usado SÓ pela prévia da tela de
# Configurações (qml/.../EstiloImpressora.qml), pra apagar visualmente os
# campos que o tipo escolhido no seletor não usa — quem decide de verdade
# continua sendo o dict `renderizadores` de cada controller
# (balcaoController/entregaController/salaoController._salvarComanda /
# _montarCupomFinal). Um valor errado aqui só acende/apaga um campo na tela;
# não muda nada do que sai impresso. Se um controller passar a imprimir um
# campo novo, atualize aqui também — senão a prévia mente.
TIPOS_COMANDA = ["Balcão", "Entrega", "Mesa", "Extras", "Fechamento"]

# Os cinco tipos acima não são cinco papéis diferentes: Balcão/Entrega/Mesa
# são três variações do MESMO papel (a comanda de venda, que muda só quais
# campos têm conteúdo), enquanto Extras e Fechamento são papéis próprios,
# impressos sozinhos e com campos que não aparecem em nenhum outro.
#
# É essa diferença que o DOCUMENTO captura: a tela de Configurações mostra
# no papel só os campos do documento do tipo escolhido (trocar de Entrega
# pra Fechamento troca a comanda inteira na prévia), e dentro de um mesmo
# documento continua apagando os campos que aquele tipo não imprime (a
# regra antiga, de TIPOS_POR_CAMPO). A configuração em disco continua sendo
# UMA só: "campos"/"ordem_secoes"/"separadores_campo" guardam os três
# documentos juntos, e cada um só enxerga as próprias chaves na hora de
# imprimir (ver comandaTextoService.montar_linhas_por_ordem, que pula
# qualquer chave sem conteúdo).
DOCUMENTO_PEDIDO = "pedido"
DOCUMENTO_EXTRA = "extra"
DOCUMENTO_FECHAMENTO = "fechamento"

DOCUMENTO_POR_TIPO = {
    "Balcão": DOCUMENTO_PEDIDO,
    "Entrega": DOCUMENTO_PEDIDO,
    "Mesa": DOCUMENTO_PEDIDO,
    "Extras": DOCUMENTO_EXTRA,
    "Fechamento": DOCUMENTO_FECHAMENTO,
}

TIPOS_POR_CAMPO = {
    "id_pedido": ["Balcão", "Entrega", "Mesa"],
    "cliente": ["Balcão", "Entrega", "Mesa"],
    "mesa": ["Mesa"],
    "telefone": ["Entrega"],
    "endereco": ["Entrega"],
    "bairro": ["Entrega"],
    "data": ["Balcão", "Entrega", "Mesa"],
    "usuario": ["Balcão", "Entrega", "Mesa"],
    "itens": ["Balcão", "Entrega", "Mesa"],
    "observacao_entrega": ["Entrega"],
    "forma_pagamento": ["Balcão", "Entrega"],
    "troco_para": ["Balcão", "Entrega"],
    "status": ["Balcão", "Entrega"],
    "taxa_entrega": ["Entrega"],
    "valor_total": ["Balcão", "Entrega", "Mesa"],
    "troco_a_dar": ["Balcão", "Entrega"],
    "divisao_conta": ["Mesa"],
    "extra_titulo": ["Extras"],
    "extra_subtitulo": ["Extras"],
    "extra_hora_data": ["Extras"],
    "extra_recebi": ["Extras"],
    "extra_valor": ["Extras"],
    "extra_discriminacao": ["Extras"],
    "extra_quitacao": ["Extras"],
    "extra_assina_nome": ["Extras"],
    "extra_assinatura": ["Extras"],
    "fech_titulo": ["Fechamento"],
    "fech_data": ["Fechamento"],
    "fech_bruto": ["Fechamento"],
    "fech_liquido": ["Fechamento"],
    "fech_por_origem": ["Fechamento"],
    "fech_diarias": ["Fechamento"],
    "fech_edicoes": ["Fechamento"],
    "fech_lucro": ["Fechamento"],
    "fech_lucro_real": ["Fechamento"],
}

# Documento (papel impresso) a que cada chave ordenável pertence — deduzido
# de TIPOS_POR_CAMPO em vez de escrito à mão, pra não haver uma terceira
# lista pra manter em dia: o documento de um campo é o do primeiro tipo que
# o imprime.
DOCUMENTO_POR_CAMPO = {
    campo: DOCUMENTO_POR_TIPO.get((tipos or [""])[0], DOCUMENTO_PEDIDO)
    for campo, tipos in TIPOS_POR_CAMPO.items()
}

# Ordem padrão dos campos na comanda impressa — reproduz o layout visual de
# antes desta tela existir (ver docstring do módulo e
# controllers/balcaoController.py/entregaController.py/salaoController.py).
_ORDEM_PADRAO = [
    # Quem lançou vem PRIMEIRO, colado no código do pedido: é a primeira coisa
    # que se procura no papel quando alguém precisa saber de quem foi a
    # comanda, e no rodapé ela se perdia no meio dos totais.
    "usuario",
    "id_pedido",
    "cliente",
    "mesa",
    "telefone",
    "endereco",
    "bairro",
    "data",
    "itens",
    "observacao_entrega",
    "forma_pagamento",
    "troco_para",
    "status",
    "taxa_entrega",
    "valor_total",
    "troco_a_dar",
    "divisao_conta",
    # Cada documento é um bloco contíguo aqui só por legibilidade — o que
    # importa de verdade é a ordem RELATIVA entre as chaves de um mesmo
    # documento, já que na impressão as dos outros são puladas por não terem
    # conteúdo (ver comandaTextoService.montar_linhas_por_ordem).
    "extra_titulo",
    "extra_subtitulo",
    "extra_hora_data",
    "extra_recebi",
    "extra_valor",
    "extra_discriminacao",
    "extra_quitacao",
    "extra_assina_nome",
    "extra_assinatura",
    "fech_titulo",
    "fech_data",
    "fech_bruto",
    "fech_liquido",
    "fech_por_origem",
    "fech_diarias",
    "fech_edicoes",
    "fech_lucro",
    "fech_lucro_real",
]


# Teto de linhas de traço numa mesma divisória. Existe pra um valor
# absurdo (JSON editado à mão, ou vindo de uma versão futura com outra
# escala) não virar uma comanda de metros de papel — 5 já é mais grosso do
# que qualquer separador que faça sentido num cupom de 40 colunas.
MAX_LINHAS_SEPARADOR = 5


def _atributos_campo_padrao():
    atributos = {atributo: False for atributo in ATRIBUTOS_BOOLEANOS}
    atributos["tamanho_fonte"] = TAMANHO_FONTE_BASE_PX
    return atributos


def _padrao():
    config = {
        "campos": {campo: _atributos_campo_padrao() for campo in CAMPOS},
        "ordem_secoes": list(_ORDEM_PADRAO),
        "espacamento_secoes": 1,
        "espacamento_corte": 4,
        # Quantas linhas de traço ("-" * 40) saem em cada divisória que a
        # regra automática de categoria pede. 1 reproduz o comportamento de
        # antes desta opção existir.
        "linhas_separador": 1,
        # Exceções à regra automática, por campo: {chave: nº de linhas de
        # traço ANTES daquele campo}. Um campo listado aqui ignora a regra de
        # categoria — é assim que dá pra pôr divisória onde ela não apareceria
        # (campos da mesma categoria) e tirar onde apareceria (0). Vazio =
        # tudo automático.
        "separadores_campo": {},
        # Família de fonte pra desenhar a comanda (ver FONTE_DA_IMPRESSORA). O
        # padrão vazio reproduz exatamente o cupom de antes desta opção existir.
        "fonte_impressao": FONTE_DA_IMPRESSORA,
        # Disposição usada quando a comanda é desenhada como imagem (ver
        # MODELOS_IMPRESSAO). O padrão clássico reproduz o cupom de antes desta
        # opção existir.
        "modelo_impressao": MODELO_PADRAO,
        # Marca de qual mudança é mais recente entre as máquinas da malha
        # (ver _aplicar_estilo_remoto/relogio.mais_novo) — "" numa
        # instalação nova, ou num arquivo salvo antes deste mecanismo
        # existir.
        "idEvento": "",
    }
    # Preserva o comportamento original do app (nome do item/observação já
    # saíam em negrito antes de existir essa tela de configuração).
    config["campos"]["pedido"]["negrito"] = True
    # Mesmo negrito de "pedido": até este campo existir, o tamanho fazia parte
    # da string do nome do item e saía com o estilo dele. O padrão reproduz o
    # cupom de antes; quem quiser o tamanho diferente do sabor agora pode.
    config["campos"]["pedido_tamanho"]["negrito"] = True
    config["campos"]["observacao_item"]["negrito"] = True
    # Pedido explícito do dono: o código do pedido sempre sai em negrito no
    # cabeçalho por padrão (continua editável em Configurações, como todo
    # outro campo desta lista).
    config["campos"]["id_pedido"]["negrito"] = True
    # Mesma ideia nos outros dois papéis: estes são os trechos que já saíam
    # em negrito fixo antes de virarem campos configuráveis (ver
    # fechamentoController._montar_recibo_extra/_montar_recibo_fechamento),
    # então o padrão reproduz o cupom de antes.
    for campo in ("extra_titulo", "extra_subtitulo", "extra_discriminacao_total",
                  "fech_titulo", "fech_origem_titulo", "fech_origem_nome",
                  "fech_diarias_titulo", "fech_edicoes_titulo", "fech_lucro",
                  "fech_lucro_real"):
        config["campos"][campo]["negrito"] = True
    return config


def _raiz_projeto():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _caminho_arquivo():
    return os.path.join(_raiz_projeto(), "Config", "estilo_impressao.json")


def _mesclar_campos(destino, campos_lidos):
    """Copia por cima de `destino` (já nos padrões) os valores válidos de
    `campos_lidos` — tolera um arquivo salvo por uma versão mais antiga do
    app (ex: sem um campo/atributo novo adicionado depois, ou com o
    "fonte_grande" booleano de antes de virar "tamanho_fonte")."""
    for campo, atributos in (campos_lidos or {}).items():
        if campo not in destino or not isinstance(atributos, dict):
            continue
        for atributo in ATRIBUTOS_BOOLEANOS:
            if atributo in atributos:
                destino[campo][atributo] = bool(atributos[atributo])
        if isinstance(atributos.get("tamanho_fonte"), (int, float)):
            destino[campo]["tamanho_fonte"] = limitar_tamanho_fonte(atributos["tamanho_fonte"])


def _posicao_padrao(ordem, indice_padrao):
    """Onde encaixar, dentro de `ordem`, a chave que ocupa `indice_padrao`
    em _ORDEM_PADRAO: logo depois do vizinho ANTERIOR dela que já esteja em
    `ordem`; não havendo nenhum, logo antes do primeiro vizinho POSTERIOR
    que esteja; e só no fim quando nenhum dos dois lados aparece."""
    for chave in reversed(_ORDEM_PADRAO[:indice_padrao]):
        if chave in ordem:
            return ordem.index(chave) + 1

    for chave in _ORDEM_PADRAO[indice_padrao + 1:]:
        if chave in ordem:
            return ordem.index(chave)

    return len(ordem)


def _herdar_estilo_do_nome_do_item(destino, campos_lidos):
    """Faz "pedido_tamanho" nascer com o estilo que a pessoa já tinha escolhido
    para "pedido", num estilo_impressao.json salvo antes deste campo existir.

    Sem isto, quem tivesse tirado o negrito do nome do item (ou aumentado a
    fonte dele) veria o "(GRANDE)" descolar sozinho do resto da linha na
    primeira abertura depois da atualização — uma mudança no papel que ninguém
    pediu, e que apareceria como defeito de impressão, não como campo novo.

    Só herda quando o arquivo tem "pedido" e NÃO tem "pedido_tamanho": a partir
    da primeira gravação os dois são independentes, e uma segunda herança
    desfaria a escolha de quem separou os dois de propósito."""
    lidos = campos_lidos or {}
    if "pedido_tamanho" in lidos or "pedido" not in lidos:
        return

    destino["pedido_tamanho"] = dict(destino["pedido"])


def _mesclar_ordem(ordem_lida):
    """Valida `ordem_lida` (lista de chaves de CAMPOS_ORDENAVEIS) e devolve
    uma ordem completa e utilizável: mantém a ordem lida, descartando
    chaves desconhecidas (versão mais nova do app removeu um campo), e
    encaixa qualquer chave de CAMPOS_ORDENAVEIS que não apareça nela (JSON
    salvo por uma versão do app anterior à introdução de um campo novo). Sem
    essa segunda parte, um campo novo simplesmente nunca seria impresso em
    instalações que já tinham um estilo_impressao.json salvo.

    O campo novo entra NA VIZINHANÇA que ele tem em _ORDEM_PADRAO, e não no
    fim da lista como antes: o fim da lista é o rodapé do papel, que quase
    nunca é onde o campo foi projetado para sair — e "quem já usava o app
    recebe o campo no lugar errado" é pior do que não recebê-lo, porque
    passa por bug de layout em vez de configuração. A ordem que a pessoa
    escolheu na tela é preservada inteira; o campo novo só se acomoda entre
    os vizinhos dela.

    Um campo que a pessoa moveu de lugar continua onde ela o pôs — a busca
    é pelo vizinho de _ORDEM_PADRAO que EXISTE na ordem lida, então o encaixe
    acompanha a escolha dela em vez de desfazê-la."""
    if not isinstance(ordem_lida, list):
        return list(_ORDEM_PADRAO)

    ordem = [chave for chave in ordem_lida if chave in CAMPOS_ORDENAVEIS]
    for indice, chave in enumerate(_ORDEM_PADRAO):
        if chave not in ordem:
            ordem.insert(_posicao_padrao(ordem, indice), chave)
    return ordem


def _limitar_linhas_separador(valor):
    return max(0, min(MAX_LINHAS_SEPARADOR, int(valor)))


def _mesclar_separadores_campo(lidos):
    """Valida o mapa de exceções {campo: nº de linhas de traço antes dele}.

    Descarta chaves que não são campos ordenáveis (JSON de uma versão do app
    que ainda tinha um campo removido depois) e valores não numéricos. Aceita
    float porque um QVariantMap vindo do QML entrega os números assim."""
    if not isinstance(lidos, dict):
        return {}

    return {
        campo: _limitar_linhas_separador(valor)
        for campo, valor in lidos.items()
        if campo in CAMPOS_ORDENAVEIS and isinstance(valor, (int, float))
    }


def _mesclar_ajustes(destino, dados):
    """Copia por cima de `destino` (já nos padrões) os ajustes de espaçamento
    e de divisórias de `dados` — seja o JSON em disco, um payload vindo de
    outra máquina da malha ou o dict que a tela de Configurações manda ao
    sair. Os três precisam exatamente da mesma validação, daí estar aqui num
    lugar só: uma chave ausente ou de tipo errado apenas mantém o padrão, que
    é o que faz um arquivo salvo por uma versão mais antiga do app continuar
    carregando."""
    if isinstance(dados.get("espacamento_secoes"), int):
        destino["espacamento_secoes"] = max(0, dados["espacamento_secoes"])
    if isinstance(dados.get("espacamento_corte"), int):
        destino["espacamento_corte"] = max(0, dados["espacamento_corte"])
    if isinstance(dados.get("linhas_separador"), (int, float)):
        destino["linhas_separador"] = _limitar_linhas_separador(dados["linhas_separador"])
    destino["separadores_campo"] = _mesclar_separadores_campo(dados.get("separadores_campo"))
    # Só o tipo é conferido, de propósito: NÃO se valida contra as fontes
    # instaladas nesta máquina. O estilo é sincronizado pela malha, e uma
    # máquina que não tenha a fonte escolhida ainda precisa GUARDAR o nome dela
    # — apagá-la aqui faria essa máquina publicar de volta a configuração sem a
    # fonte e desfazer a escolha do dono em todas as outras. Quem não tem a
    # fonte simplesmente imprime em texto (ver comandaImagemService.para_raster).
    if isinstance(dados.get("fonte_impressao"), str):
        destino["fonte_impressao"] = dados["fonte_impressao"].strip()
    # Guardado como veio, sem conferir contra MODELOS_IMPRESSAO, pelo mesmo
    # motivo da fonte logo acima: a malha sincroniza esta configuração entre
    # máquinas que podem estar em versões diferentes do app, e apagar aqui um
    # modelo que só a versão mais nova conhece faria esta máquina republicar a
    # config sem ele — desfazendo a escolha do dono em todas as outras. Quem
    # não conhece o modelo simplesmente desenha no clássico (ver
    # comandaImagemService._desenho_do_modelo).
    if isinstance(dados.get("modelo_impressao"), str):
        destino["modelo_impressao"] = dados["modelo_impressao"].strip()


def _carregar():
    caminho = _caminho_arquivo()
    config = _padrao()
    if not os.path.isfile(caminho):
        return config

    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            dados = json.load(arquivo)
    except (OSError, json.JSONDecodeError) as erro:
        print(f"[comandaEstiloService] Falha ao ler {caminho}: {erro} — usando padrões.")
        return config

    _mesclar_campos(config["campos"], dados.get("campos"))
    _herdar_estilo_do_nome_do_item(config["campos"], dados.get("campos"))
    config["ordem_secoes"] = _mesclar_ordem(dados.get("ordem_secoes"))
    _mesclar_ajustes(config, dados)

    if isinstance(dados.get("idEvento"), str):
        config["idEvento"] = dados["idEvento"]

    return config


def _salvar():
    caminho = _caminho_arquivo()
    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
        with open(caminho, "w", encoding="utf-8") as arquivo:
            json.dump(_config, arquivo, indent=2, ensure_ascii=False)
    except OSError as erro:
        print(f"[comandaEstiloService] Falha ao gravar {caminho}: {erro}")


# Estado em memória, compartilhado por todos os módulos que importam este
# (balcaoController, entregaController, printerService) — carregado uma vez
# na primeira importação; ComandaEstiloController muta esse mesmo dict, então
# mudanças feitas pela tela de Configurações valem pro próximo pedido sem
# precisar reiniciar o app.
_config = _carregar()


def formatar_campo(texto, campo):
    """Envolve `texto` com os comandos ESC/POS ligados/desligados conforme a
    configuração atual de `campo`. Ordem fixa de aninhamento (fundo preto >
    tamanho de fonte > sublinhado > negrito), sempre desligando na ordem
    inversa — evita depender da ordem de inserção de um dict."""
    atributos = _config["campos"].get(campo, {})
    prefixo = ""
    sufixo = ""

    if atributos.get("fundo_preto"):
        prefixo += FUNDO_PRETO_LIGA
        sufixo = FUNDO_PRETO_DESLIGA + sufixo

    multiplicador = _multiplicador_fonte(atributos.get("tamanho_fonte"))
    if multiplicador > 1:
        prefixo += _comando_tamanho_fonte(multiplicador)
        sufixo = FONTE_NORMAL_DESLIGA + sufixo

    # O tamanho exato vai junto do multiplicador, não no lugar dele: o "GS !"
    # é o que vale se esta comanda acabar impressa como texto (fonte não
    # escolhida, ou a máquina que imprime sem ela), e o marcador é o que vale
    # quando ela for desenhada. Assim o mesmo arquivo serve aos dois caminhos.
    tamanho_px = limitar_tamanho_fonte(atributos.get("tamanho_fonte"))
    if fonte_impressao() and tamanho_px != TAMANHO_FONTE_BASE_PX:
        prefixo += _comando_tamanho_px(tamanho_px)
        sufixo = TAMANHO_PX_DESLIGA + sufixo

    if atributos.get("sublinhado"):
        prefixo += SUBLINHADO_LIGA
        sufixo = SUBLINHADO_DESLIGA + sufixo
    if atributos.get("negrito"):
        prefixo += NEGRITO_LIGA
        sufixo = NEGRITO_DESLIGA + sufixo

    return prefixo + texto + sufixo


def linhas_espacamento_secoes():
    """Lista de linhas vazias usada como espaçador entre seções da comanda
    (cliente/itens/pagamento/total) — quantidade configurável."""
    return [""] * _config["espacamento_secoes"]


def ordem_secoes():
    """Ordem atual dos campos na comanda impressa (lista de chaves de
    CAMPOS_ORDENAVEIS) — consultada por
    comandaTextoService.montar_linhas_por_ordem através dos controllers de
    venda (Balcão/Entrega/Mesa) ao montar linhas_arquivo."""
    return _config["ordem_secoes"]


def linhas_separador_antes(campo, categoria_anterior):
    """Quantas linhas de traço ("-" * 40) entram ANTES de `campo` numa comanda
    em que o campo anterior impresso era da categoria `categoria_anterior`
    (None se `campo` é o primeiro com conteúdo).

    Uma exceção gravada para esse campo (ver "separadores_campo") manda
    sozinha — inclusive um 0, que é como se tira a divisória de um lugar onde
    a regra automática a colocaria, e inclusive quando não há campo anterior.
    Sem exceção, vale a regra de sempre: divisória só na troca de categoria, e
    com a espessura de "linhas_separador".

    Não vale para as bordas da tabela de itens: lá o separador é o
    MARCADOR_ITENS ("=" * 40) e sai sempre uma vez só, porque
    consultaController.reconstruirComanda o usa para achar onde a tabela
    começa e termina ao reabrir a comanda gravada — duas linhas de marcador de
    cada lado fariam a tabela ser lida como vazia. Quem monta o texto trata
    esse caso antes de chegar aqui (ver
    comandaTextoService.montar_linhas_por_ordem)."""
    excecao = _config["separadores_campo"].get(campo)
    if excecao is not None:
        return excecao

    if categoria_anterior is None:
        return 0

    if categoria_campo(campo) != categoria_anterior:
        return _config["linhas_separador"]

    return 0


def categoria_campo(campo):
    """Categoria de `campo` (ver CATEGORIA_CAMPO) — "" para uma chave
    desconhecida, o que faz montar_linhas_por_ordem sempre inserir
    separador antes dela (mais seguro que presumir que é igual à
    categoria anterior)."""
    return CATEGORIA_CAMPO.get(campo, "")


def linhas_espacamento_corte():
    """Quantas linhas em branco entram antes do comando de corte automático
    (ver printerService.py) — margem pra o papel avançar de verdade além da
    lâmina antes de cortar."""
    return _config["espacamento_corte"]


def fonte_impressao():
    """Família de fonte escolhida pra desenhar a comanda, ou "" quando o cupom
    deve sair em texto, como sempre saiu (ver FONTE_DA_IMPRESSORA). Consultada
    por PrinterService.imprimir na hora de decidir se rasteriza."""
    return _config["fonte_impressao"]


def modelo_impressao():
    """Disposição escolhida pra desenhar a comanda como imagem (ver
    MODELOS_IMPRESSAO). Pode devolver uma chave desconhecida — é o que uma
    máquina numa versão anterior recebe da malha quando outra, mais nova,
    escolhe um modelo que ainda não existia aqui (ver _mesclar_ajustes). Quem
    desenha trata isso como o modelo clássico."""
    return _config.get("modelo_impressao", MODELO_PADRAO)


def atributos_campo(campo):
    """Os atributos de estilo configurados pra `campo` (negrito, sublinhado,
    fundo preto, tamanho em pixels), numa cópia.

    Existe pra quem DESENHA a comanda em vez de imprimi-la em texto: no caminho
    de texto o estilo viaja embutido na própria string (ver formatar_campo), mas
    um modelo de imagem que remonta a tabela de itens a partir dos dados
    (comandaImagemService, modelo "rascunho") não tem essa string — precisa ler
    os atributos direto. Cópia, e não o dict interno, porque quem chama está
    fora deste módulo e uma escrita distraída ali mudaria a configuração do app
    inteiro sem passar por _salvar.

    Campo desconhecido devolve o padrão, e não um dict vazio: um modelo novo que
    invente uma chave de estilo ainda desenha com um tamanho de fonte válido em
    vez de tropeçar num None."""
    padrao = _atributos_campo_padrao()
    padrao.update(_config["campos"].get(campo, {}))
    return padrao


# ---------- Sincronização entre máquinas da malha (ver
# ComandaEstiloController.__init__ abaixo e services/cardapioService.py,
# mesmo padrão) ----------

# Domínio de item único (não há "categorias" aqui, ao contrário de
# cardápio) — a mesma string serve de nome do domínio na anti-entropy e de
# única chave dentro dele.
_TIPO_EVENTO_ESTILO = "estilo_impressao_alterado"
_CHAVE_DOMINIO_ESTILO = "estilo_impressao"


# Marca impressa no topo e no rodapé da comanda de exemplo (ver
# ComandaEstiloController.imprimirComandaExemplo). Mesmo texto e mesmo negrito
# direto de balcaoController._MARCA_COMANDA_TESTE: é o aviso que a pizzaria já
# conhece como "este papel não é pedido de ninguém", e inventar um segundo
# jeito de dizer isso só criaria dúvida na hora de tirar o cupom da impressora.
MARCA_COMANDA_TESTE = f"{NEGRITO_LIGA}*** COMANDA DE TESTE ***{NEGRITO_DESLIGA}"


def _montar_linha_exemplo(trechos):
    """Uma linha da comanda de exemplo, a partir dos trechos que a tela mandou
    (ver ComandaEstiloController.imprimirComandaExemplo).

    Trecho sem campo de estilo (`c` vazio) entra cru: são os rótulos fixos
    ("Cliente: ") e os recuos, que no cupom de verdade também ficam fora do
    formatar_campo — é o que faz o negrito de um campo pegar só o valor dele, e
    não a linha inteira."""
    if not isinstance(trechos, list):
        return ""

    partes = []
    for trecho in trechos:
        if not isinstance(trecho, dict):
            continue
        conteudo = trecho.get("t") or ""
        campo = trecho.get("c") or ""
        partes.append(formatar_campo(conteudo, campo) if campo else conteudo)
    return "".join(partes)


def _payload_estilo():
    """`_config` já é um dict serializável em JSON (campos/espaçamentos/
    idEvento) — mandado como está, tanto no gossip quanto na
    reconciliação."""
    return _config


def _resumo_estilo():
    versao = _config.get("idEvento") or ""
    if not versao:
        # Nunca alterado desde que este mecanismo passou a existir (arquivo
        # de uma instalação anterior, sem "idEvento") — cai no hash de
        # conteúdo só pra detectar divergência entre máquinas; não decide
        # quem é mais novo (mesmo raciocínio de
        # cardapioService._resumo_cardapio).
        versao = hashlib.sha256(json.dumps(_config, sort_keys=True).encode("utf-8")).hexdigest()[:16]
    return {"itens": {_CHAVE_DOMINIO_ESTILO: versao}}


def _obter_estilo_reconciliacao(chave):
    if chave != _CHAVE_DOMINIO_ESTILO:
        return None
    return _payload_estilo()


def _aplicar_estilo_remoto(payload):
    """Aplica localmente um estilo de impressão recebido de outra máquina
    (gossip ou reconciliação) — só sobrescreve se o `idEvento` recebido for
    mais novo que o local (ver services/rede/relogio.py). Uma configuração
    com idEvento conhecido (já editada alguma vez, aqui ou noutra máquina)
    NUNCA é sobrescrita por uma sem idEvento nem por uma mais antiga — só
    por uma comprovadamente mais nova (relogio.mais_novo). Sem essa guarda
    dos dois lados, uma máquina que nunca editou o estilo (idEvento vazio,
    só o hash de fallback de _resumo_estilo) podia, na reconciliação, pedir
    a config de quem já editou e, ao mesmo tempo, ter sua própria config
    "vazia" pedida de volta — e como o lado que recebe usava só "payload
    sem idEvento é sempre aceito" (mesma regra afrouxada de
    CardapioController._ao_receber_cardapio_remoto), a máquina com a
    edição de verdade acabava voltando pros padrões. Só quando NENHUM dos
    dois lados tem idEvento (nenhuma máquina jamais editou) é que o
    payload recebido é aceito sem comparação — não há o que perder.
    Devolve True só se aplicou de fato (pra quem chama decidir se emite
    configuracaoAlterada)."""
    from services.rede import relogio

    global _config
    payload = payload or {}
    id_recebido = payload.get("idEvento", "")
    id_local = _config.get("idEvento", "")

    if id_recebido:
        relogio.observar(id_recebido)

    if id_local and (not id_recebido or not relogio.mais_novo(id_recebido, id_local)):
        return False

    novo = _padrao()
    _mesclar_campos(novo["campos"], payload.get("campos"))
    novo["ordem_secoes"] = _mesclar_ordem(payload.get("ordem_secoes"))
    _mesclar_ajustes(novo, payload)
    novo["idEvento"] = id_recebido

    _config = novo
    _salvar()
    return True


def _publicar_estilo_atual():
    from services.rede import rede

    rede.publicarEvento(_TIPO_EVENTO_ESTILO, _payload_estilo())


class ComandaEstiloController(QObject):
    """Ponte pra tela de Configurações (QML) ler/gravar o estilo acima."""

    configuracaoAlterada = pyqtSignal()

    def __init__(self):
        super().__init__()
        from services.rede import rede

        rede.registrarEvento(_TIPO_EVENTO_ESTILO, self._ao_receber_estilo_remoto)
        rede.registrarDominioSincronizado(
            _CHAVE_DOMINIO_ESTILO,
            _resumo_estilo,
            _obter_estilo_reconciliacao,
            self._aplicar_estilo_reconciliacao,
        )

    def _ao_receber_estilo_remoto(self, payload):
        if _aplicar_estilo_remoto(payload):
            self.configuracaoAlterada.emit()

    def _aplicar_estilo_reconciliacao(self, chave, payload):
        if chave != _CHAVE_DOMINIO_ESTILO:
            return
        if _aplicar_estilo_remoto(payload):
            self.configuracaoAlterada.emit()

    @pyqtSlot(result="QVariantMap")
    @protegido({})
    def obterConfiguracao(self):
        return _config

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarCampos(self):
        return [{"chave": campo, "rotulo": RODULOS_CAMPOS[campo]} for campo in CAMPOS]

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarAtributos(self):
        return [{"chave": atributo, "rotulo": RODULOS_ATRIBUTOS[atributo]} for atributo in ATRIBUTOS_BOOLEANOS]

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarFontes(self):
        """Catálogo pro seletor de fonte da comanda: a opção padrão (imprimir
        em texto, com a fonte da própria impressora) seguida das famílias
        oferecidas — que são as da MÁQUINA QUE IMPRIME, não as desta.

        Quem desenha a comanda é a máquina em que a impressora está ligada (o
        cupom viaja até lá, ver RedeService.solicitar_impressao). Oferecer aqui
        as fontes do computador em que o dono está mexendo seria oferecer uma
        escolha que não se cumpre: uma fonte instalada só no caixa não sai no
        papel se quem imprime é a máquina da cozinha.

        Sem saber quais são as fontes de lá (nenhuma máquina eleita, ou ela
        numa versão anterior a esta lista existir), sobra só a opção padrão —
        ver origemFontes(), que é o que a tela usa pra explicar a ausência.
        Melhor um seletor curto e honesto do que uma lista que promete o que
        não vai acontecer."""
        opcoes = [{"chave": FONTE_DA_IMPRESSORA, "rotulo": "Fonte da impressora (padrão)"}]
        opcoes.extend({"chave": familia, "rotulo": familia} for familia in self._fontes_da_impressora()["fontes"])
        return opcoes

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarModelosImpressao(self):
        """Catálogo pro seletor de modelo de desenho (ver MODELOS_IMPRESSAO).

        Ao contrário de listarFontes, esta lista não depende de máquina
        nenhuma: os modelos são código, e todas as máquinas da malha que
        estejam nesta versão têm os mesmos."""
        return [dict(modelo) for modelo in MODELOS_IMPRESSAO]

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def fonteDisponivelAqui(self, familia):
        """Se ESTA máquina tem a família `familia` instalada.

        Diferente de listarFontes, que oferece as fontes da máquina que
        IMPRIME: aqui a pergunta é sobre quem está desenhando a tela. A prévia
        da comanda usa isto pra decidir se pode escrever na fonte escolhida ou
        se cai na monoespaçada de medida — o Qt substituiria calado uma fonte
        que só existe na outra máquina, e a prévia mostraria uma tipografia que
        não é nem a da tela nem a do papel, sem avisar ninguém.

        Import adiado pelo mesmo motivo de services.rede (ver o cabeçalho do
        módulo): comandaImagemService importa este módulo, e um import no topo
        fecharia o ciclo."""
        from services import comandaImagemService

        return comandaImagemService.fonte_disponivel(familia)

    @pyqtSlot(result="QVariantMap")
    @protegido({})
    def origemFontes(self):
        """De qual máquina veio a lista de listarFontes(), pra tela poder dizer
        isso em vez de deixar o dono adivinhar por que a lista está curta ou
        por que mudou de uma hora pra outra (a máquina que imprime é eleita, e
        a eleição muda quando alguém pluga a impressora em outro lugar)."""
        return self._fontes_da_impressora()

    def _fontes_da_impressora(self):
        from services.rede import rede

        return rede.fontes_da_impressora()

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarCamposOrdenaveis(self):
        """Catálogo dos campos que têm posição própria na comanda. Devolve
        também `categoria`, `tipos`, `documento` e `estilizavel` para a
        prévia da tela de Configurações conseguir desenhar os separadores
        (mesma regra de comandaTextoService.montar_linhas_por_ordem), mostrar
        só os campos do papel escolhido, apagar os campos que o tipo de
        comanda escolhido não imprime e desabilitar "Estilo…" nas âncoras de
        posição — sem duplicar CATEGORIA_CAMPO/TIPOS_POR_CAMPO/
        DOCUMENTO_POR_CAMPO/CAMPOS_ANCORA no QML, que divergiriam na primeira
        vez que alguém acrescentasse um campo aqui."""
        return [
            {
                "chave": campo,
                "rotulo": RODULOS_CAMPOS_ORDENAVEIS[campo],
                "categoria": CATEGORIA_CAMPO.get(campo, ""),
                "tipos": TIPOS_POR_CAMPO.get(campo, list(TIPOS_COMANDA)),
                "documento": DOCUMENTO_POR_CAMPO.get(campo, DOCUMENTO_PEDIDO),
                "estilizavel": campo in CAMPOS,
            }
            for campo in CAMPOS_ORDENAVEIS
        ]

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarTiposComanda(self):
        """Cada tipo com o documento (papel impresso) a que pertence — ver
        DOCUMENTO_POR_TIPO. Balcão/Entrega/Mesa compartilham "pedido"; Extras
        e Fechamento têm cada um o seu."""
        return [
            {"nome": tipo, "documento": DOCUMENTO_POR_TIPO.get(tipo, DOCUMENTO_PEDIDO)}
            for tipo in TIPOS_COMANDA
        ]

    @pyqtSlot(result=int)
    def tamanhoFontePadrao(self):
        return TAMANHO_FONTE_BASE_PX

    @pyqtSlot(result=int)
    def maxLinhasSeparador(self):
        return MAX_LINHAS_SEPARADOR

    @pyqtSlot(result=int)
    def tamanhoFonteMinimo(self):
        return TAMANHO_FONTE_MIN_PX

    @pyqtSlot(result=int)
    def tamanhoFonteMaximo(self):
        return TAMANHO_FONTE_MAX_PX

    @pyqtSlot("QVariantMap")
    @protegido()
    def salvarConfiguracaoCompleta(self, config):
        """Grava de uma vez a configuração inteira vinda da tela (chamado ao
        sair da tela de Configurações, não a cada clique/edição) — gravar em
        disco a cada mudança deixava os controles com uma sensação de
        atraso, porque a chamada síncrona pro Python bloqueia o próximo
        frame de renderização até terminar."""
        from services.rede import relogio

        global _config
        novo = _padrao()
        _mesclar_campos(novo["campos"], config.get("campos"))
        novo["ordem_secoes"] = _mesclar_ordem(config.get("ordem_secoes"))
        _mesclar_ajustes(novo, config)
        novo["idEvento"] = relogio.novo_id()

        _config = novo
        _salvar()
        self.configuracaoAlterada.emit()
        _publicar_estilo_atual()

    @pyqtSlot("QVariantMap", result=bool)
    @protegido(False)
    def imprimirComandaExemplo(self, renderizadores):
        """Imprime a comanda de exemplo da tela de Configurações, pra o dono
        conferir no PAPEL o que a prévia mostra na tela.

        POR QUE O CONTEÚDO VEM DA TELA: os textos de exemplo (o "João da
        Silva", a pizza calabresa, os blocos do recibo de diária) moram no QML,
        junto da prévia que os desenha — são material de tela, e mantê-los
        aqui em cópia faria o papel e a prévia divergirem na primeira vez que
        alguém mexesse num dos dois. O que a tela manda são só os TEXTOS, já
        separados por campo: `{chave: [[{t, c}, ...], ...]}` — uma lista de
        linhas por campo, cada linha uma lista de trechos com o texto (`t`) e o
        campo de estilo (`c`, vazio para o que não é estilizável, como o rótulo
        "Cliente: ").

        E POR QUE A MONTAGEM É AQUI: estilo, ordem, divisórias e espaçamento
        saem do MESMO caminho de uma comanda de verdade (formatar_campo +
        comandaTextoService.montar_linhas_por_ordem), não de uma imitação. É o
        que faz este papel ser um teste do que vai acontecer com o próximo
        pedido, e não de um cupom parecido.

        Usa a configuração GRAVADA, que é a que vale na hora de imprimir de
        verdade — quem chama grava as alterações pendentes antes (ver
        EstiloImpressora.imprimirExemplo).

        Devolve True quando o pedido de impressão foi despachado; o resultado
        em si chega depois, assíncrono, pelo sinal rede.impressaoResultado que
        main.qml já escuta pra qualquer impressão do app."""
        from services import comandaTextoService as texto
        from services.rede import rede

        montados = {}
        for chave, linhas in (renderizadores or {}).items():
            if not isinstance(linhas, list):
                continue
            montados[chave] = [_montar_linha_exemplo(linha) for linha in linhas]

        if not montados:
            print("[comandaEstiloService] Comanda de exemplo sem nenhum campo — nada a imprimir.")
            return False

        linhas_arquivo = [MARCA_COMANDA_TESTE]
        linhas_arquivo.extend(linhas_espacamento_secoes())
        linhas_arquivo.extend(texto.montar_linhas_por_ordem(ordem_secoes(), montados))
        linhas_arquivo.extend(linhas_espacamento_secoes())
        linhas_arquivo.append(MARCA_COMANDA_TESTE)

        conteudo = "\n".join(linhas_arquivo) + "\n"
        # Não grava em pedidos/ nem propaga pela malha, pelo mesmo motivo da
        # comanda de teste do Balcão: é papel de conferência, não um pedido —
        # não pode sobrar rastro nem aparecer na Consulta ou no Fechamento.
        rede.solicitar_impressao(conteudo.encode(texto.CODEPAGE_IMPRESSORA, errors="replace"))
        return True

    @pyqtSlot()
    @protegido()
    def restaurarPadroes(self):
        from services.rede import relogio

        global _config
        _config = _padrao()
        _config["idEvento"] = relogio.novo_id()
        _salvar()
        self.configuracaoAlterada.emit()
        _publicar_estilo_atual()
