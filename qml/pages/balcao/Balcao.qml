import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
    // Nome do arquivo da comanda original quando esta tela foi aberta pela
    // Consulta para editar uma comanda existente ("" = comanda nova). Ao
    // imprimir com sucesso, o arquivo antigo é apagado para não duplicar.
    property string arquivoOriginal: ""
    // A comanda que está sendo editada já tinha baixa, e o atendente escolheu
    // mantê-la conferida (ver o popup da página de Fechamento). Como editar é
    // apagar-e-recriar, a comanda nova nasceria fora do caixa do dia — isto
    // pede que a baixa seja transferida pra ela assim que for salva.
    property bool manterBaixaAoSalvar: false
    // Índice da linha de modeloPedidos que está sendo editada pelo popup de
    // seleção — precisa ficar fora do delegate porque o popup é um único
    // item reaproveitado, não recriado a cada clique.
    property int indicePedidoAtual: -1

    objectName: "telaBalcao"

    function mostrarNotificacao(mensagem, sucesso) {
        filaNotificacoes.notificar(mensagem, sucesso);
    }

    // O resultado de enviarPedido() só confirma que o .txt foi salvo — o
    // resultado de verdade da impressão (que pode acontecer em outra
    // máquina da rede) chega depois, de forma assíncrona, por este sinal
    // (ver services/rede/redeService.py:solicitar_impressao).
    //
    // Conexão DECLARATIVA (Connections), não um
    // "redeController.impressaoResultado.connect(function(){...})" solto em
    // Component.onCompleted: um Connections é um filho desta página, então
    // sua ligação com redeController (um objeto global, que vive pra
    // sempre) morre junto quando a página é destruída. Um .connect() direto
    // a partir de uma função anônima nunca se desliga sozinho — cada vez
    // que esta tela era recriada (todo clique na barra lateral, ver
    // LateralBar.qml), mais uma conexão "morta" se acumulava presa a uma
    // instância antiga que devia ter sido esquecida, um vazamento de
    // memória silencioso que piora a cada navegação.
    Connections {
        target: redeController

        function onImpressaoResultado(sucesso, mensagem) {
            telaBalcao.mostrarNotificacao(sucesso ? ("Comanda impressa (" + mensagem + ")") : ("Falha ao imprimir: " + mensagem), sucesso);
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
                    "borda": JSON.stringify(itensIniciais[i].borda || null),
                    // Guardado como string, não array: um array atribuído a um
                    // role de ListModel vira um list-model aninhado (não um
                    // JS array de verdade), e isso quebra tanto a leitura em
                    // coletarDadosPedido() quanto o envio pro Python (que
                    // recebe um QAbstractListModel em vez de uma lista).
                    "adicionais": JSON.stringify(itensIniciais[i].adicionais || [])
                });
            }
        }
    }

    // --- MODELO GLOBAL DA TELA (Agora acessível pelos Shortcuts e pela ListView) ---
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
        onPedidoSelecionado: function (nomePedido, valorPedido) {
            if (telaBalcao.indicePedidoAtual === -1)
                return;

            // Quando mais de um lanche é selecionado de uma vez, Lanches.qml
            // envia um array de itens em vez de nome/valor — a primeira
            // linha é reaproveitada e uma nova linha é inserida para cada
            // item extra, logo após a linha que abriu a seleção.
            if (Array.isArray(nomePedido)) {
                var itens = nomePedido;
                if (itens.length === 0)
                    return;

                modeloPedidos.setProperty(telaBalcao.indicePedidoAtual, "pedido", itens[0].nome);
                modeloPedidos.setProperty(telaBalcao.indicePedidoAtual, "valor", itens[0].valor);
                modeloPedidos.setProperty(telaBalcao.indicePedidoAtual, "observacao", itens[0].observacao || "");
                modeloPedidos.setProperty(telaBalcao.indicePedidoAtual, "borda", JSON.stringify(itens[0].borda || null));
                // Ver o comentário em Component.onCompleted sobre por que
                // "adicionais" precisa ser string (JSON), não array.
                modeloPedidos.setProperty(telaBalcao.indicePedidoAtual, "adicionais", JSON.stringify(itens[0].adicionais || []));
                for (var i = 1; i < itens.length; i++) {
                    modeloPedidos.insert(telaBalcao.indicePedidoAtual + i, {
                        "pedido": itens[i].nome,
                        "observacao": itens[i].observacao || "",
                        "valor": itens[i].valor,
                        "borda": JSON.stringify(itens[i].borda || null),
                        "adicionais": JSON.stringify(itens[i].adicionais || [])
                    });
                }
                return;
            }

            modeloPedidos.setProperty(telaBalcao.indicePedidoAtual, "pedido", nomePedido);
            if (valorPedido !== undefined && valorPedido !== "")
                modeloPedidos.setProperty(telaBalcao.indicePedidoAtual, "valor", valorPedido);
        }
    }

    // Foca o primeiro campo assim que esta página vira a atual no StackView
    // de main.qml, para já dar para navegar só com o teclado
    // (Tab/Shift+Tab/Enter) sem precisar clicar em nada antes.
    // "focus: true" sozinho não é suficiente: o StackView assume o controle
    // do foco ao trocar de página, então é preciso pedir foco de novo aqui.
    StackView.onActivated: {
        if (stackViewLocal.currentItem)
            stackViewLocal.currentItem.inputNomeCliente.forceActiveFocus();
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
        initialItem: conteudoBalcaoComponent
    }

    // --- COMPONENTE DA TELA PRINCIPAL DO BALCÃO ---
    Component {
        id: conteudoBalcaoComponent

        Item {
            id: conteudoBalcao

            anchors.fill: parent

            // ===== MEDIDAS DO LAYOUT =====
            // Antes, formulário (690) e resumo (300) eram larguras cravadas
            // dentro de um Row: somados aos 30 de respiro, exigiam 1020px
            // fixos, e abaixo disso o conteúdo simplesmente saía pela borda —
            // sem rolagem horizontal, sem alcance. Agora as duas colunas
            // partem do espaço que existe.
            readonly property real larguraDisponivel: width - Estilo.global.padding.xl * 2
            // O resumo da comanda é o primeiro a descer para baixo do
            // formulário: ele é leitura, não digitação — quem está lançando o
            // pedido precisa dos campos, e confere o resumo depois.
            readonly property bool empilhado: larguraDisponivel < 690 + 300 + Estilo.global.spacing.xxl
            readonly property int larguraResumo: empilhado ? Math.min(360, larguraDisponivel) : 300
            readonly property int larguraFormulario: empilhado ? Math.min(690, larguraDisponivel) : Math.min(690, larguraDisponivel - larguraResumo - Estilo.global.spacing.xxl)
            // Grade das três colunas de item, compartilhada pelo cabeçalho
            // (aqui) e pelos campos (components/LinhaPedido.qml) — ver
            // Responsivo.gradePedido.
            readonly property var gradePedido: Responsivo.gradePedido(larguraFormulario)
            // Os três botões de ação repartem a largura do formulário, sem
            // passar dos 200 originais nem descer abaixo do que o rótulo mais
            // longo ("Voltar para o Menu") precisa para ser lido.
            readonly property int larguraBotaoAcao: Math.max(140, Math.min(200, Math.floor((larguraFormulario - Estilo.global.spacing.xl * 2) / 3)))

            // Exposto para telaBalcao.StackView.onActivated poder focar o
            // primeiro campo assim que a tela vira a atual (ver comentário
            // lá — Component.onCompleted sozinho é cedo demais: o StackView
            // externo ainda assume o foco de volta ao concluir a transição).
            property alias inputNomeCliente: inputNomeCliente

            // Precisam ficar aqui dentro do Component, não na raiz da Page:
            // os campos que elas leem (inputNomeCliente, camposPagamento
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
                        "borda": JSON.parse(item.borda || "null"),
                        // item.adicionais é a string JSON guardada no
                        // ListModel (ver Component.onCompleted) — desfaz aqui
                        // pra virar array de novo antes de mandar pro Python.
                        "adicionais": JSON.parse(item.adicionais || "[]")
                    });
                }

                return {
                    "cliente": inputNomeCliente.text,
                    "itens": itens,
                    "formaPagamento": camposPagamento.formaPagamento,
                    "troco": camposPagamento.formaPagamento === "Dinheiro" ? camposPagamento.troco : "",
                    "statusPagamento": camposPagamento.pago ? "PG" : "NP"
                };
            }

            // Verifica se a comanda tem pelo menos um campo preenchido (nome
            // do cliente, troco ou algum item do pedido) — evita
            // lançar/imprimir uma comanda completamente vazia.
            // formaPagamento/statusPagamento não contam: sempre têm um valor
            // padrão (Pix/NP), não refletem preenchimento do usuário.
            function comandaVazia(dados) {
                if (dados.cliente.trim() !== "" || dados.troco !== "")
                    return false;

                for (var i = 0; i < dados.itens.length; i++) {
                    var item = dados.itens[i];
                    if (item.pedido !== "" || item.observacao.trim() !== "" || item.valor !== "")
                        return false;
                }

                return true;
            }

            // Campo de destino do Tab/Enter ao entrar/sair da lista de
            // pedidos — usados tanto pelos campos fora da lista (nome do
            // cliente, forma de pagamento) quanto pelas próprias linhas
            // (ver campoPedidoAnterior/campoPedidoProximo no delegate),
            // já que o número de linhas muda em tempo de execução.
            function primeiroCampoPedido() {
                var linha = listaPedidos.itemAtIndex(0);
                return linha ? linha.campoPedido : inputNomeCliente;
            }

            function ultimoCampoValor() {
                var linha = listaPedidos.itemAtIndex(listaPedidos.count - 1);
                return linha ? linha.campoValor : inputNomeCliente;
            }

            // Prosseguem de fato com o envio, depois que comandaVazia() já
            // foi checada (e, se vazia, o popup de comanda de teste já
            // respondeu) — chamadas tanto direto pelos botões quanto pelo
            // handler de popupComandaTeste.respondido.
            // Devolve pra comanda recém-gravada a baixa que a comanda editada
            // tinha. Chamada ANTES de limparFormularioPedido(), que zera
            // manterBaixaAoSalvar junto com arquivoOriginal.
            //
            // O nome do arquivo novo vem do controller (ultimoArquivoSalvo) e
            // não daqui: editar gera um .txt com carimbo e sufixo aleatório
            // novos, que a QML não tem como saber. darBaixa cuida do resto —
            // registra, propaga pra malha e recalcula o caixa do dia.
            function transferirBaixa() {
                if (!telaBalcao.manterBaixaAoSalvar)
                    return;

                var novoArquivo = balcaoController.ultimoArquivoSalvo();
                if (novoArquivo !== "")
                    fechamentoController.darBaixa(novoArquivo);
            }

            function prosseguirImprimir(dadosPedido) {
                var sucesso = balcaoController.enviarPedido(dadosPedido, spinnerCopias.value);
                if (sucesso) {
                    transferirBaixa();
                    limparFormularioPedido();
                    telaBalcao.mostrarNotificacao(dadosPedido.teste ? "Comanda de teste impressa." : "Pedido salvo com sucesso!", true);
                } else {
                    telaBalcao.mostrarNotificacao("Erro ao salvar o pedido.", false);
                }
            }

            function prosseguirLancar(dadosPedido) {
                var sucesso = balcaoController.lancarPedido(dadosPedido);
                if (sucesso) {
                    transferirBaixa();
                    limparFormularioPedido();
                    telaBalcao.mostrarNotificacao(dadosPedido.teste ? "Comanda de teste registrada (não aparece na Consulta)." : "Comanda lançada com sucesso!", true);
                } else {
                    telaBalcao.mostrarNotificacao("Erro ao lançar a comanda.", false);
                }
            }

            function limparFormularioPedido() {
                if (telaBalcao.arquivoOriginal !== "") {
                    consultaController.apagarComanda(telaBalcao.arquivoOriginal);
                    telaBalcao.arquivoOriginal = "";
                }
                telaBalcao.manterBaixaAoSalvar = false;
                inputNomeCliente.text = "";
                modeloPedidos.clear();
                modeloPedidos.append({
                    "pedido": "",
                    "observacao": "",
                    "valor": "",
                    "borda": "null",
                    "adicionais": "[]"
                });
                camposPagamento.redefinirPadrao();
                spinnerCopias.value = 1;
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

                // GridLayout de uma ou duas colunas, no lugar do Row de antes:
                // é a mesma árvore de itens nos dois casos — muda só o número
                // de colunas — então o formulário não é reconstruído (nem
                // perde o que já foi digitado) quando a janela cruza o ponto
                // de virada.
                GridLayout {
                    id: rowConteudo

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    columns: conteudoBalcao.empilhado ? 1 : 2
                    columnSpacing: Estilo.global.spacing.xxl
                    rowSpacing: Estilo.global.spacing.xxl

                    Column {
                        Layout.preferredWidth: conteudoBalcao.larguraFormulario
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                        spacing: Estilo.global.spacing.xxl

                        Row {
                            spacing: Estilo.global.spacing.md
                            anchors.horizontalCenter: parent.horizontalCenter
                            Icone {
                                nome: "fa6s.building"
                                cor: Estilo.action.confirm.base
                                tamanho: Estilo.global.fontSize.title
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "ATENDIMENTO BALCÃO"
                                font.pixelSize: Estilo.global.fontSize.title
                                font.family: Estilo.global.fontFamily.title
                                color: Estilo.action.confirm.base
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Campo Nome do Cliente
                        // Alinhado à esquerda, e não centralizado: ele é mais
                        // estreito que o formulário, e centralizado ficava com
                        // a borda deslocada em relação à lista de itens e ao
                        // bloco de pagamento logo abaixo — três começos de
                        // campo em posições diferentes na mesma coluna. Numa
                        // tela estreita, onde ele passa a ocupar a largura
                        // toda, os dois alinhamentos coincidem.
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
                                placeholderText: "NOME DO CLIENTE"
                                // Confortável quando há espaço, encolhe junto
                                // com o formulário quando não há.
                                width: Math.min(420, conteudoBalcao.larguraFormulario)
                                topPadding: 10
                                bottomPadding: 10
                                leftPadding: 10
                                rightPadding: 10
                                text: clienteNome
                                focus: true
                                KeyNavigation.backtab: btnVoltar
                                // Tab/Enter chamam primeiroCampoPedido() na hora (não
                                // usam "KeyNavigation.tab: primeiroCampoPedido()"):
                                // esse binding é avaliado só uma vez, cedo demais —
                                // antes do primeiro delegate da lista existir — e
                                // nunca mais é reavaliado, ficando preso apontando
                                // para "null"/o próprio campo.
                                Keys.onTabPressed: primeiroCampoPedido().forceActiveFocus()
                                Keys.onReturnPressed: primeiroCampoPedido().forceActiveFocus()

                                background: Rectangle {
                                    radius: Estilo.global.radius.sm
                                    color: Estilo.global.inputBackground
                                    border.color: parent.activeFocus ? Estilo.action.confirm.base : Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }
                            }
                        }

                        // --- CABEÇALHO DA LISTA DE PEDIDOS (rótulo das colunas, uma vez só —
                        // repetir em cada linha do delegate abaixo poluiria a lista) ---
                        Row {
                            width: conteudoBalcao.larguraFormulario
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Estilo.global.spacing.md

                            Text {
                                text: "Pedido"
                                width: conteudoBalcao.gradePedido.pedido
                                font.pixelSize: Estilo.global.fontSize.sm
                                font.bold: true
                                color: Estilo.global.textSecondary
                            }
                            Text {
                                text: "Observação"
                                width: conteudoBalcao.gradePedido.observacao
                                font.pixelSize: Estilo.global.fontSize.sm
                                font.bold: true
                                color: Estilo.global.textSecondary
                            }
                            Text {
                                text: "Valor"
                                width: conteudoBalcao.gradePedido.valor
                                font.pixelSize: Estilo.global.fontSize.sm
                                font.bold: true
                                color: Estilo.global.textSecondary
                            }
                        }

                        // --- LISTA DINÂMICA DE PEDIDOS ---
                        ListView {
                            id: listaPedidos

                            width: conteudoBalcao.larguraFormulario
                            height: Math.min(count * 60, 240)
                            clip: true
                            model: modeloPedidos // Consome o modelo declarado na raiz da Page
                            spacing: Estilo.global.spacing.md
                            anchors.horizontalCenter: parent.horizontalCenter

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

                            delegate: LinhaPedido {
                                corDestaque: Estilo.action.confirm.base
                                campoExternoAnterior: inputNomeCliente
                                campoExternoProximo: camposPagamento.primeiroCampo
                                onSelecionarPedido: function (indice) {
                                    telaBalcao.indicePedidoAtual = indice;
                                    popupSelecaoPedido.open();
                                }
                            }
                        }

                        // --- SEÇÃO DE PAGAMENTO ---
                        Row {
                            spacing: Estilo.global.spacing.sm
                            anchors.horizontalCenter: parent.horizontalCenter
                            Icone {
                                nome: "fa6s.credit-card"
                                cor: Estilo.action.confirm.base
                                tamanho: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "PAGAMENTO"
                                font.pixelSize: Estilo.global.fontSize.xl
                                font.bold: true
                                color: Estilo.action.confirm.base
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Flow: se os campos de pagamento e o seletor de cópias
                        // não couberem lado a lado, "Cópias" desce uma linha
                        // em vez de ficar fora da tela.
                        Flow {
                            spacing: Estilo.global.spacing.md
                            width: conteudoBalcao.larguraFormulario

                            CamposPagamento {
                                id: camposPagamento

                                // Desconta o seletor de cópias: é o espaço que
                                // sobra de fato para os campos se dividirem.
                                larguraDisponivel: conteudoBalcao.larguraFormulario - 100
                                corDestaque: Estilo.action.confirm.base
                                formaPagamentoInicial: telaBalcao.formaPagamentoInicial
                                trocoInicial: telaBalcao.trocoInicial
                                statusPagamentoInicial: telaBalcao.statusPagamentoInicial
                                obterCampoAnterior: function () {
                                    return ultimoCampoValor();
                                }
                                proximoCampo: spinnerCopias
                            }

                            // Quantas vezes "Imprimir" pede a impressão da mesma
                            // comanda (o arquivo é salvo uma única vez — ver
                            // BalcaoController.enviarPedido) — útil quando o
                            // balcão precisa de mais de uma via da mesma comanda.
                            Column {
                                spacing: 4

                                Text {
                                    text: "Cópias"
                                    font.pixelSize: Estilo.global.fontSize.sm
                                    font.bold: true
                                    color: Estilo.global.textSecondary
                                }

                                SpinnerCopias {
                                    id: spinnerCopias

                                    value: 1
                                    corDestaque: Estilo.action.confirm.base
                                    KeyNavigation.tab: btnImprimir
                                    KeyNavigation.backtab: camposPagamento.ultimoCampo
                                }
                            }
                        }

                        // --- BOTÕES DE AÇÃO INFERIORES ---
                        // Também em Flow: os três botões dividem a largura do
                        // formulário e, quando nem assim couberem os três na
                        // mesma linha, quebram para a linha de baixo. Eram
                        // 200px cada, fixos — 630px de exigência mínima só
                        // para Imprimir/Lançar/Voltar.
                        Flow {
                            spacing: Estilo.global.spacing.xl
                            width: conteudoBalcao.larguraFormulario

                            // Botão Imprimir
                            Button {
                                id: btnImprimir

                                padding: Estilo.global.padding.md
                                width: conteudoBalcao.larguraBotaoAcao
                                focusPolicy: Qt.StrongFocus
                                KeyNavigation.tab: btnLancar
                                KeyNavigation.backtab: spinnerCopias
                                Keys.onReturnPressed: clicked()
                                onClicked: {
                                    var dados = coletarDadosPedido();
                                    if (comandaVazia(dados)) {
                                        popupComandaTeste.abrirPara("imprimir", dados);
                                        return;
                                    }
                                    prosseguirImprimir(dados);
                                }

                                contentItem: Row {
                                    spacing: Estilo.global.spacing.xs
                                    anchors.centerIn: parent
                                    Icone {
                                        nome: "fa6s.print"
                                        cor: Estilo.global.textOnAccent
                                        tamanho: Estilo.global.fontSize.lg
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "Imprimir"
                                        font.bold: true
                                        color: Estilo.global.textOnAccent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.sm
                                    color: parent.down ? Estilo.action.confirm.pressed : (parent.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                                    // Anel de foco mais grosso: só aparece navegando
                                    // por teclado, para dar pra ver onde o Tab chegou.
                                    border.color: parent.activeFocus ? Estilo.global.text : Estilo.action.confirm.pressed
                                    border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                                }
                            }

                            // Botão Lançar — só salva o .txt da comanda (aparece em
                            // Consulta.qml) e propaga pela rede local, sem imprimir.
                            Button {
                                id: btnLancar

                                padding: Estilo.global.padding.md
                                width: conteudoBalcao.larguraBotaoAcao
                                focusPolicy: Qt.StrongFocus
                                KeyNavigation.tab: btnVoltar
                                KeyNavigation.backtab: btnImprimir
                                Keys.onReturnPressed: clicked()
                                onClicked: {
                                    var dados = coletarDadosPedido();
                                    if (comandaVazia(dados)) {
                                        popupComandaTeste.abrirPara("lancar", dados);
                                        return;
                                    }
                                    prosseguirLancar(dados);
                                }

                                contentItem: Row {
                                    spacing: Estilo.global.spacing.xs
                                    anchors.centerIn: parent
                                    Icone {
                                        nome: "fa6s.floppy-disk"
                                        cor: Estilo.global.textOnAccent
                                        tamanho: Estilo.global.fontSize.lg
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "Lançar"
                                        font.bold: true
                                        color: Estilo.global.textOnAccent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.sm
                                    color: parent.down ? Estilo.action.save.pressed : (parent.hovered ? Estilo.action.save.hover : Estilo.action.save.base)
                                    // Anel de foco mais grosso: só aparece navegando
                                    // por teclado, para dar pra ver onde o Tab chegou.
                                    border.color: parent.activeFocus ? Estilo.global.focusRing : Estilo.action.save.border
                                    border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                                }
                            }

                            // Botão Voltar
                            Button {
                                id: btnVoltar

                                padding: Estilo.global.padding.md
                                width: conteudoBalcao.larguraBotaoAcao
                                focusPolicy: Qt.StrongFocus
                                KeyNavigation.tab: inputNomeCliente
                                KeyNavigation.backtab: btnLancar
                                Keys.onReturnPressed: clicked()
                                onClicked: {
                                    // Dentro de uma tela de seleção de item
                                    // (Pizzas, Açaí...), volta para o
                                    // formulário; já no formulário, sai para
                                    // o menu inicial.
                                    if (stackViewLocal.depth > 1)
                                        stackViewLocal.pop();
                                    else if (telaBalcao.StackView.view)
                                        telaBalcao.StackView.view.irParaInicio();
                                }

                                contentItem: Row {
                                    spacing: Estilo.global.spacing.xs
                                    anchors.centerIn: parent
                                    Icone {
                                        nome: "fa6s.arrow-left"
                                        cor: Estilo.global.textOnAccent
                                        tamanho: Estilo.global.fontSize.lg
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "Voltar para o Menu"
                                        font.bold: true
                                        color: Estilo.global.textOnAccent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.sm
                                    color: parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                                    // Anel de foco mais grosso: só aparece navegando
                                    // por teclado, para dar pra ver onde o Tab chegou.
                                    border.color: parent.activeFocus ? Estilo.global.text : Estilo.action.danger.pressed
                                    border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                                }
                            }
                        }
                    }

                    ResumoComanda {
                        Layout.preferredWidth: conteudoBalcao.larguraResumo
                        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                        itens: modeloPedidos
                        corDestaque: Estilo.action.confirm.base
                        formaPagamento: camposPagamento.formaPagamento
                        troco: camposPagamento.formaPagamento === "Dinheiro" ? camposPagamento.troco : ""
                        pago: camposPagamento.pago
                    }
                }
            }

            // Só abre quando comandaVazia() barra o clique em Imprimir/Lançar
            // (ver os dois onClicked acima) — nunca some sem resposta: ou o
            // usuário escolhe teste/normal, ou fecha sem prosseguir.
            PopupComandaTeste {
                id: popupComandaTeste

                onRespondido: function (teste) {
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
        color: Estilo.global.background
        radius: Estilo.global.radius.xl
    }
}
