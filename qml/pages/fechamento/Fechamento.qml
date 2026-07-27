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
                                    height: Math.min(blocoTipo.info.comandas.length * 44, 220)
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
                                        color: Estilo.cores.fundoPagina
                                        border.color: Estilo.cores.bordaCard
                                        border.width: 1

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
                            color: "#ffffff"
                            border.color: "#ffa8a8"
                            border.width: 1

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
                    telaFechamento.StackView.view.pop();
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

    FilaNotificacoes {
        id: filaNotificacoes
    }
}
