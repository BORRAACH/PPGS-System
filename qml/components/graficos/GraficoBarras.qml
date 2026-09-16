import QtQuick
import estilo 1.0
import "Formato.js" as Formato

// Barras verticais para a página de Estatística: faturamento por dia, vendas
// por dia (empilhadas por modalidade), vendas por hora.
//
// Desenhado em Canvas porque o PyQt6 do pip não traz o QtCharts — mesma razão
// do mapa em QML puro (components/MapaBlocos.qml). Um Canvas só, e não um
// Rectangle por barra: com 90 dias e três modalidades seriam 270 itens vivos
// na cena para um desenho que não interage item a item.
Item {
    id: grafico

    // Rótulo de cada coluna, na ordem ("2026-09-15" vira "15/09" sozinho).
    property var rotulos: []
    // [{nome, cor, valores: [...]}] — mais de uma série empilha.
    property var series: []
    property bool empilhado: true
    // "moeda" ou "numero": muda os rótulos do eixo e da dica.
    property string formato: "moeda"
    property string mensagemVazio: "Sem dados no período"
    // Mostra a legenda quando há mais de uma série.
    readonly property bool temLegenda: series.length > 1

    implicitHeight: 220

    readonly property real _margemEsquerda: 62
    readonly property real _margemDireita: 10
    readonly property real _margemTopo: 10
    readonly property real _margemBaixo: 22

    // Soma de uma coluna (empilhada) ou o maior valor dela.
    function _totalDaColuna(indice) {
        var total = 0;
        for (var s = 0; s < series.length; s++) {
            var valor = Number((series[s].valores || [])[indice]) || 0;
            total = empilhado ? total + valor : Math.max(total, valor);
        }
        return total;
    }

    function _maiorTotal() {
        var maior = 0;
        for (var i = 0; i < rotulos.length; i++)
            maior = Math.max(maior, _totalDaColuna(i));
        return maior;
    }

    readonly property bool _vazio: rotulos.length === 0 || _maiorTotal() <= 0

    onRotulosChanged: tela.requestPaint()
    onSeriesChanged: tela.requestPaint()
    onEmpilhadoChanged: tela.requestPaint()

    // Índice da coluna sob o mouse (-1 = nenhuma).
    property int _destacado: -1

    Row {
        id: legenda

        visible: grafico.temLegenda
        height: visible ? implicitHeight : 0
        spacing: Estilo.global.spacing.md

        Repeater {
            model: grafico.temLegenda ? grafico.series : []

            delegate: Row {
                required property var modelData

                spacing: 4

                Rectangle {
                    width: 10
                    height: 10
                    radius: 2
                    color: modelData.cor
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: modelData.nome
                    font.pixelSize: Estilo.global.fontSize.xs
                    color: Estilo.global.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    Canvas {
        id: tela

        anchors.top: legenda.visible ? legenda.bottom : parent.top
        anchors.topMargin: legenda.visible ? Estilo.global.spacing.xs : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            if (grafico._vazio) {
                ctx.fillStyle = Estilo.global.textMuted;
                ctx.font = "13px sans-serif";
                ctx.textAlign = "center";
                ctx.fillText(grafico.mensagemVazio, width / 2, height / 2);
                return;
            }

            var esquerda = grafico._margemEsquerda;
            var largura = width - esquerda - grafico._margemDireita;
            var topo = grafico._margemTopo;
            var altura = height - topo - grafico._margemBaixo;
            var teto = Formato.tetoDoEixo(grafico._maiorTotal());

            // Grade e rótulos do eixo.
            ctx.font = "10px sans-serif";
            ctx.textBaseline = "middle";
            for (var linha = 0; linha <= 4; linha++) {
                var y = topo + altura - (altura * linha / 4);
                ctx.strokeStyle = Estilo.global.border;
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(esquerda, Math.round(y) + 0.5);
                ctx.lineTo(esquerda + largura, Math.round(y) + 0.5);
                ctx.stroke();

                ctx.fillStyle = Estilo.global.textMuted;
                ctx.textAlign = "right";
                ctx.fillText(Formato.formatar(teto * linha / 4, grafico.formato, true), esquerda - 6, y);
            }

            // Barras.
            var vao = largura / grafico.rotulos.length;
            var larguraBarra = Math.max(3, Math.min(30, vao * 0.62));
            // Um rótulo a cada N para os dias não se sobreporem.
            var passo = Math.max(1, Math.ceil(grafico.rotulos.length / 12));
            ctx.textAlign = "center";

            for (var i = 0; i < grafico.rotulos.length; i++) {
                var centro = esquerda + vao * (i + 0.5);
                var base = topo + altura;

                for (var s = 0; s < grafico.series.length; s++) {
                    var valor = Number((grafico.series[s].valores || [])[i]) || 0;
                    if (valor <= 0)
                        continue;
                    var alturaBarra = altura * valor / teto;
                    var x = grafico.empilhado
                        ? centro - larguraBarra / 2
                        : centro - larguraBarra / 2 + (larguraBarra / grafico.series.length) * s;
                    var largura_ = grafico.empilhado ? larguraBarra : larguraBarra / grafico.series.length;
                    ctx.fillStyle = grafico.series[s].cor;
                    ctx.globalAlpha = (grafico._destacado === -1 || grafico._destacado === i) ? 1 : 0.35;
                    ctx.fillRect(Math.round(x), Math.round(base - alturaBarra), Math.round(largura_), Math.round(alturaBarra));
                    ctx.globalAlpha = 1;
                    if (grafico.empilhado)
                        base -= alturaBarra;
                }

                if (i % passo === 0) {
                    ctx.fillStyle = Estilo.global.textMuted;
                    ctx.fillText(Formato.diaCurto(grafico.rotulos[i]), centro, topo + altura + 11);
                }
            }
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton

            onPositionChanged: function (evento) {
                if (grafico._vazio)
                    return;
                var largura = tela.width - grafico._margemEsquerda - grafico._margemDireita;
                var indice = Math.floor((evento.x - grafico._margemEsquerda) / (largura / grafico.rotulos.length));
                grafico._destacado = (indice >= 0 && indice < grafico.rotulos.length) ? indice : -1;
                tela.requestPaint();
            }
            onExited: {
                grafico._destacado = -1;
                tela.requestPaint();
            }
        }

        // Dica com os valores da coluna sob o mouse.
        Rectangle {
            id: dica

            readonly property int indice: grafico._destacado

            visible: indice >= 0 && area.containsMouse
            width: colunaDica.implicitWidth + 16
            height: colunaDica.implicitHeight + 12
            radius: Estilo.global.radius.sm
            color: Estilo.global.surface
            border.color: Estilo.global.borderCard
            border.width: Estilo.global.borderWidth.hairline
            x: Math.max(0, Math.min(tela.width - width, area.mouseX + 12))
            y: Math.max(0, area.mouseY - height - 8)

            Column {
                id: colunaDica

                anchors.centerIn: parent
                spacing: 2

                Text {
                    text: dica.indice >= 0 ? Formato.diaCurto(grafico.rotulos[dica.indice]) : ""
                    font.pixelSize: Estilo.global.fontSize.xs
                    font.bold: true
                    color: Estilo.global.text
                }

                Repeater {
                    model: dica.indice >= 0 ? grafico.series : []

                    delegate: Text {
                        required property var modelData

                        text: (grafico.temLegenda ? modelData.nome + ": " : "")
                              + Formato.formatar((modelData.valores || [])[dica.indice] || 0, grafico.formato, false)
                        font.pixelSize: Estilo.global.fontSize.xs
                        color: modelData.cor
                    }
                }
            }
        }
    }
}
