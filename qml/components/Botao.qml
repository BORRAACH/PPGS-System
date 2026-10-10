import QtQuick
import QtQuick.Controls
import estilo 1.0

// Botão em pílula com 4 variantes (primario/secundario/ghost/icone), lendo
// cor de "tom" (um ButtonTone de Estilo.action.*/screen.*/...) — substitui o
// padrão "Button { background: Rectangle{...} }" repetido à mão em cada
// popup/tela, sempre com o mesmo ternário down/hovered/base.
Button {
    id: root

    property var tom: Estilo.action.confirm
    property string variante: "primario" // primario | secundario | ghost | icone
    property string nomeIcone: ""
    property bool bloco: false

    readonly property bool preenchido: variante === "primario" || variante === "icone"
    readonly property color corConteudo: preenchido ? tom.content : (down ? tom.pressed : (hovered ? tom.hover : tom.base))

    width: bloco && parent ? parent.width : implicitWidth
    padding: variante === "icone" ? Estilo.global.padding.sm : Estilo.global.padding.md
    spacing: Estilo.global.spacing.xs

    background: Rectangle {
        radius: Estilo.global.radius.pill
        color: root.preenchido ? (root.down ? root.tom.pressed : (root.hovered ? root.tom.hover : root.tom.base)) : (root.variante === "secundario" ? Estilo.global.surface : (root.down ? Estilo.global.surfacePressed : (root.hovered ? Estilo.global.surfaceHover : "transparent")))
        // Tema comanda (secundário): botão preenchido também leva borda, e os
        // que têm fundo (preenchido/secundário) projetam a sombra dura.
        readonly property bool comBorda: root.variante === "secundario" || (Estilo.global.filledButtonBorder && root.preenchido && root.variante !== "icone")
        border.color: root.variante === "secundario" ? (Estilo.global.filledButtonBorder ? Estilo.global.borderStrong : (root.down ? root.tom.pressed : (root.hovered ? root.tom.hover : root.tom.base))) : (comBorda ? Estilo.global.borderStrong : "transparent")
        border.width: comBorda ? Estilo.global.borderWidth.hairline : 0
        opacity: root.enabled ? 1 : Estilo.global.opacity.disabled

        Rectangle {
            z: -1
            visible: Estilo.global.shadowOffset > 0 && root.variante !== "ghost" && root.variante !== "icone" && root.enabled
            x: root.down ? 1 : Estilo.global.shadowOffset
            y: root.down ? 1 : Estilo.global.shadowOffset
            width: parent.width
            height: parent.height
            radius: parent.radius
            color: Estilo.global.shadowColor
        }
    }

    contentItem: Row {
        spacing: root.spacing
        anchors.centerIn: root.variante === "icone" ? parent : undefined
        anchors.left: root.variante === "icone" ? undefined : parent.left
        anchors.leftMargin: root.variante === "icone" ? 0 : root.leftPadding
        anchors.right: root.variante === "icone" ? undefined : parent.right
        anchors.rightMargin: root.variante === "icone" ? 0 : root.rightPadding
        anchors.verticalCenter: parent.verticalCenter

        Icone {
            visible: root.nomeIcone !== ""
            nome: root.nomeIcone
            cor: root.corConteudo
            tamanho: Estilo.global.fontSize.lg
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: root.text !== "" && root.variante !== "icone"
            text: root.text
            font.family: Estilo.global.fontFamily.title
            font.pixelSize: Estilo.global.fontSize.lg
            color: root.corConteudo
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
        }

    }

}
