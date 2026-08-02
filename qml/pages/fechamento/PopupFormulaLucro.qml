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
    padding: 25
    parent: Overlay.overlay
    anchors.centerIn: parent

    width: Math.min(420, parent ? parent.width * 0.9 : 420)

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        radius: Estilo.rounding.popup
        color: Estilo.cores.fundoPagina
        border.color: Estilo.cores.bordaCard
    }

    contentItem: ColumnLayout {
        spacing: Estilo.espacamento.maior

        Row {
            spacing: 8
            Icone { nome: "fa6s.gear"; cor: "#0d9488"; tamanho: Estilo.fonte.titulo; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "Fórmula do lucro"
                font.pixelSize: 17
                font.bold: true
                color: Estilo.cores.texto
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            Layout.fillWidth: true
            text: "Lucro = soma dos três termos abaixo, cada um com o sinal escolhido."
            font.pixelSize: 12
            color: Estilo.cores.textoSecundario
            wrapMode: Text.WordWrap
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 10

            Text {
                text: "Contagem (Cartão+Dinheiro+Pix)"
                font.pixelSize: 13
                color: Estilo.cores.texto
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
                font.pixelSize: 13
                color: Estilo.cores.texto
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
                font.pixelSize: 13
                color: Estilo.cores.texto
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
            Layout.topMargin: Estilo.espacamento.normal
            spacing: Estilo.espacamento.normal

            Button {
                id: btnCancelarFormula

                Layout.fillWidth: true
                padding: 10
                onClicked: popupFormulaLucro.close()

                contentItem: Text {
                    text: "Cancelar"
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: btnCancelarFormula.down ? Estilo.cancelar.pressionado : (btnCancelarFormula.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                    border.color: Estilo.cancelar.pressionado
                    border.width: 1
                }
            }

            Button {
                id: btnConfirmarFormula

                Layout.fillWidth: true
                padding: 10
                onClicked: popupFormulaLucro._confirmar()

                contentItem: Text {
                    text: "Confirmar"
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: btnConfirmarFormula.down ? Estilo.confirmar.pressionado : (btnConfirmarFormula.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                    border.color: Estilo.confirmar.pressionado
                    border.width: 1
                }
            }
        }
    }
}
