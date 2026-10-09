import QtQuick
import estilo 1.0

// Card de superfície com kicker/título/corpo/meta — anatomia do .card do
// Organic (components/cards.html), no estilo flat: sem sombra, só borda.
Rectangle {
    id: root

    property string kicker: ""
    property string titulo: ""
    property string corpo: ""
    property string meta: ""

    color: Estilo.global.surface
    border.color: Estilo.global.borderCard
    border.width: Estilo.global.borderWidth.hairline
    radius: Estilo.global.radius.lg
    implicitWidth: 220
    implicitHeight: coluna.implicitHeight + Estilo.global.padding.lg * 2

    Column {
        id: coluna

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Estilo.global.padding.lg
        spacing: Estilo.global.spacing.sm

        Text {
            visible: root.kicker !== ""
            width: parent.width
            text: root.kicker.toUpperCase()
            font.pixelSize: Estilo.global.fontSize.xs
            font.bold: true
            letterSpacing: Estilo.global.letterSpacing.wider
            color: Estilo.action.confirm.base
        }

        Text {
            visible: root.titulo !== ""
            width: parent.width
            text: root.titulo
            font.pixelSize: Estilo.global.fontSize.xl
            font.bold: true
            color: Estilo.global.text
            wrapMode: Text.WordWrap
        }

        Text {
            visible: root.corpo !== ""
            width: parent.width
            text: root.corpo
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            wrapMode: Text.WordWrap
        }

        Text {
            visible: root.meta !== ""
            width: parent.width
            text: root.meta
            font.pixelSize: Estilo.global.fontSize.xs
            color: Estilo.global.textMuted
        }

    }

}
