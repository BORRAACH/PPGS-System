import QtQuick
import QtQuick.Controls
import estilo 1.0

// Popup padronizado: backdrop + superfície + título/corpo/ações — a anatomia
// duplicada em PopupSalvarEndereco.qml/PopupComandaTeste.qml antes de existir.
// Os botões de ação são filhos declarados direto dentro do Dialogo (viram a
// linha de ações à direita, no rodapé).
Popup {
    id: root

    property string titulo: ""
    property string corpo: ""
    property string nomeIcone: ""
    default property alias acoes: linhaAcoes.data

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
            visible: root.titulo !== ""
            spacing: Estilo.global.spacing.sm

            Icone {
                visible: root.nomeIcone !== ""
                nome: root.nomeIcone
                cor: Estilo.global.text
                tamanho: 17
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.titulo
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }

        }

        Text {
            visible: root.corpo !== ""
            text: root.corpo
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            width: 320
            wrapMode: Text.Wrap
        }

        Row {
            id: linhaAcoes

            spacing: Estilo.global.spacing.lg
            anchors.right: parent.right
        }

    }

}
