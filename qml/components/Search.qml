import QtQuick
import QtQuick.Controls
import estilo 1.0

// Barra de pesquisa padrão usada em todas as páginas com lista pesquisável
// (Pizzas, Lanches, Bebidas, Outros, Consulta) — mesmo visual e
// comportamento de foco em todas, com a cor de destaque configurável por
// página via "corDestaque".
TextField {
    id: root

    property color corDestaque: Estilo.cores.borda

    height: 42
    placeholderTextColor: "#95a5a6"
    font.pixelSize: Estilo.fonte.padrao
    leftPadding: 14
    rightPadding: 14
    color: Estilo.cores.texto
    selectByMouse: true

    background: Rectangle {
        radius: Estilo.rounding.grande
        color: root.enabled ? "#ffffff" : "#f0f0f0"
        border.color: root.activeFocus ? root.corDestaque : Estilo.cores.borda
        border.width: root.activeFocus ? 2 : 1
    }
}
