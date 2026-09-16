import QtQuick
import estilo 1.0
import "Formato.js" as Formato

// Linhas para a página de Estatística: faturamento × líquido por dia, ticket
// médio. Mesma razão do Canvas do GraficoBarras.qml (sem QtCharts no PyQt6 do
// pip) e a mesma API: rótulos no eixo e uma ou mais séries com valores.
Item {
    id: grafico

    property var rotulos: []
    // [{nome, cor, valores: [...], preenchida: bool}]
    property var series: []
    property string formato: "moeda"
    property string mensagemVazio: "Sem dados no período"
    readonly property bool temLegenda: series.length > 1

    implicitHeight: 220

    readonly property real _margemEsquerda: 62
    readonly property real _margemDireita: 10
    readonly property real _margemTopo: 10
    readonly property real _margemBaixo: 22

    function _maior() {
        var maior = 0;
        for (var s = 0; s < series.length; s++) {
            var valores = series[s].valores || [];
            for (var i = 0; i < valores.length; i++)
                maior = Math.max(maior, Number(valores[i]) || 0);
        }
        return maior;
    }

    readonly property bool _vazio: rotulos.length === 0 || _maior() <= 0

    onRotulosChanged: tela.requestPaint()
    onSeriesChanged: tela.requestPaint()

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
                    height: 3
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

        function _x(indice) {
            var largura = width - grafico._margemEsquerda - grafico._margemDireita;
            if (grafico.rotulos.length <= 1)
                return grafico._margemEsquerda + largura / 2;
            return grafico._margemEsquerda + largura * indice / (grafico.rotulos.length - 1);
        }

        function _y(valor, teto) {
            var altura = height - grafico._margemTopo - grafico._margemBaixo;
            return grafico._margemTopo + altura - altura * (Number(valor) || 0) / teto;
        }

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
            var teto = Formato.tetoDoEixo(grafico._maior());

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

            for (var s = 0; s < grafico.series.length; s++) {
                var serie = grafico.series[s];
                var valores = serie.valores || [];
                if (valores.length === 0)
                    continue;

                // Área sob a linha, bem clara: dá volume ao gráfico sem
                // esconder a segunda série.
                if (serie.preenchida) {
                    ctx.beginPath();
                    ctx.moveTo(tela._x(0), topo + altura);
                    for (var p = 0; p < valores.length; p++)
                        ctx.lineTo(tela._x(p), tela._y(valores[p], teto));
                    ctx.lineTo(tela._x(valores.length - 1), topo + altura);
                    ctx.closePath();
                    ctx.globalAlpha = 0.12;
                    ctx.fillStyle = serie.cor;
                    ctx.fill();
                    ctx.globalAlpha = 1;
                }

                ctx.beginPath();
                for (var i = 0; i < valores.length; i++) {
                    var px = tela._x(i);
                    var py = tela._y(valores[i], teto);
                    if (i === 0)
                        ctx.moveTo(px, py);
                    else
                        ctx.lineTo(px, py);
                }
                ctx.strokeStyle = serie.cor;
                ctx.lineWidth = 2;
                ctx.lineJoin = "round";
                ctx.stroke();

                // Pontos só quando cabem: com 90 dias viram uma mancha.
                if (valores.length <= 40) {
                    ctx.fillStyle = serie.cor;
                    for (var q = 0; q < valores.length; q++) {
                        ctx.beginPath();
                        ctx.arc(tela._x(q), tela._y(valores[q], teto), 2.5, 0, 2 * Math.PI);
                        ctx.fill();
                    }
                }
            }

            // Guia vertical da coluna sob o mouse.
            if (grafico._destacado >= 0) {
                ctx.strokeStyle = Estilo.global.borderCard;
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(Math.round(tela._x(grafico._destacado)) + 0.5, topo);
                ctx.lineTo(Math.round(tela._x(grafico._destacado)) + 0.5, topo + altura);
                ctx.stroke();
            }

            var passo = Math.max(1, Math.ceil(grafico.rotulos.length / 12));
            ctx.fillStyle = Estilo.global.textMuted;
            ctx.textAlign = "center";
            for (var r = 0; r < grafico.rotulos.length; r += passo)
                ctx.fillText(Formato.diaCurto(grafico.rotulos[r]), tela._x(r), topo + altura + 11);
        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton

            onPositionChanged: function (evento) {
                if (grafico._vazio || grafico.rotulos.length === 0)
                    return;
                var largura = tela.width - grafico._margemEsquerda - grafico._margemDireita;
                var passo = grafico.rotulos.length > 1 ? largura / (grafico.rotulos.length - 1) : largura;
                var indice = Math.round((evento.x - grafico._margemEsquerda) / passo);
                grafico._destacado = Math.max(0, Math.min(grafico.rotulos.length - 1, indice));
                tela.requestPaint();
            }
            onExited: {
                grafico._destacado = -1;
                tela.requestPaint();
            }
        }

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
