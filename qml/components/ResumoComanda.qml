import QtQuick
import QtQuick.Controls
import estilo 1.0

// Painel de resumo mostrado ao lado dos formulários de Balcão/Entrega —
// espelha as informações que vão para a comanda impressa (ver
// controllers/balcaoController.py e controllers/entregaController.py,
// método _salvarComanda), pra o atendente conferir valor total, forma de
// pagamento, status e taxa de entrega antes de imprimir/lançar.
//
// Tem dois modos. O padrão ("detalhado: false") é o de sempre: uma linha por
// item, só nome e valor, porque ali do lado está o formulário inteiro com o
// resto — o resumo é conferência rápida, não a comanda completa. Com
// "detalhado: true" o mesmo painel vira a comanda inteira (dados do cliente,
// frações de pizza, adicionais, borda, observações), e é assim que a página
// de Fechamento exibe uma comanda já lançada: lá não existe formulário ao
// lado, o painel é a única coisa na tela, e esconder qualquer campo
// significaria voltar a ler o cupom da impressora pra conferir.
Rectangle {
    id: root

    property alias itens: repeaterItens.model
    property color corDestaque: Estilo.action.confirm.base
    property string formaPagamento: ""
    property string troco: ""
    property bool pago: false
    property string taxaEntrega: ""
    property bool mostrarTaxaEntrega: false

    // Mostra tudo o que a comanda tem, em vez do resumo de uma linha por
    // item. Os campos abaixo só aparecem neste modo — no modo padrão quem
    // exibe cliente/telefone/endereço é o próprio formulário ao lado.
    property bool detalhado: false
    property string cliente: ""
    property string telefone: ""
    property string endereco: ""
    property string bairro: ""
    property string observacaoGeral: ""

    // Mesmo separador que services/comandaTextoService.py usa pra montar e
    // desmontar pizzas meio a meio (SEPARADOR_SABORES). Tem espaço dos dois
    // lados de propósito, o que o distingue de nomes como "Atum c/ Cebola".
    readonly property string separadorSabores: " / "

    // Uma linha rótulo/valor do bloco de dados do cliente. Some sozinha
    // quando o campo está vazio — Balcão não tem telefone/endereço/bairro, e
    // observação geral só existe na Entrega.
    component LinhaDetalhe: Item {
        id: linhaDetalhe

        property string rotulo: ""
        property string valor: ""

        width: parent ? parent.width : 0
        visible: valor !== ""
        height: visible ? Math.max(textoRotulo.implicitHeight, textoValor.implicitHeight) : 0

        Text {
            id: textoRotulo

            anchors.left: parent.left
            anchors.top: parent.top
            text: linhaDetalhe.rotulo
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
        }

        Text {
            id: textoValor

            anchors.left: textoRotulo.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.top: parent.top
            text: linhaDetalhe.valor
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.text
            horizontalAlignment: Text.AlignRight
            wrapMode: Text.WordWrap
        }

    }

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

    // "borda" e "adicionais" chegam como STRING JSON quando a origem é o
    // ListModel de Balcao.qml/Entrega.qml (um array atribuído a um role vira
    // um list-model aninhado, por isso a convenção — ver o comentário longo
    // em Balcao.qml), mas como objeto/array de verdade quando vêm direto de
    // um QVariantMap do Python. Aceitar os dois evita obrigar cada chamador a
    // converter antes.
    function _comoObjeto(valor, padrao) {
        if (valor === undefined || valor === null || valor === "")
            return padrao;

        if (typeof valor !== "string")
            return valor;

        try {
            var lido = JSON.parse(valor);
            return lido === null || lido === undefined ? padrao : lido;
        } catch (erro) {
            return padrao;
        }
    }

    // Adicionais atribuídos a um sabor específico, já formatados. Mesma
    // comparação sem diferenciar caixa de comandaTextoService._extras_adicionais:
    // o nome do sabor pode vir em caixa alta (reconstruído de uma comanda já
    // impressa) enquanto o adicional guardou o nome como veio de Pizzas.qml.
    function _extrasDoSabor(adicionais, sabor) {
        var alvo = (sabor || "").trim().toUpperCase();
        var extras = [];
        for (var i = 0; i < adicionais.length; i++) {
            var adicional = adicionais[i];
            if (!adicional || (adicional.sabor || "").trim().toUpperCase() !== alvo)
                continue;

            extras.push(root._textoAdicional(adicional));
        }
        return extras;
    }

    // Prefixo "+" igual ao do cupom (PREFIXO_ADICIONAL).
    function _textoAdicional(adicional) {
        var valor = adicional.valor || "";
        return "+ " + (adicional.nome || "") + (valor ? " (" + valor + ")" : "");
    }

    // Os sabores de um item, e o tamanho entre parênteses no fim quando
    // houver. Mesma leitura que comandaTextoService.dividir_sabores faz do
    // outro lado.
    function _saboresDe(pedido) {
        var corpo = pedido;
        var tamanho = "";

        var casou = /^(.*)\s\(([^)]+)\)$/.exec(pedido);
        if (casou) {
            corpo = casou[1];
            tamanho = casou[2];
        }

        return {
            "sabores": corpo.split(root.separadorSabores).filter(function (s) {
                return s.trim() !== "";
            }),
            "tamanho": tamanho
        };
    }

    // Todos os adicionais do item numa lista só, sem separar por fração — é o
    // que o modo compacto mostra, já que ali o item ocupa uma linha só e não
    // há fração a que pendurar cada um. Numa pizza dividida o sabor vai junto,
    // senão "+ Bacon" não diria em qual metade ele entra.
    function _extrasDoItem(pedido, adicionaisBrutos) {
        var adicionais = _comoObjeto(adicionaisBrutos, []);
        var varios = root._saboresDe(pedido).sabores.length > 1;
        var extras = [];

        for (var i = 0; i < adicionais.length; i++) {
            var adicional = adicionais[i];
            if (!adicional)
                continue;

            var texto = root._textoAdicional(adicional);
            var sabor = (adicional.sabor || "").trim();
            extras.push(varios && sabor ? texto + " — " + sabor : texto);
        }
        return extras;
    }

    // Desmonta um item nas linhas que ele ocupa, do mesmo jeito que
    // comandaTextoService.montar_grupos monta pro papel: uma pizza meio a
    // meio (ou em mais partes) vira uma linha "1/N - Sabor" por sabor, com o
    // tamanho junto só na primeira, e cada adicional aparece logo abaixo da
    // fração a que pertence. Item comum vira uma linha só.
    function _linhasDoItem(pedido, adicionaisBrutos) {
        var adicionais = _comoObjeto(adicionaisBrutos, []);
        var partes = root._saboresDe(pedido);
        var sabores = partes.sabores;
        var tamanho = partes.tamanho;

        if (sabores.length <= 1)
            return [{
                "texto": pedido,
                "extras": root._extrasDoSabor(adicionais, sabores.length ? sabores[0] : pedido)
            }];

        var linhas = [];
        for (var i = 0; i < sabores.length; i++) {
            var nome = i === 0 && tamanho ? sabores[i] + " (" + tamanho + ")" : sabores[i];
            // "1/N" em todas, não "1/N, 2/N, ...": é a fração da pizza que
            // aquele sabor ocupa, não a posição dele na lista — mesma leitura
            // do cupom (comandaTextoService.montar_grupos).
            linhas.push({
                "texto": "1/" + sabores.length + " - " + nome,
                "extras": root._extrasDoSabor(adicionais, sabores[i])
            });
        }
        return linhas;
    }

    // Borda da pizza (nível do item inteiro, não de um sabor) — "" quando não
    // houver. Prefixo "*" igual ao do cupom (PREFIXO_BORDA).
    function _linhaBorda(bordaBruta) {
        var borda = _comoObjeto(bordaBruta, null);
        if (!borda || !borda.nome)
            return "";

        return "* " + borda.nome + (borda.valor ? " (" + borda.valor + ")" : "");
    }

    readonly property int quantidadeItens: {
        var n = 0;
        for (var i = 0; i < itens.count; i++) {
            if (itens.get(i).pedido !== "")
                n++;

        }
        return n;
    }
    readonly property real valorItens: {
        var soma = 0;
        for (var i = 0; i < itens.count; i++) {
            var item = itens.get(i);
            if (item.pedido !== "")
                soma += _valorNumero(item.valor);

        }
        return soma;
    }
    readonly property bool temDadosCliente: detalhado && (cliente !== "" || telefone !== "" || endereco !== "" || bairro !== "" || observacaoGeral !== "")
    readonly property real valorTaxa: mostrarTaxaEntrega ? _valorNumero(taxaEntrega) : 0
    readonly property real valorTotal: valorItens + valorTaxa
    readonly property bool ehDinheiro: formaPagamento === "Dinheiro" && troco !== ""
    readonly property real trocoADar: _valorNumero(troco) - valorTotal

    // implicitWidth, e não width: num Row (Balcão/Entrega) o Item cai no
    // implicitWidth sozinho, então lá nada muda; quem precisa de outra
    // largura (o popup do Fechamento, que ocupa a largura toda) passa a poder
    // simplesmente atribuir width.
    implicitWidth: 300
    implicitHeight: colunaResumo.implicitHeight + Estilo.global.padding.xl * 2
    radius: Estilo.global.radius.lg
    color: Estilo.global.surface
    border.color: Estilo.global.borderCard
    border.width: Estilo.global.borderWidth.hairline

    Column {
        id: colunaResumo

        width: parent.width - Estilo.global.padding.xl * 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Estilo.global.padding.xl
        spacing: Estilo.global.spacing.lg

        Row {
            spacing: Estilo.global.spacing.sm

            Icone {
                nome: "fa6s.receipt"
                cor: root.corDestaque
                tamanho: 18
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "RESUMO DA COMANDA"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: root.corDestaque
                anchors.verticalCenter: parent.verticalCenter
            }

        }

        Rectangle {
            width: parent.width
            height: 1
            color: Estilo.global.borderCard
        }

        // --- Dados do cliente (só no modo detalhado) ---
        // No modo padrão esses campos estão todos visíveis no formulário ao
        // lado; aqui eles são a única cópia na tela.
        Column {
            width: parent.width
            spacing: 4
            visible: root.temDadosCliente

            LinhaDetalhe {
                rotulo: "Cliente"
                valor: root.cliente
            }

            LinhaDetalhe {
                rotulo: "Telefone"
                valor: root.telefone
            }

            LinhaDetalhe {
                rotulo: "Endereço"
                valor: root.endereco
            }

            LinhaDetalhe {
                rotulo: "Bairro"
                valor: root.bairro
            }

            LinhaDetalhe {
                rotulo: "Observação"
                valor: root.observacaoGeral
            }

        }

        Rectangle {
            width: parent.width
            height: 1
            color: Estilo.global.borderCard
            visible: root.temDadosCliente
        }

        // --- Itens do pedido ---
        // Simplificados (nome + valor) no modo padrão; inteiros no detalhado.
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
            spacing: root.detalhado ? 12 : 6
            visible: root.quantidadeItens > 0

            Repeater {
                id: repeaterItens

                delegate: Column {
                    id: grupoItem

                    // Os campos do item ficam presos aqui, e não lidos de
                    // "model" lá embaixo: dentro dos Repeater aninhados
                    // "model" já é o contexto DELES, não o deste item.
                    readonly property string nomeItem: model.pedido || ""
                    readonly property string valorItem: model.valor || ""
                    readonly property string observacaoItem: model.observacao || ""

                    // Frações do item (uma por sabor numa pizza dividida) já
                    // com os adicionais de cada uma — ver root._linhasDoItem.
                    // Calculado uma vez por item, e não dentro do Repeater
                    // aninhado, pra não refazer o split/parse a cada binding.
                    readonly property var linhas: root.detalhado ? root._linhasDoItem(nomeItem, model.adicionais) : []
                    // Borda e adicionais aparecem nos DOIS modos. Eles entram
                    // no preço do item e saem no cupom impresso, então um
                    // resumo que os esconde mostra um total que não bate com o
                    // que está listado — era o que acontecia em Balcão,
                    // Entrega e Salão, que usam o modo compacto.
                    readonly property var extrasItem: root.detalhado ? [] : root._extrasDoItem(nomeItem, model.adicionais)
                    readonly property string textoBorda: root._linhaBorda(model.borda)

                    width: colunaResumo.width
                    visible: nomeItem !== ""
                    spacing: 2

                    // --- Modo padrão: uma linha, nome elidido + valor ---
                    Item {
                        width: parent.width
                        height: visible ? Math.max(textoNomeItem.implicitHeight, textoValorItem.implicitHeight) : 0
                        visible: !root.detalhado

                        Text {
                            id: textoNomeItem

                            anchors.left: parent.left
                            anchors.right: textoValorItem.left
                            anchors.rightMargin: 8
                            text: "• " + grupoItem.nomeItem
                            font.pixelSize: Estilo.global.fontSize.md
                            color: Estilo.global.text
                            elide: Text.ElideRight
                        }

                        Text {
                            id: textoValorItem

                            anchors.right: parent.right
                            text: grupoItem.valorItem || "R$ 0,00"
                            font.pixelSize: Estilo.global.fontSize.md
                            color: Estilo.global.textSecondary
                        }

                    }

                    // Adicionais no modo compacto: aqui o item é uma linha só,
                    // então todos entram recuados logo abaixo dela. No modo
                    // detalhado cada um já sai sob a sua fração (ver o Repeater
                    // aninhado mais abaixo), e por isso `extrasItem` vem vazio.
                    Repeater {
                        model: grupoItem.extrasItem

                        delegate: Text {
                            required property string modelData

                            width: grupoItem.width - 20
                            x: 20
                            text: modelData
                            font.pixelSize: Estilo.global.fontSize.sm
                            color: Estilo.global.textSecondary
                            wrapMode: Text.WordWrap
                        }
                    }

                    // --- Modo detalhado: uma linha por fração, com extras ---
                    Repeater {
                        model: root.detalhado ? grupoItem.linhas : []

                        delegate: Column {
                            id: linhaFracao

                            required property int index
                            required property var modelData

                            width: grupoItem.width
                            spacing: 2

                            Item {
                                width: parent.width
                                height: Math.max(textoFracao.implicitHeight, textoValorFracao.implicitHeight)

                                Text {
                                    id: textoFracao

                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.right: textoValorFracao.left
                                    anchors.rightMargin: 8
                                    // Só a primeira fração leva o marcador do
                                    // item; as outras alinham por baixo dele.
                                    text: (linhaFracao.index === 0 ? "• " : "   ") + linhaFracao.modelData.texto
                                    font.pixelSize: Estilo.global.fontSize.md
                                    color: Estilo.global.text
                                    wrapMode: Text.WordWrap
                                }

                                Text {
                                    id: textoValorFracao

                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    // O valor é da pizza inteira, não de cada
                                    // fração — sai só na primeira linha, igual
                                    // ao cupom (comandaTextoService.formatar_tabela).
                                    text: linhaFracao.index === 0 ? grupoItem.valorItem : ""
                                    font.pixelSize: Estilo.global.fontSize.md
                                    font.bold: true
                                    color: Estilo.global.text
                                }

                            }

                            Repeater {
                                model: linhaFracao.modelData.extras

                                delegate: Text {
                                    required property string modelData

                                    width: linhaFracao.width - 20
                                    x: 20
                                    text: modelData
                                    font.pixelSize: Estilo.global.fontSize.sm
                                    color: Estilo.global.textSecondary
                                    wrapMode: Text.WordWrap
                                }

                            }

                        }

                    }

                    // Borda e observação saem depois de TODAS as frações,
                    // nunca entre uma e outra — mesma ordem do cupom.
                    Text {
                        width: parent.width - 20
                        x: 20
                        visible: grupoItem.textoBorda !== ""
                        text: grupoItem.textoBorda
                        font.pixelSize: Estilo.global.fontSize.sm
                        color: Estilo.global.textSecondary
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width - 20
                        x: 20
                        visible: root.detalhado && grupoItem.observacaoItem !== ""
                        text: grupoItem.observacaoItem
                        font.pixelSize: Estilo.global.fontSize.sm
                        font.italic: true
                        color: Estilo.global.text
                        wrapMode: Text.WordWrap
                    }

                }

            }

        }

        Rectangle {
            width: parent.width
            height: 1
            color: Estilo.global.borderCard
        }

        // --- Taxa de entrega (só aparece na tela de Entrega) ---
        Item {
            width: parent.width
            height: textoTaxaLabel.implicitHeight
            visible: root.mostrarTaxaEntrega

            Text {
                id: textoTaxaLabel

                anchors.left: parent.left
                text: "Taxa de entrega"
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.text
            }

            Text {
                anchors.right: parent.right
                text: root._formatarMoeda(root.valorTaxa)
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.text
            }

        }

        // --- Forma de pagamento ---
        Item {
            width: parent.width
            height: textoFormaLabel.implicitHeight

            Text {
                id: textoFormaLabel

                anchors.left: parent.left
                text: "Forma de pagamento"
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.text
            }

            Text {
                anchors.right: parent.right
                text: root.formaPagamento || "—"
                font.pixelSize: Estilo.global.fontSize.md
                font.bold: true
                color: Estilo.global.text
            }

        }

        // --- Troco (só quando o pagamento é em dinheiro e o valor foi informado) ---
        Item {
            width: parent.width
            height: root.ehDinheiro ? colunaTroco.implicitHeight : 0
            visible: root.ehDinheiro
            clip: true

            Column {
                id: colunaTroco

                width: parent.width
                spacing: 4

                Item {
                    width: parent.width
                    height: textoTrocoLabel.implicitHeight

                    Text {
                        id: textoTrocoLabel

                        anchors.left: parent.left
                        text: "Troco para"
                        font.pixelSize: Estilo.global.fontSize.md
                        color: Estilo.global.text
                    }

                    Text {
                        anchors.right: parent.right
                        text: root.troco
                        font.pixelSize: Estilo.global.fontSize.md
                        color: Estilo.global.text
                    }

                }

                Item {
                    width: parent.width
                    height: textoTrocoADarLabel.implicitHeight

                    Text {
                        id: textoTrocoADarLabel

                        anchors.left: parent.left
                        text: "Troco a dar"
                        font.pixelSize: Estilo.global.fontSize.md
                        color: Estilo.global.text
                    }

                    Text {
                        anchors.right: parent.right
                        text: root._formatarMoeda(Math.max(root.trocoADar, 0))
                        font.pixelSize: Estilo.global.fontSize.md
                        font.bold: true
                        color: root.trocoADar < 0 ? Estilo.action.danger.base : Estilo.global.text
                    }

                }

            }

        }

        // --- Status de pagamento ---
        Item {
            width: parent.width
            height: chipStatus.height

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Status"
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.text
            }

            Rotulo {
                id: chipStatus

                anchors.right: parent.right
                texto: root.pago ? "PAGO" : "NÃO PAGO"
                tom: root.pago ? Estilo.action.confirm : Estilo.action.danger
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
            height: textoTotalLabel.implicitHeight

            Text {
                id: textoTotalLabel

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "TOTAL"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: root.corDestaque
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root._formatarMoeda(root.valorTotal)
                font.pixelSize: Estilo.global.fontSize.xxl
                font.bold: true
                color: root.corDestaque
            }

        }

    }

}
