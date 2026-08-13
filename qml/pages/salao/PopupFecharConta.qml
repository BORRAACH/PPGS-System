import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

// Popup de fechamento de conta de uma mesa (Salao.qml) — calcula a divisão
// entre as pessoas (igual ou avulsa, cada uma com sua forma de pagamento e
// status PG/NP próprios) e chama SalaoController.fecharMesa, que monta e
// imprime o cupom final com a divisão embutida.
Popup {
    id: popupFecharConta

    property string mesaId: ""
    property real valorTotal: 0
    // Itens do pedido da mesa (nome/observação/valor), só pra exibir na
    // pré-visualização (ResumoFechamento) — quem decide o que vai pro
    // cupom final é SalaoController.fecharMesa/_montarCupomFinal, que lê
    // direto do arquivo da mesa salva, não daqui.
    property var itensMesa: []
    // true = rateio automático (spinnerPessoas pessoas, valor igual pra
    // todas); false = avulso (o atendente digita o valor de cada uma).
    property bool modoIgual: true

    readonly property var opcoesPagamento: ["Pix", "Crédito", "Débito", "Dinheiro"]
    // Forma já selecionada em cada divisão nova. Mesmo padrão de
    // components/CamposPagamento.qml (que o Salão não usa: aqui é uma linha
    // por pessoa, não um bloco único) e de
    // comandaParserService.FORMA_PAGAMENTO_PADRAO.
    readonly property string formaPagamentoPadrao: "Dinheiro"

    // Soma dos valores já digitados nas divisões — só relevante no modo
    // avulso, pra dar uma pista visual se a soma não bate com o total (não
    // bloqueia o fechamento: pode ser proposital, ex. desconto/cortesia).
    readonly property real somaDivisoes: {
        var soma = 0;
        for (var i = 0; i < modeloDivisoes.count; i++) {
            var limpo = String(modeloDivisoes.get(i).valor || "").replace("R$", "").trim().replace(",", ".");
            var numero = parseFloat(limpo);
            if (!isNaN(numero))
                soma += numero;

        }
        return soma;
    }

    signal concluido(bool sucesso)

    function abrirPara(idMesa, total, itens) {
        mesaId = idMesa;
        valorTotal = total;
        itensMesa = itens || [];
        modoIgual = true;
        spinnerPessoas.value = 1;
        gerarDivisoesIguais();
        open();
    }

    // Rateio em centavos inteiros — a sobra (quando o total não divide
    // exatamente) vai uma unidade de centavo por vez pras primeiras
    // pessoas, pra soma bater exatamente com o total mesmo com dízima.
    function gerarDivisoesIguais() {
        var quantidade = spinnerPessoas.value;
        var centavosTotal = Math.round(valorTotal * 100);
        var base = Math.floor(centavosTotal / quantidade);
        var resto = centavosTotal - base * quantidade;

        // Preserva nome/forma/status já digitados quando só a quantidade
        // muda (ex: foi de 3 pra 4 pessoas) — só o valor é recalculado.
        var antigos = [];
        for (var i = 0; i < modeloDivisoes.count; i++) {
            antigos.push(modeloDivisoes.get(i));
        }

        modeloDivisoes.clear();
        for (var idx = 0; idx < quantidade; idx++) {
            var centavos = base + (idx < resto ? 1 : 0);
            var anterior = antigos[idx];
            modeloDivisoes.append({
                "nome": anterior ? anterior.nome : ("Pessoa " + (idx + 1)),
                "valor": "R$ " + (centavos / 100).toFixed(2).replace(".", ","),
                "formaPagamento": anterior ? anterior.formaPagamento : popupFecharConta.formaPagamentoPadrao,
                "status": anterior ? anterior.status : "NP",
                "trocoRecebido": anterior ? (anterior.trocoRecebido || "") : ""
            });
        }
    }

    function adicionarPessoaAvulsa() {
        modeloDivisoes.append({
            "nome": "Pessoa " + (modeloDivisoes.count + 1),
            "valor": "R$ 0,00",
            "formaPagamento": popupFecharConta.formaPagamentoPadrao,
            "status": "NP",
            "trocoRecebido": ""
        });
    }

    function alternarModo(igual) {
        if (modoIgual === igual)
            return ;

        modoIgual = igual;
        if (igual)
            gerarDivisoesIguais();
        // Virando avulso: mantém o que já estava (ponto de partida editável),
        // sem regenerar nada.
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    // Responsivo: a largura cresce até 960 conforme o espaço disponível na
    // janela (90% dela) — mais larga que antes pra acomodar a coluna de
    // controles e o painel de pré-visualização (ResumoFechamento) lado a
    // lado. A altura acompanha o conteúdo (cresce/encolhe conforme o
    // número de divisões), limitada a 760 e a 90% da janela — o Flickable
    // abaixo é a segunda camada de proteção: mesmo se o conteúdo não
    // couber (tela bem pequena), ele rola por dentro do popup em vez de
    // vazar.
    width: Math.min(960, (parent ? parent.width : 960) * 0.9)
    // Abaixo desta largura os controles e a pré-visualização não cabem lado
    // a lado (a coluna de controles pede ~380 e o resumo, 280).
    readonly property bool empilhado: width < 700
    height: Math.max(200, Math.min(760, (parent ? parent.height : 760) * 0.9, linhaConteudo.implicitHeight + topPadding + bottomPadding))

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    contentItem: Flickable {
        id: flickableFechamento

        clip: true
        contentWidth: width
        contentHeight: linhaConteudo.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        // Controles à esquerda e pré-visualização à direita enquanto
        // couberem; um sobre o outro quando não couberem, com o Flickable
        // acima cuidando da rolagem.
        GridLayout {
            id: linhaConteudo

            width: flickableFechamento.width
            columns: popupFecharConta.empilhado ? 1 : 2
            columnSpacing: Estilo.global.spacing.xxl
            rowSpacing: Estilo.global.spacing.xxl

            Column {
        id: colunaFechamento

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: 16

        Row {
            spacing: Estilo.global.spacing.sm
            Icone { nome: "fa6s.receipt"; cor: Estilo.screen.salao.accent; tamanho: 20; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "Fechar Conta"
                font.pixelSize: Estilo.global.fontSize.xxl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: "Total da conta: R$ " + popupFecharConta.valorTotal.toFixed(2).replace(".", ",")
            font.pixelSize: Estilo.global.fontSize.xl
            font.bold: true
            color: Estilo.screen.salao.accent
        }

        // --- SELEÇÃO DO MODO DE DIVISÃO ---
        Row {
            spacing: Estilo.global.spacing.md

            Button {
                id: btnModoIgual

                text: "Dividir Igualmente"
                padding: 8
                focusPolicy: Qt.StrongFocus
                Keys.onReturnPressed: clicked()
                onClicked: popupFecharConta.alternarModo(true)

                contentItem: Text {
                    text: parent.text
                    font.family: Estilo.global.fontFamily.title
                    color: popupFecharConta.modoIgual ? Estilo.global.textOnAccent : Estilo.global.text
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: popupFecharConta.modoIgual ? Estilo.screen.salao.base : (btnModoIgual.hovered ? Estilo.screen.salao.soft : Estilo.global.surface)
                    border.color: Estilo.screen.salao.accent
                    border.width: btnModoIgual.activeFocus ? 2 : 1
                }
            }

            Button {
                id: btnModoAvulso

                text: "Valores Avulsos"
                padding: 8
                focusPolicy: Qt.StrongFocus
                Keys.onReturnPressed: clicked()
                onClicked: popupFecharConta.alternarModo(false)

                contentItem: Text {
                    text: parent.text
                    font.family: Estilo.global.fontFamily.title
                    color: !popupFecharConta.modoIgual ? Estilo.global.textOnAccent : Estilo.global.text
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: !popupFecharConta.modoIgual ? Estilo.screen.salao.base : (btnModoAvulso.hovered ? Estilo.screen.salao.soft : Estilo.global.surface)
                    border.color: Estilo.screen.salao.accent
                    border.width: btnModoAvulso.activeFocus ? 2 : 1
                }
            }
        }

        // --- QUANTIDADE DE PESSOAS (modo Igual) ---
        Row {
            spacing: Estilo.global.spacing.md
            visible: popupFecharConta.modoIgual

            Text {
                text: "Número de pessoas"
                font.pixelSize: Estilo.global.fontSize.md
                font.bold: true
                color: Estilo.global.textSecondary
                anchors.verticalCenter: parent.verticalCenter
            }

            SpinBox {
                id: spinnerPessoas

                from: 1
                to: 20
                value: 1
                editable: true
                width: 90
                onValueChanged: {
                    if (popupFecharConta.modoIgual)
                        popupFecharConta.gerarDivisoesIguais();
                }


                contentItem: TextInput {
                    text: spinnerPessoas.textFromValue(spinnerPessoas.value, spinnerPessoas.locale)
                    font.pixelSize: Estilo.global.fontSize.lg
                    color: Estilo.global.textInput
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    readOnly: !spinnerPessoas.editable
                    validator: spinnerPessoas.validator
                    selectByMouse: true
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: Estilo.global.inputBackground
                    border.color: spinnerPessoas.activeFocus ? Estilo.screen.salao.accent : Estilo.global.border
                    border.width: Estilo.global.borderWidth.hairline
                }
            }
        }

        // --- BOTÃO ADICIONAR PESSOA (modo Avulso) ---
        Button {
            text: "+ Pessoa"
            padding: 8
            visible: !popupFecharConta.modoIgual
            focusPolicy: Qt.StrongFocus
            Keys.onReturnPressed: clicked()
            onClicked: popupFecharConta.adicionarPessoaAvulsa()

            contentItem: Text {
                text: parent.text
                font.family: Estilo.global.fontFamily.title
                color: Estilo.global.textOnAccent
                horizontalAlignment: Text.AlignHCenter
            }

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: parent.down ? Estilo.screen.salao.pressed : (parent.hovered ? Estilo.screen.salao.hover : Estilo.screen.salao.base)
            }
        }

        // --- COMPARATIVO DE SOMA (só faz sentido no modo Avulso) ---
        Text {
            visible: !popupFecharConta.modoIgual
            text: "Soma das divisões: R$ " + popupFecharConta.somaDivisoes.toFixed(2).replace(".", ",") + " (total da conta: R$ " + popupFecharConta.valorTotal.toFixed(2).replace(".", ",") + ")"
            font.pixelSize: Estilo.global.fontSize.sm
            font.italic: true
            color: Math.abs(popupFecharConta.somaDivisoes - popupFecharConta.valorTotal) > 0.001 ? Estilo.action.danger.base : Estilo.global.textSecondary
        }

        // --- LISTA DE DIVISÕES (uma linha por pessoa) ---
        // Sem Flickable/rolagem própria: o Flickable do popup inteiro (ver
        // contentItem acima) já cobre rolagem quando há muitas pessoas —
        // dois Flickables aninhados brigavam pela rolagem do mouse.
        Column {
            id: colunaDivisoes

            width: parent.width
            spacing: Estilo.global.spacing.md

            Repeater {
                model: modeloDivisoes

                delegate: ColumnLayout {
                    id: linhaDivisao

                    // O índice desta pessoa, guardado num nome próprio: dentro
                    // de onActivated(index) do ComboBox abaixo, o "index" do
                    // sinal esconde o do delegate, e a escolha ia parar na
                    // linha errada (escolher "Débito" — 3ª opção — na 1ª
                    // pessoa gravava na 3ª pessoa).
                    readonly property int indiceDivisao: index
                    // Mesma armadilha com o nome "model": dentro do ComboBox,
                    // "model" é a lista de opções DELE, não a linha do
                    // Repeater — "model.formaPagamento" saía undefined e o
                    // combo abria vazio (currentIndex -1), em vez de mostrar a
                    // forma já escolhida. Lido aqui, onde nada sombreia.
                    readonly property string formaDaDivisao: model.formaPagamento

                    width: colunaDivisoes.width
                    spacing: 4

                    RowLayout {
                    Layout.fillWidth: true
                    spacing: Estilo.global.spacing.xs

                    TextField {
                        id: campoNomeDivisao

                        color: Estilo.global.textInput
                        placeholderTextColor: Estilo.global.textPlaceholder
                        Layout.fillWidth: true
                        // Responsivo: nunca menor que 15 caracteres (ver
                        // fontMetricsNome abaixo), mas cresce além disso se
                        // o nome digitado precisar de mais espaço — Layout.
                        // fillWidth continua fazendo o campo ocupar a sobra
                        // da linha quando ela for maior que esse mínimo.
                        Layout.minimumWidth: Math.max(
                            fontMetricsNome.advanceWidth("M".repeat(15)) + leftPadding + rightPadding + 4,
                            fontMetricsNome.advanceWidth(text) + leftPadding + rightPadding + 20
                        )
                        text: model.nome
                        onEditingFinished: model.nome = text
                        placeholderText: "Nome"
                        topPadding: 10
                        bottomPadding: 10
                        leftPadding: 10
                        rightPadding: 10

                        FontMetrics {
                            id: fontMetricsNome
                            font: campoNomeDivisao.font
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
                            color: Estilo.global.inputBackground
                            border.color: parent.activeFocus ? Estilo.screen.salao.accent : Estilo.global.border
                            border.width: parent.activeFocus ? 2 : 1
                        }
                    }

                    TextField {
                        id: inputValorDivisao

                        color: Estilo.global.textInput
                        placeholderTextColor: Estilo.global.textPlaceholder
                        Layout.preferredWidth: 100
                        text: model.valor
                        readOnly: popupFecharConta.modoIgual
                        topPadding: 10
                        bottomPadding: 10
                        leftPadding: 10
                        rightPadding: 10
                        // Sem validador este campo aceitava letra — e escrever
                        // direto no `text` desfazia o vínculo com o modelo, o
                        // que travava o valor digitado na tela quando o rateio
                        // voltava pro modo igual e recalculava a divisão.
                        validator: Moeda.validador
                        onEditingFinished: {
                            model.valor = Moeda.formatar(text);
                            text = Qt.binding(function () {
                                return model.valor;
                            });
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
                            color: popupFecharConta.modoIgual ? Estilo.global.inputDisabled : Estilo.global.inputBackground
                            border.color: parent.activeFocus ? Estilo.screen.salao.accent : Estilo.global.border
                            border.width: parent.activeFocus ? 2 : 1
                        }
                    }

                    ComboBox {
                        id: comboFormaDivisao

                        Layout.preferredWidth: 110
                        model: popupFecharConta.opcoesPagamento
                        currentIndex: popupFecharConta.opcoesPagamento.indexOf(linhaDivisao.formaDaDivisao)
                        onActivated: modeloDivisoes.setProperty(linhaDivisao.indiceDivisao, "formaPagamento", currentText)

                        contentItem: Text {
                            text: comboFormaDivisao.displayText
                            color: Estilo.global.textInput
                            leftPadding: 10
                            rightPadding: 10
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        // Ver o comentário do mesmo delegate em
                        // components/CamposPagamento.qml.
                        delegate: ItemDelegate {
                            width: comboFormaDivisao.width
                            text: modelData
                            highlighted: comboFormaDivisao.highlightedIndex === index
                            palette.text: Estilo.global.textInput
                            palette.highlightedText: Estilo.global.textInput
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
                            color: Estilo.global.inputBackground
                            border.color: parent.activeFocus ? Estilo.screen.salao.accent : Estilo.global.border
                            border.width: Estilo.global.borderWidth.hairline
                            implicitHeight: inputValorDivisao.implicitHeight
                        }
                    }

                    Button {
                        id: btnStatusDivisao

                        width: 60
                        topPadding: 10
                        bottomPadding: 10
                        focusPolicy: Qt.StrongFocus
                        text: model.status === "PG" ? "PG" : "NP"
                        Keys.onReturnPressed: clicked()
                        onClicked: modeloDivisoes.setProperty(linhaDivisao.indiceDivisao, "status", model.status === "PG" ? "NP" : "PG")

                        contentItem: Text {
                            text: btnStatusDivisao.text
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
                            color: model.status === "PG" ? (btnStatusDivisao.down ? Estilo.action.confirm.pressed : (btnStatusDivisao.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)) : (btnStatusDivisao.down ? Estilo.action.danger.pressed : (btnStatusDivisao.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base))
                            // Anel de foco: só aparece navegando por teclado —
                            // mesmo padrão de btnStatusPagamento em Balcao.qml/
                            // Entrega.qml.
                            border.color: Estilo.global.text
                            border.width: btnStatusDivisao.activeFocus ? Estilo.global.borderWidth.focus : 0
                        }
                    }

                    Button {
                        Layout.preferredWidth: 34
                        visible: !popupFecharConta.modoIgual && modeloDivisoes.count > 1
                        focusPolicy: Qt.StrongFocus
                        onClicked: modeloDivisoes.remove(linhaDivisao.indiceDivisao)

                        contentItem: Text {
                            text: "×"
                            color: Estilo.global.textOnAccent
                            font.family: Estilo.global.fontFamily.title
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
                            color: parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                        }
                    }
                    }

                    // --- TROCO (só quando a forma de pagamento desta
                    // pessoa é Dinheiro) — puramente uma ajuda visual pro
                    // atendente calcular o troco na hora; não entra no
                    // cupom impresso (ver SalaoController._montarCupomFinal,
                    // que não lê trocoRecebido).
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 20
                        visible: model.formaPagamento === "Dinheiro"
                        spacing: Estilo.global.spacing.xs

                        Text {
                            text: "Troco para"
                            font.pixelSize: Estilo.global.fontSize.sm
                            color: Estilo.global.textSecondary
                        }

                        TextField {
                            id: campoTrocoRecebido

                            color: Estilo.global.textInput
                            placeholderTextColor: Estilo.global.textPlaceholder
                            Layout.preferredWidth: 100
                            text: model.trocoRecebido
                            placeholderText: "R$ 0,00"
                            topPadding: 8
                            bottomPadding: 8
                            leftPadding: 10
                            rightPadding: 10
                            onEditingFinished: {
                                model.trocoRecebido = Moeda.formatar(text);
                                // Digitar desfaz o vínculo "text: model.trocoRecebido" — sem
                                // restabelecer, esta linha pararia de acompanhar o modelo (mesmo
                                // motivo detalhado em components/LinhaPedido.qml).
                                text = Qt.binding(function () {
                                    return model.trocoRecebido;
                                });
                            }

                            validator: Moeda.validador

                            background: Rectangle {
                                radius: Estilo.global.radius.pill
                                color: Estilo.global.inputBackground
                                border.color: parent.activeFocus ? Estilo.screen.salao.accent : Estilo.global.border
                                border.width: parent.activeFocus ? 2 : 1
                            }
                        }

                        Text {
                            readonly property real recebido: {
                                var limpo = String(model.trocoRecebido || "").replace("R$", "").trim().replace(",", ".");
                                var numero = parseFloat(limpo);
                                return isNaN(numero) ? 0 : numero;
                            }
                            readonly property real valorPessoa: {
                                var limpo = String(model.valor || "").replace("R$", "").trim().replace(",", ".");
                                var numero = parseFloat(limpo);
                                return isNaN(numero) ? 0 : numero;
                            }
                            readonly property real trocoADar: recebido - valorPessoa

                            visible: model.trocoRecebido !== ""
                            text: "Troco a dar: R$ " + Math.max(trocoADar, 0).toFixed(2).replace(".", ",")
                            font.pixelSize: Estilo.global.fontSize.sm
                            font.bold: true
                            color: trocoADar < 0 ? Estilo.action.danger.base : Estilo.global.textSecondary
                        }
                    }
                }
            }
        }

        ListModel {
            id: modeloDivisoes
        }

        // --- CÓPIAS + AÇÕES ---
        Row {
            spacing: Estilo.global.spacing.md

            Text {
                text: "Cópias"
                font.pixelSize: Estilo.global.fontSize.md
                font.bold: true
                color: Estilo.global.textSecondary
                anchors.verticalCenter: parent.verticalCenter
            }

            SpinnerCopias {
                id: spinnerCopiasFechamento

                value: 1
                width: 90
                corDestaque: Estilo.screen.salao.accent
            }
        }

        Row {
            spacing: Estilo.global.spacing.lg
            anchors.right: parent.right

            Button {
                id: btnCancelarFechamento

                text: "Cancelar"
                padding: Estilo.global.padding.md
                focusPolicy: Qt.StrongFocus
                Keys.onReturnPressed: clicked()
                onClicked: popupFecharConta.close()

                contentItem: Text {
                    text: btnCancelarFechamento.text
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: parent.down ? Estilo.action.neutral.pressed : (parent.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                    border.color: parent.activeFocus ? Estilo.global.text : "transparent"
                    border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : 0
                }
            }

            Button {
                id: btnConfirmarFechamento

                padding: Estilo.global.padding.md
                focusPolicy: Qt.StrongFocus
                Keys.onReturnPressed: clicked()
                onClicked: {
                    var divisoes = [];
                    for (var i = 0; i < modeloDivisoes.count; i++) {
                        var item = modeloDivisoes.get(i);
                        divisoes.push({
                            "nome": item.nome,
                            "valor": item.valor,
                            "formaPagamento": item.formaPagamento,
                            "status": item.status
                        });
                    }
                    var sucesso = salaoController.fecharMesa(popupFecharConta.mesaId, divisoes, spinnerCopiasFechamento.value);
                    popupFecharConta.close();
                    popupFecharConta.concluido(sucesso);
                }

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.print"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Confirmar e Imprimir"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: parent.down ? Estilo.action.confirm.pressed : (parent.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                    border.color: parent.activeFocus ? Estilo.global.text : Estilo.action.confirm.pressed
                    border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                }
            }
        }
        }

            // --- PRÉ-VISUALIZAÇÃO (itens da mesa + divisão da conta) ---
            ResumoFechamento {
                Layout.preferredWidth: popupFecharConta.empilhado ? linhaConteudo.width : 280
                Layout.alignment: Qt.AlignTop
                itensMesa: popupFecharConta.itensMesa
                divisoes: modeloDivisoes
                valorTotal: popupFecharConta.valorTotal
            }
        }
    }
}
