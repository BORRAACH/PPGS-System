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

    // Cor de cada categoria. Fica numa função, e não numa role do ListModel,
    // porque ListElement só aceita valores literais — uma referência a
    // Estilo.* ali dentro não compila ("cannot use script for property value").
    function corDaCategoria(chave) {
        switch (chave) {
        case "pizza":
            return Estilo.category.pizza.base;
        case "lanche":
            return Estilo.category.lanche.base;
        case "bebida":
            return Estilo.category.bebida.base;
        case "acai":
            return Estilo.category.acai.base;
        default:
            return Estilo.category.outros.base;
        }
    }

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
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    onOpened: {
        indiceFoco = 0;
        colunaSelecao.forceActiveFocus();
    }

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    // Modelo com o caminho da página de cada categoria
    ListModel {
        id: modeloCategorias

        ListElement {
            nome: "Pizza"
            icone: "fa6s.pizza-slice"
            categoria: "pizza"
            pagina: "pizzas/Pizzas.qml"
        }

        ListElement {
            nome: "Lanche"
            icone: "fa6s.burger"
            categoria: "lanche"
            pagina: "lanches/Lanches.qml"
        }

        ListElement {
            nome: "Bebidas"
            icone: "fa6s.glass-water"
            categoria: "bebida"
            pagina: "bebidas/Bebidas.qml"
        }
        
        ListElement {
            nome: "Açaí"
            icone: "fa6s.ice-cream"
            categoria: "acai"
            pagina: "acai/Acai.qml"
        }

        ListElement {
            nome: "Outros"
            icone: "fa6s.box"
            categoria: "outros"
            pagina: "outros/Outros.qml"
        }
    }

    contentItem: Column {
        id: colunaSelecao

        spacing: Estilo.global.spacing.xxl
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
            font.pixelSize: Estilo.global.fontSize.title
            font.family: Estilo.global.fontFamily.title
            color: Estilo.global.text
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Grid {
            id: gradeCategorias

            // Uma coluna por categoria enquanto todas couberem numa fila —
            // com "columns" menor que o necessário, a que sobra vai para uma
            // segunda linha (foi o que aconteceu ao entrar o Açaí, o 5º
            // item). A largura acompanha o número de colunas para o botão não
            // encolher a ponto de cortar o rótulo ("Bebidas").
            //
            // As cinco categorias em fila pedem 535px; numa janela menor que
            // isso elas passam a ocupar duas linhas em vez de vazar para fora
            // do popup — que, sendo modal, deixaria o atendente sem como
            // escolher a categoria nem como sair.
            columns: Math.max(2, Math.min(modeloCategorias.count, Responsivo.colunas(Responsivo.larguraPopup(95 * modeloCategorias.count + Estilo.global.spacing.xl * (modeloCategorias.count - 1)), 95, Estilo.global.spacing.xl)))
            width: (95 * columns) + (spacing * (columns - 1))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Estilo.global.spacing.xl

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
                                duration: Estilo.global.motion.instant
                                easing.type: Easing.OutQuad
                            }
                        }

                        contentItem: Column {
                            anchors.centerIn: parent
                            spacing: Estilo.global.spacing.sm

                            Icone {
                                nome: model.icone
                                cor: Estilo.global.textOnAccent
                                tamanho: btnCategoria.width * 0.35
                                anchors.horizontalCenter: parent.horizontalCenter
                            }

                            Text {
                                text: model.nome
                                font.pixelSize: Estilo.global.fontSize.xl
                                font.bold: true
                                color: Estilo.global.textOnAccent
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.lg
                            readonly property color corCategoria: popupSelecaoPedido.corDaCategoria(model.categoria)

                            color: btnCategoria.down ? Qt.darker(corCategoria, 1.2) : (btnCategoria.emFoco ? Qt.lighter(corCategoria, 1.1) : corCategoria)
                            border.width: btnCategoria.emFoco ? Estilo.global.borderWidth.focus : 0
                            border.color: Qt.darker(corCategoria, 0.4)

                            Behavior on color {
                                ColorAnimation {
                                    duration: Estilo.global.motion.instant
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
            padding: Estilo.global.padding.md
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
                    duration: Estilo.global.motion.instant
                    easing.type: Easing.OutQuad
                }
            }

            contentItem: Text {
                text: btnCancelar.text
                font.bold: true
                color: Estilo.global.textOnAccent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: Estilo.global.radius.sm
                color: btnCancelar.emFoco ? Estilo.action.neutral.hover : Estilo.action.neutral.base
                border.width: btnCancelar.emFoco ? Estilo.global.borderWidth.focus : 0
                border.color: Estilo.global.textOnAccent
            }
        }
    }
}
