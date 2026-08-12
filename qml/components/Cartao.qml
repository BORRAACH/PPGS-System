import QtQuick
import QtQuick.Effects
import estilo 1.0

// Card de superfície com kicker/título/corpo/meta — anatomia do .card do
// Organic (components/cards.html), com elevação opcional (Estilo.global.elevation.*).
Rectangle {
    id: root

    property string kicker: ""
    property string titulo: ""
    property string corpo: ""
    property string meta: ""
    property var elevacao: null // Estilo.global.elevation.{sm,md,lg}, opcional

    color: Estilo.global.surface
    radius: Estilo.global.radius.lg
    implicitWidth: 220
    implicitHeight: coluna.implicitHeight + Estilo.global.padding.lg * 2

    MultiEffect {
        anchors.fill: parent
        source: root
        shadowEnabled: root.elevacao !== null
        shadowColor: Estilo.global.shadow
        shadowBlur: root.elevacao ? root.elevacao.blur : 0
        shadowVerticalOffset: root.elevacao ? root.elevacao.deslocamento : 0
        z: -1
    }

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
