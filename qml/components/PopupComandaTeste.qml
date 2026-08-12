import QtQuick
import QtQuick.Controls
import estilo 1.0

// Popup de confirmação usado por Balcao.qml/Entrega.qml quando o usuário
// tenta imprimir/lançar uma comanda totalmente em branco — pergunta se é
// uma comanda de teste (ex: pra testar se a impressora está respondendo)
// antes de deixar passar, já que uma comanda em branco não faz sentido
// como pedido de verdade.
Popup {
    id: popupComandaTeste

    // Guardados aqui (não em Balcao.qml/Entrega.qml) para que quem chamou
    // abrirPara() não precise manter esse estado por conta própria — o
    // handler de "respondido" só precisa ler de volta acaoPendente/dados.
    property string acaoPendente: ""
    property var dados: null

    signal respondido(bool teste)

    function abrirPara(acao, dadosPedido) {
        acaoPendente = acao;
        dados = dadosPedido;
        open();
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    contentItem: Column {
        spacing: Estilo.global.spacing.xxl

        Row {
            spacing: Estilo.global.spacing.sm
            Icone { nome: "fa6s.flask"; cor: Estilo.global.text; tamanho: 17; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "Comanda em branco"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: "Nenhum campo foi preenchido. Deseja seguir mesmo assim como comanda de teste?"
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            width: 320
            wrapMode: Text.Wrap
        }

        Row {
            spacing: Estilo.global.spacing.lg
            anchors.right: parent.right

            Button {
                id: btnComandaNormal

                text: "Não, é normal"
                padding: Estilo.global.padding.md
                onClicked: {
                    popupComandaTeste.close();
                    popupComandaTeste.respondido(false);
                }

                contentItem: Text {
                    text: btnComandaNormal.text
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: parent.down ? Estilo.action.neutral.pressed : (parent.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                }
            }

            Button {
                id: btnComandaTeste

                padding: Estilo.global.padding.md
                onClicked: {
                    popupComandaTeste.close();
                    popupComandaTeste.respondido(true);
                }

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.flask"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Sim, é teste"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: parent.down ? Estilo.action.confirm.pressed : (parent.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                    border.color: Estilo.action.confirm.pressed
                    border.width: Estilo.global.borderWidth.hairline
                }
            }
        }
    }
}
