import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../../components"
import "../../../components/Texto.js" as Texto
import "../MontagemItem.js" as Montagem

Page {
    id: telaOutros

    focus: true
    // "focus: true" sozinho não é suficiente: StackView assume o controle do
    // foco ao trocar de página, então é preciso pedir foco de novo quando
    // esta página vira a atual (senão digitar sem clicar antes não funciona).
    StackView.onActivated: forceActiveFocus()

    property var onPedidoSelecionado: null
    property var pilha: null
    // Lista para guardar os itens selecionados — cada entrada é única por
    // nome e guarda a quantidade escolhida, permitindo pedir o mesmo item
    // mais de uma vez (ex: 2 chocolates) sem reabrir esta tela.
    property var selecionados: []
    // Soma das quantidades de todos os itens (usado nos textos de resumo)
    readonly property int totalItens: {
        var soma = 0;
        for (var i = 0; i < selecionados.length; i++) {
            soma += selecionados[i].quantidade;
        }
        return soma;
    }
    // Propriedade computada para o valor somado de todos os itens selecionados
    readonly property real valorAtual: {
        var soma = 0;
        for (var i = 0; i < selecionados.length; i++) {
            soma += selecionados[i].valorNum * selecionados[i].quantidade;
        }
        return soma;
    }

    function carregarOutros() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(raizProjeto + "data/cardapio/outros.json"));
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var dados = JSON.parse(xhr.responseText);
                        modeloOutros.clear();
                        for (var i = 0; i < dados.length; i++) {
                            modeloOutros.append(dados[i]);
                        }
                        console.log("Itens carregados:", modeloOutros.count);
                        filtrarOutros("");
                    } catch (e) {
                        console.error("Erro ao interpretar JSON:", e);
                    }
                } else {
                    console.error("Erro ao carregar outros.json, status:", xhr.status);
                }
            }
        };
        xhr.send();
    }

    function filtrarOutros(texto) {
        modeloFiltrado.clear();
        var busca = texto ? Texto.normalizar(texto.trim()) : "";
        var resultados = [];
        for (var i = 0; i < modeloOutros.count; i++) {
            var item = modeloOutros.get(i);
            var nomeLower = Texto.normalizar(item.nome);
            if (busca === "" || nomeLower.indexOf(busca) !== -1)
                resultados.push({
                    "nome": item.nome,
                    "valor": item.valor,
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
                "valor": resultados[j].valor
            });
        }
    }

    function parseValor(strValor) {
        return parseFloat(strValor.replace(",", "."));
    }

    // Quantidade atualmente escolhida de um item (0 se não selecionado)
    function quantidadeDe(nome) {
        for (var i = 0; i < selecionados.length; i++) {
            if (selecionados[i].nome === nome)
                return selecionados[i].quantidade;
        }
        return 0;
    }

    // Adiciona mais uma unidade do item (nova entrada se ainda não escolhido)
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

    // Remove uma unidade do item; some da lista quando a quantidade chega a zero
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

    // Ler o JSON do cardápio, interpretar e preencher o ListModel roda antes
    // do primeiro pixel se ficar solto em Component.onCompleted — nesta tela
    // isso é a diferença entre o popup de categoria fechar na hora e o app
    // parecer engasgado no clique (ver components/CargaDiferida.qml).
    CargaDiferida {
        id: carga

        tarefa: function() {
            carregarOutros();
        }
    }

    Component.onCompleted: carga.agendar()

    // Modelo base contendo os itens, carregado de data/cardapio/outros.json
    // (caminho absoluto a partir de "raizProjeto", exposto pelo main.py)
    ListModel {
        id: modeloOutros
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
            columns: telaOutros.empilhado ? 1 : 2
            columnSpacing: Estilo.global.spacing.xxl
            rowSpacing: Estilo.global.spacing.xxl

            // ================= COLUNA DA ESQUERDA (Lista e Pesquisa) =================
            Column {
                Layout.preferredWidth: telaOutros.larguraColunaEsquerda
                Layout.preferredHeight: telaOutros.alturaColunaEsquerda
                Layout.alignment: Qt.AlignTop
                spacing: Estilo.global.spacing.lg

                Row {
                    spacing: Estilo.global.spacing.sm
                    Icone { nome: "fa6s.box"; cor: Estilo.category.outros.base; tamanho: Estilo.global.fontSize.title; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Escolha o(s) Item(ns)"
                        font.pixelSize: Estilo.global.fontSize.title
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.category.outros.base
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    text: totalItens === 0 ? "Nenhum item selecionado" : totalItens + (totalItens === 1 ? " item selecionado" : " itens selecionados")
                    font.pixelSize: Estilo.global.fontSize.lg
                    color: totalItens > 0 ? Estilo.category.outros.pressed : Estilo.global.textSecondary
                    font.bold: totalItens > 0
                }

                // BARRA DE PESQUISA
                Search {
                    id: campoBusca

                    width: parent.width
                    corDestaque: Estilo.category.outros.base
                    placeholderText: "Pesquisar item (ex: chocolate, trufa)..."
                    onTextChanged: {
                        filtrarOutros(text);
                    }
                    // Enter com um só resultado na busca já adiciona esse item
                    // (mesmo efeito do botão "+") e limpa a busca.
                    onAccepted: {
                        if (modeloFiltrado.count === 1) {
                            var item = modeloFiltrado.get(0);
                            adicionarItem(item.nome, parseValor(item.valor));
                            campoBusca.text = "";
                        }
                    }
                }

                ListView {
                    id: listaOutrosView

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
                    // um simples toggle, para permitir escolher o mesmo item mais
                    // de uma vez sem reabrir esta tela.
                    delegate: Rectangle {
                        id: itemRow

                        property int quantidade: quantidadeDe(model.nome)

                        width: listaOutrosView.width - (listaOutrosView.ScrollBar.vertical.visible ? listaOutrosView.ScrollBar.vertical.width : 0)
                        height: 52
                        radius: Estilo.global.radius.md
                        color: quantidade > 0 ? Estilo.category.outros.soft : Estilo.global.surface
                        border.color: quantidade > 0 ? Estilo.category.outros.base : Estilo.global.border
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
                                text: "R$ " + model.valor
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
                                    font.family: Estilo.global.fontFamily.title
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
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
                                onClicked: adicionarItem(model.nome, parseValor(model.valor))

                                contentItem: Text {
                                    text: "+"
                                    color: Estilo.global.surface
                                    font.family: Estilo.global.fontFamily.title
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.category.outros.pressed : (parent.hovered ? Estilo.category.outros.hover : Estilo.category.outros.base)
                                }
                            }
                        }
                    }
                }
            }

            // ================= COLUNA DA DIREITA (Visualização, Legenda e Total) =================
            Column {
                Layout.preferredWidth: telaOutros.larguraColunaDireita
                Layout.preferredHeight: telaOutros.alturaColunaDireita
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
                            nome: "fa6s.box"
                            cor: Estilo.category.outros.base
                            tamanho: 90
                            anchors.horizontalCenter: parent.horizontalCenter
                            opacity: totalItens > 0 ? 1 : Estilo.global.opacity.muted
                        }

                        Text {
                            text: totalItens === 0 ? "Nenhum item selecionado" : (totalItens === 1 ? selecionados[0].nome : totalItens + " itens selecionados")
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
                // quantidade escolhida daquele item.
                Rectangle {
                    width: parent.width
                    // O que sobra da coluna depois dos blocos de altura fixa
                    // (ver telaOutros.alturaBlocosDireita).
                    height: Math.max(120, parent.height - telaOutros.alturaBlocosDireita)
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
                            text: "Nenhum item selecionado"
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
                                                color: Estilo.category.outros.base
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
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.surface
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
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
                                // A montagem do nome/valor mora em
                                // ../MontagemItem.js (ver o comentário
                                // equivalente em pizzas/Pizzas.qml).
                                for (var q = 0; q < item.quantidade; q++)
                                    itens.push(Montagem.montarSimples(item));
                            }
                            if (typeof onPedidoSelecionado === "function")
                                onPedidoSelecionado(itens);
                            pilha.pop(null);
                        }

                        contentItem: Text {
                            text: "Confirmar"
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.surface
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: btnConfirmar.enabled ? 1 : Estilo.global.opacity.subtle
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
                            color: !btnConfirmar.enabled ? Estilo.global.surfaceDisabled : (btnConfirmar.down ? Estilo.category.outros.pressed : (btnConfirmar.hovered ? Estilo.category.outros.hover : Estilo.category.outros.base))
                            border.color: !btnConfirmar.enabled ? Estilo.global.surfaceDisabled : Estilo.category.outros.pressed
                            border.width: Estilo.global.borderWidth.hairline
                        }
                    }
                }
            }
        }

    }
}
