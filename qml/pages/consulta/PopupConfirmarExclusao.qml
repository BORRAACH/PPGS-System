import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../components"

// Popup de confirmação de exclusão, compartilhado por todos os itens da
// lista em ColunaEsquerda.qml/ItemComandaDelegate.qml (evita instanciar um
// popup por linha).
Popup {
    id: popupConfirmarExclusao

    property string arquivoAlvo: ""
    property string tituloAlvo: ""

    signal comandaApagada

    function abrirPara(nomeArquivo, titulo) {
        arquivoAlvo = nomeArquivo;
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
                text: "Apagar esta comanda?"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: popupConfirmarExclusao.tituloAlvo
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            width: Responsivo.larguraPopup(320)
            wrapMode: Text.Wrap
        }

        Row {
            spacing: Estilo.global.spacing.lg
            anchors.right: parent.right

            Button {
                id: btnCancelarExclusao

                text: "Cancelar"
                padding: Estilo.global.padding.md
                onClicked: popupConfirmarExclusao.close()

                contentItem: Text {
                    text: btnCancelarExclusao.text
                    font.bold: true
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.sm
                    color: parent.down ? Estilo.action.neutral.pressed : (parent.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                }
            }

            Button {
                id: btnConfirmarExclusao

                padding: Estilo.global.padding.md
                onClicked: {
                    consultaController.apagarComanda(popupConfirmarExclusao.arquivoAlvo);
                    popupConfirmarExclusao.close();
                    popupConfirmarExclusao.comandaApagada();
                }

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.trash-can"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Apagar"
                        font.bold: true
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.sm
                    color: parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                    border.color: Estilo.action.danger.pressed
                    border.width: Estilo.global.borderWidth.hairline
                }
            }
        }
    }
}
