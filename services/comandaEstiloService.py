"""Configurações de estilo ESC/POS (negrito, sublinhado, fundo preto/modo
reverso, tamanho da fonte em pixels) aplicadas a campos específicos do texto
da comanda, e espaçamento entre seções/antes do corte — tudo editável pela
tela Configurações (qml/pages/configuracoes/impressora/EstiloImpressora.qml)
e usado por balcaoController.py/entregaController.py (montagem do texto) e
printerService.py (espaçamento antes do corte automático).

Persistido em Config/estilo_impressao.json — fora do git (é preferência de
cada máquina/impressora, não código-fonte), igual a Config/.versao (ver
Config/atualizador.py).
"""

import json
import math
import os

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

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

# Campos da comanda que podem ter estilo configurado. Alguns só são usados
# por um dos dois tipos de pedido (ex: "taxa_entrega", "endereco" só saem em
# pedidos de Entrega) — ficam na mesma lista/tela mesmo assim; não fazem
# diferença nenhuma pro outro tipo, que nunca chama formatar_campo com esse
# nome.
CAMPOS = [
    "cliente",
    "telefone",
    "endereco",
    "bairro",
    "data",
    "pedido",
    "observacao_item",
    "observacao_entrega",
    "forma_pagamento",
    "troco_para",
    "status",
    "taxa_entrega",
    "valor_total",
    "troco_a_dar",
]
ATRIBUTOS_BOOLEANOS = ["negrito", "sublinhado", "fundo_preto"]

RODULOS_CAMPOS = {
    "cliente": "Nome do cliente",
    "telefone": "Telefone",
    "endereco": "Endereço (com número)",
    "bairro": "Bairro",
    "data": "Data/hora do pedido",
    "pedido": "Nome do pedido",
    # Distintos de propósito: "observacao_item" é a observação de cada
    # sabor/item (ex: "sem cebola", digitada na tela de seleção de pizza);
    # "observacao_entrega" é a observação geral do pedido, que só existe na
    # tela de Entrega, perto dos dados de endereço.
    "observacao_item": "Observação do item (sabor)",
    "observacao_entrega": "Observação geral (perto do endereço)",
    "forma_pagamento": "Forma de pagamento",
    "troco_para": "Troco para",
    "status": "Status (pago/não pago)",
    "taxa_entrega": "Taxa de entrega",
    "valor_total": "Valor do pedido",
    "troco_a_dar": "Troco a dar",
}

RODULOS_ATRIBUTOS = {
    "negrito": "Negrito",
    "sublinhado": "Sublinhado",
    "fundo_preto": "Fundo preto",
}


def _atributos_campo_padrao():
    atributos = {atributo: False for atributo in ATRIBUTOS_BOOLEANOS}
    atributos["tamanho_fonte"] = TAMANHO_FONTE_BASE_PX
    return atributos


def _padrao():
    config = {
        "campos": {campo: _atributos_campo_padrao() for campo in CAMPOS},
        "espacamento_secoes": 1,
        "espacamento_corte": 4,
    }
    # Preserva o comportamento original do app (nome do item/observação já
    # saíam em negrito antes de existir essa tela de configuração).
    config["campos"]["pedido"]["negrito"] = True
    config["campos"]["observacao_item"]["negrito"] = True
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
            destino[campo]["tamanho_fonte"] = max(1, int(atributos["tamanho_fonte"]))


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

    if isinstance(dados.get("espacamento_secoes"), int):
        config["espacamento_secoes"] = max(0, dados["espacamento_secoes"])
    if isinstance(dados.get("espacamento_corte"), int):
        config["espacamento_corte"] = max(0, dados["espacamento_corte"])

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


def linhas_espacamento_corte():
    """Quantas linhas em branco entram antes do comando de corte automático
    (ver printerService.py) — margem pra o papel avançar de verdade além da
    lâmina antes de cortar."""
    return _config["espacamento_corte"]


class ComandaEstiloController(QObject):
    """Ponte pra tela de Configurações (QML) ler/gravar o estilo acima."""

    configuracaoAlterada = pyqtSignal()

    @pyqtSlot(result="QVariantMap")
    def obterConfiguracao(self):
        return _config

    @pyqtSlot(result="QVariantList")
    def listarCampos(self):
        return [{"chave": campo, "rotulo": RODULOS_CAMPOS[campo]} for campo in CAMPOS]

    @pyqtSlot(result="QVariantList")
    def listarAtributos(self):
        return [{"chave": atributo, "rotulo": RODULOS_ATRIBUTOS[atributo]} for atributo in ATRIBUTOS_BOOLEANOS]

    @pyqtSlot(result=int)
    def tamanhoFontePadrao(self):
        return TAMANHO_FONTE_BASE_PX

    @pyqtSlot("QVariantMap")
    def salvarConfiguracaoCompleta(self, config):
        """Grava de uma vez a configuração inteira vinda da tela (chamado ao
        sair da tela de Configurações, não a cada clique/edição) — gravar em
        disco a cada mudança deixava os controles com uma sensação de
        atraso, porque a chamada síncrona pro Python bloqueia o próximo
        frame de renderização até terminar."""
        global _config
        novo = _padrao()
        _mesclar_campos(novo["campos"], config.get("campos"))

        if isinstance(config.get("espacamento_secoes"), int):
            novo["espacamento_secoes"] = max(0, config["espacamento_secoes"])
        if isinstance(config.get("espacamento_corte"), int):
            novo["espacamento_corte"] = max(0, config["espacamento_corte"])

        _config = novo
        _salvar()
        self.configuracaoAlterada.emit()

    @pyqtSlot()
    def restaurarPadroes(self):
        global _config
        _config = _padrao()
        _salvar()
        self.configuracaoAlterada.emit()
