import QtQuick
import QtQuick.Controls
import estilo 1.0

// Barra de pesquisa padrão usada em todas as páginas com lista pesquisável
// (Pizzas, Lanches, Bebidas, Outros, Consulta) — mesmo visual e
// comportamento de foco em todas, com a cor de destaque configurável por
// página via "corDestaque".
TextField {
    id: root

    property color corDestaque: Estilo.global.border

    height: 42
    placeholderTextColor: Estilo.global.textPlaceholder
    font.pixelSize: Estilo.global.fontSize.lg
    leftPadding: 14
    rightPadding: 14
    color: Estilo.global.textInput
    selectByMouse: true

    background: Rectangle {
        radius: Estilo.global.radius.pill
        color: root.enabled ? Estilo.global.inputBackground : Estilo.global.inputDisabled
        border.color: root.activeFocus ? root.corDestaque : Estilo.global.border
        border.width: root.activeFocus ? 2 : 1
    }
}
