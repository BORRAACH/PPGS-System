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

    spacing: Estilo.global.spacing.md

    // Quanto de largura a página tem para oferecer a este bloco. -1 (padrão)
    // significa "sem restrição": os campos ficam com os 150px de sempre, e as
    // telas que não passam nada continuam idênticas ao que eram. Quando a
    // página informa um limite, os campos dividem esse espaço entre si em vez
    // de a linha inteira transbordar — são até quatro (forma, troco, taxa,
    // status) e, na Entrega, os 150 fixos somavam mais que a tela toda de um
    // tablet.
    property real larguraDisponivel: -1
    // Quantos campos de texto/combo estão realmente em cena agora: troco só
    // aparece no pagamento em dinheiro, taxa só na Entrega.
    readonly property int _camposLargos: 1 + (comboFormaPagamento.currentText === "Dinheiro" ? 1 : 0) + (mostrarTaxaEntrega ? 1 : 0)
    // O status é um botão estreito de largura fixa (60) e fica de fora do
    // rateio; o resto do espaço é dividido igualmente entre os campos largos.
    readonly property int larguraCampo: larguraDisponivel < 0 ? 150 : Math.max(100, Math.min(150, Math.floor((larguraDisponivel - 60 - spacing * _camposLargos) / _camposLargos)))

    // A altura de TODOS os controles desta linha, tirada de um campo de texto:
    // é ele quem manda, porque a altura dele sai da fonte do app mais os 10+10
    // de padding, e é o que o resto da tela também usa.
    //
    // Os outros três precisam ser mandados: o combo tem uma conta de altura
    // própria (ver ComboBoxPagamento.alturaCampo) e o botão de status escreve
    // na fonte de TÍTULO, cuja linha é um pixel mais baixa que a do corpo —
    // sem isto ele saía um pixel menor que os campos ao lado.
    readonly property real alturaCampo: inputTroco.implicitHeight

    property color corDestaque: Estilo.action.confirm.base
    property var opcoesPagamento: ["Pix", "Crédito", "Débito", "Dinheiro"]
    // Forma de pagamento já selecionada quando o formulário abre limpo. É
    // separada da ORDEM de opcoesPagamento de propósito: a ordem é a que
    // aparece na lista do combo, e mudar o padrão não deveria bagunçá-la.
    //
    // Precisa acompanhar comandaParserService.FORMA_PAGAMENTO_PADRAO: é por
    // ela que eh_suspeita reconhece uma comanda em que ninguém tocou no bloco
    // de pagamento (sem nome + não pago + forma padrão). Se as duas
    // divergirem, comandas assim deixam de ser sinalizadas em
    // Consulta/Fechamento.
    property string formaPagamentoPadrao: "Dinheiro"
    readonly property int _indicePadrao: Math.max(0, camposPagamento.opcoesPagamento.indexOf(camposPagamento.formaPagamentoPadrao))
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
        comboFormaPagamento.currentIndex = camposPagamento._indicePadrao;
        inputTroco.text = "";
        inputTaxaEntrega.text = "";
        btnStatusPagamento.pago = false;
    }

    // O contrário de redefinirPadrao: repõe valores guardados — usado ao
    // retomar um rascunho (ver services/rascunhosPedido.py e a faixa no topo
    // de Balcão/Entrega).
    //
    // Escreve nos campos, e não nas properties "*Inicial": elas só valem
    // enquanto os bindings iniciais estiverem de pé, e redefinirPadrao() os
    // quebra na primeira chamada ao atribuir ".text" direto. Uma tela que já
    // lançou um pedido não conseguiria mais restaurar nada por ali.
    //
    // Forma vazia (ou desconhecida) cai no padrão, mesma regra do
    // currentIndex inicial — um rascunho gravado por uma versão do app com
    // outras formas de pagamento não deixa o combo em branco.
    function aplicarValores(forma, troco, pago, taxaEntrega) {
        var indice = camposPagamento.opcoesPagamento.indexOf(forma || "");
        comboFormaPagamento.currentIndex = indice >= 0 ? indice : camposPagamento._indicePadrao;
        inputTroco.text = troco || "";
        inputTaxaEntrega.text = taxaEntrega || "";
        btnStatusPagamento.pago = pago === true;
    }

    Column {
        spacing: 4

        Text {
            text: "Forma de Pagamento"
            font.pixelSize: Estilo.global.fontSize.sm
            font.bold: true
            color: Estilo.global.textSecondary
        }

        ComboBoxPagamento {
            id: comboFormaPagamento

            width: camposPagamento.larguraCampo
            corDestaque: camposPagamento.corDestaque
            alturaCampo: camposPagamento.alturaCampo
            model: camposPagamento.opcoesPagamento
            // Reabrir uma comanda salva manda a forma dela em
            // formaPagamentoInicial; formulário limpo (string vazia, que o
            // indexOf não acha) cai no padrão.
            currentIndex: {
                var indice = camposPagamento.opcoesPagamento.indexOf(camposPagamento.formaPagamentoInicial);
                return indice >= 0 ? indice : camposPagamento._indicePadrao;
            }
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
        }
    }

    // Campo Troco — só faz sentido quando o pagamento é em dinheiro.
    Column {
        spacing: 4
        visible: comboFormaPagamento.currentText === "Dinheiro"

        Text {
            text: "Troco"
            font.pixelSize: Estilo.global.fontSize.sm
            font.bold: true
            color: Estilo.global.textSecondary
        }

        TextField {
            id: inputTroco

            color: Estilo.global.textInput
            placeholderTextColor: Estilo.global.textPlaceholder
            placeholderText: "TROCO PARA"
            width: camposPagamento.larguraCampo
            topPadding: 10
            bottomPadding: 10
            leftPadding: 10
            rightPadding: 10
            text: camposPagamento.trocoInicial
            visible: comboFormaPagamento.currentText === "Dinheiro"
            KeyNavigation.tab: camposPagamento.mostrarTaxaEntrega ? inputTaxaEntrega : (btnStatusPagamento.visible ? btnStatusPagamento : camposPagamento.proximoCampo)
            KeyNavigation.backtab: comboFormaPagamento
            Keys.onReturnPressed: (camposPagamento.mostrarTaxaEntrega ? inputTaxaEntrega : (btnStatusPagamento.visible ? btnStatusPagamento : camposPagamento.proximoCampo)).forceActiveFocus()
            onEditingFinished: text = Moeda.formatar(text)

            validator: Moeda.validador

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: Estilo.global.inputBackground
                border.color: parent.activeFocus ? camposPagamento.corDestaque : Estilo.global.border
                // Engrossa no foco, como o combo ao lado e como os campos do
                // Salão — é o que o token diz ("thick: ênfase e input em
                // foco"). Antes só a cor mudava aqui, e o campo em foco ficava
                // visivelmente mais fraco que o combo em foco.
                border.width: parent.activeFocus ? Estilo.global.borderWidth.thick : Estilo.global.borderWidth.hairline
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
            font.pixelSize: Estilo.global.fontSize.sm
            font.bold: true
            color: Estilo.global.textSecondary
        }

        TextField {
            id: inputTaxaEntrega

            color: Estilo.global.textInput
            placeholderTextColor: Estilo.global.textPlaceholder
            placeholderText: "TAXA DE ENTREGA"
            width: camposPagamento.larguraCampo
            topPadding: 10
            bottomPadding: 10
            leftPadding: 10
            rightPadding: 10
            text: camposPagamento.taxaEntregaInicial
            KeyNavigation.tab: btnStatusPagamento.visible ? btnStatusPagamento : camposPagamento.proximoCampo
            KeyNavigation.backtab: inputTroco.visible ? inputTroco : comboFormaPagamento
            Keys.onReturnPressed: (btnStatusPagamento.visible ? btnStatusPagamento : camposPagamento.proximoCampo).forceActiveFocus()
            onEditingFinished: text = Moeda.formatar(text)

            validator: Moeda.validador

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: Estilo.global.inputBackground
                border.color: parent.activeFocus ? camposPagamento.corDestaque : Estilo.global.border
                // Engrossa no foco, como o combo ao lado e como os campos do
                // Salão — é o que o token diz ("thick: ênfase e input em
                // foco"). Antes só a cor mudava aqui, e o campo em foco ficava
                // visivelmente mais fraco que o combo em foco.
                border.width: parent.activeFocus ? Estilo.global.borderWidth.thick : Estilo.global.borderWidth.hairline
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
            font.pixelSize: Estilo.global.fontSize.sm
            font.bold: true
            color: Estilo.global.textSecondary
        }

        Button {
            id: btnStatusPagamento

            property bool pago: camposPagamento.statusPagamentoInicial === "PG"

            text: pago ? "PG" : "NP"
            width: 60
            height: camposPagamento.alturaCampo
            topPadding: 10
            bottomPadding: 10
            focusPolicy: Qt.StrongFocus
            KeyNavigation.tab: camposPagamento.proximoCampo
            KeyNavigation.backtab: camposPagamento.mostrarTaxaEntrega ? inputTaxaEntrega : (inputTroco.visible ? inputTroco : comboFormaPagamento)
            Keys.onReturnPressed: clicked()
            onClicked: pago = !pago

            contentItem: Text {
                text: btnStatusPagamento.text
                font.family: Estilo.global.fontFamily.title
                color: Estilo.global.textOnAccent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: btnStatusPagamento.pago ? (parent.down ? Estilo.action.confirm.pressed : (parent.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)) : (parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base))
                // Anel de foco: só aparece navegando por teclado — sem
                // isso, Tab chegava ao botão sem nenhum sinal visual de
                // onde o foco estava.
                border.color: Estilo.global.text
                border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : 0
            }
        }
    }
}
