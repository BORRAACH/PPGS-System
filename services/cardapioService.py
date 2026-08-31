"""Leitura e gravação do cardápio (data/cardapio/*.json) pela tela Cardápio
(qml/pages/cardapio/Cardapio.qml).

As telas de pedido (qml/pages/pedidos/) continuam lendo esses mesmos arquivos
direto por XMLHttpRequest — só a edição passa por aqui, porque o QML não
grava arquivo. Como cada tela de pedido é criada de novo a cada vez que entra
na pilha, ela relê o JSON do disco sozinha: alterações feitas aqui já valem no
próximo pedido, sem reiniciar o app.

Cada categoria descreve seus próprios campos (CATEGORIAS abaixo) porque os
arquivos não têm o mesmo formato: pizza tem três preços por tamanho, lanche
tem três preços por tipo de pão (aninhados em "valor"), bebida e "outros" têm
um preço só. A tela monta o formulário a partir dessa descrição, em vez de ter
um formulário escrito à mão por categoria.

Uma categoria normalmente ocupa um arquivo inteiro (a lista de itens é a raiz
do JSON), mas pode ocupar só uma parte dele: acai.json guarda dois grupos
independentes ("tamanhos" e "adicionais") num objeto só, porque a tela de
Açaí lê os dois juntos. Categorias assim declaram "secao" e duas delas
convivem no mesmo arquivo — ver _categorias_por_arquivo e a mesclagem em
salvar().

Atenção: só os campos descritos aqui sobrevivem a uma gravação — o arquivo é
reescrito a partir da lista de campos da categoria, então uma chave nova
adicionada à mão no JSON (sem entrar em CATEGORIAS) se perde no primeiro
salvamento feito pela tela.
"""

import base64
import hashlib
import json
import os
import re

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services.rede import relogio, rede

# Tipos de campo que a tela sabe renderizar (ver PopupItemCardapio.qml):
# uma linha de texto, um texto de várias linhas e um preço no formato
# "24,90".
TEXTO = "texto"
TEXTO_LONGO = "texto_longo"
PRECO = "preco"

