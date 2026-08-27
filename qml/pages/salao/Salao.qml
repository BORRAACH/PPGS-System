import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../pedidos"
import "../../components"
import "../../components/Texto.js" as Texto
import "../../components/DestinoPedido.js" as Destino
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

    // --- Lançamento rápido pelo Ctrl+S (ver components/PopupLancamentoRapido.qml) ---
    // Preenchidas pelo `replace()` que traz o atendente pra cá com um item já
    // escolhido. "" em mesaInicialId significa mesa nova.
    //
    // Diferente de Balcao/Entrega, aqui os itens NÃO podem ser copiados no
    // Component.onCompleted: o formulário do Salão carrega a mesa escolhida
    // primeiro (carregarMesaNoFormulario substitui modeloPedidos inteiro), e
    // um item acrescentado antes disso seria apagado por esse carregamento.
    // Daí o gancho ser o StackView.onActivated, quando stackViewLocal.currentItem
    // já existe — e a flag de uma vez só, pra voltar a esta tela pela barra
    // lateral não relançar o item.
    // Chama-se `itensLancamento`, e não `itensIniciais` como em
    // Balcao/Entrega, porque a FORMA é outra: aqui os itens chegam como as
    // páginas de categoria os produzem ({nome, valor, ...}), já que quem os
    // insere é acrescentarItens(). Em Balcao/Entrega a propriedade é lida
    // pelo Component.onCompleted de lá, que espera a chave "pedido". Dar o
    // mesmo nome às duas convidaria a passar uma no lugar da outra — o que
    // não dá erro nenhum, só linha de pedido em branco.
    property string mesaInicialId: ""
    property var itensLancamento: []
    property bool _lancamentoPendente: false

    function mostrarNotificacao(mensagem, sucesso) {
        filaNotificacoes.notificar(mensagem, sucesso);
    }

    // API do lançamento rápido — ver o comentário equivalente em
    // balcao/Balcao.qml.
    function acrescentarItens(itens) {
        return Destino.acrescentarAoModelo(modeloPedidos, itens);
    }

    function temPedidoEmAndamento() {
        return Destino.temPedidoEmAndamento(modeloPedidos);
    }

    // Carrega a mesa pedida (ou limpa o formulário, se for mesa nova) e só
    // então acrescenta os itens. Chamada tanto por este StackView.onActivated
    // quanto direto pelo popup, quando o Salão já é a tela atual.
    function aplicarLancamentoRapido(mesaId, itens) {
        if (!stackViewLocal.currentItem)
            return;

        if (mesaId !== "" && mesaId !== telaSalao.mesaAtualId)
            stackViewLocal.currentItem.carregarMesaNoFormulario(mesaId);
        else if (mesaId === "")
            stackViewLocal.currentItem.limparFormularioMesa();

        telaSalao.acrescentarItens(itens);
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
        // da malha. Via carga.agendar(), e não direto: numa sincronização a
        // malha dispara este sinal uma vez por mesa recebida, e a CargaDiferida
        // junta a rajada inteira numa releitura só, entre quadros — em vez de
        // travar a tela uma vez por mesa.
        function onMesasAtualizadas() {
            carga.agendar();
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

    // listarMesasAbertas() atravessa a ponte pro Python e lê as comandas de
    // mesa abertas — o suficiente pra segurar o primeiro quadro da tela se for
    // chamado direto daqui. Diferida, a tela aparece antes e a lista de mesas
    // entra logo em seguida (ver components/CargaDiferida.qml).
    CargaDiferida {
        id: carga

        tarefa: function() {
            carregarMesasAbertas();
        }
    }

    Component.onCompleted: {
        carga.agendar();
        // Só arma a flag: quem executa o lançamento é o StackView.onActivated
        // abaixo, que roda depois e com o formulário já instanciado.
        if (telaSalao.itensLancamento && telaSalao.itensLancamento.length > 0)
            telaSalao._lancamentoPendente = true;
    }

    StackView.onActivated: {
        carga.agendar();
        // Foco fica fora da tarefa diferida de propósito: faz parte de montar
        // a tela, não de carregar dado — adiar isso perderia as primeiras
        // teclas de quem já chega digitando o nome do cliente.
        if (stackViewLocal.currentItem)
            stackViewLocal.currentItem.inputNomeCliente.forceActiveFocus();

        if (telaSalao._lancamentoPendente) {
            telaSalao._lancamentoPendente = false;
            telaSalao.aplicarLancamentoRapido(telaSalao.mesaInicialId, telaSalao.itensLancamento);
        }
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
        // Alguns itens de bebida têm um preço maior específico pra mesa
        // (ver qml/pages/pedidos/bebidas/Bebidas.qml).
        comandaDeMesa: true
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
            id: conteudoSalao

            anchors.fill: parent

            // ===== MEDIDAS DO LAYOUT =====
            // Mesma conta do Balcão e da Entrega (ver Balcao.qml): formulário
            // (690) e resumo (300) eram larguras cravadas dentro de um Row.
            readonly property real larguraDisponivel: width - Estilo.global.padding.xl * 2
            readonly property bool empilhado: larguraDisponivel < 690 + 300 + Estilo.global.spacing.xxl
            readonly property int larguraResumo: empilhado ? Math.min(360, larguraDisponivel) : 300
            readonly property int larguraFormulario: empilhado ? Math.min(690, larguraDisponivel) : Math.min(690, larguraDisponivel - larguraResumo - Estilo.global.spacing.xxl)
            // Cliente + número da mesa lado a lado: 280 e 120 no desenho
            // original, agora proporcionais ao que couber.
            readonly property int larguraCampos: Math.min(420, larguraFormulario)
            readonly property var gradePedido: Responsivo.gradePedido(larguraFormulario)
            readonly property int larguraBotaoAcao: Math.max(140, Math.min(200, Math.floor((larguraFormulario - Estilo.global.spacing.xl * 2) / 3)))

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

                // Uma ou duas colunas conforme o espaço — ver o comentário
                // equivalente em Balcao.qml.
                GridLayout {
                    id: rowConteudo

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    columns: conteudoSalao.empilhado ? 1 : 2
                    columnSpacing: Estilo.global.spacing.xxl
                    rowSpacing: Estilo.global.spacing.xxl

                    Column {
                        Layout.preferredWidth: conteudoSalao.larguraFormulario
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                        spacing: Estilo.global.spacing.xxl

                        Row {
                            spacing: Estilo.global.spacing.md
                            anchors.horizontalCenter: parent.horizontalCenter
                            Icone { nome: "fa6s.utensils"; cor: Estilo.screen.salao.accent; tamanho: Estilo.global.fontSize.title; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: "ATENDIMENTO SALÃO"
                                font.pixelSize: Estilo.global.fontSize.title
                                font.family: Estilo.global.fontFamily.title
                                color: Estilo.screen.salao.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Campos Cliente + Mesa lado a lado.
                        // Alinhados à esquerda, e não centralizados: juntos são
                        // mais estreitos que o formulário, e centralizados
                        // começavam deslocados em relação à lista de itens
                        // logo abaixo. Numa tela estreita, onde ocupam a
                        // largura toda, os dois alinhamentos coincidem.
                        Row {
                            spacing: Estilo.global.spacing.xxl

                            Column {
                                spacing: 4

                                Text {
                                    text: "Nome do Cliente"
                                    font.pixelSize: Estilo.global.fontSize.sm
                                    font.bold: true
                                    color: Estilo.global.textSecondary
                                }

                                TextField {
                                    id: inputNomeCliente

                                    color: Estilo.global.textInput
                                    placeholderTextColor: Estilo.global.textPlaceholder
                                    placeholderText: "NOME DO CLIENTE (opcional)"
                                    // "Maria Alice" mesmo digitando tudo minusculo: capitaliza a
                                    // primeira letra e cada uma logo depois de um espaco, sem tirar o
                                    // cursor do lugar (ver components/Texto.js).
                                    //
                                    // Em onTextChanged, e nao em onEditingFinished: o nome ja sai
                                    // formatado enquanto se digita, e o que vem preenchido ao editar
                                    // uma comanda antiga tambem entra na regra. O campo passa a ter uma
                                    // invariante simples — o que esta nele esta sempre capitalizado —,
                                    // que e o que faz a comanda impressa nunca discordar da tela.
                                    onTextChanged: Texto.capitalizarCampo(inputNomeCliente)
                                    width: Math.round((conteudoSalao.larguraCampos - Estilo.global.spacing.xxl) * 0.7)
                                    topPadding: 10
                                    bottomPadding: 10
                                    leftPadding: 10
                                    rightPadding: 10
                                    focus: true
                                    KeyNavigation.backtab: btnVoltar
                                    Keys.onTabPressed: inputMesa.forceActiveFocus()
                                    Keys.onReturnPressed: inputMesa.forceActiveFocus()

                                    background: Rectangle {
                                        radius: Estilo.global.radius.pill
                                        color: Estilo.global.inputBackground
                                        border.color: parent.activeFocus ? Estilo.screen.salao.accent : Estilo.global.border
                                        border.width: Estilo.global.borderWidth.hairline
                                    }
                                }
                            }

                            Column {
                                spacing: 4

                                Text {
                                    text: "Mesa"
                                    font.pixelSize: Estilo.global.fontSize.sm
                                    font.bold: true
                                    color: Estilo.global.textSecondary
                                }

                                SpinBox {
                                    id: inputMesa

                                    from: 1
                                    to: 200
                                    value: 1
                                    editable: true
                                    width: (conteudoSalao.larguraCampos - Estilo.global.spacing.xxl) - Math.round((conteudoSalao.larguraCampos - Estilo.global.spacing.xxl) * 0.7)
                                    height: inputNomeCliente.implicitHeight
                                    KeyNavigation.backtab: inputNomeCliente
                                    Keys.onTabPressed: primeiroCampoPedido().forceActiveFocus()
                                    Keys.onReturnPressed: primeiroCampoPedido().forceActiveFocus()

                                    contentItem: TextInput {
                                        text: inputMesa.textFromValue(inputMesa.value, inputMesa.locale)
                                        font.pixelSize: Estilo.global.fontSize.lg
                                        color: Estilo.global.textInput
                                        horizontalAlignment: Qt.AlignHCenter
                                        verticalAlignment: Qt.AlignVCenter
                                        readOnly: !inputMesa.editable
                                        validator: inputMesa.validator
                                        selectByMouse: true
                                    }

                                    background: Rectangle {
                                        radius: Estilo.global.radius.pill
                                        color: Estilo.global.inputBackground
                                        border.color: inputMesa.activeFocus ? Estilo.screen.salao.accent : Estilo.global.border
                                        border.width: inputMesa.activeFocus ? 2 : 1
                                    }
                                }
                            }
                        }

                        // --- CABEÇALHO DA LISTA DE PEDIDOS ---
                        Row {
                            width: conteudoSalao.larguraFormulario
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Estilo.global.spacing.md

                            Text { text: "Pedido"; width: conteudoSalao.gradePedido.pedido; font.pixelSize: Estilo.global.fontSize.sm; font.bold: true; color: Estilo.global.textSecondary }
                            Text { text: "Observação"; width: conteudoSalao.gradePedido.observacao; font.pixelSize: Estilo.global.fontSize.sm; font.bold: true; color: Estilo.global.textSecondary }
                            Text { text: "Valor"; width: conteudoSalao.gradePedido.valor; font.pixelSize: Estilo.global.fontSize.sm; font.bold: true; color: Estilo.global.textSecondary }
                        }

                        // --- LISTA DINÂMICA DE PEDIDOS (mesmo delegate de Balcao.qml) ---
                        ListView {
                            id: listaPedidos

                            width: conteudoSalao.larguraFormulario
                            height: Math.min(count * 60, 240)
                            clip: true
                            model: modeloPedidos
                            spacing: Estilo.global.spacing.md
                            anchors.horizontalCenter: parent.horizontalCenter

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
                                corDestaque: Estilo.screen.salao.accent
                                campoExternoAnterior: inputMesa
                                campoExternoProximo: btnSalvarMesa
                                onSelecionarPedido: function(indice) {
                                    telaSalao.indicePedidoAtual = indice;
                                    popupSelecaoPedido.open();
                                }
                            }
                        }

                        // --- BOTÕES DE AÇÃO INFERIORES ---
                        // Flow pelo mesmo motivo de Balcão/Entrega: os botões
                        // repartem a largura do formulário e quebram para a
                        // linha de baixo quando não couberem lado a lado.
                        Flow {
                            spacing: Estilo.global.spacing.xl
                            width: conteudoSalao.larguraFormulario

                            // Salva o estado atual (itens, cliente, mesa) sem
                            // imprimir nada — a mesa continua aberta, pronta
                            // pra mais uma rodada de pedidos mais tarde.
                            Button {
                                id: btnSalvarMesa

                                padding: Estilo.global.padding.md
                                width: conteudoSalao.larguraBotaoAcao
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
                                    if (!resultado)
                                        return ;

                                    telaSalao.carregarMesasAbertas();
                                    telaSalao.mostrarNotificacao("Mesa salva com sucesso!", true);
                                    // Pergunta pela via de produção só quando
                                    // há de fato item novo pra fazer: salvar
                                    // a mesa de novo só pra corrigir o nome
                                    // do cliente, por exemplo, não tem o que
                                    // mandar pro pizzaiolo (ver
                                    // PopupComandaPizzaiolo.qml).
                                    var pendentes = salaoController.itensPendentesCozinha(resultado.id);
                                    if (pendentes.length > 0)
                                        popupComandaPizzaiolo.abrirPara(resultado.id, inputMesa.value, inputNomeCliente.text, pendentes);

                                }

                                contentItem: Row {
                                    spacing: Estilo.global.spacing.xs
                                    anchors.centerIn: parent
                                    Icone { nome: "fa6s.floppy-disk"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: "Salvar Mesa"
                                        font.family: Estilo.global.fontFamily.title
                                        color: Estilo.global.textOnAccent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.action.save.pressed : (parent.hovered ? Estilo.action.save.hover : Estilo.action.save.base)
                                    border.color: parent.activeFocus ? Estilo.global.focusRing : Estilo.action.save.border
                                    border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                                }
                            }

                            // Abre o popup de fechamento (divisão da conta) —
                            // só depois de garantir que o estado atual do
                            // formulário já está salvo, pra fecharMesa() ler
                            // os itens certos.
                            Button {
                                id: btnFecharConta

                                padding: Estilo.global.padding.md
                                width: conteudoSalao.larguraBotaoAcao
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
                                    spacing: Estilo.global.spacing.xs
                                    anchors.centerIn: parent
                                    Icone { nome: "fa6s.receipt"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: "Fechar Conta"
                                        font.family: Estilo.global.fontFamily.title
                                        color: Estilo.global.textOnAccent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.action.confirm.pressed : (parent.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                                    border.color: parent.activeFocus ? Estilo.global.text : Estilo.action.confirm.pressed
                                    border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                                }
                            }

                            // Botão Voltar
                            Button {
                                id: btnVoltar

                                padding: Estilo.global.padding.md
                                width: conteudoSalao.larguraBotaoAcao
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
                                    spacing: Estilo.global.spacing.xs
                                    anchors.centerIn: parent
                                    Icone { nome: "fa6s.arrow-left"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: "Voltar para o Menu"
                                        font.family: Estilo.global.fontFamily.title
                                        color: Estilo.global.textOnAccent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                                    border.color: parent.activeFocus ? Estilo.global.text : Estilo.action.danger.pressed
                                    border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                                }
                            }
                        }
                    }

                    // --- RESUMO (itens + total, sem forma de pagamento/status —
                    // isso agora é por pessoa, só na hora de fechar a conta) ---
                    Rectangle {
                        id: resumoMesa

                        Layout.preferredWidth: conteudoSalao.larguraResumo
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                        width: conteudoSalao.larguraResumo
                        implicitHeight: colunaResumoMesa.implicitHeight + Estilo.global.padding.xl * 2
                        radius: Estilo.global.radius.lg
                        color: Estilo.global.surface
                        border.color: Estilo.global.borderCard
                        border.width: Estilo.global.borderWidth.hairline

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

                            width: parent.width - Estilo.global.padding.xl * 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: Estilo.global.padding.xl
                            spacing: Estilo.global.spacing.lg

                            Row {
                                spacing: Estilo.global.spacing.sm
                                Icone { nome: "fa6s.receipt"; cor: Estilo.screen.salao.accent; tamanho: 18; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: "RESUMO DA MESA"
                                    font.pixelSize: Estilo.global.fontSize.xl
                                    font.bold: true
                                    color: Estilo.screen.salao.accent
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Rectangle { width: parent.width; height: 1; color: Estilo.global.borderCard }

                            Text {
                                width: parent.width
                                visible: resumoMesa.quantidadeItensMesa === 0
                                text: "Nenhum item adicionado ainda."
                                font.pixelSize: Estilo.global.fontSize.md
                                font.italic: true
                                color: Estilo.global.textSecondary
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
                                        font.pixelSize: Estilo.global.fontSize.md
                                        color: Estilo.global.text
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        id: textoValorItemMesa

                                        anchors.right: parent.right
                                        text: model.valor || "R$ 0,00"
                                        font.pixelSize: Estilo.global.fontSize.md
                                        color: Estilo.global.textSecondary
                                    }
                                }
                            }

                            Rectangle { width: parent.width; height: 1; color: Estilo.global.borderCard }

                            Item {
                                width: parent.width
                                height: textoTotalLabelMesa.implicitHeight

                                Text {
                                    id: textoTotalLabelMesa

                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "TOTAL"
                                    font.pixelSize: Estilo.global.fontSize.xl
                                    font.bold: true
                                    color: Estilo.screen.salao.accent
                                }

                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "R$ " + resumoMesa.valorTotalMesa.toFixed(2).replace(".", ",")
                                    font.pixelSize: Estilo.global.fontSize.xxl
                                    font.bold: true
                                    color: Estilo.screen.salao.accent
                                }
                            }
                        }
                    }
                }
            }

            // Pergunta, logo depois de lançar o pedido, se a via de produção
            // (a comanda do pizzaiolo) deve ser impressa agora.
            PopupComandaPizzaiolo {
                id: popupComandaPizzaiolo

                // Sucesso aqui é só "o pedido de impressão foi feito" — o
                // resultado da impressão em si chega depois, pelo
                // Connections de redeController lá em cima, que já notifica
                // "Comanda impressa"/"Falha ao imprimir".
                onSolicitado: function (sucesso) {
                    if (!sucesso)
                        telaSalao.mostrarNotificacao("Não foi possível montar a comanda do pizzaiolo.", false);

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
        anchors.margins: Estilo.global.padding.xl
        // A faixa é o "menu de mesas" fixo no topo: em tela baixa ela cede
        // altura para o formulário, que é onde o pedido é digitado.
        height: Responsivo.baixa ? 88 : 110
        spacing: Estilo.global.spacing.md

        Button {
            Layout.preferredWidth: Responsivo.compacto ? 90 : 110
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
                spacing: Estilo.global.spacing.xs
                Icone { nome: "fa6s.plus"; cor: Estilo.screen.salao.accent; tamanho: 20; anchors.horizontalCenter: parent.horizontalCenter }
                Text {
                    text: "Nova Mesa"
                    width: parent.width
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.screen.salao.accent
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            background: Rectangle {
                radius: Estilo.global.radius.md
                color: parent.down ? Estilo.screen.salao.softStrong : (parent.hovered ? Estilo.screen.salao.soft : Estilo.global.surface)
                border.color: Estilo.screen.salao.accent
                border.width: Estilo.global.borderWidth.thick
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Estilo.global.radius.md
            color: Estilo.global.surface
            border.color: Estilo.global.borderCard

            Text {
                anchors.centerIn: parent
                visible: modeloMesasAbertas.count === 0
                text: "Nenhuma mesa aberta no momento."
                font.italic: true
                color: Estilo.global.textSecondary
            }

            ListView {
                anchors.fill: parent
                anchors.margins: 8
                orientation: ListView.Horizontal
                spacing: Estilo.global.spacing.md
                clip: true
                model: modeloMesasAbertas

                delegate: Rectangle {
                    id: cardMesaAberta

                    readonly property bool selecionada: model.id === telaSalao.mesaAtualId

                    width: Responsivo.compacto ? 130 : 160
                    height: ListView.view.height
                    radius: Estilo.global.radius.md
                    color: selecionada ? Estilo.screen.salao.softStrong : (mouseAreaMesa.containsMouse ? Estilo.global.surfaceHover : Estilo.global.background)
                    border.color: selecionada ? Estilo.screen.salao.accent : Estilo.global.borderCard
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
                            font.pixelSize: Estilo.global.fontSize.lg
                            font.bold: true
                            color: Estilo.screen.salao.accent
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: model.cliente && model.cliente.trim() !== "" ? model.cliente : "Sem nome"
                            font.pixelSize: Estilo.global.fontSize.sm
                            color: Estilo.global.text
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }

                        Text {
                            text: model.quantidadeItens + (model.quantidadeItens === 1 ? " item" : " itens")
                            font.pixelSize: Estilo.global.fontSize.xs
                            color: Estilo.global.textSecondary
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "R$ " + model.valorTotal.toFixed(2).replace(".", ",")
                            font.pixelSize: Estilo.global.fontSize.md
                            font.bold: true
                            color: Estilo.global.text
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
                            cor: Estilo.global.textOnAccent
                            tamanho: 11
                            anchors.centerIn: parent
                        }

                        background: Rectangle {
                            radius: width / 2
                            color: parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
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
        color: Estilo.global.background
        radius: Estilo.global.radius.xl
    }
}
