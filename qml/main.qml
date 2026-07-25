import "./components"
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import estilo 1.0

ApplicationWindow {
    id: root

    width: 600
    height: 500
    visible: true
    color: Qt.darker(Estilo.cores.fundoPagina, 1.8)
    title: "Sistema de Pedidos"

    RowLayout {
        anchors.fill: parent
        spacing: 0

        LateralBar {
            id: lateralBar

            stackView: stackView
        }

        // ÁREA DE CONTEÚDO DINÂMICO
        Rectangle {
            id: contentContainer

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            Layout.rightMargin: 8
            color: Estilo.cores.fundoPagina // Cor de fundo do app
            radius: Estilo.rounding.popup
            clip: true // Garante o corte dos elementos internos e da sombra

            StackView {
                id: stackView

                anchors.fill: parent

                initialItem: Component {
                    Item {
                        objectName: "pageHome"
                        anchors.fill: parent

                        Column {
                            anchors.centerIn: parent
                            spacing: 25

                            Text {
                                id: textoBoasVindas

                                text: "Selecione o Tipo de Atendimento"
                                font.pixelSize: 20
                                font.bold: true
                                color: Estilo.cores.texto
                                anchors.horizontalCenter: parent
                            }

                            Row {
                                spacing: 20
                                anchors.horizontalCenter: parent

                                // Botão Balcão
                                Button {
                                    id: btnBalcao

                                    implicitWidth: 120
                                    implicitHeight: 120
                                    padding: 10
                                    onClicked: {
                                        stackView.push("pages/balcao/Balcao.qml", {});
                                    }

                                    background: Rectangle {
                                        id: bgBalcao

                                        color: btnBalcao.pressed ? "#35d97706" : (btnBalcao.hovered ? "#20d97706" : "#0ad97706")
                                        border.color: btnBalcao.hovered ? "#d97706" : "#fcd34d"
                                        border.width: 2
                                        radius: Estilo.rounding.medio

                                        MultiEffect {
                                            anchors.fill: parent
                                            source: bgBalcao
                                            shadowEnabled: true
                                            shadowColor: "#20000000"
                                            shadowBlur: btnBalcao.hovered ? 0.8 : 0.4
                                            shadowVerticalOffset: btnBalcao.pressed ? 1 : (btnBalcao.hovered ? 4 : 2)
                                            shadowHorizontalOffset: 0
                                            z: -1
                                        }
                                    }

                                    contentItem: Column {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Icone {
                                            nome: "fa6s.bag-shopping"
                                            cor: "#d97706"
                                            tamanho: 36
                                            anchors.horizontalCenter: parent
                                        }

                                        Text {
                                            text: "Balcão"
                                            font.pixelSize: Estilo.fonte.padrao
                                            font.bold: true
                                            color: btnBalcao.pressed ? "#92400e" : "#b45309"
                                            horizontalAlignment: Text.AlignHCenter
                                            anchors.horizontalCenter: parent
                                        }
                                    }
                                }

                                // Botão Entrega
                                Button {
                                    id: btnEntrega

                                    implicitWidth: 120
                                    implicitHeight: 120
                                    padding: 10
                                    onClicked: {
                                        stackView.push("pages/entrega/Entrega.qml", {});
                                    }

                                    background: Rectangle {
                                        id: bgEntrega

                                        color: btnEntrega.pressed ? "#350284c7" : (btnEntrega.hovered ? "#200284c7" : "#0a0284c7")
                                        border.color: btnEntrega.hovered ? "#0284c7" : "#7dd3fc"
                                        border.width: 2
                                        radius: Estilo.rounding.medio

                                        MultiEffect {
                                            anchors.fill: parent
                                            source: bgEntrega
                                            shadowEnabled: true
                                            shadowColor: "#20000000"
                                            shadowBlur: btnEntrega.hovered ? 0.8 : 0.4
                                            shadowVerticalOffset: btnEntrega.pressed ? 1 : (btnEntrega.hovered ? 4 : 2)
                                            shadowHorizontalOffset: 0
                                            z: -1
                                        }
                                    }

                                    contentItem: Column {
                                        anchors.centerIn: parent
                                        spacing: 8

                                        Icone {
                                            nome: "fa6s.motorcycle"
                                            cor: "#0284c7"
                                            tamanho: 36
                                            anchors.horizontalCenter: parent
                                        }

                                        Text {
                                            text: "Entrega"
                                            font.pixelSize: Estilo.fonte.padrao
                                            font.bold: true
                                            color: btnEntrega.pressed ? "#075985" : "#0369a1"
                                            horizontalAlignment: Text.AlignHCenter
                                            anchors.horizontalCenter: parent
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
