import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../components"

// Popup de confirmação de exclusão de uma mesa aberta — mesmo padrão visual
// de qml/pages/consulta/PopupConfirmarExclusao.qml, mas chamando
// salaoController.apagarMesa em vez de consultaController.apagarComanda
// (não dá pra reaproveitar aquele componente direto: ele chama o controller
// certo já embutido no próprio onClicked).
Popup {
    id: popupConfirmarExclusaoMesa

    property string mesaIdAlvo: ""
    property string tituloAlvo: ""

    signal mesaApagada(string mesaId)

    function abrirPara(mesaId, titulo) {
        mesaIdAlvo = mesaId;
        tituloAlvo = titulo;
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
            Icone { nome: "fa6s.trash-can"; cor: Estilo.global.text; tamanho: 17; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "Excluir esta mesa?"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: popupConfirmarExclusaoMesa.tituloAlvo + "\nTodos os itens lançados nela serão perdidos — nenhum cupom é impresso."
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            width: Responsivo.larguraPopup(320)
            wrapMode: Text.Wrap
        }

        Row {
            spacing: Estilo.global.spacing.lg
            anchors.right: parent.right

            Button {
                id: btnCancelarExclusaoMesa

                text: "Cancelar"
                padding: Estilo.global.padding.md
                onClicked: popupConfirmarExclusaoMesa.close()

                contentItem: Text {
                    text: btnCancelarExclusaoMesa.text
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
                id: btnConfirmarExclusaoMesa

                padding: Estilo.global.padding.md
                onClicked: {
                    var mesaId = popupConfirmarExclusaoMesa.mesaIdAlvo;
                    salaoController.apagarMesa(mesaId);
                    popupConfirmarExclusaoMesa.close();
                    popupConfirmarExclusaoMesa.mesaApagada(mesaId);
                }

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.trash-can"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Excluir"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                    border.color: Estilo.action.danger.pressed
                    border.width: Estilo.global.borderWidth.hairline
                }
            }
        }
    }
}
