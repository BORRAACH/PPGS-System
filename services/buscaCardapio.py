"""Índice de consulta do cardápio inteiro, por trás do Ctrl+S de qualquer tela.

O atendente com o cliente na linha precisa responder "quanto é a Calabresa
grande?" ou "o que vem na Moda do Dani?" sem sair da comanda que está
montando. Até aqui a única forma era abrir a tela de Cardápio (perdendo o que
estava preenchido) ou o popup de seleção de pedido, que mostra preço mas não
ingrediente e só cobre uma categoria por vez.

DE ONDE VÊM OS ITENS. De `cardapioService.CATEGORIAS`, e não de uma lista
própria: aquela estrutura já descreve cada categoria (arquivo, seção dentro do
JSON, campos, rótulos, ícone e cor), é o que a tela de Cardápio usa pra montar
os formulários, e é o que a malha sincroniza entre as máquinas. Reusá-la
significa que uma categoria nova aparece na busca sozinha, sem ninguém lembrar
de mexer aqui.

PROMOÇÕES. Não são uma categoria — são uma substituição de preço por NOME, e
só nos dias em que valem (data/cardapio/promocoes/, ver Pizzas.qml). A busca
aplica a mesma regra de dia da semana que a tela de Pizzas: o preço mostrado é
o que o cliente paga HOJE, com o preço de tabela ao lado quando os dois
diferem. Uma categoria "Promoções" separada duplicaria cada sabor na lista e
obrigaria o atendente a saber qual das duas linhas vale agora.

SOBRE A BUSCA BINÁRIA. Ela responde exatamente uma pergunta: "quais nomes
começam com este prefixo?" — duas buscas binárias sobre a lista ordenada de
nomes normalizados dão o intervalo inteiro em O(log n). É o caminho de quem
digita "cala" esperando Calabresa, que é o uso comum.

O que a busca binária NÃO responde, por construção: "quais nomes CONTÊM este
pedaço" (procurar "bacon" e achar "Frango Bacon") e "quais itens levam este
ingrediente". Nenhuma ordenação de nomes ajuda aí — só um índice invertido, e
com ~180 itens ele custaria mais memória e complexidade do que a varredura
linear que resolve isso em uma fração de milissegundo. Então: binária pro
prefixo, varredura pro resto, e os resultados saem em três faixas de
relevância (prefixo, pedaço do nome, ingrediente).
"""

import bisect
import json
import os
import unicodedata
from datetime import date

from services import cardapioService

# "promo_seg_qui.json" vale de segunda a quinta; "promo_sex_dom.json" de sexta
# a domingo. Mesma regra de Pizzas.qml:arquivoPromocaoDoDia — se as duas
# divergirem, a busca passa a mostrar um preço que a tela de pedido não pratica.
# date.weekday(): segunda=0 ... domingo=6.
_PROMO_SEG_QUI = "promo_seg_qui.json"
_PROMO_SEX_DOM = "promo_sex_dom.json"

_ROTULO = "buscaCardapio"

# Teto de resultados devolvidos ao QML. Ninguém lê 180 linhas numa lista de
# busca, e cada linha vira um delegate a instanciar na máquina fraca do balcão.
_LIMITE_PADRAO = 40


def _pasta_cardapio():
    raiz = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(raiz, "data", "cardapio")


def _arquivo_promocao_do_dia():
    return _PROMO_SEG_QUI if date.today().weekday() <= 3 else _PROMO_SEX_DOM


def normalizar(texto):
    """Minúsculas e sem acento, que é a forma comparável de tudo aqui.

    Sem isto, "acai" não acha "Açaí" e "moda" não acha "À Moda da Casa" — e
    ninguém digita acento com o cliente esperando. NFD separa a letra do
    acento e o filtro descarta as marcas combinantes, o que também resolve
    "ç" -> "c".
    """
    decomposto = unicodedata.normalize("NFD", str(texto or ""))
    sem_acento = "".join(c for c in decomposto if unicodedata.category(c) != "Mn")
    return " ".join(sem_acento.casefold().split())


def _formatar_preco(bruto):
    """"24,90" -> "R$ 24,90". Campo vazio devolve "" (nem toda pizza tem mini)."""
    texto = str(bruto or "").strip()
    return f"R$ {texto}" if texto else ""


