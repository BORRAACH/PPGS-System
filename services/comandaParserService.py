"""Extração de campos do cabeçalho de uma comanda já salva (pedidos/*.txt) —
compartilhado por ConsultaController (exibir/editar/apagar) e
FechamentoController (somar/agrupar por dia).

Extraído de controllers/consultaController.py quando FechamentoController
apareceu como um segundo consumidor dessas mesmas regexes — mesmo motivo
que já levou comandaTextoService.py a existir (ver o docstring de lá).
Comportamento idêntico ao que já rodava dentro de ConsultaController; só
mudou de endereço.

Inclui também o parsing pesado da tabela de itens (`reconstruir_itens`), que
por muito tempo viveu só dentro de consultaController.py: enquanto o único
consumidor era "reabrir a comanda num formulário editável" (Consulta >
Editar), deixá-lo lá fazia sentido. Deixou de fazer quando
services/comandaComparacaoService.py passou a precisar dos MESMOS itens para
comparar duas versões da mesma comanda campo a campo — duas cópias dessa
lógica divergiriam na primeira vez que alguém mexesse no formato da tabela, e
a comparação passaria a acusar diferença onde não há."""

import re

from services import comandaEstiloService as estilo
from services.comandaTextoService import (
    MARCADOR_ITENS,
    PREFIXO_ADICIONAL,
    PREFIXO_BORDA,
    PREFIXO_ITEM_UNICO,
    valor_para_float,
)

CODEPAGE_IMPRESSORA = "cp850"

# Forma de pagamento que já vem selecionada quando o formulário de pedido abre
# limpo. Usada por eh_suspeita para reconhecer a comanda em que ninguém tocou
# no bloco de pagamento — não é uma preferência de negócio, é "o que o combo
# mostra sozinho".
#
# Tem que ser a MESMA de qml/components/CamposPagamento.qml
# (formaPagamentoPadrao) e de qml/pages/salao/PopupFecharConta.qml. Se
# divergirem, a comanda deixada no padrão para de ser sinalizada em
# Consulta/Fechamento — e nada quebra de forma visível, o aviso só some.
FORMA_PAGAMENTO_PADRAO = "Dinheiro"

ESC = "\x1b"
GS = "\x1d"
# Remove os códigos ESC/POS de estilo embutidos no .txt pelos controllers de
# venda — só fazem sentido para a impressora térmica, não para exibição em
# tela nem para extrair campos.
#
# São os quatro comandos que comandaEstiloService.formatar_campo emite, cada
# um com um byte de parâmetro logo depois: negrito (ESC E n), sublinhado
# (ESC - n), fundo preto/modo reverso (GS B n) e tamanho da fonte (GS ! n).
# Por muito tempo só o negrito era removido aqui, porque só ele existia; os
# outros três chegaram com a tela Configurações > Estilo e passaram
# despercebidos, então os campos configurados com eles (endereco e bairro
# saem sublinhados e maiores por padrão) voltavam de reconstruirComanda com
# os bytes de controle no meio do texto — e eram reimpressos assim,
# aninhando um estilo dentro do outro a cada edição da mesma comanda.
# O marcador de tamanho exato em pixels entra na mesma limpeza (ver
# comandaEstiloService.MARCA_TAMANHO_PX): ele só existe para quem DESENHA a
# comanda, e aqui, que é quem a lê de volta, é lixo igual aos outros — sem
# removê-lo, o "\x1d~048" apareceria no meio do nome do cliente na Consulta e
# seria reimpresso junto a cada edição, aninhando um marcador dentro do outro.
# Diferente dos quatro de cima, o parâmetro dele tem três caracteres.
_PADRAO_ESTILO = re.compile(
    r"(?:" + re.escape(ESC) + r"[E\-]|" + re.escape(GS) + r"[B!])[\s\S]"
    r"|" + re.escape(estilo.MARCA_TAMANHO_PX) + r"\d{3}"
)

