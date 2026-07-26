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
    padding: 25
    parent: Overlay.overlay
    anchors.centerIn: parent

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        radius: Estilo.rounding.popup
        color: Estilo.cores.fundoPagina
        border.color: Estilo.cores.bordaCard
    }

    contentItem: Column {
        spacing: 20

        Row {
            spacing: 8

            Icone {
                nome: "fa6s.trash-can"
                cor: Estilo.cores.texto
                tamanho: 17
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Remover este item do cardápio?"
                font.pixelSize: 17
                font.bold: true
                color: Estilo.cores.texto
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: popupConfirmarRemocao.nomeAlvo
            font.pixelSize: 13
            color: Estilo.cores.textoSecundario
            width: 320
            wrapMode: Text.Wrap
        }

        Text {
            text: "Ele deixa de aparecer nas telas de pedido. Comandas já feitas não mudam."
            font.pixelSize: 12
            color: Estilo.cores.textoSecundario
            width: 320
            wrapMode: Text.Wrap
        }

        Row {
            spacing: 12
            anchors.right: parent.right

            Button {
                id: btnCancelarRemocao

                text: "Cancelar"
                padding: 10
                onClicked: popupConfirmarRemocao.close()

                contentItem: Text {
                    text: btnCancelarRemocao.text
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: btnCancelarRemocao.down ? Estilo.cores.textoSecundario : (btnCancelarRemocao.hovered ? "#95a5a6" : Estilo.cores.textoSecundario)
                }
            }

            Button {
                id: btnConfirmarRemocao

                padding: 10
                onClicked: {
                    popupConfirmarRemocao.close();
                    popupConfirmarRemocao.confirmada(popupConfirmarRemocao.indiceAlvo);
                }

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent

                    Icone {
                        nome: "fa6s.trash-can"
                        cor: "#ffffff"
                        tamanho: Estilo.fonte.padrao
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Remover"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: btnConfirmarRemocao.down ? Estilo.cancelar.pressionado : (btnConfirmarRemocao.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                    border.color: Estilo.cancelar.pressionado
                    border.width: 1
                }
            }
        }
    }
}
