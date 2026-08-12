import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

// Fechamento de caixa diário — soma o total de todas as comandas lançadas
// no dia (Balcão/Entrega/Mesa, ver controllers/fechamentoController.py) e
// mostra de onde cada valor vem. Comandas suspeitas (ver
// comandaParserService.eh_suspeita) ganham borda vermelha na própria lista,
// em vez de uma área separada.
//
// O resumo é recalculado sozinho ao abrir a página (ou trocar de dia) —
// "hoje" sempre ao vivo, dias passados usam o cache local quando já existe
// (ver FechamentoController.obterFechamento). O botão "Fechar Caixa" força
// um recálculo na hora, pro caso de outra máquina ter lançado uma comanda
// nova enquanto esta tela já estava aberta.
Page {
    id: telaFechamento

    objectName: "telaFechamento"

    // ===== MEDIDAS DO LAYOUT =====
    // Esta tela é toda feita de Layouts, então já acompanhava a largura da
    // janela — mas só até certo ponto: um Layout nunca encolhe um filho
    // abaixo do tamanho que ele pede, e o cabeçalho (título + navegação de
    // data + quatro botões) mais os dois painéis lado a lado pediam bem mais
    // de 900px. O que passava disso simplesmente saía pela direita.
    readonly property real larguraUtil: width - Estilo.global.padding.xl * 2
    readonly property bool empilhado: larguraUtil < 900

    // Digitar qualquer letra/número em qualquer lugar da tela já começa a
    // busca, sem precisar clicar na barra primeiro. A página fica com o foco
    // do teclado (focus + o forceActiveFocus de StackView.onActivated abaixo)
    // e repassa a primeira tecla para o campo, que assume o foco a partir daí.
    //
    // event.text cobre exatamente o que se quer: vem preenchido para teclas
    // que produzem caractere e vazio para Shift/Ctrl/setas/F5. O filtro de
    // controle descarta Backspace, Tab, Enter e Esc, que também trazem texto
    // mas não são "começar a escrever". Ctrl/Alt pressionados ficam de fora
    // para não sequestrar atalhos.
    focus: true
    Keys.onPressed: function (event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return;
        if (!event.text || event.text.length === 0)
            return;
        if (event.text.charCodeAt(0) < 32 || event.key === Qt.Key_Delete)
            return;

        telaFechamento.comecarBusca(event.text);
        event.accepted = true;
    }

    // "AAAA-MM-DD" — sempre preenchida (ver hojeIso()/carregarDia()).
    property string dataSelecionada: ""
    // {data, total, quantidade, porTipo, abertas, extras} — {} antes da
    // primeira carga.
    property var resumoAtual: ({})

    // --- Busca no mapeamento por origem ---

    // O que está digitado na barra de busca. Filtra as comandas de todos os
    // tipos ao mesmo tempo (ver comandasDoTipo).
    property string termoBusca: ""
    // Normalizado uma vez por digitação, e não a cada comanda comparada: o
    // outro lado da comparação (o campo "busca" de cada comanda) já vem
    // normalizado do Python — ver FechamentoController._texto_de_busca.
    readonly property string _termoNormalizado: telaFechamento._normalizar(telaFechamento.termoBusca)
    readonly property bool buscando: telaFechamento._termoNormalizado !== ""

    // Comandas do dia que ainda não receberam baixa — vendas que existem mas
    // estão fora do caixa (ver services/rede/baixaComandas.py). A chave
    // "abertas" não existe em resumos gravados em cache por versões
    // anteriores, daí o valor padrão.
    readonly property var _abertas: telaFechamento.resumoAtual.abertas || ({
        "quantidade": 0,
        "total": 0
    })
    readonly property int quantidadeAberta: telaFechamento._abertas.quantidade || 0
    readonly property real totalAberto: telaFechamento._abertas.total || 0

    // Pagamentos de diária a funcionários lançados no dia — dinheiro que
    // sai do caixa fora de qualquer venda (ver services/rede/extrasCaixa.py
    // e FechamentoController._calcular_resumo_dia). A chave "extras" não
    // existe em resumos gravados em cache antes desta feature existir, daí
    // o valor padrão — mesmo cuidado de "_abertas" acima.
    readonly property var _extras: telaFechamento.resumoAtual.extras || ({
        "quantidade": 0,
        "total": 0,
        "itens": []
    })
    readonly property int quantidadeExtras: telaFechamento._extras.quantidade || 0
    readonly property real totalExtras: telaFechamento._extras.total || 0

    // Contagem manual de Cartão/Dinheiro/Pix do dia (ver
    // services/rede/contagemCaixa.py) — diferente de resumoAtual, não vem
    // do recálculo das comandas: é preenchida à parte por carregarDia() e
    // sobrescrita pelo popup de Contagem.
    property var contagemAtual: ({
        "cartao": 0,
        "dinheiro": 0,
        "pix": 0
    })
    readonly property real totalContagem: (telaFechamento.contagemAtual.cartao || 0)
        + (telaFechamento.contagemAtual.dinheiro || 0)
        + (telaFechamento.contagemAtual.pix || 0)

    // Fórmula de como o Lucro é calculado (ver
    // services/formulaLucroService.py e PopupFormulaLucro.qml) — não é por
    // dia, é uma configuração única da malha inteira; carregada uma vez e
    // atualizada sozinha quando muda (aqui ou em outra máquina).
    property var formulaAtual: ({
        "contagem": "somar",
        "extras": "subtrair",
        "bruto": "subtrair"
    })

    function _multiplicadorSinal(sinal) {
        if (sinal === "somar")
            return 1;
        if (sinal === "subtrair")
            return -1;
        return 0;
    }

    readonly property real lucro: telaFechamento.totalContagem * telaFechamento._multiplicadorSinal(telaFechamento.formulaAtual.contagem)
        + telaFechamento.totalExtras * telaFechamento._multiplicadorSinal(telaFechamento.formulaAtual.extras)
        + (telaFechamento.resumoAtual.total || 0) * telaFechamento._multiplicadorSinal(telaFechamento.formulaAtual.bruto)

    readonly property var ordemTipos: ["Balcão", "Entrega", "Mesa"]
    readonly property var coresTipo: ({
        "Balcão": Estilo.orderType.balcao.base,
        "Entrega": Estilo.orderType.entrega.base,
        "Mesa": Estilo.orderType.mesa.base
    })

    function _doisDigitos(numero) {
        return numero < 10 ? "0" + numero : String(numero);
    }

    function _isoDeData(d) {
        return d.getFullYear() + "-" + _doisDigitos(d.getMonth() + 1) + "-" + _doisDigitos(d.getDate());
    }

    function hojeIso() {
        return _isoDeData(new Date());
    }

    function somarDias(iso, delta) {
        var partes = iso.split("-").map(Number);
        var d = new Date(partes[0], partes[1] - 1, partes[2]);
        d.setDate(d.getDate() + delta);
        return _isoDeData(d);
    }

    function formatarDataExibicao(iso) {
        if (!iso)
            return "";

        var partes = iso.split("-");
        return partes[2] + "/" + partes[1] + "/" + partes[0];
    }

    function mostrarNotificacao(mensagem, sucesso) {
        filaNotificacoes.notificar(mensagem, sucesso);
    }

    // Info de um tipo específico (Balcão/Entrega/Mesa) já com um valor
    // padrão seguro — nem toda comanda existe todo dia (ex: nenhuma
    // Entrega hoje), e porTipo só carrega as chaves que de fato tiveram
    // alguma comanda (ver FechamentoController._calcular_resumo_dia).
    function infoTipo(tipo) {
        var mapa = telaFechamento.resumoAtual.porTipo || {};
        return mapa[tipo] || {
            "total": 0,
            "quantidade": 0,
            "comandas": []
        };
    }

    // "Açaí" -> "acai". Mesma normalização que o Python aplica ao montar o
    // campo "busca" de cada comanda, para os dois lados da comparação
    // combinarem sem acento e sem diferença de caixa.
    function _normalizar(texto) {
        return (texto || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    }

    // As comandas de um tipo que casam com a busca atual — todas, quando não
    // há busca.
    //
    // É uma varredura simples pelo campo de busca de cada comanda. Não dá pra
    // usar busca binária aqui: ela exige dados ordenados pela chave procurada
    // e só responde "existe este valor exato", enquanto o que se quer é
    // "contém este trecho" em qualquer posição de qualquer campo — um termo
    // como "pizza" tem que achar comandas cujo texto NÃO começa por ele. Na
    // prática o custo não aparece: é um dia de comandas (dezenas a poucas
    // centenas), refiltrado a cada tecla em menos de um milissegundo.
    function comandasDoTipo(tipo) {
        var todas = telaFechamento.infoTipo(tipo).comandas || [];
        if (!telaFechamento.buscando)
            return todas;

        var termo = telaFechamento._termoNormalizado;
        var achadas = [];
        for (var i = 0; i < todas.length; i++) {
            // Comandas de um resumo gravado em cache antes desta busca
            // existir não têm o campo — caem fora em vez de derrubar a tela.
            var alvo = todas[i].busca || "";
            if (alvo.indexOf(termo) >= 0)
                achadas.push(todas[i]);
        }
        return achadas;
    }

    function totalDoTipo(tipo) {
        if (!telaFechamento.buscando)
            return telaFechamento.infoTipo(tipo).total || 0;

        var achadas = telaFechamento.comandasDoTipo(tipo);
        var soma = 0;
        for (var i = 0; i < achadas.length; i++)
            soma += Number(achadas[i].valor) || 0;
        return soma;
    }

    function totalEncontrado() {
        var total = 0;
        for (var i = 0; i < telaFechamento.ordemTipos.length; i++)
            total += telaFechamento.comandasDoTipo(telaFechamento.ordemTipos[i]).length;
        return total;
    }

    // Chamado pela captura de teclado da página: qualquer caractere digitado
    // fora de um campo de texto começa a busca (ver Keys.onPressed).
    function comecarBusca(texto) {
        campoBusca.forceActiveFocus();
        if (texto)
            campoBusca.insert(campoBusca.length, texto);
    }

    function limparBusca() {
        telaFechamento.termoBusca = "";
        campoBusca.text = "";
    }

    function carregarDia(iso) {
        // A busca vale para o dia que está na tela: trocar de dia com um termo
        // antigo ainda filtrando esconderia comandas sem explicação.
        telaFechamento.limparBusca();
        telaFechamento.dataSelecionada = iso;
        telaFechamento.resumoAtual = fechamentoController.obterFechamento(iso);
        telaFechamento.contagemAtual = fechamentoController.obterContagem(iso);
    }

    // Chamado pelos campos de Cartão/Dinheiro/Pix (botão "Salvar
    // contagem") — sobrescreve a contagem do dia visualizado e atualiza a
    // tela na hora com o que foi de fato salvo.
    function salvarContagem(cartaoTexto, dinheiroTexto, pixTexto) {
        telaFechamento.contagemAtual = fechamentoController.registrarContagem(telaFechamento.dataSelecionada, cartaoTexto, dinheiroTexto, pixTexto);
        telaFechamento.mostrarNotificacao("Contagem de " + telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada) + " salva.", true);
    }

    function _carregarFormula() {
        telaFechamento.formulaAtual = formulaLucroController.obterConfiguracao();
    }

    function abrirFormulaLucro() {
        popupFormulaLucro.abrirCom(telaFechamento.formulaAtual);
    }

    function fecharCaixa() {
        telaFechamento.resumoAtual = fechamentoController.calcularFechamento(telaFechamento.dataSelecionada);
        fechamentoController.imprimirFechamentoCaixa(telaFechamento.dataSelecionada);
        telaFechamento.mostrarNotificacao("Caixa de " + telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada) + " recalculado, salvo e enviado para impressão.", true);
    }

    function abrirFechamentoRapido() {
        if (!popupFechamentoRapido.abrirPara(telaFechamento.dataSelecionada))
            telaFechamento.mostrarNotificacao("Nenhuma comanda em aberto em " + telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada) + ".", true);
    }

    // Age sobre o dia visualizado (dataSelecionada), não necessariamente
    // hoje — permite lançar uma diária esquecida de um dia anterior, mesmo
    // comportamento do botão "Fechar Caixa".
    function abrirExtras() {
        popupExtras.abrirPara(telaFechamento.dataSelecionada);
    }

    // Correção de uma comanda já fechada — único caminho pra isso agora
    // (ver ItemComandaDelegate.qml, que escondeu lápis/lixeira de comandas
    // fechadas na Consulta). Fila espelhada da de "Fechamento rápido", só
    // que sobre as que já têm baixa.
    function abrirEditarCaixa() {
        if (!popupFechamentoRapido.abrirParaFechadas(telaFechamento.dataSelecionada))
            telaFechamento.mostrarNotificacao("Nenhuma comanda fechada em " + telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada) + ".", true);
    }

    // Conexão declarativa, não um .connect() solto em Component.onCompleted
    // — mesmo motivo documentado em Balcao.qml/Rede.qml: fechamentoController
    // é global e vive pra sempre, então a conexão precisa estar presa ao
    // ciclo de vida desta página (Connections), não solta num closure.
    Connections {
        target: fechamentoController

        // Se outra máquina fechar o caixa do dia que está sendo exibido
        // aqui agora, recarrega sozinha — mesmo espírito de
        // SalaoController.mesasAtualizadas.
        function onFechamentoAtualizado(data) {
            if (data === telaFechamento.dataSelecionada)
                telaFechamento.carregarDia(data);
        }

        // Qualquer baixa (aqui ou em outra máquina da malha) muda o total do
        // dia e o contador de abertas. Recarregar o dia exibido cobre os
        // dois casos; o daqui só recarrega o que darBaixa() acabou de
        // recalcular, o que é barato e mantém um caminho só.
        function onBaixasAtualizadas() {
            telaFechamento.carregarDia(telaFechamento.dataSelecionada);
        }

        // Contagem editada em outra máquina, pro mesmo dia sendo exibido
        // aqui agora — mesmo espírito de onFechamentoAtualizado.
        function onContagemAtualizada(data) {
            if (data === telaFechamento.dataSelecionada)
                telaFechamento.carregarDia(data);
        }
    }

    // formulaLucroController é global e a fórmula não é por dia — trocada
    // em outra máquina, precisa recarregar aqui mesmo sem trocar de dia.
    Connections {
        target: formulaLucroController

        function onFormulaAlterada() {
            telaFechamento._carregarFormula();
        }
    }

    // A reimpressão pedida pelo popup é assíncrona e pode acontecer em outra
    // máquina da malha (ver rede.solicitar_impressao) — o resultado só chega
    // por aqui, do mesmo jeito que em Balcao.qml/Entrega.qml.
    Connections {
        target: redeController
        // Só enquanto esta página está à vista: redeController é global e o
        // sinal é o mesmo de qualquer impressão do app — sem isto, imprimir
        // um pedido no Balcão enfileiraria um "Comanda reimpressa" aqui.
        enabled: telaFechamento.visible

        function onImpressaoResultado(sucesso, mensagem) {
            telaFechamento.mostrarNotificacao(sucesso ? ("Comanda reimpressa (" + mensagem + ")") : ("Falha ao reimprimir: " + mensagem), sucesso);
        }
    }

    // Os campos de Cartão/Dinheiro/Pix são TextField comuns (não bindings
    // declarativos): assim que o usuário digita algo, QML desfaz o binding
    // daquele campo com contagemAtual pra sempre (comportamento normal de
    // TextField) — sem isto, trocar de dia e voltar mostraria o valor
    // digitado no dia anterior em vez do que está salvo pra este dia.
    onContagemAtualChanged: {
        inputCartao.text = "R$ " + Number(telaFechamento.contagemAtual.cartao || 0).toFixed(2).replace(".", ",");
        inputDinheiro.text = "R$ " + Number(telaFechamento.contagemAtual.dinheiro || 0).toFixed(2).replace(".", ",");
        inputPix.text = "R$ " + Number(telaFechamento.contagemAtual.pix || 0).toFixed(2).replace(".", ",");
    }

    // obterFechamento/obterContagem varrem as comandas do dia no disco e
    // remontam o resumo; obterConfiguracao lê a fórmula de lucro. Chamados
    // direto de Component.onCompleted, seguravam a tela inteira antes do
    // primeiro pixel — agora entram depois do primeiro quadro, com a página já
    // desenhada (ver components/CargaDiferida.qml).
    CargaDiferida {
        id: carga

        tarefa: function() {
            _carregarFormula();
            carregarDia(telaFechamento.dataSelecionada || hojeIso());
        }
    }

    Component.onCompleted: {
        // A data em si é só uma conta de calendário (nenhum acesso a disco), e
        // é ela que o cabeçalho mostra — fica aqui pra tela já nascer com o dia
        // certo escrito, em vez de piscar um campo de data vazio até a leitura
        // terminar.
        telaFechamento.dataSelecionada = hojeIso();
        carga.agendar();
    }
    StackView.onActivated: {
        carga.agendar();
        // Sem isto, a primeira tecla digitada ao chegar na tela não chega em
        // Keys.onPressed: o foco do teclado continua em quem estava antes na
        // pilha de telas. Fica FORA da tarefa diferida de propósito: mexer no
        // foco é parte de montar a tela, não de carregar dado, e adiar isso
        // perderia as primeiras teclas de quem já chega digitando.
        telaFechamento.forceActiveFocus();
    }

    background: Rectangle {
        color: Estilo.global.background
        radius: Estilo.global.radius.xl
    }

    // Rola quando os painéis empilham e a página fica mais alta que a
    // janela — sem isto, o bloco de Lucro (o último) ficava escondido atrás
    // do botão "Voltar para o Menu", sem jeito de alcançá-lo.
    Flickable {
        id: rolagemFechamento

        anchors.fill: parent
        anchors.margins: Estilo.global.padding.xl
        clip: true
        contentWidth: width
        contentHeight: colunaFechamento.height
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: colunaFechamento

            width: rolagemFechamento.width
            // Empilhada, a coluna cresce até onde o conteúdo pedir e o Flickable
            // rola; lado a lado, ela cabe na janela como sempre coube.
            height: telaFechamento.empilhado ? implicitHeight : rolagemFechamento.height
            spacing: Estilo.global.spacing.xl

            // --- CABEÇALHO ---
            // Duas colunas (título | controles) enquanto couberem lado a lado;
            // uma só quando não couberem, com os controles fluindo para as linhas
            // seguintes em vez de saírem pela borda.
            GridLayout {
                Layout.fillWidth: true
                columns: telaFechamento.empilhado ? 1 : 2
                columnSpacing: Estilo.global.spacing.xl
                rowSpacing: Estilo.global.spacing.md

                Row {
                    spacing: Estilo.global.spacing.sm
                    Icone { nome: "fa6s.cash-register"; cor: Estilo.screen.caixa.accent; tamanho: Estilo.global.fontSize.title; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "FECHAMENTO DE CAIXA"
                        font.pixelSize: Estilo.global.fontSize.title
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.screen.caixa.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Controles do dia: navegação de data e as ações do caixa.
                // Encostados à direita quando há espaço (como sempre foram), e
                // quebrando em linhas quando não há.
                Flow {
                    Layout.fillWidth: telaFechamento.empilhado
                    Layout.maximumWidth: telaFechamento.larguraUtil
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    spacing: Estilo.global.spacing.md

                // --- NAVEGAÇÃO DE DATA ---
                Row {
                    spacing: Estilo.global.spacing.sm

                    Button {
                        text: "◀"
                        padding: 8
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: telaFechamento.carregarDia(telaFechamento.somarDias(telaFechamento.dataSelecionada, -1))

                        contentItem: Text {
                            text: parent.text
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            horizontalAlignment: Text.AlignHCenter
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
                            color: parent.down ? Estilo.screen.caixa.pressed : (parent.hovered ? Estilo.screen.caixa.hover : Estilo.screen.caixa.base)
                        }
                    }

                    Rectangle {
                        width: 130
                        height: 36
                        radius: Estilo.global.radius.sm
                        color: Estilo.global.surface
                        border.color: Estilo.global.borderCard
                        border.width: Estilo.global.borderWidth.hairline
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada)
                            font.bold: true
                            font.pixelSize: Estilo.global.fontSize.lg
                            color: Estilo.global.text
                        }
                    }

                    Button {
                        text: "▶"
                        padding: 8
                        enabled: telaFechamento.dataSelecionada !== telaFechamento.hojeIso()
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: telaFechamento.carregarDia(telaFechamento.somarDias(telaFechamento.dataSelecionada, 1))

                        contentItem: Text {
                            text: parent.text
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            horizontalAlignment: Text.AlignHCenter
                            opacity: parent.enabled ? 1 : Estilo.global.opacity.disabled
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
                            opacity: parent.enabled ? 1 : Estilo.global.opacity.disabled
                            color: parent.down ? Estilo.screen.caixa.pressed : (parent.hovered ? Estilo.screen.caixa.hover : Estilo.screen.caixa.base)
                        }
                    }
                }

                Button {
                    id: btnEditarCaixa

                    padding: Estilo.global.padding.md
                    focusPolicy: Qt.StrongFocus
                    enabled: telaFechamento.resumoAtual.quantidade > 0
                    onClicked: telaFechamento.abrirEditarCaixa()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.pen-to-square"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Editar caixa"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: {
                            if (!btnEditarCaixa.enabled)
                                return Estilo.global.border;
                            return btnEditarCaixa.down ? Estilo.action.save.pressed : (btnEditarCaixa.hovered ? Estilo.action.save.hover : Estilo.action.save.base);
                        }
                        border.color: btnEditarCaixa.activeFocus ? Estilo.global.text : "transparent"
                        border.width: btnEditarCaixa.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                    }
                }

                Button {
                    id: btnFechamentoRapido

                    padding: Estilo.global.padding.md
                    focusPolicy: Qt.StrongFocus
                    enabled: telaFechamento.quantidadeAberta > 0
                    onClicked: telaFechamento.abrirFechamentoRapido()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.list-check"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: telaFechamento.quantidadeAberta > 0
                                ? "Fechamento rápido (" + telaFechamento.quantidadeAberta + ")"
                                : "Fechamento rápido"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: {
                            if (!btnFechamentoRapido.enabled)
                                return Estilo.global.border;
                            return btnFechamentoRapido.down ? Estilo.action.review.pressed : (btnFechamentoRapido.hovered ? Estilo.action.review.hover : Estilo.action.review.base);
                        }
                        border.color: btnFechamentoRapido.activeFocus ? Estilo.global.text : "transparent"
                        border.width: btnFechamentoRapido.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                    }
                }

                Button {
                    id: btnExtras

                    padding: Estilo.global.padding.md
                    focusPolicy: Qt.StrongFocus
                    onClicked: telaFechamento.abrirExtras()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.hand-holding-dollar"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Extras"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnExtras.down ? Estilo.action.outflow.pressed : (btnExtras.hovered ? Estilo.action.outflow.hover : Estilo.action.outflow.base)
                        border.color: btnExtras.activeFocus ? Estilo.global.text : "transparent"
                        border.width: btnExtras.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                    }
                }

                Button {
                    id: btnFecharCaixa

                    padding: Estilo.global.padding.md
                    focusPolicy: Qt.StrongFocus
                    onClicked: telaFechamento.fecharCaixa()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.lock"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Fechar Caixa"
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

                }
            }

            // --- TOTAL DO DIA (destaque) ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: colunaTotalDia.implicitHeight + 30
                radius: Estilo.global.radius.md
                color: Estilo.status.success.background
                border.color: Estilo.status.success.border
                border.width: Estilo.global.borderWidth.hairline

                ColumnLayout {
                    id: colunaTotalDia

                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "TOTAL DO DIA"
                        font.pixelSize: Estilo.global.fontSize.md
                        font.bold: true
                        color: Estilo.global.textSecondary
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "R$ " + (telaFechamento.resumoAtual.total || 0).toFixed(2).replace(".", ",")
                        font.pixelSize: Estilo.global.fontSize.display
                        font.bold: true
                        color: Estilo.finance.positive
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: (telaFechamento.resumoAtual.quantidade || 0) + (telaFechamento.resumoAtual.quantidade === 1 ? " comanda" : " comandas")
                        font.pixelSize: Estilo.global.fontSize.md
                        color: Estilo.global.textSecondary
                    }

                    // O que foi vendido mas ainda não entrou no caixa. Fica
                    // junto do total de propósito: sem isto, um dia com metade
                    // das comandas sem baixa mostraria um total menor sem
                    // nenhuma pista do motivo.
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 6
                        visible: telaFechamento.quantidadeAberta > 0
                        text: telaFechamento.quantidadeAberta
                            + (telaFechamento.quantidadeAberta === 1 ? " comanda em aberto · " : " comandas em aberto · ")
                            + "R$ " + telaFechamento.totalAberto.toFixed(2).replace(".", ",") + " fora do caixa"
                        font.pixelSize: Estilo.global.fontSize.md
                        font.bold: true
                        color: Estilo.finance.outflow
                    }
                }
            }

            // --- MAPEAMENTO POR ORIGEM (esquerda) + SUSPEITAS (direita) ---
            // Lado a lado enquanto couberem; empilhados quando não couberem — a
            // contagem de caixa passa a ficar embaixo do mapeamento, com a
            // rolagem da página dando conta da altura.
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: !telaFechamento.empilhado
                columns: telaFechamento.empilhado ? 1 : 2
                columnSpacing: Estilo.global.spacing.xl
                rowSpacing: Estilo.global.spacing.xl

                // --- MAPEAMENTO POR ORIGEM ---
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Estilo.global.spacing.md

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Estilo.global.spacing.sm

                        Text {
                            text: "Mapeamento por origem"
                            font.pixelSize: Estilo.global.fontSize.lg
                            font.bold: true
                            color: Estilo.global.textSecondary
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            visible: telaFechamento.buscando
                            text: {
                                var n = telaFechamento.totalEncontrado();
                                return n === 1 ? "1 comanda encontrada" : n + " comandas encontradas";
                            }
                            font.pixelSize: Estilo.global.fontSize.sm
                            color: telaFechamento.totalEncontrado() > 0 ? Estilo.global.textSecondary : Estilo.action.danger.base
                        }
                    }

                    // --- BUSCA ---
                    // Aceita modalidade (Balcão/Entrega/Mesa), nome do cliente,
                    // código, forma de pagamento, item pedido e valor — tudo o que
                    // o Python empacotou no campo "busca" de cada comanda.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: Estilo.global.radius.pill
                        color: Estilo.global.inputBackground
                        border.color: campoBusca.activeFocus ? Estilo.screen.caixa.accent : Estilo.global.borderCard
                        border.width: campoBusca.activeFocus ? 2 : 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: Estilo.global.spacing.sm

                            Icone {
                                nome: "fa6s.magnifying-glass"
                                cor: Estilo.global.textSecondary
                                tamanho: 13
                                Layout.alignment: Qt.AlignVCenter
                            }

                            TextField {
                                id: campoBusca

                                Layout.fillWidth: true
                                placeholderText: "Buscar por modalidade, cliente, pedido ou valor — é só começar a digitar"
                                font.pixelSize: Estilo.global.fontSize.md
                                // Preto explícito: sem isto o Qt usa palette.text,
                                // que no Windows vem do tema do sistema e some no
                                // fundo branco quando o tema é escuro (mesmo
                                // cuidado documentado em qml/estilo/Estilo.qml).
                                color: Estilo.global.text
                                background: Item {}
                                onTextChanged: telaFechamento.termoBusca = text
                                // Esc limpa e devolve o teclado para a página, para
                                // a próxima tecla começar uma busca nova.
                                Keys.onEscapePressed: {
                                    telaFechamento.limparBusca();
                                    telaFechamento.forceActiveFocus();
                                }
                            }

                            Button {
                                visible: telaFechamento.buscando
                                implicitWidth: 26
                                implicitHeight: 26
                                focusPolicy: Qt.NoFocus
                                Layout.alignment: Qt.AlignVCenter
                                onClicked: {
                                    telaFechamento.limparBusca();
                                    telaFechamento.forceActiveFocus();
                                }

                                contentItem: Icone {
                                    nome: "fa6s.xmark"
                                    cor: Estilo.global.textSecondary
                                    tamanho: 12
                                    anchors.centerIn: parent
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.borderCard : "transparent"
                                }
                            }
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: colunaTipos.implicitHeight

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        ColumnLayout {
                            id: colunaTipos

                            width: parent.width
                            spacing: Estilo.global.spacing.lg

                            Repeater {
                                model: telaFechamento.ordemTipos

                                delegate: ColumnLayout {
                                    id: blocoTipo

                                    readonly property var info: telaFechamento.infoTipo(modelData)
                                    // Preso aqui porque lá dentro, na ListView de
                                    // comandas, "modelData" já é a comanda.
                                    readonly property string nomeTipo: modelData
                                    // Só as que casam com a busca (todas quando
                                    // não há busca) — ver comandasDoTipo.
                                    readonly property var comandas: telaFechamento.comandasDoTipo(modelData)
                                    // Fechado por padrão — a lista de comandas só
                                    // aparece quando o box do tipo é clicado (ver
                                    // areaCabecalhoTipo abaixo). Durante uma busca
                                    // abre sozinho: quem digitou quer ver o que
                                    // achou, não um bloco fechado com a contagem.
                                    property bool expandidoManual: false
                                    readonly property bool expandido: telaFechamento.buscando || expandidoManual

                                    Layout.fillWidth: true
                                    // Some por completo quando a busca não achou
                                    // nada aqui, para sobrar só o que interessa.
                                    visible: comandas.length > 0
                                    spacing: Estilo.global.spacing.xs

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: linhaCabecalhoTipo.implicitHeight + 16
                                        radius: Estilo.global.radius.sm
                                        color: Estilo.global.surface
                                        border.color: Estilo.global.borderCard
                                        border.width: Estilo.global.borderWidth.hairline

                                        MouseArea {
                                            id: areaCabecalhoTipo

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: blocoTipo.expandidoManual = !blocoTipo.expandidoManual
                                        }

                                        RowLayout {
                                            id: linhaCabecalhoTipo

                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: Estilo.global.spacing.sm

                                            Rectangle {
                                                width: 10
                                                height: 10
                                                radius: Estilo.global.radius.sm
                                                color: telaFechamento.coresTipo[modelData] || Estilo.global.text
                                                Layout.alignment: Qt.AlignVCenter
                                            }

                                            Text {
                                                text: modelData
                                                font.bold: true
                                                font.pixelSize: Estilo.global.fontSize.lg
                                                color: Estilo.global.text
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: blocoTipo.comandas.length + (blocoTipo.comandas.length === 1 ? " comanda" : " comandas")
                                                font.pixelSize: Estilo.global.fontSize.sm
                                                color: Estilo.global.textSecondary
                                            }

                                            Text {
                                                text: "R$ " + telaFechamento.totalDoTipo(blocoTipo.nomeTipo).toFixed(2).replace(".", ",")
                                                font.bold: true
                                                font.pixelSize: Estilo.global.fontSize.lg
                                                color: telaFechamento.coresTipo[modelData] || Estilo.global.text
                                            }

                                            Icone {
                                                nome: blocoTipo.expandido ? "fa6s.chevron-up" : "fa6s.chevron-down"
                                                cor: Estilo.global.textSecondary
                                                tamanho: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }

                                    // Altura = conteúdo inteiro (sem limite/scroll
                                    // próprio) — quem rola é só o Flickable de
                                    // fora, um scroll só pra "Mapeamento por
                                    // origem" inteiro, em vez de uma caixinha de
                                    // rolagem dentro da outra.
                                    ListView {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 18
                                        Layout.preferredHeight: contentHeight
                                        visible: blocoTipo.expandido
                                        interactive: false
                                        clip: true
                                        spacing: 4
                                        model: blocoTipo.comandas
                                        boundsBehavior: Flickable.StopAtBounds

                                        delegate: Rectangle {
                                            id: itemComandaTipo

                                            // Provável erro de digitação no pedido
                                            // (ver comandaParserService.eh_suspeita)
                                            // — só um aviso visual.
                                            readonly property bool suspeita: modelData.suspeita === true

                                            width: ListView.view.width
                                            height: 40
                                            radius: Estilo.global.radius.sm
                                            color: areaComanda.containsMouse ? Estilo.global.surface : Estilo.global.background
                                            border.color: itemComandaTipo.suspeita
                                                ? Estilo.status.error.content
                                                : (areaComanda.containsMouse ? (telaFechamento.coresTipo[blocoTipo.nomeTipo] || Estilo.global.border) : Estilo.global.borderCard)
                                            border.width: itemComandaTipo.suspeita ? 2 : 1

                                            // Abre a comanda pra conferir e, se
                                            // preciso, corrigir. Estas são as já
                                            // baixadas — as em aberto têm o botão
                                            // "Fechamento rápido" lá em cima — e
                                            // são justamente as que o caixa do
                                            // dia já está contando, ou seja, as
                                            // que um erro de digitação afeta.
                                            MouseArea {
                                                id: areaComanda

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: popupFechamentoRapido.abrirComanda(modelData.arquivo, telaFechamento.dataSelecionada)
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: Estilo.global.spacing.sm

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: (modelData.cliente && modelData.cliente.trim() !== "" ? modelData.cliente : "Sem nome") + " · " + modelData.dataHora
                                                    font.pixelSize: Estilo.global.fontSize.sm
                                                    color: Estilo.global.text
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: modelData.formaPagamento + (modelData.status ? " [" + modelData.status + "]" : "")
                                                    font.pixelSize: Estilo.global.fontSize.xs
                                                    color: Estilo.global.textSecondary
                                                }

                                                Text {
                                                    text: "R$ " + Number(modelData.valor).toFixed(2).replace(".", ",")
                                                    font.bold: true
                                                    font.pixelSize: Estilo.global.fontSize.sm
                                                    color: Estilo.global.text
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: (telaFechamento.resumoAtual.quantidade || 0) === 0
                                text: "Nenhuma comanda lançada neste dia."
                                font.italic: true
                                color: Estilo.global.textSecondary
                            }
                        }
                    }

                    // --- EXTRAS (pagamento de diária, descontado do caixa) ---
                    Rectangle {
                        Layout.fillWidth: true
                        visible: telaFechamento.quantidadeExtras > 0
                        implicitHeight: colunaExtras.implicitHeight + 20
                        radius: Estilo.global.radius.sm
                        color: Estilo.status.pending.background
                        border.color: Estilo.status.pending.border
                        border.width: Estilo.global.borderWidth.hairline

                        ColumnLayout {
                            id: colunaExtras

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10
                            spacing: Estilo.global.spacing.xs

                            Row {
                                spacing: Estilo.global.spacing.xs
                                Icone { nome: "fa6s.hand-holding-dollar"; cor: Estilo.finance.outflow; tamanho: 14; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    text: "Pagamentos de diária (descontados do caixa)"
                                    font.bold: true
                                    font.pixelSize: Estilo.global.fontSize.md
                                    color: Estilo.finance.outflow
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Repeater {
                                model: telaFechamento._extras.itens

                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Estilo.global.spacing.sm

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.funcionario
                                        font.pixelSize: Estilo.global.fontSize.sm
                                        color: Estilo.global.text
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: modelData.dataHora
                                        font.pixelSize: Estilo.global.fontSize.xs
                                        color: Estilo.global.textSecondary
                                    }

                                    Text {
                                        text: "R$ " + Number(modelData.valor).toFixed(2).replace(".", ",")
                                        font.bold: true
                                        font.pixelSize: Estilo.global.fontSize.sm
                                        color: Estilo.finance.outflow
                                    }

                                    Button {
                                        id: btnEditarExtra

                                        implicitWidth: 24
                                        implicitHeight: 24
                                        padding: 0
                                        onClicked: popupExtras.abrirParaEditar(modelData)

                                        contentItem: Icone {
                                            nome: "fa6s.pen"
                                            cor: Estilo.global.textSecondary
                                            tamanho: 11
                                            anchors.centerIn: parent
                                        }

                                        background: Rectangle {
                                            radius: Estilo.global.radius.pill
                                            color: btnEditarExtra.down ? Estilo.action.ghost.pressed : (btnEditarExtra.hovered ? Estilo.action.ghost.hover : Estilo.action.ghost.base)
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                text: "Total descontado: R$ " + telaFechamento.totalExtras.toFixed(2).replace(".", ",")
                                font.bold: true
                                font.pixelSize: Estilo.global.fontSize.md
                                color: Estilo.finance.outflow
                            }
                        }
                    }
                }

                // --- CONTAGEM DE CAIXA ---
                ColumnLayout {
                    // Coluna estreita e fixa ao lado do mapeamento; empilhada,
                    // ocupa a largura toda.
                    Layout.preferredWidth: telaFechamento.empilhado ? telaFechamento.larguraUtil : 340
                    Layout.fillWidth: telaFechamento.empilhado
                    Layout.fillHeight: !telaFechamento.empilhado
                    Layout.alignment: Qt.AlignTop
                    spacing: Estilo.global.spacing.md

                    RowLayout {
                        Layout.fillWidth: true

                        Row {
                            spacing: Estilo.global.spacing.xs
                            Icone { nome: "fa6s.calculator"; cor: Estilo.screen.caixa.base; tamanho: 16; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: "Contagem de caixa"
                                font.pixelSize: Estilo.global.fontSize.lg
                                font.bold: true
                                color: Estilo.screen.caixa.base
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Muda a lógica de como o Lucro abaixo é calculado (ver
                        // PopupFormulaLucro.qml) — engrenagem, não um botão de
                        // texto, porque é uma configuração da malha inteira, não
                        // uma ação do dia visualizado.
                        Button {
                            id: btnFormulaLucro

                            padding: 6
                            focusPolicy: Qt.StrongFocus
                            onClicked: telaFechamento.abrirFormulaLucro()

                            contentItem: Icone {
                                nome: "fa6s.gear"
                                cor: Estilo.global.textSecondary
                                tamanho: 14
                                anchors.centerIn: parent
                            }

                            background: Rectangle {
                                radius: Estilo.global.radius.pill
                                color: btnFormulaLucro.down ? Estilo.action.ghost.pressed : (btnFormulaLucro.hovered ? Estilo.action.ghost.hover : Estilo.action.ghost.base)
                                border.color: Estilo.global.border
                                border.width: Estilo.global.borderWidth.hairline
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: colunaContagem.implicitHeight + 20
                        radius: Estilo.global.radius.md
                        color: Estilo.global.surface
                        border.color: Estilo.global.borderCard
                        border.width: Estilo.global.borderWidth.hairline

                        ColumnLayout {
                            id: colunaContagem

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10
                            spacing: Estilo.global.spacing.md

                            Column {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "Cartão (crédito/débito)"
                                    font.pixelSize: Estilo.global.fontSize.sm
                                    font.bold: true
                                    color: Estilo.global.textSecondary
                                }

                                TextField {
                                    id: inputCartao

                                    width: parent.width
                                    color: Estilo.global.textInput
                                    placeholderTextColor: Estilo.global.textPlaceholder
                                    placeholderText: "VALOR"
                                    topPadding: 10
                                    bottomPadding: 10
                                    leftPadding: 10
                                    rightPadding: 10
                                    validator: Moeda.validador
                                    // Mesmo padrão de inputTroco/inputTaxaEntrega
                                    // em CamposPagamento.qml.
                                    onEditingFinished: text = Moeda.formatar(text)

                                    background: Rectangle {
                                        radius: Estilo.global.radius.pill
                                        color: Estilo.global.inputBackground
                                        border.color: inputCartao.activeFocus ? Estilo.screen.caixa.base : Estilo.global.border
                                        border.width: Estilo.global.borderWidth.hairline
                                    }
                                }
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "Dinheiro (no caixa)"
                                    font.pixelSize: Estilo.global.fontSize.sm
                                    font.bold: true
                                    color: Estilo.global.textSecondary
                                }

                                TextField {
                                    id: inputDinheiro

                                    width: parent.width
                                    color: Estilo.global.textInput
                                    placeholderTextColor: Estilo.global.textPlaceholder
                                    placeholderText: "VALOR"
                                    topPadding: 10
                                    bottomPadding: 10
                                    leftPadding: 10
                                    rightPadding: 10
                                    validator: Moeda.validador
                                    onEditingFinished: text = Moeda.formatar(text)

                                    background: Rectangle {
                                        radius: Estilo.global.radius.pill
                                        color: Estilo.global.inputBackground
                                        border.color: inputDinheiro.activeFocus ? Estilo.screen.caixa.base : Estilo.global.border
                                        border.width: Estilo.global.borderWidth.hairline
                                    }
                                }
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "Pix"
                                    font.pixelSize: Estilo.global.fontSize.sm
                                    font.bold: true
                                    color: Estilo.global.textSecondary
                                }

                                TextField {
                                    id: inputPix

                                    width: parent.width
                                    color: Estilo.global.textInput
                                    placeholderTextColor: Estilo.global.textPlaceholder
                                    placeholderText: "VALOR"
                                    topPadding: 10
                                    bottomPadding: 10
                                    leftPadding: 10
                                    rightPadding: 10
                                    validator: Moeda.validador
                                    onEditingFinished: text = Moeda.formatar(text)

                                    background: Rectangle {
                                        radius: Estilo.global.radius.pill
                                        color: Estilo.global.inputBackground
                                        border.color: inputPix.activeFocus ? Estilo.screen.caixa.base : Estilo.global.border
                                        border.width: Estilo.global.borderWidth.hairline
                                    }
                                }
                            }

                            Button {
                                id: btnSalvarContagem

                                Layout.fillWidth: true
                                padding: Estilo.global.padding.md
                                onClicked: telaFechamento.salvarContagem(inputCartao.text, inputDinheiro.text, inputPix.text)

                                contentItem: Text {
                                    text: "Salvar contagem"
                                    font.family: Estilo.global.fontFamily.title
                                    color: Estilo.global.textOnAccent
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: btnSalvarContagem.down ? Estilo.screen.caixa.pressed : (btnSalvarContagem.hovered ? Estilo.screen.caixa.hover : Estilo.screen.caixa.base)
                                }
                            }
                        }
                    }

                    // --- LUCRO ---
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Estilo.global.radius.md
                        color: telaFechamento.lucro >= 0 ? Estilo.status.success.background : Estilo.status.error.background
                        border.color: telaFechamento.lucro >= 0 ? Estilo.status.success.border : Estilo.status.error.border
                        border.width: Estilo.global.borderWidth.hairline

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "LUCRO"
                                font.pixelSize: Estilo.global.fontSize.md
                                font.bold: true
                                color: Estilo.global.textSecondary
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "R$ " + telaFechamento.lucro.toFixed(2).replace(".", ",")
                                font.pixelSize: Estilo.global.fontSize.display
                                font.bold: true
                                color: telaFechamento.lucro >= 0 ? Estilo.finance.positive : Estilo.finance.negative
                            }
                        }
                    }
                }
            }

            // --- BOTÃO VOLTAR ---
            Button {
                id: btnVoltar

                padding: Estilo.global.padding.md
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 200
                onClicked: {
                    if (telaFechamento.StackView.view)
                        telaFechamento.StackView.view.irParaInicio();
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
                    border.color: Estilo.action.danger.pressed
                    border.width: Estilo.global.borderWidth.hairline
                }
            }
        }

    }

    PopupFechamentoRapido {
        id: popupFechamentoRapido

        // O popup vive em Overlay.overlay, fora da hierarquia visual desta
        // página, então não alcança o StackView sozinho — e ele precisa da
        // pilha pra empurrar o formulário de edição.
        pilhaPrincipal: telaFechamento.StackView.view

        onConcluido: telaFechamento.carregarDia(telaFechamento.dataSelecionada)
    }

    PopupExtras {
        id: popupExtras
        objectName: "popupExtras"

        onConcluido: telaFechamento.carregarDia(telaFechamento.dataSelecionada)
    }

    PopupFormulaLucro {
        id: popupFormulaLucro

        onConcluido: telaFechamento._carregarFormula()
    }

    FilaNotificacoes {
        id: filaNotificacoes
    }
}
