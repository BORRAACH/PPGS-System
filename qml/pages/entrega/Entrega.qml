import QtQuick
import QtQuick.Controls

Page {
    id: telaEntrega

    property string clienteNome: ""

    objectName: "telaEntrega"

    background: Rectangle {
        color: "#f8f9fa"
    }

    Column {
        anchors.centerIn: parent
        spacing: 20

        Text {
            text: "🛵 PEDIDO DE ENTREGA"
            font.pixelSize: 22
            font.bold: true
            color: "#e67e22"
            anchors.horizontalCenter: parent
        }

        Text {
            text: clienteNome !== "" ? "Cliente: " + clienteNome : "Cliente não informado"
            font.pixelSize: 16
            anchors.horizontalCenter: parent
        }

        TextField {
            placeholderText: "Endereço de entrega..."
            width: 250
            anchors.horizontalCenter: parent
        }

        Button {
            text: "← Voltar para o Menu"
            width: 200
            anchors.horizontalCenter: parent

            onClicked: {
                if (telaEntrega.StackView.view)
                    telaEntrega.StackView.view.pop();
            }
        }
    }
}