def _carregar_promocoes():
    """{nome: {valorMini, valorBroto, valorGrande}} da promoção que vale hoje.

    Melhor esforço, igual ao lado QML: uma promoção com problema no arquivo
    não pode derrubar a consulta ao cardápio inteiro.
    """
    caminho = os.path.join(_pasta_cardapio(), "promocoes", _arquivo_promocao_do_dia())
    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            itens = json.load(arquivo)
    except (OSError, json.JSONDecodeError) as erro:
        print(f"[{_ROTULO}] Falha ao ler {caminho}: {erro} — seguindo sem promoções.")
        return {}

    if not isinstance(itens, list):
        return {}

    return {item["nome"]: item for item in itens if isinstance(item, dict) and item.get("nome")}


def _precos_do_item(categoria, item):
    """Os preços de um item, já rotulados:
    [{"rotulo": "Broto", "valor": "R$ 34,90", "chave": "valorBroto"}].

    O rótulo sai de "curto" na descrição do campo (ver cardapioService.
    CATEGORIAS) — é o mesmo texto que a tela de Cardápio usa no resumo da
    lista. Categorias de preço único têm "curto" vazio e caem em "Preço".

    "chave" existe para o lançamento rápido de pedido (ver
    qml/components/PopupLancamentoRapido.qml), que precisa saber QUAL campo de
    preço o atendente escolheu. Vai por chave e não por rótulo porque o rótulo
    é texto de exibição, editável na tela de Cardápio: casar "Francês" com o
    pão `pao_frances` quebraria em silêncio no dia em que alguém renomeasse o
    campo para "Pão francês". A chave é estável.

    O número puro NÃO viaja junto: quem precisa dele desfaz o "R$ " com
    MontagemItem.parseValor, que já trata as duas formas. Mandar os dois
    engordava em ~20% o payload da busca inteira, que atravessa a ponte pro
    QML a cada tecla digitada — e a máquina do balcão tem 2 núcleos.

    Um preço vazio continua não entrando na lista — é isso que faz uma pizza
    sem `valorMini` chegar ao QML com dois tamanhos, e uma bebida sem preço de
    mesa com um só, sem nenhum tratamento por categoria do lado de lá."""
    precos = []
    for campo in categoria["campos"]:
        if campo["tipo"] != cardapioService.PRECO:
            continue
        bruto = item.get(campo["chave"], "")
        valor = _formatar_preco(bruto)
        if valor:
            precos.append({
                "rotulo": campo["curto"] or "Preço",
                "valor": valor,
                "chave": campo["chave"],
            })
    return precos


def _aplicar_promocao(categoria, item, precos, promocoes):
    """Troca os preços pelos da promoção do dia, quando o sabor está nela.

    Devolve (precos_de_hoje, precos_de_tabela). A segunda lista só vem
    preenchida quando de fato mudou alguma coisa — mostrar "de R$ 59,90 por
    R$ 59,90" seria ruído.
    """
    promo = promocoes.get(item.get("nome", ""))
    if not promo:
        return precos, []

    promocionais = []
    for campo in categoria["campos"]:
        if campo["tipo"] != cardapioService.PRECO:
            continue
        # A promoção pode trazer só alguns dos três tamanhos; os que ela não
        # cita continuam valendo pelo cardápio normal (mesma regra de Pizzas.qml).
        bruto = promo.get(campo["chave"])
        if bruto is None:
            bruto = item.get(campo["chave"], "")
        valor = _formatar_preco(bruto)
        if valor:
            promocionais.append({
                "rotulo": campo["curto"] or "Preço",
                "valor": valor,
                "chave": campo["chave"],
            })

    if promocionais == precos:
        return precos, []
    return promocionais, precos


def _detalhes_do_item(categoria, item):
    """Os campos que não são nome nem preço — hoje só "ingredientes", mas sai
    da descrição da categoria pra um campo novo aparecer aqui sozinho."""
    detalhes = []
    for campo in categoria["campos"]:
        if campo["chave"] == "nome" or campo["tipo"] == cardapioService.PRECO:
            continue
        valor = str(item.get(campo["chave"], "") or "").strip()
        if valor:
            detalhes.append({"rotulo": campo["rotulo"], "valor": valor})
    return detalhes


