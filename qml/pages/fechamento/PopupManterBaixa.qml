import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

// O que fazer com a conferência ao corrigir uma comanda que já recebeu baixa
// — aberto por PopupFechamentoRapido.editarAtual(), logo depois de o código
// do usuário ser autorizado.
//
// Corrigir é apagar e gravar de novo, e a comanda nova nasce sem baixa (ver
// services/rede/baixaComandas.py) — ou seja, some do caixa do dia até alguém
// reconferir. Isso é o certo quando a baixa foi dada por engano, e é
// justamente o errado quando a correção é só um valor digitado torto. Como as
// duas intenções são indistinguíveis daqui, quem decide é quem está
// corrigindo.
//
// Já foi uma faixa dentro do próprio PopupFechamentoRapido, com o argumento
// de que empilhar modal sobre modal só acrescentaria uma camada pra fechar.
// Virou popup a pedido, e o argumento antigo perdeu força no caminho: a
// escolha agora chega logo depois do popup de autorização, então a pilha de
// modais já existe de qualquer forma — e uma pergunta que muda o caixa do dia
// pedindo resposta numa faixa embaixo do cupom era fácil demais de não ver.
Popup {
    id: popupManterBaixa

    // Nomeado pelo mesmo motivo de PopupAutorizacao: deixa o popup
    // alcançável de fora para inspeção e teste.
    objectName: "popupManterBaixa"

    // `manterBaixa` é o que segue para EdicaoComanda.abrir. Cancelar não
    // emite nada: some o popup e a comanda fica como estava.
    signal escolhido(bool manterBaixa)

    function _escolher(manterBaixa) {
        // Fecha antes de emitir: quem escuta empurra o formulário de edição na
        // pilha de telas, e deixar este popup aberto por baixo faria ele
        // reaparecer por cima do formulário — mesmo cuidado documentado em
        // PopupFechamentoRapido._abrirEdicao.
        popupManterBaixa.close();
        popupManterBaixa.escolhido(manterBaixa);
    }

    modal: true
    focus: true
    // Sem CloseOnPressOutside: é uma pergunta que muda o caixa do dia, e
    // fechar sem querer com um clique fora não é uma resposta.
    closePolicy: Popup.CloseOnEscape
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent

    width: Math.min(440, parent ? parent.width * 0.9 : 440)

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    contentItem: ColumnLayout {
        spacing: Estilo.global.spacing.xl

        Row {
            spacing: Estilo.global.spacing.sm

            Icone {
                nome: "fa6s.circle-question"
                cor: Estilo.status.warning.content
                tamanho: Estilo.global.fontSize.title
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Comanda já conferida"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Esta comanda já foi conferida e conta no caixa do dia. A comanda corrigida é gravada como uma comanda nova — o que fazer com a conferência?"
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            wrapMode: Text.WordWrap
        }

        Button {
            id: btnManterConferida

            Layout.fillWidth: true
            padding: Estilo.global.padding.md
            onClicked: popupManterBaixa._escolher(true)

            contentItem: ColumnLayout {
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: "Manter conferida"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: "a correção continua no caixa de hoje"
                    font.pixelSize: Estilo.global.fontSize.xs
                    color: Estilo.global.textOnAccent
                    opacity: 0.85
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: btnManterConferida.down ? Estilo.action.confirm.pressed : (btnManterConferida.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
            }
        }

        Button {
            id: btnReconferirDepois

            Layout.fillWidth: true
            padding: Estilo.global.padding.md
            onClicked: popupManterBaixa._escolher(false)

            contentItem: ColumnLayout {
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: "Reconferir depois"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.status.warning.content
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.fillWidth: true
                    text: "sai do caixa até alguém conferir de novo"
                    font.pixelSize: Estilo.global.fontSize.xs
                    color: Estilo.status.warning.content
                    opacity: 0.85
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: btnReconferirDepois.down ? Estilo.status.warning.border : (btnReconferirDepois.hovered ? Estilo.status.warning.background : "transparent")
                border.color: Estilo.status.warning.border
                border.width: Estilo.global.borderWidth.hairline
            }
        }

        Button {
            id: btnCancelarEscolha

            Layout.fillWidth: true
            padding: Estilo.global.padding.md
            onClicked: popupManterBaixa.close()

            contentItem: Text {
                text: "Cancelar"
                font.family: Estilo.global.fontFamily.title
                color: Estilo.global.textSecondary
                horizontalAlignment: Text.AlignHCenter
            }

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: btnCancelarEscolha.hovered ? Estilo.action.ghost.hover : Estilo.action.ghost.base
            }
        }
    }
}
