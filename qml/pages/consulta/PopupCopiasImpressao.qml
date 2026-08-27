import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

// Quantas vias reimprimir de uma comanda — aberto pelo "Reimprimir" do menu
// de contexto da lista (ver ItemComandaDelegate.qml).
//
// Existe porque reimprimir quase nunca é "mais uma": é a via que faltou pro
// entregador, ou o cupom inteiro de novo porque o papel picotou no meio. Sem
// perguntar, quem precisava de duas clicava duas vezes e ficava sem saber se a
// primeira tinha saído — a impressão é assíncrona, e o aviso de resultado chega
// depois (ver redeController.impressaoResultado).
//
// Não confere nada nem imprime: junta o número e devolve pelo callback, do
// mesmo jeito que components/PopupAutorizacao.qml faz com a ação protegida.
Popup {
    id: popupCopias

    objectName: "popupCopiasImpressao"

    // Texto que identifica a comanda na pergunta ("Balcão — João, 20:15").
    property string tituloComanda: ""

    // Continuação, guardada só enquanto o popup está aberto (ver onClosed).
    property var _aoConfirmar: null

    function abrirPara(titulo, aoConfirmar) {
        popupCopias.tituloComanda = titulo || "";
        popupCopias._aoConfirmar = aoConfirmar || null;
        // Sempre volta a 1: a quantidade da reimpressão anterior não diz nada
        // sobre esta, e herdar "3" de uma comanda passada é o tipo de coisa
        // que só se percebe olhando o papel sair.
        spinner.value = 1;
        open();
    }

    function _confirmar() {
        var quantas = spinner.value;
        var seguir = popupCopias._aoConfirmar;
        popupCopias.close();
        if (seguir)
            seguir(quantas);
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    onOpened: spinner.forceActiveFocus()
    onClosed: popupCopias._aoConfirmar = null

    width: Math.min(360, parent ? parent.width * 0.9 : 360)

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    contentItem: ColumnLayout {
        spacing: Estilo.global.spacing.xl

        Row {
            spacing: Estilo.global.spacing.sm

            Icone {
                nome: "fa6s.print"
                cor: Estilo.global.text
                tamanho: Estilo.global.fontSize.title
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Reimprimir"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            Layout.fillWidth: true
            visible: popupCopias.tituloComanda !== ""
            text: popupCopias.tituloComanda
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Estilo.global.spacing.lg

            Text {
                text: "Quantas cópias?"
                font.pixelSize: Estilo.global.fontSize.lg
                color: Estilo.global.text
                Layout.fillWidth: true
            }

            SpinnerCopias {
                id: spinner

                objectName: "spinnerCopiasReimpressao"

                corDestaque: Estilo.screen.consulta.base
                Keys.onReturnPressed: popupCopias._confirmar()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Estilo.global.spacing.lg

            Button {
                id: btnCancelarCopias

                Layout.fillWidth: true
                padding: Estilo.global.padding.md
                onClicked: popupCopias.close()

                contentItem: Text {
                    text: "Cancelar"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnCancelarCopias.down ? Estilo.action.neutral.pressed : (btnCancelarCopias.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                }
            }

            Button {
                id: btnConfirmarCopias

                Layout.fillWidth: true
                padding: Estilo.global.padding.md
                onClicked: popupCopias._confirmar()

                contentItem: Text {
                    text: spinner.value === 1 ? "Imprimir" : "Imprimir " + spinner.value + " vias"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnConfirmarCopias.down ? Estilo.screen.consulta.pressed : (btnConfirmarCopias.hovered ? Estilo.screen.consulta.hover : Estilo.screen.consulta.base)
                }
            }
        }
    }
}
