import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../pedidos"
import "../../components"
import "../../components/MontagemExtras.js" as Extras
import "../../components/Texto.js" as Texto
import "../../components/DestinoPedido.js" as Destino
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
    // Nome do arquivo da comanda original quando esta tela foi aberta pela
    // Consulta para editar uma comanda existente ("" = comanda nova). Ao
    // imprimir com sucesso, o arquivo antigo é apagado para não duplicar.
    property string arquivoOriginal: ""
    // A comanda que está sendo editada já tinha baixa, e o atendente escolheu
    // mantê-la conferida (ver o popup da página de Fechamento). Como editar é
    // apagar-e-recriar, a comanda nova nasceria fora do caixa do dia — isto
    // pede que a baixa seja transferida pra ela assim que for salva.
    property bool manterBaixaAoSalvar: false
    // Estado do autofill por telefone (ver Connections com
    // pizzeriaServerController mais abaixo): se o telefone atual já tem
    // endereço salvo no servidor, e quais dígitos foram usados na última
    // busca disparada — usado para descartar uma resposta que chegue
    // depois do atendente já ter trocado o telefone de novo.
    property bool enderecoEncontradoNoServidor: false
    property string telefoneEmConsulta: ""
    // Índice da linha de modeloPedidos que está sendo editada pelo popup de
    // seleção — precisa ficar fora do delegate porque o popup é um único
    // item reaproveitado, não recriado a cada clique.
    property int indicePedidoAtual: -1

    // --- RASCUNHO (ver services/rascunhosPedido.py) ---
    // Id do rascunho que este formulário está editando. "" enquanto o pedido
    // ainda não tem conteúdo nenhum — um formulário em branco não vira card na
    // faixa. Preenchido ao retomar um rascunho e no primeiro autosave.
    property string rascunhoIdInicial: ""
    property string rascunhoId: telaEntrega.rascunhoIdInicial
    // Quantas cópias, para a retomada devolver também isto. As outras
    // "*Inicial" já existiam; esta faltava — cópias nunca teve canal de
    // restauração (ver o segundo argumento de enviarPedido).
    property int copiasIniciais: 2

    // O que o autosave grava. Sai daqui, e não da Page, porque só o item de
    // nível 0 do stackViewLocal enxerga os campos do formulário.
    function _formulario() {
        return stackViewLocal.get(0);
    }

    // Vale a pena guardar? Um formulário em que ninguém digitou nada não pode
    // virar card — a faixa encheria de rascunhos de quem só abriu a tela.
    //
    // Mais largo que DestinoPedido.temPedidoEmAndamento, que só olha o nome do
    // item: aqui um pedido com só o telefone do cliente já é trabalho que se
    // perde ao fechar a página, que é justamente o que isto evita.
    function _temConteudo(estado) {
        if (!estado || !estado.dados)
            return false;

        var dados = estado.dados;
        if ((dados.cliente || "").trim() !== "")
            return true;
        if ((dados.telefone || "").trim() !== "" || (dados.endereco || "").trim() !== "")
            return true;

        var itens = dados.itens || [];
        for (var i = 0; i < itens.length; i++) {
            var item = itens[i];
            if ((item.pedido || "").trim() !== "" || (item.observacao || "").trim() !== ""
                    || (item.valor || "").trim() !== "")
                return true;
        }
        return false;
    }

    // Grava o rascunho se houver o que gravar. Chamada pelo relógio de
    // autosave, ao sair da tela e antes de trocar de rascunho.
    //
    // Não apaga o rascunho quando o formulário fica vazio: esvaziar um pedido
    // é raro e desfazê-lo é impossível — deixar o card na faixa é o lado
    // seguro de errar. Quem quer sumir com ele usa o × do card.
    // `confirmarEdicao` só quando dá para mexer no foco — a página saindo, ou
    // o formulário prestes a ser trocado por outro rascunho. O relógio de
    // autosave passa false: roubar o foco a cada 3 segundos quebrava a
    // digitação e o teclado dos popups.
    //
    // O custo de não confirmar no autosave é pequeno e temporário: um valor
    // digitado e ainda não confirmado entra no rascunho no tique seguinte à
    // saída do campo, e a saída da página confirma de qualquer jeito.
    function salvarRascunho(confirmarEdicao) {
        var formulario = telaEntrega._formulario();
        if (!formulario || !formulario.estadoDoRascunho)
            return "";

        if (confirmarEdicao === true && formulario.confirmarEdicaoPendente)
            formulario.confirmarEdicaoPendente();

        var estado = formulario.estadoDoRascunho();
        if (!telaEntrega._temConteudo(estado))
            return "";

        estado.id = telaEntrega.rascunhoId;
        estado.tipo = "Entrega";
        var id = rascunhosController.salvarRascunho(estado);
        if (id !== "") {
            telaEntrega.rascunhoId = id;
            faixaRascunhosEntrega.rascunhoAtualId = id;
            faixaRascunhosEntrega.recarregar();
        }
        return id;
    }

    objectName: "telaEntrega"

    // Repõe no formulário o rascunho com que esta página foi aberta. Adiada
    // com Qt.callLater: no Component.onCompleted da Page o item de nível 0 do
    // stackViewLocal pode ainda não existir, e _formulario() devolveria null —
    // um quadro depois ele está de pé.
    function carregarRascunhoInicial() {
        Qt.callLater(function () {
            var formulario = telaEntrega._formulario();
            if (!formulario)
                return;

            var rascunho = rascunhosController.carregarRascunho(telaEntrega.rascunhoIdInicial);
            // Sumiu entre o clique e a troca de tela (descartado noutra aba,
            // podado por idade): a página fica em branco, mas sem o id — senão
            // o autosave gravaria o formulário vazio por cima de um rascunho
            // que já não existe, ressuscitando um card fantasma.
            if (!rascunho || !rascunho.dados) {
                telaEntrega.rascunhoId = "";
                return;
            }

            formulario.aplicarRascunho(rascunho);
        });
    }

    function mostrarNotificacao(mensagem, sucesso) {
        filaNotificacoes.notificar(mensagem, sucesso);
    }

    // API do lançamento rápido pelo Ctrl+S — ver o comentário equivalente em
    // balcao/Balcao.qml.
    function acrescentarItens(itens) {
        return Destino.acrescentarAoModelo(modeloPedidos, itens);
    }

    function temPedidoEmAndamento() {
        return Destino.temPedidoEmAndamento(modeloPedidos);
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

    // Resultado da busca de endereço por telefone (buscarPorTelefone) e do
    // salvamento (salvarEndereco) — ver PizzeriaServerService. A consulta é
    // assíncrona, então tanto onEnderecoEncontrado quanto
    // onEnderecoNaoEncontrado só valem se ainda forem sobre o telefone que
    // está no campo agora (telefoneEmConsulta); senão o atendente já apagou
    // e redigitou outro número enquanto a resposta ainda estava a caminho.
    Connections {
        target: pizzeriaServerController

        function onEnderecoEncontrado(dados) {
            if (stackViewLocal.currentItem.inputTelefone.text.replace(/\D/g, "") !== telaEntrega.telefoneEmConsulta)
                return ;

            var campos = stackViewLocal.currentItem;
            campos.inputNomeCliente.text = dados.nome || "";
            campos.inputEndereco.text = dados.rua || "";
            campos.inputNumero.text = dados.numero || "";
            campos.inputBairro.text = dados.bairro || "";
            campos.inputObservacao.text = dados.observacao || "";
            telaEntrega.enderecoEncontradoNoServidor = true;
            telaEntrega.mostrarNotificacao("Endereço encontrado e preenchido automaticamente.", true);
        }

        function onEnderecoNaoEncontrado() {
            if (stackViewLocal.currentItem.inputTelefone.text.replace(/\D/g, "") !== telaEntrega.telefoneEmConsulta)
                return ;

            telaEntrega.enderecoEncontradoNoServidor = false;
        }

        function onEnderecoSalvo(sucesso, mensagem) {
            telaEntrega.mostrarNotificacao(mensagem, sucesso);
        }
    }

    Component.onCompleted: {
        // Aberta para retomar um rascunho do OUTRO tipo (a faixa navegou até
        // aqui — ver onRetomar). Sem isto a página nascia sabendo o id do
        // rascunho e com o formulário em branco: o card era clicado, a tela
        // trocava, e nada aparecia.
        //
        // Antes de itensIniciais de propósito: os dois nunca chegam juntos (um
        // vem da faixa, o outro da Consulta), mas se chegarem, o rascunho é o
        // mais completo — ele traz também pagamento, cópias e a edição em
        // curso.
        if (telaEntrega.rascunhoIdInicial !== "") {
            telaEntrega.carregarRascunhoInicial();
            return;
        }

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


    // --- POPUP DE BORDAS/ADICIONAIS DE UM ITEM JÁ NA COMANDA ---
    // Aberto pelo menu de botão direito da linha (ver
    // components/LinhaPedido.qml). Fica aqui, e não dentro do delegate, pelo
    // mesmo motivo do popup de seleção de pedido: um popup por linha seria um
    // popup a mais a cada item da comanda, e todos modais sobre a mesma tela.
    PopupExtrasItem {
        id: popupExtrasItem

        objectName: "popupExtrasItem"

        property int indiceLinha: -1

        // A análise vem pronta do delegate, que a calculou depois de a linha
        // já estar na tela — ver components/LinhaPedido.qml.
        function abrirPara(indice, modoPedido, analise) {
            indiceLinha = indice;
            abrirDaLinha(modeloPedidos, indice, modoPedido, analise);
        }

        onAplicado: function (borda, adicionais, delta) {
            Extras.gravarNaLinha(modeloPedidos, indiceLinha, borda, adicionais, delta);
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
                modeloPedidos.setProperty(telaEntrega.indicePedidoAtual, "borda", JSON.stringify(itens[0].borda || null));
                // Ver o comentário em Component.onCompleted sobre por que
                // "adicionais" precisa ser string (JSON), não array.
                modeloPedidos.setProperty(telaEntrega.indicePedidoAtual, "adicionais", JSON.stringify(itens[0].adicionais || []));
                for (var i = 1; i < itens.length; i++) {
                    modeloPedidos.insert(telaEntrega.indicePedidoAtual + i, {
                        "pedido": itens[i].nome,
                        "observacao": itens[i].observacao || "",
                        "valor": itens[i].valor,
                        "borda": JSON.stringify(itens[i].borda || null),
                        "adicionais": JSON.stringify(itens[i].adicionais || [])
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
    // O par onDeactivated + onDestruction é obrigatório, não redundante:
    // onDeactivated nem sempre dispara antes da destruição, e a barra lateral
    // navega com replace(null, ...), que destrói esta página inteira. Mesmo
    // par usado em pages/cardapio/Cardapio.qml pelo mesmo motivo.
    StackView.onDeactivated: telaEntrega.salvarRascunho(true)
    Component.onDestruction: telaEntrega.salvarRascunho(true)

    // Rede de segurança entre uma saída e outra: o pedido continua sendo
    // digitado por minutos, e um travamento ou queda de energia no meio não
    // dispara gancho nenhum.
    //
    // Um relógio só, em vez de pendurar onTextChanged nos doze campos do
    // formulário: com um gatilho por campo, o décimo terceiro campo criado
    // depois ficaria de fora em silêncio.
    Timer {
        id: relogioRascunho

        interval: 3000
        repeat: true
        running: true
        onTriggered: telaEntrega.salvarRascunho()
    }

    StackView.onActivated: {
        if (stackViewLocal.currentItem)
            stackViewLocal.currentItem.inputTelefone.forceActiveFocus();
    }

    // --- ÁREA DE CONTEÚDO DINÂMICO ---
    // Sem barra lateral própria aqui: esta página já é empurrada para dentro
    // do StackView de main.qml, que fica ao lado da LateralBar permanente do
    // app. Carregar outra LateralBar aqui duplicava o logo "PPGS".
    // --- FAIXA DE PEDIDOS EM ANDAMENTO ---
    // Irmã do stackViewLocal, não filha: assim ela continua visível quando o
    // atendente entra em Pizzas/Lanches (que são empilhados LÁ DENTRO), e é
    // alcançável por id de dentro do Component do formulário.
    FaixaRascunhos {
        id: faixaRascunhosEntrega

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Estilo.global.padding.xl
        tipoAtual: "Entrega"
        rascunhoAtualId: telaEntrega.rascunhoId

        onDescartado: function (id) {
            // Só o que está aberto no formulário: descartar o card de outro
            // pedido não pode limpar o que se está digitando agora.
            if (id !== telaEntrega.rascunhoId)
                return;

            // O id sai ANTES de esvaziar: o autosave roda a cada 3 segundos, e
            // com o id ainda apontando para o arquivo apagado ele o gravaria
            // de volta.
            telaEntrega.rascunhoId = "";

            var formulario = telaEntrega._formulario();
            if (formulario)
                formulario.descartarConteudo();
        }

        onRetomar: function (id, tipo) {
            if (id === telaEntrega.rascunhoId)
                return;

            // O que está no formulário agora ainda não foi gravado — e aqui
            // dá para confirmar a edição pendente, porque o formulário vai ser
            // trocado logo em seguida.
            telaEntrega.salvarRascunho(true);

            if (tipo === "Entrega") {
                var formulario = telaEntrega._formulario();
                if (formulario)
                    formulario.aplicarRascunho(rascunhosController.carregarRascunho(id));
                telaEntrega.rascunhoId = id;
                faixaRascunhosEntrega.rascunhoAtualId = id;
                faixaRascunhosEntrega.recarregar();
                return;
            }

            // Rascunho do outro tipo: trocar de tela. replace(null, ...), como
            // a barra lateral e o lançamento rápido — esta página é destruída,
            // e o rascunho dela já foi salvo acima.
            telaEntrega.StackView.view.replace(null, raizProjeto + "qml/pages/balcao/Balcao.qml",
                                               { "rascunhoIdInicial": id },
                                               StackView.Immediate);
        }
    }

    StackView {
        id: stackViewLocal

        // Abaixo da faixa, não a página inteira — mesmo arranjo de
        // pages/salao/Salao.qml (ids do QML valem no documento todo,
        // independente da ordem de declaração).
        anchors.top: faixaRascunhosEntrega.bottom
        anchors.topMargin: 15
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
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
            id: conteudoEntrega

            anchors.fill: parent

            // ===== MEDIDAS DO LAYOUT =====
            // Mesma conta do Balcão (ver Balcao.qml): formulário e resumo
            // eram larguras cravadas — 690 e 300 — dentro de um Row, e abaixo
            // de ~1020px de janela o conteúdo saía pela borda sem rolagem
            // horizontal que o alcançasse.
            readonly property real larguraDisponivel: width - Estilo.global.padding.xl * 2
            readonly property bool empilhado: larguraDisponivel < 690 + 300 + Estilo.global.spacing.xxl
            readonly property int larguraResumo: empilhado ? Math.min(360, larguraDisponivel) : 300
            readonly property int larguraFormulario: empilhado ? Math.min(690, larguraDisponivel) : Math.min(690, larguraDisponivel - larguraResumo - Estilo.global.spacing.xxl)
            // Os campos de cliente/endereço são mais estreitos que a lista de
            // itens: 420px no desenho original, contra os 690 da lista. Esta é
            // a largura desse bloco de cima, e as duplas de campos
            // (telefone+nome, endereço+número) repartem exatamente ela.
            readonly property int larguraCampos: Math.min(420, larguraFormulario)
            readonly property var gradePedido: Responsivo.gradePedido(larguraFormulario)
            readonly property int larguraBotaoAcao: Math.max(140, Math.min(200, Math.floor((larguraFormulario - Estilo.global.spacing.xl * 2) / 3)))

            // Exposto para telaEntrega.StackView.onActivated poder focar o
            // primeiro campo assim que a tela vira a atual (ver comentário
            // lá — Component.onCompleted sozinho é cedo demais: o StackView
            // externo ainda assume o foco de volta ao concluir a transição).
            property alias inputTelefone: inputTelefone
            // Expostos para o Connections de pizzeriaServerController (fora
            // deste Component) poder preencher os campos quando a busca por
            // telefone encontra um endereço salvo — mesmo motivo do alias
            // acima.
            property alias inputNomeCliente: inputNomeCliente
            property alias inputEndereco: inputEndereco
            property alias inputNumero: inputNumero
            property alias inputBairro: inputBairro
            property alias inputObservacao: inputObservacao

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
                    "telefone": inputTelefone.text,
                    "endereco": inputEndereco.text,
                    "numero": inputNumero.text,
                    "bairro": inputBairro.text,
                    "observacaoGeral": inputObservacao.text,
                    "itens": itens,
                    "formaPagamento": camposPagamento.formaPagamento,
                    "troco": camposPagamento.formaPagamento === "Dinheiro" ? camposPagamento.troco : "",
                    "statusPagamento": camposPagamento.pago ? "PG" : "NP",
                    "taxaEntrega": camposPagamento.taxaEntrega
                };
            }

            // --- RASCUNHO ---
            // O estado inteiro do formulário, pronto para
            // rascunhosController.salvarRascunho (ver
            // services/rascunhosPedido.py). Mora AQUI, e não na Page, porque
            // os campos só existem dentro desta árvore instanciada — mesmo
            // motivo de coletarDadosPedido estar aqui.
            //
            // LEITURA PURA: não mexe no foco. Já mexeu, e foi um desastre —
            // o relógio de autosave chamava isto a cada 3 segundos, e o
            // forceActiveFocus daqui arrancava o foco de quem estivesse
            // digitando. Na prática: o nome do cliente perdia o cursor no meio
            // da palavra, e as teclas (setas, Esc, Enter, Tab) paravam de
            // funcionar em qualquer popup aberto por cima, como o de
            // lançamento rápido do Ctrl+S.
            //
            // Quem precisa confirmar uma edição pendente chama
            // confirmarEdicaoPendente() ANTES — e só quem pode se dar ao luxo
            // de mexer no foco faz isso (ver salvarRascunho na Page).
            function estadoDoRascunho() {
                return {
                    "dados": coletarDadosPedido(),
                    "copias": spinnerCopias.value,
                    // Um rascunho pode ser a EDIÇÃO de uma comanda já salva
                    // (ver components/EdicaoComanda.js). Sem estes dois,
                    // retomá-lo gravaria uma comanda nova e deixaria a antiga
                    // para trás, duplicando a venda no caixa do dia.
                    "arquivoOriginal": telaEntrega.arquivoOriginal,
                    "manterBaixaAoSalvar": telaEntrega.manterBaixaAoSalvar
                };
            }

            // Empurra para o modelo o que estiver digitado e ainda não
            // confirmado. O campo de valor de cada linha só escreve no
            // modeloPedidos em onEditingFinished (ver
            // components/LinhaPedido.qml), então sem sair do campo o valor
            // recém-digitado não entraria no rascunho.
            //
            // Mexe no foco, e por isso SÓ é chamada quando a página está de
            // saída ou o formulário está prestes a ser trocado — nunca no
            // autosave periódico.
            function confirmarEdicaoPendente() {
                conteudoEntrega.forceActiveFocus();
            }

            // Repovoa o formulário com um rascunho guardado.
            //
            // Escreve nos campos, e não nas properties "*Inicial" da Page: a
            // primeira chamada de limparFormularioPedido() atribui ".text"
            // direto e quebra para sempre os bindings dessas properties, então
            // depois dela mexer nelas não mexe mais na tela.
            function aplicarRascunho(rascunho) {
                if (!rascunho || !rascunho.dados)
                    return;

                var dados = rascunho.dados;
                telaEntrega.arquivoOriginal = rascunho.arquivoOriginal || "";
                telaEntrega.manterBaixaAoSalvar = rascunho.manterBaixaAoSalvar === true;

                inputNomeCliente.text = dados.cliente || "";
                inputTelefone.text = dados.telefone || "";
                inputEndereco.text = dados.endereco || "";
                inputNumero.text = dados.numero || "";
                inputBairro.text = dados.bairro || "";
                inputObservacao.text = dados.observacaoGeral || "";
                modeloPedidos.clear();
                var itens = dados.itens || [];
                for (var i = 0; i < itens.length; i++) {
                    var item = itens[i];
                    // Borda e adicionais voltam para STRING JSON, a convenção
                    // do ListModel destas telas (ver Component.onCompleted):
                    // um objeto/array atribuído a um role vira um list-model
                    // aninhado em vez de continuar sendo objeto/array.
                    modeloPedidos.append({
                        "pedido": item.pedido || "",
                        "observacao": item.observacao || "",
                        "valor": item.valor || "",
                        "borda": JSON.stringify(item.borda !== undefined ? item.borda : null),
                        "adicionais": JSON.stringify(item.adicionais || [])
                    });
                }
                // A lista nunca fica sem uma linha em branco no fim, senão não
                // há onde digitar o próximo item.
                if (modeloPedidos.count === 0) {
                    modeloPedidos.append({
                        "pedido": "", "observacao": "", "valor": "",
                        "borda": "null", "adicionais": "[]"
                    });
                }

                camposPagamento.aplicarValores(dados.formaPagamento || "", dados.troco || "",
                                               dados.statusPagamento === "PG",
                                               dados.taxaEntrega || "");
                spinnerCopias.value = rascunho.copias || 2;
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
            // Fecha a correção de uma comanda que veio do Fechamento: devolve
            // pra comanda recém-gravada a baixa que a comanda editada tinha e
            // deixa registrada, no caixa daquele dia, a alteração e quem a
            // fez. Chamada ANTES de limparFormularioPedido(), que zera
            // manterBaixaAoSalvar junto com arquivoOriginal — e que também
            // apaga a comanda antiga, o que precisa acontecer DEPOIS: o valor
            // que o caixa tinha antes só existe enquanto aquele .txt existe.
            //
            // O nome do arquivo novo vem do controller (ultimoArquivoSalvo) e
            // não daqui: editar gera um .txt com carimbo e sufixo aleatório
            // novos, que a QML não tem como saber. darBaixa cuida do resto —
            // registra, propaga pra malha e recalcula o caixa do dia.
            //
            // O usuário é o mesmo que já sai impresso na comanda: quem liberou
            // ESTA gravação (ver prosseguirImprimir), e não quem abriu a fila
            // lá no Fechamento — a correção é assinada por quem a salvou.
            //
            // Chamada em toda edição, e não só quando manterBaixaAoSalvar:
            // quem decide se houve alteração de caixa a registrar é o
            // controller, olhando se a comanda editada tinha baixa (ver
            // FechamentoController.registrarEdicaoCaixa). Uma correção que
            // NÃO devolve a baixa também mexe no caixa — tira a venda dele.
            function concluirEdicao(usuario) {
                if (telaEntrega.arquivoOriginal === "")
                    return;

                var novoArquivo = entregaController.ultimoArquivoSalvo();
                fechamentoController.registrarEdicaoCaixa(telaEntrega.arquivoOriginal, novoArquivo, usuario, telaEntrega.manterBaixaAoSalvar);

                if (telaEntrega.manterBaixaAoSalvar && novoArquivo !== "")
                    fechamentoController.darBaixa(novoArquivo);
            }

            // O código do usuário é pedido aqui, e não no onClicked do botão,
            // porque este é o ponto por onde passam os DOIS caminhos até a
            // impressão: o clique direto e a confirmação de comanda de teste
            // (ver PopupComandaTeste). Guardar só o botão deixaria o segundo
            // aberto.
            //
            // O nome de quem autorizou entra em dadosPedido e sai impresso na
            // comanda (ver o campo "usuario" em services/comandaEstiloService.py
            // e entregaController.py). Sem ninguém cadastrado o guarda
            // libera e devolve nome vazio — a linha some do cupom.
            function prosseguirImprimir(dadosPedido) {
                popupAutorizacao.solicitar("Imprimir comanda (Entrega)", dadosPedido.cliente || "sem cliente", function (usuario) {
                    dadosPedido.usuario = usuario.nome || "";
                    _imprimirAutorizado(dadosPedido);
                });
            }

            function _imprimirAutorizado(dadosPedido) {
                var sucesso = entregaController.enviarPedido(dadosPedido, spinnerCopias.value);
                if (sucesso) {
                    concluirEdicao(dadosPedido.usuario);
                    limparFormularioPedido();
                    telaEntrega.mostrarNotificacao(dadosPedido.teste ? "Comanda de teste impressa." : "Pedido salvo com sucesso!", true);
                } else {
                    telaEntrega.mostrarNotificacao("Erro ao salvar o pedido.", false);
                }
            }

            function prosseguirLancar(dadosPedido) {
                popupAutorizacao.solicitar("Lançar comanda (Entrega)", dadosPedido.cliente || "sem cliente", function (usuario) {
                    dadosPedido.usuario = usuario.nome || "";
                    _lancarAutorizado(dadosPedido);
                });
            }

            function _lancarAutorizado(dadosPedido) {
                var sucesso = entregaController.lancarPedido(dadosPedido);
                if (sucesso) {
                    concluirEdicao(dadosPedido.usuario);
                    limparFormularioPedido();
                    telaEntrega.mostrarNotificacao(dadosPedido.teste ? "Comanda de teste registrada (não aparece na Consulta)." : "Comanda lançada com sucesso!", true);
                } else {
                    telaEntrega.mostrarNotificacao("Erro ao lançar a comanda.", false);
                }
            }

            // Chamada pelos botões Imprimir/Lançar no lugar de
            // prosseguirImprimir/prosseguirLancar diretos, quando a comanda
            // não está vazia: se houver telefone + algum dado de endereço,
            // pergunta antes se deve salvar/sobrescrever no servidor (ver
            // PopupSalvarEndereco e o onRespondido dele, mais abaixo). Sem
            // telefone/endereço suficiente não faz sentido perguntar — segue
            // direto.
            //
            // O estado do servidor NÃO entra mais nesta decisão. Ele entrava
            // enquanto uma gravação sem servidor de pé era impossível: a
            // pergunta seria sobre algo que não podia acontecer, e o caixa
            // clicaria "Salvar" achando que guardou o endereço do cliente.
            // Agora o salvamento vai para uma fila em disco
            // (services/rede/enviosPendentes.py) e sobe sozinho quando o
            // servidor voltar, então perguntar com o servidor fora do ar
            // guarda o cadastro de verdade. Manter o gate antigo é que passou
            // a ser a perda de dado: todo endereço tomado com a máquina
            // hospedeira desligada sumia sem nunca ter sido oferecido.
            function confirmarSalvarEnderecoEProsseguir(acao, dadosPedido) {
                var temTelefone = dadosPedido.telefone.replace(/\D/g, "").length >= 10;
                var temEndereco = dadosPedido.endereco.trim() !== "" || dadosPedido.numero !== "" || dadosPedido.bairro.trim() !== "";
                if (temTelefone && temEndereco) {
                    popupSalvarEndereco.abrirPara(acao, dadosPedido, telaEntrega.enderecoEncontradoNoServidor);
                    return ;
                }
                if (acao === "imprimir")
                    prosseguirImprimir(dadosPedido);
                else
                    prosseguirLancar(dadosPedido);
            }

            function limparFormularioPedido() {
                // O pedido virou comanda: o rascunho cumpriu o papel dele.
                // Esta função só é chamada dos dois caminhos de SUCESSO
                // (_imprimirAutorizado e _lancarAutorizado) — sair da tela não
                // passa por aqui, e por isso não descarta nada.
                if (telaEntrega.rascunhoId !== "") {
                    rascunhosController.excluirRascunho(telaEntrega.rascunhoId);
                    telaEntrega.rascunhoId = "";
                }

                // A comanda antiga só é apagada AQUI, no sucesso: editar é
                // apagar-e-recriar, e a nova acabou de ser gravada no lugar
                // dela. Descartar um rascunho não passa por este caminho, e é
                // por isso que descartarConteudo() existe separada.
                if (telaEntrega.arquivoOriginal !== "") {
                    consultaController.apagarComanda(telaEntrega.arquivoOriginal);
                    telaEntrega.arquivoOriginal = "";
                }

                zerarCampos();
            }

            // Esvazia o formulário sem apagar nada em disco — usada ao
            // descartar o rascunho que está sendo editado (ver o × da faixa).
            //
            // NÃO chama limparFormularioPedido: aquela apaga a comanda original
            // quando o rascunho é a edição de uma comanda salva, o que aqui
            // seria destruir a venda por ter desistido de corrigi-la. Descartar
            // o rascunho abandona a edição; a comanda continua como estava.
            function descartarConteudo() {
                telaEntrega.arquivoOriginal = "";
                zerarCampos();
            }

            // Só os CAMPOS. Compartilhada pelas duas acima para não existirem
            // duas listas de campos a zerar — a segunda esqueceria o campo
            // novo criado depois.
            function zerarCampos() {
                telaEntrega.manterBaixaAoSalvar = false;
                telaEntrega.enderecoEncontradoNoServidor = false;
                telaEntrega.telefoneEmConsulta = "";
                inputTelefone.text = "";
                inputEndereco.text = "";
                inputNumero.text = "";
                inputBairro.text = "";
                inputObservacao.text = "";
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

            // Uma ou duas colunas conforme o espaço — ver o comentário
            // equivalente em Balcao.qml.
            GridLayout {
                id: rowConteudo

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                columns: conteudoEntrega.empilhado ? 1 : 2
                columnSpacing: Estilo.global.spacing.xxl
                rowSpacing: Estilo.global.spacing.xxl

                Column {
                    Layout.preferredWidth: conteudoEntrega.larguraFormulario
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    spacing: Estilo.global.spacing.xxl

                    Row {
                        spacing: Estilo.global.spacing.md
                        anchors.horizontalCenter: parent.horizontalCenter
                        Icone { nome: "fa6s.motorcycle"; cor: Estilo.screen.entrega.accent; tamanho: Estilo.global.fontSize.title; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "PEDIDO DE ENTREGA"
                            font.pixelSize: Estilo.global.fontSize.title
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.screen.entrega.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Campos Telefone e Nome do Cliente
                    // Alinhados à esquerda, e não centralizados: são mais
                    // estreitos que o formulário (ver larguraCampos), e
                    // centralizados começavam deslocados em relação à lista de
                    // itens e ao bloco de pagamento logo abaixo. Numa tela
                    // estreita, onde ocupam a largura toda, os dois
                    // alinhamentos coincidem.
                    Row {
                        spacing: Estilo.global.spacing.md

                        Column {
                            spacing: 4

                            Text {
                                text: "Telefone"
                                font.pixelSize: Estilo.global.fontSize.sm
                                font.bold: true
                                color: Estilo.global.textSecondary
                            }

                            TextField {
                                id: inputTelefone

                                color: Estilo.global.textInput
                                placeholderTextColor: Estilo.global.textPlaceholder
                                // Evita recursão: reformatar o texto abaixo dispara
                                // onTextChanged de novo, então ignoramos essa segunda
                                // chamada enquanto a primeira ainda está ajustando o texto.
                                property bool reformatando: false

                                placeholderText: "TELEFONE"
                                width: Math.round((conteudoEntrega.larguraCampos - Estilo.global.spacing.md) * 0.46)
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

                                // Dispara a busca de endereço salvo ao SAIR do
                                // campo (não a cada tecla) — ver Connections
                                // com pizzeriaServerController, que preenche
                                // Nome/Endereço/Número/Bairro/Observação quando
                                // a resposta chegar.
                                onEditingFinished: {
                                    var digitos = text.replace(/\D/g, "");
                                    if (digitos.length < 10) {
                                        telaEntrega.telefoneEmConsulta = "";
                                        telaEntrega.enderecoEncontradoNoServidor = false;
                                        return ;
                                    }
                                    telaEntrega.telefoneEmConsulta = digitos;
                                    pizzeriaServerController.buscarPorTelefone(digitos);
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: Estilo.global.inputBackground
                                    border.color: parent.activeFocus ? Estilo.screen.entrega.accent : Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }

                            }
                        }

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
                                width: (conteudoEntrega.larguraCampos - Estilo.global.spacing.md) - Math.round((conteudoEntrega.larguraCampos - Estilo.global.spacing.md) * 0.46)
                                topPadding: 10
                                bottomPadding: 10
                                leftPadding: 10
                                rightPadding: 10
                                text: clienteNome
                                KeyNavigation.tab: inputEndereco
                                KeyNavigation.backtab: inputTelefone
                                Keys.onReturnPressed: inputEndereco.forceActiveFocus()

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: Estilo.global.inputBackground
                                    border.color: parent.activeFocus ? Estilo.screen.entrega.accent : Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }

                            }
                        }

                    }

                    // Campos Endereço e Número
                    Row {
                        spacing: Estilo.global.spacing.md

                        Column {
                            spacing: 4

                            Text {
                                text: "Endereço"
                                font.pixelSize: Estilo.global.fontSize.sm
                                font.bold: true
                                color: Estilo.global.textSecondary
                            }

                            TextField {
                                id: inputEndereco

                                color: Estilo.global.textInput
                                placeholderTextColor: Estilo.global.textPlaceholder
                                placeholderText: "ENDEREÇO"
                                // Mesma capitalizacao do nome do cliente logo acima.
                                // Vale tambem para o endereco que chega preenchido do servidor
                                // (ver onEnderecoEncontrado): a rua cadastrada em minusculo por
                                // outra maquina sai formatada aqui do mesmo jeito.
                                onTextChanged: Texto.capitalizarCampo(inputEndereco)
                                width: Math.round((conteudoEntrega.larguraCampos - Estilo.global.spacing.md) * 0.78)
                                topPadding: 10
                                bottomPadding: 10
                                leftPadding: 10
                                rightPadding: 10
                                text: enderecoInicial
                                KeyNavigation.tab: inputNumero
                                KeyNavigation.backtab: inputNomeCliente
                                Keys.onReturnPressed: inputNumero.forceActiveFocus()

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: Estilo.global.inputBackground
                                    border.color: parent.activeFocus ? Estilo.screen.entrega.accent : Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }

                            }
                        }

                        Column {
                            spacing: 4

                            Text {
                                text: "Número"
                                font.pixelSize: Estilo.global.fontSize.sm
                                font.bold: true
                                color: Estilo.global.textSecondary
                            }

                            TextField {
                                id: inputNumero

                                color: Estilo.global.textInput
                                placeholderTextColor: Estilo.global.textPlaceholder
                                placeholderText: "NÚMERO"
                                width: (conteudoEntrega.larguraCampos - Estilo.global.spacing.md) - Math.round((conteudoEntrega.larguraCampos - Estilo.global.spacing.md) * 0.78)
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
                                    radius: Estilo.global.radius.pill
                                    color: Estilo.global.inputBackground
                                    border.color: parent.activeFocus ? Estilo.screen.entrega.accent : Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }

                            }
                        }

                    }

                    // Campo Bairro
                    Column {
                        spacing: 4

                        Text {
                            text: "Bairro"
                            font.pixelSize: Estilo.global.fontSize.sm
                            font.bold: true
                            color: Estilo.global.textSecondary
                        }

                        TextField {
                            id: inputBairro

                            color: Estilo.global.textInput
                            placeholderTextColor: Estilo.global.textPlaceholder
                            placeholderText: "BAIRRO"
                            // Mesma capitalizacao do nome do cliente logo acima.
                            onTextChanged: Texto.capitalizarCampo(inputBairro)
                            width: conteudoEntrega.larguraCampos
                            topPadding: 10
                            bottomPadding: 10
                            leftPadding: 10
                            rightPadding: 10
                            text: bairroInicial
                            KeyNavigation.tab: inputObservacao
                            KeyNavigation.backtab: inputNumero
                            Keys.onReturnPressed: inputObservacao.forceActiveFocus()

                            background: Rectangle {
                                radius: Estilo.global.radius.pill
                                color: Estilo.global.inputBackground
                                border.color: parent.activeFocus ? Estilo.screen.entrega.accent : Estilo.global.border
                                border.width: Estilo.global.borderWidth.hairline
                            }

                        }
                    }

                    // Campo Observação (geral da entrega)
                    Column {
                        spacing: 4

                        Text {
                            text: "Observação"
                            font.pixelSize: Estilo.global.fontSize.sm
                            font.bold: true
                            color: Estilo.global.textSecondary
                        }

                        TextField {
                            id: inputObservacao

                            color: Estilo.global.textInput
                            placeholderTextColor: Estilo.global.textPlaceholder
                            placeholderText: "OBSERVAÇÃO"
                            // So a primeira letra, ao contrario do nome/endereco acima:
                            // observacao e frase, nao nome proprio (ver capitalizarFrase em
                            // components/Texto.js).
                            onTextChanged: Texto.capitalizarCampoFrase(inputObservacao)
                            width: conteudoEntrega.larguraCampos
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
                                radius: Estilo.global.radius.pill
                                color: Estilo.global.inputBackground
                                border.color: parent.activeFocus ? Estilo.screen.entrega.accent : Estilo.global.border
                                border.width: Estilo.global.borderWidth.hairline
                            }

                        }
                    }

                    // Espaçador extra para separar os dados do cliente/entrega da seção de pedido
                    Item {
                        width: 1
                        height: 20
                    }

                    Row {
                        spacing: Estilo.global.spacing.sm
                        anchors.horizontalCenter: parent.horizontalCenter
                        Icone { nome: "fa6s.pizza-slice"; cor: Estilo.screen.entrega.accent; tamanho: 16; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "ITENS DO PEDIDO"
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.bold: true
                            color: Estilo.screen.entrega.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // --- CABEÇALHO DA LISTA DE PEDIDOS (rótulo das colunas, uma vez só —
                    // repetir em cada linha do delegate abaixo poluiria a lista) ---
                    Row {
                        width: conteudoEntrega.larguraFormulario
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Estilo.global.spacing.md

                        Text { text: "Pedido"; width: conteudoEntrega.gradePedido.pedido; font.pixelSize: Estilo.global.fontSize.sm; font.bold: true; color: Estilo.global.textSecondary }
                        Text { text: "Observação"; width: conteudoEntrega.gradePedido.observacao; font.pixelSize: Estilo.global.fontSize.sm; font.bold: true; color: Estilo.global.textSecondary }
                        Text { text: "Valor"; width: conteudoEntrega.gradePedido.valor; font.pixelSize: Estilo.global.fontSize.sm; font.bold: true; color: Estilo.global.textSecondary }
                    }

                    // --- LISTA DINÂMICA DE PEDIDOS ---
                    ListView {
                        id: listaPedidos

                        width: conteudoEntrega.larguraFormulario
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
                            corDestaque: Estilo.screen.entrega.accent
                            campoExternoAnterior: inputObservacao
                            campoExternoProximo: camposPagamento.primeiroCampo
                            onSelecionarPedido: function(indice) {
                                telaEntrega.indicePedidoAtual = indice;
                                popupSelecaoPedido.open();
                            }
                            onEditarExtras: function(indice, modo, analise) {
                                popupExtrasItem.abrirPara(indice, modo, analise);
                            }
                        }

                    }

                    // --- SEÇÃO DE PAGAMENTO ---
                    Row {
                        spacing: Estilo.global.spacing.sm
                        anchors.horizontalCenter: parent.horizontalCenter
                        Icone { nome: "fa6s.credit-card"; cor: Estilo.screen.entrega.accent; tamanho: 16; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "PAGAMENTO"
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.bold: true
                            color: Estilo.screen.entrega.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Flow: se os campos de pagamento (que aqui são quatro,
                    // com a taxa de entrega) e o seletor de cópias não
                    // couberem lado a lado, "Cópias" desce uma linha em vez de
                    // ficar fora da tela.
                    Flow {
                        spacing: Estilo.global.spacing.md
                        width: conteudoEntrega.larguraFormulario

                        CamposPagamento {
                            id: camposPagamento

                            // Desconta o seletor de cópias — o que sobra é o
                            // que os campos têm para dividir entre si.
                            larguraDisponivel: conteudoEntrega.larguraFormulario - 100
                            corDestaque: Estilo.screen.entrega.accent
                            formaPagamentoInicial: telaEntrega.formaPagamentoInicial
                            trocoInicial: telaEntrega.trocoInicial
                            statusPagamentoInicial: telaEntrega.statusPagamentoInicial
                            mostrarTaxaEntrega: true
                            taxaEntregaInicial: telaEntrega.taxaEntregaInicial
                            obterCampoAnterior: function() {
                                return ultimoCampoValor();
                            }
                            proximoCampo: spinnerCopias
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
                                font.pixelSize: Estilo.global.fontSize.sm
                                font.bold: true
                                color: Estilo.global.textSecondary
                            }

                            SpinnerCopias {
                                id: spinnerCopias

                                value: 2
                                corDestaque: Estilo.screen.entrega.accent
                                KeyNavigation.tab: btnImprimir
                                KeyNavigation.backtab: camposPagamento.ultimoCampo
                            }
                        }

                    }

                    // --- BOTÕES DE AÇÃO INFERIORES ---
                    // Flow pelo mesmo motivo do Balcão: os três botões
                    // repartem a largura do formulário e quebram para a linha
                    // de baixo quando nem assim couberem.
                    Flow {
                        spacing: Estilo.global.spacing.xl
                        width: conteudoEntrega.larguraFormulario

                        // Botão Imprimir
                        Button {
                            id: btnImprimir

                            padding: Estilo.global.padding.md
                            width: conteudoEntrega.larguraBotaoAcao
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
                                confirmarSalvarEnderecoEProsseguir("imprimir", dados);
                            }

                            contentItem: Row {
                                spacing: Estilo.global.spacing.xs
                                anchors.centerIn: parent
                                Icone { nome: "fa6s.print"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: "Imprimir"
                                    font.family: Estilo.global.fontFamily.title
                                    color: Estilo.global.textOnAccent
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            background: Rectangle {
                                radius: Estilo.global.radius.pill
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
                            width: conteudoEntrega.larguraBotaoAcao
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
                                confirmarSalvarEnderecoEProsseguir("lancar", dados);
                            }

                            contentItem: Row {
                                spacing: Estilo.global.spacing.xs
                                anchors.centerIn: parent
                                Icone { nome: "fa6s.floppy-disk"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: "Lançar"
                                    font.family: Estilo.global.fontFamily.title
                                    color: Estilo.global.textOnAccent
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            background: Rectangle {
                                radius: Estilo.global.radius.pill
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
                            width: conteudoEntrega.larguraBotaoAcao
                            focusPolicy: Qt.StrongFocus
                            KeyNavigation.tab: inputTelefone
                            KeyNavigation.backtab: btnLancar
                            Keys.onReturnPressed: clicked()
                            onClicked: {
                                // Ver o mesmo comentário em Balcao.qml.
                                if (stackViewLocal.depth > 1)
                                    stackViewLocal.pop();
                                else if (telaEntrega.StackView.view)
                                    telaEntrega.StackView.view.irParaInicio();
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
                                // Anel de foco mais grosso: só aparece navegando
                                // por teclado, para dar pra ver onde o Tab chegou.
                                border.color: parent.activeFocus ? Estilo.global.text : Estilo.action.danger.pressed
                                border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                            }

                        }

                    }

                }

                ResumoComanda {
                    Layout.preferredWidth: conteudoEntrega.larguraResumo
                    Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                    itens: modeloPedidos
                    corDestaque: Estilo.screen.entrega.accent
                    formaPagamento: camposPagamento.formaPagamento
                    troco: camposPagamento.formaPagamento === "Dinheiro" ? camposPagamento.troco : ""
                    pago: camposPagamento.pago
                    taxaEntrega: camposPagamento.taxaEntrega
                    mostrarTaxaEntrega: true
                }

            }

            }

            // Só abre quando comandaVazia() barra o clique em Imprimir/Lançar
            // (ver os dois onClicked acima) — nunca some sem resposta: ou o
            // usuário escolhe teste/normal, ou fecha sem prosseguir.
            // Guarda de Imprimir/Lançar (ver prosseguirImprimir).
            PopupAutorizacao {
                id: popupAutorizacao
            }

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

            // Só abre quando confirmarSalvarEnderecoEProsseguir() decide que
            // vale perguntar (telefone + algum dado de endereço presentes).
            PopupSalvarEndereco {
                id: popupSalvarEndereco

                onRespondido: function(salvar) {
                    // Sem reconferir o servidor: o popup fica na tela
                    // esperando uma decisão e a hospedeira pode cair nesse
                    // intervalo, mas isso deixou de importar — salvarEndereco
                    // enfileira antes de tentar subir, então a resposta "Salvar"
                    // vale igual com ou sem servidor no ar. Quem conta o que
                    // aconteceu é o onEnderecoSalvo, que distingue "salvo no
                    // servidor" de "guardado para subir depois".
                    if (salvar)
                        pizzeriaServerController.salvarEndereco(dados);

                    if (acaoPendente === "imprimir")
                        prosseguirImprimir(dados);
                    else
                        prosseguirLancar(dados);
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
