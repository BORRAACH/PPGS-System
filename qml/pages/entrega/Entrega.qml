import QtQuick
import QtQuick.Controls
import "../pedidos"
import "../../components"
import estilo 1.0

Page {
    id: telaEntrega

    focus: true

    property string clienteNome: ""
    // Preenchimento inicial dos campos de entrega e de modeloPedidos — usado
    // pela Consulta ao reabrir uma comanda salva para edição.
    property string telefoneInicial: ""
    property string enderecoInicial: ""
    property string numeroInicial: ""
    property string bairroInicial: ""
    property string observacaoInicial: ""
    property string formaPagamentoInicial: ""
    property string trocoInicial: ""
    property string statusPagamentoInicial: ""
    property string taxaEntregaInicial: ""
    property var itensIniciais: []
    // Formas de pagamento disponíveis para o pedido de entrega.
    readonly property var opcoesPagamento: ["Pix", "Crédito", "Débito", "Dinheiro"]
    // Nome do arquivo da comanda original quando esta tela foi aberta pela
    // Consulta para editar uma comanda existente ("" = comanda nova). Ao
    // imprimir com sucesso, o arquivo antigo é apagado para não duplicar.
    property string arquivoOriginal: ""
    // Índice da linha de modeloPedidos que está sendo editada pelo popup de
    // seleção — precisa ficar fora do delegate porque o popup é um único
    // item reaproveitado, não recriado a cada clique.
    property int indicePedidoAtual: -1

    objectName: "telaEntrega"

    function mostrarNotificacao(mensagem, sucesso) {
        filaNotificacoes.notificar(mensagem, sucesso);
    }

    // Conexão declarativa, não um .connect() solto em Component.onCompleted
    // — mesmo motivo documentado em Balcao.qml: sua vida útil fica presa à
    // desta página automaticamente, evitando acumular uma conexão morta a
    // cada vez que esta tela é recriada (todo clique na barra lateral).
    Connections {
        target: redeController

        function onImpressaoResultado(sucesso, mensagem) {
            telaEntrega.mostrarNotificacao(
                sucesso ? ("Comanda impressa (" + mensagem + ")") : ("Falha ao imprimir: " + mensagem),
                sucesso
            );
        }
    }

    Component.onCompleted: {
        if (itensIniciais && itensIniciais.length > 0) {
            modeloPedidos.clear();
            for (var i = 0; i < itensIniciais.length; i++) {
                modeloPedidos.append({
                    "pedido": itensIniciais[i].pedido || "",
                    "observacao": itensIniciais[i].observacao || "",
                    "valor": itensIniciais[i].valor || "",
                    "borda": itensIniciais[i].borda || null,
                    "adicionais": itensIniciais[i].adicionais || []
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
        enabled: telaEntrega.visible
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
        enabled: telaEntrega.visible && modeloPedidos.count > 1
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
            if (telaEntrega.indicePedidoAtual === -1)
                return ;

            // Quando mais de um lanche é selecionado de uma vez, Lanches.qml
            // envia um array de itens em vez de nome/valor — a primeira
            // linha é reaproveitada e uma nova linha é inserida para cada
            // item extra, logo após a linha que abriu a seleção.
            if (Array.isArray(nomePedido)) {
                var itens = nomePedido;
                if (itens.length === 0)
                    return ;

                modeloPedidos.setProperty(telaEntrega.indicePedidoAtual, "pedido", itens[0].nome);
                modeloPedidos.setProperty(telaEntrega.indicePedidoAtual, "valor", itens[0].valor);
                modeloPedidos.setProperty(telaEntrega.indicePedidoAtual, "observacao", itens[0].observacao || "");
                modeloPedidos.setProperty(telaEntrega.indicePedidoAtual, "borda", itens[0].borda || null);
                modeloPedidos.setProperty(telaEntrega.indicePedidoAtual, "adicionais", itens[0].adicionais || []);
                for (var i = 1; i < itens.length; i++) {
                    modeloPedidos.insert(telaEntrega.indicePedidoAtual + i, {
                        "pedido": itens[i].nome,
                        "observacao": itens[i].observacao || "",
                        "valor": itens[i].valor,
                        "borda": itens[i].borda || null,
                        "adicionais": itens[i].adicionais || []
                    });
                }
                return ;
            }

            modeloPedidos.setProperty(telaEntrega.indicePedidoAtual, "pedido", nomePedido);
            if (valorPedido !== undefined && valorPedido !== "")
                modeloPedidos.setProperty(telaEntrega.indicePedidoAtual, "valor", valorPedido);

        }
    }

    // Foca o primeiro campo assim que esta página vira a atual no StackView
    // de main.qml, para já dar para navegar só com o teclado
    // (Tab/Shift+Tab/Enter) sem precisar clicar em nada antes.
    // "focus: true" sozinho não é suficiente: o StackView assume o controle
    // do foco ao trocar de página, então é preciso pedir foco de novo aqui.
    StackView.onActivated: {
        if (stackViewLocal.currentItem)
            stackViewLocal.currentItem.inputTelefone.forceActiveFocus();
    }

    // --- ÁREA DE CONTEÚDO DINÂMICO ---
    // Sem barra lateral própria aqui: esta página já é empurrada para dentro
    // do StackView de main.qml, que fica ao lado da LateralBar permanente do
    // app. Carregar outra LateralBar aqui duplicava o logo "PPGS".
    StackView {
        id: stackViewLocal

        anchors.fill: parent
        // Sem animação de transição — ver o mesmo ajuste em qml/main.qml.
        pushEnter: Transition {}
        pushExit: Transition {}
        popEnter: Transition {}
        popExit: Transition {}
        replaceEnter: Transition {}
        replaceExit: Transition {}
        initialItem: conteudoEntregaComponent
    }

    // --- COMPONENTE DA TELA PRINCIPAL DE ENTREGA ---
    Component {
        id: conteudoEntregaComponent

        Item {
            anchors.fill: parent

            // Exposto para telaEntrega.StackView.onActivated poder focar o
            // primeiro campo assim que a tela vira a atual (ver comentário
            // lá — Component.onCompleted sozinho é cedo demais: o StackView
            // externo ainda assume o foco de volta ao concluir a transição).
            property alias inputTelefone: inputTelefone

            // Precisam ficar aqui dentro do Component, não na raiz da Page:
            // os campos que elas leem (inputNomeCliente, inputTaxaEntrega
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
                        "valor": item.valor,
                        "borda": item.borda || null,
                        "adicionais": item.adicionais || []
                    });
                }

                return {
                    "cliente": inputNomeCliente.text,
                    "telefone": inputTelefone.text,
                    "endereco": inputEndereco.text,
                    "numero": inputNumero.text,
                    "bairro": inputBairro.text,
                    "observacaoGeral": inputObservacao.text,
                    "itens": itens,
                    "formaPagamento": comboFormaPagamento.currentText,
                    "troco": comboFormaPagamento.currentText === "Dinheiro" ? inputTroco.text : "",
                    "statusPagamento": btnStatusPagamento.pago ? "PG" : "NP",
                    "taxaEntrega": inputTaxaEntrega.text
                };
            }

            // Verifica se a comanda tem pelo menos um campo preenchido (dados
            // do cliente/entrega, troco, taxa de entrega ou algum item do
            // pedido) — evita lançar/imprimir uma comanda completamente
            // vazia. formaPagamento/statusPagamento não contam: sempre têm
            // um valor padrão (Pix/NP), não refletem preenchimento do usuário.
            function comandaVazia(dados) {
                if (dados.cliente.trim() !== "" || dados.telefone !== "" || dados.endereco.trim() !== "" || dados.numero !== "" || dados.bairro.trim() !== "" || dados.observacaoGeral.trim() !== "" || dados.troco !== "" || dados.taxaEntrega !== "")
                    return false;

                for (var i = 0; i < dados.itens.length; i++) {
                    var item = dados.itens[i];
                    if (item.pedido !== "" || item.observacao.trim() !== "" || item.valor !== "")
                        return false;
                }

                return true;
            }

            // Campo de destino do Tab/Enter ao entrar/sair da lista de
            // pedidos — usados tanto pelo campo fora da lista (observação
            // geral) quanto pelas próprias linhas (ver
            // campoPedidoAnterior/campoPedidoProximo no delegate), já que o
            // número de linhas muda em tempo de execução.
            function primeiroCampoPedido() {
                var linha = listaPedidos.itemAtIndex(0);
                return linha ? linha.campoPedido : inputObservacao;
            }

            function ultimoCampoValor() {
                var linha = listaPedidos.itemAtIndex(listaPedidos.count - 1);
                return linha ? linha.campoValor : inputObservacao;
            }

            // Prosseguem de fato com o envio, depois que comandaVazia() já
            // foi checada (e, se vazia, o popup de comanda de teste já
            // respondeu) — chamadas tanto direto pelos botões quanto pelo
            // handler de popupComandaTeste.respondido.
            function prosseguirImprimir(dadosPedido) {
                var sucesso = entregaController.enviarPedido(dadosPedido, spinnerCopias.value);
                if (sucesso) {
                    limparFormularioPedido();
                    telaEntrega.mostrarNotificacao(dadosPedido.teste ? "Comanda de teste impressa." : "Pedido salvo com sucesso!", true);
                } else {
                    telaEntrega.mostrarNotificacao("Erro ao salvar o pedido.", false);
                }
            }

            function prosseguirLancar(dadosPedido) {
                var sucesso = entregaController.lancarPedido(dadosPedido);
                if (sucesso) {
                    limparFormularioPedido();
                    telaEntrega.mostrarNotificacao(dadosPedido.teste ? "Comanda de teste registrada (não aparece na Consulta)." : "Comanda lançada com sucesso!", true);
                } else {
                    telaEntrega.mostrarNotificacao("Erro ao lançar a comanda.", false);
                }
            }

            function limparFormularioPedido() {
                if (telaEntrega.arquivoOriginal !== "") {
                    consultaController.apagarComanda(telaEntrega.arquivoOriginal);
                    telaEntrega.arquivoOriginal = "";
                }
                inputNomeCliente.text = "";
                inputTelefone.text = "";
                inputEndereco.text = "";
                inputNumero.text = "";
                inputBairro.text = "";
                inputObservacao.text = "";
                modeloPedidos.clear();
                modeloPedidos.append({
                    "pedido": "",
                    "observacao": "",
                    "valor": ""
                });
                comboFormaPagamento.currentIndex = 0;
                inputTroco.text = "";
                inputTaxaEntrega.text = "";
                btnStatusPagamento.pago = false;
                spinnerCopias.value = 2;
            }

            // Rola verticalmente quando a lista de pedidos cresce (ou a
            // janela é pequena) o suficiente pra empurrar o conteúdo pra
            // fora da área visível — mesmo padrão de Flickable+ScrollBar
            // usado em PainelDetalhe.qml (Consulta). Sem isso, os botões
            // de baixo (Imprimir/Lançar/Voltar) ficavam inacessíveis.
            Flickable {
                id: flickableConteudo

                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, rowConteudo.implicitHeight + 40)
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

            Row {
                id: rowConteudo

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: 30

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 20

                    Row {
                        spacing: 10
                        anchors.horizontalCenter: parent
                        Icone { nome: "fa6s.motorcycle"; cor: "#e67e22"; tamanho: Estilo.fonte.titulo; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "PEDIDO DE ENTREGA"
                            font.pixelSize: Estilo.fonte.titulo
                            font.bold: true
                            color: "#e67e22"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Campos Telefone e Nome do Cliente
                    Row {
                        spacing: 10
                        anchors.horizontalCenter: parent

                        Column {
                            spacing: 4

                            Text {
                                text: "Telefone"
                                font.pixelSize: 12
                                font.bold: true
                                color: Estilo.cores.textoSecundario
                            }

                            TextField {
                                id: inputTelefone

                                // Evita recursão: reformatar o texto abaixo dispara
                                // onTextChanged de novo, então ignoramos essa segunda
                                // chamada enquanto a primeira ainda está ajustando o texto.
                                property bool reformatando: false

                                placeholderText: "TELEFONE"
                                width: 190
                                topPadding: 10
                                bottomPadding: 10
                                leftPadding: 10
                                rightPadding: 10
                                text: telefoneInicial
                                inputMethodHints: Qt.ImhDigitsOnly
                                focus: true
                                KeyNavigation.tab: inputNomeCliente
                                KeyNavigation.backtab: btnVoltar
                                Keys.onReturnPressed: inputNomeCliente.forceActiveFocus()
                                onTextChanged: {
                                    if (reformatando)
                                        return ;

                                    reformatando = true;
                                    // Mantém só os dígitos e formata como "(DD)NNNNNNNNN"
                                    // conforme o usuário digita.
                                    var digitos = text.replace(/\D/g, "").slice(0, 11);
                                    var formatado = "";
                                    if (digitos.length > 0) {
                                        formatado = "(" + digitos.slice(0, 2);
                                        if (digitos.length >= 2)
                                            formatado += ")" + digitos.slice(2);

                                    }
                                    text = formatado;
                                    reformatando = false;
                                }

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: parent.activeFocus ? "#e67e22" : Estilo.cores.borda
                                    border.width: 1
                                }

                            }
                        }

                        Column {
                            spacing: 4

                            Text {
                                text: "Nome do Cliente"
                                font.pixelSize: 12
                                font.bold: true
                                color: Estilo.cores.textoSecundario
                            }

                            TextField {
                                id: inputNomeCliente

                                placeholderText: "NOME DO CLIENTE"
                                width: 220
                                topPadding: 10
                                bottomPadding: 10
                                leftPadding: 10
                                rightPadding: 10
                                text: clienteNome
                                KeyNavigation.tab: inputEndereco
                                KeyNavigation.backtab: inputTelefone
                                Keys.onReturnPressed: inputEndereco.forceActiveFocus()

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: parent.activeFocus ? "#e67e22" : Estilo.cores.borda
                                    border.width: 1
                                }

                            }
                        }

                    }

                    // Campos Endereço e Número
                    Row {
                        spacing: 10
                        anchors.horizontalCenter: parent

                        Column {
                            spacing: 4

                            Text {
                                text: "Endereço"
                                font.pixelSize: 12
                                font.bold: true
                                color: Estilo.cores.textoSecundario
                            }

                            TextField {
                                id: inputEndereco

                                placeholderText: "ENDEREÇO"
                                width: 320
                                topPadding: 10
                                bottomPadding: 10
                                leftPadding: 10
                                rightPadding: 10
                                text: enderecoInicial
                                KeyNavigation.tab: inputNumero
                                KeyNavigation.backtab: inputNomeCliente
                                Keys.onReturnPressed: inputNumero.forceActiveFocus()

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: parent.activeFocus ? "#e67e22" : Estilo.cores.borda
                                    border.width: 1
                                }

                            }
                        }

                        Column {
                            spacing: 4

                            Text {
                                text: "Número"
                                font.pixelSize: 12
                                font.bold: true
                                color: Estilo.cores.textoSecundario
                            }

                            TextField {
                                id: inputNumero

                                placeholderText: "NÚMERO"
                                width: 90
                                topPadding: 10
                                bottomPadding: 10
                                leftPadding: 10
                                rightPadding: 10
                                text: numeroInicial
                                inputMethodHints: Qt.ImhDigitsOnly
                                KeyNavigation.tab: inputBairro
                                KeyNavigation.backtab: inputEndereco
                                Keys.onReturnPressed: inputBairro.forceActiveFocus()

                                validator: RegularExpressionValidator {
                                    regularExpression: /^[0-9]*$/
                                }

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: parent.activeFocus ? "#e67e22" : Estilo.cores.borda
                                    border.width: 1
                                }

                            }
                        }

                    }

                    // Campo Bairro
                    Column {
                        anchors.horizontalCenter: parent
                        spacing: 4

                        Text {
                            text: "Bairro"
                            font.pixelSize: 12
                            font.bold: true
                            color: Estilo.cores.textoSecundario
                        }

                        TextField {
                            id: inputBairro

                            placeholderText: "BAIRRO"
                            width: 420
                            topPadding: 10
                            bottomPadding: 10
                            leftPadding: 10
                            rightPadding: 10
                            text: bairroInicial
                            KeyNavigation.tab: inputObservacao
                            KeyNavigation.backtab: inputNumero
                            Keys.onReturnPressed: inputObservacao.forceActiveFocus()

                            background: Rectangle {
                                radius: Estilo.rounding.padrao
                                color: "#ffffff"
                                border.color: parent.activeFocus ? "#e67e22" : Estilo.cores.borda
                                border.width: 1
                            }

                        }
                    }

                    // Campo Observação (geral da entrega)
                    Column {
                        anchors.horizontalCenter: parent
                        spacing: 4

                        Text {
                            text: "Observação"
                            font.pixelSize: 12
                            font.bold: true
                            color: Estilo.cores.textoSecundario
                        }

                        TextField {
                            id: inputObservacao

                            placeholderText: "OBSERVAÇÃO"
                            width: 420
                            topPadding: 10
                            bottomPadding: 10
                            leftPadding: 10
                            rightPadding: 10
                            text: observacaoInicial
                            KeyNavigation.backtab: inputBairro
                            // Tab/Enter chamam primeiroCampoPedido() na hora (não
                            // usam "KeyNavigation.tab: ..."): esse binding seria
                            // avaliado só uma vez, cedo demais — antes do primeiro
                            // delegate da lista existir — e nunca mais reavaliado.
                            Keys.onTabPressed: primeiroCampoPedido().forceActiveFocus()
                            Keys.onReturnPressed: primeiroCampoPedido().forceActiveFocus()

                            background: Rectangle {
                                radius: Estilo.rounding.padrao
                                color: "#ffffff"
                                border.color: parent.activeFocus ? "#e67e22" : Estilo.cores.borda
                                border.width: 1
                            }

                        }
                    }

                    // Espaçador extra para separar os dados do cliente/entrega da seção de pedido
                    Item {
                        width: 1
                        height: 20
                    }

                    Row {
                        spacing: 8
                        anchors.horizontalCenter: parent
                        Icone { nome: "fa6s.pizza-slice"; cor: "#e67e22"; tamanho: 16; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "ITENS DO PEDIDO"
                            font.pixelSize: 16
                            font.bold: true
                            color: "#e67e22"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // --- CABEÇALHO DA LISTA DE PEDIDOS (rótulo das colunas, uma vez só —
                    // repetir em cada linha do delegate abaixo poluiria a lista) ---
                    Row {
                        width: 690
                        anchors.horizontalCenter: parent
                        spacing: 10

                        Text { text: "Pedido"; width: 200; font.pixelSize: 12; font.bold: true; color: Estilo.cores.textoSecundario }
                        Text { text: "Observação"; width: 180; font.pixelSize: 12; font.bold: true; color: Estilo.cores.textoSecundario }
                        Text { text: "Valor"; width: 110; font.pixelSize: 12; font.bold: true; color: Estilo.cores.textoSecundario }
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

                            property alias campoPedido: campoPedido
                            property alias campoObservacao: campoObservacao
                            property alias campoValor: campoValor

                            // Vizinhos dinâmicos: cada linha é uma instância
                            // separada do mesmo delegate, então não dá pra
                            // referenciar "a linha de baixo" por id — o
                            // número de linhas muda em tempo de execução, daí
                            // o lookup por índice via ListView.view.
                            function campoPedidoAnterior() {
                                if (index > 0) {
                                    var linha = ListView.view.itemAtIndex(index - 1);
                                    if (linha)
                                        return linha.campoValor;
                                }
                                return inputObservacao;
                            }

                            function campoPedidoProximo() {
                                if (index + 1 < ListView.view.count) {
                                    var linha = ListView.view.itemAtIndex(index + 1);
                                    if (linha)
                                        return linha.campoPedido;
                                }
                                return comboFormaPagamento;
                            }

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
                                KeyNavigation.tab: campoObservacao
                                // Backtab chama campoPedidoAnterior() na hora, não
                                // como "KeyNavigation.backtab: ..." — ver o
                                // comentário em inputObservacao sobre por que um
                                // binding com itemAtIndex() fica preso.
                                Keys.onBacktabPressed: linhaDelegate.campoPedidoAnterior().forceActiveFocus()
                                // Enter abre o popup de seleção — mesmo efeito do
                                // clique do mouse, já que o campo é somente leitura.
                                Keys.onReturnPressed: {
                                    telaEntrega.indicePedidoAtual = index;
                                    popupSelecaoPedido.open();
                                }

                                MouseArea {
                                    id: mouseAreaPedido

                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    hoverEnabled: true
                                    onClicked: {
                                        telaEntrega.indicePedidoAtual = index;
                                        popupSelecaoPedido.open();
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: mouseAreaPedido.containsMouse ? "#f0f0f0" : "#ffffff"
                                    border.color: parent.activeFocus ? "#e67e22" : Estilo.cores.borda
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
                                KeyNavigation.tab: campoValor
                                KeyNavigation.backtab: campoPedido
                                Keys.onReturnPressed: campoValor.forceActiveFocus()

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: parent.activeFocus ? "#e67e22" : Estilo.cores.borda
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
                                KeyNavigation.backtab: campoObservacao
                                // Tab chama campoPedidoProximo() na hora, não como
                                // "KeyNavigation.tab: ..." — ver o comentário em
                                // inputObservacao sobre por que um binding com
                                // itemAtIndex() fica preso.
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
                                    border.color: parent.activeFocus ? "#e67e22" : Estilo.cores.borda
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
                                    color: parent.down ? "#e67e22" : (parent.hovered ? Estilo.cores.bordaCard : "#ffffff")
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
                        Icone { nome: "fa6s.credit-card"; cor: "#e67e22"; tamanho: 16; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "PAGAMENTO"
                            font.pixelSize: 16
                            font.bold: true
                            color: "#e67e22"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        spacing: 10
                        anchors.horizontalCenter: parent

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
                                model: opcoesPagamento
                                currentIndex: Math.max(0, opcoesPagamento.indexOf(formaPagamentoInicial))
                                KeyNavigation.tab: inputTroco.visible ? inputTroco : inputTaxaEntrega
                                // Backtab chama ultimoCampoValor() na hora, não como
                                // "KeyNavigation.backtab: ..." — ver o comentário em
                                // inputObservacao sobre por que um binding com
                                // itemAtIndex() fica preso.
                                Keys.onBacktabPressed: ultimoCampoValor().forceActiveFocus()

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
                                    border.color: comboFormaPagamento.activeFocus ? "#e67e22" : Estilo.cores.borda
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
                                text: trocoInicial
                                visible: comboFormaPagamento.currentText === "Dinheiro"
                                KeyNavigation.tab: inputTaxaEntrega
                                KeyNavigation.backtab: comboFormaPagamento
                                Keys.onReturnPressed: inputTaxaEntrega.forceActiveFocus()
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
                                    border.color: parent.activeFocus ? "#e67e22" : Estilo.cores.borda
                                    border.width: 1
                                }

                            }
                        }

                        // Campo Taxa de entrega — soma ao valor total do pedido.
                        Column {
                            spacing: 4

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
                                text: taxaEntregaInicial
                                KeyNavigation.tab: btnStatusPagamento.visible ? btnStatusPagamento : spinnerCopias
                                KeyNavigation.backtab: inputTroco.visible ? inputTroco : comboFormaPagamento
                                Keys.onReturnPressed: (btnStatusPagamento.visible ? btnStatusPagamento : spinnerCopias).forceActiveFocus()
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
                                    border.color: parent.activeFocus ? "#e67e22" : Estilo.cores.borda
                                    border.width: 1
                                }

                            }
                        }

                        // Botão de status: alterna entre pago (PG) e não pago (NP).
                        // Visível pra qualquer forma de pagamento, inclusive Pix —
                        // Pix não é necessariamente pago na hora (ex: cliente manda
                        // o comprovante depois), então também precisa poder marcar
                        // como NP nesse caso.
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

                                property bool pago: statusPagamentoInicial === "PG"

                                text: pago ? "PG" : "NP"
                                width: 60
                                topPadding: 10
                                bottomPadding: 10
                                focusPolicy: Qt.StrongFocus
                                KeyNavigation.tab: spinnerCopias
                                KeyNavigation.backtab: inputTaxaEntrega
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
                                    // Anel de foco: só aparece navegando por teclado —
                                    // sem isso, Tab chegava ao botão sem nenhum sinal
                                    // visual de onde o foco estava.
                                    border.color: Estilo.cores.texto
                                    border.width: parent.activeFocus ? 3 : 0
                                }

                            }
                        }

                        // Quantas vezes "Imprimir" pede a impressão da mesma
                        // comanda (o arquivo é salvo uma única vez — ver
                        // EntregaController.enviarPedido). Padrão 2 aqui —
                        // diferente de Balcão — porque toda entrega já sai
                        // precisando de duas vias (uma pro motoboy, uma pra
                        // cozinha/registro).
                        Column {
                            spacing: 4

                            Text {
                                text: "Cópias"
                                font.pixelSize: 12
                                font.bold: true
                                color: Estilo.cores.textoSecundario
                            }

                            SpinBox {
                                id: spinnerCopias

                                from: 1
                                to: 5
                                value: 2
                                editable: true
                                width: 100
                                height: 42
                                KeyNavigation.tab: btnImprimir
                                KeyNavigation.backtab: btnStatusPagamento.visible ? btnStatusPagamento : inputTaxaEntrega

                                contentItem: TextInput {
                                    text: spinnerCopias.textFromValue(spinnerCopias.value, spinnerCopias.locale)
                                    font.pixelSize: Estilo.fonte.padrao
                                    color: Estilo.cores.texto
                                    horizontalAlignment: Qt.AlignHCenter
                                    verticalAlignment: Qt.AlignVCenter
                                    readOnly: !spinnerCopias.editable
                                    validator: spinnerCopias.validator
                                    selectByMouse: true
                                }

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: spinnerCopias.activeFocus ? "#e67e22" : Estilo.cores.borda
                                    border.width: spinnerCopias.activeFocus ? 2 : 1
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

                            padding: 10
                            width: 200
                            focusPolicy: Qt.StrongFocus
                            KeyNavigation.tab: btnLancar
                            KeyNavigation.backtab: spinnerCopias
                            Keys.onReturnPressed: clicked()
                            onClicked: {
                                var dados = coletarDadosPedido();
                                if (comandaVazia(dados)) {
                                    popupComandaTeste.abrirPara("imprimir", dados);
                                    return ;
                                }
                                prosseguirImprimir(dados);
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
                                // Anel de foco mais grosso: só aparece navegando
                                // por teclado, para dar pra ver onde o Tab chegou.
                                border.color: parent.activeFocus ? Estilo.cores.texto : Estilo.confirmar.pressionado
                                border.width: parent.activeFocus ? 3 : 1
                            }

                        }

                        // Botão Lançar — só salva o .txt da comanda (aparece em
                        // Consulta.qml) e propaga pela rede local, sem imprimir.
                        Button {
                            id: btnLancar

                            padding: 10
                            width: 200
                            focusPolicy: Qt.StrongFocus
                            KeyNavigation.tab: btnVoltar
                            KeyNavigation.backtab: btnImprimir
                            Keys.onReturnPressed: clicked()
                            onClicked: {
                                var dados = coletarDadosPedido();
                                if (comandaVazia(dados)) {
                                    popupComandaTeste.abrirPara("lancar", dados);
                                    return ;
                                }
                                prosseguirLancar(dados);
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
                                // Anel de foco mais grosso: só aparece navegando
                                // por teclado, para dar pra ver onde o Tab chegou.
                                border.color: parent.activeFocus ? Estilo.cores.texto : "#1d4ed8"
                                border.width: parent.activeFocus ? 3 : 1
                            }

                        }

                        // Botão Voltar
                        Button {
                            id: btnVoltar

                            padding: 10
                            width: 200
                            focusPolicy: Qt.StrongFocus
                            KeyNavigation.tab: inputTelefone
                            KeyNavigation.backtab: btnLancar
                            Keys.onReturnPressed: clicked()
                            onClicked: {
                                if (stackViewLocal.depth > 1)
                                    stackViewLocal.pop();
                                else if (telaEntrega.StackView.view)
                                    telaEntrega.StackView.view.pop();
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
                                // Anel de foco mais grosso: só aparece navegando
                                // por teclado, para dar pra ver onde o Tab chegou.
                                border.color: parent.activeFocus ? Estilo.cores.texto : Estilo.cancelar.pressionado
                                border.width: parent.activeFocus ? 3 : 1
                            }

                        }

                    }

                }

                ResumoComanda {
                    anchors.verticalCenter: parent.verticalCenter
                    itens: modeloPedidos
                    corDestaque: "#e67e22"
                    formaPagamento: comboFormaPagamento.currentText
                    troco: comboFormaPagamento.currentText === "Dinheiro" ? inputTroco.text : ""
                    pago: btnStatusPagamento.pago
                    taxaEntrega: inputTaxaEntrega.text
                    mostrarTaxaEntrega: true
                }

            }

            }

            // Só abre quando comandaVazia() barra o clique em Imprimir/Lançar
            // (ver os dois onClicked acima) — nunca some sem resposta: ou o
            // usuário escolhe teste/normal, ou fecha sem prosseguir.
            PopupComandaTeste {
                id: popupComandaTeste

                onRespondido: function(teste) {
                    var dadosPedido = dados;
                    if (teste) {
                        dadosPedido.cliente = "Teste";
                        dadosPedido.teste = true;
                    }
                    if (acaoPendente === "imprimir")
                        prosseguirImprimir(dadosPedido);
                    else
                        prosseguirLancar(dadosPedido);
                }
            }

        }

    }

    // --- NOTIFICAÇÕES TEMPORÁRIAS (SALVAR/LANÇAR O PEDIDO, RESULTADO DA IMPRESSÃO) ---
    FilaNotificacoes {
        id: filaNotificacoes
    }

    background: Rectangle {
        color: Estilo.cores.fundoPagina
        radius: Estilo.rounding.popup
    }

}
