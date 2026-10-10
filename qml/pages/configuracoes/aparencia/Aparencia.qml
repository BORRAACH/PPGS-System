import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../../components"

// Escolha do tema visual do app (ver qml/estilo/Estilo.qml e os temas em
// qml/estilo/temas/). A troca vale na hora e fica guardada nesta máquina —
// como na seção de Usuários, não há "alterações pendentes" aqui: clicar no
// cartão já aplica.
ColumnLayout {
    id: aparencia

    readonly property color corDestaque: Estilo.screen.config.accent

    spacing: Estilo.global.spacing.lg

    Text {
        text: "Aparência"
        font.pixelSize: Estilo.global.fontSize.lg
        font.bold: true
        color: aparencia.corDestaque
    }

    Text {
        Layout.fillWidth: true
        text: "Escolha o visual do sistema. A troca é imediata e vale só para esta máquina."
        wrapMode: Text.WordWrap
        font.pixelSize: Estilo.global.fontSize.sm
        color: Estilo.global.textSecondary
    }

    Flow {
        Layout.fillWidth: true
        spacing: Estilo.global.spacing.lg

        Repeater {
            model: Estilo.temas

            delegate: Rectangle {
                id: cartaoTema

                required property var modelData

                readonly property bool ativo: Estilo.nomeTema === cartaoTema.modelData.chave

                width: 240
                height: 110
                radius: Estilo.global.radius.md
                color: areaTema.containsMouse ? Estilo.global.surfaceHover : Estilo.global.surface
                border.color: cartaoTema.ativo ? aparencia.corDestaque : Estilo.global.borderCard
                border.width: cartaoTema.ativo ? 2 : 1

                MouseArea {
                    id: areaTema

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Estilo.definirTema(cartaoTema.modelData.chave)
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: Estilo.global.padding.lg
                    spacing: Estilo.global.spacing.xs

                    Row {
                        spacing: Estilo.global.spacing.sm

                        Icone {
                            nome: cartaoTema.ativo ? "fa6s.circle-check" : "fa6s.palette"
                            cor: cartaoTema.ativo ? aparencia.corDestaque : Estilo.global.textSecondary
                            tamanho: Estilo.global.fontSize.md
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: cartaoTema.modelData.nome + (cartaoTema.ativo ? " (em uso)" : "")
                            font.pixelSize: Estilo.global.fontSize.md
                            font.bold: true
                            color: Estilo.global.text
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        width: parent.width
                        text: cartaoTema.modelData.descricao
                        wrapMode: Text.WordWrap
                        font.pixelSize: Estilo.global.fontSize.sm
                        color: Estilo.global.textSecondary
                    }
                }
            }
        }
    }
}
