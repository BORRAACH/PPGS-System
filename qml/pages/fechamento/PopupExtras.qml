import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

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
    padding: 25
    parent: Overlay.overlay
    anchors.centerIn: parent
    onOpened: inputNome.forceActiveFocus()

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
            Icone { nome: "fa6s.hand-holding-dollar"; cor: "#b45309"; tamanho: Estilo.fonte.titulo; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: {
                    if (popupExtras.confirmando)
                        return "Imprimir recibo?";
                    if (popupExtras.confirmandoExclusao)
                        return "Excluir pagamento?";
                    return popupExtras.idEdicao !== "" ? "Editar pagamento de diária" : "Pagamento de diária";
                }
                font.pixelSize: 17
                font.bold: true
                color: Estilo.cores.texto
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // --- FORMULÁRIO ---
        ColumnLayout {
            Layout.fillWidth: true
            visible: !popupExtras.confirmando && !popupExtras.confirmandoExclusao
            spacing: Estilo.espacamento.normal

            Column {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "Nome do funcionário"
                    font.pixelSize: 12
                    font.bold: true
                    color: Estilo.cores.textoSecundario
                }

                TextField {
                    id: inputNome

                    width: parent.width
                    color: Estilo.cores.textoInput
                    placeholderTextColor: Estilo.cores.placeholderInput
                    placeholderText: "NOME DO FUNCIONÁRIO"
                    topPadding: 10
                    bottomPadding: 10
                    leftPadding: 10
                    rightPadding: 10
                    KeyNavigation.tab: inputValor
                    Keys.onReturnPressed: inputValor.forceActiveFocus()

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: "#ffffff"
                        border.color: inputNome.activeFocus ? "#b45309" : Estilo.cores.borda
                        border.width: 1
                    }
                }
            }

            Column {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "Valor pago"
                    font.pixelSize: 12
                    font.bold: true
                    color: Estilo.cores.textoSecundario
                }

                TextField {
                    id: inputValor

                    width: parent.width
                    color: Estilo.cores.textoInput
                    placeholderTextColor: Estilo.cores.placeholderInput
                    placeholderText: "VALOR"
                    topPadding: 10
                    bottomPadding: 10
                    leftPadding: 10
                    rightPadding: 10
                    validator: DoubleValidator {
                        bottom: 0
                        decimals: 2
                        notation: DoubleValidator.StandardNotation
                    }
                    Keys.onReturnPressed: popupExtras._confirmar()

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: "#ffffff"
                        border.color: inputValor.activeFocus ? "#b45309" : Estilo.cores.borda
                        border.width: 1
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Estilo.espacamento.normal
                spacing: Estilo.espacamento.normal

                // Só existe corrigindo um lançamento já existente — um
                // pagamento novo ainda não tem o que excluir.

Button {
                    id: btnConfirmarExtra

                    Layout.fillWidth: true
                    padding: 10
                    enabled: inputNome.text.trim() !== "" && parseFloat((inputValor.text || "0").replace(",", ".")) > 0
                    onClicked: popupExtras._confirmar()

                    contentItem: Text {
                        text: "Confirmar"
                        font.bold: true
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        opacity: btnConfirmarExtra.enabled ? 1 : 0.5
                        color: btnConfirmarExtra.down ? Estilo.confirmar.pressionado : (btnConfirmarExtra.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                        border.color: Estilo.confirmar.pressionado
                        border.width: 1
                    }
                }


                Button {
                    id: btnCancelarExtra

                    Layout.fillWidth: true
                    padding: 10
                    onClicked: popupExtras.close()

                    contentItem: Text {
                        text: "Cancelar"
                        font.bold: true
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: btnCancelarExtra.down ? Estilo.cancelar.pressionado : (btnCancelarExtra.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                        border.color: Estilo.cancelar.pressionado
                        border.width: 1
                    }
                  }

                  Button {
                    id: btnExcluirExtra

                    visible: popupExtras.idEdicao !== ""
                    Layout.fillWidth: true
                    padding: 10
                    onClicked: popupExtras.confirmandoExclusao = true

                    contentItem: Row {
                        spacing: 6
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.trash-can"; cor: Estilo.cancelar.normal; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Excluir"
                            font.bold: true
                            color: Estilo.cancelar.normal
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: btnExcluirExtra.down ? "#fecaca" : (btnExcluirExtra.hovered ? "#fee2e2" : "transparent")
                        border.color: Estilo.cancelar.normal
                        border.width: 1
                    }
                }


                            }
        }

        // --- CONFIRMAR EXCLUSÃO ---
        ColumnLayout {
            Layout.fillWidth: true
            visible: popupExtras.confirmandoExclusao
            spacing: Estilo.espacamento.normal

            Text {
                Layout.fillWidth: true
                text: "Excluir o pagamento de " + (popupExtras.registroEditando.funcionario || "") + " no valor de R$ "
                    + Number(popupExtras.registroEditando.valor || 0).toFixed(2).replace(".", ",")
                    + "? Esta ação não pode ser desfeita."
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                color: Estilo.cores.texto
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Estilo.espacamento.normal
                spacing: Estilo.espacamento.normal

                Button {
                    id: btnCancelarExclusaoExtra

                    Layout.fillWidth: true
                    padding: 10
                    onClicked: popupExtras.confirmandoExclusao = false

                    contentItem: Text {
                        text: "Cancelar"
                        font.bold: true
                        color: Estilo.cores.textoSecundario
                        horizontalAlignment: Text.AlignHCenter
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: btnCancelarExclusaoExtra.down ? "#e5e7eb" : (btnCancelarExclusaoExtra.hovered ? "#f1f5f9" : "transparent")
                        border.color: Estilo.cores.borda
                        border.width: 1
                    }
                }

                Button {
                    id: btnConfirmarExclusaoExtra

                    Layout.fillWidth: true
                    padding: 10
                    onClicked: popupExtras._excluir()

                    contentItem: Row {
                        spacing: 6
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.trash-can"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Excluir"
                            font.bold: true
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: btnConfirmarExclusaoExtra.down ? Estilo.cancelar.pressionado : (btnConfirmarExclusaoExtra.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                        border.color: Estilo.cancelar.pressionado
                        border.width: 1
                    }
                }
            }
        }

        // --- PERGUNTA DE IMPRESSÃO ---
        ColumnLayout {
            Layout.fillWidth: true
            visible: popupExtras.confirmando
            spacing: Estilo.espacamento.normal

            Text {
                Layout.fillWidth: true
                text: "Pagamento de " + (popupExtras.registroAtual.funcionario || "") + " no valor de R$ "
                    + Number(popupExtras.registroAtual.valor || 0).toFixed(2).replace(".", ",")
                    + " salvo. Deseja imprimir o recibo?"
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                color: Estilo.cores.texto
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Estilo.espacamento.normal
                spacing: Estilo.espacamento.normal

                Button {
                    id: btnNaoImprimirExtra

                    Layout.fillWidth: true
                    padding: 10
                    onClicked: popupExtras.close()

                    contentItem: Text {
                        text: "Não"
                        font.bold: true
                        color: Estilo.cores.textoSecundario
                        horizontalAlignment: Text.AlignHCenter
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: btnNaoImprimirExtra.down ? "#e5e7eb" : (btnNaoImprimirExtra.hovered ? "#f1f5f9" : "transparent")
                        border.color: Estilo.cores.borda
                        border.width: 1
                    }
                }

                Button {
                    id: btnSimImprimirExtra

                    Layout.fillWidth: true
                    padding: 10
                    onClicked: popupExtras._imprimirRecibo()

                    contentItem: Row {
                        spacing: 6
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.print"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Sim, imprimir"
                            font.bold: true
                            color: "#ffffff"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: btnSimImprimirExtra.down ? Estilo.confirmar.pressionado : (btnSimImprimirExtra.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                        border.color: Estilo.confirmar.pressionado
                        border.width: 1
                    }
                }
            }
        }
    }

    FilaNotificacoes {
        id: filaNotificacoesExtras
    }
}
