import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../components"

Popup {
    id: popupSelecaoPedido

    property var onPedidoSelecionado: null
    property var pilha: null
    // Índice do item em foco: 0..N-1 são as categorias, N é o botão Cancelar
    property int indiceFoco: 0
    readonly property int totalFocaveis: modeloCategorias.count + 1
    // Repassado pra pizzas/Pizzas.qml (só ela usa) — false em Salao.qml, já
    // que promoção de pizza não vale pra comanda de mesa. As demais
    // categorias não recebem essa prop (ver acionarItem): incluí-la no
    // push delas gera aviso de "propriedade inexistente" em tempo de
    // execução, já que elas não a declaram.
    property bool usarPromocoes: true
    // Repassado pra bebidas/Bebidas.qml (só ela usa) — true só em Salao.qml,
    // já que alguns itens de bebida têm um preço maior específico pra
    // comanda de mesa (ver Bebidas.qml:comandaDeMesa/precoEfetivo). Mesmo
    // motivo de usarPromocoes: as demais categorias não declaram esta prop.
    property bool comandaDeMesa: false

    // Abre a categoria correspondente ao índice, ou fecha se for o Cancelar
    function acionarItem(indice) {
        if (indice >= modeloCategorias.count) {
            popupSelecaoPedido.close();
            return;
        }
        var pagina = modeloCategorias.get(indice).pagina;
        var props = {
            "pilha": pilha,
            "onPedidoSelecionado": function (nome, valor) {
                if (popupSelecaoPedido.onPedidoSelecionado)
                    popupSelecaoPedido.onPedidoSelecionado(nome, valor);
            }
        };
        if (pagina === "pizzas/Pizzas.qml")
            props["usarPromocoes"] = popupSelecaoPedido.usarPromocoes;
        else if (pagina === "bebidas/Bebidas.qml")
            props["comandaDeMesa"] = popupSelecaoPedido.comandaDeMesa;
        // Fecha o popup e repassa a navegação adiante, para
        // a pilha local da tela que abriu a seleção.
        popupSelecaoPedido.close();
        if (pilha)
            pilha.push(pagina, props);
    }

    function moverFoco(passo) {
        indiceFoco = (indiceFoco + passo + totalFocaveis) % totalFocaveis;
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 25
    parent: Overlay.overlay
    anchors.centerIn: parent
    onOpened: {
        indiceFoco = 0;
        colunaSelecao.forceActiveFocus();
    }

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
            nome: "Açaí"
            icone: "fa6s.ice-cream"
            cor: "#8e44ad"
            pagina: "acai/Acai.qml"
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
        focus: true
        // Navegação por teclado: TAB / SHIFT+TAB percorrem os itens e
        // ENTER (ou espaço) aciona o item em foco.
        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                popupSelecaoPedido.moverFoco(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Tab) {
                popupSelecaoPedido.moverFoco(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                popupSelecaoPedido.acionarItem(popupSelecaoPedido.indiceFoco);
                event.accepted = true;
            }
        }

        Text {
            text: "Selecione a Categoria"
            font.pixelSize: Estilo.fonte.titulo
            font.bold: true
            color: Estilo.cores.texto
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Grid {
            id: gradeCategorias

            // Uma coluna por categoria: com "columns" menor que o número de
            // categorias, a última sobra sozinha numa segunda linha alinhada
            // à esquerda (foi o que aconteceu ao entrar o Açaí, o 5º item).
            // A largura acompanha o número de categorias para o botão não
            // encolher a ponto de cortar o rótulo ("Bebidas").
            columns: modeloCategorias.count
            width: (95 * columns) + (spacing * (columns - 1))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 15

            Repeater {
                model: modeloCategorias

                delegate: Item {
                    property real tamanhoBotao: (gradeCategorias.width - (gradeCategorias.spacing * (gradeCategorias.columns - 1))) / gradeCategorias.columns

                    width: tamanhoBotao
                    height: tamanhoBotao

                    Button {
                        id: btnCategoria

                        readonly property bool emFoco: popupSelecaoPedido.indiceFoco === index

                        anchors.fill: parent
                        // O foco de teclado é controlado pelo popup, então o
                        // botão não deve capturá-lo e quebrar a ordem do TAB.
                        focusPolicy: Qt.NoFocus
                        // O item em foco cresce, em vez de encolher por causa
                        // da borda desenhada para dentro do retângulo.
                        scale: emFoco ? 1.1 : 1
                        z: emFoco ? 1 : 0
                        onHoveredChanged: {
                            if (hovered)
                                popupSelecaoPedido.indiceFoco = index;
                        }
                        onClicked: popupSelecaoPedido.acionarItem(index)

                        Behavior on scale {
                            NumberAnimation {
                                duration: 100
                                easing.type: Easing.OutQuad
                            }
                        }

                        contentItem: Column {
                            anchors.centerIn: parent
                            spacing: 8

                            Icone {
                                nome: model.icone
                                cor: "#ffffff"
                                tamanho: btnCategoria.width * 0.35
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: model.nome
                                font.pixelSize: 15
                                font.bold: true
                                color: "#ffffff"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.medio
                            color: btnCategoria.down ? Qt.darker(model.cor, 1.2) : (btnCategoria.emFoco ? Qt.lighter(model.cor, 1.1) : model.cor)
                            border.width: btnCategoria.emFoco ? 3 : 0
                            border.color: Qt.darker(modeloCategorias.cor, 0.4)

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

            readonly property bool emFoco: popupSelecaoPedido.indiceFoco === modeloCategorias.count

            text: "Cancelar"
            padding: 10
            width: Math.min(gradeCategorias.width, 200)
            anchors.horizontalCenter: parent.horizontalCenter
            focusPolicy: Qt.NoFocus
            scale: emFoco ? 1.1 : 1
            onHoveredChanged: {
                if (hovered)
                    popupSelecaoPedido.indiceFoco = modeloCategorias.count;
            }
            onClicked: popupSelecaoPedido.close()

            Behavior on scale {
                NumberAnimation {
                    duration: 100
                    easing.type: Easing.OutQuad
                }
            }

            contentItem: Text {
                text: btnCancelar.text
                font.bold: true
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: Estilo.rounding.padrao
                color: btnCancelar.emFoco ? "#95a5a6" : Estilo.cores.textoSecundario
                border.width: btnCancelar.emFoco ? 3 : 0
                border.color: "#ffffff"
            }
        }
    }
}
