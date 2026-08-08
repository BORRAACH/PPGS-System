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
        "Balcão": "#16a34a",
        "Entrega": "#e67e22",
        "Mesa": "#0d9488"
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

    Component.onCompleted: {
        _carregarFormula();
        carregarDia(hojeIso());
    }
    StackView.onActivated: {
        carregarDia(telaFechamento.dataSelecionada || hojeIso());
        // Sem isto, a primeira tecla digitada ao chegar na tela não chega em
        // Keys.onPressed: o foco do teclado continua em quem estava antes na
        // pilha de telas.
        telaFechamento.forceActiveFocus();
    }

    background: Rectangle {
        color: Estilo.cores.fundoPagina
        radius: Estilo.rounding.popup
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        // --- CABEÇALHO ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 15

            Row {
                spacing: 8
                Icone { nome: "fa6s.cash-register"; cor: "#16a34a"; tamanho: Estilo.fonte.titulo; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "FECHAMENTO DE CAIXA"
                    font.pixelSize: Estilo.fonte.titulo
                    font.bold: true
                    color: "#16a34a"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item { Layout.fillWidth: true }

            // --- NAVEGAÇÃO DE DATA ---
            Row {
                spacing: 8

                Button {
                    text: "◀"
                    padding: 8
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: telaFechamento.carregarDia(telaFechamento.somarDias(telaFechamento.dataSelecionada, -1))

                    contentItem: Text {
                        text: parent.text
                        font.bold: true
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: parent.down ? "#0f766e" : (parent.hovered ? "#0f8a80" : "#0d9488")
                    }
                }

                Rectangle {
                    width: 130
                    height: 36
                    radius: Estilo.rounding.padrao
                    color: "#ffffff"
                    border.color: Estilo.cores.bordaCard
                    border.width: 1
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada)
                        font.bold: true
                        font.pixelSize: Estilo.fonte.padrao
                        color: Estilo.cores.texto
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
                        font.bold: true
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        opacity: parent.enabled ? 1 : 0.4
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        opacity: parent.enabled ? 1 : 0.4
                        color: parent.down ? "#0f766e" : (parent.hovered ? "#0f8a80" : "#0d9488")
                    }
                }
            }

            Button {
                id: btnEditarCaixa

                padding: 10
                focusPolicy: Qt.StrongFocus
                enabled: telaFechamento.resumoAtual.quantidade > 0
                onClicked: telaFechamento.abrirEditarCaixa()

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.pen-to-square"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Editar caixa"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: {
                        if (!btnEditarCaixa.enabled)
                            return Estilo.cores.borda;
                        return btnEditarCaixa.down ? "#1d4ed8" : (btnEditarCaixa.hovered ? "#3b82f6" : "#2563eb");
                    }
                    border.color: btnEditarCaixa.activeFocus ? Estilo.cores.texto : "transparent"
                    border.width: btnEditarCaixa.activeFocus ? 3 : 1
                }
            }

            Button {
                id: btnFechamentoRapido

                padding: 10
                focusPolicy: Qt.StrongFocus
                enabled: telaFechamento.quantidadeAberta > 0
                onClicked: telaFechamento.abrirFechamentoRapido()

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.list-check"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: telaFechamento.quantidadeAberta > 0
                            ? "Fechamento rápido (" + telaFechamento.quantidadeAberta + ")"
                            : "Fechamento rápido"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: {
                        if (!btnFechamentoRapido.enabled)
                            return Estilo.cores.borda;
                        return btnFechamentoRapido.down ? "#6d28d9" : (btnFechamentoRapido.hovered ? "#8b5cf6" : "#7c3aed");
                    }
                    border.color: btnFechamentoRapido.activeFocus ? Estilo.cores.texto : "transparent"
                    border.width: btnFechamentoRapido.activeFocus ? 3 : 1
                }
            }

            Button {
                id: btnExtras

                padding: 10
                focusPolicy: Qt.StrongFocus
                onClicked: telaFechamento.abrirExtras()

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.hand-holding-dollar"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Extras"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: btnExtras.down ? "#92400e" : (btnExtras.hovered ? "#c2660a" : "#b45309")
                    border.color: btnExtras.activeFocus ? Estilo.cores.texto : "transparent"
                    border.width: btnExtras.activeFocus ? 3 : 1
                }
            }

            Button {
                id: btnFecharCaixa

                padding: 10
                focusPolicy: Qt.StrongFocus
                onClicked: telaFechamento.fecharCaixa()

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.lock"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Fechar Caixa"
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
        }

        // --- TOTAL DO DIA (destaque) ---
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: colunaTotalDia.implicitHeight + 30
            radius: Estilo.rounding.grande
            color: "#f0fdf4"
            border.color: "#bbf7d0"
            border.width: 1

            ColumnLayout {
                id: colunaTotalDia

                anchors.centerIn: parent
                spacing: 4

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "TOTAL DO DIA"
                    font.pixelSize: 13
                    font.bold: true
                    color: Estilo.cores.textoSecundario
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "R$ " + (telaFechamento.resumoAtual.total || 0).toFixed(2).replace(".", ",")
                    font.pixelSize: 34
                    font.bold: true
                    color: "#16a34a"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: (telaFechamento.resumoAtual.quantidade || 0) + (telaFechamento.resumoAtual.quantidade === 1 ? " comanda" : " comandas")
                    font.pixelSize: 13
                    color: Estilo.cores.textoSecundario
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
                    font.pixelSize: 13
                    font.bold: true
                    color: "#b45309"
                }
            }
        }

        // --- MAPEAMENTO POR ORIGEM (esquerda) + SUSPEITAS (direita) ---
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 15

            // --- MAPEAMENTO POR ORIGEM ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Mapeamento por origem"
                        font.pixelSize: Estilo.fonte.padrao
                        font.bold: true
                        color: Estilo.cores.textoSecundario
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: telaFechamento.buscando
                        text: {
                            var n = telaFechamento.totalEncontrado();
                            return n === 1 ? "1 comanda encontrada" : n + " comandas encontradas";
                        }
                        font.pixelSize: 12
                        color: telaFechamento.totalEncontrado() > 0 ? Estilo.cores.textoSecundario : Estilo.cancelar.normal
                    }
                }

                // --- BUSCA ---
                // Aceita modalidade (Balcão/Entrega/Mesa), nome do cliente,
                // código, forma de pagamento, item pedido e valor — tudo o que
                // o Python empacotou no campo "busca" de cada comanda.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: Estilo.rounding.padrao
                    color: "#ffffff"
                    border.color: campoBusca.activeFocus ? telaFechamento.corDestaque : Estilo.cores.bordaCard
                    border.width: campoBusca.activeFocus ? 2 : 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 8

                        Icone {
                            nome: "fa6s.magnifying-glass"
                            cor: Estilo.cores.textoSecundario
                            tamanho: 13
                            Layout.alignment: Qt.AlignVCenter
                        }

                        TextField {
                            id: campoBusca

                            Layout.fillWidth: true
                            placeholderText: "Buscar por modalidade, cliente, pedido ou valor — é só começar a digitar"
                            font.pixelSize: 13
                            // Preto explícito: sem isto o Qt usa palette.text,
                            // que no Windows vem do tema do sistema e some no
                            // fundo branco quando o tema é escuro (mesmo
                            // cuidado documentado em qml/estilo/Estilo.qml).
                            color: Estilo.cores.texto
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
                                cor: Estilo.cores.textoSecundario
                                tamanho: 12
                                anchors.centerIn: parent
                            }

                            background: Rectangle {
                                radius: Estilo.rounding.padrao
                                color: parent.down ? Estilo.cores.bordaCard : "transparent"
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
                        spacing: 12

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
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: linhaCabecalhoTipo.implicitHeight + 16
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: Estilo.cores.bordaCard
                                    border.width: 1

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
                                        spacing: 8

                                        Rectangle {
                                            width: 10
                                            height: 10
                                            radius: 5
                                            color: telaFechamento.coresTipo[modelData] || Estilo.cores.texto
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        Text {
                                            text: modelData
                                            font.bold: true
                                            font.pixelSize: Estilo.fonte.padrao
                                            color: Estilo.cores.texto
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: blocoTipo.comandas.length + (blocoTipo.comandas.length === 1 ? " comanda" : " comandas")
                                            font.pixelSize: 12
                                            color: Estilo.cores.textoSecundario
                                        }

                                        Text {
                                            text: "R$ " + telaFechamento.totalDoTipo(blocoTipo.nomeTipo).toFixed(2).replace(".", ",")
                                            font.bold: true
                                            font.pixelSize: Estilo.fonte.padrao
                                            color: telaFechamento.coresTipo[modelData] || Estilo.cores.texto
                                        }

                                        Icone {
                                            nome: blocoTipo.expandido ? "fa6s.chevron-up" : "fa6s.chevron-down"
                                            cor: Estilo.cores.textoSecundario
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
                                        radius: Estilo.rounding.padrao
                                        color: areaComanda.containsMouse ? "#ffffff" : Estilo.cores.fundoPagina
                                        border.color: itemComandaTipo.suspeita
                                            ? "#dc2626"
                                            : (areaComanda.containsMouse ? (telaFechamento.coresTipo[blocoTipo.nomeTipo] || Estilo.cores.borda) : Estilo.cores.bordaCard)
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
                                            spacing: 8

                                            Text {
                                                Layout.fillWidth: true
                                                text: (modelData.cliente && modelData.cliente.trim() !== "" ? modelData.cliente : "Sem nome") + " · " + modelData.dataHora
                                                font.pixelSize: 12
                                                color: Estilo.cores.texto
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: modelData.formaPagamento + (modelData.status ? " [" + modelData.status + "]" : "")
                                                font.pixelSize: 11
                                                color: Estilo.cores.textoSecundario
                                            }

                                            Text {
                                                text: "R$ " + Number(modelData.valor).toFixed(2).replace(".", ",")
                                                font.bold: true
                                                font.pixelSize: 12
                                                color: Estilo.cores.texto
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
                            color: Estilo.cores.textoSecundario
                        }
                    }
                }

                // --- EXTRAS (pagamento de diária, descontado do caixa) ---
                Rectangle {
                    Layout.fillWidth: true
                    visible: telaFechamento.quantidadeExtras > 0
                    implicitHeight: colunaExtras.implicitHeight + 20
                    radius: Estilo.rounding.padrao
                    color: "#fff7ed"
                    border.color: "#fed7aa"
                    border.width: 1

                    ColumnLayout {
                        id: colunaExtras

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 6

                        Row {
                            spacing: 6
                            Icone { nome: "fa6s.hand-holding-dollar"; cor: "#b45309"; tamanho: 14; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: "Pagamentos de diária (descontados do caixa)"
                                font.bold: true
                                font.pixelSize: 13
                                color: "#b45309"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Repeater {
                            model: telaFechamento._extras.itens

                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.funcionario
                                    font.pixelSize: 12
                                    color: Estilo.cores.texto
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: modelData.dataHora
                                    font.pixelSize: 11
                                    color: Estilo.cores.textoSecundario
                                }

                                Text {
                                    text: "R$ " + Number(modelData.valor).toFixed(2).replace(".", ",")
                                    font.bold: true
                                    font.pixelSize: 12
                                    color: "#b45309"
                                }

                                Button {
                                    id: btnEditarExtra

                                    implicitWidth: 24
                                    implicitHeight: 24
                                    padding: 0
                                    onClicked: popupExtras.abrirParaEditar(modelData)

                                    contentItem: Icone {
                                        nome: "fa6s.pen"
                                        cor: Estilo.cores.textoSecundario
                                        tamanho: 11
                                        anchors.centerIn: parent
                                    }

                                    background: Rectangle {
                                        radius: Estilo.rounding.cheio
                                        color: btnEditarExtra.down ? "#e5e7eb" : (btnEditarExtra.hovered ? "#f1f5f9" : "transparent")
                                    }
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            text: "Total descontado: R$ " + telaFechamento.totalExtras.toFixed(2).replace(".", ",")
                            font.bold: true
                            font.pixelSize: 13
                            color: "#b45309"
                        }
                    }
                }
            }

            // --- CONTAGEM DE CAIXA ---
            ColumnLayout {
                Layout.preferredWidth: 340
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    Row {
                        spacing: 6
                        Icone { nome: "fa6s.calculator"; cor: "#0d9488"; tamanho: 16; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Contagem de caixa"
                            font.pixelSize: Estilo.fonte.padrao
                            font.bold: true
                            color: "#0d9488"
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
                            cor: Estilo.cores.textoSecundario
                            tamanho: 14
                            anchors.centerIn: parent
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.cheio
                            color: btnFormulaLucro.down ? "#e5e7eb" : (btnFormulaLucro.hovered ? "#f1f5f9" : "transparent")
                            border.color: Estilo.cores.borda
                            border.width: 1
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: colunaContagem.implicitHeight + 20
                    radius: Estilo.rounding.grande
                    color: "#ffffff"
                    border.color: Estilo.cores.bordaCard
                    border.width: 1

                    ColumnLayout {
                        id: colunaContagem

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 10

                        Column {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: "Cartão (crédito/débito)"
                                font.pixelSize: 12
                                font.bold: true
                                color: Estilo.cores.textoSecundario
                            }

                            TextField {
                                id: inputCartao

                                width: parent.width
                                color: Estilo.cores.textoInput
                                placeholderTextColor: Estilo.cores.placeholderInput
                                placeholderText: "VALOR"
                                topPadding: 10
                                bottomPadding: 10
                                leftPadding: 10
                                rightPadding: 10
                                validator: DoubleValidator {
                                    bottom: 0
                                    decimals: 2
                                    notation: DoubleValidator.StandardNotation
                                }
                                // Mesmo padrão de inputTroco/inputTaxaEntrega
                                // em CamposPagamento.qml.
                                onEditingFinished: {
                                    if (text !== "") {
                                        var numLimpo = text.replace("R$", "").replace(" ", "").replace(",", ".");
                                        var valorFloat = parseFloat(numLimpo);
                                        if (!isNaN(valorFloat))
                                            text = "R$ " + valorFloat.toFixed(2).replace(".", ",");
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: inputCartao.activeFocus ? "#0d9488" : Estilo.cores.borda
                                    border.width: 1
                                }
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: "Dinheiro (no caixa)"
                                font.pixelSize: 12
                                font.bold: true
                                color: Estilo.cores.textoSecundario
                            }

                            TextField {
                                id: inputDinheiro

                                width: parent.width
                                color: Estilo.cores.textoInput
                                placeholderTextColor: Estilo.cores.placeholderInput
                                placeholderText: "VALOR"
                                topPadding: 10
                                bottomPadding: 10
                                leftPadding: 10
                                rightPadding: 10
                                validator: DoubleValidator {
                                    bottom: 0
                                    decimals: 2
                                    notation: DoubleValidator.StandardNotation
                                }
                                onEditingFinished: {
                                    if (text !== "") {
                                        var numLimpo = text.replace("R$", "").replace(" ", "").replace(",", ".");
                                        var valorFloat = parseFloat(numLimpo);
                                        if (!isNaN(valorFloat))
                                            text = "R$ " + valorFloat.toFixed(2).replace(".", ",");
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: inputDinheiro.activeFocus ? "#0d9488" : Estilo.cores.borda
                                    border.width: 1
                                }
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: "Pix"
                                font.pixelSize: 12
                                font.bold: true
                                color: Estilo.cores.textoSecundario
                            }

                            TextField {
                                id: inputPix

                                width: parent.width
                                color: Estilo.cores.textoInput
                                placeholderTextColor: Estilo.cores.placeholderInput
                                placeholderText: "VALOR"
                                topPadding: 10
                                bottomPadding: 10
                                leftPadding: 10
                                rightPadding: 10
                                validator: DoubleValidator {
                                    bottom: 0
                                    decimals: 2
                                    notation: DoubleValidator.StandardNotation
                                }
                                onEditingFinished: {
                                    if (text !== "") {
                                        var numLimpo = text.replace("R$", "").replace(" ", "").replace(",", ".");
                                        var valorFloat = parseFloat(numLimpo);
                                        if (!isNaN(valorFloat))
                                            text = "R$ " + valorFloat.toFixed(2).replace(".", ",");
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: inputPix.activeFocus ? "#0d9488" : Estilo.cores.borda
                                    border.width: 1
                                }
                            }
                        }

                        Button {
                            id: btnSalvarContagem

                            Layout.fillWidth: true
                            padding: 10
                            onClicked: telaFechamento.salvarContagem(inputCartao.text, inputDinheiro.text, inputPix.text)

                            contentItem: Text {
                                text: "Salvar contagem"
                                font.bold: true
                                color: "#ffffff"
                                horizontalAlignment: Text.AlignHCenter
                            }

                            background: Rectangle {
                                radius: Estilo.rounding.padrao
                                color: btnSalvarContagem.down ? "#0f766e" : (btnSalvarContagem.hovered ? "#0f8a80" : "#0d9488")
                            }
                        }
                    }
                }

                // --- LUCRO ---
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Estilo.rounding.grande
                    color: telaFechamento.lucro >= 0 ? "#f0fdf4" : "#fff5f5"
                    border.color: telaFechamento.lucro >= 0 ? "#bbf7d0" : "#ffc9c9"
                    border.width: 1

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "LUCRO"
                            font.pixelSize: 13
                            font.bold: true
                            color: Estilo.cores.textoSecundario
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "R$ " + telaFechamento.lucro.toFixed(2).replace(".", ",")
                            font.pixelSize: 30
                            font.bold: true
                            color: telaFechamento.lucro >= 0 ? "#16a34a" : Estilo.cancelar.normal
                        }
                    }
                }
            }
        }

        // --- BOTÃO VOLTAR ---
        Button {
            id: btnVoltar

            padding: 10
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 200
            onClicked: {
                if (telaFechamento.StackView.view)
                    telaFechamento.StackView.view.irParaInicio();
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
