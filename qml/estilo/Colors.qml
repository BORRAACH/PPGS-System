pragma Singleton
import QtQuick

// Paleta "Organic" (design system) — singleton global de cores para o Qt Quick.
// Uso: import <Modulo> 1.0  ->  Colors.background, Colors.accent500, etc.
QtObject {
    id: root

    // Base
    readonly property color background: "#f5ead8"
    readonly property color surface: "#ebddc5"
    readonly property color text: "#201e1d"
    readonly property color divider: Qt.rgba(root.text.r, root.text.g, root.text.b, 0.2) // texto a 20% de opacidade

    // Terracota (accent)
    readonly property color accent100: "#fff2eb"
    readonly property color accent500: "#d67f48"
    readonly property color accent600: "#b2622d"
    readonly property color accent700: "#8c491a"
    readonly property color accent800: "#643312"

    // Sage (accent2)
    readonly property color accent2_100: "#f0fae1"
    readonly property color accent2_600: "#728157"
    readonly property color accent2_800: "#3d472b"
}
