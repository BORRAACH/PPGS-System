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

            Botao {
                tom: Estilo.action.neutral
                text: "Não salvar"
                onClicked: {
                    popupSalvarEndereco.close();
                    popupSalvarEndereco.respondido(false);
                }
            }

            Botao {
                tom: Estilo.action.confirm
                nomeIcone: "fa6s.floppy-disk"
                text: popupSalvarEndereco.jaExiste ? "Sobrescrever" : "Salvar"
                onClicked: {
                    popupSalvarEndereco.close();
                    popupSalvarEndereco.respondido(true);
                }
            }
        }
    }
}
