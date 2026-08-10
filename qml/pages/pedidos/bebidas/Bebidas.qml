import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../../components"
import "../../../components/Texto.js" as Texto

Page {
    id: telaBebidas

    focus: true
    // "focus: true" sozinho não é suficiente: StackView assume o controle do
    // foco ao trocar de página, então é preciso pedir foco de novo quando
    // esta página vira a atual (senão digitar sem clicar antes não funciona).
    StackView.onActivated: forceActiveFocus()

    property var onPedidoSelecionado: null
    property var pilha: null
    // true só quando aberta a partir de Salao.qml (via Pedido.qml) — alguns
    // itens de bebida têm um preço maior específico pra comanda de mesa
    // (campo opcional "valorMesa" em data/cardapio/bebidas.json), usado em
    // vez do preço normal só quando isto está ligado (ver precoEfetivo()).
    property bool comandaDeMesa: false
    // Lista para guardar as bebidas selecionadas — cada entrada é única por
    // nome e guarda a quantidade escolhida, permitindo pedir a mesma bebida
    // mais de uma vez (ex: 2 Coca-Cola) sem reabrir esta tela.
    property var selecionados: []
    // Soma das quantidades de todas as bebidas (usado nos textos de resumo)
    readonly property int totalItens: {
        var soma = 0;
        for (var i = 0; i < selecionados.length; i++) {
            soma += selecionados[i].quantidade;
        }
        return soma;
    }
    // Propriedade computada para o valor somado de todas as bebidas selecionadas
    readonly property real valorAtual: {
        var soma = 0;
        for (var i = 0; i < selecionados.length; i++) {
            soma += selecionados[i].valorNum * selecionados[i].quantidade;
        }
        return soma;
    }

    function carregarBebidas() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(raizProjeto + "data/cardapio/bebidas.json"));
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var dados = JSON.parse(xhr.responseText);
                        modeloBebidas.clear();
                        for (var i = 0; i < dados.length; i++) {
                            modeloBebidas.append(dados[i]);
                        }
                        console.log("Bebidas carregadas:", modeloBebidas.count);
                        filtrarBebidas("");
                    } catch (e) {
                        console.error("Erro ao interpretar JSON:", e);
                    }
                } else {
                    console.error("Erro ao carregar bebidas.json, status:", xhr.status);
                }
            }
        };
        xhr.send();
    }

    function filtrarBebidas(texto) {
        modeloFiltrado.clear();
        var busca = texto ? Texto.normalizar(texto.trim()) : "";
        var resultados = [];
        for (var i = 0; i < modeloBebidas.count; i++) {
            var item = modeloBebidas.get(i);
            var nomeLower = Texto.normalizar(item.nome);
            if (busca === "" || nomeLower.indexOf(busca) !== -1)
                resultados.push({
                    "nome": item.nome,
                    "valor": item.valor,
                    "valorMesa": item.valorMesa || "",
                    "prioridade": nomeLower.startsWith(busca) ? 0 : 1
                });
        }
        resultados.sort(function(a, b) {
            if (a.prioridade !== b.prioridade)
                return a.prioridade - b.prioridade;

            return a.nome.localeCompare(b.nome);
        });
        for (var j = 0; j < resultados.length; j++) {
            modeloFiltrado.append({
                "nome": resultados[j].nome,
                "valor": resultados[j].valor,
                "valorMesa": resultados[j].valorMesa
            });
        }
    }

    function parseValor(strValor) {
        return parseFloat(strValor.replace(",", "."));
    }

    // Preço de fato cobrado por este item: o de mesa, só quando esta tela
    // foi aberta a partir do Salão (comandaDeMesa) e o item tem um preço de
    // mesa cadastrado — senão, o preço normal de Balcão/Entrega.
    function precoEfetivo(item) {
        return (comandaDeMesa && item.valorMesa) ? item.valorMesa : item.valor;
    }

    // Quantidade atualmente escolhida de uma bebida (0 se não selecionada)
    function quantidadeDe(nome) {
        for (var i = 0; i < selecionados.length; i++) {
            if (selecionados[i].nome === nome)
                return selecionados[i].quantidade;
        }
        return 0;
    }

    // Adiciona mais uma unidade da bebida (nova entrada se ainda não escolhida)
    function adicionarItem(nome, valorNum) {
        var lista = selecionados.slice();
        for (var i = 0; i < lista.length; i++) {
            if (lista[i].nome === nome) {
                lista[i] = {
                    "nome": nome,
                    "valorNum": valorNum,
                    "quantidade": lista[i].quantidade + 1
                };
                selecionados = lista;
                return ;
            }
        }
        lista.push({
            "nome": nome,
            "valorNum": valorNum,
            "quantidade": 1
        });
        selecionados = lista;
    }

    // Remove uma unidade da bebida; some da lista quando a quantidade chega a zero
    function removerItem(nome) {
        var lista = [];
        for (var i = 0; i < selecionados.length; i++) {
            var item = selecionados[i];
            if (item.nome === nome) {
                if (item.quantidade > 1)
                    lista.push({
                        "nome": item.nome,
                        "valorNum": item.valorNum,
                        "quantidade": item.quantidade - 1
                    });

            } else {
                lista.push(item);
            }
        }
        selecionados = lista;
    }

    // Permite digitar direto na tela para pesquisar, sem precisar clicar
    // antes na barra de busca — qualquer tecla "imprimível" (letras,
    // números, acentos) foca a barra e já entra com o caractere digitado.
    Keys.onPressed: function (event) {
        if (!campoBusca.activeFocus && event.key >= Qt.Key_Space && event.key <= Qt.Key_ydiaeresis) {
            campoBusca.forceActiveFocus();
            campoBusca.text += event.text;
            event.accepted = true;
        }
    }

    Component.onCompleted: {
        carregarBebidas();
    }

    // Modelo base contendo as bebidas, carregado de data/cardapio/bebidas.json
    // (caminho absoluto a partir de "raizProjeto", exposto pelo main.py)
    ListModel {
        id: modeloBebidas
    }

    // Modelo auxiliar para exibir apenas os itens filtrados
    ListModel {
        id: modeloFiltrado
    }

    background: Rectangle {
        color: Estilo.global.background
        radius: Estilo.global.radius.xl
    }

    // Layout Principal
    // ===== MEDIDAS DO LAYOUT =====
    // Escolher itens (esquerda) e conferir o pedido (direita) eram 52% e 43%
    // da largura, sempre — o que em tela estreita virava duas colunas
    // apertadas demais para as duas coisas. Abaixo do ponto de virada elas
    // passam a ocupar a largura inteira, uma embaixo da outra, com a rolagem
    // do Flickable dando conta do resto. Mesmo padrão de Pizzas.qml.
    readonly property real larguraUtil: width - Estilo.global.padding.xl * 2
    readonly property real alturaUtil: height - Estilo.global.padding.xl * 2
    readonly property bool empilhado: larguraUtil < 760
    readonly property int larguraColunaEsquerda: empilhado ? larguraUtil : Math.round(larguraUtil * 0.545)
    readonly property int larguraColunaDireita: empilhado ? larguraUtil : larguraUtil - larguraColunaEsquerda - Estilo.global.spacing.xxl
    // Soma dos blocos de altura fixa da coluna direita mais o respiro entre
    // eles; o que sobra vai para a lista do pedido — e é isso que a mantém
    // com altura positiva mesmo numa janela baixa, onde a subtração crua
    // ficava negativa e o painel sumia.
    readonly property int alturaBlocosDireita: 210 + 65 + 46 + Estilo.global.spacing.lg * 3
    readonly property int alturaColunaDireita: empilhado ? alturaBlocosDireita + 180 : Math.max(alturaBlocosDireita + 120, alturaUtil)
    readonly property int alturaColunaEsquerda: empilhado ? Math.max(320, Math.round(alturaUtil * 0.7)) : alturaUtil

    // Layout Principal
    // Rola quando as duas colunas passam a ficar empilhadas (e, mesmo lado a
    // lado, quando a janela é baixa demais para a coluna direita inteira).
    Flickable {
        anchors.fill: parent
        anchors.margins: Estilo.global.padding.xl
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, gradePrincipal.implicitHeight)
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        GridLayout {
            id: gradePrincipal

            width: parent.width
            columns: telaBebidas.empilhado ? 1 : 2
            columnSpacing: Estilo.global.spacing.xxl
            rowSpacing: Estilo.global.spacing.xxl

            // ================= COLUNA DA ESQUERDA (Lista e Pesquisa) =================
            Column {
                Layout.preferredWidth: telaBebidas.larguraColunaEsquerda
                Layout.preferredHeight: telaBebidas.alturaColunaEsquerda
                Layout.alignment: Qt.AlignTop
                spacing: Estilo.global.spacing.lg

                Row {
                    spacing: Estilo.global.spacing.sm
                    Icone { nome: "fa6s.glass-water"; cor: Estilo.category.bebida.base; tamanho: Estilo.global.fontSize.title; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Escolha a(s) Bebida(s)"
                        font.pixelSize: Estilo.global.fontSize.title
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.category.bebida.base
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    text: totalItens === 0 ? "Nenhuma bebida selecionada" : totalItens + (totalItens === 1 ? " bebida selecionada" : " bebidas selecionadas")
                    font.pixelSize: Estilo.global.fontSize.lg
                    color: totalItens > 0 ? Estilo.category.bebida.strong : Estilo.global.textSecondary
                    font.bold: totalItens > 0
                }

                // BARRA DE PESQUISA
                Search {
                    id: campoBusca

                    width: parent.width
                    corDestaque: Estilo.category.bebida.base
                    placeholderText: "Pesquisar bebida (ex: coca, suco)..."
                    onTextChanged: {
                        filtrarBebidas(text);
                    }
                    // Enter com um só resultado na busca já adiciona essa bebida
                    // (mesmo efeito do botão "+") e limpa a busca.
                    onAccepted: {
                        if (modeloFiltrado.count === 1) {
                            var item = modeloFiltrado.get(0);
                            adicionarItem(item.nome, parseValor(precoEfetivo(item)));
                            campoBusca.text = "";
                        }
                    }
                }

                ListView {
                    id: listaBebidasView

                    width: parent.width
                    // O desconto é o que cabeçalho/busca/filtros ocupam acima
                    // dela; o piso evita que a lista suma numa janela baixa.
                    height: Math.max(160, parent.height - 110)
                    model: modeloFiltrado
                    spacing: Estilo.global.spacing.sm
                    clip: true

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AlwaysOn
                        active: true
                    }

                    // Cada item da lista tem um contador próprio (+ / -) em vez de
                    // um simples toggle, para permitir escolher a mesma bebida
                    // mais de uma vez sem reabrir esta tela.
                    delegate: Rectangle {
                        id: itemRow

                        property int quantidade: quantidadeDe(model.nome)

                        width: listaBebidasView.width - (listaBebidasView.ScrollBar.vertical.visible ? listaBebidasView.ScrollBar.vertical.width : 0)
                        height: 52
                        radius: Estilo.global.radius.md
                        color: quantidade > 0 ? Estilo.category.bebida.soft : Estilo.global.surface
                        border.color: quantidade > 0 ? Estilo.category.bebida.base : Estilo.global.border
                        border.width: quantidade > 0 ? 2 : 1

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            anchors.right: controles.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Estilo.global.spacing.md

                            Text {
                                text: model.nome
                                font.pixelSize: Estilo.global.fontSize.lg
                                font.bold: true
                                color: Estilo.global.text
                                width: parent.width - 90
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "R$ " + precoEfetivo(model)
                                font.pixelSize: Estilo.global.fontSize.lg
                                color: Estilo.action.confirm.base
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            id: controles

                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Estilo.global.spacing.xs

                            Button {
                                width: 26
                                height: 26
                                padding: 0
                                visible: itemRow.quantidade > 0
                                onClicked: removerItem(model.nome)

                                contentItem: Text {
                                    text: "−"
                                    color: Estilo.global.surface
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.sm
                                    color: parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                                }
                            }

                            Text {
                                text: itemRow.quantidade
                                visible: itemRow.quantidade > 0
                                font.bold: true
                                font.pixelSize: Estilo.global.fontSize.lg
                                color: Estilo.global.text
                                width: 16
                                horizontalAlignment: Text.AlignHCenter
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Button {
                                width: 26
                                height: 26
                                padding: 0
                                onClicked: adicionarItem(model.nome, parseValor(precoEfetivo(model)))

                                contentItem: Text {
                                    text: "+"
                                    color: Estilo.global.surface
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.sm
                                    color: parent.down ? Estilo.category.bebida.pressed : (parent.hovered ? Estilo.category.bebida.hover : Estilo.category.bebida.base)
                                }
                            }
                        }
                    }
                }
            }

            // ================= COLUNA DA DIREITA (Visualização, Legenda e Total) =================
            Column {
                Layout.preferredWidth: telaBebidas.larguraColunaDireita
                Layout.preferredHeight: telaBebidas.alturaColunaDireita
                Layout.alignment: Qt.AlignTop
                spacing: Estilo.global.spacing.lg

                // 1. Painel Visual
                Rectangle {
                    width: parent.width
                    height: 210
                    color: Estilo.global.surface
                    radius: Estilo.global.radius.lg
                    border.color: Estilo.global.borderCard

                    Column {
                        anchors.centerIn: parent
                        spacing: Estilo.global.spacing.md

                        Icone {
                            nome: "fa6s.glass-water"
                            cor: Estilo.category.bebida.base
                            tamanho: 90
                            anchors.horizontalCenter: parent.horizontalCenter
                            opacity: totalItens > 0 ? 1 : Estilo.global.opacity.muted
                        }

                        Text {
                            text: totalItens === 0 ? "Nenhuma bebida selecionada" : (totalItens === 1 ? selecionados[0].nome : totalItens + " bebidas selecionadas")
                            font.pixelSize: Estilo.global.fontSize.lg
                            font.bold: true
                            color: Estilo.global.text
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                // 2. Valor Total
                Rectangle {
                    width: parent.width
                    height: 65
                    color: Estilo.global.text
                    radius: Estilo.global.radius.lg

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Text {
                            text: "VALOR TOTAL"
                            color: Estilo.global.textDisabled
                            font.pixelSize: Estilo.global.fontSize.xs
                            font.bold: true
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "R$ " + valorAtual.toFixed(2).replace(".", ",")
                            color: Estilo.action.confirm.hover
                            font.pixelSize: Estilo.global.fontSize.xxl
                            font.bold: true
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                // 3. Pré-comanda: prévia do pedido que será enviado para
                // Balcao.qml/Entrega.qml, no mesmo formato de cartão usado pela
                // lista de comandas em Consulta.qml. Cada linha mostra a
                // quantidade escolhida daquela bebida.
                Rectangle {
                    width: parent.width
                    // O que sobra da coluna depois dos blocos de altura fixa
                    // (ver telaBebidas.alturaBlocosDireita).
                    height: Math.max(120, parent.height - telaBebidas.alturaBlocosDireita)
                    color: Estilo.global.surface
                    radius: Estilo.global.radius.lg
                    border.color: Estilo.global.borderCard
                    clip: true

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: Estilo.global.spacing.xs

                        Text {
                            text: "PRÉ-COMANDA"
                            font.pixelSize: Estilo.global.fontSize.xs
                            font.bold: true
                            color: Estilo.global.textSecondary
                        }

                        Text {
                            text: "Nenhuma bebida selecionada"
                            font.pixelSize: Estilo.global.fontSize.md
                            color: Estilo.global.textDisabled
                            font.italic: true
                            visible: selecionados.length === 0
                        }

                        Flickable {
                            width: parent.width
                            height: parent.height - 24
                            clip: true
                            contentHeight: colunaPreComanda.height
                            visible: selecionados.length > 0
                            boundsBehavior: Flickable.StopAtBounds

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }

                            Column {
                                id: colunaPreComanda

                                width: parent.width
                                spacing: Estilo.global.spacing.xs

                                Repeater {
                                    model: selecionados

                                    Rectangle {
                                        width: colunaPreComanda.width
                                        height: linhaPreComanda.implicitHeight + 16
                                        radius: Estilo.global.radius.md
                                        color: Estilo.global.background
                                        border.color: Estilo.global.borderCard

                                        Row {
                                            id: linhaPreComanda

                                            x: 8
                                            y: 8
                                            spacing: Estilo.global.spacing.sm
                                            width: parent.width - 16

                                            Text {
                                                text: "×" + modelData.quantidade
                                                font.pixelSize: Estilo.global.fontSize.sm
                                                font.bold: true
                                                color: Estilo.category.bebida.base
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Text {
                                                text: modelData.nome
                                                font.pixelSize: Estilo.global.fontSize.md
                                                font.bold: true
                                                color: Estilo.global.text
                                                width: parent.width - 130
                                                elide: Text.ElideRight
                                                anchors.verticalCenter: parent.verticalCenter
                                            }

                                            Text {
                                                text: "R$ " + (modelData.valorNum * modelData.quantidade).toFixed(2).replace(".", ",")
                                                font.pixelSize: Estilo.global.fontSize.sm
                                                color: Estilo.global.textSecondary
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 4. Botões de Ação
                Row {
                    width: parent.width
                    spacing: Estilo.global.spacing.lg

                    // BOTÃO VOLTAR
                    Button {
                        id: btnVoltar

                        width: (parent.width - parent.spacing) / 2
                        height: 46
                        onClicked: pilha.pop()

                        contentItem: Text {
                            text: "Voltar"
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.bold: true
                            color: Estilo.global.surface
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.md
                            color: btnVoltar.down ? Estilo.action.back.pressed : (btnVoltar.hovered ? Estilo.action.back.hover : Estilo.action.danger.base)
                            border.color: Estilo.action.back.pressed
                            border.width: Estilo.global.borderWidth.hairline
                        }
                    }

                    // BOTÃO CONFIRMAR
                    Button {
                        id: btnConfirmar

                        width: (parent.width - parent.spacing) / 2
                        height: 46
                        enabled: totalItens > 0
                        onClicked: {
                            if (totalItens === 0)
                                return ;

                            // Envia sempre um array de itens — uma linha de
                            // pedido por unidade — para que Balcao/Entrega tratem
                            // qualquer quantidade da mesma forma.
                            var itens = [];
                            for (var i = 0; i < selecionados.length; i++) {
                                var item = selecionados[i];
                                for (var q = 0; q < item.quantidade; q++) {
                                    itens.push({
                                        "nome": item.nome,
                                        "valor": "R$ " + item.valorNum.toFixed(2).replace(".", ","),
                                        "observacao": ""
                                    });
                                }
                            }
                            if (typeof onPedidoSelecionado === "function")
                                onPedidoSelecionado(itens);
                            pilha.pop(null);
                        }

                        contentItem: Text {
                            text: "Confirmar"
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.bold: true
                            color: Estilo.global.surface
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: btnConfirmar.enabled ? 1 : Estilo.global.opacity.subtle
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.md
                            color: !btnConfirmar.enabled ? Estilo.global.surfaceDisabled : (btnConfirmar.down ? Estilo.category.bebida.pressed : (btnConfirmar.hovered ? Estilo.category.bebida.hover : Estilo.category.bebida.base))
                            border.color: !btnConfirmar.enabled ? Estilo.global.surfaceDisabled : Estilo.category.bebida.pressed
                            border.width: Estilo.global.borderWidth.hairline
                        }
                    }
                }
            }
        }

    }
}