# "chave" é o caminho dentro do JSON do item — "valor.pao_frances" quer dizer
# item["valor"]["pao_frances"] (ver _ler_caminho/_gravar_caminho). Para a tela
# isso é só uma chave opaca de um objeto plano; quem desmonta/remonta o
# aninhamento é este módulo.
#
# "curto" é o rótulo usado no resumo de preços da lista (ex: "Mini R$ 24,90");
# vazio quando a categoria só tem um preço e não precisa de qualificação.
#
# "secao" (opcional) é a chave do objeto JSON onde a lista de itens desta
# categoria mora. Sem ela, a lista é a própria raiz do arquivo.
CATEGORIAS = [
    {
        "chave": "pizzas",
        "rotulo": "Pizzas",
        "novoRotulo": "Nova pizza",
        "arquivo": "pizzas.json",
        "icone": "fa6s.pizza-slice",
        "cor": "#d32f2f",
        # pizzas.json e lanches.json têm um "id" por item; bebidas.json e
        # outros.json não. Ver _numerar_itens.
        "numerado": True,
        "campos": [
            {"chave": "nome", "rotulo": "Nome do sabor", "tipo": TEXTO, "obrigatorio": True, "curto": ""},
            {"chave": "ingredientes", "rotulo": "Ingredientes", "tipo": TEXTO_LONGO, "obrigatorio": False, "curto": ""},
            # Nem toda pizza tem mini (ver data/cardapio/pizzas.json: pizzas
            # "especiais" como Camarão só vêm a partir do broto) — por isso
            # este é o único preço opcional das três, diferente de broto/
            # grande, que toda pizza tem.
            {"chave": "valorMini", "rotulo": "Preço (mini)", "tipo": PRECO, "obrigatorio": False, "curto": "Mini"},
            {"chave": "valorBroto", "rotulo": "Preço (broto)", "tipo": PRECO, "obrigatorio": True, "curto": "Broto"},
            {"chave": "valorGrande", "rotulo": "Preço (grande)", "tipo": PRECO, "obrigatorio": True, "curto": "Grande"},
        ],
    },
    # Bordas e adicionais de pizza dividem adicionais.json, do mesmo jeito que
    # as duas seções de acai.json (ver "secao" acima): a tela de Pizzas lê os
    # dois grupos numa leitura só (qml/pages/pedidos/pizzas/PopupAdicionaisBordas.qml
    # espera "bordas" e "adicionais" no mesmo objeto), mas aqui são duas listas
    # editáveis independentes.
    {
        "chave": "pizzaBordas",
        "rotulo": "Bordas de pizza",
        "novoRotulo": "Nova borda",
        "arquivo": "adicionais.json",
        "secao": "bordas",
        "icone": "fa6s.circle-notch",
        "cor": "#d32f2f",
        "numerado": False,
        "campos": [
            {"chave": "nome", "rotulo": "Nome da borda", "tipo": TEXTO, "obrigatorio": True, "curto": ""},
            {"chave": "valor", "rotulo": "Preço", "tipo": PRECO, "obrigatorio": True, "curto": ""},
        ],
    },
    {
        "chave": "pizzaAdicionais",
        "rotulo": "Adicionais de pizza",
        "novoRotulo": "Novo adicional",
        "arquivo": "adicionais.json",
        "secao": "adicionais",
        "icone": "fa6s.plus",
        "cor": "#d32f2f",
        "numerado": False,
        "campos": [
            {"chave": "nome", "rotulo": "Nome do adicional", "tipo": TEXTO, "obrigatorio": True, "curto": ""},
            {"chave": "valor", "rotulo": "Preço", "tipo": PRECO, "obrigatorio": True, "curto": ""},
        ],
    },
    {
        "chave": "lanches",
        "rotulo": "Lanches",
        "novoRotulo": "Novo lanche",
        "arquivo": "lanches.json",
        "icone": "fa6s.burger",
        "cor": "#e67e22",
        "numerado": True,
        "campos": [
            {"chave": "nome", "rotulo": "Nome do lanche", "tipo": TEXTO, "obrigatorio": True, "curto": ""},
            {"chave": "ingredientes", "rotulo": "Ingredientes", "tipo": TEXTO_LONGO, "obrigatorio": False, "curto": ""},
            {"chave": "valor.pao_hamburguer", "rotulo": "Preço (pão de hambúrguer)", "tipo": PRECO, "obrigatorio": True, "curto": "Hambúrguer"},
            {"chave": "valor.pao_frances", "rotulo": "Preço (pão francês)", "tipo": PRECO, "obrigatorio": True, "curto": "Francês"},
            {"chave": "valor.pao_baby", "rotulo": "Preço (pão baby)", "tipo": PRECO, "obrigatorio": True, "curto": "Baby"},
        ],
    },
    # Ao contrário dos de pizza, os adicionais de lanche ocupam o arquivo
    # inteiro (a lista é a raiz de adicionaisLanches.json), então não declaram
    # "secao" — ver PopupAdicionaisLanches.qml, que itera o JSON direto.
    {
        "chave": "lanchesAdicionais",
        "rotulo": "Adicionais de lanche",
        "novoRotulo": "Novo adicional",
        "arquivo": "adicionaisLanches.json",
        "icone": "fa6s.plus",
        "cor": "#e67e22",
        "numerado": False,
        "campos": [
            {"chave": "nome", "rotulo": "Nome do adicional", "tipo": TEXTO, "obrigatorio": True, "curto": ""},
            {"chave": "valor", "rotulo": "Preço", "tipo": PRECO, "obrigatorio": True, "curto": ""},
        ],
    },
    {
        "chave": "bebidas",
        "rotulo": "Bebidas",
        "novoRotulo": "Nova bebida",
        "arquivo": "bebidas.json",
        "icone": "fa6s.glass-water",
        "cor": "#3498db",
        "numerado": False,
        "campos": [
            {"chave": "nome", "rotulo": "Nome da bebida", "tipo": TEXTO, "obrigatorio": True, "curto": ""},
            {"chave": "valor", "rotulo": "Preço", "tipo": PRECO, "obrigatorio": True, "curto": ""},
            # Opcional: só alguns itens têm um preço diferente pra comanda de
            # mesa (ver qml/pages/pedidos/bebidas/Bebidas.qml:comandaDeMesa) —
            # a maioria das bebidas cobra o mesmo valor em Balcão/Entrega/Salão
            # e não preenche este campo.
            {"chave": "valorMesa", "rotulo": "Preço no salão/mesa (opcional)", "tipo": PRECO, "obrigatorio": False, "curto": "Mesa"},
        ],
    },
    # As duas categorias de açaí dividem acai.json (ver "secao" acima): a tela
    # de Açaí precisa dos tamanhos e dos adicionais juntos numa leitura só, mas
    # aqui eles são duas listas editáveis independentes.
    {
        "chave": "acaiTamanhos",
        "rotulo": "Açaí",
        "novoRotulo": "Novo tamanho",
        "arquivo": "acai.json",
        "secao": "tamanhos",
        "icone": "fa6s.ice-cream",
        "cor": "#8e44ad",
        "numerado": False,
        "campos": [
            {"chave": "nome", "rotulo": "Tamanho do copo", "tipo": TEXTO, "obrigatorio": True, "curto": ""},
            {"chave": "valor", "rotulo": "Preço", "tipo": PRECO, "obrigatorio": True, "curto": ""},
        ],
    },
    {
        "chave": "acaiAdicionais",
        "rotulo": "Adicionais de açaí",
        "novoRotulo": "Novo adicional",
        "arquivo": "acai.json",
        "secao": "adicionais",
        "icone": "fa6s.cookie",
        "cor": "#8e44ad",
        "numerado": False,
        "campos": [
            {"chave": "nome", "rotulo": "Nome do adicional", "tipo": TEXTO, "obrigatorio": True, "curto": ""},
            {"chave": "valor", "rotulo": "Preço", "tipo": PRECO, "obrigatorio": True, "curto": ""},
        ],
    },
    {
        "chave": "outros",
        "rotulo": "Outros",
        "novoRotulo": "Novo item",
        "arquivo": "outros.json",
        "icone": "fa6s.box",
        "cor": "#9b59b6",
        "numerado": False,
        "campos": [
            {"chave": "nome", "rotulo": "Nome do item", "tipo": TEXTO, "obrigatorio": True, "curto": ""},
            {"chave": "valor", "rotulo": "Preço", "tipo": PRECO, "obrigatorio": True, "curto": ""},
        ],
    },
]

