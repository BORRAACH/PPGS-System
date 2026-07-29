import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../pedidos"
import "../../components"
import estilo 1.0

// Atendimento no salão (mesas) — diferente de Balcão/Entrega, uma comanda de
// mesa não é lançada de uma vez só: fica aberta (salva e sincronizada pela
// malha local, ver controllers/salaoController.py), pode ser incrementada
// várias vezes ao longo da visita do cliente, e só vira um cupom impresso de
// verdade quando a conta é fechada (ver PopupFecharConta.qml) — com a
// divisão entre as pessoas (igual ou avulsa, cada uma com seu próprio status
// de pagamento) embutida no cupom final.
Page {
    id: telaSalao

    objectName: "telaSalao"

    // "" enquanto o formulário representa uma mesa nova (ainda não salva) —
    // vira o id de verdade assim que salvarMesa() responde pela primeira vez.
    property string mesaAtualId: ""
    property int indicePedidoAtual: -1

    function mostrarNotificacao(mensagem, sucesso) {
        filaNotificacoes.notificar(mensagem, sucesso);
    }

    function carregarMesasAbertas() {
        modeloMesasAbertas.clear();
        var mesas = salaoController.listarMesasAbertas();
        for (var i = 0; i < mesas.length; i++) {
            modeloMesasAbertas.append(mesas[i]);
        }
    }

    // Conexões declarativas, não .connect() soltos em Component.onCompleted
    // — mesmo motivo documentado em Balcao.qml: salaoController/
    // redeController são globais que vivem pra sempre, então uma conexão
    // feita a partir de uma função solta nunca se desligava sozinha —
    // acumulava uma a cada vez que esta tela era recriada (todo clique na
    // barra lateral). Um Connections é filho desta página e morre junto
    // com ela.
    Connections {
        target: salaoController

        // Recarrega sozinho quando uma mesa muda/fecha em qualquer máquina
        // da malha.
        function onMesasAtualizadas() {
            carregarMesasAbertas();
        }
    }

    Connections {
        target: redeController

        // O resultado de verdade da impressão (que pode acontecer em outra
        // máquina) chega depois, assíncrono, por este sinal.
        function onImpressaoResultado(sucesso, mensagem) {
            telaSalao.mostrarNotificacao(
                sucesso ? ("Comanda impressa (" + mensagem + ")") : ("Falha ao imprimir: " + mensagem),
                sucesso
            );
        }
    }

    Component.onCompleted: {
        carregarMesasAbertas();
    }
    StackView.onActivated: {
        carregarMesasAbertas();
        if (stackViewLocal.currentItem)
            stackViewLocal.currentItem.inputNomeCliente.forceActiveFocus();
    }

    // --- MODELOS GLOBAIS DA TELA ---
    ListModel {
        id: modeloPedidos

        // Todos os roles precisam existir já no primeiro elemento:
        // ListModel.setProperty() NÃO cria role novo quando o valor é um
        // objeto (só quando é tipo simples), e append() com um valor null
        // também não cria. Sem declarar aqui, "borda" nunca chegava a
        // existir e a borda escolhida sumia da comanda sem aviso nenhum.
        //
        // "borda" e "adicionais" são STRING JSON, não objeto/array: um
        // array ou objeto atribuído a um role vira um model aninhado, que
        // chega no Python como QAbstractListModel em vez de lista/dict.
        ListElement {
            pedido: ""
            observacao: ""
            valor: ""
            borda: "null"
            adicionais: "[]"
        }
    }

    ListModel {
        id: modeloMesasAbertas
    }

    // Compartilhado por todos os cards da faixa de mesas abertas (ver
    // btnExcluirMesaAberta) — evita instanciar um popup por card, mesmo
    // padrão de PopupConfirmarExclusao.qml em Consulta.qml.
    PopupConfirmarExclusaoMesa {
        id: popupConfirmarExclusaoMesa

        onMesaApagada: function (mesaId) {
            // Se a mesa excluída era a que estava carregada no formulário,
            // limpa também — senão o formulário continuaria mostrando itens
            // de uma mesa que não existe mais.
            if (mesaId === telaSalao.mesaAtualId && stackViewLocal.currentItem)
                stackViewLocal.currentItem.limparFormularioMesa();
            telaSalao.carregarMesasAbertas();
        }
    }

    // --- TECLAS DE ATALHO GLOBAIS DA TELA (mesmo padrão de Balcao.qml) ---
    Shortcut {
        sequence: "Ctrl+A"
        enabled: telaSalao.visible
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
        enabled: telaSalao.visible && modeloPedidos.count > 1
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
        // Comanda de mesa não usa a promoção de pizza do dia.
        usarPromocoes: false
        onPedidoSelecionado: function(nomePedido, valorPedido) {
            if (telaSalao.indicePedidoAtual === -1)
                return ;

            if (Array.isArray(nomePedido)) {
                var itens = nomePedido;
                if (itens.length === 0)
                    return ;

                modeloPedidos.setProperty(telaSalao.indicePedidoAtual, "pedido", itens[0].nome);
                modeloPedidos.setProperty(telaSalao.indicePedidoAtual, "valor", itens[0].valor);
                modeloPedidos.setProperty(telaSalao.indicePedidoAtual, "observacao", itens[0].observacao || "");
                modeloPedidos.setProperty(telaSalao.indicePedidoAtual, "borda", JSON.stringify(itens[0].borda || null));
                // Guardado como string, não array: um array atribuído a um
                // role de ListModel vira um list-model aninhado (não um JS
                // array de verdade), e isso quebra tanto a leitura em
                // coletarDadosMesa() quanto o envio pro Python (que recebe um
                // QAbstractListModel em vez de uma lista).
                modeloPedidos.setProperty(telaSalao.indicePedidoAtual, "adicionais", JSON.stringify(itens[0].adicionais || []));
                for (var i = 1; i < itens.length; i++) {
                    modeloPedidos.insert(telaSalao.indicePedidoAtual + i, {
                        "pedido": itens[i].nome,
                        "observacao": itens[i].observacao || "",
                        "valor": itens[i].valor,
                        "borda": JSON.stringify(itens[i].borda || null),
                        "adicionais": JSON.stringify(itens[i].adicionais || [])
                    });
                }
                return ;
            }

            modeloPedidos.setProperty(telaSalao.indicePedidoAtual, "pedido", nomePedido);
            if (valorPedido !== undefined && valorPedido !== "")
                modeloPedidos.setProperty(telaSalao.indicePedidoAtual, "valor", valorPedido);

        }
    }

    // --- ÁREA DE CONTEÚDO DINÂMICO ---
    StackView {
        id: stackViewLocal

        // Abaixo da faixa de mesas abertas, não a página inteira — ver
        // faixaMesasAbertas mais abaixo (ids do QML são visíveis no
        // documento inteiro, independente da ordem de declaração).
        anchors.top: faixaMesasAbertas.bottom
        anchors.topMargin: 15
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        pushEnter: Transition {}
        pushExit: Transition {}
        popEnter: Transition {}
        popExit: Transition {}
        replaceEnter: Transition {}
        replaceExit: Transition {}
        initialItem: conteudoSalaoComponent
    }

    // --- COMPONENTE DA TELA PRINCIPAL DO SALÃO ---
    Component {
        id: conteudoSalaoComponent

        Item {
            anchors.fill: parent

            property alias inputNomeCliente: inputNomeCliente

            function coletarDadosMesa() {
                var itens = [];
                for (var i = 0; i < modeloPedidos.count; i++) {
                    var item = modeloPedidos.get(i);
                    itens.push({
                        "pedido": item.pedido,
                        "observacao": item.observacao,
                        "valor": item.valor,
                        "borda": JSON.parse(item.borda || "null"),
                        // item.adicionais é a string JSON guardada no
                        // ListModel (ver onPedidoSelecionado) — desfaz aqui
                        // pra virar array de novo antes de mandar pro Python.
                        "adicionais": JSON.parse(item.adicionais || "[]")
                    });
                }

                return {
                    "id": telaSalao.mesaAtualId,
                    "mesa": inputMesa.value,
                    "cliente": inputNomeCliente.text,
                    "itens": itens
                };
            }

            // Diferente de comandaVazia() em Balcao.qml/Entrega.qml: aqui não
            // existe "comanda de teste" (o número da mesa já é obrigatório
            // pelo próprio SpinBox, de 1 em diante) — só barra Fechar Conta
            // quando não há nenhum item de verdade na lista.
            function temItemPreenchido() {
                for (var i = 0; i < modeloPedidos.count; i++) {
                    if (modeloPedidos.get(i).pedido !== "")
                        return true;

                }
                return false;
            }

            function primeiroCampoPedido() {
                var linha = listaPedidos.itemAtIndex(0);
                return linha ? linha.campoPedido : inputMesa;
            }

            function ultimoCampoValor() {
                var linha = listaPedidos.itemAtIndex(listaPedidos.count - 1);
                return linha ? linha.campoValor : inputMesa;
            }

            function limparFormularioMesa() {
                telaSalao.mesaAtualId = "";
                inputNomeCliente.text = "";
                inputMesa.value = 1;
                modeloPedidos.clear();
                modeloPedidos.append({
                    "pedido": "",
                    "observacao": "",
                    "valor": ""
                });
            }

            // Carrega uma mesa já aberta (clique num card da faixa de cima)
            // no formulário, para adicionar itens/trocar de mesa/fechar a
            // conta.
            function carregarMesaNoFormulario(mesaId) {
                var mesa = salaoController.carregarMesa(mesaId);
                if (!mesa || !mesa.id)
                    return ;

                telaSalao.mesaAtualId = mesa.id;
                inputNomeCliente.text = mesa.cliente || "";
                inputMesa.value = mesa.mesa || 1;
                modeloPedidos.clear();
                var itens = mesa.itens || [];
                if (itens.length === 0) {
                    modeloPedidos.append({
                        "pedido": "",
                        "observacao": "",
                        "valor": ""
                    });
                } else {
                    for (var i = 0; i < itens.length; i++) {
                        // Não repassa itens[i] direto: "adicionais" chega do
                        // Python como array de verdade, e um array atribuído
                        // a um role de ListModel vira um list-model
                        // aninhado, não um JS array (ver coletarDadosMesa()).
                        modeloPedidos.append({
                            "pedido": itens[i].pedido || "",
                            "observacao": itens[i].observacao || "",
                            "valor": itens[i].valor || "",
                            "borda": JSON.stringify(itens[i].borda || null),
                            "adicionais": JSON.stringify(itens[i].adicionais || [])
                        });
                    }
                }
            }

            // Salva o estado atual da mesa (nova ou já existente) sem
            // imprimir nada — usado tanto pelo botão "Salvar Mesa" quanto
            // internamente por "Fechar Conta" (que precisa garantir que o
            // que está no formulário já foi persistido antes de abrir o
            // popup de fechamento).
            function salvarMesaAtual() {
                var dados = coletarDadosMesa();
                var resultado = salaoController.salvarMesa(dados);
                if (resultado.erro) {
                    telaSalao.mostrarNotificacao(resultado.erro, false);
                    return null;
                }
                telaSalao.mesaAtualId = resultado.id;
                return resultado;
            }

            // Rola verticalmente quando a lista de pedidos cresce o
            // suficiente pra empurrar o conteúdo pra fora da área visível —
            // mesmo padrão de Balcao.qml/Entrega.qml.
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
                            Icone { nome: "fa6s.utensils"; cor: "#0d9488"; tamanho: Estilo.fonte.titulo; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: "ATENDIMENTO SALÃO"
                                font.pixelSize: Estilo.fonte.titulo
                                font.bold: true
                                color: "#0d9488"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Campos Cliente + Mesa lado a lado.
                        Row {
                            spacing: 20
                            anchors.horizontalCenter: parent

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

                                    color: Estilo.cores.textoInput
                                    placeholderTextColor: Estilo.cores.placeholderInput
                                    placeholderText: "NOME DO CLIENTE (opcional)"
                                    width: 280
                                    topPadding: 10
                                    bottomPadding: 10
                                    leftPadding: 10
                                    rightPadding: 10
                                    focus: true
                                    KeyNavigation.backtab: btnVoltar
                                    Keys.onTabPressed: inputMesa.forceActiveFocus()
                                    Keys.onReturnPressed: inputMesa.forceActiveFocus()

                                    background: Rectangle {
                                        radius: Estilo.rounding.padrao
                                        color: "#ffffff"
                                        border.color: parent.activeFocus ? "#0d9488" : Estilo.cores.borda
                                        border.width: 1
                                    }
                                }
                            }

                            Column {
                                spacing: 4

                                Text {
                                    text: "Mesa"
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Estilo.cores.textoSecundario
                                }

                                SpinBox {
                                    id: inputMesa

                                    from: 1
                                    to: 200
                                    value: 1
                                    editable: true
                                    width: 120
                                    height: inputNomeCliente.implicitHeight
                                    KeyNavigation.backtab: inputNomeCliente
                                    Keys.onTabPressed: primeiroCampoPedido().forceActiveFocus()
                                    Keys.onReturnPressed: primeiroCampoPedido().forceActiveFocus()

                                    contentItem: TextInput {
                                        text: inputMesa.textFromValue(inputMesa.value, inputMesa.locale)
                                        font.pixelSize: Estilo.fonte.padrao
                                        color: Estilo.cores.textoInput
                                        horizontalAlignment: Qt.AlignHCenter
                                        verticalAlignment: Qt.AlignVCenter
                                        readOnly: !inputMesa.editable
                                        validator: inputMesa.validator
                                        selectByMouse: true
                                    }

                                    background: Rectangle {
                                        radius: Estilo.rounding.padrao
                                        color: "#ffffff"
                                        border.color: inputMesa.activeFocus ? "#0d9488" : Estilo.cores.borda
                                        border.width: inputMesa.activeFocus ? 2 : 1
                                    }
                                }
                            }
                        }

                        // --- CABEÇALHO DA LISTA DE PEDIDOS ---
                        Row {
                            width: 690
                            anchors.horizontalCenter: parent
                            spacing: 10

                            Text { text: "Pedido"; width: 200; font.pixelSize: 12; font.bold: true; color: Estilo.cores.textoSecundario }
                            Text { text: "Observação"; width: 180; font.pixelSize: 12; font.bold: true; color: Estilo.cores.textoSecundario }
                            Text { text: "Valor"; width: 110; font.pixelSize: 12; font.bold: true; color: Estilo.cores.textoSecundario }
                        }

                        // --- LISTA DINÂMICA DE PEDIDOS (mesmo delegate de Balcao.qml) ---
                        ListView {
                            id: listaPedidos

                            width: 690
                            height: Math.min(count * 60, 240)
                            clip: true
                            model: modeloPedidos
                            spacing: 10
                            anchors.horizontalCenter: parent

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                            Connections {
                                function onCountChanged() {
                                    listaPedidos.positionViewAtEnd();
                                }

                                target: modeloPedidos
                            }

                            delegate: LinhaPedido {
                                corDestaque: "#0d9488"
                                campoExternoAnterior: inputMesa
                                campoExternoProximo: btnSalvarMesa
                                onSelecionarPedido: function(indice) {
                                    telaSalao.indicePedidoAtual = indice;
                                    popupSelecaoPedido.open();
                                }
                            }
                        }

                        // --- BOTÕES DE AÇÃO INFERIORES ---
                        Row {
                            spacing: 15
                            anchors.horizontalCenter: parent

                            // Salva o estado atual (itens, cliente, mesa) sem
                            // imprimir nada — a mesa continua aberta, pronta
                            // pra mais uma rodada de pedidos mais tarde.
                            Button {
                                id: btnSalvarMesa

                                padding: 10
                                width: 200
                                focusPolicy: Qt.StrongFocus
                                KeyNavigation.tab: btnFecharConta
                                // Chama ultimoCampoValor() na hora, não como
                                // "KeyNavigation.backtab: ..." — esse binding
                                // avalia só uma vez (cedo demais, antes da
                                // lista ter linhas) e nunca mais é reavaliado
                                // (mesmo motivo documentado em Balcao.qml).
                                Keys.onBacktabPressed: ultimoCampoValor().forceActiveFocus()
                                Keys.onReturnPressed: clicked()
                                onClicked: {
                                    var resultado = salvarMesaAtual();
                                    if (resultado) {
                                        telaSalao.carregarMesasAbertas();
                                        telaSalao.mostrarNotificacao("Mesa salva com sucesso!", true);
                                    }
                                }

                                contentItem: Row {
                                    spacing: 6
                                    anchors.centerIn: parent
                                    Icone { nome: "fa6s.floppy-disk"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: "Salvar Mesa"
                                        font.bold: true
                                        color: "#ffffff"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: parent.down ? "#1d4ed8" : (parent.hovered ? "#1e40af" : "#2563eb")
                                    border.color: parent.activeFocus ? Estilo.cores.texto : "#1d4ed8"
                                    border.width: parent.activeFocus ? 3 : 1
                                }
                            }

                            // Abre o popup de fechamento (divisão da conta) —
                            // só depois de garantir que o estado atual do
                            // formulário já está salvo, pra fecharMesa() ler
                            // os itens certos.
                            Button {
                                id: btnFecharConta

                                padding: 10
                                width: 200
                                focusPolicy: Qt.StrongFocus
                                KeyNavigation.tab: btnVoltar
                                KeyNavigation.backtab: btnSalvarMesa
                                Keys.onReturnPressed: clicked()
                                onClicked: {
                                    if (!temItemPreenchido()) {
                                        telaSalao.mostrarNotificacao("Adicione ao menos um item antes de fechar a conta.", false);
                                        return ;
                                    }
                                    var resultado = salvarMesaAtual();
                                    if (!resultado)
                                        return ;

                                    popupFecharConta.abrirPara(resultado.id, resumoMesa.valorTotalMesa, coletarDadosMesa().itens);
                                }

                                contentItem: Row {
                                    spacing: 6
                                    anchors.centerIn: parent
                                    Icone { nome: "fa6s.receipt"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: "Fechar Conta"
                                        font.bold: true
                                        color: "#ffffff"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: parent.down ? Estilo.confirmar.pressionado : (parent.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                                    border.color: parent.activeFocus ? Estilo.cores.texto : Estilo.confirmar.pressionado
                                    border.width: parent.activeFocus ? 3 : 1
                                }
                            }

                            // Botão Voltar
                            Button {
                                id: btnVoltar

                                padding: 10
                                width: 200
                                focusPolicy: Qt.StrongFocus
                                KeyNavigation.tab: inputNomeCliente
                                KeyNavigation.backtab: btnFecharConta
                                Keys.onReturnPressed: clicked()
                                onClicked: {
                                    // Ver o mesmo comentário em Balcao.qml.
                                    if (stackViewLocal.depth > 1)
                                        stackViewLocal.pop();
                                    else if (telaSalao.StackView.view)
                                        telaSalao.StackView.view.irParaInicio();
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
                                    border.color: parent.activeFocus ? Estilo.cores.texto : Estilo.cancelar.pressionado
                                    border.width: parent.activeFocus ? 3 : 1
                                }
                            }
                        }
                    }

                    // --- RESUMO (itens + total, sem forma de pagamento/status —
                    // isso agora é por pessoa, só na hora de fechar a conta) ---
                    Rectangle {
                        id: resumoMesa

                        width: 300
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: colunaResumoMesa.implicitHeight + Estilo.preenchimento.grande * 2
                        radius: Estilo.rounding.painel
                        color: "#ffffff"
                        border.color: Estilo.cores.bordaCard
                        border.width: 1

                        readonly property int quantidadeItensMesa: {
                            var n = 0;
                            for (var i = 0; i < modeloPedidos.count; i++) {
                                if (modeloPedidos.get(i).pedido !== "")
                                    n++;

                            }
                            return n;
                        }
                        readonly property real valorTotalMesa: {
                            var soma = 0;
                            for (var i = 0; i < modeloPedidos.count; i++) {
                                var item = modeloPedidos.get(i);
                                if (item.pedido === "")
                                    continue;

                                var limpo = String(item.valor || "").replace("R$", "").trim().replace(",", ".");
                                var numero = parseFloat(limpo);
                                if (!isNaN(numero))
                                    soma += numero;

                            }
                            return soma;
                        }

                        Column {
                            id: colunaResumoMesa

                            width: parent.width - Estilo.preenchimento.grande * 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: Estilo.preenchimento.grande
                            spacing: Estilo.espacamento.normal

                            Row {
                                spacing: 8
                                Icone { nome: "fa6s.receipt"; cor: "#0d9488"; tamanho: 18; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: "RESUMO DA MESA"
                                    font.pixelSize: 15
                                    font.bold: true
                                    color: "#0d9488"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Rectangle { width: parent.width; height: 1; color: Estilo.cores.bordaCard }

                            Text {
                                width: parent.width
                                visible: resumoMesa.quantidadeItensMesa === 0
                                text: "Nenhum item adicionado ainda."
                                font.pixelSize: 13
                                font.italic: true
                                color: Estilo.cores.textoSecundario
                                wrapMode: Text.WordWrap
                            }

                            Repeater {
                                model: modeloPedidos

                                delegate: Item {
                                    width: colunaResumoMesa.width
                                    height: visible ? Math.max(textoNomeItemMesa.implicitHeight, textoValorItemMesa.implicitHeight) : 0
                                    visible: model.pedido !== ""

                                    Text {
                                        id: textoNomeItemMesa

                                        anchors.left: parent.left
                                        anchors.right: textoValorItemMesa.left
                                        anchors.rightMargin: 8
                                        text: "• " + model.pedido
                                        font.pixelSize: 13
                                        color: Estilo.cores.texto
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        id: textoValorItemMesa

                                        anchors.right: parent.right
                                        text: model.valor || "R$ 0,00"
                                        font.pixelSize: 13
                                        color: Estilo.cores.textoSecundario
                                    }
                                }
                            }

                            Rectangle { width: parent.width; height: 1; color: Estilo.cores.bordaCard }

                            Item {
                                width: parent.width
                                height: textoTotalLabelMesa.implicitHeight

                                Text {
                                    id: textoTotalLabelMesa

                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "TOTAL"
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: "#0d9488"
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "R$ " + resumoMesa.valorTotalMesa.toFixed(2).replace(".", ",")
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: "#0d9488"
                                }
                            }
                        }
                    }
                }
            }

            PopupFecharConta {
                id: popupFecharConta

                onConcluido: function(sucesso) {
                    if (sucesso) {
                        limparFormularioMesa();
                        telaSalao.carregarMesasAbertas();
                        telaSalao.mostrarNotificacao("Conta fechada e impressa com sucesso!", true);
                    } else {
                        telaSalao.mostrarNotificacao("Erro ao fechar a conta.", false);
                    }
                }
            }
        }
    }

    // --- FAIXA DE MESAS ABERTAS ---
    RowLayout {
        id: faixaMesasAbertas

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 20
        height: 110
        spacing: 10

        Button {
            Layout.preferredWidth: 110
            Layout.fillHeight: true
            onClicked: {
                if (stackViewLocal.currentItem)
                    stackViewLocal.currentItem.limparFormularioMesa();
            }

            contentItem: Column {
                // Largura explícita igual à do próprio botão (não só o
                // tamanho implícito do texto/ícone) — sem isso, a
                // centralização dos filhos era relativa a uma coluna mais
                // estreita que o botão, então ícone e texto ficavam
                // deslocados pra esquerda em vez de centralizados na caixa
                // inteira.
                width: parent.width
                anchors.centerIn: parent
                spacing: 6
                Icone { nome: "fa6s.plus"; cor: "#0d9488"; tamanho: 20; anchors.horizontalCenter: parent.horizontalCenter }
                Text {
                    text: "Nova Mesa"
                    width: parent.width
                    font.pixelSize: 12
                    font.bold: true
                    color: "#0d9488"
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            background: Rectangle {
                radius: Estilo.rounding.grande
                color: parent.down ? "#ccfbf1" : (parent.hovered ? "#e6fffa" : "#ffffff")
                border.color: "#0d9488"
                border.width: 2
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Estilo.rounding.grande
            color: "#ffffff"
            border.color: Estilo.cores.bordaCard

            Text {
                anchors.centerIn: parent
                visible: modeloMesasAbertas.count === 0
                text: "Nenhuma mesa aberta no momento."
                font.italic: true
                color: Estilo.cores.textoSecundario
            }

            ListView {
                anchors.fill: parent
                anchors.margins: 8
                orientation: ListView.Horizontal
                spacing: 10
                clip: true
                model: modeloMesasAbertas

                delegate: Rectangle {
                    id: cardMesaAberta

                    readonly property bool selecionada: model.id === telaSalao.mesaAtualId

                    width: 160
                    height: ListView.view.height
                    radius: Estilo.rounding.grande
                    color: selecionada ? "#ccfbf1" : (mouseAreaMesa.containsMouse ? "#f5f5f5" : Estilo.cores.fundoPagina)
                    border.color: selecionada ? "#0d9488" : Estilo.cores.bordaCard
                    border.width: selecionada ? 2 : 1

                    MouseArea {
                        id: mouseAreaMesa

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (stackViewLocal.currentItem)
                                stackViewLocal.currentItem.carregarMesaNoFormulario(model.id);
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        width: parent.width - 16

                        Text {
                            text: "Mesa " + model.mesa
                            font.pixelSize: 14
                            font.bold: true
                            color: "#0d9488"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: model.cliente && model.cliente.trim() !== "" ? model.cliente : "Sem nome"
                            font.pixelSize: 12
                            color: Estilo.cores.texto
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            text: model.quantidadeItens + (model.quantidadeItens === 1 ? " item" : " itens")
                            font.pixelSize: 11
                            color: Estilo.cores.textoSecundario
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "R$ " + model.valorTotal.toFixed(2).replace(".", ",")
                            font.pixelSize: 13
                            font.bold: true
                            color: Estilo.cores.texto
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    // Excluir mesa aberta (cancela sem imprimir nada) — fica
                    // por cima de mouseAreaMesa (declarada antes, então
                    // perde a disputa de z-order), então o clique aqui não
                    // também abre a mesa no formulário.
                    Button {
                        id: btnExcluirMesaAberta

                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 4
                        width: 22
                        height: 22
                        padding: 0
                        onClicked: {
                            popupConfirmarExclusaoMesa.abrirPara(
                                model.id,
                                "Mesa " + model.mesa + (model.cliente && model.cliente.trim() !== "" ? " — " + model.cliente : "")
                            );
                        }

                        contentItem: Icone {
                            nome: "fa6s.xmark"
                            cor: "#ffffff"
                            tamanho: 11
                            anchors.centerIn: parent
                        }

                        background: Rectangle {
                            radius: width / 2
                            color: parent.down ? Estilo.cancelar.pressionado : (parent.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                        }
                    }
                }
            }
        }
    }

    // --- NOTIFICAÇÕES TEMPORÁRIAS ---
    FilaNotificacoes {
        id: filaNotificacoes
    }

    background: Rectangle {
        color: Estilo.cores.fundoPagina
        radius: Estilo.rounding.popup
    }
}
