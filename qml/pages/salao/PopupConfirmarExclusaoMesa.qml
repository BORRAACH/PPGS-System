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

        Row {
            spacing: 8
            Icone { nome: "fa6s.trash-can"; cor: Estilo.cores.texto; tamanho: 17; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "Excluir esta mesa?"
                font.pixelSize: 17
                font.bold: true
                color: Estilo.cores.texto
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: popupConfirmarExclusaoMesa.tituloAlvo + "\nTodos os itens lançados nela serão perdidos — nenhum cupom é impresso."
            font.pixelSize: 13
            color: Estilo.cores.textoSecundario
            width: 320
            wrapMode: Text.Wrap
        }

        Row {
            spacing: 12
            anchors.right: parent.right

            Button {
                id: btnCancelarExclusaoMesa

                text: "Cancelar"
                padding: 10
                onClicked: popupConfirmarExclusaoMesa.close()

                contentItem: Text {
                    text: btnCancelarExclusaoMesa.text
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
                id: btnConfirmarExclusaoMesa

                padding: 10
                onClicked: {
                    var mesaId = popupConfirmarExclusaoMesa.mesaIdAlvo;
                    salaoController.apagarMesa(mesaId);
                    popupConfirmarExclusaoMesa.close();
                    popupConfirmarExclusaoMesa.mesaApagada(mesaId);
                }

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.trash-can"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Excluir"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
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
