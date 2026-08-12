import QtQuick
import estilo 1.0

// Etiqueta em pílula pequena (badge/chip de status), lendo cor de "tom" — um
// Tone (Estilo.status.*: background/border/content) ou um ButtonTone
// (Estilo.action.*/screen.*: base/content). "contorno" desenha só a borda,
// sem fundo, igual ao .tag-outline do Organic.
Rectangle {
    id: root

    property string texto: ""
    property var tom: Estilo.status.info
    property string variante: "solido" // solido | contorno

    readonly property color corBase: tom.background !== undefined ? tom.background : tom.base
    readonly property color corTexto: root.variante === "contorno" ? root.corBase : (tom.content !== undefined ? tom.content : Estilo.global.textOnAccent)

    radius: Estilo.global.radius.pill
    color: root.variante === "contorno" ? "transparent" : root.corBase
    border.color: root.corBase
    border.width: root.variante === "contorno" ? Estilo.global.borderWidth.hairline : 0
    implicitWidth: rotuloTexto.implicitWidth + Estilo.global.padding.md * 2
    implicitHeight: rotuloTexto.implicitHeight + Estilo.global.padding.xs * 2

    Text {
        id: rotuloTexto

        anchors.centerIn: parent
        text: root.texto
        font.pixelSize: Estilo.global.fontSize.sm
        font.bold: true
        color: root.corTexto
    }

}
