import QtQuick
import QtQuick.Controls

Page {
    id: telaBalcao

    property string clienteNome: ""

    objectName: "telaBalcao"

    function mostrarNotificacao(mensagem, sucesso) {
        notificacao.texto = mensagem;
        notificacao.sucesso = sucesso;
        notificacao.aberta = true;
        timerNotificacao.restart();
    }

    // --- MODELO GLOBAL DA TELA (Agora acessível pelos Shortcuts e pela ListView) ---
    ListModel {
        id: modeloPedidos

        ListElement {
            pedido: ""
            observacao: ""
            valor: ""
        }

    }

    // --- TECLAS DE ATALHO GLOBAIS DA TELA ---
    Shortcut {
        sequence: "Ctrl+A"
        enabled: telaBalcao.visible
        onActivated: {
            modeloPedidos.append({
                "pedido": "",
                "observacao": "",
                "valor": ""
            });
        }
    }

    Shortcut {
        sequence: "Ctrl+R"
        enabled: telaBalcao.visible && modeloPedidos.count > 1
        onActivated: {
            var linhaParaRemover = -1;
            for (var i = 0; i < listaPedidos.contentItem.children.length; i++) {
                var item = listaPedidos.contentItem.children[i];
                if (item && item.children) {
                    for (var j = 0; j < item.children.length; j++) {
                        if (item.children[j].activeFocus) {
                            linhaParaRemover = i;
                            break;
                        }
                    }
                }
                if (linhaParaRemover !== -1)
                    break;

            }
            if (linhaParaRemover !== -1)
                modeloPedidos.remove(linhaParaRemover);
            else
                modeloPedidos.remove(modeloPedidos.count - 1);
        }
    }

    // --- ÁREA DE CONTEÚDO DINÂMICO ---
    // Sem barra lateral própria aqui: esta página já é empurrada para dentro
    // do StackView de main.qml, que fica ao lado da LateralBar permanente do
    // app. Carregar outra LateralBar aqui duplicava o logo "PPGS".
    StackView {
        id: stackViewLocal

        anchors.fill: parent
        initialItem: conteudoBalcaoComponent
    }

    // --- COMPONENTE DA TELA PRINCIPAL DO BALCÃO ---
    Component {
        id: conteudoBalcaoComponent

        Item {
            anchors.fill: parent

            Column {
                anchors.centerIn: parent
                spacing: 20

                Text {
                    text: "🏢 ATENDIMENTO BALCÃO"
                    font.pixelSize: 22
                    font.bold: true
                    color: "#27ae60"
                    anchors.horizontalCenter: parent
                }

                // Campo Nome do Cliente
                TextField {
                    id: inputNomeCliente

                    placeholderText: "NOME DO CLIENTE"
                    width: 420
                    topPadding: 10
                    bottomPadding: 10
                    leftPadding: 10
                    rightPadding: 10
                    anchors.horizontalCenter: parent
                    text: clienteNome

                    background: Rectangle {
                        radius: 5
                        color: "#ffffff"
                        border.color: parent.activeFocus ? "#27ae60" : "#cccccc"
                        border.width: 1
                    }

                }

                // --- LISTA DINÂMICA DE PEDIDOS ---
                ListView {
                    id: listaPedidos

                    width: 690
                    height: Math.min(count * 60, 240)
                    clip: true
                    model: modeloPedidos // Consome o modelo declarado na raiz da Page
                    spacing: 10
                    anchors.horizontalCenter: parent

                    delegate: Row {
                        id: linhaDelegate

                        spacing: 10
                        anchors.horizontalCenter: parent

                        // Campo Pedido
                        TextField {
                            id: campoPedido

                            placeholderText: "SELECIONAR PEDIDO"
                            width: 200
                            topPadding: 10
                            bottomPadding: 10
                            leftPadding: 10
                            rightPadding: 10
                            text: model.pedido
                            readOnly: true
                            hoverEnabled: true

                            MouseArea {
                                id: mouseAreaPedido

                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: {
                                    var indiceAtual = index;
                                    if (typeof stackViewLocal !== "undefined")
                                        // <-- adicionar esta linha

                                        stackViewLocal.push("../pedidos/Pedido.qml", {
                                            "pilha": stackViewLocal,
                                            "onPedidoSelecionado": function(nomePedido, valorPedido) {
                                                modeloPedidos.setProperty(indiceAtual, "pedido", nomePedido);
                                                if (valorPedido !== undefined && valorPedido !== "")
                                                    modeloPedidos.setProperty(indiceAtual, "valor", valorPedido);

                                            }
                                        });

                                }
                            }

                            background: Rectangle {
                                radius: 5
                                color: mouseAreaPedido.containsMouse ? "#f0f0f0" : "#ffffff"
                                border.color: parent.activeFocus ? "#27ae60" : "#cccccc"
                                border.width: 1
                            }

                        }

                        // Campo Observação
                        TextField {
                            id: campoObservacao

                            placeholderText: "OBSERVAÇÃO"
                            width: 180
                            topPadding: 10
                            bottomPadding: 10
                            leftPadding: 10
                            rightPadding: 10
                            text: model.observacao
                            onTextChanged: model.observacao = text

                            background: Rectangle {
                                radius: 5
                                color: "#ffffff"
                                border.color: parent.activeFocus ? "#27ae60" : "#cccccc"
                                border.width: 1
                            }

                        }

                        // Campo Valor
                        TextField {
                            id: campoValor

                            placeholderText: "R$ 0,00"
                            width: 110
                            topPadding: 10
                            bottomPadding: 10
                            leftPadding: 10
                            rightPadding: 10
                            text: model.valor
                            onEditingFinished: {
                                if (text !== "") {
                                    var numLimpo = text.replace("R$", "").replace(" ", "").replace(",", ".");
                                    var valorFloat = parseFloat(numLimpo);
                                    if (!isNaN(valorFloat)) {
                                        var formatado = "R$ " + valorFloat.toFixed(2).replace(".", ",");
                                        model.valor = formatado;
                                        text = formatado;
                                    }
                                }
                            }

                            validator: DoubleValidator {
                                bottom: 0
                                decimals: 2
                                notation: DoubleValidator.StandardNotation
                            }

                            background: Rectangle {
                                radius: 5
                                color: "#ffffff"
                                border.color: parent.activeFocus ? "#27ae60" : "#cccccc"
                                border.width: 1
                            }

                        }

                        // Botão "+"
                        Button {
                            text: "+"
                            padding: 10
                            height: campoPedido.implicitHeight
                            width: height
                            anchors.verticalCenter: parent.verticalCenter
                            visible: index === (modeloPedidos.count - 1)
                            onClicked: {
                                modeloPedidos.append({
                                    "pedido": "",
                                    "observacao": "",
                                    "valor": ""
                                });
                            }

                            background: Rectangle {
                                radius: 5
                                color: parent.down ? "#27ae60" : (parent.hovered ? "#e0e0e0" : "#ffffff")
                                border.color: "#cccccc"
                                border.width: 1
                            }

                        }

                        // Botão "-"
                        Button {
                            text: "-"
                            padding: 10
                            height: campoPedido.implicitHeight
                            width: height
                            anchors.verticalCenter: parent.verticalCenter
                            visible: modeloPedidos.count > 1
                            onClicked: {
                                modeloPedidos.remove(index);
                            }

                            background: Rectangle {
                                radius: 5
                                color: parent.down ? "#e74c3c" : (parent.hovered ? "#e0e0e0" : "#ffffff")
                                border.color: "#cccccc"
                                border.width: 1
                            }

                        }

                    }

                }

                // --- BOTÕES DE AÇÃO INFERIORES ---
                Row {
                    spacing: 15
                    anchors.horizontalCenter: parent

                    // Botão Imprimir
                    Button {
                        id: btnImprimir

                        text: "🖨️ Imprimir"
                        padding: 10
                        width: 200
                        onClicked: {
                            var itens = [];
                            for (var i = 0; i < modeloPedidos.count; i++) {
                                var item = modeloPedidos.get(i);
                                itens.push({
                                    "pedido": item.pedido,
                                    "observacao": item.observacao,
                                    "valor": item.valor
                                });
                            }

                            var dados = {
                                "cliente": inputNomeCliente.text,
                                "itens": itens
                            };

                            var sucesso = balcaoController.enviarPedido(dados);
                            if (sucesso) {
                                inputNomeCliente.text = "";
                                modeloPedidos.clear();
                                modeloPedidos.append({
                                    "pedido": "",
                                    "observacao": "",
                                    "valor": ""
                                });
                                telaBalcao.mostrarNotificacao("✅ Pedido salvo com sucesso!", true);
                            } else {
                                telaBalcao.mostrarNotificacao("❌ Erro ao salvar o pedido.", false);
                            }
                        }

                        contentItem: Text {
                            text: btnImprimir.text
                            font.bold: true
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: 5
                            color: parent.down ? "#1e8449" : (parent.hovered ? "#2ecc71" : "#27ae60")
                            border.color: "#1e8449"
                            border.width: 1
                        }

                    }

                    // Botão Voltar
                    Button {
                        id: btnVoltar

                        text: "← Voltar para o Menu"
                        padding: 10
                        width: 200
                        onClicked: {
                            if (stackViewLocal.depth > 1)
                                stackViewLocal.pop();
                            else if (telaBalcao.StackView.view)
                                telaBalcao.StackView.view.pop();
                        }

                        contentItem: Text {
                            text: btnVoltar.text
                            font.bold: true
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: 5
                            color: parent.down ? "#922b21" : (parent.hovered ? "#ec7063" : "#e74c3c")
                            border.color: "#922b21"
                            border.width: 1
                        }

                    }

                }

            }

        }

    }

    // --- NOTIFICAÇÃO TEMPORÁRIA (SUCESSO/ERRO AO SALVAR O PEDIDO) ---
    Rectangle {
        id: notificacao

        property string texto: ""
        property bool sucesso: true
        property bool aberta: false

        z: 1000
        radius: 10
        color: sucesso ? "#27ae60" : "#e74c3c"
        width: textoNotificacao.implicitWidth + 40
        height: 50
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.bottom: parent.bottom
        // Fora da tela (abaixo da borda inferior) quando fechada; sobe para a
        // margem de 20px quando aberta — o Behavior anima essa transição.
        anchors.bottomMargin: aberta ? 20 : -(height + 20)

        Behavior on anchors.bottomMargin {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }

        }

        Text {
            id: textoNotificacao

            text: notificacao.texto
            color: "#ffffff"
            font.bold: true
            font.pixelSize: 14
            anchors.centerIn: parent
        }

    }

    Timer {
        id: timerNotificacao

        interval: 2000
        repeat: false
        onTriggered: notificacao.aberta = false
    }

    background: Rectangle {
        color: "#f8f9fa"
        radius: 20
    }

}
