import QtQuick
import QtQuick.Controls
import estilo 1.0

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
    padding: 25
    parent: Overlay.overlay
    anchors.centerIn: parent

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        radius: 16
        color: Estilo.cores.fundoPagina
        border.color: Estilo.cores.bordaCard
    }

    contentItem: Column {
        spacing: 20

        Text {
            text: "🗑️ Apagar esta comanda?"
            font.pixelSize: 17
            font.bold: true
            color: Estilo.cores.texto
        }

        Text {
            text: popupConfirmarExclusao.tituloAlvo
            font.pixelSize: 13
            color: Estilo.cores.textoSecundario
            width: 320
            wrapMode: Text.Wrap
        }

        Row {
            spacing: 12
            anchors.right: parent.right

            Button {
                id: btnCancelarExclusao

                text: "Cancelar"
                padding: 10
                onClicked: popupConfirmarExclusao.close()

                contentItem: Text {
                    text: btnCancelarExclusao.text
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Estilo.cores.textoSecundario : (parent.hovered ? "#95a5a6" : Estilo.cores.textoSecundario)
                }
            }

            Button {
                id: btnConfirmarExclusao

                text: "🗑️ Apagar"
                padding: 10
                onClicked: {
                    consultaController.apagarComanda(popupConfirmarExclusao.arquivoAlvo);
                    popupConfirmarExclusao.close();
                    popupConfirmarExclusao.comandaApagada();
                }

                contentItem: Text {
                    text: btnConfirmarExclusao.text
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Estilo.cancelar.pressionado : (parent.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                    border.color: Estilo.cancelar.pressionado
                    border.width: 1
                }
            }
        }
    }
}
