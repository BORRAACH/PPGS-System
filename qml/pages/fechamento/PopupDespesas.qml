import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

// Lançamento (ou edição) de uma DESPESA do dia — conta do negócio paga com
// dinheiro do caixa: gás, embalagem, insumo comprado na hora. Aberto pelo
// botão "Despesas" em Fechamento.qml, ao lado do de Extras.
//
// Decalque de PopupExtras.qml, e as duas telas são quase idênticas de
// propósito: quem já sabe lançar uma diária sabe lançar uma despesa. O que
// muda é o destino do valor — ver o comentário de totalContagem em
// Fechamento.qml e o topo de services/rede/despesasCaixa.py.
//
// Sem a pergunta de impressão que o popup de extras tem no fim: recibo é
// coisa de pagamento a pessoa, e uma despesa já vem com a nota de quem
// vendeu.
Popup {
    id: popupDespesas

    property string dataIso: ""
    property var registroAtual: ({})
    property bool confirmandoExclusao: false
    // "" = lançando um pagamento novo; preenchido (id do lançamento) =
    // corrigindo nome/valor de um já existente (ver abrirParaEditar).
    property string idEdicao: ""
    // Registro tal como veio de abrirParaEditar — usado no texto de
    // confirmação de exclusão (independe do que o usuário já tenha digitado
    // nos campos, sem confirmar).
    property var registroEditando: ({})

    // Emitido assim que o lançamento é gravado/editado/apagado
    // (fechamentoController já recalculou e salvou o dia — ver
    // registrarDespesa/editarDespesa/excluirDespesa).
    // calcularFechamento não avisa esta própria máquina sozinho (só emite
    // fechamentoAtualizado para mudanças aprendidas de outra máquina, ver
    // FechamentoController._recalcular_e_cachear) — mesmo motivo de
    // PopupFechamentoRapido.concluido, que Fechamento.qml também escuta.
    signal concluido

    function abrirPara(iso) {
        popupDespesas.dataIso = iso;
        popupDespesas.idEdicao = "";
        popupDespesas.registroAtual = ({});
        popupDespesas.registroEditando = ({});
        popupDespesas.confirmandoExclusao = false;
        inputNomeDespesa.text = "";
        inputValorDespesa.text = "";
        open();
    }

    // Corrige um lançamento já existente — `registro` é um item de
    // telaFechamento._extras.itens (tem "id", "funcionario", "valor",
    // "dataIso"). A dataHora original não é editável aqui (ver
    // extrasCaixa.editar): a correção é de nome/valor, não de quando o
    // dinheiro foi entregue.
    function abrirParaEditar(registro) {
        popupDespesas.dataIso = registro.dataIso;
        popupDespesas.idEdicao = registro.id;
        popupDespesas.registroAtual = ({});
        popupDespesas.registroEditando = registro;
        popupDespesas.confirmandoExclusao = false;
        inputNomeDespesa.text = registro.nome;
        inputValorDespesa.text = Number(registro.valor || 0).toFixed(2).replace(".", ",");
        open();
    }

    function _confirmar() {
        var registro = popupDespesas.idEdicao !== ""
            ? fechamentoController.editarDespesa(popupDespesas.idEdicao, inputNomeDespesa.text, inputValorDespesa.text)
            : fechamentoController.registrarDespesa(popupDespesas.dataIso, inputNomeDespesa.text, inputValorDespesa.text);
        if (!registro || !registro.id) {
            filaNotificacoesDespesas.notificar("Preencha a descrição e um valor válido.", false);
            return;
        }

        popupDespesas.registroAtual = registro;
        popupDespesas.concluido();
        popupDespesas.close();
    }

    function _excluir() {
        var ok = fechamentoController.excluirDespesa(popupDespesas.idEdicao);
        if (!ok) {
            filaNotificacoesDespesas.notificar("Não foi possível excluir — o lançamento pode já ter sido removido.", false);
            popupDespesas.confirmandoExclusao = false;
            return;
        }

        popupDespesas.concluido();
        popupDespesas.close();
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    onOpened: inputNomeDespesa.forceActiveFocus()

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
            Icone { nome: "fa6s.hand-holding-dollar"; cor: Estilo.finance.outflow; tamanho: Estilo.global.fontSize.title; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: {
                    if (popupDespesas.confirmandoExclusao)
                        return "Excluir despesa?";
                    return popupDespesas.idEdicao !== "" ? "Editar despesa" : "Despesa";
                }
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // --- FORMULÁRIO ---
        ColumnLayout {
            Layout.fillWidth: true
            visible: !popupDespesas.confirmandoExclusao
            spacing: Estilo.global.spacing.lg

            Column {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "Descrição da despesa"
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                TextField {
                    id: inputNomeDespesa

                    width: parent.width
                    color: Estilo.global.textInput
                    placeholderTextColor: Estilo.global.textPlaceholder
                    placeholderText: "EX: GÁS, EMBALAGEM"
                    topPadding: 10
                    bottomPadding: 10
                    leftPadding: 10
                    rightPadding: 10
                    KeyNavigation.tab: inputValorDespesa
                    Keys.onReturnPressed: inputValorDespesa.forceActiveFocus()

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: Estilo.global.inputBackground
                        border.color: inputNomeDespesa.activeFocus ? Estilo.finance.outflow : Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "Valor da despesa"
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                TextField {
                    id: inputValorDespesa

                    width: parent.width
                    color: Estilo.global.textInput
                    placeholderTextColor: Estilo.global.textPlaceholder
                    placeholderText: "VALOR"
                    topPadding: 10
                    bottomPadding: 10
                    leftPadding: 10
                    rightPadding: 10
                    validator: Moeda.validador
                    Keys.onReturnPressed: popupDespesas._confirmar()

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: Estilo.global.inputBackground
                        border.color: inputValorDespesa.activeFocus ? Estilo.finance.outflow : Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Estilo.global.spacing.lg
                spacing: Estilo.global.spacing.lg

                // Só existe corrigindo um lançamento já existente — um
                // pagamento novo ainda não tem o que excluir.

Button {
                    id: btnConfirmarDespesa

                    Layout.fillWidth: true
                    padding: Estilo.global.padding.md
                    enabled: inputNomeDespesa.text.trim() !== "" && parseFloat((inputValorDespesa.text || "0").replace(",", ".")) > 0
                    onClicked: popupDespesas._confirmar()

                    contentItem: Text {
                        text: "Confirmar"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        opacity: btnConfirmarDespesa.enabled ? 1 : Estilo.global.opacity.disabled
                        color: btnConfirmarDespesa.down ? Estilo.action.confirm.pressed : (btnConfirmarDespesa.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                        border.color: Estilo.action.confirm.pressed
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }


                Button {
                    id: btnCancelarExtra

                    Layout.fillWidth: true
                    padding: Estilo.global.padding.md
                    onClicked: popupDespesas.close()

                    contentItem: Text {
                        text: "Cancelar"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnCancelarExtra.down ? Estilo.action.danger.pressed : (btnCancelarExtra.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                        border.color: Estilo.action.danger.pressed
                        border.width: Estilo.global.borderWidth.hairline
                    }
                  }

                  Button {
                    id: btnExcluirExtra

                    visible: popupDespesas.idEdicao !== ""
                    Layout.fillWidth: true
                    padding: Estilo.global.padding.md
                    onClicked: popupDespesas.confirmandoExclusao = true

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.trash-can"; cor: Estilo.action.danger.base; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Excluir"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.action.danger.base
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnExcluirExtra.down ? Estilo.status.error.border : (btnExcluirExtra.hovered ? Estilo.status.error.background : "transparent")
                        border.color: Estilo.action.danger.base
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }


                            }
        }

        // --- CONFIRMAR EXCLUSÃO ---
        ColumnLayout {
            Layout.fillWidth: true
            visible: popupDespesas.confirmandoExclusao
            spacing: Estilo.global.spacing.lg

            Text {
                Layout.fillWidth: true
                text: "Excluir o pagamento de " + (popupDespesas.registroEditando.funcionario || "") + " no valor de R$ "
                    + Number(popupDespesas.registroEditando.valor || 0).toFixed(2).replace(".", ",")
                    + "? Esta ação não pode ser desfeita."
                wrapMode: Text.WordWrap
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.text
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Estilo.global.spacing.lg
                spacing: Estilo.global.spacing.lg

                Button {
                    id: btnCancelarExclusaoExtra

                    Layout.fillWidth: true
                    padding: Estilo.global.padding.md
                    onClicked: popupDespesas.confirmandoExclusao = false

                    contentItem: Text {
                        text: "Cancelar"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textSecondary
                        horizontalAlignment: Text.AlignHCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnCancelarExclusaoExtra.down ? Estilo.action.ghost.pressed : (btnCancelarExclusaoExtra.hovered ? Estilo.action.ghost.hover : Estilo.action.ghost.base)
                        border.color: Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }

                Button {
                    id: btnConfirmarExclusaoExtra

                    Layout.fillWidth: true
                    padding: Estilo.global.padding.md
                    onClicked: popupDespesas._excluir()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.trash-can"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Excluir"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnConfirmarExclusaoExtra.down ? Estilo.action.danger.pressed : (btnConfirmarExclusaoExtra.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                        border.color: Estilo.action.danger.pressed
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }
            }
        }

    }

    // Fora do contentItem: FilaNotificacoes se ancora ao pai (anchors.fill),
    // e declarada solta aqui ela viraria filha do ColumnLayout do conteúdo —
    // ancorar dentro de um layout é comportamento indefinido no Qt. O overlay
    // é onde uma fila de avisos deve viver de qualquer forma: ela flutua
    // sobre a tela, não ocupa uma linha do formulário.
    FilaNotificacoes {
        id: filaNotificacoesDespesas

        parent: Overlay.overlay
    }
}
