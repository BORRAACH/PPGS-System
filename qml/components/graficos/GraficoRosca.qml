import QtQuick
import estilo 1.0
import "Formato.js" as Formato

// Rosca de participação para a página de Estatística: quanto cada modalidade
// e cada forma de pagamento representam no período. O total fica no meio, que
// é o lugar que sobra e responde a pergunta seguinte ("de quanto estamos
// falando?"). Canvas pelo mesmo motivo dos outros gráficos (sem QtCharts).
Item {
    id: grafico

    // [{nome, valor, cor}]
    property var fatias: []
    property string formato: "moeda"
    property string rotuloTotal: "Total"
    property string mensagemVazio: "Sem dados no período"

    implicitHeight: 200

    readonly property real total: {
        var soma = 0;
        for (var i = 0; i < fatias.length; i++)
            soma += Number(fatias[i].valor) || 0;
        return soma;
    }
    readonly property bool _vazio: total <= 0

    onFatiasChanged: tela.requestPaint()

    Canvas {
        id: tela

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Math.min(parent.width * 0.52, height)
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.clearRect(0, 0, width, height);

            var centroX = width / 2;
            var centroY = height / 2;
            var raio = Math.min(width, height) / 2 - 4;
            var raioInterno = raio * 0.62;

            if (grafico._vazio) {
                ctx.strokeStyle = Estilo.global.border;
                ctx.lineWidth = raio - raioInterno;
                ctx.beginPath();
                ctx.arc(centroX, centroY, (raio + raioInterno) / 2, 0, 2 * Math.PI);
                ctx.stroke();
                return;
            }

            var angulo = -Math.PI / 2;
            for (var i = 0; i < grafico.fatias.length; i++) {
                var valor = Number(grafico.fatias[i].valor) || 0;
                if (valor <= 0)
                    continue;
                var fim = angulo + 2 * Math.PI * valor / grafico.total;
                ctx.beginPath();
                ctx.moveTo(centroX, centroY);
                ctx.arc(centroX, centroY, raio, angulo, fim);
                ctx.closePath();
                ctx.fillStyle = grafico.fatias[i].cor;
                ctx.fill();
                angulo = fim;
            }

            // O furo da rosca, na cor do cartão.
            ctx.beginPath();
            ctx.arc(centroX, centroY, raioInterno, 0, 2 * Math.PI);
            ctx.fillStyle = Estilo.global.surface;
            ctx.fill();
        }
    }

    // Total no meio da rosca — Text, e não fillText, para herdar a fonte do
    // tema e quebrar linha sozinho.
    Column {
        anchors.centerIn: tela
        width: tela.width * 0.7
        spacing: 0

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: grafico.rotuloTotal
            font.pixelSize: Estilo.global.fontSize.xs
            color: Estilo.global.textMuted
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Formato.formatar(grafico.total, grafico.formato, grafico.total >= 10000)
            font.pixelSize: Estilo.global.fontSize.lg
            font.bold: true
            color: Estilo.global.text
            elide: Text.ElideRight
        }
    }

    Column {
        anchors.left: tela.right
        anchors.leftMargin: Estilo.global.spacing.md
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Estilo.global.spacing.xs

        Text {
            width: parent.width
            visible: grafico._vazio
            text: grafico.mensagemVazio
            font.pixelSize: Estilo.global.fontSize.sm
            color: Estilo.global.textMuted
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: grafico._vazio ? [] : grafico.fatias

            delegate: Row {
                required property var modelData

                readonly property real fatia: Number(modelData.valor) || 0

                width: parent.width
                spacing: 6

                Rectangle {
                    width: 10
                    height: 10
                    radius: 2
                    color: modelData.cor
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    width: parent.width - 16 - textoValor.width - parent.spacing * 2
                    text: modelData.nome
                    font.pixelSize: Estilo.global.fontSize.xs
                    color: Estilo.global.textSecondary
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    id: textoValor

                    text: Math.round(100 * parent.fatia / Math.max(1, grafico.total)) + "% · "
                          + Formato.formatar(parent.fatia, grafico.formato, true)
                    font.pixelSize: Estilo.global.fontSize.xs
                    font.bold: true
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
