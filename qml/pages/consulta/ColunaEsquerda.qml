import QtQuick
import QtQuick.Controls
import estilo 1.0

// Coluna esquerda de Consulta.qml: contador de comandas, barra de busca,
// botão de alternância do modo de edição rápida e a lista de comandas.
Column {
    id: colunaEsquerda

    // Referência à página Consulta.qml (estado/funções compartilhadas) e ao
    // popup de exclusão, único e compartilhado por todos os itens.
    property var pagina
    property var popupExclusao
    property alias model: listaComandas.model
    property alias totalComandas: listaComandas.count

    // Estado local: só a própria lista precisa saber se os botões rápidos
    // de editar/apagar estão visíveis.
    property bool modoEdicao: false

    spacing: 10

    Text {
        text: "Comandas (" + listaComandas.count + ")"
        font.pixelSize: Estilo.fonte.padrao
        font.bold: true
        color: Estilo.cores.textoSecundario
    }

    // --- BARRA DE PESQUISA + BOTÃO DE MODO DE EDIÇÃO ---
    Row {
        id: linhaBusca

        width: parent.width
        height: 42
        spacing: 8

        TextField {
            id: campoBusca

            width: parent.width - btnModoEdicao.width - linhaBusca.spacing
            height: 42
            placeholderText: "🔍 Pesquisar por cliente ou conteúdo..."
            placeholderTextColor: "#95a5a6"
            font.pixelSize: Estilo.fonte.padrao
            leftPadding: 14
            rightPadding: 14
            color: Estilo.cores.texto
            selectByMouse: true
            onTextChanged: {
                colunaEsquerda.pagina.buscaAtual = text;
                colunaEsquerda.pagina.aplicarFiltro();
            }

            background: Rectangle {
                radius: Estilo.rounding.grande
                color: "#ffffff"
                border.color: campoBusca.activeFocus ? "#7c3aed" : Estilo.cores.borda
                border.width: campoBusca.activeFocus ? 2 : 1
            }
        }

        Button {
            id: btnModoEdicao

            height: 42
            padding: 10
            text: colunaEsquerda.modoEdicao ? "✖️  Concluir" : "✏️  Editar"
            onClicked: colunaEsquerda.modoEdicao = !colunaEsquerda.modoEdicao

            contentItem: Text {
                text: btnModoEdicao.text
                font.bold: true
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: Estilo.rounding.grande
                color: colunaEsquerda.modoEdicao ? (parent.down ? "#6d28d9" : (parent.hovered ? "#8b5cf6" : "#7c3aed")) : (parent.down ? "#4b5563" : (parent.hovered ? "#6b7280" : "#95a5a6"))
            }
        }
    }

    ListView {
        id: listaComandas

        width: parent.width
        height: parent.height - 30 - campoBusca.height - 10
        clip: true
        spacing: 8

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        delegate: ItemComandaDelegate {
            pagina: colunaEsquerda.pagina
            popupExclusao: colunaEsquerda.popupExclusao
            modoEdicao: colunaEsquerda.modoEdicao
            onAlternarModoEdicao: colunaEsquerda.modoEdicao = !colunaEsquerda.modoEdicao
        }
    }
}
