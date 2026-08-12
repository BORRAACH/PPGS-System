import QtQuick
import estilo 1.0

// Tabela simples: cabeçalho + linhas, com friso de hover e régua divisória
// — pronta para telas com dado tabular (Rede, Consulta), que hoje usam
// ListView cru. "linhas" é um array de arrays de string, uma por coluna.
Column {
    id: root

    property var cabecalhos: []
    property var linhas: []
    property var larguras: [] // largura de cada coluna, em px; opcional

    readonly property real colunaLargura: width / Math.max(cabecalhos.length, 1)

    spacing: 0

    Row {
        width: root.width
        height: Estilo.global.fontSize.xs + Estilo.global.padding.sm * 2

        Repeater {
            model: root.cabecalhos

            delegate: Text {
                required property string modelData
                required property int index

                width: root.larguras.length > index ? root.larguras[index] : root.colunaLargura
                height: parent.height
                verticalAlignment: Text.AlignVCenter
                text: modelData.toUpperCase()
                font.pixelSize: Estilo.global.fontSize.xs
                font.bold: true
                letterSpacing: Estilo.global.letterSpacing.wide
                color: Estilo.global.textSecondary
            }

        }

    }

    Rectangle {
        width: root.width
        height: Estilo.global.borderWidth.hairline
        color: Estilo.global.divider
    }

    Repeater {
        model: root.linhas

        delegate: Rectangle {
            id: linha

            required property var modelData

            width: root.width
            height: colunaLinha.implicitHeight + Estilo.global.padding.sm * 2
            color: areaLinha.containsMouse ? Estilo.global.surfaceHover : "transparent"

            Row {
                id: colunaLinha

                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    model: linha.modelData

                    delegate: Text {
                        required property string modelData
                        required property int index

                        width: root.larguras.length > index ? root.larguras[index] : root.colunaLargura
                        text: modelData
                        font.pixelSize: Estilo.global.fontSize.md
                        color: Estilo.global.text
                        elide: Text.ElideRight
                    }

                }

            }

            MouseArea {
                id: areaLinha

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Estilo.global.borderWidth.hairline
                color: Estilo.global.divider
            }

        }

    }

}
