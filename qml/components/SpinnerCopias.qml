import QtQuick
import QtQuick.Controls
import estilo 1.0

// Quantas vezes "Imprimir"/"Fechar conta" pede a impressão da mesma
// comanda — extraído de Balcao.qml/Entrega.qml/PopupFecharConta.qml, onde
// era byte-a-byte idêntico exceto pela cor de destaque do foco. O rótulo
// "Cópias" continua em cada tela (um Text de 2 linhas não vale a pena
// empacotar) — só o SpinBox em si mora aqui.
SpinBox {
    id: spinnerCopias

    property color corDestaque: Estilo.confirmar.normal

    from: 1
    to: 5
    editable: true
    width: 100
    height: 42

    contentItem: TextInput {
        text: spinnerCopias.textFromValue(spinnerCopias.value, spinnerCopias.locale)
        font.pixelSize: Estilo.fonte.padrao
        color: Estilo.cores.textoInput
        horizontalAlignment: Qt.AlignHCenter
        verticalAlignment: Qt.AlignVCenter
        readOnly: !spinnerCopias.editable
        validator: spinnerCopias.validator
        selectByMouse: true
    }

    background: Rectangle {
        radius: Estilo.rounding.padrao
        color: "#ffffff"
        border.color: spinnerCopias.activeFocus ? spinnerCopias.corDestaque : Estilo.cores.borda
        border.width: spinnerCopias.activeFocus ? 2 : 1
    }
}
