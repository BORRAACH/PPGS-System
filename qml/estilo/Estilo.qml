// ===== CAMADA 2 e 3: TOKENS SEMÂNTICOS =====
// Configurações de estilo compartilhadas por todas as páginas/componentes do
// app. Import: "import estilo 1.0" (o diretório qml/ já está no import path,
// configurado em main.py).
// Os tokens dizem o que a cor SIGNIFICA, nunca qual cor ela é. "action.confirm",
// não "green". A paleta bruta mora em Colors.qml e só este arquivo a importa.
// GRAMÁTICA DOS NOMES — escopo, papel, modificador, nessa ordem:
//     Estilo . global    . surfaceHover
//             ^escopo      ^papel ^modificador de estado
//   escopo      global (transversal) · action · status · finance · screen ·
//               orderType · category · printer
//   papel       background, surface, border, text, radius, spacing...
//   modificador Hover, Pressed, Disabled, Secondary, OnAccent, Strong

import "."
import QtQuick
pragma Singleton

// Escalas dimensionais usam t-shirt sizes (xs < sm < md < lg < xl), que ordenam
// sozinhas — ao contrário de adjetivos, onde "menor" acabava sendo maior que
// "pequeno".
QtObject {
    // =========================================================================
    // TIPOS REUTILIZÁVEIS DE ESTADO
    // Existem para que seja impossível declarar um controle interativo pela
    // metade. Antes, cada botão repetia à mão um ternário down/hover/normal, e
    // em seis popups o "down" acabou igual ao "normal" — clicar não dava
    // retorno visual nenhum. Com um tipo, os estados vêm sempre juntos.
    // =========================================================================
    // =========================================================================
    // SCREEN — identidade visual de cada tela
    // =========================================================================
    // ORDERTYPE — modalidade da comanda: Balcão, Entrega e Mesa/Salão
    // Havia três esquemas divergentes para isso no app (Consulta, Fechamento e
    // o popup de fechamento rápido pintavam a mesma modalidade de cores
    // diferentes). Este grupo é o esquema único.
    // =========================================================================
    // CATEGORY — categorias do cardápio

    id: root

    // ===== Tokens globais: valem em qualquer tela =====
    readonly property GlobalTokens
    global: GlobalTokens {
    }

    // ===== Tokens de contexto =====
    readonly property ActionTokens
    // intenção do botão
    action: ActionTokens {
    }

    readonly property StatusTokens
    status: StatusTokens {
    }
    // dinheiro

    readonly property FinanceTokens
    finance: FinanceTokens {
    }
    // identidade por tela

    readonly property ScreenTokens
    screen: ScreenTokens {
    }
    // modalidade da comanda

    readonly property OrderTypeTokens
    orderType: OrderTypeTokens {
    }
    // categorias do cardápio

    readonly property CategoryTokens
    category: CategoryTokens {
    }
    // tipos de pão dos lanches

    readonly property BreadTokens
    bread: BreadTokens {
    }
    // desenhos

    readonly property IllustrationTokens
    illustration: IllustrationTokens {
    }
    // impressora térmica

    readonly property PrinterTokens
    printer: PrinterTokens {
    }

    // Botão ou controle clicável.
    component ButtonTone: QtObject {
        property color base // repouso
        property color hover // mouse por cima
        property color pressed // sendo clicado (down)
        property color border: pressed // contorno, quando o botão tem um
        property color content: Colors.white // texto e ícone por cima
    }

    // Faixa, card ou badge que comunica um estado (sem interação).
    component Tone: QtObject {
        property color background
        property color border
        property color content
    }

    // =========================================================================
    // GLOBAL — superfícies, bordas, texto e escalas dimensionais
    // =========================================================================
    component GlobalTokens: QtObject {
        // anel de foco por teclado

        // ===== Superfícies =====
        readonly property color background: Colors.areia100
        // fundo das páginas e dos popups
        readonly property color surface: Colors.creme50
        // cards, painéis, itens de lista
        readonly property color surfaceHover: Colors.areia200
        // item/linha/aba sob o mouse
        readonly property color surfacePressed: Colors.areia300
        // item/botão neutro sendo clicado
        readonly property color inputBackground: Colors.ouro50
        // TextField/ComboBox/SpinBox
        readonly property color inputDisabled: Colors.areia200
        // input desabilitado
        readonly property color surfaceDisabled: Colors.taupe500
        // fundo de botão desabilitado
        readonly property color overlay: Colors.overlay
        // scrim escuro atrás de um modal
        readonly property color shadow: Colors.shadow
        // sombra projetada de cartão
        // Moldura da janela e barra lateral: o mesmo tom em volta de tudo.
        readonly property color chrome: Qt.darker(background, 1.8)
        // ===== Bordas =====
        readonly property color border: Colors.taupe400
        // input em repouso
        readonly property color borderStrong: Colors.taupe500
        // ênfase, checkbox desmarcado
        readonly property color borderCard: Colors.areia300
        // card, painel, popup
        readonly property color divider: Colors.areia300
        // régua horizontal de 1px
        readonly property color focusRing: Colors.carvao800
        // ===== Texto =====
        readonly property color text: Colors.carvao800
        readonly property color textSecondary: Colors.umbre700
        readonly property color textDisabled: Colors.taupe500
        readonly property color textMuted: Colors.umbre600 // estado vazio, texto itálico
        readonly property color textOnAccent: Colors.white // sobre botão/badge colorido
        // Texto DIGITADO dentro de inputs (TextField/TextArea/SpinBox/
        // ComboBox). Preto fixo, e sempre declarado explicitamente em cada
        // input: sem "color:", o Qt usa palette.text, que no Windows vem do
        // tema do sistema — em máquinas com tema escuro o texto saía branco
        // sobre o fundo branco do input, ficando invisível enquanto o
        // atendente digitava o pedido. Como o fundo dos inputs é sempre
        // branco (inputBackground, fixo no background de cada um), a cor do
        // texto também precisa ser fixa, não herdada.
        readonly property color textInput: Colors.carvao900
        // Mesma história para o texto de dica (placeholderText), que vem de
        // palette.placeholderText.
        readonly property color textPlaceholder: Colors.umbre600
        // ===== Escalas dimensionais =====
        readonly property RadiusScale
        radius: RadiusScale {
        }

        readonly property SpacingScale
        spacing: SpacingScale {
        }

        readonly property PaddingScale
        padding: PaddingScale {
        }

        readonly property FontSizeScale
        fontSize: FontSizeScale {
        }

        readonly property FontFamilyScale
        fontFamily: FontFamilyScale {
        }

        readonly property FontWeightScale
        fontWeight: FontWeightScale {
        }

        readonly property LineHeightScale
        lineHeight: LineHeightScale {
        }

        readonly property LetterSpacingScale
        letterSpacing: LetterSpacingScale {
        }

        readonly property BorderWidthScale
        borderWidth: BorderWidthScale {
        }

        readonly property OpacityScale
        opacity: OpacityScale {
        }

        readonly property MotionScale
        motion: MotionScale {
        }

        readonly property ElevationScale
        elevation: ElevationScale {
        }

    }

    // ===== Raios de canto =====
    // As quatro escalas abaixo saem do tamanho da janela (ver
    // qml/estilo/Responsivo.qml): num monitor de 1280x800 o fator é 1 e todos
    // os valores são exatamente os de sempre; em tela menor eles encolhem
    // juntos, cada um com o piso que o seu papel aguenta. Math.round porque
    // os campos são int — sem ele, "11 * 0.93" truncaria para 10, perdendo
    // quase um pixel inteiro em cada passo da escala.
    component RadiusScale: QtObject {
        readonly property real scale: Responsivo.escalaRaio
        readonly property int xs: Math.round(4 * scale) // checkbox, barra de acento, papel da prévia
        readonly property int sm: Math.round(5 * scale) // inputs e botões de ação
        readonly property int md: Math.round(8 * scale) // cards, itens de lista, botões grandes
        readonly property int lg: Math.round(12 * scale) // painéis e notificações
        readonly property int xl: Math.round(20 * scale) // popups
        readonly property int pill: 1000 // cápsulas — o Qt limita à metade do menor lado
    }

    // ===== Espaçamento entre elementos (spacing) =====
    component SpacingScale: QtObject {
        readonly property real scale: Responsivo.escalaEspaco
        readonly property int xs: Math.round(6 * scale) // gap apertado ícone/texto em botão
        readonly property int sm: Math.round(8 * scale) // gap ícone/texto em linha
        readonly property int md: Math.round(10 * scale) // campos de uma mesma linha
        readonly property int lg: Math.round(12 * scale) // botões de rodapé
        readonly property int xl: Math.round(15 * scale) // blocos de layout
        readonly property int xxl: Math.round(20 * scale) // seções da página
    }

    // ===== Preenchimento interno / margens (padding) =====
    component PaddingScale: QtObject {
        readonly property real scale: Responsivo.escalaEspaco
        readonly property int xs: Math.round(5 * scale)
        readonly property int sm: Math.round(7 * scale)
        readonly property int md: Math.round(10 * scale) // botões de ação e inputs
        readonly property int lg: Math.round(12 * scale)
        readonly property int xl: Math.round(15 * scale)
        readonly property int popup: Math.round(25 * scale) // margem interna de todo Popup
    }

    // ===== Tamanhos de fonte =====
    component FontSizeScale: QtObject {
        readonly property real scale: Responsivo.escalaTexto
        readonly property int xs: Math.round(11 * scale) // metadados, legendas, "há 5 min"
        readonly property int sm: Math.round(12 * scale) // rótulos em maiúsculas, chips
        readonly property int md: Math.round(13 * scale) // corpo de lista, linhas de resumo
        readonly property int lg: Math.round(14 * scale) // texto padrão de inputs e listas
        readonly property int xl: Math.round(16 * scale) // subtítulo de seção, título de popup
        readonly property int xxl: Math.round(20 * scale) // valores em destaque
        readonly property int title: Math.round(22 * scale) // título principal de cada página
        readonly property int display: Math.round(32 * scale) // números grandes de fechamento
    }

    // ===== Famílias tipográficas =====
    // O par vem inteiro da paleta (ver design/Paleta Forno.html,
    // "--font-heading" e "--font-body"): Caprasimo nos títulos, Figtree no
    // corpo. Os dois arquivos vêm embarcados em qml/estilo/fontes/ e não
    // instalados no sistema: o app roda em máquinas que ninguém administra, e
    // uma fonte "que precisa ser instalada antes" acaba não existindo em
    // metade delas.
    //
    // A divisão de trabalho entre as duas é o motivo de elas serem carregadas
    // de formas diferentes. Caprasimo é display: um só peso (400), desenhada
    // para chamar atenção em tamanho grande, e usada de propósito só em
    // título de página — num rótulo de campo ou numa linha de lista ela
    // atrapalharia a leitura. Por ser pontual, um FontLoader daqui basta.
    // Figtree é o texto de todo o resto, e em Qt Quick a fonte não se herda de
    // um Item pai para os filhos; quem a aplica é Config/fontes.py, trocando a
    // fonte padrão da QApplication.
    component FontFamilyScale: QtObject {
        // Enquanto o arquivo carrega (e se por algum motivo ele falhar),
        // font.family devolve string vazia — que no Qt significa "a fonte
        // padrão", exatamente o comportamento anterior. Nenhum título fica
        // sem texto por causa disto.
        readonly property FontLoader carregadorTitulo: FontLoader {
            source: Qt.resolvedUrl("fontes/Caprasimo-Regular.woff2")
        }

        readonly property string title: carregadorTitulo.font.family
        // Vazio = fonte padrão da aplicação, que Config/fontes.py já trocou
        // para Figtree. Continua vazio em vez de "Figtree" cravado justamente
        // para o caso de aquele registro falhar: aí isto volta a significar a
        // fonte do sistema, em vez de apontar para uma família inexistente e
        // deixar o Qt escolher uma substituta qualquer.
        readonly property string body: ""
    }

    // ===== Pesos =====
    // Só existem os quatro pesos que a Figtree embarca (ver Config/fontes.py);
    // pedir Font.Black aqui devolveria o Bold mesmo, então não há token para
    // ele. A Caprasimo tem só o 400 e ignora este eixo — título não muda de
    // peso, muda de família.
    //
    // Enquanto a migração dos ~300 `font.bold: true` espalhados pelo app não
    // acontece, eles seguem funcionando: `bold` é o 700, o mesmo que `strong`.
    component FontWeightScale: QtObject {
        readonly property int regular: Font.Normal // 400 — corpo, listas, inputs
        readonly property int medium: Font.Medium // 500 — rótulo de campo, aba ativa
        readonly property int semibold: Font.DemiBold // 600 — título de seção, cabeçalho de coluna
        readonly property int strong: Font.Bold // 700 — total, valor em destaque
    }

    // ===== Entrelinha =====
    // Multiplicador do tamanho da fonte; em QML só vale junto com
    // `lineHeightMode: Text.ProportionalHeight`, que é o padrão do Text.
    // Texto de uma linha só (a maioria dos rótulos) não precisa de nenhum
    // destes — o padrão do Qt já serve. Isto é para o que quebra em duas ou
    // mais linhas, onde a entrelinha padrão fica apertada demais para ler de
    // relance atrás do balcão.
    component LineHeightScale: QtObject {
        readonly property real tight: 1.1 // display e título em Caprasimo
        readonly property real snug: 1.25 // título de seção, nome de item em duas linhas
        readonly property real normal: 1.45 // observação da comanda, endereço
        readonly property real relaxed: 1.6 // texto de ajuda, estado vazio
    }

    // ===== Espaçamento entre letras =====
    // Em pixels, e por isso acompanham a escala de texto do Responsivo — um
    // tracking fixo em px vira tracking grande demais quando a fonte encolhe.
    // Regra de ouro: quanto maior a fonte, menos tracking ela quer; texto em
    // CAIXA ALTA quer mais que o mesmo texto em caixa baixa.
    component LetterSpacingScale: QtObject {
        readonly property real scale: Responsivo.escalaTexto
        readonly property real tight: -0.3 * scale // fontSize.display/title
        readonly property real normal: 0 // corpo — o desenho da fonte já resolve
        readonly property real wide: 0.4 * scale // rótulo em maiúsculas (fontSize.sm)
        readonly property real wider: 0.8 * scale // chip e badge em maiúsculas (fontSize.xs)
    }

    // ===== Espessura de borda =====
    component BorderWidthScale: QtObject {
        readonly property int hairline: 1 // borda padrão de card/input/botão
        readonly property int thick: 2 // ênfase e input em foco
        readonly property int focus: 3 // anel de foco por teclado
    }

    // ===== Opacidade de estado =====
    component OpacityScale: QtObject {
        readonly property real muted: 0.35 // conteúdo que não se aplica ao contexto
        readonly property real disabled: 0.4 // controle desabilitado
        readonly property real subtle: 0.6 // botão ainda inativo, mas quase pronto
    }

    // ===== Durações de animação (ms) =====
    component MotionScale: QtObject {
        readonly property int instant: 100 // realce de hover e clique
        readonly property int fast: 150 // fade-out, reordenação
        readonly property int normal: 250 // entrada de notificação
        readonly property int slow: 300 // slide do toast
    }

    // Um nível de elevação: blur/deslocamento de MultiEffect (a cor vem
    // sempre de Estilo.global.shadow, à parte).
    component NivelElevacao: QtObject {
        property real blur
        property real deslocamento
    }

    // ===== Elevação (sombra projetada) =====
    // Três níveis sobre Estilo.global.shadow — trocar de nível nunca troca a
    // cor, só o alcance. Antes de existir, cada tela que precisava de sombra
    // (Inicio.qml) repetia esses números soltos em cada botão.
    component ElevationScale: QtObject {
        readonly property NivelElevacao sm: NivelElevacao {
            blur: 0.4
            deslocamento: 1
        }
        readonly property NivelElevacao md: NivelElevacao {
            blur: 0.6
            deslocamento: 2
        }
        readonly property NivelElevacao lg: NivelElevacao {
            blur: 0.8
            deslocamento: 4
        }
    }

    // =========================================================================
    // ACTION — a INTENÇÃO do botão, não a cor dele
    // =========================================================================
    component ActionTokens: QtObject {
        // Confirmar, salvar e imprimir.
        readonly property ButtonTone
        confirm: ButtonTone {
            base: Colors.oliva500
            hover: Colors.oliva400
            pressed: Colors.oliva600
        }
        // Apagar, remover, restaurar padrões — ação destrutiva.

        readonly property ButtonTone
        danger: ButtonTone {
            base: Colors.brasa300
            hover: Colors.brasa200
            pressed: Colors.brasa600
        }
        // Voltar ao menu. Mesma base do danger, tons um pouco mais escuros.

        readonly property ButtonTone
        back: ButtonTone {
            base: Colors.brasa300
            hover: Colors.brasa400
            pressed: Colors.brasa500
        }
        // Lançar / salvar sem imprimir.

        readonly property ButtonTone
        save: ButtonTone {
            base: Colors.indigo500
            hover: Colors.indigo300
            pressed: Colors.indigo700
        }
        // Conferir, revisar, editar uma comanda já lançada.

        readonly property ButtonTone
        review: ButtonTone {
            base: Colors.uva500
            hover: Colors.uva300
            pressed: Colors.uva700
        }
        // Registrar dinheiro saindo do caixa (diárias, extras).

        readonly property ButtonTone
        outflow: ButtonTone {
            base: Colors.ouro600
            hover: Colors.ouro500
            pressed: Colors.ouro700
        }
        // Cancelar e sair — cinza, sem carga de intenção.

        readonly property ButtonTone
        neutral: ButtonTone {
            base: Colors.umbre700
            hover: Colors.umbre600
            pressed: Colors.carvao800
        }
        // Botão-ícone sem fundo em repouso (setas, engrenagem, lápis).

        readonly property ButtonTone
        ghost: ButtonTone {
            base: "transparent"
            hover: Colors.areia200
            pressed: Colors.areia300
            border: "transparent"
            content: Colors.umbre700
        }

    }

    // =========================================================================
    // STATUS — faixas e cards que comunicam uma situação
    // =========================================================================
    component StatusTokens: QtObject {
        // Conflito de sincronização na Consulta: as máquinas da rede discordam
        // sobre uma comanda e alguém precisa decidir. Amarelo de propósito, e
        // não vermelho: nada foi perdido nem deu erro — só está esperando uma
        // escolha.
        readonly property Tone
        warning: Tone {
            background: Colors.ouro100
            border: Colors.ouro300
            content: Colors.ouro700
        }
        // Pendência de caixa: diárias a descontar, comandas ainda em aberto.

        readonly property Tone
        pending: Tone {
            background: Colors.ouro50
            border: Colors.ouro200
            content: Colors.ouro600
        }

        readonly property Tone
        success: Tone {
            background: Colors.pinho50
            border: Colors.pinho100
            content: Colors.pinho400
        }

        readonly property Tone
        error: Tone {
            background: Colors.brasa50
            border: Colors.brasa100
            content: Colors.brasa300
        }

        readonly property Tone
        info: Tone {
            background: Colors.indigo50
            border: Colors.indigo100
            content: Colors.indigo500
        }

    }

    // =========================================================================
    // FINANCE — dinheiro. Separado de "action" de propósito: o verde de um
    // botão Confirmar e o verde de um lucro positivo mudam por motivos
    // diferentes, e antes eram o mesmo token.
    // =========================================================================
    component FinanceTokens: QtObject {
        readonly property color positive: Colors.pinho400 // receita, total, preço, lucro
        readonly property color negative: Colors.brasa300 // prejuízo, troco insuficiente
        readonly property color outflow: Colors.ouro600 // dinheiro saindo do caixa
    }

    // "accent" pinta título, ícone de cabeçalho e borda de input em foco.
    // base/hover/pressed pintam o botão primário daquela tela.
    // "soft"/"softStrong" são o mesmo acento diluído, para fundo de item sob o
    // mouse e de item já selecionado.
    // =========================================================================
    component ScreenTone: QtObject {
        property color accent
        property color base: accent
        property color hover
        property color pressed
        property color soft // fundo de item sob o mouse
        property color softStrong: soft // fundo de item selecionado
        readonly property color content: Colors.white
    }

    component ScreenTokens: QtObject {
        readonly property ScreenTone
        balcao: ScreenTone {
            accent: Colors.oliva500
            hover: Colors.oliva400
            pressed: Colors.oliva600
        }

        readonly property ScreenTone
        entrega: ScreenTone {
            accent: Colors.terracota400
            hover: Colors.terracota300
            pressed: Colors.terracota600
        }

        readonly property ScreenTone
        salao: ScreenTone {
            accent: Colors.agua500
            hover: Colors.agua300
            pressed: Colors.agua700
            soft: Colors.agua50
            softStrong: Colors.agua100
        }

        readonly property ScreenTone
        consulta: ScreenTone {
            accent: Colors.uva500
            hover: Colors.uva300
            pressed: Colors.uva700
            soft: Colors.uva50
        }
        // Fechamento de caixa. O accent é o verde-caixa do título e dos totais;

        // os botões da tela (navegação de data, salvar contagem) são teal.
        readonly property ScreenTone
        caixa: ScreenTone {
            accent: Colors.pinho400
            base: Colors.agua500
            hover: Colors.agua300
            pressed: Colors.agua700
        }

        readonly property ScreenTone
        rede: ScreenTone {
            accent: Colors.indigo300
            base: Colors.indigo500
            hover: Colors.indigo300
            pressed: Colors.indigo700
            soft: Colors.indigo50
        }

        readonly property ScreenTone
        config: ScreenTone {
            accent: Colors.umbre700
            hover: Colors.umbre600
            pressed: Colors.carvao800
            soft: Colors.areia200
            softStrong: Colors.indigo100
        }

    }

    // "base" pinta o badge e o ícone. Os campos surface* são o mesmo acento
    // diluído em 4%, 12% e 21%, para os cartões de escolha do Início — a
    // transparência é intencional ali: o acento vaza pelo fundo da página.
    // =========================================================================
    component OrderTypeTone: QtObject {
        property color base // badge, ícone, borda do cartão sob o mouse
        property color border // borda do cartão em repouso
        property color surface // fundo do cartão em repouso
        property color surfaceHover
        property color surfacePressed
        property color label // rótulo do cartão
        property color labelPressed
        readonly property color content: Colors.white // texto dentro do badge
    }

    component OrderTypeTokens: QtObject {
        readonly property OrderTypeTone
        balcao: OrderTypeTone {
            base: Colors.ouro600
            border: Colors.ouro200
            surface: Colors.ouro500Alpha04
            surfaceHover: Colors.ouro500Alpha12
            surfacePressed: Colors.ouro500Alpha21
            label: Colors.ouro700
            labelPressed: Colors.ouro800
        }

        readonly property OrderTypeTone
        entrega: OrderTypeTone {
            base: Colors.terracota500
            border: Colors.terracota100
            surface: Colors.terracota500Alpha04
            surfaceHover: Colors.terracota500Alpha12
            surfacePressed: Colors.terracota500Alpha21
            label: Colors.terracota600
            labelPressed: Colors.terracota700
        }
        // Chamada de "Salão" na tela inicial e de "Mesa" nas comandas.

        readonly property OrderTypeTone
        mesa: OrderTypeTone {
            base: Colors.agua500
            border: Colors.agua100
            surface: Colors.agua500Alpha04
            surfaceHover: Colors.agua500Alpha12
            surfacePressed: Colors.agua500Alpha21
            label: Colors.agua700
            labelPressed: Qt.darker(Colors.agua700, 1.4)
        }

    }

    // "soft" é o fundo do item já escolhido na lista; "strong", o texto de
    // ênfase (contador de selecionados, total). Espelha as cores que
    // services/cardapioService.py devolve para cada categoria.
    // =========================================================================
    component CategoryTone: QtObject {
        property color base
        property color hover: Qt.lighter(base, 1.1)
        property color pressed: Qt.darker(base, 1.2)
        property color soft // fundo do item selecionado
        property color strong: pressed // texto de ênfase
        readonly property color content: Colors.white
    }

    component CategoryTokens: QtObject {
        readonly property CategoryTone
        pizza: CategoryTone {
            base: Colors.brasa400
            soft: Colors.oliva100 // a seleção de sabor usa o verde de confirmar
        }

        readonly property CategoryTone
        lanche: CategoryTone {
            base: Colors.terracota500
            hover: Colors.terracota400
            pressed: Colors.terracota600
            soft: Colors.terracota100
        }

        readonly property CategoryTone
        bebida: CategoryTone {
            base: Colors.indigo500
            hover: Colors.indigo300
            pressed: Colors.indigo700
            soft: Colors.indigo100
            strong: Colors.indigo700
        }

        readonly property CategoryTone
        acai: CategoryTone {
            base: Colors.uva500
            hover: Colors.uva300
            pressed: Colors.uva700
            soft: Colors.uva50
        }

        readonly property CategoryTone
        outros: CategoryTone {
            base: Colors.uva700
            hover: Colors.uva500
            pressed: Qt.darker(Colors.uva700, 1.3)
            soft: Colors.uva100
        }
        // Etapas do popup de adicionais das pizzas.

        readonly property CategoryTone
        borda: CategoryTone {
            base: Colors.ouro600
            soft: Colors.ouro100
        }

        readonly property CategoryTone
        adicional: CategoryTone {
            base: Colors.agua500
            hover: Colors.agua300
            pressed: Colors.agua700
            soft: Colors.agua50
        }

    }

    // =========================================================================
    // BREAD — os três tipos de pão da tela de Lanches. Servem só para o
    // atendente distinguir as opções de relance; não carregam outro sentido.
    // =========================================================================
    component BreadTokens: QtObject {
        readonly property color hamburguer: Colors.terracota400
        readonly property color frances: Colors.uva500
        readonly property color baby: Colors.agua500
    }

    // =========================================================================
    // ILLUSTRATION — desenhos feitos em Canvas, não elementos de interface.
    // =========================================================================
    component IllustrationTokens: QtObject {
        // A pizza da tela de Pizzas, dividida em uma fatia por sabor.
        readonly property color pizzaDough: Colors.terracota200
        readonly property color pizzaCrust: Colors.terracota600
        readonly property color pizzaSliceLine: Colors.creme50 // divisórias e números
    }

    // =========================================================================
    // PRINTER — simulação da impressora térmica na prévia do cupom.
    // Não são cores de tema: representam tinta e papel de verdade, e por isso
    // não devem acompanhar mudanças de aparência do app.
    // =========================================================================
    component PrinterTokens: QtObject {
        readonly property color ink: Colors.carvao900 // texto impresso
        readonly property color paper: Colors.paper // fundo do cupom
        readonly property color paperBorder: Colors.paperBorder
        readonly property color reverseBackground: Colors.carvao900 // modo reverso ESC/POS
        readonly property color reverseText: Colors.creme50
    }

}
