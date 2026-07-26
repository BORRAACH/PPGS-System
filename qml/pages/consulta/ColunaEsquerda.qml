import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../components"

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
    // Exposto para Consulta.qml poder focar a busca e já entrar com o
    // caractere digitado, sem precisar clicar antes no campo (ver
    // Consulta.qml Keys.onPressed).
    property alias campoBusca: campoBusca

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

        Search {
            id: campoBusca

            width: parent.width - btnModoEdicao.width - linhaBusca.spacing
            corDestaque: "#7c3aed"
            placeholderText: "Pesquisar por cliente ou conteúdo..."
            // Só reordena/exibe depois que o usuário para de digitar (ver
            // debounceBusca abaixo) — reprocessar a lista inteira a cada
            // tecla é o que travava em CPUs fracas conforme a lista de
            // comandas cresce.
            onTextChanged: {
                colunaEsquerda.pagina.buscaAtual = text;
                debounceBusca.restart();
            }
            // Enter age na hora (não espera o debounce): já reordena, se
            // ainda não reordenou, e seleciona a comanda mais próxima (topo
            // da lista, ver Consulta.qml aplicarFiltro) — não existe
            // "resultado único" aqui porque a busca reordena em vez de
            // esconder comandas.
            onAccepted: {
                debounceBusca.stop();
                colunaEsquerda.pagina.aplicarFiltro();
                if (colunaEsquerda.pagina.buscaAtual.trim() !== "" && listaComandas.count > 0) {
                    colunaEsquerda.pagina.selecionarComanda(listaComandas.model.get(0));
                    campoBusca.text = "";
                }
            }
        }

        // Debounce: espera uma pequena pausa na digitação antes de reordenar
        // a lista, em vez de fazer isso a cada tecla. 200ms é imperceptível
        // para quem digita, mas evita recalcular a pontuação de todas as
        // comandas (e o sort) a cada letra numa lista que só cresce com o
        // tempo.
        Timer {
            id: debounceBusca

            interval: 200
            repeat: false
            onTriggered: colunaEsquerda.pagina.aplicarFiltro()
        }

        Button {
            id: btnModoEdicao

            height: 42
            padding: 10
            onClicked: colunaEsquerda.modoEdicao = !colunaEsquerda.modoEdicao

            contentItem: Row {
                spacing: 6
                anchors.centerIn: parent
                Icone {
                    nome: colunaEsquerda.modoEdicao ? "fa6s.xmark" : "fa6s.pen"
                    cor: "#ffffff"
                    tamanho: Estilo.fonte.padrao
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: colunaEsquerda.modoEdicao ? "Concluir" : "Editar"
                    font.bold: true
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                }
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