def _montar_entradas():
    promocoes = _carregar_promocoes()
    entradas = []

    for categoria in cardapioService.CATEGORIAS:
        try:
            itens = cardapioService.carregar(categoria["chave"])
        except Exception as erro:  # noqa: BLE001 - uma categoria quebrada não pode derrubar a busca
            print(f"[{_ROTULO}] Falha ao ler a categoria '{categoria['chave']}': {erro} — ignorada.")
            continue

        for item in itens:
            nome = str(item.get("nome", "") or "").strip()
            if not nome:
                continue

            precos = _precos_do_item(categoria, item)
            # Promoção é por sabor de pizza; as outras categorias não têm o
            # conceito e passam direto.
            if categoria["chave"] == "pizzas":
                precos, precos_tabela = _aplicar_promocao(categoria, item, precos, promocoes)
            else:
                precos_tabela = []

            detalhes = _detalhes_do_item(categoria, item)
            ingredientes = next((d["valor"] for d in detalhes if d["rotulo"].startswith("Ingredientes")), "")

            entradas.append({
                "nome": nome,
                "categoria": categoria["rotulo"],
                # A chave estável da categoria, ao lado do rótulo de exibição:
                # é ela que o lançamento rápido usa pra decidir o roteiro de
                # perguntas (tamanho? pão? borda?) e pra saber que "Bacon" é um
                # adicional, não um item que se vende sozinho. O rótulo não
                # serve pra isso — é texto de tela.
                "chaveCategoria": categoria["chave"],
                "icone": categoria["icone"],
                "cor": categoria["cor"],
                "precos": precos,
                "precosTabela": precos_tabela,
                "emPromocao": bool(precos_tabela),
                "detalhes": detalhes,
                "ingredientes": ingredientes,
                "resumoPrecos": "   ".join(
                    (p["rotulo"] + " " + p["valor"]) if p["rotulo"] != "Preço" else p["valor"]
                    for p in precos
                ),
                # Só para o filtro; o QML não usa.
                "_nomeNormalizado": normalizar(nome),
                "_textoNormalizado": normalizar(nome + " " + ingredientes),
                # A categoria entra na busca porque o nome do item nem sempre
                # diz do que ele é: os copos de açaí se chamam "300 ML", e
                # quem digita "acai" quer os três, não a única bebida que por
                # acaso tem "Açaí" no nome.
                "_tudoNormalizado": normalizar(nome + " " + ingredientes + " " + categoria["rotulo"]),
            })

    # Ordenado pelo nome normalizado — é esta ordem que torna a busca binária
    # possível, e também a ordem em que a lista aparece com a busca vazia.
    entradas.sort(key=lambda e: (e["_nomeNormalizado"], e["categoria"]))
    return entradas


# ---------- Cache ----------
# O índice é reconstruído quando qualquer arquivo de cardápio muda em disco:
# a tela de Cardápio edita, e a malha grava o que veio de outra máquina (ver
# cardapioService._ao_receber_cardapio_remoto). Sem esta checagem, o atendente
# consultaria um preço que já não é o praticado.
_indice_em_memoria = None
_assinatura_em_memoria = None


def _assinatura_dos_arquivos():
    """(caminho, mtime, tamanho) de cada arquivo que alimenta o índice, mais o
    dia de hoje — a promoção vigente muda sozinha na virada da semana, sem
    nenhum arquivo ser tocado."""
    nomes = {categoria["arquivo"] for categoria in cardapioService.CATEGORIAS}
    assinatura = [date.today().isoformat()]
    for nome in sorted(nomes) + [os.path.join("promocoes", _arquivo_promocao_do_dia())]:
        caminho = os.path.join(_pasta_cardapio(), nome)
        try:
            info = os.stat(caminho)
            assinatura.append(f"{nome}:{info.st_mtime_ns}:{info.st_size}")
        except OSError:
            assinatura.append(f"{nome}:ausente")
    return tuple(assinatura)


def indice():
    """As entradas ordenadas por nome normalizado, reconstruídas só quando
    algum arquivo de cardápio mudou."""
    global _indice_em_memoria, _assinatura_em_memoria

    assinatura = _assinatura_dos_arquivos()
    if _indice_em_memoria is None or assinatura != _assinatura_em_memoria:
        _indice_em_memoria = _montar_entradas()
        _assinatura_em_memoria = assinatura
    return _indice_em_memoria


def invalidar():
    """Descarta o índice. A checagem de mtime já cobre o caso normal; isto
    existe pros testes e pra quem quiser forçar a releitura."""
    global _indice_em_memoria, _assinatura_em_memoria
    _indice_em_memoria = None
    _assinatura_em_memoria = None


# ---------- Busca ----------


def _faixa_por_prefixo(chaves, prefixo):
    """(inicio, fim) das entradas cujo nome começa com `prefixo`, por busca
    binária.

    O truque do limite superior: todo nome que começa com o prefixo é menor
    que o prefixo com o último caractere incrementado ("cala" -> "calb"), então
    um segundo bisect acha o fim da faixa sem varrer nada. Para o prefixo
    vazio, a faixa é a lista inteira.
    """
    if not prefixo:
        return 0, len(chaves)

    inicio = bisect.bisect_left(chaves, prefixo)
    limite = prefixo[:-1] + chr(ord(prefixo[-1]) + 1)
    fim = bisect.bisect_left(chaves, limite, lo=inicio)
    return inicio, fim


