import QtQuick
import QtQuick.Controls
import "../pedidos"
import "../../components"
import estilo 1.0

Page {
    id: telaBalcao

    property string clienteNome: ""
    // Preenche modeloPedidos ao abrir — usado pela Consulta ao reabrir uma
    // comanda salva para edição (veja Component.onCompleted abaixo).
    property var itensIniciais: []
    // Preenchimento inicial da seção de pagamento — usado pela Consulta ao
    // reabrir uma comanda salva para edição, igual a Entrega.qml.
    property string formaPagamentoInicial: ""
    property string trocoInicial: ""
    property string statusPagamentoInicial: ""
    // Formas de pagamento disponíveis para o pedido de balcão.
    readonly property var opcoesPagamento: ["Pix", "Crédito", "Débito", "Dinheiro"]
    // Nome do arquivo da comanda original quando esta tela foi aberta pela
    // Consulta para editar uma comanda existente ("" = comanda nova). Ao
    // imprimir com sucesso, o arquivo antigo é apagado para não duplicar.
    property string arquivoOriginal: ""
    // Índice da linha de modeloPedidos que está sendo editada pelo popup de
    // seleção — precisa ficar fora do delegate porque o popup é um único
    // item reaproveitado, não recriado a cada clique.
    property int indicePedidoAtual: -1

    objectName: "telaBalcao"

    function mostrarNotificacao(mensagem, sucesso) {
        notificacao.texto = mensagem;
        notificacao.sucesso = sucesso;
        notificacao.aberta = true;
        timerNotificacao.restart();
    }

    Component.onCompleted: {
        if (itensIniciais && itensIniciais.length > 0) {
            modeloPedidos.clear();
            for (var i = 0; i < itensIniciais.length; i++) {
                modeloPedidos.append({
                    "pedido": itensIniciais[i].pedido || "",
                    "observacao": itensIniciais[i].observacao || "",
                    "valor": itensIniciais[i].valor || ""
                });
            }
        }
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

    // --- POPUP DE SELEÇÃO DE PEDIDO (categorias) ---
    Pedido {
        id: popupSelecaoPedido

        pilha: stackViewLocal
        onPedidoSelecionado: function(nomePedido, valorPedido) {
            if (telaBalcao.indicePedidoAtual === -1)
                return ;

            // Quando mais de um lanche é selecionado de uma vez, Lanches.qml
            // envia um array de itens em vez de nome/valor — a primeira
            // linha é reaproveitada e uma nova linha é inserida para cada
            // item extra, logo após a linha que abriu a seleção.
            if (Array.isArray(nomePedido)) {
                var itens = nomePedido;
                if (itens.length === 0)
                    return ;

                modeloPedidos.setProperty(telaBalcao.indicePedidoAtual, "pedido", itens[0].nome);
                modeloPedidos.setProperty(telaBalcao.indicePedidoAtual, "valor", itens[0].valor);
                modeloPedidos.setProperty(telaBalcao.indicePedidoAtual, "observacao", itens[0].observacao || "");
                for (var i = 1; i < itens.length; i++) {
                    modeloPedidos.insert(telaBalcao.indicePedidoAtual + i, {
                        "pedido": itens[i].nome,
                        "observacao": itens[i].observacao || "",
                        "valor": itens[i].valor
                    });
                }
                return ;
            }

            modeloPedidos.setProperty(telaBalcao.indicePedidoAtual, "pedido", nomePedido);
            if (valorPedido !== undefined && valorPedido !== "")
                modeloPedidos.setProperty(telaBalcao.indicePedidoAtual, "valor", valorPedido);

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

            // Precisam ficar aqui dentro do Component, não na raiz da Page:
            // os campos que elas leem (inputNomeCliente, comboFormaPagamento
            // etc.) só existem dentro desta árvore instanciada — uma função
            // declarada na Page não os enxerga (ReferenceError em runtime,
            // só aparece quando a função é chamada, não no carregamento).
            function coletarDadosPedido() {
                var itens = [];
                for (var i = 0; i < modeloPedidos.count; i++) {
                    var item = modeloPedidos.get(i);
                    itens.push({
                        "pedido": item.pedido,
                        "observacao": item.observacao,
                        "valor": item.valor
                    });
                }

                return {
                    "cliente": inputNomeCliente.text,
                    "itens": itens,
                    "formaPagamento": comboFormaPagamento.currentText,
                    "troco": comboFormaPagamento.currentText === "Dinheiro" ? inputTroco.text : "",
                    "statusPagamento": btnStatusPagamento.pago ? "PG" : "NP"
                };
            }

            function limparFormularioPedido() {
                if (telaBalcao.arquivoOriginal !== "") {
                    consultaController.apagarComanda(telaBalcao.arquivoOriginal);
                    telaBalcao.arquivoOriginal = "";
                }
                inputNomeCliente.text = "";
                modeloPedidos.clear();
                modeloPedidos.append({
                    "pedido": "",
                    "observacao": "",
                    "valor": ""
                });
                comboFormaPagamento.currentIndex = 0;
                inputTroco.text = "";
                btnStatusPagamento.pago = false;
            }

            Row {
                anchors.centerIn: parent
                spacing: 30

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 20

                    Row {
                        spacing: 10
                        anchors.horizontalCenter: parent
                        Icone { nome: "fa6s.building"; cor: Estilo.confirmar.normal; tamanho: Estilo.fonte.titulo; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "ATENDIMENTO BALCÃO"
                            font.pixelSize: Estilo.fonte.titulo
                            font.bold: true
                            color: Estilo.confirmar.normal
                            anchors.verticalCenter: parent.verticalCenter
                        }
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
                            radius: Estilo.rounding.padrao
                            color: "#ffffff"
                            border.color: parent.activeFocus ? Estilo.confirmar.normal : Estilo.cores.borda
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

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        // modeloPedidos é declarado na raiz da Page (fora deste
                        // Component), então é o único jeito seguro de reagir a
                        // novas linhas aqui dentro — referenciar "listaPedidos" a
                        // partir de fora deste Component (ex: no popup de seleção
                        // de pedido) lança ReferenceError, pois o id não é
                        // visível fora da árvore em que foi declarado.
                        Connections {
                            function onCountChanged() {
                                listaPedidos.positionViewAtEnd();
                            }

                            target: modeloPedidos
                        }

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
                                        telaBalcao.indicePedidoAtual = index;
                                        popupSelecaoPedido.open();
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: mouseAreaPedido.containsMouse ? "#f0f0f0" : "#ffffff"
                                    border.color: parent.activeFocus ? Estilo.confirmar.normal : Estilo.cores.borda
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
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: parent.activeFocus ? Estilo.confirmar.normal : Estilo.cores.borda
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
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: parent.activeFocus ? Estilo.confirmar.normal : Estilo.cores.borda
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
                                    radius: Estilo.rounding.padrao
                                    color: parent.down ? Estilo.confirmar.normal : (parent.hovered ? Estilo.cores.bordaCard : "#ffffff")
                                    border.color: Estilo.cores.borda
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
                                    radius: Estilo.rounding.padrao
                                    color: parent.down ? Estilo.cancelar.normal : (parent.hovered ? Estilo.cores.bordaCard : "#ffffff")
                                    border.color: Estilo.cores.borda
                                    border.width: 1
                                }

                            }

                        }

                    }

                    // --- SEÇÃO DE PAGAMENTO ---
                    Row {
                        spacing: 8
                        anchors.horizontalCenter: parent
                        Icone { nome: "fa6s.credit-card"; cor: Estilo.confirmar.normal; tamanho: 16; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "PAGAMENTO"
                            font.pixelSize: 16
                            font.bold: true
                            color: Estilo.confirmar.normal
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        spacing: 10
                        anchors.horizontalCenter: parent

                        ComboBox {
                            id: comboFormaPagamento

                            width: 150
                            model: opcoesPagamento
                            currentIndex: Math.max(0, opcoesPagamento.indexOf(formaPagamentoInicial))

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
                                border.color: comboFormaPagamento.activeFocus ? Estilo.confirmar.normal : Estilo.cores.borda
                                border.width: 1
                                implicitHeight: inputTroco.implicitHeight
                            }

                        }

                        // Campo Troco — só faz sentido quando o pagamento é em dinheiro.
                        TextField {
                            id: inputTroco

                            placeholderText: "TROCO PARA"
                            width: 150
                            topPadding: 10
                            bottomPadding: 10
                            leftPadding: 10
                            rightPadding: 10
                            text: trocoInicial
                            visible: comboFormaPagamento.currentText === "Dinheiro"
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
                                border.color: parent.activeFocus ? Estilo.confirmar.normal : Estilo.cores.borda
                                border.width: 1
                            }

                        }

                        // Botão de status: alterna entre pago (PG) e não pago (NP).
                        Button {
                            id: btnStatusPagamento

                            property bool pago: statusPagamentoInicial === "PG"

                            text: pago ? "PG" : "NP"
                            width: 60
                            topPadding: 10
                            bottomPadding: 10
                            // Só faz sentido perguntar se já foi pago quando o
                            // pagamento não é instantâneo como o Pix.
                            visible: comboFormaPagamento.currentText !== "Pix"
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

                            padding: 10
                            width: 200
                            onClicked: {
                                var dados = coletarDadosPedido();
                                var sucesso = balcaoController.enviarPedido(dados);
                                if (sucesso) {
                                    limparFormularioPedido();
                                    telaBalcao.mostrarNotificacao("Pedido salvo com sucesso!", true);
                                } else {
                                    telaBalcao.mostrarNotificacao("Erro ao salvar o pedido.", false);
                                }
                            }

                            contentItem: Row {
                                spacing: 6
                                anchors.centerIn: parent
                                Icone { nome: "fa6s.print"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: "Imprimir"
                                    font.bold: true
                                    color: "#ffffff"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            background: Rectangle {
                                radius: Estilo.rounding.padrao
                                color: parent.down ? Estilo.confirmar.pressionado : (parent.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                                border.color: Estilo.confirmar.pressionado
                                border.width: 1
                            }

                        }

                        // Botão Lançar — só salva o .txt da comanda (aparece em
                        // Consulta.qml) e propaga pela rede local, sem imprimir.
                        Button {
                            id: btnLancar

                            padding: 10
                            width: 200
                            onClicked: {
                                var dados = coletarDadosPedido();
                                var sucesso = balcaoController.lancarPedido(dados);
                                if (sucesso) {
                                    limparFormularioPedido();
                                    telaBalcao.mostrarNotificacao("Comanda lançada com sucesso!", true);
                                } else {
                                    telaBalcao.mostrarNotificacao("Erro ao lançar a comanda.", false);
                                }
                            }

                            contentItem: Row {
                                spacing: 6
                                anchors.centerIn: parent
                                Icone { nome: "fa6s.floppy-disk"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: "Lançar"
                                    font.bold: true
                                    color: "#ffffff"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            background: Rectangle {
                                radius: Estilo.rounding.padrao
                                color: parent.down ? "#1d4ed8" : (parent.hovered ? "#1e40af" : "#2563eb")
                                border.color: "#1d4ed8"
                                border.width: 1
                            }

                        }

                        // Botão Voltar
                        Button {
                            id: btnVoltar

                            padding: 10
                            width: 200
                            onClicked: {
                                if (stackViewLocal.depth > 1)
                                    stackViewLocal.pop();
                                else if (telaBalcao.StackView.view)
                                    telaBalcao.StackView.view.pop();
                            }

                            contentItem: Row {
                                spacing: 6
                                anchors.centerIn: parent
                                Icone { nome: "fa6s.arrow-left"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: "Voltar para o Menu"
                                    font.bold: true
                                    color: "#ffffff"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            background: Rectangle {
                                radius: Estilo.rounding.padrao
                                color: parent.down ? Estilo.cancelar.pressionado : (parent.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                                border.color: Estilo.cancelar.pressionado
                                border.width: 1
                            }

                        }

                    }

                }

                ResumoComanda {
                    anchors.verticalCenter: parent.verticalCenter
                    itens: modeloPedidos
                    corDestaque: Estilo.confirmar.normal
                    formaPagamento: comboFormaPagamento.currentText
                    troco: comboFormaPagamento.currentText === "Dinheiro" ? inputTroco.text : ""
                    pago: btnStatusPagamento.pago
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
        radius: Estilo.rounding.medio
        color: sucesso ? Estilo.confirmar.normal : Estilo.cancelar.normal
        width: linhaNotificacao.implicitWidth + 40
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

        Row {
            id: linhaNotificacao

            spacing: 8
            anchors.centerIn: parent

            Icone {
                nome: notificacao.sucesso ? "fa6s.circle-check" : "fa6s.circle-xmark"
                cor: "#ffffff"
                tamanho: Estilo.fonte.padrao
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: notificacao.texto
                color: "#ffffff"
                font.bold: true
                font.pixelSize: Estilo.fonte.padrao
                anchors.verticalCenter: parent.verticalCenter
            }
        }

    }

    Timer {
        id: timerNotificacao

        interval: 2000
        repeat: false
        onTriggered: notificacao.aberta = false
    }

    background: Rectangle {
        color: Estilo.cores.fundoPagina
        radius: Estilo.rounding.popup
    }

}
