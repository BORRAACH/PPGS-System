import QtQuick
import QtQuick.Controls
import estilo 1.0

// Forma de pagamento + Troco (só quando "Dinheiro") + Taxa de Entrega
// (opcional, só a tela de Entrega usa) + Status (pago/não pago) —
// extraído de Balcao.qml/Entrega.qml, onde era duplicado quase
// byte-a-byte. Salão não usa este componente: não tem bloco de pagamento
// na própria tela (isso só existe em PopupFecharConta.qml, com uma linha
// por pessoa em vez de uma só — estrutura diferente, fora de escopo aqui).
//
// A cadeia de Tab/Shift+Tab interna generaliza os dois casos: quando
// mostrarTaxaEntrega é false, o campo de taxa nunca entra na cadeia (fica
// exatamente como Balcao.qml sempre foi); quando true, entra entre Troco
// e Status (exatamente como Entrega.qml sempre foi).
Row {
    id: camposPagamento

    spacing: 10

    property color corDestaque: Estilo.confirmar.normal
    property var opcoesPagamento: ["Pix", "Crédito", "Débito", "Dinheiro"]
    // Preenchimento inicial — usado pela Consulta ao reabrir uma comanda
    // salva para edição (ver itensIniciais/reconstruirComanda nas telas).
    property string formaPagamentoInicial: ""
    property string trocoInicial: ""
    property string statusPagamentoInicial: ""
    property bool mostrarTaxaEntrega: false
    property string taxaEntregaInicial: ""
    // Chamada ao dar Shift+Tab a partir do combo (o "de onde eu vim" muda
    // em tempo de execução — normalmente é o valor da última linha da
    // lista de pedidos —, por isso é uma função e não um Item fixo; mesmo
    // padrão já usado em "property var onPedidoSelecionado" em Pizzas.qml).
    property var obterCampoAnterior: null
    // Pra onde vai o Tab a partir do último campo (o spinner de cópias,
    // que mora fora deste componente).
    property Item proximoCampo: null

    property alias formaPagamento: comboFormaPagamento.currentText
    property alias troco: inputTroco.text
    property alias taxaEntrega: inputTaxaEntrega.text
    property alias pago: btnStatusPagamento.pago
    // Pra LinhaPedido.qml saber pra onde ir ao dar Tab na última linha da
    // lista, e pro spinner de cópias saber pra onde ir no Shift+Tab.
    property alias primeiroCampo: comboFormaPagamento
    property alias ultimoCampo: btnStatusPagamento

    // Restaura os campos ao estado inicial — usado ao limpar o formulário
    // depois de lançar/imprimir um pedido.
    function redefinirPadrao() {
        comboFormaPagamento.currentIndex = 0;
        inputTroco.text = "";
        inputTaxaEntrega.text = "";
        btnStatusPagamento.pago = false;
    }

    Column {
        spacing: 4

        Text {
            text: "Forma de Pagamento"
            font.pixelSize: 12
            font.bold: true
            color: Estilo.cores.textoSecundario
        }

        ComboBox {
            id: comboFormaPagamento

            width: 150
            model: camposPagamento.opcoesPagamento
            currentIndex: Math.max(0, camposPagamento.opcoesPagamento.indexOf(camposPagamento.formaPagamentoInicial))
            KeyNavigation.tab: inputTroco.visible ? inputTroco : (camposPagamento.mostrarTaxaEntrega ? inputTaxaEntrega : (btnStatusPagamento.visible ? btnStatusPagamento : camposPagamento.proximoCampo))
            // Backtab chama obterCampoAnterior() na hora, não como
            // "KeyNavigation.backtab: ..." — o alvo (normalmente a última
            // linha da lista de pedidos) muda conforme quantas linhas
            // existem agora, um binding estático travaria no valor de
            // quando o componente foi criado.
            Keys.onBacktabPressed: {
                var alvo = camposPagamento.obterCampoAnterior ? camposPagamento.obterCampoAnterior() : null;
                if (alvo)
                    alvo.forceActiveFocus();
            }

            contentItem: Text {
                text: comboFormaPagamento.displayText
                color: Estilo.cores.texto
                leftPadding: 10
                rightPadding: 10
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }

            background: Rectangle {
                radius: Estilo.rounding.padrao
                color: "#ffffff"
                border.color: comboFormaPagamento.activeFocus ? camposPagamento.corDestaque : Estilo.cores.borda
                border.width: 1
                implicitHeight: inputTroco.implicitHeight
            }
        }
    }

    // Campo Troco — só faz sentido quando o pagamento é em dinheiro.
    Column {
        spacing: 4
        visible: comboFormaPagamento.currentText === "Dinheiro"

        Text {
            text: "Troco"
            font.pixelSize: 12
            font.bold: true
            color: Estilo.cores.textoSecundario
        }

        TextField {
            id: inputTroco

            placeholderText: "TROCO PARA"
            width: 150
            topPadding: 10
            bottomPadding: 10
            leftPadding: 10
            rightPadding: 10
            text: camposPagamento.trocoInicial
            visible: comboFormaPagamento.currentText === "Dinheiro"
            KeyNavigation.tab: camposPagamento.mostrarTaxaEntrega ? inputTaxaEntrega : (btnStatusPagamento.visible ? btnStatusPagamento : camposPagamento.proximoCampo)
            KeyNavigation.backtab: comboFormaPagamento
            Keys.onReturnPressed: (camposPagamento.mostrarTaxaEntrega ? inputTaxaEntrega : (btnStatusPagamento.visible ? btnStatusPagamento : camposPagamento.proximoCampo)).forceActiveFocus()
            onEditingFinished: {
                if (text !== "") {
                    var numLimpo = text.replace("R$", "").replace(" ", "").replace(",", ".");
                    var valorFloat = parseFloat(numLimpo);
                    if (!isNaN(valorFloat))
                        text = "R$ " + valorFloat.toFixed(2).replace(".", ",");
                }
            }

            validator: DoubleValidator {
                bottom: 0
                decimals: 2
                notation: DoubleValidator.StandardNotation
            }

            background: Rectangle {
                radius: Estilo.rounding.padrao
                color: "#ffffff"
                border.color: parent.activeFocus ? camposPagamento.corDestaque : Estilo.cores.borda
                border.width: 1
            }
        }
    }

    // Campo Taxa de entrega — só a tela de Entrega liga isso (soma ao
    // valor total do pedido).
    Column {
        spacing: 4
        visible: camposPagamento.mostrarTaxaEntrega

        Text {
            text: "Taxa de Entrega"
            font.pixelSize: 12
            font.bold: true
            color: Estilo.cores.textoSecundario
        }

        TextField {
            id: inputTaxaEntrega

            placeholderText: "TAXA DE ENTREGA"
            width: 150
            topPadding: 10
            bottomPadding: 10
            leftPadding: 10
            rightPadding: 10
            text: camposPagamento.taxaEntregaInicial
            KeyNavigation.tab: btnStatusPagamento.visible ? btnStatusPagamento : camposPagamento.proximoCampo
            KeyNavigation.backtab: inputTroco.visible ? inputTroco : comboFormaPagamento
            Keys.onReturnPressed: (btnStatusPagamento.visible ? btnStatusPagamento : camposPagamento.proximoCampo).forceActiveFocus()
            onEditingFinished: {
                if (text !== "") {
                    var numLimpo = text.replace("R$", "").replace(" ", "").replace(",", ".");
                    var valorFloat = parseFloat(numLimpo);
                    if (!isNaN(valorFloat))
                        text = "R$ " + valorFloat.toFixed(2).replace(".", ",");
                }
            }

            validator: DoubleValidator {
                bottom: 0
                decimals: 2
                notation: DoubleValidator.StandardNotation
            }

            background: Rectangle {
                radius: Estilo.rounding.padrao
                color: "#ffffff"
                border.color: parent.activeFocus ? camposPagamento.corDestaque : Estilo.cores.borda
                border.width: 1
            }
        }
    }

    // Botão de status: alterna entre pago (PG) e não pago (NP). Visível
    // pra qualquer forma de pagamento, inclusive Pix — Pix não é
    // necessariamente pago na hora (ex: cliente manda o comprovante
    // depois), então também precisa poder marcar como NP nesse caso.
    Column {
        spacing: 4

        Text {
            text: "Status"
            font.pixelSize: 12
            font.bold: true
            color: Estilo.cores.textoSecundario
        }

        Button {
            id: btnStatusPagamento

            property bool pago: camposPagamento.statusPagamentoInicial === "PG"

            text: pago ? "PG" : "NP"
            width: 60
            topPadding: 10
            bottomPadding: 10
            focusPolicy: Qt.StrongFocus
            KeyNavigation.tab: camposPagamento.proximoCampo
            KeyNavigation.backtab: camposPagamento.mostrarTaxaEntrega ? inputTaxaEntrega : (inputTroco.visible ? inputTroco : comboFormaPagamento)
            Keys.onReturnPressed: clicked()
            onClicked: pago = !pago

            contentItem: Text {
                text: btnStatusPagamento.text
                font.bold: true
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: Estilo.rounding.padrao
                color: btnStatusPagamento.pago ? (parent.down ? Estilo.confirmar.pressionado : (parent.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)) : (parent.down ? Estilo.cancelar.pressionado : (parent.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal))
                // Anel de foco: só aparece navegando por teclado — sem
                // isso, Tab chegava ao botão sem nenhum sinal visual de
                // onde o foco estava.
                border.color: Estilo.cores.texto
                border.width: parent.activeFocus ? 3 : 0
            }
        }
    }
}
