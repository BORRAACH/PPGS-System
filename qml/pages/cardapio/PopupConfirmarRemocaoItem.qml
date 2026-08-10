import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../components"

// Confirmação de remoção de um item do cardápio, compartilhada por todas as
// linhas da lista de Cardapio.qml (um popup só, não um por linha — mesma
// ideia de pages/consulta/PopupConfirmarExclusao.qml).
//
// Diferente daquele, este não chama nenhum controller: só avisa quem o
// instanciou (sinal "confirmada"), porque é Cardapio.qml que conhece a
// categoria atual e grava a lista inteira de uma vez.
Popup {
    id: popupConfirmarRemocao

    property int indiceAlvo: -1
    property string nomeAlvo: ""

    signal confirmada(int indice)

    function abrirPara(indice, nome) {
        indiceAlvo = indice;
        nomeAlvo = nome;
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

            Icone {
                nome: "fa6s.trash-can"
                cor: Estilo.global.text
                tamanho: 17
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Remover este item do cardápio?"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: popupConfirmarRemocao.nomeAlvo
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            width: 320
            wrapMode: Text.Wrap
        }

        Text {
            text: "Ele deixa de aparecer nas telas de pedido. Comandas já feitas não mudam."
            font.pixelSize: Estilo.global.fontSize.sm
            color: Estilo.global.textSecondary
            width: 320
            wrapMode: Text.Wrap
        }

        Row {
            spacing: Estilo.global.spacing.lg
            anchors.right: parent.right

            Button {
                id: btnCancelarRemocao

                text: "Cancelar"
                padding: Estilo.global.padding.md
                onClicked: popupConfirmarRemocao.close()

                contentItem: Text {
                    text: btnCancelarRemocao.text
                    font.bold: true
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.sm
                    color: btnCancelarRemocao.down ? Estilo.action.neutral.pressed : (btnCancelarRemocao.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                }
            }

            Button {
                id: btnConfirmarRemocao

                padding: Estilo.global.padding.md
                onClicked: {
                    popupConfirmarRemocao.close();
                    popupConfirmarRemocao.confirmada(popupConfirmarRemocao.indiceAlvo);
                }

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent

                    Icone {
                        nome: "fa6s.trash-can"
                        cor: Estilo.global.textOnAccent
                        tamanho: Estilo.global.fontSize.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Remover"
                        font.bold: true
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.sm
                    color: btnConfirmarRemocao.down ? Estilo.action.danger.pressed : (btnConfirmarRemocao.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                    border.color: Estilo.action.danger.pressed
                    border.width: Estilo.global.borderWidth.hairline
                }
            }
        }
    }
}
