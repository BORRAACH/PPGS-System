import QtQuick
import QtQuick.Controls
import estilo 1.0

// Popup de confirmação usado por Entrega.qml ao clicar Imprimir/Lançar com
// telefone+endereço preenchidos: pergunta se deve salvar (ou sobrescrever,
// se já havia um endereço salvo pra esse telefone — ver
// enderecoEncontradoNoServidor) no pizzeria-server, antes de prosseguir com
// o pedido em si. Mesmo padrão de abrirPara/respondido de
// PopupComandaTeste.qml.
Popup {
    id: popupSalvarEndereco

    property string acaoPendente: ""
    property var dados: null
    property bool jaExiste: false

    signal respondido(bool salvar)

    function abrirPara(acao, dadosPedido, enderecoJaExiste) {
        acaoPendente = acao;
        dados = dadosPedido;
        jaExiste = enderecoJaExiste;
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
            Icone { nome: "fa6s.address-book"; cor: Estilo.global.text; tamanho: 17; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: popupSalvarEndereco.jaExiste ? "Endereço já cadastrado" : "Salvar endereço"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: popupSalvarEndereco.jaExiste ? "Já existe um endereço salvo para esse telefone. Deseja sobrescrever com os dados atuais?" : "Deseja salvar este endereço para agilizar pedidos futuros com esse telefone?"
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            width: 320
            wrapMode: Text.Wrap
        }

        Row {
            spacing: Estilo.global.spacing.lg
            anchors.right: parent.right

            Button {
                id: btnNaoSalvar

                text: "Não salvar"
                padding: Estilo.global.padding.md
                onClicked: {
                    popupSalvarEndereco.close();
                    popupSalvarEndereco.respondido(false);
                }

                contentItem: Text {
                    text: btnNaoSalvar.text
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
                id: btnSalvar

                padding: Estilo.global.padding.md
                onClicked: {
                    popupSalvarEndereco.close();
                    popupSalvarEndereco.respondido(true);
                }

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.floppy-disk"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: popupSalvarEndereco.jaExiste ? "Sobrescrever" : "Salvar"
                        font.bold: true
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.sm
                    color: parent.down ? Estilo.action.confirm.pressed : (parent.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                    border.color: Estilo.action.confirm.pressed
                    border.width: Estilo.global.borderWidth.hairline
                }
            }
        }
    }
}
