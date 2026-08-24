import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../components"

// Perguntado logo depois de lançar o pedido de uma mesa (botão "Salvar
// Mesa" em Salao.qml): imprimir agora a via de produção — a comanda que vai
// pro pizzaiolo — com o que acabou de ser pedido?
//
// Só lista (e só imprime) os itens AINDA NÃO impressos pra cozinha, não a
// mesa inteira: uma comanda de mesa é incrementada várias vezes ao longo da
// visita, e reimprimir tudo a cada rodada faria o pizzaiolo produzir de novo
// o que já saiu. Quem decide o que está pendente é
// SalaoController.itensPendentesCozinha — aqui os itens chegam prontos, só
// pra o atendente conferir antes de mandar pro papel.
Popup {
    id: popupComandaPizzaiolo

    property string mesaId: ""
    property int numeroMesa: 0
    property string cliente: ""
    // [{pedido, observacao, valor, borda, adicionais}, ...] — o que
    // itensPendentesCozinha() devolveu. Só pré-visualização: quem monta o
    // papel de verdade é SalaoController.imprimirComandaCozinha, que relê a
    // mesa salva em disco.
    property var itens: []

    // Falso só quando o pedido de impressão nem chegou a ser feito (mesa
    // sumiu do disco, nada pendente) — o resultado da impressão em si é
    // assíncrono e chega por redeController.impressaoResultado, já tratado
    // em Salao.qml.
    signal solicitado(bool sucesso)

    function abrirPara(idMesa, mesa, nomeCliente, itensPendentes) {
        mesaId = idMesa;
        numeroMesa = mesa;
        cliente = nomeCliente || "";
        itens = itensPendentes || [];
        spinnerCopiasCozinha.value = 1;
        open();
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    // Mesma conta de PopupFecharConta: largura até um teto confortável, e
    // altura acompanhando o conteúdo (que cresce com o número de itens),
    // com o Flickable abaixo cobrindo o caso de nem assim caber na janela.
    width: Math.min(520, (parent ? parent.width : 520) * 0.9)
    height: Math.max(200, Math.min(560, (parent ? parent.height : 560) * 0.9, colunaCozinha.implicitHeight + topPadding + bottomPadding))
    // O botão de imprimir já vem focado: lançar o pedido e apertar Enter é o
    // caminho normal (a maioria das rodadas vai pra cozinha), e Esc continua
    // fechando sem imprimir.
    onOpened: btnImprimirCozinha.forceActiveFocus()

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    contentItem: Flickable {
        id: flickableCozinha

        clip: true
        contentWidth: width
        contentHeight: colunaCozinha.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Column {
            id: colunaCozinha

            width: flickableCozinha.width
            spacing: Estilo.global.spacing.lg

            Row {
                spacing: Estilo.global.spacing.sm

                Icone {
                    nome: "fa6s.pizza-slice"
                    cor: Estilo.screen.salao.accent
                    tamanho: 20
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Comanda do pizzaiolo"
                    font.pixelSize: Estilo.global.fontSize.xxl
                    font.bold: true
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                width: parent.width
                text: "Pedido lançado. Deseja imprimir a comanda de produção com os itens abaixo?"
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.textSecondary
                wrapMode: Text.Wrap
            }

            // --- PRÉ-VISUALIZAÇÃO DO QUE VAI PRO PAPEL ---
            Rectangle {
                width: parent.width
                implicitHeight: colunaPreviaCozinha.implicitHeight + Estilo.global.padding.xl * 2
                radius: Estilo.global.radius.lg
                color: Estilo.global.surface
                border.color: Estilo.global.borderCard
                border.width: Estilo.global.borderWidth.hairline

                Column {
                    id: colunaPreviaCozinha

                    width: parent.width - Estilo.global.padding.xl * 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Estilo.global.padding.xl
                    spacing: Estilo.global.spacing.sm

                    Text {
                        width: parent.width
                        text: "MESA " + popupComandaPizzaiolo.numeroMesa + (popupComandaPizzaiolo.cliente.trim() !== "" ? " — " + popupComandaPizzaiolo.cliente : "")
                        font.pixelSize: Estilo.global.fontSize.lg
                        font.bold: true
                        color: Estilo.screen.salao.accent
                        elide: Text.ElideRight
                    }

                    Rectangle { width: parent.width; height: 1; color: Estilo.global.borderCard }

                    Repeater {
                        model: popupComandaPizzaiolo.itens

                        // Um item e, abaixo dele, o que o pizzaiolo precisa
                        // saber junto: borda, adicionais e observação. Sem
                        // valor nenhum — a via de produção não leva preço
                        // (ver SalaoController._montarComandaCozinha).
                        delegate: Column {
                            id: linhaItemCozinha

                            // O item desta linha guardado num nome próprio:
                            // dentro do Repeater de adicionais abaixo,
                            // "modelData" já é o adicional, não o item — ler
                            // o item por lá daria undefined (mesma armadilha
                            // documentada em PopupFecharConta.qml).
                            readonly property var itemCozinha: modelData

                            width: colunaPreviaCozinha.width
                            spacing: 2

                            Text {
                                width: parent.width
                                text: "• " + linhaItemCozinha.itemCozinha.pedido
                                font.pixelSize: Estilo.global.fontSize.md
                                font.bold: true
                                color: Estilo.global.text
                                wrapMode: Text.Wrap
                            }

                            Text {
                                readonly property var borda: linhaItemCozinha.itemCozinha.borda

                                width: parent.width
                                leftPadding: Estilo.global.spacing.md
                                visible: !!borda && !!borda.nome
                                text: visible ? ("Borda: " + borda.nome) : ""
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.textSecondary
                                wrapMode: Text.Wrap
                            }

                            Repeater {
                                model: linhaItemCozinha.itemCozinha.adicionais || []

                                delegate: Text {
                                    width: colunaPreviaCozinha.width
                                    leftPadding: Estilo.global.spacing.md
                                    text: "+ " + modelData.nome + (modelData.sabor ? " (" + modelData.sabor + ")" : "")
                                    font.pixelSize: Estilo.global.fontSize.sm
                                    color: Estilo.global.textSecondary
                                    wrapMode: Text.Wrap
                                }
                            }

                            Text {
                                width: parent.width
                                leftPadding: Estilo.global.spacing.md
                                visible: !!linhaItemCozinha.itemCozinha.observacao
                                text: linhaItemCozinha.itemCozinha.observacao || ""
                                font.pixelSize: Estilo.global.fontSize.sm
                                font.italic: true
                                color: Estilo.global.textSecondary
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }

            // --- CÓPIAS + AÇÕES ---
            Row {
                spacing: Estilo.global.spacing.md

                Text {
                    text: "Cópias"
                    font.pixelSize: Estilo.global.fontSize.md
                    font.bold: true
                    color: Estilo.global.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }

                SpinnerCopias {
                    id: spinnerCopiasCozinha

                    value: 1
                    width: 90
                    corDestaque: Estilo.screen.salao.accent
                }
            }

            Row {
                spacing: Estilo.global.spacing.lg
                anchors.right: parent.right

                Button {
                    id: btnAgoraNaoCozinha

                    text: "Agora não"
                    padding: Estilo.global.padding.md
                    focusPolicy: Qt.StrongFocus
                    Keys.onReturnPressed: clicked()
                    // Fecha sem marcar nada como impresso: os itens
                    // continuam pendentes e o popup volta a oferecê-los no
                    // próximo lançamento desta mesa.
                    onClicked: popupComandaPizzaiolo.close()

                    contentItem: Text {
                        text: btnAgoraNaoCozinha.text
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.action.neutral.pressed : (parent.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                        border.color: parent.activeFocus ? Estilo.global.text : "transparent"
                        border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : 0
                    }
                }

                Button {
                    id: btnImprimirCozinha

                    padding: Estilo.global.padding.md
                    focusPolicy: Qt.StrongFocus
                    Keys.onReturnPressed: clicked()
                    onClicked: {
                        var sucesso = salaoController.imprimirComandaCozinha(popupComandaPizzaiolo.mesaId, spinnerCopiasCozinha.value);
                        popupComandaPizzaiolo.close();
                        popupComandaPizzaiolo.solicitado(sucesso);
                    }

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent

                        Icone {
                            nome: "fa6s.print"
                            cor: Estilo.global.textOnAccent
                            tamanho: Estilo.global.fontSize.lg
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "Imprimir comanda"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.action.confirm.pressed : (parent.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                        border.color: parent.activeFocus ? Estilo.global.text : Estilo.action.confirm.pressed
                        border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                    }
                }
            }
        }
    }
}