# Sem underscore: usadas de fora (ConsultaController) via extrair_campo(),
# diferente das de baixo, que só interessam às funções desta própria
# arquivo (por isso ficam encapsuladas em extrair_status_pagamento/
# extrair_valor_total em vez de expostas soltas).
PADRAO_CLIENTE = re.compile(r"^Cliente:[ \t]*(.*)$", re.MULTILINE)
PADRAO_DATA = re.compile(r"^Data:[ \t]*(.*)$", re.MULTILINE)
PADRAO_FORMA_PAGAMENTO = re.compile(r"^Forma de pagamento:[ \t]*(.*)$", re.MULTILINE)
# Só entregaController imprime esta linha (ver EntregaController._salvarComanda)
# — Balcão/Mesa não têm endereço, e extrair_campo devolve "" pra eles, o que
# é o comportamento certo (ver eh_suspeita abaixo).
PADRAO_ENDERECO = re.compile(r"^Endereço:[ \t]*(.*)$", re.MULTILINE)
# Código curto do cabeçalho (ver services/comandaSequencialService.py), ex:
# "ID: A291201". Está no arquivo desde que passou a ser impresso, mas até
# agora ninguém o lia de volta — a Consulta o mostra pra que o mesmo código
# que está no papel possa ser conferido entre as máquinas. Comandas
# anteriores a ele simplesmente não têm a linha, e extrair_campo devolve "".
PADRAO_ID_PEDIDO = re.compile(r"^ID:[ \t]*(.*)$", re.MULTILINE)

# Campos exclusivos de Entrega (ver EntregaController._salvarComanda). Vieram
# de consultaController.py junto com reconstruir_itens, pelo mesmo motivo: a
# comparação entre máquinas precisa deles tanto quanto a tela de edição.
PADRAO_TELEFONE = re.compile(r"^Telefone:[ \t]*(.*)$", re.MULTILINE)
# Só o cupom final de Mesa imprime esta linha (ver SalaoController._montarCupomFinal).
PADRAO_MESA = re.compile(r"^Mesa:[ \t]*(.*)$", re.MULTILINE)
PADRAO_BAIRRO = re.compile(r"^Bairro:[ \t]*(.*)$", re.MULTILINE)
PADRAO_OBSERVACAO_GERAL = re.compile(r"^Observação:[ \t]*(.*)$", re.MULTILINE)
PADRAO_TROCO = re.compile(r"^Troco para:[ \t]*(.*)$", re.MULTILINE)
PADRAO_TAXA_ENTREGA = re.compile(r"^Taxa de entrega:[ \t]*(.*)$", re.MULTILINE)

# Linha de um item na tabela do cupom: "coluna_pedido | valor". A observação
# (quando houver) vem numa linha própria logo abaixo, recuada com 2 espaços
# (ver comandaTextoService.formatar_tabela).
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
# O prefixo de um item que não é pizza fracionada. Reconhece o de hoje
# (PREFIXO_ITEM_UNICO, a quantidade: "1 PORTUGUESA") e o "- " que as comandas
# gravadas antes dele têm — sem o segundo, editar uma comanda antiga via
# Consulta traria o traço para dentro do nome do item, e ele sairia reimpresso
# como "1 - PORTUGUESA".
_PADRAO_PREFIXO_ITEM = re.compile(r"^(?:" + re.escape(PREFIXO_ITEM_UNICO) + r"|- )")
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

# Tamanho que não coube na linha do item e desceu sozinho para a de baixo (ver
# comandaTextoService._acomodar_tamanho). Precisa ser reconhecido ANTES da
# linha de observação, que também é recuada e casaria com ele — e aí o
# "(BROTO)" viraria a observação do pedido ao editar a comanda, some do nome do
# item e ainda aparece escrito no lugar errado.

_PADRAO_LINHA_TAMANHO = re.compile(r"^\s+\(([^)]+)\)\s*$")

_PADRAO_STATUS_PAGAMENTO = re.compile(r"^Status:[ \t]*(.*)$", re.MULTILINE)
# balcaoController imprime o status colado no fim da linha do valor total
# (ex: "Valor do pedido: R$ 45,00 [PG]") em vez de uma linha "Status:"
# própria como o entregaController — precisa de um padrão à parte para
# reconstruir.
_PADRAO_STATUS_PAGAMENTO_INLINE = re.compile(r"^Valor do pedido:.*\[(NP|PG)\][ \t]*$", re.MULTILINE)
# Valor total do pedido (Balcão/Entrega/Mesa sempre imprimem essa linha, com
# ou sem o status colado no fim — ver acima). Não-guloso antes de "R$" pra
# pular por cima de qualquer código ESC/POS de estilo que o campo tenha
# (negrito/sublinhado/etc. configurados em Configurações > Estilo).
_PADRAO_VALOR_TOTAL = re.compile(r"^Valor do pedido:.*?R\$\s*([\d.,]+)", re.MULTILINE)

# Os três tipos de comanda embutem a data (AAAAMMDD) no próprio nome do
# arquivo: "pedido_AAAAMMDD_HHMMSS_hash.txt" (Balcão), "entrega_..." e
# "mesa_..." — ver data_arquivo_aaaammdd.
_PADRAO_PREFIXO_ARQUIVO = re.compile(r"^(mesa|entrega|pedido)_(\d{8})_")
# O mesmo carimbo, agora com a hora junto — ver carimbo_arquivo.
_PADRAO_CARIMBO_ARQUIVO = re.compile(r"^(?:mesa|entrega|pedido)_(\d{8})_(\d{6})_")

