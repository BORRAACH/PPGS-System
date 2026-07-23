import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: sideBar
    Layout.fillHeight: true
    Layout.preferredWidth: 70
    Layout.rightMargin: 5
    // Nada (texto, botão, etc.) pode ser desenhado além dos limites da
    // barra lateral — sem isso, textos mais largos que o espaço disponível
    // vazavam para fora do retângulo.
    clip: true
    // Poucos tons mais escuro que o fundo das páginas (#f8f9fa, usado em
    // Balcao.qml, Pedido.qml, Entrega.qml etc.), em vez de uma cor solta.
    color: Qt.darker("#f8f9fa", 115)

    property StackView stackView: null

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 15
        anchors.bottomMargin: 15
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 12

        // Logo / Topo
        Text {
            text: "PPGS"
            font.pixelSize: 26
            Layout.alignment: Qt.AlignHCenter
        }

        // --- CÁPSULA DE NAVEGAÇÃO PRINCIPAL (Estilo Ícones Agrupados) ---
        Rectangle {
            id: capsulaNavegacao

            Layout.fillWidth: true
            Layout.preferredHeight: colNavegacao.implicitHeight + 16
            // Levemente mais clara que o fundo do LateralBar, em vez do
            // tom azulado escuro de antes.
            color: Qt.lighter(sideBar.color, 108)
            radius: 20

            ColumnLayout {
                id: colNavegacao
                anchors.centerIn: parent
                width: parent.width - 8
                spacing: 8

                // Botão Home
                Button {
                    id: btnNavHome
                    Layout.fillWidth: true
                    implicitHeight: 44

                    background: Rectangle {
                        color: btnNavHome.hovered ? Qt.darker(capsulaNavegacao.color, 106) : "transparent"
                        radius: 12
                    }

                    contentItem: Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text { text: "🏠"; font.pixelSize: 16; anchors.horizontalCenter: parent }
                        Text { text: "Início"; font.pixelSize: 9; color: "#2c3e50"; font.bold: true; anchors.horizontalCenter: parent }
                    }

                    onClicked: {
                        if (sideBar.stackView) {
                            sideBar.stackView.pop(null)
                        }
                    }
                }

                // Botão Balcão
                Button {
                    id: btnNavBalcao
                    Layout.fillWidth: true
                    implicitHeight: 44

                    background: Rectangle {
                        color: btnNavBalcao.hovered ? Qt.darker(capsulaNavegacao.color, 106) : "transparent"
                        radius: 12
                    }

                    contentItem: Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text { text: "🛍️"; font.pixelSize: 16; anchors.horizontalCenter: parent }
                        Text { text: "Balcão"; font.pixelSize: 9; color: "#2c3e50"; font.bold: true; anchors.horizontalCenter: parent }
                    }

                    onClicked: {
                        if (sideBar.stackView && sideBar.stackView.currentItem && sideBar.stackView.currentItem.objectName !== "telaBalcao") {
                            sideBar.stackView.push("pages/balcao/Balcao.qml", {}, StackView.Immediate)
                        }
                    }
                }

                // Botão Entrega
                Button {
                    id: btnNavEntrega
                    Layout.fillWidth: true
                    implicitHeight: 44

                    background: Rectangle {
                        color: btnNavEntrega.hovered ? Qt.darker(capsulaNavegacao.color, 106) : "transparent"
                        radius: 12
                    }

                    contentItem: Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text { text: "🛵"; font.pixelSize: 16; anchors.horizontalCenter: parent }
                        Text { text: "Entrega"; font.pixelSize: 9; color: "#2c3e50"; font.bold: true; anchors.horizontalCenter: parent }
                    }

                    onClicked: {
                        if (sideBar.stackView && sideBar.stackView.currentItem && sideBar.stackView.currentItem.objectName !== "telaEntrega") {
                            sideBar.stackView.push("pages/entrega/Entrega.qml", {}, StackView.Immediate)
                        }
                    }
                }
            }
        }

        Item { Layout.fillHeight: true } // Espaçador Flexível

        // --- CÁPSULA INFERIOR (Atalhos/Rodapé estilo Imagem) ---
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: colFooter.implicitHeight + 16
            color: Qt.lighter(sideBar.color, 108)
            radius: 20

            ColumnLayout {
                id: colFooter
                anchors.centerIn: parent
                width: parent.width - 8
                spacing: 10

                Text {
                    text: "⚡"
                    font.pixelSize: 16
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "⚙️"
                    font.pixelSize: 16
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
