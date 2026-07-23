import QtQuick
import QtQuick.Controls

Page {
    id: telaSelecaoPedido

    property var onPedidoSelecionado: null
    property var pilha: null

    // Modelo com o caminho da página de cada categoria
    ListModel {
        id: modeloCategorias

        ListElement {
            nome: "Pizza"
            icone: "🍕"
            cor: "#e74c3c"
            pagina: "pizzas/Pizzas.qml"
        }

        ListElement {
            nome: "Lanche"
            icone: "🍔"
            cor: "#e67e22"
            pagina: "lanches/Lanches.qml"
        }

        ListElement {
            nome: "Bebidas"
            icone: "🥤"
            cor: "#3498db"
            pagina: "bebidas/Bebidas.qml"
        }

        ListElement {
            nome: "Outros"
            icone: "📦"
            cor: "#9b59b6"
            pagina: "outros/Outros.qml"
        }

    }

    Column {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        Text {
            text: "Selecione a Categoria"
            font.pixelSize: 22
            font.bold: true
            color: "#2c3e50"
            anchors.horizontalCenter: parent
        }

        Grid {
            id: gradeCategorias

            width: Math.min(parent.width, 480)
            anchors.horizontalCenter: parent
            spacing: 15
            columns: parent.width > 500 ? 4 : 2

            Repeater {
                model: modeloCategorias

                delegate: Item {
                    property real tamanhoBotao: (gradeCategorias.width - (gradeCategorias.spacing * (gradeCategorias.columns - 1))) / gradeCategorias.columns

                    width: tamanhoBotao
                    height: tamanhoBotao

                    Button {
                        id: btnCategoria

                        anchors.fill: parent
                        onClicked: {
                            // repassa adiante

                            pilha.push(model.pagina, {
                                "pilha": pilha,
                                "onPedidoSelecionado": function(nome, valor) {
                                    if (telaSelecaoPedido.onPedidoSelecionado)
                                        telaSelecaoPedido.onPedidoSelecionado(nome, valor);

                                }
                            });
                        }

                        contentItem: Column {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: model.icone
                                font.pixelSize: btnCategoria.width * 0.35
                                anchors.horizontalCenter: parent
                            }

                            Text {
                                text: model.nome
                                font.pixelSize: 15
                                font.bold: true
                                color: "#ffffff"
                                anchors.horizontalCenter: parent
                            }

                        }

                        background: Rectangle {
                            radius: 10
                            color: btnCategoria.down ? Qt.darker(model.cor, 1.2) : (btnCategoria.hovered ? Qt.lighter(model.cor, 1.1) : model.cor)

                            Behavior on color {
                                ColorAnimation {
                                    duration: 100
                                }

                            }

                        }

                    }

                }

            }

        }

        Button {
            id: btnCancelar

            text: "Cancelar"
            padding: 10
            width: Math.min(gradeCategorias.width, 200)
            anchors.horizontalCenter: parent
            onClicked: pilha.pop()

            contentItem: Text {
                text: btnCancelar.text
                font.bold: true
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: 5
                color: parent.down ? "#7f8c8d" : (parent.hovered ? "#95a5a6" : "#7f8c8d")
            }

        }

    }

    background: Rectangle {
        color: "#f8f9fa"
        radius: 20
    }

}
