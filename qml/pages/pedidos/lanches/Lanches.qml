import QtQuick
import QtQuick.Controls

Page {
    id: telaLanches

    property var onPedidoSelecionado: null

    background: Rectangle {
        color: "#f8f9fa"
        radius: 20
    }

    ListModel {
        id: modeloLanches
        ListElement { nome: "X-Burguer"; valor: "22,00" }
        ListElement { nome: "X-Salada"; valor: "25,50" }
        ListElement { nome: "X-Bacon"; valor: "29,90" }
        ListElement { nome: "X-Tudo"; valor: "34,90" }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        Text {
            text: "🍔 Escolha o Lanche"
            font.pixelSize: 22
            font.bold: true
            color: "#e67e22"
            anchors.horizontalCenter: parent
        }

        ListView {
            width: Math.min(parent.width, 400)
            height: parent.height - 120
            anchors.horizontalCenter: parent
            model: modeloLanches
            spacing: 10
            clip: true

            delegate: Button {
                id: btnItem
                width: parent.width
                padding: 12

                onClicked: {
                    if (onPedidoSelecionado) {
                        onPedidoSelecionado(model.nome, "R$ " + model.valor);
                    }

                    var telaBalcao = stackView.find(function(item) {
                        return item.objectName === "telaBalcao";
                    });

                    if (telaBalcao) {
                        stackView.pop(telaBalcao);
                    } else {
                        stackView.pop();
                    }
                }

                contentItem: Row {
                    spacing: 10
                    Text {
                        text: model.nome
                        font.pixelSize: 16
                        font.bold: true
                        color: "#2c3e50"
                        width: btnItem.width - 120
                        elide: Text.ElideRight
                    }
                    Text {
                        text: "R$ " + model.valor
                        font.pixelSize: 16
                        color: "#27ae60"
                        font.bold: true
                    }
                }

                background: Rectangle {
                    radius: 8
                    color: btnItem.down ? "#e0e0e0" : (btnItem.hovered ? "#f1f1f1" : "#ffffff")
                    border.color: "#cccccc"
                    border.width: 1
                }
            }
        }

        Button {
            text: "Voltar"
            anchors.horizontalCenter: parent
            onClicked: stackView.pop()
        }
    }
}
