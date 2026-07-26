import QtQuick
import QtQuick.Controls
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
        color: Estilo.cores.fundoPagina
        radius: Estilo.rounding.popup
    }

    // Layout Principal
    Row {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        // ================= COLUNA DA ESQUERDA (Lista e Pesquisa) =================
        Column {
            width: parent.width * 0.52
            height: parent.height
            spacing: 12

            Row {
                spacing: 8
                Icone { nome: "fa6s.glass-water"; cor: "#3498db"; tamanho: Estilo.fonte.titulo; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "Escolha a(s) Bebida(s)"
                    font.pixelSize: Estilo.fonte.titulo
                    font.bold: true
                    color: "#3498db"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                text: totalItens === 0 ? "Nenhuma bebida selecionada" : totalItens + (totalItens === 1 ? " bebida selecionada" : " bebidas selecionadas")
                font.pixelSize: Estilo.fonte.padrao
                color: totalItens > 0 ? "#2874a6" : Estilo.cores.textoSecundario
                font.bold: totalItens > 0
            }

            // BARRA DE PESQUISA
            Search {
                id: campoBusca

                width: parent.width
                corDestaque: "#3498db"
                placeholderText: "Pesquisar bebida (ex: coca, suco)..."
                onTextChanged: {
                    filtrarBebidas(text);
                }
                // Enter com um só resultado na busca já adiciona essa bebida
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
                id: listaBebidasView

                width: parent.width
                height: parent.height - 110
                model: modeloFiltrado
                spacing: 8
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
                    radius: Estilo.rounding.grande
                    color: quantidade > 0 ? "#d6eaf8" : "#ffffff"
                    border.color: quantidade > 0 ? "#3498db" : Estilo.cores.borda
                    border.width: quantidade > 0 ? 2 : 1

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: controles.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Text {
                            text: model.nome
                            font.pixelSize: Estilo.fonte.padrao
                            font.bold: true
                            color: Estilo.cores.texto
                            width: parent.width - 90
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "R$ " + model.valor
                            font.pixelSize: Estilo.fonte.padrao
                            color: Estilo.confirmar.normal
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        id: controles

                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Button {
                            width: 26
                            height: 26
                            padding: 0
                            visible: itemRow.quantidade > 0
                            onClicked: removerItem(model.nome)

                            contentItem: Text {
                                text: "−"
                                color: "#ffffff"
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                radius: 6
                                color: parent.down ? Estilo.cancelar.pressionado : (parent.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                            }
                        }

                        Text {
                            text: itemRow.quantidade
                            visible: itemRow.quantidade > 0
                            font.bold: true
                            font.pixelSize: Estilo.fonte.padrao
                            color: Estilo.cores.texto
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
                                color: "#ffffff"
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                radius: 6
                                color: parent.down ? "#21618c" : (parent.hovered ? "#5dade2" : "#3498db")
                            }
                        }
                    }
                }
            }
        }

        // ================= COLUNA DA DIREITA (Visualização, Legenda e Total) =================
        Column {
            width: parent.width * 0.43
            height: parent.height
            spacing: 12
            anchors.verticalCenter: parent.verticalCenter

            // 1. Painel Visual
            Rectangle {
                width: parent.width
                height: 210
                color: "#ffffff"
                radius: Estilo.rounding.painel
                border.color: Estilo.cores.bordaCard

                Column {
                    anchors.centerIn: parent
                    spacing: 10

                    Icone {
                        nome: "fa6s.glass-water"
                        cor: "#3498db"
                        tamanho: 90
                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: totalItens > 0 ? 1 : 0.35
                    }

                    Text {
                        text: totalItens === 0 ? "Nenhuma bebida selecionada" : (totalItens === 1 ? selecionados[0].nome : totalItens + " bebidas selecionadas")
                        font.pixelSize: Estilo.fonte.padrao
                        font.bold: true
                        color: Estilo.cores.texto
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            // 2. Valor Total
            Rectangle {
                width: parent.width
                height: 65
                color: Estilo.cores.texto
                radius: Estilo.rounding.medio

                Column {
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        text: "VALOR TOTAL"
                        color: "#bdc3c7"
                        font.pixelSize: 10
                        font.bold: true
                        anchors.horizontalCenter: parent
                    }

                    Text {
                        text: "R$ " + valorAtual.toFixed(2).replace(".", ",")
                        color: Estilo.confirmar.hover
                        font.pixelSize: 20
                        font.bold: true
                        anchors.horizontalCenter: parent
                    }
                }
            }

            // 3. Pré-comanda: prévia do pedido que será enviado para
            // Balcao.qml/Entrega.qml, no mesmo formato de cartão usado pela
            // lista de comandas em Consulta.qml. Cada linha mostra a
            // quantidade escolhida daquela bebida.
            Rectangle {
                width: parent.width
                height: parent.height - 210 - 65 - 46 - (12 * 3)
                color: "#ffffff"
                radius: Estilo.rounding.medio
                border.color: Estilo.cores.bordaCard
                clip: true

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Text {
                        text: "PRÉ-COMANDA"
                        font.pixelSize: 11
                        font.bold: true
                        color: Estilo.cores.textoSecundario
                    }

                    Text {
                        text: "Nenhuma bebida selecionada"
                        font.pixelSize: 13
                        color: "#bdc3c7"
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
                            spacing: 6

                            Repeater {
                                model: selecionados

                                Rectangle {
                                    width: colunaPreComanda.width
                                    height: linhaPreComanda.implicitHeight + 16
                                    radius: Estilo.rounding.grande
                                    color: Estilo.cores.fundoPagina
                                    border.color: Estilo.cores.bordaCard

                                    Row {
                                        id: linhaPreComanda

                                        x: 8
                                        y: 8
                                        spacing: 8
                                        width: parent.width - 16

                                        Text {
                                            text: "×" + modelData.quantidade
                                            font.pixelSize: 12
                                            font.bold: true
                                            color: "#3498db"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: modelData.nome
                                            font.pixelSize: 13
                                            font.bold: true
                                            color: Estilo.cores.texto
                                            width: parent.width - 130
                                            elide: Text.ElideRight
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: "R$ " + (modelData.valorNum * modelData.quantidade).toFixed(2).replace(".", ",")
                                            font.pixelSize: 12
                                            color: Estilo.cores.textoSecundario
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
                spacing: 12

                // BOTÃO VOLTAR
                Button {
                    id: btnVoltar

                    width: (parent.width - parent.spacing) / 2
                    height: 46
                    onClicked: pilha.pop()

                    contentItem: Text {
                        text: "Voltar"
                        font.pixelSize: 15
                        font.bold: true
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.grande
                        color: btnVoltar.down ? Estilo.voltar.pressionado : (btnVoltar.hovered ? Estilo.voltar.hover : Estilo.cancelar.normal)
                        border.color: Estilo.voltar.pressionado
                        border.width: 1
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
                        font.pixelSize: 15
                        font.bold: true
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        opacity: btnConfirmar.enabled ? 1 : 0.6
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.grande
                        color: !btnConfirmar.enabled ? "#bdc3c7" : (btnConfirmar.down ? "#21618c" : (btnConfirmar.hovered ? "#5dade2" : "#3498db"))
                        border.color: !btnConfirmar.enabled ? "#bdc3c7" : "#21618c"
                        border.width: 1
                    }
                }
            }
        }
    }
}
