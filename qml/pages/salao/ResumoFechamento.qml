import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../components"

// Painel de pré-visualização mostrado dentro do popup de fechamento
// (PopupFecharConta.qml), ao lado dos controles — mesmo espírito visual de
// qml/components/ResumoComanda.qml (usado em Balcão/Entrega), mas com um
// formato de dados diferente: aqui são os itens do pedido da MESA inteira
// mais uma divisão por pessoa (cada uma com sua própria forma de
// pagamento/status/troco), não uma única comanda com um pagamento só — por
// isso um componente próprio em vez de reaproveitar aquele.
Rectangle {
    id: root

    // Itens do pedido da mesa: [{pedido, observacao, valor}, ...] — mesmo
    // formato de modeloPedidos em Salao.qml.
    property var itensMesa: []
    // ListModel de divisões de PopupFecharConta.qml: cada item tem
    // {nome, valor, formaPagamento, status, trocoRecebido}.
    property var divisoes: null
    property real valorTotal: 0

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
        for (var i = 0; i < itensMesa.length; i++) {
            if (itensMesa[i].pedido !== "")
                n++;

        }
        return n;
    }

    width: 280
    implicitHeight: colunaResumoFechamento.implicitHeight + Estilo.preenchimento.grande * 2
    radius: Estilo.rounding.painel
    color: "#ffffff"
    border.color: Estilo.cores.bordaCard
    border.width: 1

    Column {
        id: colunaResumoFechamento

        width: parent.width - Estilo.preenchimento.grande * 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Estilo.preenchimento.grande
        spacing: Estilo.espacamento.normal

        Row {
            spacing: 8

            Icone {
                nome: "fa6s.receipt"
                cor: "#0d9488"
                tamanho: 18
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "RESUMO DO FECHAMENTO"
                font.pixelSize: 14
                font.bold: true
                color: "#0d9488"
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.WordWrap
                width: colunaResumoFechamento.width - 26
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Estilo.cores.bordaCard
        }

        // --- Itens do pedido da mesa ---
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
                model: root.itensMesa

                delegate: Item {
                    width: colunaResumoFechamento.width
                    height: visible ? Math.max(textoNomeItemFechamento.implicitHeight, textoValorItemFechamento.implicitHeight) : 0
                    visible: modelData.pedido !== ""

                    Text {
                        id: textoNomeItemFechamento

                        anchors.left: parent.left
                        anchors.right: textoValorItemFechamento.left
                        anchors.rightMargin: 8
                        text: "• " + modelData.pedido
                        font.pixelSize: 13
                        color: Estilo.cores.texto
                        elide: Text.ElideRight
                    }

                    Text {
                        id: textoValorItemFechamento

                        anchors.right: parent.right
                        text: modelData.valor || "R$ 0,00"
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

        // --- Divisão da conta (uma linha por pessoa) ---
        Text {
            text: "DIVISÃO DA CONTA"
            font.pixelSize: 12
            font.bold: true
            color: Estilo.cores.textoSecundario
        }

        Column {
            width: parent.width
            spacing: 10

            Repeater {
                model: root.divisoes

                delegate: Column {
                    width: colunaResumoFechamento.width
                    spacing: 2

                    Item {
                        width: parent.width
                        height: Math.max(textoNomeDivisaoResumo.implicitHeight, chipStatusResumo.height)

                        Text {
                            id: textoNomeDivisaoResumo

                            anchors.left: parent.left
                            anchors.right: chipStatusResumo.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: model.nome
                            font.pixelSize: 13
                            font.bold: true
                            color: Estilo.cores.texto
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: chipStatusResumo

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: textoStatusResumo.implicitWidth + 16
                            height: textoStatusResumo.implicitHeight + 6
                            radius: Estilo.rounding.cheio
                            color: model.status === "PG" ? Estilo.confirmar.normal : Estilo.cancelar.normal

                            Text {
                                id: textoStatusResumo

                                anchors.centerIn: parent
                                text: model.status === "PG" ? "PAGO" : "NÃO PAGO"
                                font.pixelSize: 10
                                font.bold: true
                                color: "#ffffff"
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: textoValorFormaResumo.implicitHeight

                        Text {
                            id: textoValorFormaResumo

                            anchors.left: parent.left
                            text: model.formaPagamento
                            font.pixelSize: 12
                            color: Estilo.cores.textoSecundario
                        }

                        Text {
                            anchors.right: parent.right
                            text: model.valor
                            font.pixelSize: 13
                            font.bold: true
                            color: Estilo.cores.texto
                        }
                    }

                    Text {
                        readonly property real recebido: root._valorNumero(model.trocoRecebido)
                        readonly property real valorPessoa: root._valorNumero(model.valor)

                        width: parent.width
                        visible: model.formaPagamento === "Dinheiro" && !!model.trocoRecebido
                        text: "Troco a dar: " + root._formatarMoeda(Math.max(recebido - valorPessoa, 0))
                        font.pixelSize: 11
                        font.italic: true
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

        // --- Total ---
        Item {
            width: parent.width
            height: textoTotalLabelFechamento.implicitHeight

            Text {
                id: textoTotalLabelFechamento

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "TOTAL"
                font.pixelSize: 16
                font.bold: true
                color: "#0d9488"
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root._formatarMoeda(root.valorTotal)
                font.pixelSize: 18
                font.bold: true
                color: "#0d9488"
            }
        }
    }
}
