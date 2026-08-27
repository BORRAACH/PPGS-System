import QtQuick
import QtQuick.Controls
import estilo 1.0
import "Texto.js" as Texto

// Linha de item do pedido (pedido/observação/valor) — usado como delegate
// da lista de itens em Balcao.qml/Entrega.qml/Salao.qml, onde era
// duplicado byte-a-byte exceto pela cor de destaque e pelos campos de
// fuga da navegação por teclado (o que fica fora da lista, quando o foco
// sai da primeira/última linha — muda por tela: cliente/forma de
// pagamento no Balcão, observação/forma de pagamento na Entrega,
// mesa/salvar no Salão).
Row {
    id: linhaDelegate

    spacing: Estilo.global.spacing.md

    // Largura das três colunas. Calculada a partir da largura da lista que
    // hospeda esta linha, pela mesma função que a página usa para desenhar o
    // cabeçalho — é o que garante que rótulo e campo continuem um em cima do
    // outro em qualquer tamanho de tela (ver Responsivo.gradePedido).
    // O fallback de 690 é a largura original da lista, e só vale no instante
    // em que o delegate existe antes de a view ter medida.
    readonly property var grade: Responsivo.gradePedido(ListView.view ? ListView.view.width : 690)

    property alias campoPedido: campoPedido
    property alias campoObservacao: campoObservacao
    property alias campoValor: campoValor
    property color corDestaque: Estilo.action.confirm.base
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

    // Normaliza o que foi digitado no campo Valor e devolve pro modelo, que
    // é de onde saem tanto o total da tela (components/ResumoComanda.qml)
    // quanto o valor impresso na comanda — escrever só no `text` do campo
    // deixaria os dois discordando do que está na tela.
    function aplicarValorDigitado(campo) {
        model.valor = Moeda.formatar(campo.text);

        // Digitar desfaz o vínculo "text: model.valor" — a partir da
        // primeira tecla, quem manda no text é o usuário. Sem restabelecer o
        // vínculo aqui, escolher outro pedido NESTA linha depois de editar o
        // preço à mão não atualizaria mais o campo: ele ficaria preso no
        // último valor digitado, mostrando um preço que não é o do item.
        campo.text = Qt.binding(function () {
            return model.valor;
        });
    }

    // Campo Pedido
    TextField {
        id: campoPedido

        color: Estilo.global.textInput
        placeholderTextColor: Estilo.global.textPlaceholder
        placeholderText: "SELECIONAR PEDIDO"
        width: linhaDelegate.grade.pedido
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
            radius: Estilo.global.radius.pill
            color: mouseAreaPedido.containsMouse ? Estilo.global.surfaceHover : Estilo.global.inputBackground
            border.color: parent.activeFocus ? linhaDelegate.corDestaque : Estilo.global.border
            border.width: Estilo.global.borderWidth.hairline
        }
    }

    // Campo Observação
    TextField {
        id: campoObservacao

        color: Estilo.global.textInput
        placeholderTextColor: Estilo.global.textPlaceholder
        placeholderText: "OBSERVAÇÃO"
        width: linhaDelegate.grade.observacao
        topPadding: 10
        bottomPadding: 10
        leftPadding: 10
        rightPadding: 10
        text: model.observacao
        // So a primeira letra da frase (ver capitalizarFrase em Texto.js):
        // "sem cebola e sem azeitona" vira "Sem cebola e sem azeitona", e nao
        // "Sem Cebola E Sem Azeitona" — capitalizar cada palavra deixaria mais
        // dificil de ler justamente a linha que a cozinha le com pressa.
        //
        // Aplicada escrevendo no MODEL, e nao atribuindo "text" como fazem os
        // campos de nome e endereco: aqui o binding "text: model.observacao"
        // continua vivo mesmo depois de digitar, e e o model que a comanda
        // impressa le. Passar por "text" quebraria o binding e deixaria duas
        // fontes para o mesmo dado, com o campo e o model livres para
        // discordar — e quem discordasse em silencio seria o papel.
        //
        // O cursor e devolvido na mao porque a volta pelo binding reposiciona o
        // campo no fim: sem isso, corrigir a primeira letra de uma observacao
        // ja escrita jogaria a proxima tecla para o final da linha.
        onTextChanged: {
            var formatado = Texto.capitalizarFrase(text);
            if (formatado === text) {
                model.observacao = text;
                return;
            }

            var cursor = cursorPosition;
            model.observacao = formatado;
            cursorPosition = cursor;
        }
        KeyNavigation.tab: campoValor
        KeyNavigation.backtab: campoPedido
        Keys.onReturnPressed: campoValor.forceActiveFocus()

        background: Rectangle {
            radius: Estilo.global.radius.pill
            color: Estilo.global.inputBackground
            border.color: parent.activeFocus ? linhaDelegate.corDestaque : Estilo.global.border
            border.width: Estilo.global.borderWidth.hairline
        }
    }

    // Campo Valor
    TextField {
        id: campoValor

        color: Estilo.global.textInput
        placeholderTextColor: Estilo.global.textPlaceholder
        placeholderText: "R$ 0,00"
        width: linhaDelegate.grade.valor
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
        onEditingFinished: linhaDelegate.aplicarValorDigitado(campoValor)
        // Entrar no campo já seleciona o valor inteiro: a intenção de quem
        // vem parar aqui é trocar o preço, não emendar dígitos no que a
        // seleção de pedido preencheu.
        onActiveFocusChanged: {
            if (activeFocus)
                selectAll();
        }

        // Precisa aceitar o "R$ " que este mesmo campo escreve — ver
        // estilo/Moeda.qml para por que o DoubleValidator que estava aqui
        // impedia a edição manual de chegar no modelo.
        validator: Moeda.validador

        background: Rectangle {
            radius: Estilo.global.radius.pill
            color: Estilo.global.inputBackground
            border.color: parent.activeFocus ? linhaDelegate.corDestaque : Estilo.global.border
            border.width: Estilo.global.borderWidth.hairline
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
        font.family: Estilo.global.fontFamily.title
        padding: Estilo.global.padding.md
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
            radius: Estilo.global.radius.pill
            color: parent.down ? linhaDelegate.corDestaque : (parent.hovered ? Estilo.global.surfaceHover : Estilo.global.surface)
            border.color: Estilo.global.border
            border.width: Estilo.global.borderWidth.hairline
        }
    }

    // Botão "-" — remove esta linha, exceto quando é a única.
    Button {
        text: "-"
        font.family: Estilo.global.fontFamily.title
        padding: Estilo.global.padding.md
        height: campoPedido.implicitHeight
        width: height
        anchors.verticalCenter: parent.verticalCenter
        visible: linhaDelegate.ListView.view.count > 1
        onClicked: {
            linhaDelegate.ListView.view.model.remove(index);
        }

        background: Rectangle {
            radius: Estilo.global.radius.pill
            color: parent.down ? Estilo.action.danger.base : (parent.hovered ? Estilo.global.surfaceHover : Estilo.global.surface)
            border.color: Estilo.global.border
            border.width: Estilo.global.borderWidth.hairline
        }
    }
}