def listar_da_categoria(chave_categoria, termo=""):
    """Todos os itens de UMA categoria, em ordem alfabética, opcionalmente
    filtrados por `termo` (no nome ou nos ingredientes).

    Serve à etapa "escolha a pizza" do lançamento rápido, quando o atendente
    entrou pelo caminho invertido — buscou "Borda Catupiry" e agora precisa
    dizer em qual pizza ela vai (ver qml/components/PopupLancamentoRapido.qml).

    Sai daqui, e não de cardapioService.carregar(), porque este índice já tem
    a promoção do dia aplicada em `precos` e o preço de tabela em
    `precosTabela` — ler o JSON cru devolveria sempre o preço de tabela, e a
    pizza em promoção sairia mais cara pelo caminho rápido do que pelo normal.

    Sem o teto de `buscar()`: aquele existe porque uma busca de termo vazio
    casaria com o cardápio inteiro (~180 itens) numa lista só; aqui a
    categoria já é o recorte, e as 74 pizzas são exatamente o que se quer
    poder rolar."""
    alvo = normalizar(termo)
    return [
        _sem_campos_internos(entrada)
        for entrada in indice()
        if entrada["chaveCategoria"] == chave_categoria
        and (not alvo or alvo in entrada["_textoNormalizado"])
    ]


def buscar(termo, limite=_LIMITE_PADRAO):
    """Itens do cardápio que casam com `termo`, mais relevantes primeiro.

    Quatro faixas, nesta ordem: nome começando com o termo (busca binária),
    nome contendo o termo, ingrediente contendo o termo, e categoria contendo
    o termo. Termo com mais de uma palavra exige todas elas (em qualquer um
    dos três campos) e não usa a binária — ver a nota no topo do módulo.

    Termo vazio devolve o cardápio inteiro em ordem alfabética, que é o que a
    tela mostra enquanto ninguém digitou nada.
    """
    entradas = indice()
    alvo = normalizar(termo)

    if not alvo:
        return [_sem_campos_internos(e) for e in entradas[:limite]]

    palavras = alvo.split()
    if len(palavras) > 1:
        # Mesmas faixas de relevância do caso de uma palavra, só que sem a
        # binária: quem digita "frango bacon" quer a pizza com esse nome antes
        # das outras que levam os dois ingredientes. Sem esta ordenação, a
        # ordem alfabética punha "À Moda do Jura" na frente da "Frango Bacon".
        no_nome = []
        no_ingrediente = []
        na_categoria = []
        for entrada in entradas:
            if all(p in entrada["_nomeNormalizado"] for p in palavras):
                no_nome.append(entrada)
            elif all(p in entrada["_textoNormalizado"] for p in palavras):
                no_ingrediente.append(entrada)
            elif all(p in entrada["_tudoNormalizado"] for p in palavras):
                na_categoria.append(entrada)
        casam = no_nome + no_ingrediente + na_categoria
        return [_sem_campos_internos(e) for e in casam[:limite]]

    chaves = [e["_nomeNormalizado"] for e in entradas]
    inicio, fim = _faixa_por_prefixo(chaves, alvo)

    resultado = list(entradas[inicio:fim])
    ja_incluidos = set(range(inicio, fim))

    # As três faixas restantes numa varredura só, preservando a prioridade
    # entre elas.
    no_nome = []
    no_ingrediente = []
    na_categoria = []
    for posicao, entrada in enumerate(entradas):
        if posicao in ja_incluidos:
            continue
        if alvo in entrada["_nomeNormalizado"]:
            no_nome.append(entrada)
        elif alvo in entrada["_textoNormalizado"]:
            no_ingrediente.append(entrada)
        elif alvo in entrada["_tudoNormalizado"]:
            na_categoria.append(entrada)

    resultado.extend(no_nome)
    resultado.extend(no_ingrediente)
    resultado.extend(na_categoria)
    return [_sem_campos_internos(e) for e in resultado[:limite]]


def _sem_campos_internos(entrada):
    """Os campos "_*" são do filtro e não têm o que fazer no QML."""
    return {chave: valor for chave, valor in entrada.items() if not chave.startswith("_")}


def total():
    return len(indice())
