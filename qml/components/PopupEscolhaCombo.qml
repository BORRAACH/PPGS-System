import QtQuick
import QtQuick.Controls
import estilo 1.0

// Escolha manual do combo quando mais de um rende desconto no mesmo pedido
// (ver services/combosService.calcular: "conflito"). Com um único combo
// aplicável o desconto é automático e este popup nunca abre.
//
// Só devolve a decisão em `escolhido(id)` — quem guarda a escolha e recalcula
// é o ResumoComanda, que é quem conhece o pedido.
Popup {
    id: root

    // [{id, nome, desconto, grupos}, ...] como vem de calcularCombos().conflito
    property var opcoes: []

    // id do combo, ou "nenhum" (valor de combosService.SEM_COMBO) para vender
    // tudo a preço cheio.
    signal escolhido(string id)

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
        border.width: Estilo.global.borderWidth.hairline
    }

    contentItem: Column {
        spacing: Estilo.global.spacing.xl

        Row {
            spacing: Estilo.global.spacing.sm

            Icone {
                nome: "fa6s.tags"
                cor: Estilo.global.text
                tamanho: 17
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Escolha o combo"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: "Mais de um combo vale para este pedido. Qual deve ser aplicado?"
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            width: 360
            wrapMode: Text.Wrap
        }

        Repeater {
            model: root.opcoes

            delegate: Botao {
                required property var modelData

                width: 360
                variante: "secundario"
                text: modelData.nome + "  ·  −R$ " + Number(modelData.desconto).toFixed(2).replace(".", ",")
                onClicked: {
                    root.close();
                    root.escolhido(modelData.id);
                }
            }
        }

        Botao {
            width: 360
            variante: "ghost"
            tom: Estilo.action.neutral
            text: "Nenhum — cobrar preço cheio"
            onClicked: {
                root.close();
                root.escolhido("nenhum");
            }
        }
    }
}
