import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../components"

Popup {
    id: popupSelecaoPedido

    property var onPedidoSelecionado: null
    property var pilha: null

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 25
    parent: Overlay.overlay
    anchors.centerIn: parent

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        radius: Estilo.rounding.popup
        color: Estilo.cores.fundoPagina
        border.color: Estilo.cores.bordaCard
    }

    // Modelo com o caminho da página de cada categoria
    ListModel {
        id: modeloCategorias

        ListElement {
            nome: "Pizza"
            icone: "fa6s.pizza-slice"
            cor: "#e74c3c"
            pagina: "pizzas/Pizzas.qml"
        }

        ListElement {
            nome: "Lanche"
            icone: "fa6s.burger"
            cor: "#e67e22"
            pagina: "lanches/Lanches.qml"
        }

        ListElement {
            nome: "Bebidas"
            icone: "fa6s.glass-water"
            cor: "#3498db"
            pagina: "bebidas/Bebidas.qml"
        }

        ListElement {
            nome: "Outros"
            icone: "fa6s.box"
            cor: "#9b59b6"
            pagina: "outros/Outros.qml"
        }

    }

    contentItem: Column {
        id: colunaSelecao

        spacing: 20

        Text {
            text: "Selecione a Categoria"
            font.pixelSize: Estilo.fonte.titulo
            font.bold: true
            color: Estilo.cores.texto
            anchors.horizontalCenter: parent
        }

        Grid {
            id: gradeCategorias

            width: 380
            anchors.horizontalCenter: parent
            spacing: 15
            columns: 4

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
                            // Fecha o popup e repassa a navegação adiante, para
                            // a pilha local da tela que abriu a seleção.
                            popupSelecaoPedido.close();
                            if (pilha)
                                pilha.push(model.pagina, {
                                    "pilha": pilha,
                                    "onPedidoSelecionado": function(nome, valor) {
                                        if (popupSelecaoPedido.onPedidoSelecionado)
                                            popupSelecaoPedido.onPedidoSelecionado(nome, valor);

                                    }
                                });

                        }

                        contentItem: Column {
                            anchors.centerIn: parent
                            spacing: 8

                            Icone {
                                nome: model.icone
                                cor: "#ffffff"
                                tamanho: btnCategoria.width * 0.35
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
                            radius: Estilo.rounding.medio
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
            onClicked: popupSelecaoPedido.close()

            contentItem: Text {
                text: btnCancelar.text
                font.bold: true
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: Estilo.rounding.padrao
                color: parent.down ? Estilo.cores.textoSecundario : (parent.hovered ? "#95a5a6" : Estilo.cores.textoSecundario)
            }

        }

    }

}
