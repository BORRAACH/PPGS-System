import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

// Coluna esquerda de Consulta.qml: contador de comandas, barra de busca,
// botão de alternância do modo de edição rápida e a lista de comandas —
// hoje exibida direto, dias anteriores aninhados numa caixinha por dia
// (fechada por padrão, mesmo padrão de "Mapeamento por origem" em
// Fechamento.qml).
Column {
    id: colunaEsquerda

    // Referência à página Consulta.qml (estado/funções compartilhadas) e ao
    // popup de exclusão, único e compartilhado por todos os itens.
    property var pagina
    property var popupExclusao
    property alias model: listaHoje.model
    // Total exibido (hoje + todos os dias anteriores agrupados), não só o
    // que está com a caixinha aberta — usado por PainelDetalhe.qml pra
    // decidir a mensagem de "nenhuma comanda encontrada".
    readonly property int totalComandas: {
        var total = listaHoje.count;
        var grupos = colunaEsquerda.pagina ? colunaEsquerda.pagina.gruposAnteriores : [];
        for (var i = 0; i < grupos.length; i++)
            total += grupos[i].comandas.length;
        return total;
    }
    // Exposto para Consulta.qml poder focar a busca e já entrar com o
    // caractere digitado, sem precisar clicar antes no campo (ver
    // Consulta.qml Keys.onPressed).
    property alias campoBusca: campoBusca

    // Estado local: só a própria lista precisa saber se os botões rápidos
    // de editar/apagar estão visíveis.
    property bool modoEdicao: false

    spacing: Estilo.global.spacing.md

    Text {
        text: "Comandas (" + colunaEsquerda.totalComandas + ")"
        font.pixelSize: Estilo.global.fontSize.lg
        font.bold: true
        color: Estilo.global.textSecondary
    }

    // --- BARRA DE PESQUISA + BOTÃO DE MODO DE EDIÇÃO ---
    Row {
        id: linhaBusca

        width: parent.width
        height: 42
        spacing: Estilo.global.spacing.sm

        Search {
            id: campoBusca

            width: parent.width - btnModoEdicao.width - linhaBusca.spacing
            corDestaque: Estilo.screen.consulta.accent
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
                if (colunaEsquerda.pagina.buscaAtual.trim() !== "" && listaHoje.count > 0) {
                    colunaEsquerda.pagina.selecionarComanda(listaHoje.model.get(0));
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
            padding: Estilo.global.padding.md
            onClicked: colunaEsquerda.modoEdicao = !colunaEsquerda.modoEdicao

            contentItem: Row {
                spacing: Estilo.global.spacing.xs
                anchors.centerIn: parent
                Icone {
                    nome: colunaEsquerda.modoEdicao ? "fa6s.xmark" : "fa6s.pen"
                    cor: Estilo.global.textOnAccent
                    tamanho: Estilo.global.fontSize.lg
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: colunaEsquerda.modoEdicao ? "Concluir" : "Editar"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: colunaEsquerda.modoEdicao ? (parent.down ? Estilo.screen.consulta.pressed : (parent.hovered ? Estilo.screen.consulta.hover : Estilo.screen.consulta.base)) : (parent.down ? Estilo.action.neutral.pressed : (parent.hovered ? Estilo.action.neutral.base : Estilo.action.neutral.hover))
            }
        }
    }

    // --- FILTRO POR STATUS ---
    // Aberta = ainda sem baixa, fora do caixa do dia; fechada = já conferida
    // e contando no fechamento (ver services/rede/baixaComandas.py). É o
    // único controle da tela que esconde comandas — a busca ao lado só
    // reordena.
    Row {
        id: linhaFiltroStatus

        spacing: Estilo.global.spacing.xs

        Repeater {
            model: [
                { "rotulo": "Todas", "valor": "todas" },
                { "rotulo": "Abertas", "valor": "abertas" },
                { "rotulo": "Fechadas", "valor": "fechadas" }
            ]

            delegate: Button {
                id: botaoFiltro

                required property var modelData

                readonly property bool ativo: colunaEsquerda.pagina.filtroStatus === modelData.valor

                height: 28
                padding: Estilo.global.padding.lg
                onClicked: {
                    colunaEsquerda.pagina.filtroStatus = modelData.valor;
                    colunaEsquerda.pagina.aplicarFiltro();
                }

                contentItem: Text {
                    text: botaoFiltro.modelData.rotulo
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.family: Estilo.global.fontFamily.title
                    font.bold: botaoFiltro.ativo
                    color: botaoFiltro.ativo ? Estilo.global.textOnAccent : Estilo.global.textSecondary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: botaoFiltro.ativo
                        ? (botaoFiltro.down ? Estilo.screen.consulta.pressed : Estilo.screen.consulta.base)
                        : (botaoFiltro.hovered ? Estilo.screen.consulta.soft : "transparent")
                    border.color: botaoFiltro.ativo ? Estilo.screen.consulta.pressed : Estilo.global.border
                    border.width: Estilo.global.borderWidth.hairline
                }
            }
        }
    }

    // Única área de rolagem da coluna — hoje e os dias anteriores rolam
    // juntos, num scroll só (mesmo raciocínio do Flickable de "Mapeamento
    // por origem" em Fechamento.qml). As duas ListView internas abaixo não
    // rolam sozinhas (interactive: false, altura = contentHeight): elas só
    // existem pra reaproveitar ItemComandaDelegate.qml sem alterá-lo (ele
    // depende de "ListView.view" pra própria largura).
    Flickable {
        id: flickableComandas

        width: parent.width
        height: parent.height - 30 - campoBusca.height - linhaFiltroStatus.height - 2 * colunaEsquerda.spacing
        clip: true
        contentWidth: width
        contentHeight: colunaListas.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: colunaListas

            width: flickableComandas.width
            spacing: Estilo.global.spacing.lg

            // --- CARREGANDO ---
            // A tela abre antes das comandas (ver Consulta.qml
            // carregarComandas), e elas entram na lista aos poucos. Sem esta
            // caixa, esse intervalo seria indistinguível de "não tem comanda
            // nenhuma aqui" — que é a leitura mais alarmante possível numa
            // tela de consulta de vendas.
            Rectangle {
                id: caixaCarregando

                readonly property bool ativa: colunaEsquerda.pagina ? colunaEsquerda.pagina.carregando : false

                Layout.fillWidth: true
                visible: ativa
                implicitHeight: linhaCarregando.implicitHeight + 24
                radius: Estilo.global.radius.sm
                color: Estilo.global.surface
                border.color: Estilo.global.borderCard
                border.width: Estilo.global.borderWidth.hairline

                Row {
                    id: linhaCarregando

                    anchors.centerIn: parent
                    spacing: Estilo.global.spacing.md

                    BusyIndicator {
                        width: 20
                        height: 20
                        running: caixaCarregando.ativa
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Carregando comandas..."
                        font.pixelSize: Estilo.global.fontSize.lg
                        color: Estilo.global.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // --- HOJE (direto, sem caixinha) ---
            ListView {
                id: listaHoje

                Layout.fillWidth: true
                Layout.preferredHeight: contentHeight
                interactive: false
                spacing: Estilo.global.spacing.sm

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

            // --- DIAS ANTERIORES (agrupados, uma caixinha fechada por dia) ---
            Repeater {
                model: colunaEsquerda.pagina ? colunaEsquerda.pagina.gruposAnteriores : []

                delegate: ColumnLayout {
                    id: blocoDia

                    required property var modelData
                    // Fechado por padrão — só abre no clique do box (ver
                    // areaCabecalhoDia), mesmo padrão de "Mapeamento por
                    // origem" em Fechamento.qml.
                    property bool expandido: false

                    Layout.fillWidth: true
                    spacing: Estilo.global.spacing.xs

                    // Precisa ser um ListModel (não o array direto) pra
                    // ItemComandaDelegate.qml continuar acessando os campos
                    // via "model.xxx" do mesmo jeito que já faz na lista de
                    // hoje.
                    ListModel {
                        id: modeloDia
                    }

                    // Preenchido só quando a caixinha é aberta pela primeira
                    // vez, e não na criação do delegate: fechada, ela mostra
                    // apenas o dia e a contagem (que saem do próprio
                    // modelData), então montar o modelo antes disso era jogar
                    // no carregamento da página o custo de todas as comandas
                    // de todos os dias anteriores — a maioria das quais
                    // ninguém vai abrir.
                    function _garantirPreenchido() {
                        if (modeloDia.count > 0)
                            return;
                        for (var i = 0; i < blocoDia.modelData.comandas.length; i++)
                            modeloDia.append(blocoDia.modelData.comandas[i]);
                    }

                    onExpandidoChanged: {
                        if (blocoDia.expandido)
                            blocoDia._garantirPreenchido();
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: linhaCabecalhoDia.implicitHeight + 16
                        radius: Estilo.global.radius.sm
                        color: Estilo.global.surface
                        border.color: Estilo.global.borderCard
                        border.width: Estilo.global.borderWidth.hairline

                        MouseArea {
                            id: areaCabecalhoDia

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: blocoDia.expandido = !blocoDia.expandido
                        }

                        RowLayout {
                            id: linhaCabecalhoDia

                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: Estilo.global.spacing.sm

                            Icone {
                                nome: "fa6s.calendar-day"
                                cor: Estilo.global.textSecondary
                                tamanho: 14
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: blocoDia.modelData.dia
                                font.bold: true
                                font.pixelSize: Estilo.global.fontSize.lg
                                color: Estilo.global.text
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: blocoDia.modelData.comandas.length + (blocoDia.modelData.comandas.length === 1 ? " comanda" : " comandas")
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.textSecondary
                            }

                            Icone {
                                nome: blocoDia.expandido ? "fa6s.chevron-up" : "fa6s.chevron-down"
                                cor: Estilo.global.textSecondary
                                tamanho: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.leftMargin: 18
                        Layout.preferredHeight: contentHeight
                        visible: blocoDia.expandido
                        interactive: false
                        spacing: Estilo.global.spacing.sm
                        model: modeloDia

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
            }
        }
    }
}