# Aceita o que o usuário provavelmente digita — "24,90", "24.90", "24",
# "R$ 24,9" — e normaliza tudo para o formato usado nos arquivos ("24,90"),
# que é o que as telas de pedido esperam em parseValor() (troca a vírgula por
# ponto antes do parseFloat). Não aceita separador de milhar: nenhum item de
# cardápio de pizzaria chega perto disso, e "1.234" seria ambíguo com
# "1.234 = 1,23" na leitura decimal.
_PRECO = re.compile(r"^(?:R\$\s*)?(\d{1,5})(?:[.,](\d{1,2}))?$")


def _raiz_projeto():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _caminho_arquivo(categoria):
    return os.path.join(_raiz_projeto(), "data", "cardapio", categoria["arquivo"])


# Versão (idEvento, ver services/rede/relogio.py) da última gravação
# conhecida de cada arquivo de categoria — necessário porque os arquivos de
# cardápio têm schema fixo (ver módulo, topo) e não sobra espaço pra
# embutir esse campo neles sem quebrar essa garantia. Sidecar fora dos
# arquivos de cardápio de verdade, mesmo padrão de pasta ".sync/" que
# services/rede/tombstones.py já usa dentro de pedidos/.
def _pasta_sincronizacao():
    return os.path.join(_raiz_projeto(), "data", "cardapio", ".sync")


def _caminho_versoes():
    return os.path.join(_pasta_sincronizacao(), "versoes.json")


