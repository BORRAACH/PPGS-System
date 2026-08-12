import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

// Muda a lógica de cálculo do "Lucro" (ver services/formulaLucroService.py)
// — três termos (Contagem, Extras, Bruto), cada um com um sinal (Somar /
// Subtrair / Não incluir). Configuração única da malha inteira, não por
// dia — mesmo raciocínio de EstiloImpressora.qml/Configurações.
Popup {
    id: popupFormulaLucro

    // Rótulo -> valor salvo em services/formulaLucroService.py — os
    // ComboBox trabalham com o índice da lista de rótulos, então a
    // conversão pro valor de verdade acontece só na hora de confirmar.
    readonly property var opcoesSinal: ["Somar", "Subtrair", "Não incluir"]
    readonly property var valoresSinal: ["somar", "subtrair", "nao_incluir"]

    signal concluido

    function _indiceSinal(sinal) {
        var indice = popupFormulaLucro.valoresSinal.indexOf(sinal);
        return indice >= 0 ? indice : 0;
    }

    function abrirCom(formula) {
        formula = formula || {};
        comboContagem.currentIndex = popupFormulaLucro._indiceSinal(formula.contagem);
        comboExtras.currentIndex = popupFormulaLucro._indiceSinal(formula.extras);
        comboBruto.currentIndex = popupFormulaLucro._indiceSinal(formula.bruto);
        open();
    }

    function _confirmar() {
        formulaLucroController.definirFormula(
            popupFormulaLucro.valoresSinal[comboContagem.currentIndex],
            popupFormulaLucro.valoresSinal[comboExtras.currentIndex],
            popupFormulaLucro.valoresSinal[comboBruto.currentIndex]
        );
        popupFormulaLucro.concluido();
        popupFormulaLucro.close();
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent

    width: Math.min(420, parent ? parent.width * 0.9 : 420)

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
            Icone { nome: "fa6s.gear"; cor: Estilo.screen.caixa.base; tamanho: Estilo.global.fontSize.title; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "Fórmula do lucro"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Lucro = soma dos três termos abaixo, cada um com o sinal escolhido."
            font.pixelSize: Estilo.global.fontSize.sm
            color: Estilo.global.textSecondary
            wrapMode: Text.WordWrap
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 10

            Text {
                text: "Contagem (Cartão+Dinheiro+Pix)"
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.text
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            ComboBox {
                id: comboContagem
                Layout.preferredWidth: 150
                model: popupFormulaLucro.opcoesSinal
            }

            Text {
                text: "Extras (diárias de funcionários)"
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.text
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            ComboBox {
                id: comboExtras
                Layout.preferredWidth: 150
                model: popupFormulaLucro.opcoesSinal
            }

            Text {
                text: "Vendas brutas (Total do dia)"
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.text
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
            ComboBox {
                id: comboBruto
                Layout.preferredWidth: 150
                model: popupFormulaLucro.opcoesSinal
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Estilo.global.spacing.lg
            spacing: Estilo.global.spacing.lg

            Button {
                id: btnCancelarFormula

                Layout.fillWidth: true
                padding: Estilo.global.padding.md
                onClicked: popupFormulaLucro.close()

                contentItem: Text {
                    text: "Cancelar"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnCancelarFormula.down ? Estilo.action.danger.pressed : (btnCancelarFormula.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                    border.color: Estilo.action.danger.pressed
                    border.width: Estilo.global.borderWidth.hairline
                }
            }

            Button {
                id: btnConfirmarFormula

                Layout.fillWidth: true
                padding: Estilo.global.padding.md
                onClicked: popupFormulaLucro._confirmar()

                contentItem: Text {
                    text: "Confirmar"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnConfirmarFormula.down ? Estilo.action.confirm.pressed : (btnConfirmarFormula.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                    border.color: Estilo.action.confirm.pressed
                    border.width: Estilo.global.borderWidth.hairline
                }
            }
        }
    }
}
