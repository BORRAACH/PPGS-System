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
                "formaPagamento": anterior ? anterior.formaPagamento : "Pix",
                "status": anterior ? anterior.status : "NP",
                "trocoRecebido": anterior ? (anterior.trocoRecebido || "") : ""
            });
        }
    }

    function adicionarPessoaAvulsa() {
        modeloDivisoes.append({
            "nome": "Pessoa " + (modeloDivisoes.count + 1),
            "valor": "R$ 0,00",
            "formaPagamento": "Pix",
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
    padding: 25
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
    height: Math.max(200, Math.min(760, (parent ? parent.height : 760) * 0.9, linhaConteudo.implicitHeight + topPadding + bottomPadding))

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        radius: Estilo.rounding.popup
        color: Estilo.cores.fundoPagina
        border.color: Estilo.cores.bordaCard
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

        RowLayout {
            id: linhaConteudo

            width: flickableFechamento.width
            spacing: 20

            Column {
        id: colunaFechamento

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        spacing: 16

        Row {
            spacing: 8
            Icone { nome: "fa6s.receipt"; cor: "#0d9488"; tamanho: 20; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "Fechar Conta"
                font.pixelSize: 18
                font.bold: true
                color: Estilo.cores.texto
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: "Total da conta: R$ " + popupFecharConta.valorTotal.toFixed(2).replace(".", ",")
            font.pixelSize: 15
            font.bold: true
            color: "#0d9488"
        }

        // --- SELEÇÃO DO MODO DE DIVISÃO ---
        Row {
            spacing: 10

            Button {
                id: btnModoIgual

                text: "Dividir Igualmente"
                padding: 8
                focusPolicy: Qt.StrongFocus
                Keys.onReturnPressed: clicked()
                onClicked: popupFecharConta.alternarModo(true)

                contentItem: Text {
                    text: parent.text
                    font.bold: true
                    color: popupFecharConta.modoIgual ? "#ffffff" : Estilo.cores.texto
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: popupFecharConta.modoIgual ? "#0d9488" : (btnModoIgual.hovered ? "#e6fffa" : "#ffffff")
                    border.color: "#0d9488"
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
                    font.bold: true
                    color: !popupFecharConta.modoIgual ? "#ffffff" : Estilo.cores.texto
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: !popupFecharConta.modoIgual ? "#0d9488" : (btnModoAvulso.hovered ? "#e6fffa" : "#ffffff")
                    border.color: "#0d9488"
                    border.width: btnModoAvulso.activeFocus ? 2 : 1
                }
            }
        }

        // --- QUANTIDADE DE PESSOAS (modo Igual) ---
        Row {
            spacing: 10
            visible: popupFecharConta.modoIgual

            Text {
                text: "Número de pessoas"
                font.pixelSize: 13
                font.bold: true
                color: Estilo.cores.textoSecundario
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
                    font.pixelSize: Estilo.fonte.padrao
                    color: Estilo.cores.texto
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    readOnly: !spinnerPessoas.editable
                    validator: spinnerPessoas.validator
                    selectByMouse: true
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: "#ffffff"
                    border.color: spinnerPessoas.activeFocus ? "#0d9488" : Estilo.cores.borda
                    border.width: 1
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
                font.bold: true
                color: "#ffffff"
                horizontalAlignment: Text.AlignHCenter
            }

            background: Rectangle {
                radius: Estilo.rounding.padrao
                color: parent.down ? "#0f766e" : (parent.hovered ? "#0f8a80" : "#0d9488")
            }
        }

        // --- COMPARATIVO DE SOMA (só faz sentido no modo Avulso) ---
        Text {
            visible: !popupFecharConta.modoIgual
            text: "Soma das divisões: R$ " + popupFecharConta.somaDivisoes.toFixed(2).replace(".", ",") + " (total da conta: R$ " + popupFecharConta.valorTotal.toFixed(2).replace(".", ",") + ")"
            font.pixelSize: 12
            font.italic: true
            color: Math.abs(popupFecharConta.somaDivisoes - popupFecharConta.valorTotal) > 0.001 ? Estilo.cancelar.normal : Estilo.cores.textoSecundario
        }

        // --- LISTA DE DIVISÕES (uma linha por pessoa) ---
        // Sem Flickable/rolagem própria: o Flickable do popup inteiro (ver
        // contentItem acima) já cobre rolagem quando há muitas pessoas —
        // dois Flickables aninhados brigavam pela rolagem do mouse.
        Column {
            id: colunaDivisoes

            width: parent.width
            spacing: 10

            Repeater {
                model: modeloDivisoes

                delegate: ColumnLayout {
                    id: linhaDivisao

                    width: colunaDivisoes.width
                    spacing: 4

                    RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    TextField {
                        id: campoNomeDivisao

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
                            radius: Estilo.rounding.padrao
                            color: "#ffffff"
                            border.color: parent.activeFocus ? "#0d9488" : Estilo.cores.borda
                            border.width: parent.activeFocus ? 2 : 1
                        }
                    }

                    TextField {
                        id: inputValorDivisao

                        Layout.preferredWidth: 100
                        text: model.valor
                        readOnly: popupFecharConta.modoIgual
                        topPadding: 10
                        bottomPadding: 10
                        leftPadding: 10
                        rightPadding: 10
                        onEditingFinished: {
                            if (text !== "") {
                                var numLimpo = text.replace("R$", "").replace(" ", "").replace(",", ".");
                                var valorFloat = parseFloat(numLimpo);
                                if (!isNaN(valorFloat)) {
                                    var formatado = "R$ " + valorFloat.toFixed(2).replace(".", ",");
                                    model.valor = formatado;
                                    text = formatado;
                                }
                            }
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.padrao
                            color: popupFecharConta.modoIgual ? Estilo.cores.fundoPagina : "#ffffff"
                            border.color: parent.activeFocus ? "#0d9488" : Estilo.cores.borda
                            border.width: parent.activeFocus ? 2 : 1
                        }
                    }

                    ComboBox {
                        Layout.preferredWidth: 110
                        model: popupFecharConta.opcoesPagamento
                        currentIndex: popupFecharConta.opcoesPagamento.indexOf(model.formaPagamento)
                        onActivated: modeloDivisoes.setProperty(index, "formaPagamento", currentText)

                        contentItem: Text {
                            text: parent.displayText
                            color: Estilo.cores.texto
                            leftPadding: 10
                            rightPadding: 10
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.padrao
                            color: "#ffffff"
                            border.color: parent.activeFocus ? "#0d9488" : Estilo.cores.borda
                            border.width: 1
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
                        onClicked: modeloDivisoes.setProperty(index, "status", model.status === "PG" ? "NP" : "PG")

                        contentItem: Text {
                            text: btnStatusDivisao.text
                            font.bold: true
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.padrao
                            color: model.status === "PG" ? (btnStatusDivisao.down ? Estilo.confirmar.pressionado : (btnStatusDivisao.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)) : (btnStatusDivisao.down ? Estilo.cancelar.pressionado : (btnStatusDivisao.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal))
                            // Anel de foco: só aparece navegando por teclado —
                            // mesmo padrão de btnStatusPagamento em Balcao.qml/
                            // Entrega.qml.
                            border.color: Estilo.cores.texto
                            border.width: btnStatusDivisao.activeFocus ? 3 : 0
                        }
                    }

                    Button {
                        Layout.preferredWidth: 34
                        visible: !popupFecharConta.modoIgual && modeloDivisoes.count > 1
                        focusPolicy: Qt.StrongFocus
                        onClicked: modeloDivisoes.remove(index)

                        contentItem: Text {
                            text: "×"
                            color: "#ffffff"
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.padrao
                            color: parent.down ? Estilo.cancelar.pressionado : (parent.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
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
                        spacing: 6

                        Text {
                            text: "Troco para"
                            font.pixelSize: 12
                            color: Estilo.cores.textoSecundario
                        }

                        TextField {
                            id: campoTrocoRecebido

                            Layout.preferredWidth: 100
                            text: model.trocoRecebido
                            placeholderText: "R$ 0,00"
                            topPadding: 8
                            bottomPadding: 8
                            leftPadding: 10
                            rightPadding: 10
                            onEditingFinished: {
                                if (text !== "") {
                                    var numLimpo = text.replace("R$", "").replace(" ", "").replace(",", ".");
                                    var valorFloat = parseFloat(numLimpo);
                                    if (!isNaN(valorFloat)) {
                                        var formatado = "R$ " + valorFloat.toFixed(2).replace(".", ",");
                                        model.trocoRecebido = formatado;
                                        text = formatado;
                                        return;
                                    }
                                }
                                model.trocoRecebido = text;
                            }

                            validator: DoubleValidator {
                                bottom: 0
                                decimals: 2
                                notation: DoubleValidator.StandardNotation
                            }

                            background: Rectangle {
                                radius: Estilo.rounding.padrao
                                color: "#ffffff"
                                border.color: parent.activeFocus ? "#0d9488" : Estilo.cores.borda
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
                            font.pixelSize: 12
                            font.bold: true
                            color: trocoADar < 0 ? Estilo.cancelar.normal : Estilo.cores.textoSecundario
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
            spacing: 10

            Text {
                text: "Cópias"
                font.pixelSize: 13
                font.bold: true
                color: Estilo.cores.textoSecundario
                anchors.verticalCenter: parent.verticalCenter
            }

            SpinBox {
                id: spinnerCopiasFechamento

                from: 1
                to: 5
                value: 1
                editable: true
                width: 90

                contentItem: TextInput {
                    text: spinnerCopiasFechamento.textFromValue(spinnerCopiasFechamento.value, spinnerCopiasFechamento.locale)
                    font.pixelSize: Estilo.fonte.padrao
                    color: Estilo.cores.texto
                    horizontalAlignment: Qt.AlignHCenter
                    verticalAlignment: Qt.AlignVCenter
                    readOnly: !spinnerCopiasFechamento.editable
                    validator: spinnerCopiasFechamento.validator
                    selectByMouse: true
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: "#ffffff"
                    border.color: spinnerCopiasFechamento.activeFocus ? "#0d9488" : Estilo.cores.borda
                    border.width: 1
                }
            }
        }

        Row {
            spacing: 12
            anchors.right: parent.right

            Button {
                id: btnCancelarFechamento

                text: "Cancelar"
                padding: 10
                focusPolicy: Qt.StrongFocus
                Keys.onReturnPressed: clicked()
                onClicked: popupFecharConta.close()

                contentItem: Text {
                    text: btnCancelarFechamento.text
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Estilo.cores.textoSecundario : (parent.hovered ? "#95a5a6" : Estilo.cores.textoSecundario)
                    border.color: parent.activeFocus ? Estilo.cores.texto : "transparent"
                    border.width: parent.activeFocus ? 3 : 0
                }
            }

            Button {
                id: btnConfirmarFechamento

                padding: 10
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
                    spacing: 6
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.print"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Confirmar e Imprimir"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Estilo.confirmar.pressionado : (parent.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                    border.color: parent.activeFocus ? Estilo.cores.texto : Estilo.confirmar.pressionado
                    border.width: parent.activeFocus ? 3 : 1
                }
            }
        }
        }

            // --- PRÉ-VISUALIZAÇÃO (itens da mesa + divisão da conta) ---
            ResumoFechamento {
                Layout.preferredWidth: 280
                Layout.alignment: Qt.AlignTop
                itensMesa: popupFecharConta.itensMesa
                divisoes: modeloDivisoes
                valorTotal: popupFecharConta.valorTotal
            }
        }
    }
}