# Sufixo aleatório do nome do arquivo ("..._07fe75.txt") — ver
# balcaoController._salvarComanda.
_PADRAO_SUFIXO_ARQUIVO = re.compile(r"_([0-9a-f]{6})\.txt$")

# Uma linha por pessoa na seção "DIVISÃO DA CONTA" de uma comanda de Mesa
# (ver salaoController._montarCupomFinal), ex: "Fulano: R$ 45,00 [Pix] [PG]".
# É o único lugar onde uma comanda de Mesa registra forma de pagamento — o
# cabeçalho dela não tem "Forma de pagamento:" porque cada divisão pode ser
# paga de um jeito diferente (ver eh_suspeita, que por isso pula Mesa).
_PADRAO_DIVISAO_MESA = re.compile(r"^(.+): (R\$\s*[\d.,]+) \[([^\]]*)\] \[(NP|PG)\]$", re.MULTILINE)


def limpar_codigos_impressora(texto):
    return _PADRAO_ESTILO.sub("", texto)


def extrair_campo(padrao, texto):
    match = padrao.search(texto)
    return match.group(1).strip() if match else ""


def extrair_status_pagamento(texto):
    """Tenta primeiro a linha "Status:" própria (entregaController); se não
    encontrar, tenta o formato colado na linha do valor total
    (balcaoController). Comandas de Mesa não têm nenhum dos dois no nível
    do cabeçalho (cada divisão da conta tem sua própria forma/status, lá
    embaixo na seção "DIVISÃO DA CONTA") — devolve "" nesse caso."""
    status = extrair_campo(_PADRAO_STATUS_PAGAMENTO, texto)
    if status:
        return status

    match = _PADRAO_STATUS_PAGAMENTO_INLINE.search(texto)
    return match.group(1) if match else ""


def extrair_valor_total(texto):
    """Valor total impresso na comanda (já inclui taxa de entrega, quando
    houver — ver EntregaController._salvarComanda). 0.0 se não encontrar."""
    match = _PADRAO_VALOR_TOTAL.search(texto)
    if not match:
        return 0.0
    return valor_para_float("R$ " + match.group(1))


def eh_suspeita(tipo, cliente, forma_pagamento, status, endereco=""):
    """Sinaliza uma comanda que provavelmente teve um erro de digitação na
    hora do pedido, pra revisão manual em Consulta/Fechamento (borda
    vermelha nas duas telas, ver ItemComandaDelegate.qml e Fechamento.qml).

    Dois critérios independentes (OR), qualquer um basta:
    - Sem nome do cliente + status NP + a forma de pagamento PADRÃO, em
      Balcão/Entrega — a combinação exata de quem lançou o pedido sem tocar
      em nada do bloco de pagamento. Mesa não entra aqui: cada divisão da
      conta tem seu próprio nome/status/forma, sem um único valor no nível
      do cabeçalho (ver FechamentoController._calcular_resumo_dia).
    - Entrega sem nome OU sem endereço — os dois são obrigatórios pra
      entregar de verdade, então a ausência de qualquer um dos dois é sinal
      de pedido incompleto, independente da forma de pagamento."""
    cliente = (cliente or "").strip()
    endereco = (endereco or "").strip()

    if tipo != "Mesa" and cliente == "" and status == "NP" and forma_pagamento == FORMA_PAGAMENTO_PADRAO:
        return True

    if tipo == "Entrega" and (cliente == "" or endereco == ""):
        return True

    return False


def extrair_divisoes_mesa(texto):
    """Cada linha da seção "DIVISÃO DA CONTA" de uma comanda de Mesa como
    {"nome", "valor", "formaPagamento", "status"} — usado pra saber quanto
    de uma Mesa foi pago em dinheiro/Pix/cartão no cupom de "Fechar Caixa"
    (ver FechamentoController._somar_por_forma_pagamento). [] para
    comandas sem essa seção (Balcão/Entrega, ou Mesa fechada sem
    divisão)."""
    resultado = []
    for correspondencia in _PADRAO_DIVISAO_MESA.finditer(texto):
        resultado.append({
            "nome": correspondencia.group(1).strip(),
            "valor": valor_para_float(correspondencia.group(2)),
            "formaPagamento": correspondencia.group(3),
            "status": correspondencia.group(4),
        })
    return resultado


def tipo_comanda(nome_arquivo):
    if nome_arquivo.startswith("mesa_"):
        return "Mesa"
    if nome_arquivo.startswith("entrega_"):
        return "Entrega"
    return "Balcão"


