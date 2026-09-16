import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"
import "../../components/graficos"
import "../../components/graficos/Formato.js" as Formato

// Estatística — o histórico de vendas em números e gráficos, a partir do JSON
// que cada "Fechar Caixa" grava (ver services/estatisticasService.py e
// controllers/estatisticasController.py).
//
// De onde vêm os dados: um arquivo por dia em pedidos/estatisticas/. Hoje é
// calculado ao vivo (as comandas continuam chegando), os dias passados vêm do
// arquivo. Ao abrir, a página manda gerar o que falta do histórico — os dias
// que têm comanda e nunca tiveram arquivo — numa thread, com o progresso na
// tela; nada trava enquanto isso.
//
// Os gráficos são desenhados em QML puro (components/graficos/): o PyQt6 do
// pip não traz o QtCharts, mesma limitação que levou o mapa a ser feito em
// blocos (components/MapaBlocos.qml).
Page {
    id: telaEstatistica

    objectName: "telaEstatistica"

    // ===== MEDIDAS =====
    readonly property real larguraUtil: width - Estilo.global.padding.xl * 2
    readonly property bool empilhado: larguraUtil < 900
    readonly property int colunasCartoes: Math.max(1, Math.min(6, Math.floor(larguraUtil / 210)))

    // ===== ESTADO =====
    // "AAAA-MM-DD" (inclusive nas duas pontas).
    property string inicio: ""
    property string fim: ""
    // "hoje" | "7" | "30" | "mes" | "mesAnterior" — qual botão está aceso.
    property string periodoAtual: "30"
    // Resultado de estatisticasController.obterPeriodo.
    property var dados: ({})
    // Geração do histórico em segundo plano.
    property int historicoTotal: 0
    property int historicoFeitos: 0
    property bool gerandoHistorico: false
    // O histórico só é pedido uma vez por abertura da página.
    property bool historicoPedido: false

    readonly property var totais: dados.totais || ({})
    readonly property var dias: dados.dias || []

    // ===== SÉRIES DOS GRÁFICOS =====
    // Readonly properties, e não funções: assim cada gráfico se redesenha
    // sozinho quando `dados` troca.
    readonly property var rotulosDias: dias.map(function (dia) { return dia.data; })

    readonly property var serieFaturamento: [{
        "nome": "Faturamento",
        "cor": Estilo.finance.positive,
        "valores": dias.map(function (dia) { return dia.faturamento; })
    }]

    readonly property var serieVendasPorModalidade: [
        { "nome": "Balcão", "cor": Estilo.orderType.balcao.base, "valores": dias.map(function (dia) { return dia.vendasPorModalidade["Balcão"] || 0; }) },
        { "nome": "Entrega", "cor": Estilo.orderType.entrega.base, "valores": dias.map(function (dia) { return dia.vendasPorModalidade["Entrega"] || 0; }) },
        { "nome": "Mesa", "cor": Estilo.orderType.mesa.base, "valores": dias.map(function (dia) { return dia.vendasPorModalidade["Mesa"] || 0; }) }
    ]

    readonly property var serieRendimento: [
        { "nome": "Faturamento", "cor": Estilo.finance.positive, "preenchida": true, "valores": dias.map(function (dia) { return dia.faturamento; }) },
        { "nome": "Líquido (sem diárias e despesas)", "cor": Estilo.screen.caixa.accent, "valores": dias.map(function (dia) { return dia.liquido; }) }
    ]

    readonly property var serieAlteracoes: [
        { "nome": "Editadas", "cor": Estilo.status.warning.content, "valores": dias.map(function (dia) { return dia.editadas; }) },
        { "nome": "Excluídas", "cor": Estilo.status.error.content, "valores": dias.map(function (dia) { return dia.excluidas; }) }
    ]

    readonly property var fatiasModalidade: (dados.porModalidade || []).map(function (modalidade) {
        return {
            "nome": modalidade.nome,
            "valor": modalidade.total,
            "cor": modalidade.nome === "Balcão" ? Estilo.orderType.balcao.base
                 : (modalidade.nome === "Entrega" ? Estilo.orderType.entrega.base : Estilo.orderType.mesa.base)
        };
    })

    readonly property var fatiasPagamento: {
        var cores = { "Dinheiro": Estilo.finance.positive, "Pix": Estilo.status.info.content, "Cartão": Estilo.finance.outflow };
        return (dados.formasPagamento || []).map(function (forma) {
            return { "nome": forma.nome, "valor": forma.total, "cor": cores[forma.nome] || Estilo.global.textMuted };
        });
    }

    readonly property var rotulosHoras: (dados.porHora || []).map(function (faixa) { return faixa.hora + "h"; })
    readonly property var serieHoras: [{
        "nome": "Vendas",
        "cor": Estilo.screen.caixa.accent,
        "valores": (dados.porHora || []).map(function (faixa) { return faixa.quantidade; })
    }]

    readonly property var rankingProdutos: (dados.produtos || []).map(function (produto) {
        return { "nome": produto.nome, "valor": produto.quantidade, "detalhe": Formato.moeda(produto.total) };
    })
    readonly property var rankingBairros: (dados.bairros || []).map(function (bairro) {
        return { "nome": bairro.nome, "valor": bairro.quantidade, "detalhe": "" };
    })
    readonly property var rankingUsuarios: (dados.usuarios || []).map(function (usuario) {
        return { "nome": usuario.nome, "valor": usuario.total, "detalhe": usuario.quantidade + (usuario.quantidade === 1 ? " venda" : " vendas") };
    })

    // ===== FUNÇÕES =====
    function _doisDigitos(numero) {
        return numero < 10 ? "0" + numero : "" + numero;
    }

    function _iso(data) {
        return data.getFullYear() + "-" + _doisDigitos(data.getMonth() + 1) + "-" + _doisDigitos(data.getDate());
    }

    function hojeIso() {
        return _iso(new Date());
    }

    function somarDias(iso, delta) {
        var partes = iso.split("-");
        var data = new Date(Number(partes[0]), Number(partes[1]) - 1, Number(partes[2]));
        data.setDate(data.getDate() + delta);
        return _iso(data);
    }

    function formatarData(iso) {
        var partes = String(iso || "").split("-");
        return partes.length === 3 ? partes[2] + "/" + partes[1] + "/" + partes[0] : iso;
    }

    // Quantos dias o período tem — usado para o passo das setas ◀ ▶.
    function _tamanhoDoPeriodo() {
        var partes = telaEstatistica.inicio.split("-");
        var comeco = new Date(Number(partes[0]), Number(partes[1]) - 1, Number(partes[2]));
        partes = telaEstatistica.fim.split("-");
        var fimData = new Date(Number(partes[0]), Number(partes[1]) - 1, Number(partes[2]));
        return Math.round((fimData - comeco) / 86400000) + 1;
    }

    function definirPeriodo(chave) {
        var hoje = hojeIso();
        telaEstatistica.periodoAtual = chave;
        if (chave === "hoje") {
            telaEstatistica.inicio = hoje;
            telaEstatistica.fim = hoje;
        } else if (chave === "7" || chave === "30") {
            telaEstatistica.inicio = somarDias(hoje, -(Number(chave) - 1));
            telaEstatistica.fim = hoje;
        } else if (chave === "mes") {
            telaEstatistica.inicio = hoje.substring(0, 8) + "01";
            telaEstatistica.fim = hoje;
        } else if (chave === "mesAnterior") {
            var primeiroDesteMes = hoje.substring(0, 8) + "01";
            var ultimoDoAnterior = somarDias(primeiroDesteMes, -1);
            telaEstatistica.inicio = ultimoDoAnterior.substring(0, 8) + "01";
            telaEstatistica.fim = ultimoDoAnterior;
        }
        carregar();
    }

    // Move a janela inteira para trás/para frente, sem passar de hoje.
    function deslocarPeriodo(direcao) {
        var passo = _tamanhoDoPeriodo() * direcao;
        var novoFim = somarDias(telaEstatistica.fim, passo);
        if (novoFim > hojeIso())
            return;
        telaEstatistica.inicio = somarDias(telaEstatistica.inicio, passo);
        telaEstatistica.fim = novoFim;
        telaEstatistica.periodoAtual = "";
        carregar();
    }

    function carregar() {
        if (telaEstatistica.inicio === "" || telaEstatistica.fim === "")
            return;
        telaEstatistica.dados = estatisticasController.obterPeriodo(telaEstatistica.inicio, telaEstatistica.fim);
    }

    // Os dias que nunca foram fechados (ou que vêm de antes desta tela existir)
    // ganham arquivo agora, uma vez só por abertura da página.
    function gerarHistoricoPendente() {
        if (telaEstatistica.historicoPedido)
            return;
        telaEstatistica.historicoPedido = true;
        var total = estatisticasController.gerarHistorico();
        if (total > 0) {
            telaEstatistica.historicoTotal = total;
            telaEstatistica.historicoFeitos = 0;
            telaEstatistica.gerandoHistorico = true;
        }
    }

    focus: true

    // Carrega depois do primeiro quadro: obterPeriodo lê um arquivo por dia do
    // período (e recalcula hoje a partir das comandas) — ver
    // components/CargaDiferida.qml, mesmo cuidado da tela de Fechamento.
    CargaDiferida {
        id: carga

        tarefa: function () {
            telaEstatistica.carregar();
            telaEstatistica.gerarHistoricoPendente();
        }
    }

    Component.onCompleted: {
        definirPeriodo("30");
        // definirPeriodo já chamou carregar(); a carga diferida recarrega
        // depois do primeiro quadro, junto com o histórico.
        telaEstatistica.dados = ({});
        carga.agendar();
    }

    StackView.onActivated: carga.agendar()

    Connections {
        target: estatisticasController

        function onEstatisticasAtualizadas() {
            telaEstatistica.carregar();
        }

        function onProgressoHistorico(feitos, total) {
            telaEstatistica.historicoFeitos = feitos;
            telaEstatistica.historicoTotal = total;
        }

        function onHistoricoGerado(gerados) {
            telaEstatistica.gerandoHistorico = false;
        }
    }

    background: Rectangle {
        color: Estilo.global.background
        radius: Estilo.global.radius.xl
    }

    // ===== BLOCOS REUTILIZADOS NESTA TELA =====
    // Cartão de um número só (faturamento, vendas, ticket médio...).
    component CartaoNumero: Rectangle {
        property string rotulo: ""
        property string valor: ""
        property string detalhe: ""
        property string nomeIcone: ""
        property color corValor: Estilo.global.text

        color: Estilo.global.surface
        radius: Estilo.global.radius.lg
        border.color: Estilo.global.borderCard
        border.width: Estilo.global.borderWidth.hairline
        implicitHeight: colunaCartao.implicitHeight + Estilo.global.padding.lg * 2

        Column {
            id: colunaCartao

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Estilo.global.padding.lg
            spacing: 4

            Row {
                spacing: 6

                Icone {
                    visible: nomeIcone !== ""
                    nome: nomeIcone
                    cor: Estilo.global.textMuted
                    tamanho: Estilo.global.fontSize.sm
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: rotulo
                    font.pixelSize: Estilo.global.fontSize.xs
                    font.bold: true
                    color: Estilo.global.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                width: parent.width
                text: valor
                font.pixelSize: Estilo.global.fontSize.xxl
                font.bold: true
                color: corValor
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                visible: detalhe !== ""
                text: detalhe
                font.pixelSize: Estilo.global.fontSize.xs
                color: Estilo.global.textMuted
                elide: Text.ElideRight
            }
        }
    }

    // Painel com título para um gráfico.
    component Painel: Rectangle {
        property string titulo: ""
        property string subtitulo: ""
        property int alturaConteudo: 220
        default property alias conteudo: areaPainel.data

        color: Estilo.global.surface
        radius: Estilo.global.radius.lg
        border.color: Estilo.global.borderCard
        border.width: Estilo.global.borderWidth.hairline
        implicitHeight: cabecalhoPainel.implicitHeight + alturaConteudo
                        + Estilo.global.padding.lg * 2 + Estilo.global.spacing.sm

        Column {
            id: cabecalhoPainel

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Estilo.global.padding.lg
            spacing: 2

            Text {
                width: parent.width
                text: titulo
                font.pixelSize: Estilo.global.fontSize.lg
                font.bold: true
                color: Estilo.global.text
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: subtitulo !== ""
                text: subtitulo
                font.pixelSize: Estilo.global.fontSize.xs
                color: Estilo.global.textMuted
                elide: Text.ElideRight
            }
        }

        Item {
            id: areaPainel

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: cabecalhoPainel.bottom
            anchors.leftMargin: Estilo.global.padding.lg
            anchors.rightMargin: Estilo.global.padding.lg
            anchors.topMargin: Estilo.global.spacing.sm
            height: alturaConteudo
        }
    }

    // ===== LAYOUT =====
    Flickable {
        id: rolagem

        anchors.fill: parent
        anchors.margins: Estilo.global.padding.xl
        clip: true
        contentWidth: width
        contentHeight: coluna.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: coluna

            width: rolagem.width
            spacing: Estilo.global.spacing.xl

            // --- CABEÇALHO: título e período ---
            GridLayout {
                Layout.fillWidth: true
                columns: telaEstatistica.empilhado ? 1 : 2
                columnSpacing: Estilo.global.spacing.xl
                rowSpacing: Estilo.global.spacing.md

                Row {
                    spacing: Estilo.global.spacing.sm

                    Icone {
                        nome: "fa6s.chart-line"
                        cor: Estilo.screen.caixa.accent
                        tamanho: Estilo.global.fontSize.title
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "ESTATÍSTICA"
                        font.pixelSize: Estilo.global.fontSize.title
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.screen.caixa.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    spacing: Estilo.global.spacing.sm

                    Repeater {
                        model: [
                            { "chave": "hoje", "rotulo": "Hoje" },
                            { "chave": "7", "rotulo": "7 dias" },
                            { "chave": "30", "rotulo": "30 dias" },
                            { "chave": "mes", "rotulo": "Este mês" },
                            { "chave": "mesAnterior", "rotulo": "Mês anterior" }
                        ]

                        delegate: Botao {
                            required property var modelData

                            text: modelData.rotulo
                            variante: telaEstatistica.periodoAtual === modelData.chave ? "primario" : "secundario"
                            tom: Estilo.screen.caixa
                            onClicked: telaEstatistica.definirPeriodo(modelData.chave)
                        }
                    }

                    Botao {
                        text: "◀"
                        variante: "ghost"
                        tom: Estilo.screen.caixa
                        onClicked: telaEstatistica.deslocarPeriodo(-1)
                    }
                    Botao {
                        text: "▶"
                        variante: "ghost"
                        tom: Estilo.screen.caixa
                        enabled: telaEstatistica.fim < telaEstatistica.hojeIso()
                        onClicked: telaEstatistica.deslocarPeriodo(1)
                    }
                }
            }

            // Período mostrado e andamento da geração do histórico.
            RowLayout {
                Layout.fillWidth: true
                spacing: Estilo.global.spacing.sm

                Text {
                    text: telaEstatistica.inicio === telaEstatistica.fim
                        ? telaEstatistica.formatarData(telaEstatistica.inicio)
                        : telaEstatistica.formatarData(telaEstatistica.inicio) + " a " + telaEstatistica.formatarData(telaEstatistica.fim)
                    font.pixelSize: Estilo.global.fontSize.md
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                Text {
                    Layout.fillWidth: true
                    visible: telaEstatistica.gerandoHistorico
                    text: "Gerando o histórico… " + telaEstatistica.historicoFeitos + " de " + telaEstatistica.historicoTotal + " dias"
                    font.pixelSize: Estilo.global.fontSize.xs
                    color: Estilo.global.textMuted
                    elide: Text.ElideRight
                }

                Item {
                    Layout.fillWidth: !telaEstatistica.gerandoHistorico
                }
            }

            // --- CARTÕES ---
            GridLayout {
                Layout.fillWidth: true
                columns: telaEstatistica.colunasCartoes
                columnSpacing: Estilo.global.spacing.md
                rowSpacing: Estilo.global.spacing.md

                CartaoNumero {
                    Layout.fillWidth: true
                    rotulo: "Faturamento"
                    nomeIcone: "fa6s.sack-dollar"
                    valor: Formato.moeda(telaEstatistica.totais.faturamento || 0)
                    corValor: Estilo.finance.positive
                    detalhe: (telaEstatistica.dados.diasComDados || 0) + " dia(s) com venda"
                }
                CartaoNumero {
                    Layout.fillWidth: true
                    rotulo: "Vendas"
                    nomeIcone: "fa6s.receipt"
                    valor: Formato.numero(telaEstatistica.totais.vendas || 0)
                    detalhe: "comandas fechadas"
                }
                CartaoNumero {
                    Layout.fillWidth: true
                    rotulo: "Ticket médio"
                    nomeIcone: "fa6s.calculator"
                    valor: Formato.moeda(telaEstatistica.totais.ticketMedio || 0)
                    detalhe: "por comanda"
                }
                CartaoNumero {
                    Layout.fillWidth: true
                    rotulo: "Entregas"
                    nomeIcone: "fa6s.motorcycle"
                    valor: Formato.numero(telaEstatistica.totais.entregas || 0)
                    detalhe: "taxas: " + Formato.moeda(telaEstatistica.totais.taxasEntrega || 0)
                }
                CartaoNumero {
                    Layout.fillWidth: true
                    rotulo: "Líquido"
                    nomeIcone: "fa6s.wallet"
                    valor: Formato.moeda(telaEstatistica.totais.liquido || 0)
                    corValor: (telaEstatistica.totais.liquido || 0) >= 0 ? Estilo.finance.positive : Estilo.finance.negative
                    detalhe: "– diárias " + Formato.moeda(telaEstatistica.totais.extras || 0)
                             + " e despesas " + Formato.moeda(telaEstatistica.totais.despesas || 0)
                }
                CartaoNumero {
                    Layout.fillWidth: true
                    rotulo: "Alterações"
                    nomeIcone: "fa6s.pen-to-square"
                    valor: Formato.numero(telaEstatistica.totais.editadas || 0) + " / " + Formato.numero(telaEstatistica.totais.excluidas || 0)
                    corValor: ((telaEstatistica.totais.editadas || 0) + (telaEstatistica.totais.excluidas || 0)) > 0
                              ? Estilo.status.warning.content : Estilo.global.text
                    detalhe: "editadas / excluídas · " + Formato.moeda(telaEstatistica.totais.valorExcluido || 0) + " apagados"
                }
            }

            // --- GRÁFICOS ---
            GridLayout {
                Layout.fillWidth: true
                columns: telaEstatistica.empilhado ? 1 : 2
                columnSpacing: Estilo.global.spacing.md
                rowSpacing: Estilo.global.spacing.md

                Painel {
                    Layout.fillWidth: true
                    titulo: "Faturamento por dia"
                    subtitulo: "Só comandas com baixa"

                    GraficoBarras {
                        anchors.fill: parent
                        rotulos: telaEstatistica.rotulosDias
                        series: telaEstatistica.serieFaturamento
                        formato: "moeda"
                    }
                }

                Painel {
                    Layout.fillWidth: true
                    titulo: "Vendas por dia"
                    subtitulo: "Empilhadas por modalidade"

                    GraficoBarras {
                        anchors.fill: parent
                        rotulos: telaEstatistica.rotulosDias
                        series: telaEstatistica.serieVendasPorModalidade
                        formato: "numero"
                    }
                }

                Painel {
                    Layout.fillWidth: true
                    titulo: "Rendimento"
                    subtitulo: "Faturamento e o que sobrou depois das saídas do caixa"

                    GraficoLinha {
                        anchors.fill: parent
                        rotulos: telaEstatistica.rotulosDias
                        series: telaEstatistica.serieRendimento
                        formato: "moeda"
                    }
                }

                Painel {
                    Layout.fillWidth: true
                    titulo: "Vendas por hora"
                    subtitulo: "Horário de pico no período"

                    GraficoBarras {
                        anchors.fill: parent
                        rotulos: telaEstatistica.rotulosHoras
                        series: telaEstatistica.serieHoras
                        formato: "numero"
                    }
                }

                Painel {
                    Layout.fillWidth: true
                    titulo: "Modalidades"
                    alturaConteudo: 190

                    GraficoRosca {
                        anchors.fill: parent
                        fatias: telaEstatistica.fatiasModalidade
                        formato: "moeda"
                        rotuloTotal: "Faturamento"
                    }
                }

                Painel {
                    Layout.fillWidth: true
                    titulo: "Formas de pagamento"
                    subtitulo: "Crédito e débito contam como cartão"
                    alturaConteudo: 190

                    GraficoRosca {
                        anchors.fill: parent
                        fatias: telaEstatistica.fatiasPagamento
                        formato: "moeda"
                        rotuloTotal: "Recebido"
                    }
                }

                Painel {
                    Layout.fillWidth: true
                    titulo: "Produtos mais vendidos"
                    subtitulo: "Quantidade e valor no período"
                    alturaConteudo: Math.min(300, Math.max(60, listaProdutos.implicitHeight))

                    BarrasHorizontais {
                        id: listaProdutos

                        anchors.fill: parent
                        itens: telaEstatistica.rankingProdutos
                        formato: "numero"
                        cor: Estilo.orderType.balcao.base
                    }
                }

                Painel {
                    Layout.fillWidth: true
                    titulo: "Entregas por bairro"
                    alturaConteudo: Math.min(300, Math.max(60, listaBairros.implicitHeight))

                    BarrasHorizontais {
                        id: listaBairros

                        anchors.fill: parent
                        itens: telaEstatistica.rankingBairros
                        formato: "numero"
                        cor: Estilo.orderType.entrega.base
                    }
                }

                Painel {
                    Layout.fillWidth: true
                    titulo: "Vendas por usuário"
                    subtitulo: "Quem lançou a comanda"
                    alturaConteudo: Math.min(220, Math.max(60, listaUsuarios.implicitHeight))

                    BarrasHorizontais {
                        id: listaUsuarios

                        anchors.fill: parent
                        itens: telaEstatistica.rankingUsuarios
                        formato: "moeda"
                        cor: Estilo.screen.caixa.accent
                    }
                }

                Painel {
                    Layout.fillWidth: true
                    titulo: "Comandas alteradas"
                    subtitulo: "Correções e exclusões por dia"
                    alturaConteudo: 220

                    GraficoBarras {
                        anchors.fill: parent
                        rotulos: telaEstatistica.rotulosDias
                        series: telaEstatistica.serieAlteracoes
                        formato: "numero"
                        mensagemVazio: "Nenhuma comanda alterada no período"
                    }
                }
            }

            // --- DIA A DIA ---
            Painel {
                Layout.fillWidth: true
                titulo: "Dia a dia"
                subtitulo: "Do mais recente para o mais antigo"
                alturaConteudo: Math.min(320, Math.max(60, telaEstatistica.dias.length * 34))

                ListView {
                    anchors.fill: parent
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: telaEstatistica.dias.slice().reverse()

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    delegate: Rectangle {
                        required property var modelData

                        width: ListView.view.width
                        height: 32
                        radius: Estilo.global.radius.sm
                        color: modelData.temDados ? "transparent" : Estilo.global.surfaceHover

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Estilo.global.padding.sm
                            anchors.rightMargin: Estilo.global.padding.sm
                            spacing: Estilo.global.spacing.md

                            Text {
                                Layout.preferredWidth: 90
                                text: telaEstatistica.formatarData(modelData.data)
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.text
                            }
                            Text {
                                Layout.preferredWidth: 80
                                text: modelData.vendas + (modelData.vendas === 1 ? " venda" : " vendas")
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.textSecondary
                            }
                            Text {
                                Layout.preferredWidth: 110
                                text: Formato.moeda(modelData.faturamento)
                                font.pixelSize: Estilo.global.fontSize.sm
                                font.bold: true
                                color: Estilo.finance.positive
                            }
                            Text {
                                Layout.fillWidth: true
                                text: !modelData.temDados ? "Sem movimento registrado"
                                    : (modelData.origem === "fechamento"
                                        ? ("Caixa fechado" + (modelData.ultimoFechamento ? " às " + modelData.ultimoFechamento.substring(11, 16) : ""))
                                        : (modelData.origem === "ao_vivo" ? "Hoje, ainda em andamento" : "Gerado do histórico"))
                                font.pixelSize: Estilo.global.fontSize.xs
                                color: Estilo.global.textMuted
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Botao {
                Layout.alignment: Qt.AlignLeft
                text: "Voltar para o Menu"
                nomeIcone: "fa6s.arrow-left"
                variante: "primario"
                tom: Estilo.action.danger
                onClicked: {
                    if (telaEstatistica.StackView.view)
                        telaEstatistica.StackView.view.irParaInicio();
                }
            }
        }
    }
}
