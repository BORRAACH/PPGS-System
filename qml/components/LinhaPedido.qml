import QtQuick
import QtQuick.Controls
import estilo 1.0

// Linha de item do pedido (pedido/observação/valor) — usado como delegate
// da lista de itens em Balcao.qml/Entrega.qml/Salao.qml, onde era
// duplicado byte-a-byte exceto pela cor de destaque e pelos campos de
// fuga da navegação por teclado (o que fica fora da lista, quando o foco
// sai da primeira/última linha — muda por tela: cliente/forma de
// pagamento no Balcão, observação/forma de pagamento na Entrega,
// mesa/salvar no Salão).
Row {
    id: linhaDelegate

    spacing: 10
    anchors.horizontalCenter: parent

    property alias campoPedido: campoPedido
    property alias campoObservacao: campoObservacao
    property alias campoValor: campoValor
    property color corDestaque: Estilo.confirmar.normal
    // Alvo de foco quando esta é a PRIMEIRA linha e o usuário dá
    // Shift+Tab a partir do campo Pedido.
    property Item campoExternoAnterior: null
    // Alvo de foco quando esta é a ÚLTIMA linha e o usuário dá Tab/Enter
    // a partir do campo Valor.
    property Item campoExternoProximo: null

    // Pedida a seleção de um pedido pro índice desta linha (clique ou
    // Enter no campo Pedido, somente-leitura) — quem instancia decide o
    // que fazer (abrir o popup de seleção, guardar o índice em edição),
    // já que isso depende de ids que só existem na página (telaBalcao/
    // popupSelecaoPedido), fora do alcance deste componente.
    signal selecionarPedido(int indice)

    // Vizinhos dinâmicos: cada linha é uma instância separada deste
    // delegate, então não dá pra referenciar "a linha de baixo" por id —
    // o número de linhas muda em tempo de execução, daí o lookup por
    // índice via ListView.view.
    function campoPedidoAnterior() {
        if (index > 0) {
            var linha = ListView.view.itemAtIndex(index - 1);
            if (linha)
                return linha.campoValor;
        }
        return linhaDelegate.campoExternoAnterior;
    }

    function campoPedidoProximo() {
        if (index + 1 < ListView.view.count) {
            var linha = ListView.view.itemAtIndex(index + 1);
            if (linha)
                return linha.campoPedido;
        }
        return linhaDelegate.campoExternoProximo;
    }

    // Campo Pedido
    TextField {
        id: campoPedido

        color: Estilo.cores.textoInput
        placeholderTextColor: Estilo.cores.placeholderInput
        placeholderText: "SELECIONAR PEDIDO"
        width: 200
        topPadding: 10
        bottomPadding: 10
        leftPadding: 10
        rightPadding: 10
        text: model.pedido
        readOnly: true
        hoverEnabled: true
        KeyNavigation.tab: campoObservacao
        // Backtab chama campoPedidoAnterior() na hora, não como
        // "KeyNavigation.backtab: ..." — ver o comentário na função sobre
        // por que um binding com itemAtIndex() fica preso.
        Keys.onBacktabPressed: linhaDelegate.campoPedidoAnterior().forceActiveFocus()
        // Enter abre a seleção — mesmo efeito do clique do mouse, já que
        // o campo é somente leitura.
        Keys.onReturnPressed: linhaDelegate.selecionarPedido(index)

        MouseArea {
            id: mouseAreaPedido

            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: linhaDelegate.selecionarPedido(index)
        }

        background: Rectangle {
            radius: Estilo.rounding.padrao
            color: mouseAreaPedido.containsMouse ? "#f0f0f0" : "#ffffff"
            border.color: parent.activeFocus ? linhaDelegate.corDestaque : Estilo.cores.borda
            border.width: 1
        }
    }

    // Campo Observação
    TextField {
        id: campoObservacao

        color: Estilo.cores.textoInput
        placeholderTextColor: Estilo.cores.placeholderInput
        placeholderText: "OBSERVAÇÃO"
        width: 180
        topPadding: 10
        bottomPadding: 10
        leftPadding: 10
        rightPadding: 10
        text: model.observacao
        onTextChanged: model.observacao = text
        KeyNavigation.tab: campoValor
        KeyNavigation.backtab: campoPedido
        Keys.onReturnPressed: campoValor.forceActiveFocus()

        background: Rectangle {
            radius: Estilo.rounding.padrao
            color: "#ffffff"
            border.color: parent.activeFocus ? linhaDelegate.corDestaque : Estilo.cores.borda
            border.width: 1
        }
    }

    // Campo Valor
    TextField {
        id: campoValor

        color: Estilo.cores.textoInput
        placeholderTextColor: Estilo.cores.placeholderInput
        placeholderText: "R$ 0,00"
        width: 110
        topPadding: 10
        bottomPadding: 10
        leftPadding: 10
        rightPadding: 10
        text: model.valor
        KeyNavigation.backtab: campoObservacao
        // Tab chama campoPedidoProximo() na hora, não como
        // "KeyNavigation.tab: ..." — mesmo motivo do Backtab do campo
        // Pedido.
        Keys.onTabPressed: linhaDelegate.campoPedidoProximo().forceActiveFocus()
        Keys.onReturnPressed: linhaDelegate.campoPedidoProximo().forceActiveFocus()
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
            radius: Estilo.rounding.padrao
            color: "#ffffff"
            border.color: parent.activeFocus ? linhaDelegate.corDestaque : Estilo.cores.borda
            border.width: 1
        }
    }

    // Botão "+" — só na última linha, adiciona uma linha em branco.
    //
    // "linhaDelegate.ListView.view", não "ListView.view" sozinho: a
    // propriedade anexada ListView só é populada automaticamente na RAIZ
    // do delegate (linhaDelegate) — um item aninhado dentro dele (como
    // este Button) tem seu próprio contexto de propriedade anexada, vazio,
    // então "ListView.view" solto aqui sempre voltava null (TypeError ao
    // ler ".count"/".model"). Qualificar com o id da raiz força a consulta
    // na propriedade anexada correta.
    Button {
        text: "+"
        padding: 10
        height: campoPedido.implicitHeight
        width: height
        anchors.verticalCenter: parent.verticalCenter
        visible: index === (linhaDelegate.ListView.view.count - 1)
        onClicked: {
            linhaDelegate.ListView.view.model.append({
                "pedido": "",
                "observacao": "",
                "valor": "",
                // String JSON, não objeto/array — ver o comentário no
                // ListElement de Balcao.qml/Entrega.qml/Salao.qml.
                "borda": "null",
                "adicionais": "[]"
            });
        }

        background: Rectangle {
            radius: Estilo.rounding.padrao
            color: parent.down ? linhaDelegate.corDestaque : (parent.hovered ? Estilo.cores.bordaCard : "#ffffff")
            border.color: Estilo.cores.borda
            border.width: 1
        }
    }

    // Botão "-" — remove esta linha, exceto quando é a única.
    Button {
        text: "-"
        padding: 10
        height: campoPedido.implicitHeight
        width: height
        anchors.verticalCenter: parent.verticalCenter
        visible: linhaDelegate.ListView.view.count > 1
        onClicked: {
            linhaDelegate.ListView.view.model.remove(index);
        }

        background: Rectangle {
            radius: Estilo.rounding.padrao
            color: parent.down ? Estilo.cancelar.normal : (parent.hovered ? Estilo.cores.bordaCard : "#ffffff")
            border.color: Estilo.cores.borda
            border.width: 1
        }
    }
}