def _carregar_versoes():
    caminho = _caminho_versoes()
    if not os.path.isfile(caminho):
        return {}
    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            dados = json.load(arquivo)
    except (OSError, json.JSONDecodeError) as erro:
        print(f"[cardapioService] Falha ao ler {caminho}: {erro} — assumindo vazio.")
        return {}
    return dados if isinstance(dados, dict) else {}


def _salvar_versoes(dados):
    caminho = _caminho_versoes()
    temporario = caminho + ".tmp"
    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
        with open(temporario, "w", encoding="utf-8") as arquivo:
            json.dump(dados, arquivo, indent=2, ensure_ascii=False)
        os.replace(temporario, caminho)
    except OSError as erro:
        print(f"[cardapioService] Falha ao gravar {caminho}: {erro}")
        try:
            os.remove(temporario)
        except OSError:
            pass


def _versao_arquivo(nome_arquivo):
    """idEvento da última gravação conhecida de `nome_arquivo` por este
    mecanismo, ou "" se nunca foi registrada (arquivo nunca alterado desde
    que este sidecar passou a existir)."""
    return _carregar_versoes().get(nome_arquivo, "")


def _definir_versao_arquivo(nome_arquivo, id_evento):
    dados = _carregar_versoes()
    dados[nome_arquivo] = id_evento
    _salvar_versoes(dados)


def _categoria(chave):
    for categoria in CATEGORIAS:
        if categoria["chave"] == chave:
            return categoria
    return None


def _categorias_por_arquivo(nome_arquivo):
    """Caminho inverso de _categoria: a partir de "pizzas.json" (nome que
    chega no evento "cardapio_alterado" de outra máquina, ver
    CardapioController._ao_receber_cardapio_remoto), acha as categorias —
    pra saber onde gravar e quais chaves repassar em cardapioAlterado.

    Devolve uma lista porque um arquivo pode conter mais de uma categoria
    (as duas seções de acai.json): quando ele chega da rede, a tela precisa
    recarregar as duas, não só a primeira encontrada."""
    return [categoria for categoria in CATEGORIAS if categoria["arquivo"] == nome_arquivo]


def _ler_caminho(item, caminho):
    """Valor de "valor.pao_frances" dentro do dict lido do JSON, tolerando um
    item que não tenha aquele nível (arquivo editado à mão, item antigo)."""
    atual = item
    for parte in caminho.split("."):
        if not isinstance(atual, dict):
            return ""
        atual = atual.get(parte)
    return atual if atual is not None else ""


def _gravar_caminho(destino, caminho, valor):
    partes = caminho.split(".")
    atual = destino
    for parte in partes[:-1]:
        atual = atual.setdefault(parte, {})
    atual[partes[-1]] = valor


def normalizar_preco(texto):
    """Devolve o preço no formato "24,90", ou None se não for um preço
    válido."""
    if isinstance(texto, (int, float)) and not isinstance(texto, bool):
        texto = f"{texto:.2f}".replace(".", ",")
    correspondencia = _PRECO.match(str(texto or "").strip())
    if not correspondencia:
        return None
    reais, centavos = correspondencia.group(1), correspondencia.group(2) or "0"
    return f"{int(reais)},{centavos.ljust(2, '0')}"


def _numerar_itens(categoria, itens):
    """Renumera o "id" de 1 a N na ordem do arquivo, nas categorias que têm
    esse campo. Hoje nada no app usa o id (as telas de pedido casam os itens
    pelo nome), mas ele existe nos dois arquivos e some se a gravação não o
    recolocar — renumerar por posição mantém os ids únicos e sem buracos
    depois de remoções."""
    if not categoria["numerado"]:
        return
    for indice, item in enumerate(itens, start=1):
        item["id"] = indice


def _ler_documento(categoria):
    """Lê o JSON inteiro do arquivo da categoria (não só a parte dela).

    Devolve (documento, ""), (None, "") se o arquivo ainda não existe, ou
    (None, mensagem) se existe mas não deu pra ler. Quem chama trata esses
    três casos de forma diferente: carregar() mostra lista vazia nos dois
    últimos, mas salvar() precisa distinguir "não existe" (pode criar) de
    "ilegível" (não pode reescrever por cima, senão apaga a outra seção)."""
    caminho = _caminho_arquivo(categoria)
    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            return json.load(arquivo), ""
    except FileNotFoundError:
        return None, ""
    except (OSError, json.JSONDecodeError) as erro:
        return None, f"Falha ao ler {caminho}: {erro}"


