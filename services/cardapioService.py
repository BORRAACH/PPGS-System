"""Leitura e gravação do cardápio (data/cardapio/*.json) pela tela Cardápio
(qml/pages/cardapio/Cardapio.qml).

As telas de pedido (qml/pages/pedidos/) continuam lendo esses mesmos arquivos
direto por XMLHttpRequest — só a edição passa por aqui, porque o QML não
grava arquivo. Como cada tela de pedido é criada de novo a cada vez que entra
na pilha, ela relê o JSON do disco sozinha: alterações feitas aqui já valem no
próximo pedido, sem reiniciar o app.

Cada categoria descreve seus próprios campos (CATEGORIAS abaixo) porque os
quatro arquivos não têm o mesmo formato: pizza tem três preços por tamanho,
lanche tem três preços por tipo de pão (aninhados em "valor"), bebida e
"outros" têm um preço só. A tela monta o formulário a partir dessa descrição,
em vez de ter um formulário escrito à mão por categoria.

Atenção: só os campos descritos aqui sobrevivem a uma gravação — o arquivo é
reescrito a partir da lista de campos da categoria, então uma chave nova
adicionada à mão no JSON (sem entrar em CATEGORIAS) se perde no primeiro
salvamento feito pela tela.
"""

import json
import os
import re

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

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


def _categoria(chave):
    for categoria in CATEGORIAS:
        if categoria["chave"] == chave:
            return categoria
    return None


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


def carregar(chave_categoria):
    """Itens da categoria como dicts planos ({"valor.pao_baby": "14,00"}),
    prontos para o formulário da tela. Lista vazia se o arquivo não existir ou
    estiver ilegível — o app segue funcionando e a tela mostra o cardápio
    vazio, em vez de derrubar a página."""
    categoria = _categoria(chave_categoria)
    if categoria is None:
        return []

    caminho = _caminho_arquivo(categoria)
    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            dados = json.load(arquivo)
    except FileNotFoundError:
        return []
    except (OSError, json.JSONDecodeError) as erro:
        print(f"[cardapioService] Falha ao ler {caminho}: {erro}")
        return []

    if not isinstance(dados, list):
        print(f"[cardapioService] {caminho} não contém uma lista de itens.")
        return []

    itens = []
    for item in dados:
        if not isinstance(item, dict):
            continue
        itens.append({campo["chave"]: str(_ler_caminho(item, campo["chave"])) for campo in categoria["campos"]})
    return itens


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
    # Grava num temporário e só então troca pelo arquivo real: se faltar
    # espaço/permissão no meio da escrita, o cardápio antigo continua
    # intacto em vez de virar um JSON truncado que nenhuma tela de pedido
    # consegue mais ler.
    temporario = caminho + ".tmp"
    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
        with open(temporario, "w", encoding="utf-8") as arquivo:
            json.dump(saida, arquivo, indent=2, ensure_ascii=False)
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
    """Ponte para a tela Cardápio (QML) ler/gravar os arquivos acima."""

    cardapioAlterado = pyqtSignal(str)

    @pyqtSlot(result="QVariantList")
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
    def listarItens(self, chave_categoria):
        return carregar(chave_categoria)

    @pyqtSlot(str, "QVariantList", result=str)
    def salvarItens(self, chave_categoria, itens):
        """Devolve "" se gravou, ou a mensagem de erro para a tela mostrar na
        notificação (ver Cardapio.qml)."""
        erro = salvar(chave_categoria, itens)
        if not erro:
            self.cardapioAlterado.emit(chave_categoria)
        return erro
