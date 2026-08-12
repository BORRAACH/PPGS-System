import QtQuick
import QtQuick.Controls
import estilo 1.0

// Campo de texto padrão em pílula — borda muda para "corDestaque" no foco,
// mesmo padrão que Search.qml já usava. Substitui o TextField cru repetido
// em cada formulário (nome do cliente, troco, taxa de entrega...).
TextField {
    id: root

    property color corDestaque: Estilo.global.focusRing

    placeholderTextColor: Estilo.global.textPlaceholder
    font.pixelSize: Estilo.global.fontSize.lg
    topPadding: Estilo.global.padding.sm
    bottomPadding: Estilo.global.padding.sm
    leftPadding: Estilo.global.padding.lg
    rightPadding: Estilo.global.padding.lg
    color: Estilo.global.textInput
    selectByMouse: true

    background: Rectangle {
        radius: Estilo.global.radius.pill
        color: root.enabled ? Estilo.global.inputBackground : Estilo.global.inputDisabled
        border.color: root.activeFocus ? root.corDestaque : Estilo.global.border
        border.width: root.activeFocus ? Estilo.global.borderWidth.thick : Estilo.global.borderWidth.hairline
    }

}
