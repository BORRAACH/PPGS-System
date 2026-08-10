"""Registra as fontes embarcadas do app e define a Figtree como fonte padrão.

Por quê no Python, e não num FontLoader do QML como a Caprasimo: as duas
fontes têm papéis diferentes.

A Caprasimo é aplicada PONTUALMENTE — uns quinze títulos que escrevem
`font.family: Estilo.global.fontFamily.title`. Um FontLoader dentro do
Estilo.qml resolve isso sozinho.

A Figtree é o texto de TODO o resto: cada Text, Label, TextField, item de
lista e rótulo do sistema. Em Qt Quick a fonte não é herdada de um Item pai
para os filhos (só dentro de um Control), então não existe "aplicar no
main.qml e pronto" — ou se escrevia `font.family` em algumas centenas de
lugares, ou se troca a fonte padrão da QApplication, que é de onde todo
Text sem `font.family` explícito tira a dele. É o que este módulo faz.

Efeito colateral bem-vindo: com a padrão trocada, o token
`Estilo.global.fontFamily.body` pode continuar sendo a string vazia — que
no Qt significa "a fonte padrão" e agora resolve para Figtree. Se o
registro aqui falhar, o vazio volta a significar a fonte do sistema e
nenhum texto some.

As fontes são arquivos dentro do repositório, não fontes instaladas na
máquina: o app roda em computadores que ninguém administra, e uma fonte
"que precisa ser instalada antes" acaba não existindo em metade deles.
Como o .exe não empacota o código (ver launcher/gerar_exe.bat), elas
viajam junto pela auto-atualização por git, como qualquer outro arquivo.
"""

from pathlib import Path

from PyQt6.QtGui import QFontDatabase

_PASTA = Path(__file__).resolve().parent.parent / "qml" / "estilo" / "fontes"

# A Figtree upstream é uma fonte variável (um arquivo só, eixo wght de 300 a
# 900). O Qt 6.11 até a carrega, mas registra apenas a instância padrão dela
# — testado: os pesos Light a Black saíam todos com a mesma largura, e
# `font.bold` não engordava nada. Por isso o repositório guarda quatro
# instâncias estáticas, geradas com fontTools a partir da variável, cada uma
# com o nome de família "Figtree" e o subfamily correto, que é o que faz o
# Qt juntá-las numa família só com quatro pesos selecionáveis.
# A Caprasimo não entra nesta lista de propósito: quem a carrega é o
# FontLoader do Estilo.qml, e registrar o mesmo arquivo duas vezes só
# duplicaria a família na QFontDatabase.
_ARQUIVOS = (
    "Figtree-Regular.woff2",   # 400 — corpo de texto
    "Figtree-Medium.woff2",    # 500 — rótulos, ênfase leve
    "Figtree-SemiBold.woff2",  # 600 — títulos de seção, valores
    "Figtree-Bold.woff2",      # 700 — totais e destaques (font.bold cai aqui)
)

_FAMILIA_CORPO = "Figtree"


def aplicar(app) -> None:
    """Carrega os arquivos de fonte e troca a fonte padrão da aplicação.

    Melhor esforço: qualquer arquivo que falhe vira um aviso no log e o app
    segue com a fonte do sistema, que é exatamente o comportamento que havia
    antes de existirem fontes embarcadas.

    Precisa ser chamado com a QApplication já criada e antes do
    `engine.load()` — depois disso os textos já foram medidos com a fonte
    antiga.
    """
    carregadas = []
    for nome in _ARQUIVOS:
        caminho = _PASTA / nome
        if not caminho.exists():
            print(f"[fontes] Arquivo não encontrado, ignorando: {caminho}")
            continue
        # -1 = o Qt não entendeu o arquivo (woff2 corrompido, build do Qt sem
        # suporte a woff2...). Não é motivo para impedir o app de abrir.
        if QFontDatabase.addApplicationFont(str(caminho)) == -1:
            print(f"[fontes] O Qt não conseguiu carregar: {nome}")
            continue
        carregadas.append(nome)

    if _FAMILIA_CORPO not in QFontDatabase.families():
        print(
            f"[fontes] '{_FAMILIA_CORPO}' não ficou disponível — o app segue "
            "com a fonte padrão do sistema."
        )
        return

    # Troca só a família: o tamanho, o peso e o DPI da fonte padrão vêm do
    # sistema e continuam valendo. Um QFont("Figtree") zerado no lugar disto
    # levaria junto o tamanho padrão do Qt, mudando de tabela todo texto que
    # não declara font.pixelSize.
    fonte = app.font()
    fonte.setFamily(_FAMILIA_CORPO)
    app.setFont(fonte)

    print(f"[fontes] {len(carregadas)} arquivo(s) carregado(s); corpo em {_FAMILIA_CORPO}.")
