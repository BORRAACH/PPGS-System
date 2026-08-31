import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"
import "../../components/Texto.js" as Texto

// Lançamento (ou edição de um lançamento) de pagamento de diária a um
// funcionário — dinheiro que sai do caixa fora de qualquer venda (ver
// services/rede/extrasCaixa.py e FechamentoController.registrarExtraDiaria/
// editarExtraDiaria). Aberto pelo botão "Extras" em Fechamento.qml (novo
// lançamento, sempre sobre telaFechamento.dataSelecionada) ou pelo lápis ao
// lado de um pagamento já lançado (edição, ver abrirParaEditar).
//
// Três estágios dentro do mesmo popup, trocados por propriedades booleanas
// mutuamente exclusivas — mesma técnica de "escolhendoBaixa" em
// PopupFechamentoRapido.qml: são escolhas curtas, e empilhar modal sobre
// modal só acrescentaria uma camada pra fechar.
// - Formulário: nome do funcionário + valor, Confirmar/Cancelar (e, editando
//   um lançamento já existente, Excluir).
// - Confirmar exclusão: só quando editando — "tem certeza?" antes de
//   apagar de vez.
// - Pergunta de impressão: depois que o lançamento já foi gravado/editado
//   (e o caixa do dia já recalculado), pergunta se imprime o recibo.
Popup {
    id: popupExtras

    property string dataIso: ""
    property var registroAtual: ({})
    property bool confirmando: false
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
    // registrarExtraDiaria/editarExtraDiaria/excluirExtraDiaria).
    // calcularFechamento não avisa esta própria máquina sozinho (só emite
    // fechamentoAtualizado para mudanças aprendidas de outra máquina, ver
    // FechamentoController._recalcular_e_cachear) — mesmo motivo de
    // PopupFechamentoRapido.concluido, que Fechamento.qml também escuta.
    signal concluido

    function abrirPara(iso) {
        popupExtras.dataIso = iso;
        popupExtras.idEdicao = "";
        popupExtras.registroAtual = ({});
        popupExtras.registroEditando = ({});
        popupExtras.confirmando = false;
        popupExtras.confirmandoExclusao = false;
        inputNome.text = "";
        inputValor.text = "";
        open();
    }

    // Corrige um lançamento já existente — `registro` é um item de
    // telaFechamento._extras.itens (tem "id", "funcionario", "valor",
    // "dataIso"). A dataHora original não é editável aqui (ver
    // extrasCaixa.editar): a correção é de nome/valor, não de quando o
    // dinheiro foi entregue.
    function abrirParaEditar(registro) {
        popupExtras.dataIso = registro.dataIso;
        popupExtras.idEdicao = registro.id;
        popupExtras.registroAtual = ({});
        popupExtras.registroEditando = registro;
        popupExtras.confirmando = false;
        popupExtras.confirmandoExclusao = false;
        inputNome.text = registro.funcionario;
        inputValor.text = Number(registro.valor || 0).toFixed(2).replace(".", ",");
        open();
    }

    function _confirmar() {
        var registro = popupExtras.idEdicao !== ""
            ? fechamentoController.editarExtraDiaria(popupExtras.idEdicao, inputNome.text, inputValor.text)
            : fechamentoController.registrarExtraDiaria(popupExtras.dataIso, inputNome.text, inputValor.text);
        if (!registro || !registro.id) {
            filaNotificacoesExtras.notificar("Preencha o nome do funcionário e um valor válido.", false);
            return;
        }

        popupExtras.registroAtual = registro;
        popupExtras.confirmando = true;
        popupExtras.concluido();
    }

    function _imprimirRecibo() {
        fechamentoController.imprimirReciboExtra(popupExtras.registroAtual);
        popupExtras.close();
    }

    function _excluir() {
        var ok = fechamentoController.excluirExtraDiaria(popupExtras.idEdicao);
        if (!ok) {
            filaNotificacoesExtras.notificar("Não foi possível excluir — o lançamento pode já ter sido removido.", false);
            popupExtras.confirmandoExclusao = false;
            return;
        }

        popupExtras.concluido();
        popupExtras.close();
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    onOpened: inputNome.forceActiveFocus()

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
                    if (popupExtras.confirmando)
                        return "Imprimir recibo?";
                    if (popupExtras.confirmandoExclusao)
                        return "Excluir pagamento?";
                    return popupExtras.idEdicao !== "" ? "Editar pagamento de diária" : "Pagamento de diária";
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
            visible: !popupExtras.confirmando && !popupExtras.confirmandoExclusao
            spacing: Estilo.global.spacing.lg

            Column {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "Nome do funcionário"
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                TextField {
                    id: inputNome

                    width: parent.width
                    color: Estilo.global.textInput
                    placeholderTextColor: Estilo.global.textPlaceholder
                    placeholderText: "NOME DO FUNCIONÁRIO"
                    // Mesma capitalização dos campos de nome de cliente do
                    // Balcão e da Entrega, e pelo mesmo motivo: em
                    // onTextChanged, não em onEditingFinished, para o nome já
                    // sair formatado enquanto se digita e para o que vem
                    // preenchido ao EDITAR um pagamento antigo entrar na regra
                    // também. O campo passa a ter uma invariante simples — o
                    // que está nele está sempre capitalizado —, que é o que faz
                    // o recibo impresso nunca discordar da tela.
                    onTextChanged: Texto.capitalizarCampo(inputNome)
                    topPadding: 10
                    bottomPadding: 10
                    leftPadding: 10
                    rightPadding: 10
                    KeyNavigation.tab: inputValor
                    Keys.onReturnPressed: inputValor.forceActiveFocus()

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: Estilo.global.inputBackground
                        border.color: inputNome.activeFocus ? Estilo.finance.outflow : Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "Valor pago"
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                TextField {
                    id: inputValor

                    width: parent.width
                    color: Estilo.global.textInput
                    placeholderTextColor: Estilo.global.textPlaceholder
                    placeholderText: "VALOR"
                    topPadding: 10
                    bottomPadding: 10
                    leftPadding: 10
                    rightPadding: 10
                    validator: Moeda.validador
                    Keys.onReturnPressed: popupExtras._confirmar()

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: Estilo.global.inputBackground
                        border.color: inputValor.activeFocus ? Estilo.finance.outflow : Estilo.global.border
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
                    id: btnConfirmarExtra

                    Layout.fillWidth: true
                    padding: Estilo.global.padding.md
                    enabled: inputNome.text.trim() !== "" && parseFloat((inputValor.text || "0").replace(",", ".")) > 0
                    onClicked: popupExtras._confirmar()

                    contentItem: Text {
                        text: "Confirmar"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        opacity: btnConfirmarExtra.enabled ? 1 : Estilo.global.opacity.disabled
                        color: btnConfirmarExtra.down ? Estilo.action.confirm.pressed : (btnConfirmarExtra.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                        border.color: Estilo.action.confirm.pressed
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }


                Button {
                    id: btnCancelarExtra

                    Layout.fillWidth: true
                    padding: Estilo.global.padding.md
                    onClicked: popupExtras.close()

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

                    visible: popupExtras.idEdicao !== ""
                    Layout.fillWidth: true
                    padding: Estilo.global.padding.md
                    onClicked: popupExtras.confirmandoExclusao = true

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
            visible: popupExtras.confirmandoExclusao
            spacing: Estilo.global.spacing.lg

            Text {
                Layout.fillWidth: true
                text: "Excluir o pagamento de " + (popupExtras.registroEditando.funcionario || "") + " no valor de R$ "
                    + Number(popupExtras.registroEditando.valor || 0).toFixed(2).replace(".", ",")
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
                    onClicked: popupExtras.confirmandoExclusao = false

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
                    onClicked: popupExtras._excluir()

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

        // --- PERGUNTA DE IMPRESSÃO ---
        ColumnLayout {
            Layout.fillWidth: true
            visible: popupExtras.confirmando
            spacing: Estilo.global.spacing.lg

            Text {
                Layout.fillWidth: true
                text: "Pagamento de " + (popupExtras.registroAtual.funcionario || "") + " no valor de R$ "
                    + Number(popupExtras.registroAtual.valor || 0).toFixed(2).replace(".", ",")
                    + " salvo. Deseja imprimir o recibo?"
                wrapMode: Text.WordWrap
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.text
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Estilo.global.spacing.lg
                spacing: Estilo.global.spacing.lg

                Button {
                    id: btnNaoImprimirExtra

                    Layout.fillWidth: true
                    padding: Estilo.global.padding.md
                    onClicked: popupExtras.close()

                    contentItem: Text {
                        text: "Não"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textSecondary
                        horizontalAlignment: Text.AlignHCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnNaoImprimirExtra.down ? Estilo.action.ghost.pressed : (btnNaoImprimirExtra.hovered ? Estilo.action.ghost.hover : Estilo.action.ghost.base)
                        border.color: Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }

                Button {
                    id: btnSimImprimirExtra

                    Layout.fillWidth: true
                    padding: Estilo.global.padding.md
                    onClicked: popupExtras._imprimirRecibo()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.print"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Sim, imprimir"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnSimImprimirExtra.down ? Estilo.action.confirm.pressed : (btnSimImprimirExtra.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                        border.color: Estilo.action.confirm.pressed
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }
            }
        }
    }

    FilaNotificacoes {
        id: filaNotificacoesExtras
    }
}
