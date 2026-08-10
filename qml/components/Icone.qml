import QtQuick
import estilo 1.0

// Ícone da biblioteca QtAwesome (Font Awesome, Material Design Icons...),
// renderizado por services/iconProvider.py e exposto via
// "image://qtaicon/<nome>?color=<cor>" (registrado em main.py). "nome" usa
// o formato do qtawesome — ex: "fa6s.house", "fa6s.magnifying-glass" (ver
// https://github.com/spyder-ide/qtawesome para a lista completa).
Image {
    id: root

    property string nome: ""
    property color cor: Estilo.global.text
    property int tamanho: 20

    source: nome ? "image://qtaicon/" + nome + "?color=" + encodeURIComponent(String(cor)) : ""
    sourceSize.width: tamanho
    sourceSize.height: tamanho
    width: tamanho
    height: tamanho
    fillMode: Image.PreserveAspectFit
    smooth: true
}
