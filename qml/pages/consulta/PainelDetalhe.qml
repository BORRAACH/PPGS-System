import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0

// Coluna direita de Consulta.qml ("Área principal"): mostra o conteúdo
// completo da comanda selecionada na lista, ou uma mensagem de estado vazio.
Rectangle {
    id: painelDetalhe

    // Referência à página Consulta.qml (comandaSelecionada/tituloComanda).
    property var pagina
    property int totalComandas: 0

    radius: Estilo.rounding.medio
    color: "#ffffff"
    border.color: Estilo.cores.bordaCard

    Text {
        anchors.centerIn: parent
        text: painelDetalhe.totalComandas === 0 ? "Nenhuma comanda encontrada em pedidos/" : "← Selecione uma comanda para ver os detalhes"
        color: "#95a5a6"
        font.italic: true
        font.pixelSize: Estilo.fonte.padrao
        visible: painelDetalhe.pagina.comandaSelecionada === null
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12
        visible: painelDetalhe.pagina.comandaSelecionada !== null

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Column {
              spacing:5

                Rectangle {
                    radius: 6
                    width: textoBadgeDetalhe.implicitWidth + 16
                    height: textoBadgeDetalhe.implicitHeight + 8
                    color: {
                        var tipo = painelDetalhe.pagina.comandaSelecionada ? painelDetalhe.pagina.comandaSelecionada.tipo : "";
                        return tipo === "Entrega" ? "#0284c7" : (tipo === "Mesa" ? "#0d9488" : "#d97706");
                    }

                    Text {
                        id: textoBadgeDetalhe

                        text: painelDetalhe.pagina.comandaSelecionada ? painelDetalhe.pagina.comandaSelecionada.tipo : ""
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: 12
                        anchors.centerIn: parent
                    }
                }

                Text {
                    text: painelDetalhe.pagina.comandaSelecionada ? painelDetalhe.pagina.tituloComanda(painelDetalhe.pagina.comandaSelecionada) : ""
                    font.pixelSize: 15
                    font.bold: true
                    color: Estilo.cores.texto
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#eeeeee"
        }

        // Área do conteúdo do cupom: fonte monoespaçada e sem quebra
        // de linha automática, para as colunas com "|" ficarem
        // alinhadas exatamente como saem na impressora. Rola nos
        // dois eixos quando o texto não cabe no painel.
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: Math.max(width, textoConteudo.implicitWidth)
            contentHeight: Math.max(height, textoConteudo.implicitHeight)
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            ScrollBar.horizontal: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            Text {
                id: textoConteudo

                text: painelDetalhe.pagina.comandaSelecionada ? painelDetalhe.pagina.comandaSelecionada.conteudo : ""
                font.family: "monospace"
                font.pixelSize: 13
                color: "#34495e"
                wrapMode: Text.NoWrap
            }
        }
    }
}
