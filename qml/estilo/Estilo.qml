pragma Singleton
import QtQuick

// Configurações de estilo compartilhadas por todas as páginas/componentes do
// app. Organizadas como sub-objetos temáticos (rounding, cores, fonte, ...),
// cada um com uma "escala" multiplicadora e propriedades nomeadas — mesma
// esquemática usada pelo Appearance/AppearanceConfig do caelestia
// (~/.config/quickshell/caelestia/config/AppearanceConfig.qml): um singleton
// que agrupa tokens de design em componentes aninhados, em vez de uma lista
// plana de propriedades soltas. Import: "import estilo 1.0" (o diretório
// qml/ já está no import path, configurado em main.py).
QtObject {
    id: root

    // ===== Raios (cantos arredondados) =====
    component Rounding: QtObject {
        readonly property real escala: 1
        readonly property int padrao: 5 * escala // inputs e botões de ação padrão
        readonly property int grande: 8 * escala // cards, itens de lista, botões grandes
        readonly property int medio: 10 * escala // painéis e notificações
        readonly property int painel: 12 * escala // painéis visuais maiores
        readonly property int popup: 20 * escala // popups e fundo das páginas
        readonly property int cheio: 1000 * escala // cápsulas/pílulas — Qt limita ao raio máximo possível (metade do menor lado)
    }

    // ===== Espaçamento entre elementos (spacing) =====
    component Espacamento: QtObject {
        readonly property real escala: 1
        readonly property int pequeno: 7 * escala
        readonly property int menor: 10 * escala
        readonly property int normal: 12 * escala
        readonly property int maior: 15 * escala
        readonly property int grande: 20 * escala
    }

    // ===== Preenchimento interno / margens (padding) =====
    component Preenchimento: QtObject {
        readonly property real escala: 1
        readonly property int pequeno: 5 * escala
        readonly property int menor: 7 * escala
        readonly property int normal: 10 * escala
        readonly property int maior: 12 * escala
        readonly property int grande: 15 * escala
    }

    // ===== Cores de borda/texto/fundo =====
    component Cores: QtObject {
        readonly property color borda: "#cccccc" // borda padrão (sem foco) de inputs
        readonly property color bordaCard: "#e0e0e0" // borda de cards/painéis/popups
        readonly property color texto: "#2c3e50" // texto padrão
        readonly property color textoSecundario: "#7f8c8d" // texto secundário/desabilitado
        readonly property color fundoPagina: "#f8f9fa" // fundo das páginas e popups

        // Texto DIGITADO dentro de inputs (TextField/TextArea/SpinBox/
        // ComboBox). Preto fixo, e sempre declarado explicitamente em cada
        // input: sem "color:", o Qt usa palette.text, que no Windows vem do
        // tema do sistema — em máquinas com tema escuro o texto saía branco
        // sobre o fundo branco do input, ficando invisível enquanto o
        // atendente digitava o pedido. Como o fundo dos inputs é sempre
        // branco (fixo no background de cada um), a cor do texto também
        // precisa ser fixa, não herdada.
        readonly property color textoInput: "#000000"
        // Mesma história para o texto de dica (placeholderText), que vem de
        // palette.placeholderText.
        readonly property color placeholderInput: "#95a5a6"
    }

    // ===== Botão Confirmar / Sucesso (verde) =====
    component Confirmar: QtObject {
        readonly property color normal: "#27ae60"
        readonly property color hover: "#2ecc71"
        readonly property color pressionado: "#1e8449"
    }

    // ===== Botão Cancelar / Apagar / Erro (vermelho) =====
    component Cancelar: QtObject {
        readonly property color normal: "#e74c3c"
        readonly property color hover: "#ec7063"
        readonly property color pressionado: "#922b21"
    }

    // Variante um pouco mais escura usada pelos botões "Voltar" de
    // Lanches.qml/Pizzas.qml — mesma cor base de Cancelar, tons diferentes.
    component Voltar: QtObject {
        readonly property color hover: "#d63031"
        readonly property color pressionado: "#c0392b"
    }

    // ===== Fonte =====
    component Fonte: QtObject {
        readonly property real escala: 1
        readonly property int padrao: 14 * escala // texto padrão de inputs e listas
        readonly property int titulo: 22 * escala // título principal de cada página
    }

    readonly property Rounding rounding: Rounding {}
    readonly property Espacamento espacamento: Espacamento {}
    readonly property Preenchimento preenchimento: Preenchimento {}
    readonly property Cores cores: Cores {}
    readonly property Confirmar confirmar: Confirmar {}
    readonly property Cancelar cancelar: Cancelar {}
    readonly property Voltar voltar: Voltar {}
    readonly property Fonte fonte: Fonte {}
}