def carregar(chave_categoria):
    """Itens da categoria como dicts planos ({"valor.pao_baby": "14,00"}),
    prontos para o formulário da tela. Lista vazia se o arquivo não existir ou
    estiver ilegível — o app segue funcionando e a tela mostra o cardápio
    vazio, em vez de derrubar a página."""
    categoria = _categoria(chave_categoria)
    if categoria is None:
        return []

    caminho = _caminho_arquivo(categoria)
    documento, erro = _ler_documento(categoria)
    if erro:
        print(f"[cardapioService] {erro}")
        return []

    if documento is None:
        return []

    dados = documento
    secao = categoria.get("secao")
    if secao is not None:
        if not isinstance(documento, dict):
            print(f'[cardapioService] {caminho} não é um objeto com a seção "{secao}".')
            return []
        # Seção ausente é normal num arquivo ainda sem nenhum item daquele
        # grupo — a tela só mostra a lista vazia.
        dados = documento.get(secao) or []

    if not isinstance(dados, list):
        print(f"[cardapioService] {caminho} não contém uma lista de itens.")
        return []

    itens = []
    for item in dados:
        if not isinstance(item, dict):
            continue
        itens.append({campo["chave"]: str(_ler_caminho(item, campo["chave"])) for campo in categoria["campos"]})
    return itens


def _montar_conteudo_do_arquivo(categoria, itens_validados):
    """O que vai ser escrito no arquivo inteiro: a própria lista, quando a
    categoria ocupa o arquivo todo; ou o objeto de hoje com só a seção dela
    trocada, quando divide o arquivo com outra (acai.json).

    Devolve (conteudo, "") ou (None, mensagem). Se o arquivo existe mas está
    ilegível, recusa a gravação: reescrevê-lo com apenas esta seção apagaria
    silenciosamente a outra (os tamanhos sumiriam ao salvar os adicionais)."""
    secao = categoria.get("secao")
    if secao is None:
        return itens_validados, ""

    documento, erro = _ler_documento(categoria)
    if erro:
        return None, f"Não foi possível ler o cardápio atual para atualizá-lo: {erro}"

    if documento is None:
        documento = {}
    elif not isinstance(documento, dict):
        caminho = _caminho_arquivo(categoria)
        return None, f'O arquivo {os.path.basename(caminho)} não está no formato esperado (seção "{secao}").'

    documento[secao] = itens_validados
    return documento, ""


