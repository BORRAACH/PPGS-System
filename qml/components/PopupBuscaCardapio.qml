import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0

// Consulta rápida ao cardápio, aberta por Ctrl+S de QUALQUER tela (o atalho
// mora em main.qml, junto com esta instância, porque só a janela raiz existe
// o tempo todo — dentro de uma página o popup morreria na troca de tela e o
// atendente perderia a consulta ao navegar).
//
// Serve o momento em que o cliente está na linha e o atendente precisa de um
// preço ou de um ingrediente SEM abandonar a comanda meio preenchida. Por
// isso é só leitura: nada aqui adiciona item ao pedido. Um botão "adicionar"
// teria que saber em qual das telas (Balcão/Entrega/Salão) e em qual linha
// inserir, e erraria justamente quando a tela atual não é de pedido.
//
// Duas colunas: a lista de resultados à esquerda e o detalhe do item
// selecionado à direita. Em janela estreita (Responsivo.compacto) o detalhe
// desce para baixo da lista, que é o mesmo reflow que o resto do app usa.
Popup {
    id: popupBusca

    // O que o controller devolveu, como array JS puro — e NÃO copiado para um
    // ListModel. Cada item traz listas de objetos dentro ("precos",
    // "detalhes"), e o ListModel converte lista aninhada num sub-modelo: ao
    // reler com get(), o que volta não é mais um array e o painel de detalhe
    // fica vazio. É a mesma armadilha que Balcao.qml contorna guardando
    // "adicionais" como string JSON. Um array JS serve de model para a
    // ListView direto, sem cópia e sem conversão.
    property var resultados: []
    // Índice do item destacado na lista — é ele que alimenta o painel de
    // detalhe. -1 quando a busca não devolveu nada.
    property int indiceSelecionado: 0
    readonly property var itemSelecionado: (indiceSelecionado >= 0 && indiceSelecionado < resultados.length) ? resultados[indiceSelecionado] : null
    readonly property bool empilhado: Responsivo.compacto
    // Estado da consulta, de fora pra dentro: o que está digitado e quantos
    // itens casaram.
    readonly property alias termo: campoBusca.text
    readonly property int totalResultados: resultados.length

    // Refaz a busca do zero. Chamada a cada tecla digitada e ao abrir: o
    // controller relê os arquivos só quando eles mudaram em disco (ver
    // services/buscaCardapio.py), então repetir a chamada é barato.
    function atualizar() {
        popupBusca.resultados = cardapioController.buscar(campoBusca.text);
        popupBusca.indiceSelecionado = popupBusca.resultados.length > 0 ? 0 : -1;
        listaResultados.positionViewAtBeginning();
    }

    function mover(passo) {
        if (popupBusca.resultados.length === 0)
            return;

        var destino = popupBusca.indiceSelecionado + passo;
        if (destino < 0)
            destino = 0;
        if (destino > popupBusca.resultados.length - 1)
            destino = popupBusca.resultados.length - 1;
        popupBusca.indiceSelecionado = destino;
        listaResultados.positionViewAtIndex(destino, ListView.Contain);
    }

    modal: true
    focus: true
    // Centralizado na janela inteira: o pai é o overlay, não a página atual.
    anchors.centerIn: Overlay.overlay
    width: Math.min(Math.round(Responsivo.largura * 0.86), empilhado ? 620 : 980)
    height: Math.min(Math.round(Responsivo.altura * 0.82), 620)
    padding: 0
    // Fechar por clique fora ou Esc; sem isso o único jeito seria o botão.
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onOpened: {
        campoBusca.text = "";
        popupBusca.atualizar();
        campoBusca.forceActiveFocus();
    }

    background: Rectangle {
        color: Estilo.global.surface
        radius: Estilo.global.radius.xl
        border.color: Estilo.global.border
        border.width: Estilo.global.borderWidth.hairline
    }

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Estilo.global.padding.lg
        spacing: Estilo.global.spacing.md

        // --- CABEÇALHO: campo de busca ---
        RowLayout {
            Layout.fillWidth: true
            spacing: Estilo.global.spacing.sm

            Icone {
                nome: "fa6s.magnifying-glass"
                cor: Estilo.action.confirm.base
                tamanho: Estilo.global.fontSize.lg
                Layout.alignment: Qt.AlignVCenter
            }

            TextField {
                id: campoBusca

                Layout.fillWidth: true
                color: Estilo.global.textInput
                placeholderTextColor: Estilo.global.textPlaceholder
                placeholderText: "Buscar no cardápio — nome, ingrediente ou categoria"
                font.pixelSize: Estilo.global.fontSize.lg
                topPadding: 10
                bottomPadding: 10
                leftPadding: 12
                rightPadding: 12
                onTextChanged: popupBusca.atualizar()
                // As setas navegam a LISTA sem tirar o foco do campo: quem
                // está digitando não deveria ter que dar Tab pra escolher o
                // resultado e Shift+Tab pra corrigir o que digitou.
                Keys.onDownPressed: popupBusca.mover(1)
                Keys.onUpPressed: popupBusca.mover(-1)
                Keys.onPressed: function (evento) {
                    if (evento.key === Qt.Key_PageDown) {
                        popupBusca.mover(8);
                        evento.accepted = true;
                    } else if (evento.key === Qt.Key_PageUp) {
                        popupBusca.mover(-8);
                        evento.accepted = true;
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: Estilo.global.inputBackground
                    border.color: campoBusca.activeFocus ? Estilo.action.confirm.base : Estilo.global.border
                    border.width: Estilo.global.borderWidth.hairline
                }
            }

            Text {
                text: popupBusca.totalResultados === 1 ? "1 item" : (popupBusca.totalResultados + " itens")
                font.pixelSize: Estilo.global.fontSize.sm
                color: Estilo.global.textMuted
                Layout.alignment: Qt.AlignVCenter
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: Estilo.global.borderWidth.hairline
            color: Estilo.global.divider
        }

        // --- CORPO: lista + detalhe ---
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: popupBusca.empilhado ? 1 : 2
            columnSpacing: Estilo.global.spacing.md
            rowSpacing: Estilo.global.spacing.md

            ListView {
                id: listaResultados

                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: popupBusca.empilhado ? -1 : Math.round(popupBusca.width * 0.46)
                clip: true
                model: popupBusca.resultados
                currentIndex: popupBusca.indiceSelecionado
                spacing: 2
                // A máquina do balcão tem 2 núcleos: reaproveitar o delegate
                // ao rolar evita reconstruir a linha inteira a cada pixel.
                reuseItems: true

                ScrollBar.vertical: ScrollBar {
                }

                delegate: Rectangle {
                    id: linhaResultado

                    required property int index
                    // O model é um array JS, então o item inteiro chega em
                    // modelData — não há roles pra declarar um a um.
                    required property var modelData

                    readonly property bool selecionada: index === popupBusca.indiceSelecionado

                    width: ListView.view.width - (ListView.view.ScrollBar.vertical.visible ? ListView.view.ScrollBar.vertical.width : 0)
                    height: colunaLinha.implicitHeight + Estilo.global.padding.sm * 2
                    radius: Estilo.global.radius.md
                    color: selecionada ? Estilo.global.surfacePressed : (areaLinha.containsMouse ? Estilo.global.surfaceHover : "transparent")

                    Icone {
                        id: iconeLinha

                        nome: linhaResultado.modelData.icone
                        cor: linhaResultado.modelData.cor
                        tamanho: Estilo.global.fontSize.lg
                        anchors.left: parent.left
                        anchors.leftMargin: Estilo.global.padding.sm
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        id: colunaLinha

                        anchors.left: iconeLinha.right
                        anchors.leftMargin: Estilo.global.spacing.sm
                        anchors.right: parent.right
                        anchors.rightMargin: Estilo.global.padding.sm
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Row {
                            width: parent.width
                            spacing: Estilo.global.spacing.xs

                            Text {
                                text: linhaResultado.modelData.nome
                                font.pixelSize: Estilo.global.fontSize.md
                                font.bold: true
                                color: Estilo.global.text
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, parent.width - (linhaResultado.modelData.emPromocao ? 78 : 0))
                            }

                            // Etiqueta de promoção: o preço mostrado é o de
                            // hoje, e sem esta marca ele pareceria o preço de
                            // tabela (ver services/buscaCardapio.py).
                            Rectangle {
                                visible: linhaResultado.modelData.emPromocao
                                width: textoPromo.implicitWidth + 10
                                height: textoPromo.implicitHeight + 4
                                radius: Estilo.global.radius.pill
                                color: Estilo.finance.positive
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    id: textoPromo

                                    text: "PROMO"
                                    anchors.centerIn: parent
                                    font.pixelSize: Estilo.global.fontSize.xs
                                    font.bold: true
                                    color: Estilo.global.textOnAccent
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            text: linhaResultado.modelData.categoria + "  ·  " + linhaResultado.modelData.resumoPrecos
                            font.pixelSize: Estilo.global.fontSize.sm
                            color: Estilo.global.textSecondary
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: areaLinha

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Só destaca: o foco continua no campo de busca, pra
                        // o atendente seguir refinando o termo sem reclicar.
                        onClicked: popupBusca.indiceSelecionado = linhaResultado.index
                    }
                }

                // Vazio: some quando há resultado, e explica o que fazer.
                Text {
                    anchors.centerIn: parent
                    width: parent.width - Estilo.global.padding.lg * 2
                    visible: popupBusca.totalResultados === 0
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Nenhum item do cardápio casa com \"" + campoBusca.text + "\"."
                    font.pixelSize: Estilo.global.fontSize.md
                    color: Estilo.global.textMuted
                }
            }

            // --- PAINEL DE DETALHE ---
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Estilo.global.radius.lg
                color: Estilo.global.background
                border.color: Estilo.global.border
                border.width: Estilo.global.borderWidth.hairline

                Flickable {
                    id: rolagemDetalhe

                    anchors.fill: parent
                    anchors.margins: Estilo.global.padding.lg
                    contentHeight: colunaDetalhe.implicitHeight
                    clip: true
                    visible: popupBusca.itemSelecionado !== null

                    ScrollBar.vertical: ScrollBar {
                    }

                    Column {
                        id: colunaDetalhe

                        width: rolagemDetalhe.width
                        spacing: Estilo.global.spacing.sm

                        Row {
                            width: parent.width
                            spacing: Estilo.global.spacing.sm

                            Icone {
                                nome: popupBusca.itemSelecionado ? popupBusca.itemSelecionado.icone : ""
                                cor: popupBusca.itemSelecionado ? popupBusca.itemSelecionado.cor : Estilo.global.text
                                tamanho: Estilo.global.fontSize.xl
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: popupBusca.itemSelecionado ? popupBusca.itemSelecionado.categoria.toUpperCase() : ""
                                font.pixelSize: Estilo.global.fontSize.xs
                                font.bold: true
                                font.letterSpacing: Estilo.global.letterSpacing.wider
                                color: popupBusca.itemSelecionado ? popupBusca.itemSelecionado.cor : Estilo.global.textSecondary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Text {
                            width: parent.width
                            text: popupBusca.itemSelecionado ? popupBusca.itemSelecionado.nome : ""
                            font.family: Estilo.global.fontFamily.title
                            font.pixelSize: Estilo.global.fontSize.title
                            color: Estilo.global.text
                            wrapMode: Text.WordWrap
                        }

                        // --- Preços ---
                        Repeater {
                            model: popupBusca.itemSelecionado ? popupBusca.itemSelecionado.precos : []

                            delegate: Row {
                                required property var modelData

                                width: colunaDetalhe.width
                                spacing: Estilo.global.spacing.sm

                                Text {
                                    text: modelData.rotulo
                                    width: 110
                                    font.pixelSize: Estilo.global.fontSize.md
                                    color: Estilo.global.textSecondary
                                }

                                Text {
                                    text: modelData.valor
                                    font.pixelSize: Estilo.global.fontSize.lg
                                    font.bold: true
                                    color: Estilo.global.text
                                }
                            }
                        }

                        // --- Preço de tabela, quando hoje tem promoção ---
                        Text {
                            width: parent.width
                            visible: popupBusca.itemSelecionado ? popupBusca.itemSelecionado.emPromocao : false
                            text: {
                                if (!popupBusca.itemSelecionado || !popupBusca.itemSelecionado.emPromocao)
                                    return "";

                                var partes = [];
                                var tabela = popupBusca.itemSelecionado.precosTabela;
                                for (var i = 0; i < tabela.length; i++)
                                    partes.push(tabela[i].rotulo + " " + tabela[i].valor);
                                return "Em promoção hoje. Preço de tabela: " + partes.join("  ·  ");
                            }
                            font.pixelSize: Estilo.global.fontSize.sm
                            color: Estilo.finance.positive
                            wrapMode: Text.WordWrap
                        }

                        // --- Ingredientes e demais campos da categoria ---
                        Repeater {
                            model: popupBusca.itemSelecionado ? popupBusca.itemSelecionado.detalhes : []

                            delegate: Column {
                                required property var modelData

                                width: colunaDetalhe.width
                                spacing: 2
                                topPadding: Estilo.global.spacing.xs

                                Text {
                                    text: modelData.rotulo.toUpperCase()
                                    font.pixelSize: Estilo.global.fontSize.xs
                                    font.bold: true
                                    font.letterSpacing: Estilo.global.letterSpacing.wide
                                    color: Estilo.global.textMuted
                                }

                                Text {
                                    width: parent.width
                                    text: modelData.valor
                                    font.pixelSize: Estilo.global.fontSize.md
                                    color: Estilo.global.text
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: popupBusca.itemSelecionado === null
                    text: "Selecione um item"
                    font.pixelSize: Estilo.global.fontSize.md
                    color: Estilo.global.textMuted
                }
            }
        }

        // --- RODAPÉ: ajuda de teclado ---
        Text {
            Layout.fillWidth: true
            text: "↑ ↓ navegar   ·   Esc fechar   ·   Ctrl+S abre esta busca de qualquer tela"
            font.pixelSize: Estilo.global.fontSize.xs
            color: Estilo.global.textMuted
        }
    }
}
