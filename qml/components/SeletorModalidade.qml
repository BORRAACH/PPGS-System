import QtQuick
import QtQuick.Controls
import estilo 1.0

// Troca a modalidade do pedido (Balcão / Entrega / Salão) sem perder o que já
// foi digitado. Este componente só mostra a modalidade atual e avisa o clique;
// quem leva os dados de uma tela para a outra é o trocarModalidade() de cada
// tela de venda.
//
// NoFocus nos botões: as telas de venda montam a ordem de Tab/Enter campo a
// campo, e um botão a mais no caminho desviaria quem lança só pelo teclado.
Row {
    id: seletor

    // "Balcão", "Entrega" ou "Salão" — os mesmos rótulos de
    // DestinoPedido.tipoDaTela, que é o que trocarModalidade() espera.
    property string modalidadeAtual: ""

    signal trocar(string tipo)

    // Ícone e cor de cada modalidade, os mesmos do título de cada tela e dos
    // cards da faixa de rascunhos — é por eles que se reconhece o tipo sem ler.
    readonly property var _opcoes: [
        { "tipo": "Balcão", "icone": "fa6s.bag-shopping", "tom": Estilo.screen.balcao },
        { "tipo": "Entrega", "icone": "fa6s.motorcycle", "tom": Estilo.screen.entrega },
        { "tipo": "Salão", "icone": "fa6s.utensils", "tom": Estilo.screen.salao }
    ]

    spacing: Estilo.global.spacing.sm

    Repeater {
        model: seletor._opcoes

        delegate: Button {
            id: botaoModalidade

            required property var modelData
            readonly property bool atual: botaoModalidade.modelData.tipo === seletor.modalidadeAtual
            readonly property color corTom: botaoModalidade.modelData.tom.accent
            readonly property color corConteudo: botaoModalidade.atual ? Estilo.global.textOnAccent : botaoModalidade.corTom

            focusPolicy: Qt.NoFocus
            topPadding: 6
            bottomPadding: 6
            leftPadding: 14
            rightPadding: 14
            onClicked: {
                if (!botaoModalidade.atual)
                    seletor.trocar(botaoModalidade.modelData.tipo);
            }

            contentItem: Row {
                spacing: Estilo.global.spacing.xs

                Icone {
                    nome: botaoModalidade.modelData.icone
                    cor: botaoModalidade.corConteudo
                    tamanho: Estilo.global.fontSize.md
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: botaoModalidade.modelData.tipo
                    font.pixelSize: Estilo.global.fontSize.md
                    font.family: Estilo.global.fontFamily.title
                    color: botaoModalidade.corConteudo
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: botaoModalidade.atual
                       ? botaoModalidade.corTom
                       : (botaoModalidade.hovered
                          ? Qt.rgba(botaoModalidade.corTom.r, botaoModalidade.corTom.g, botaoModalidade.corTom.b, 0.12)
                          : Estilo.global.surface)
                border.color: botaoModalidade.corTom
                border.width: Estilo.global.borderWidth.hairline
            }
        }
    }
}