def salvar(chave_categoria, itens):
    """Reescreve o arquivo da categoria com `itens` (a lista inteira, na ordem
    em que deve ficar no arquivo). Devolve "" em caso de sucesso ou a mensagem
    de erro a mostrar na tela — o arquivo só é tocado se a lista inteira
    passar pela validação, para nunca deixar o cardápio meio gravado."""
    categoria = _categoria(chave_categoria)
    if categoria is None:
        return f"Categoria desconhecida: {chave_categoria}"

    if not isinstance(itens, list):
        return "Lista de itens inválida."

    saida = []
    for posicao, item in enumerate(itens, start=1):
        if not isinstance(item, dict):
            return f"Item {posicao} do cardápio está em formato inválido."

        novo = {}
        for campo in categoria["campos"]:
            valor = str(item.get(campo["chave"], "") or "").strip()

            if campo["tipo"] == PRECO:
                if not valor and not campo["obrigatorio"]:
                    continue
                preco = normalizar_preco(valor)
                if preco is None:
                    nome = item.get("nome") or f"item {posicao}"
                    return f'"{campo["rotulo"]}" de "{nome}" não é um preço válido: "{valor}".'
                valor = preco
            elif campo["obrigatorio"] and not valor:
                return f'"{campo["rotulo"]}" do item {posicao} não pode ficar em branco.'

            _gravar_caminho(novo, campo["chave"], valor)
        saida.append(novo)

    _numerar_itens(categoria, saida)

    caminho = _caminho_arquivo(categoria)
    conteudo, erro = _montar_conteudo_do_arquivo(categoria, saida)
    if erro:
        return erro

    # Grava num temporário e só então troca pelo arquivo real: se faltar
    # espaço/permissão no meio da escrita, o cardápio antigo continua
    # intacto em vez de virar um JSON truncado que nenhuma tela de pedido
    # consegue mais ler.
    temporario = caminho + ".tmp"
    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
        # newline="\n" força LF mesmo no Windows (Python em modo texto
        # normalmente escreve "\r\n" lá) — sem isso, todo cardápio salvo
        # pela tela numa máquina Windows diverge do arquivo commitado só
        # por causa da quebra de linha, deixando data/cardapio/*.json
        # "modificado localmente" pro git mesmo sem nenhuma edição de
        # verdade. Isso trava o autoupdate (ver Config/atualizador.py:
        # "git merge --ff-only" se recusa a mexer num arquivo com mudança
        # local, sempre que uma atualização também tocar nesse arquivo).
        with open(temporario, "w", encoding="utf-8", newline="\n") as arquivo:
            json.dump(conteudo, arquivo, indent=2, ensure_ascii=False)
            arquivo.write("\n")
        os.replace(temporario, caminho)
    except OSError as erro:
        print(f"[cardapioService] Falha ao gravar {caminho}: {erro}")
        try:
            os.remove(temporario)
        except OSError:
            pass
        return f"Não foi possível gravar o cardápio: {erro}"

    return ""


