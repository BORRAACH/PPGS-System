import QtQuick
import QtQuick.Controls
import estilo 1.0
import "Formato.js" as Formato

// Ranking para a página de Estatística: produtos mais vendidos, bairros que
// mais recebem entrega, vendas por usuário.
//
// Aqui o desenho é de Rectangles, e não de Canvas como os outros gráficos: são
// poucas linhas (10 a 15), cada uma tem nome comprido que precisa de elide e
// de fonte do tema, e a barra é só um retângulo proporcional — Canvas daria
// mais trabalho e texto pior.
//
// A lista rola: o painel que a contém limita a altura (ver Estatistica.qml),
// e sem rolagem os últimos colocados ficavam cortados sem aviso.
Item {
    id: ranking

    // [{nome, valor, detalhe}] — `detalhe` é o texto secundário à direita
    // (ex.: o valor em reais de um produto contado por quantidade).
    property var itens: []
    property string formato: "numero"
    property color cor: Estilo.finance.positive
    property string mensagemVazio: "Sem dados no período"

    // A altura que a lista inteira pediria. Quem usa dá ao painel esta altura
    // até um teto; passando dele, a barra de rolagem aparece.
    implicitHeight: coluna.implicitHeight

    readonly property real _maior: {
        var maior = 0;
        for (var i = 0; i < itens.length; i++)
            maior = Math.max(maior, Number(itens[i].valor) || 0);
        return maior;
    }

    Text {
        anchors.centerIn: parent
        visible: ranking.itens.length === 0
        text: ranking.mensagemVazio
        font.pixelSize: Estilo.global.fontSize.sm
        color: Estilo.global.textMuted
    }

    Flickable {
        id: rolagem

        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: coluna.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        // Sempre à vista quando há item fora da área, e não só enquanto o
        // mouse rola: no estilo Basic o "quando necessário" esconde a barra
        // assim que a interação acaba, e quem olha o painel não descobre que a
        // lista continua abaixo.
        ScrollBar.vertical: ScrollBar {
            id: barra

            policy: rolagem.contentHeight > rolagem.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
        }

        Column {
            id: coluna

            // Abre espaço para a barra só quando ela aparece — senão o valor
            // da primeira linha ficaria embaixo dela.
            width: rolagem.width - (rolagem.contentHeight > rolagem.height ? 10 : 0)
            spacing: Estilo.global.spacing.sm

            Repeater {
                model: ranking.itens

                delegate: Item {
                    required property int index
                    required property var modelData

                    width: coluna.width
                    height: linha.implicitHeight + 6

                    Column {
                        id: linha

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Row {
                            width: parent.width
                            spacing: Estilo.global.spacing.sm

                            Text {
                                width: parent.width - valores.width - parent.spacing
                                text: (index + 1) + ". " + (modelData.nome || "")
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.text
                                elide: Text.ElideRight
                            }

                            Row {
                                id: valores

                                spacing: 6

                                Text {
                                    text: Formato.formatar(modelData.valor, ranking.formato, false)
                                    font.pixelSize: Estilo.global.fontSize.sm
                                    font.bold: true
                                    color: Estilo.global.text
                                }
                                Text {
                                    visible: text !== ""
                                    text: modelData.detalhe || ""
                                    font.pixelSize: Estilo.global.fontSize.xs
                                    color: Estilo.global.textMuted
                                    anchors.baseline: parent.children[0].baseline
                                }
                            }
                        }

                        // A barra: proporção em relação ao primeiro colocado.
                        Rectangle {
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Estilo.global.surfaceHover

                            Rectangle {
                                width: Math.max(2, parent.width * (Number(modelData.valor) || 0) / Math.max(1, ranking._maior))
                                height: parent.height
                                radius: parent.radius
                                color: ranking.cor
                            }
                        }
                    }
                }
            }
        }
    }
}
