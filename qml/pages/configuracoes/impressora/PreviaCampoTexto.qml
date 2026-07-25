import QtQuick
import estilo 1.0

// Um "campo" de texto da prévia da comanda (ver EstiloImpressora.qml),
// estilizado de acordo com a configuração atual do campo indicado —
// negrito/sublinhado refletidos via font, fundo preto via cor de fundo +
// texto branco (o modo reverso real da impressora), e tamanho de fonte via
// o mesmo multiplicador ESC/POS (1x-8x) que realmente sai impresso — não o
// valor em pixels puro, pra prévia não prometer uma granularidade que a
// impressora não tem.
Rectangle {
    id: raizCampo

    property var controlador
    property string campo: ""
    property string texto: ""
    property int tamanhoBase: 12

    // Cada propriedade lê controlador.versaoConfig como argumento de
    // obterAtributoReativo()/obterTamanhoFonteReativo() (ver
    // EstiloImpressora.qml) — sem isso, mudanças feitas no popup (em outra
    // instância de componente) não chegariam a esta prévia, já que
    // configAtual é um objeto JS comum e mutá-lo não emite sinal de mudança
    // de propriedade sozinho.
    readonly property bool _negrito: !!(controlador && controlador.obterAtributoReativo(campo, "negrito", controlador.versaoConfig))
    readonly property bool _sublinhado: !!(controlador && controlador.obterAtributoReativo(campo, "sublinhado", controlador.versaoConfig))
    readonly property bool _fundoPreto: !!(controlador && controlador.obterAtributoReativo(campo, "fundo_preto", controlador.versaoConfig))
    readonly property int _multiplicador: controlador ? controlador.multiplicadorFonte(controlador.obterTamanhoFonteReativo(campo, controlador.versaoConfig)) : 1

    implicitWidth: rotulo.implicitWidth + (_fundoPreto ? 8 : 0)
    implicitHeight: rotulo.implicitHeight + (_fundoPreto ? 2 : 0)
    color: _fundoPreto ? "#000000" : "transparent"

    Text {
        id: rotulo

        anchors.centerIn: parent
        text: raizCampo.texto
        font.family: "monospace"
        font.bold: raizCampo._negrito
        font.underline: raizCampo._sublinhado
        font.pixelSize: raizCampo.tamanhoBase * raizCampo._multiplicador
        color: raizCampo._fundoPreto ? "#ffffff" : Estilo.cores.texto
    }
}