class CardapioController(QObject):
    """Ponte para a tela Cardápio (QML) ler/gravar os arquivos acima.

    Também mantém o cardápio sincronizado entre as máquinas da malha local:
    toda gravação bem-sucedida publica o arquivo inteiro no barramento de
    eventos por gossip (ver services/rede/eventos.py), e esta classe já
    nasce inscrita para receber o mesmo tipo de evento vindo de outra
    máquina e gravar localmente — sem que RedeService precise saber nada
    sobre cardápio."""

    cardapioAlterado = pyqtSignal(str)

    _TIPO_EVENTO_CARDAPIO = "cardapio_alterado"

    def __init__(self):
        super().__init__()
        rede.registrarEvento(self._TIPO_EVENTO_CARDAPIO, self._ao_receber_cardapio_remoto)
        rede.registrarDominioSincronizado(
            "cardapio",
            self._resumo_cardapio,
            self._obter_cardapio_reconciliacao,
            self._aplicar_cardapio_reconciliacao,
        )

    # ---------- Anti-entropy (ver services/rede/redeService.py:registrarDominioSincronizado) ----------
    # Sem "apagados": os arquivos de categoria nunca são removidos, só
    # reescritos — a exclusão de um item do cardápio já é implícita na
    # próxima gravação (a lista sai sem ele), não precisa de tombstone.
    #
    # A unidade sincronizada é o ARQUIVO, não a categoria: as duas seções de
    # acai.json viajam juntas, num hash/payload só.

    def _resumo_cardapio(self):
        itens = {}
        for categoria in CATEGORIAS:
            if categoria["arquivo"] in itens:
                continue
            versao = _versao_arquivo(categoria["arquivo"])
            if not versao:
                # Arquivo nunca alterado desde que este mecanismo passou a
                # existir — cai no hash de conteúdo (comportamento de
                # antes) só pra detectar divergência; não é usado como
                # critério de "mais recente" (ver _ao_receber_cardapio_remoto).
                caminho = _caminho_arquivo(categoria)
                try:
                    with open(caminho, "rb") as arquivo:
                        conteudo = arquivo.read()
                except OSError:
                    continue
                versao = hashlib.sha256(conteudo).hexdigest()[:16]
            itens[categoria["arquivo"]] = versao
        return {"itens": itens}

    def _obter_cardapio_reconciliacao(self, nome_arquivo):
        categorias = _categorias_por_arquivo(nome_arquivo)
        if not categorias:
            return None
        caminho = _caminho_arquivo(categorias[0])
        try:
            with open(caminho, "rb") as arquivo:
                conteudo = arquivo.read()
        except OSError:
            return None
        return {
            "conteudo_b64": base64.b64encode(conteudo).decode("ascii"),
            "idEvento": _versao_arquivo(nome_arquivo),
        }

    def _aplicar_cardapio_reconciliacao(self, nome_arquivo, payload):
        payload = payload or {}
        self._ao_receber_cardapio_remoto({
            "arquivo": nome_arquivo,
            "conteudo_b64": payload.get("conteudo_b64", ""),
            "idEvento": payload.get("idEvento", ""),
        })

    def _publicar_cardapio_alterado(self, categoria):
        caminho = _caminho_arquivo(categoria)
        try:
            with open(caminho, "rb") as arquivo:
                conteudo = arquivo.read()
        except OSError as erro:
            print(f"[cardapioService] Falha ao ler {caminho} para propagar à rede: {erro}")
            return

        id_evento = relogio.novo_id()
        _definir_versao_arquivo(categoria["arquivo"], id_evento)
        rede.publicarEvento(self._TIPO_EVENTO_CARDAPIO, {
            "arquivo": categoria["arquivo"],
            "conteudo_b64": base64.b64encode(conteudo).decode("ascii"),
            "idEvento": id_evento,
        })

    def _ao_receber_cardapio_remoto(self, payload):
        """Grava localmente um data/cardapio/*.json alterado em outra
        máquina — mesmo formato que _publicar_cardapio_alterado manda. Só
        sobrescreve se o idEvento recebido for mais novo que a versão
        local conhecida (ver services/rede/relogio.py) — sem essa
        checagem, duas máquinas editando o mesmo arquivo quase ao mesmo
        tempo convergiam pra quem "chegasse por último" (gossip ou
        reconciliação), podendo desfazer uma edição mais nova. Payload sem
        idEvento (de uma máquina ainda não atualizada com este mecanismo)
        continua sendo aceito sempre, pra não travar um rollout misto."""
        payload = payload or {}
        nome_arquivo = os.path.basename(payload.get("arquivo", ""))
        conteudo_b64 = payload.get("conteudo_b64", "")
        id_recebido = payload.get("idEvento", "")
        categorias = _categorias_por_arquivo(nome_arquivo) if nome_arquivo else []
        if not categorias or not conteudo_b64:
            return

        if id_recebido:
            relogio.observar(id_recebido)
            versao_local = _versao_arquivo(nome_arquivo)
            if versao_local and not relogio.mais_novo(id_recebido, versao_local):
                return

        try:
            conteudo = base64.b64decode(conteudo_b64)
        except ValueError:
            return

        caminho = _caminho_arquivo(categorias[0])
        # Mesmo cuidado de salvar(): grava num temporário e só então troca
        # pelo arquivo real, pra uma falha no meio da escrita nunca deixar
        # o cardápio recebido da rede pela metade.
        temporario = caminho + ".tmp"
        try:
            os.makedirs(os.path.dirname(caminho), exist_ok=True)
            with open(temporario, "wb") as arquivo:
                arquivo.write(conteudo)
            os.replace(temporario, caminho)
        except OSError as erro:
            print(f"[cardapioService] Falha ao gravar {caminho} (recebido da rede): {erro}")
            try:
                os.remove(temporario)
            except OSError:
                pass
            return

        if id_recebido:
            _definir_versao_arquivo(nome_arquivo, id_recebido)

        # Uma chave por categoria do arquivo: com acai.json, a tela precisa
        # recarregar tanto os tamanhos quanto os adicionais.
        for categoria in categorias:
            self.cardapioAlterado.emit(categoria["chave"])

    @pyqtSlot(result="QVariantList")
    @protegido([])
    def listarCategorias(self):
        return [
            {
                "chave": categoria["chave"],
                "rotulo": categoria["rotulo"],
                "novoRotulo": categoria["novoRotulo"],
                "icone": categoria["icone"],
                "cor": categoria["cor"],
                "campos": categoria["campos"],
            }
            for categoria in CATEGORIAS
        ]

    @pyqtSlot(str, result="QVariantList")
    @protegido([])
    def listarItens(self, chave_categoria):
        return carregar(chave_categoria)

    # ---------- Consulta rápida (Ctrl+S de qualquer tela) ----------
    # Mora neste controller, e não num novo, por dois motivos: é cardápio, e
    # cada controller a mais é mais um objeto construído no caminho de abertura
    # do app (ver main.py) numa máquina que já demora a abrir. O índice em si é
    # preguiçoso — nada é lido do disco até o primeiro Ctrl+S.
    #
    # Import local: services/buscaCardapio.py importa este módulo pra ler
    # CATEGORIAS, então trazê-lo no topo daqui fecharia um ciclo.

    @pyqtSlot(str, result="QVariantList")
    @protegido([])
    def buscar(self, termo):
        """Itens do cardápio que casam com `termo` — ver services/buscaCardapio.py."""
        from services import buscaCardapio

        return buscaCardapio.buscar(termo)

    @pyqtSlot()
    @protegido()
    def aquecerIndice(self):
        """Monta o índice do cardápio numa thread, para que ele já esteja
        pronto quando alguém precisar dele.

        Numa thread, e não aqui mesmo, porque quem chama é a subida do app: a
        montagem lê todos os arquivos do cardápio, e fazê-la na thread da
        interface só mudaria de lugar a espera que este aquecimento existe para
        remover. Nada aqui toca em QObject nem em QML — só monta uma lista em
        memória (ver services/buscaCardapio.aquecer, que serializa a montagem
        com a trava do módulo)."""
        import threading

        from services import buscaCardapio

        threading.Thread(target=buscaCardapio.aquecer, daemon=True).start()

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
    def analisarItemComanda(self, nome_impresso):
        """Categoria, sabores e tamanho de um item que já está na comanda —
        ver services/buscaCardapio.analisar_item_comanda. Usado pelo menu de
        botão direito da linha do pedido pra saber o que oferecer: borda e
        adicional numa pizza, só adicional num lanche ou açaí, nada numa
        bebida."""
        from services import buscaCardapio

        return buscaCardapio.analisar_item_comanda(nome_impresso)

    @pyqtSlot(str, str, result="QVariantList")
    @protegido([])
    def buscarNaCategoria(self, chave_categoria, termo):
        """Como buscar(), mas só dentro de uma categoria e sem teto de
        resultados — as mesmas faixas de relevância, o mesmo tratamento de
        acento e de várias palavras.

        É o que a etapa "outros sabores" do lançamento rápido usa pra filtrar
        as pizzas (ver qml/components/PopupLancamentoRapido.qml): ali a busca
        precisa ordenar por relevância como a barra do Ctrl+S, e não só
        peneirar em ordem alfabética como listarDaCategoria."""
        from services import buscaCardapio

        return buscaCardapio.buscar(termo, limite=None, chave_categoria=chave_categoria)

    @pyqtSlot(str, str, result="QVariantList")
    @protegido([])
    def listarDaCategoria(self, chave_categoria, termo):
        """Os itens de uma categoria só, no mesmo formato de buscar() — com a
        promoção do dia já aplicada. Usado pelo lançamento rápido quando o
        atendente escolheu primeiro um adicional/borda e ainda precisa dizer a
        qual pizza/lanche/açaí ele vai."""
        from services import buscaCardapio

        return buscaCardapio.listar_da_categoria(chave_categoria, termo)

    @pyqtSlot(result=int)
    @protegido(0)
    def totalItensCardapio(self):
        from services import buscaCardapio

        return buscaCardapio.total()

    @pyqtSlot(str, "QVariantList", result=str)
    @protegido("Falha inesperada ao salvar o cardápio — ver logs/app.log.")
    def salvarItens(self, chave_categoria, itens):
        """Devolve "" se gravou, ou a mensagem de erro para a tela mostrar na
        notificação (ver Cardapio.qml)."""
        erro = salvar(chave_categoria, itens)
        if not erro:
            self.cardapioAlterado.emit(chave_categoria)
            categoria = _categoria(chave_categoria)
            if categoria is not None:
                self._publicar_cardapio_alterado(categoria)
        return erro
