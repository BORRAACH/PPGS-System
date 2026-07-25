import QtQuick
import QtQuick.Controls
import estilo 1.0

// Painel de resumo mostrado ao lado dos formulários de Balcão/Entrega —
// espelha as informações que vão para a comanda impressa (ver
// controllers/balcaoController.py e controllers/entregaController.py,
// método _salvarComanda), pra o atendente conferir valor total, forma de
// pagamento, status e taxa de entrega antes de imprimir/lançar.
Rectangle {
    id: root

    property alias itens: repeaterItens.model
    property color corDestaque: Estilo.confirmar.normal
    property string formaPagamento: ""
    property string troco: ""
    property bool pago: false
    property string taxaEntrega: ""
    property bool mostrarTaxaEntrega: false

    function _valorNumero(texto) {
        if (!texto)
            return 0;

        var limpo = String(texto).replace("R$", "").trim().replace(",", ".");
        var numero = parseFloat(limpo);
        return isNaN(numero) ? 0 : numero;
    }

    function _formatarMoeda(valor) {
        return "R$ " + valor.toFixed(2).replace(".", ",");
    }

    readonly property int quantidadeItens: {
        var n = 0;
        for (var i = 0; i < itens.count; i++) {
            if (itens.get(i).pedido !== "")
                n++;

        }
        return n;
    }
    readonly property real valorItens: {
        var soma = 0;
        for (var i = 0; i < itens.count; i++) {
            var item = itens.get(i);
            if (item.pedido !== "")
                soma += _valorNumero(item.valor);

        }
        return soma;
    }
    readonly property real valorTaxa: mostrarTaxaEntrega ? _valorNumero(taxaEntrega) : 0
    readonly property real valorTotal: valorItens + valorTaxa
    readonly property bool ehDinheiro: formaPagamento === "Dinheiro" && troco !== ""
    readonly property real trocoADar: _valorNumero(troco) - valorTotal

    width: 300
    implicitHeight: colunaResumo.implicitHeight + Estilo.preenchimento.grande * 2
    radius: Estilo.rounding.painel
    color: "#ffffff"
    border.color: Estilo.cores.bordaCard
    border.width: 1

    Column {
        id: colunaResumo

        width: parent.width - Estilo.preenchimento.grande * 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Estilo.preenchimento.grande
        spacing: Estilo.espacamento.normal

        Row {
            spacing: 8

            Icone {
                nome: "fa6s.receipt"
                cor: root.corDestaque
                tamanho: 18
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "RESUMO DA COMANDA"
                font.pixelSize: 15
                font.bold: true
                color: root.corDestaque
                anchors.verticalCenter: parent.verticalCenter
            }

        }

        Rectangle {
            width: parent.width
            height: 1
            color: Estilo.cores.bordaCard
        }

        // --- Itens do pedido, simplificados (nome + valor) ---
        Text {
            width: parent.width
            visible: root.quantidadeItens === 0
            text: "Nenhum item adicionado ainda."
            font.pixelSize: 13
            font.italic: true
            color: Estilo.cores.textoSecundario
            wrapMode: Text.WordWrap
        }

        Column {
            width: parent.width
            spacing: 6
            visible: root.quantidadeItens > 0

            Repeater {
                id: repeaterItens

                delegate: Item {
                    width: colunaResumo.width
                    height: visible ? Math.max(textoNomeItem.implicitHeight, textoValorItem.implicitHeight) : 0
                    visible: model.pedido !== ""

                    Text {
                        id: textoNomeItem

                        anchors.left: parent.left
                        anchors.right: textoValorItem.left
                        anchors.rightMargin: 8
                        text: "• " + model.pedido
                        font.pixelSize: 13
                        color: Estilo.cores.texto
                        elide: Text.ElideRight
                    }

                    Text {
                        id: textoValorItem

                        anchors.right: parent.right
                        text: model.valor || "R$ 0,00"
                        font.pixelSize: 13
                        color: Estilo.cores.textoSecundario
                    }

                }

            }

        }

        Rectangle {
            width: parent.width
            height: 1
            color: Estilo.cores.bordaCard
        }

        // --- Taxa de entrega (só aparece na tela de Entrega) ---
        Item {
            width: parent.width
            height: textoTaxaLabel.implicitHeight
            visible: root.mostrarTaxaEntrega

            Text {
                id: textoTaxaLabel

                anchors.left: parent.left
                text: "Taxa de entrega"
                font.pixelSize: 13
                color: Estilo.cores.texto
            }

            Text {
                anchors.right: parent.right
                text: root._formatarMoeda(root.valorTaxa)
                font.pixelSize: 13
                color: Estilo.cores.texto
            }

        }

        // --- Forma de pagamento ---
        Item {
            width: parent.width
            height: textoFormaLabel.implicitHeight

            Text {
                id: textoFormaLabel

                anchors.left: parent.left
                text: "Forma de pagamento"
                font.pixelSize: 13
                color: Estilo.cores.texto
            }

            Text {
                anchors.right: parent.right
                text: root.formaPagamento || "—"
                font.pixelSize: 13
                font.bold: true
                color: Estilo.cores.texto
            }

        }

        // --- Troco (só quando o pagamento é em dinheiro e o valor foi informado) ---
        Item {
            width: parent.width
            height: root.ehDinheiro ? colunaTroco.implicitHeight : 0
            visible: root.ehDinheiro
            clip: true

            Column {
                id: colunaTroco

                width: parent.width
                spacing: 4

                Item {
                    width: parent.width
                    height: textoTrocoLabel.implicitHeight

                    Text {
                        id: textoTrocoLabel

                        anchors.left: parent.left
                        text: "Troco para"
                        font.pixelSize: 13
                        color: Estilo.cores.texto
                    }

                    Text {
                        anchors.right: parent.right
                        text: root.troco
                        font.pixelSize: 13
                        color: Estilo.cores.texto
                    }

                }

                Item {
                    width: parent.width
                    height: textoTrocoADarLabel.implicitHeight

                    Text {
                        id: textoTrocoADarLabel

                        anchors.left: parent.left
                        text: "Troco a dar"
                        font.pixelSize: 13
                        color: Estilo.cores.texto
                    }

                    Text {
                        anchors.right: parent.right
                        text: root._formatarMoeda(Math.max(root.trocoADar, 0))
                        font.pixelSize: 13
                        font.bold: true
                        color: root.trocoADar < 0 ? Estilo.cancelar.normal : Estilo.cores.texto
                    }

                }

            }

        }

        // --- Status de pagamento ---
        Item {
            width: parent.width
            height: chipStatus.height

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Status"
                font.pixelSize: 13
                color: Estilo.cores.texto
            }

            Rectangle {
                id: chipStatus

                anchors.right: parent.right
                width: textoStatus.implicitWidth + 20
                height: textoStatus.implicitHeight + 8
                radius: Estilo.rounding.cheio
                color: root.pago ? Estilo.confirmar.normal : Estilo.cancelar.normal

                Text {
                    id: textoStatus

                    anchors.centerIn: parent
                    text: root.pago ? "PAGO" : "NÃO PAGO"
                    font.pixelSize: 12
                    font.bold: true
                    color: "#ffffff"
                }

            }

        }

        Rectangle {
            width: parent.width
            height: 1
            color: Estilo.cores.bordaCard
        }

        // --- Total ---
        Item {
            width: parent.width
            height: textoTotalLabel.implicitHeight

            Text {
                id: textoTotalLabel

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "TOTAL"
                font.pixelSize: 16
                font.bold: true
                color: root.corDestaque
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root._formatarMoeda(root.valorTotal)
                font.pixelSize: 18
                font.bold: true
                color: root.corDestaque
            }

        }

    }

}