def carimbo_arquivo(nome_arquivo):
    """"AAAAMMDD_HHMMSS" embutido no nome do arquivo — chave de ordenação
    cronológica que não depende de abrir a comanda nem do mtime (que é o
    momento da gravação LOCAL: numa comanda recebida pela rede ele difere de
    máquina pra máquina).

    Existe separado de data_arquivo_aaaammdd porque ordenar pelo nome inteiro
    NÃO ordena por tempo: o prefixo vem antes do carimbo, então
    "pedido_..._190001" ordena depois de "mesa_..._190003" só por causa da
    letra. Devolve "" quando o nome não bate com o padrão — esses vão pro fim
    de uma ordenação decrescente, que é o lugar certo pra uma comanda de
    origem desconhecida."""
    correspondencia = _PADRAO_CARIMBO_ARQUIVO.match(nome_arquivo)
    return correspondencia.group(1) + correspondencia.group(2) if correspondencia else ""


def codigo_comanda(nome_arquivo, conteudo):
    """Código curto pra identificar a comanda ao conferir duas máquinas na
    mão. É o mesmo que está impresso no papel (linha "ID:", ver
    services/comandaSequencialService.py); comandas anteriores a esse código
    caem no sufixo aleatório do nome do arquivo, que também é idêntico em
    todas as máquinas por ser parte da identidade da comanda."""
    codigo = extrair_campo(PADRAO_ID_PEDIDO, conteudo)
    if codigo:
        return codigo

    correspondencia = _PADRAO_SUFIXO_ARQUIVO.search(nome_arquivo)
    return correspondencia.group(1).upper() if correspondencia else ""


def data_arquivo_aaaammdd(nome_arquivo):
    """Extrai a data (string "AAAAMMDD") embutida no nome do arquivo, sem
    abrir/ler o conteúdo — permite filtrar comandas de um dia específico
    (ver FechamentoController._calcular_resumo_dia) antes de gastar
    qualquer I/O de disco com arquivos de outros dias. None se o nome não
    bater com o padrão esperado (arquivo de origem desconhecida)."""
    match = _PADRAO_PREFIXO_ARQUIVO.match(nome_arquivo)
    return match.group(2) if match else None


def linhas_tabela_itens(linhas):
    """As linhas da tabela de itens dentro de `linhas` (o cupom já limpo,
    quebrado por "\\n"), ou None quando não dá pra localizá-la.

    A tabela é sempre cercada por MARCADOR_ITENS ("="*40), não importa em que
    posição da comanda ela esteja configurada pra sair (ver
    comandaEstiloService.ordem_secoes/comandaTextoService.montar_linhas_por_ordem)
    — diferente do separador genérico ("-"*40) usado entre os demais campos,
    que pode aparecer em qualquer quantidade e posição. O fallback cobre
    comandas gravadas antes dessa mudança, quando a tabela de itens sempre
    ficava entre a 1ª e a 2ª linha de traços do arquivo."""
    divisorias = [i for i, linha in enumerate(linhas) if linha == MARCADOR_ITENS]
    if len(divisorias) < 2:
        divisorias = [i for i, linha in enumerate(linhas) if linha.startswith("----")]
    if len(divisorias) < 2:
        return None

    return linhas[divisorias[0] + 1:divisorias[1]]


def dividir_endereco_numero(endereco_completo):
    """Desfaz o "Endereço, Número" montado por entregaController.enviarPedido."""
    if not endereco_completo:
        return "", ""

    partes = endereco_completo.rsplit(",", 1)
    if len(partes) == 2 and partes[1].strip():
        return partes[0].strip(), partes[1].strip()

    return endereco_completo.strip(), ""


def reconstruir_itens(linhas_tabela):
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
            pedido = _PADRAO_PREFIXO_ITEM.sub("", coluna_pedido, count=1)
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

        # Tamanho que desceu de linha: volta para o fim do nome do item, que é
        # de onde ele saiu. Reconstruído assim, o item volta idêntico ao que
        # foi lançado — e reimprimi-lo torna a descer o tamanho, se continuar
        # não cabendo.
        match_tamanho_solto = _PADRAO_LINHA_TAMANHO.match(linha)
        if (match_tamanho_solto and grupo_atual
                and match_tamanho_solto.group(1).strip().upper() in _TAMANHOS_VALIDOS_UPPER):
            coluna_pedido, observacao, valor, adicionais = grupo_atual[-1]
            grupo_atual[-1] = (
                f"{coluna_pedido} ({match_tamanho_solto.group(1).strip()})",
                observacao,
                valor,
                adicionais,
            )
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
