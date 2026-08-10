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

    // Largura padrão do painel; quem o usa dentro de um Layout (ver
    // PopupFecharConta.qml) manda a largura por Layout.preferredWidth, e aí
    // esta linha sai de cena sozinha.
    width: 280
    implicitHeight: colunaResumoFechamento.implicitHeight + Estilo.global.padding.xl * 2
    radius: Estilo.global.radius.lg
    color: Estilo.global.surface
    border.color: Estilo.global.borderCard
    border.width: Estilo.global.borderWidth.hairline

    Column {
        id: colunaResumoFechamento

        width: parent.width - Estilo.global.padding.xl * 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Estilo.global.padding.xl
        spacing: Estilo.global.spacing.lg

        Row {
            spacing: Estilo.global.spacing.sm

            Icone {
                nome: "fa6s.receipt"
                cor: Estilo.screen.salao.accent
                tamanho: 18
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "RESUMO DO FECHAMENTO"
                font.pixelSize: Estilo.global.fontSize.lg
                font.bold: true
                color: Estilo.screen.salao.accent
                anchors.verticalCenter: parent.verticalCenter
                wrapMode: Text.WordWrap
                width: colunaResumoFechamento.width - 26
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Estilo.global.borderCard
        }

        // --- Itens do pedido da mesa ---
        Text {
            width: parent.width
            visible: root.quantidadeItens === 0
            text: "Nenhum item adicionado ainda."
            font.pixelSize: Estilo.global.fontSize.md
            font.italic: true
            color: Estilo.global.textSecondary
            wrapMode: Text.WordWrap
        }

        Column {
            width: parent.width
            spacing: Estilo.global.spacing.xs
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
                        font.pixelSize: Estilo.global.fontSize.md
                        color: Estilo.global.text
                        elide: Text.ElideRight
                    }

                    Text {
                        id: textoValorItemFechamento

                        anchors.right: parent.right
                        text: modelData.valor || "R$ 0,00"
                        font.pixelSize: Estilo.global.fontSize.md
                        color: Estilo.global.textSecondary
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Estilo.global.borderCard
        }

        // --- Divisão da conta (uma linha por pessoa) ---
        Text {
            text: "DIVISÃO DA CONTA"
            font.pixelSize: Estilo.global.fontSize.sm
            font.bold: true
            color: Estilo.global.textSecondary
        }

        Column {
            width: parent.width
            spacing: Estilo.global.spacing.md

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
                            font.pixelSize: Estilo.global.fontSize.md
                            font.bold: true
                            color: Estilo.global.text
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: chipStatusResumo

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: textoStatusResumo.implicitWidth + 16
                            height: textoStatusResumo.implicitHeight + 6
                            radius: Estilo.global.radius.pill
                            color: model.status === "PG" ? Estilo.action.confirm.base : Estilo.action.danger.base

                            Text {
                                id: textoStatusResumo

                                anchors.centerIn: parent
                                text: model.status === "PG" ? "PAGO" : "NÃO PAGO"
                                font.pixelSize: Estilo.global.fontSize.xs
                                font.bold: true
                                color: Estilo.global.textOnAccent
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
                            font.pixelSize: Estilo.global.fontSize.sm
                            color: Estilo.global.textSecondary
                        }

                        Text {
                            anchors.right: parent.right
                            text: model.valor
                            font.pixelSize: Estilo.global.fontSize.md
                            font.bold: true
                            color: Estilo.global.text
                        }
                    }

                    Text {
                        readonly property real recebido: root._valorNumero(model.trocoRecebido)
                        readonly property real valorPessoa: root._valorNumero(model.valor)

                        width: parent.width
                        visible: model.formaPagamento === "Dinheiro" && !!model.trocoRecebido
                        text: "Troco a dar: " + root._formatarMoeda(Math.max(recebido - valorPessoa, 0))
                        font.pixelSize: Estilo.global.fontSize.xs
                        font.italic: true
                        color: Estilo.global.textSecondary
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Estilo.global.borderCard
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
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.screen.salao.accent
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root._formatarMoeda(root.valorTotal)
                font.pixelSize: Estilo.global.fontSize.xxl
                font.bold: true
                color: Estilo.screen.salao.accent
            }
        }
    }
}
