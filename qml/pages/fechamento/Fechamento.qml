import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

// Fechamento de caixa diário — soma o total de todas as comandas lançadas
// no dia (Balcão/Entrega/Mesa, ver controllers/fechamentoController.py),
// mostra de onde cada valor vem, e separa comandas suspeitas (sem nome do
// cliente + NP + Pix) pra revisão manual.
//
// O resumo é recalculado sozinho ao abrir a página (ou trocar de dia) —
// "hoje" sempre ao vivo, dias passados usam o cache local quando já existe
// (ver FechamentoController.obterFechamento). O botão "Fechar Caixa" força
// um recálculo na hora, pro caso de outra máquina ter lançado uma comanda
// nova enquanto esta tela já estava aberta.
Page {
    id: telaFechamento

    objectName: "telaFechamento"

    // "AAAA-MM-DD" — sempre preenchida (ver hojeIso()/carregarDia()).
    property string dataSelecionada: ""
    // {data, total, quantidade, porTipo, suspeitas} — {} antes da primeira
    // carga.
    property var resumoAtual: ({})

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

    function carregarDia(iso) {
        telaFechamento.dataSelecionada = iso;
        telaFechamento.resumoAtual = fechamentoController.obterFechamento(iso);
    }

    function fecharCaixa() {
        telaFechamento.resumoAtual = fechamentoController.calcularFechamento(telaFechamento.dataSelecionada);
        telaFechamento.mostrarNotificacao("Caixa de " + telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada) + " recalculado e salvo.", true);
    }

    function abrirFechamentoRapido() {
        if (!popupFechamentoRapido.abrirPara(telaFechamento.dataSelecionada))
            telaFechamento.mostrarNotificacao("Nenhuma comanda em aberto em " + telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada) + ".", true);
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

    Component.onCompleted: {
        carregarDia(hojeIso());
    }
    StackView.onActivated: {
        carregarDia(telaFechamento.dataSelecionada || hojeIso());
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

                Text {
                    text: "Mapeamento por origem"
                    font.pixelSize: Estilo.fonte.padrao
                    font.bold: true
                    color: Estilo.cores.textoSecundario
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

                                Layout.fillWidth: true
                                visible: info.quantidade > 0
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: linhaCabecalhoTipo.implicitHeight + 16
                                    radius: Estilo.rounding.padrao
                                    color: "#ffffff"
                                    border.color: Estilo.cores.bordaCard
                                    border.width: 1

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
                                            text: blocoTipo.info.quantidade + (blocoTipo.info.quantidade === 1 ? " comanda" : " comandas")
                                            font.pixelSize: 12
                                            color: Estilo.cores.textoSecundario
                                        }

                                        Text {
                                            text: "R$ " + blocoTipo.info.total.toFixed(2).replace(".", ",")
                                            font.bold: true
                                            font.pixelSize: Estilo.fonte.padrao
                                            color: telaFechamento.coresTipo[modelData] || Estilo.cores.texto
                                        }
                                    }
                                }

                                ListView {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 18
                                    Layout.preferredHeight: Math.min(blocoTipo.info.comandas.length * 44, 220)
                                    clip: true
                                    spacing: 4
                                    model: blocoTipo.info.comandas
                                    boundsBehavior: Flickable.StopAtBounds

                                    ScrollBar.vertical: ScrollBar {
                                        policy: ScrollBar.AsNeeded
                                    }

                                    delegate: Rectangle {
                                        width: ListView.view.width
                                        height: 40
                                        radius: Estilo.rounding.padrao
                                        color: areaComanda.containsMouse ? "#ffffff" : Estilo.cores.fundoPagina
                                        border.color: areaComanda.containsMouse ? (telaFechamento.coresTipo[blocoTipo.nomeTipo] || Estilo.cores.borda) : Estilo.cores.bordaCard
                                        border.width: 1

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
            }

            // --- COMANDAS SUSPEITAS ---
            ColumnLayout {
                Layout.preferredWidth: 340
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                spacing: 10

                Row {
                    spacing: 6
                    Icone { nome: "fa6s.triangle-exclamation"; cor: Estilo.cancelar.normal; tamanho: 16; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Comandas suspeitas"
                        font.pixelSize: Estilo.fonte.padrao
                        font.bold: true
                        color: Estilo.cancelar.normal
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Sem nome do cliente, status NP e forma de pagamento Pix — pode ter sido um erro na hora de tirar o pedido."
                    font.pixelSize: 11
                    color: Estilo.cores.textoSecundario
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Estilo.rounding.grande
                    color: "#fff5f5"
                    border.color: "#ffc9c9"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        visible: (telaFechamento.resumoAtual.suspeitas || []).length === 0
                        text: "Nenhuma comanda suspeita neste dia."
                        font.italic: true
                        color: Estilo.cores.textoSecundario
                        width: parent.width - 20
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ListView {
                        anchors.fill: parent
                        anchors.margins: 10
                        clip: true
                        spacing: 6
                        model: telaFechamento.resumoAtual.suspeitas || []

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: colunaSuspeita.implicitHeight + 16
                            radius: Estilo.rounding.padrao
                            color: areaSuspeita.containsMouse ? "#fff0f0" : "#ffffff"
                            border.color: areaSuspeita.containsMouse ? Estilo.cancelar.normal : "#ffa8a8"
                            border.width: 1

                            // O motivo de a comanda estar nesta lista é a
                            // suspeita de erro ao tirar o pedido — poder
                            // clicar e corrigir é o desfecho natural dela.
                            MouseArea {
                                id: areaSuspeita

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: popupFechamentoRapido.abrirComanda(modelData.arquivo, telaFechamento.dataSelecionada)
                            }

                            ColumnLayout {
                                id: colunaSuspeita

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 8
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.dataHora
                                    font.bold: true
                                    font.pixelSize: 12
                                    color: Estilo.cores.texto
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Pix · NP · R$ " + Number(modelData.valor).toFixed(2).replace(".", ",")
                                    font.pixelSize: 12
                                    color: Estilo.cancelar.normal
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.arquivo
                                    font.pixelSize: 10
                                    color: Estilo.cores.textoSecundario
                                    elide: Text.ElideMiddle
                                }
                            }
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

    FilaNotificacoes {
        id: filaNotificacoes
    }
}
