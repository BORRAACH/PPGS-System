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

    // Textos da pergunta. Os padrões são os da exclusão pelo card; a troca de
    // modalidade (ver Salao.qml:trocarModalidade) reaproveita o popup com
    // outros, porque ali a mesa também sai — só que o pedido segue adiante.
    property string textoTitulo: "Excluir esta mesa?"
    property string textoCorpo: "Todos os itens lançados nela serão perdidos — nenhum cupom é impresso."
    property string textoConfirmar: "Excluir"
    // Quando definido, o Confirmar entrega a decisão a quem abriu o popup em
    // vez de apagar a mesa aqui: a troca de modalidade precisa gravar o
    // rascunho ANTES de apagar, senão uma falha de gravação perderia o pedido.
    property var aoConfirmar: null

    signal mesaApagada(string mesaId)

    function abrirPara(mesaId, titulo) {
        mesaIdAlvo = mesaId;
        tituloAlvo = titulo;
        open();
    }

    // Volta aos textos e ao comportamento de exclusão: o popup é um só para a
    // tela inteira, e o próximo clique no × de um card não pode herdar a troca.
    onClosed: {
        textoTitulo = "Excluir esta mesa?";
        textoCorpo = "Todos os itens lançados nela serão perdidos — nenhum cupom é impresso.";
        textoConfirmar = "Excluir";
        aoConfirmar = null;
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
                text: popupConfirmarExclusaoMesa.textoTitulo
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: popupConfirmarExclusaoMesa.tituloAlvo + "\n" + popupConfirmarExclusaoMesa.textoCorpo
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
                    // Guardada antes do close(): onClosed zera aoConfirmar.
                    var acao = popupConfirmarExclusaoMesa.aoConfirmar;
                    if (acao) {
                        popupConfirmarExclusaoMesa.close();
                        acao();
                        return;
                    }

                    salaoController.apagarMesa(mesaId);
                    popupConfirmarExclusaoMesa.close();
                    popupConfirmarExclusaoMesa.mesaApagada(mesaId);
                }

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.trash-can"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: popupConfirmarExclusaoMesa.textoConfirmar
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
