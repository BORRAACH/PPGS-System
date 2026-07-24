import QtQuick
import QtQuick.Controls
import estilo 1.0

Page {
    // 2. Atualiza os preços internos das pizzas já selecionadas para o novo tamanho

    id: telaPizzas

    property var onPedidoSelecionado: null
    property var pilha: null
    // Sabores escolhidos para a pizza que está sendo montada agora
    property var selecionados: []
    // Pizzas já fechadas nesta visita (cada uma com seus sabores e tamanho
    // próprios) — permite montar mais de uma pizza sem sair desta tela.
    // Cada item: { sabores: [...], tamanho: "Grande", valorNum: 45.0 }
    property var pizzasMontadas: []
    // Tamanho atualmente selecionado: "Grande", "Broto" ou "Mini"
    property string tamanhoSelecionado: "Grande"
    // Propriedade computada para o limite de sabores com base no tamanho
    readonly property int limiteSabores: tamanhoSelecionado === "Grande" ? 3 : 2
    // Propriedade computada para calcular o valor mais alto em tempo real
    readonly property real valorAtualMaior: {
        var maior = 0;
        for (var i = 0; i < selecionados.length; i++) {
            if (selecionados[i].valorNum > maior)
                maior = selecionados[i].valorNum;

        }
        return maior;
    }
    // Valor total do pedido: soma as pizzas já adicionadas + a pizza em
    // andamento (mesmo antes de clicar em "Adicionar Pizza").
    readonly property real valorTotalPedido: {
        var soma = 0;
        for (var i = 0; i < pizzasMontadas.length; i++) {
            soma += pizzasMontadas[i].valorNum;
        }
        return soma + valorAtualMaior;
    }

    // Fecha a pizza em andamento (sabores + tamanho atuais) e a guarda em
    // pizzasMontadas, liberando a seleção de sabores para montar a próxima
    // pizza sem precisar reabrir esta tela.
    function adicionarPizzaAtual() {
        if (selecionados.length === 0)
            return ;

        var lista = pizzasMontadas.slice();
        lista.push({
            "sabores": selecionados.slice(),
            "tamanho": tamanhoSelecionado,
            "valorNum": valorAtualMaior
        });
        pizzasMontadas = lista;
        selecionados = [];
    }

    function removerPizzaMontada(indice) {
        var lista = pizzasMontadas.slice();
        lista.splice(indice, 1);
        pizzasMontadas = lista;
    }

    function carregarPizzas() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(raizProjeto + "data/cardapio/pizzas.json"));
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var dados = JSON.parse(xhr.responseText);
                        modeloPizzas.clear();
                        for (var i = 0; i < dados.length; i++) {
                            modeloPizzas.append(dados[i]);
                        }
                        console.log("Pizzas carregadas:", modeloPizzas.count);
                        filtrarPizzas("");
                    } catch (e) {
                        console.error("Erro ao interpretar JSON:", e);
                    }
                } else {
                    console.error("Erro ao carregar pizzas.json, status:", xhr.status);
                }
            }
        };
        xhr.send();
    }

    function filtrarPizzas(texto) {
        modeloFiltrado.clear();
        var busca = texto ? texto.trim().toLowerCase() : "";
        // Verifica rigorosamente se a quantidade atual atingiu o limite permitido pelo tamanho
        var limiteAtingido = (selecionados.length >= limiteSabores);
        var resultados = [];
        for (var i = 0; i < modeloPizzas.count; i++) {
            var item = modeloPizzas.get(i);
            var nomeLower = item.nome.toLowerCase();
            var selecionado = isSelecionado(item.nome);
            // Se o limite foi atingido, exibe APENAS os itens já selecionados.
            // Se ainda HÁ ESPAÇO (ex: 2 selecionados num limite de 3), exibe todos os disponíveis!
            if (limiteAtingido && !selecionado)
                continue;

            // Seleciona o valor correspondente ao tamanho ativo
            var valorExibicao = item.valorGrande;
            if (tamanhoSelecionado === "Broto")
                valorExibicao = item.valorBroto;
            else if (tamanhoSelecionado === "Mini")
                valorExibicao = item.valorMini;
            if (busca === "" || nomeLower.indexOf(busca) !== -1)
                resultados.push({
                    "nome": item.nome,
                    "valor": valorExibicao,
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

    // Função para atualizar o valorNum dos itens já selecionados quando troca de tamanho
    function reatualizarPrecosSelecionados() {
        var novaLista = [];
        for (var i = 0; i < selecionados.length; i++) {
            var nome = selecionados[i].nome;
            for (var j = 0; j < modeloPizzas.count; j++) {
                var p = modeloPizzas.get(j);
                if (p.nome === nome) {
                    var strVal = p.valorGrande;
                    if (tamanhoSelecionado === "Broto")
                        strVal = p.valorBroto;
                    else if (tamanhoSelecionado === "Mini")
                        strVal = p.valorMini;
                    novaLista.push({
                        "nome": nome,
                        "valorNum": parseValor(strVal)
                    });
                    break;
                }
            }
        }
        selecionados = novaLista;
    }

    function parseValor(strValor) {
        return parseFloat(strValor.replace(",", "."));
    }

    function isSelecionado(nome) {
        return selecionados.some(function(item) {
            return item.nome === nome;
        });
    }

    Component.onCompleted: {
        carregarPizzas();
    }
    onSelecionadosChanged: {
        filtrarPizzas(campoBusca.text);
    }
    onTamanhoSelecionadoChanged: {
        // 1. Caso o novo limite seja menor do que o número de pizzas selecionadas, corta a lista
        if (selecionados.length > limiteSabores)
            selecionados = selecionados.slice(0, limiteSabores);
        else
            reatualizarPrecosSelecionados();
        // 3. Força a atualização da lista exibida considerando o novo limite e tamanho
        filtrarPizzas(campoBusca.text);
    }

    // Modelo base contendo os sabores, carregado de data/cardapio/pizzas.json
    // (caminho absoluto a partir de "raizProjeto", exposto pelo main.py)
    ListModel {
        id: modeloPizzas
    }

    // Modelo auxiliar para exibir apenas os itens filtrados
    ListModel {
        id: modeloFiltrado
    }

    // Layout Principal
    Row {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20

        // ================= COLUNA DA ESQUERDA (Lista, Tamanho e Pesquisa) =================
        Column {
            width: parent.width * 0.52
            height: parent.height
            spacing: 12

            Text {
                text: "🍕 Escolha até " + limiteSabores + (limiteSabores === 1 ? " Sabor" : " Sabores")
                font.pixelSize: Estilo.fonte.titulo
                font.bold: true
                color: Estilo.cancelar.normal
            }

            Text {
                text: selecionados.length === limiteSabores ? "⚠️ Limite máximo de " + limiteSabores + " sabores atingido!" : selecionados.length + " de " + limiteSabores + " sabores selecionados"
                font.pixelSize: Estilo.fonte.padrao
                color: selecionados.length === limiteSabores ? "#d32f2f" : Estilo.cores.textoSecundario
                font.bold: selecionados.length > 0
            }

            // BARRA DE PESQUISA
            TextField {
                id: campoBusca

                width: parent.width
                height: 42
                placeholderText: "🔍 Pesquisar sabor (ex: calabresa, chocolate)..."
                placeholderTextColor: "#95a5a6"
                font.pixelSize: Estilo.fonte.padrao
                leftPadding: 14
                rightPadding: 14
                color: Estilo.cores.texto
                selectByMouse: true
                enabled: selecionados.length < limiteSabores
                onTextChanged: {
                    filtrarPizzas(text);
                }

                background: Rectangle {
                    radius: Estilo.rounding.grande
                    color: campoBusca.enabled ? "#ffffff" : "#f0f0f0"
                    border.color: campoBusca.activeFocus ? Estilo.cancelar.normal : Estilo.cores.borda
                    border.width: campoBusca.activeFocus ? 2 : 1
                }

            }

            // SELEÇÃO DE TAMANHO (3 Opções Exclusivas com fallback para Grande)
            Rectangle {
                width: parent.width
                height: 50
                color: "#ffffff"
                radius: Estilo.rounding.grande
                border.color: Estilo.cores.borda

                Row {
                    anchors.centerIn: parent
                    spacing: 18

                    Text {
                        text: "Tamanho:"
                        font.pixelSize: Estilo.fonte.padrao
                        font.bold: true
                        color: Estilo.cores.texto
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // --- CHECKBOX GRANDE ---
                    CheckBox {
                        id: chkGrande

                        text: "Grande"
                        checked: tamanhoSelecionado === "Grande"
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: true
                        onClicked: {
                            tamanhoSelecionado = "Grande";
                        }

                        contentItem: Text {
                            text: chkGrande.text
                            font.pixelSize: Estilo.fonte.padrao
                            font.bold: true
                            color: Estilo.cores.texto
                            leftPadding: chkGrande.indicator.width + chkGrande.spacing
                            verticalAlignment: Text.AlignVCenter
                        }

                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: chkGrande.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 4
                            border.color: chkGrande.checked ? Estilo.confirmar.normal : "#bdc3c7"
                            border.width: 2
                            color: chkGrande.checked ? Estilo.confirmar.normal : "transparent"

                            Text {
                                text: "✓"
                                color: "white"
                                font.bold: true
                                font.pixelSize: 12
                                anchors.centerIn: parent
                                visible: chkGrande.checked
                            }

                        }

                    }

                    // --- CHECKBOX BROTO ---
                    CheckBox {
                        id: chkBroto

                        text: "Broto"
                        checked: tamanhoSelecionado === "Broto"
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: selecionados.length <= 2
                        onClicked: {
                            if (checked)
                                tamanhoSelecionado = "Broto";
                            else
                                tamanhoSelecionado = "Grande";
                        }

                        contentItem: Text {
                            text: chkBroto.text
                            font.pixelSize: Estilo.fonte.padrao
                            font.bold: true
                            color: chkBroto.enabled ? Estilo.cores.texto : "#bdc3c7"
                            leftPadding: chkBroto.indicator.width + chkBroto.spacing
                            verticalAlignment: Text.AlignVCenter
                        }

                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: chkBroto.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 4
                            border.color: chkBroto.enabled ? (chkBroto.checked ? Estilo.confirmar.normal : "#bdc3c7") : Estilo.cores.bordaCard
                            border.width: 2
                            color: chkBroto.enabled ? (chkBroto.checked ? Estilo.confirmar.normal : "transparent") : "#f0f0f0"

                            Text {
                                text: "✓"
                                color: "white"
                                font.bold: true
                                font.pixelSize: 12
                                anchors.centerIn: parent
                                visible: chkBroto.checked
                            }

                        }

                    }

                    // --- CHECKBOX MINI ---
                    CheckBox {
                        id: chkMini

                        text: "Mini"
                        checked: tamanhoSelecionado === "Mini"
                        anchors.verticalCenter: parent.verticalCenter
                        enabled: selecionados.length <= 2
                        onClicked: {
                            if (checked)
                                tamanhoSelecionado = "Mini";
                            else
                                tamanhoSelecionado = "Grande";
                        }

                        contentItem: Text {
                            text: chkMini.text
                            font.pixelSize: Estilo.fonte.padrao
                            font.bold: true
                            color: chkMini.enabled ? Estilo.cores.texto : "#bdc3c7"
                            leftPadding: chkMini.indicator.width + chkMini.spacing
                            verticalAlignment: Text.AlignVCenter
                        }

                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: chkMini.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 4
                            border.color: chkMini.enabled ? (chkMini.checked ? Estilo.confirmar.normal : "#bdc3c7") : Estilo.cores.bordaCard
                            border.width: 2
                            color: chkMini.enabled ? (chkMini.checked ? Estilo.confirmar.normal : "transparent") : "#f0f0f0"

                            Text {
                                text: "✓"
                                color: "white"
                                font.bold: true
                                font.pixelSize: 12
                                anchors.centerIn: parent
                                visible: chkMini.checked
                            }

                        }

                    }

                }

            }

            ListView {
                id: listaPizzasView

                width: parent.width
                height: parent.height - 225
                model: modeloFiltrado
                spacing: 8
                clip: true

                // 1. Adiciona a barra de rolagem à direita da lista
                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOn
                    active: true
                }

                delegate: Button {
                    id: btnItem

                    property bool checado: isSelecionado(model.nome)

                    // 2. Subtrai a largura da ScrollBar (aprox. 12px) para o botão não ficar embaixo dela
                    width: listaPizzasView.width - (listaPizzasView.ScrollBar.vertical.visible ? listaPizzasView.ScrollBar.vertical.width : 0)
                    padding: 10
                    onClicked: {
                        var listaTemp = selecionados.slice();
                        if (checado) {
                            listaTemp = listaTemp.filter(function(item) {
                                return item.nome !== model.nome;
                            });
                        } else {
                            if (listaTemp.length < limiteSabores)
                                listaTemp.push({
                                    "nome": model.nome,
                                    "valorNum": parseValor(model.valor)
                                });

                        }
                        selecionados = listaTemp;
                    }

                    contentItem: Row {
                        spacing: 10

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 4
                            border.color: btnItem.checado ? Estilo.confirmar.normal : "#bdc3c7"
                            border.width: 2
                            color: btnItem.checado ? Estilo.confirmar.normal : "transparent"
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                text: "✓"
                                color: "white"
                                font.bold: true
                                anchors.centerIn: parent
                                visible: btnItem.checado
                            }

                        }

                        Text {
                            text: model.nome
                            font.pixelSize: Estilo.fonte.padrao
                            font.bold: true
                            color: Estilo.cores.texto
                            // Ajuste proporcional para não encostar nos preços
                            width: parent.width - 120
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

                    background: Rectangle {
                        radius: Estilo.rounding.grande
                        color: btnItem.checado ? "#d5f5e3" : (btnItem.down ? Estilo.cores.bordaCard : (btnItem.hovered ? "#f1f1f1" : "#ffffff"))
                        border.color: btnItem.checado ? Estilo.confirmar.normal : Estilo.cores.borda
                        border.width: btnItem.checado ? 2 : 1
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

            // 1. Painel da Pizza Visual
            Rectangle {
                width: parent.width
                height: 210
                color: "#ffffff"
                radius: Estilo.rounding.painel
                border.color: Estilo.cores.bordaCard

                Canvas {
                    id: canvasPizza

                    width: 160
                    height: 160
                    anchors.centerIn: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        var centroX = width / 2;
                        var centroY = height / 2;
                        var raio = width / 2 - 5;
                        // Massa e Borda
                        ctx.beginPath();
                        ctx.arc(centroX, centroY, raio, 0, 2 * Math.PI);
                        ctx.fillStyle = "#f39c12";
                        ctx.fill();
                        ctx.lineWidth = 6;
                        ctx.strokeStyle = "#d35400";
                        ctx.stroke();
                        var qtd = selecionados.length;
                        if (qtd === 0)
                            return ;

                        var anguloFatia = (2 * Math.PI) / qtd;
                        for (var i = 0; i < qtd; i++) {
                            var inicio = i * anguloFatia - (Math.PI / 2);
                            if (qtd > 1) {
                                ctx.beginPath();
                                ctx.moveTo(centroX, centroY);
                                ctx.lineTo(centroX + raio * Math.cos(inicio), centroY + raio * Math.sin(inicio));
                                ctx.lineWidth = 2;
                                ctx.strokeStyle = "#ffffff";
                                ctx.stroke();
                            }
                            var anguloMeio = inicio + (anguloFatia / 2);
                            var distTexto = raio * 0.55;
                            var posX = centroX + distTexto * Math.cos(anguloMeio);
                            var posY = centroY + distTexto * Math.sin(anguloMeio);
                            ctx.font = "bold 18px sans-serif";
                            ctx.fillStyle = "#ffffff";
                            ctx.textAlign = "center";
                            ctx.textBaseline = "middle";
                            ctx.fillText((i + 1).toString(), posX, posY);
                        }
                    }

                    Connections {
                        function onSelecionadosChanged() {
                            canvasPizza.requestPaint();
                        }

                        target: telaPizzas
                    }

                }

            }

            // 2. Legenda dos Sabores
            Rectangle {
                width: parent.width
                height: 110
                color: "#ffffff"
                radius: Estilo.rounding.medio
                border.color: Estilo.cores.bordaCard
                clip: true

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Text {
                        text: "LEGENDA (" + tamanhoSelecionado.toUpperCase() + ")"
                        font.pixelSize: 11
                        font.bold: true
                        color: Estilo.cores.textoSecundario
                    }

                    Text {
                        text: "Nenhum sabor selecionado"
                        font.pixelSize: 13
                        color: "#bdc3c7"
                        font.italic: true
                        visible: selecionados.length === 0
                    }

                    Repeater {
                        model: selecionados

                        Row {
                            spacing: 10
                            width: parent.width

                            Rectangle {
                                width: 18
                                height: 18
                                radius: 9
                                color: Estilo.cancelar.normal
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    text: index + 1
                                    color: "#ffffff"
                                    font.pixelSize: 11
                                    font.bold: true
                                    anchors.centerIn: parent
                                }

                            }

                            Text {
                                text: modelData.nome
                                font.pixelSize: 13
                                font.bold: true
                                color: Estilo.cores.texto
                                width: parent.width - 100
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "R$ " + modelData.valorNum.toFixed(2).replace(".", ",")
                                font.pixelSize: 12
                                color: Estilo.cores.textoSecundario
                                anchors.verticalCenter: parent.verticalCenter
                            }

                        }

                    }

                }

            }

            // 3. Botão para fechar a pizza atual e começar a próxima, sem
            // sair desta tela — é isso que permite montar mais de uma pizza
            // de uma vez.
            Button {
                id: btnAdicionarPizza

                width: parent.width
                height: 42
                enabled: selecionados.length > 0
                onClicked: adicionarPizzaAtual()

                contentItem: Text {
                    text: "➕ Adicionar Pizza (" + tamanhoSelecionado + ")"
                    font.pixelSize: 14
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    opacity: btnAdicionarPizza.enabled ? 1 : 0.6
                }

                background: Rectangle {
                    radius: Estilo.rounding.grande
                    color: !btnAdicionarPizza.enabled ? "#bdc3c7" : (btnAdicionarPizza.down ? "#219150" : (btnAdicionarPizza.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal))
                    border.color: !btnAdicionarPizza.enabled ? "#bdc3c7" : "#219150"
                    border.width: 1
                }
            }

            // 4. Pizzas já adicionadas ao pedido — cada uma pode ser
            // removida individualmente antes de confirmar.
            Rectangle {
                width: parent.width
                height: parent.height - 210 - 110 - 42 - 65 - 46 - (12 * 5)
                color: "#ffffff"
                radius: Estilo.rounding.medio
                border.color: Estilo.cores.bordaCard
                clip: true

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Text {
                        text: "PIZZAS ADICIONADAS"
                        font.pixelSize: 11
                        font.bold: true
                        color: Estilo.cores.textoSecundario
                    }

                    Text {
                        text: "Nenhuma pizza adicionada ainda"
                        font.pixelSize: 13
                        color: "#bdc3c7"
                        font.italic: true
                        visible: pizzasMontadas.length === 0
                    }

                    Flickable {
                        width: parent.width
                        height: parent.height - 24
                        clip: true
                        contentHeight: colunaPizzasMontadas.height
                        visible: pizzasMontadas.length > 0
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        Column {
                            id: colunaPizzasMontadas

                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: pizzasMontadas

                                Rectangle {
                                    width: colunaPizzasMontadas.width
                                    height: linhaPizzaMontada.implicitHeight + 16
                                    radius: Estilo.rounding.grande
                                    color: Estilo.cores.fundoPagina
                                    border.color: Estilo.cores.bordaCard

                                    Row {
                                        id: linhaPizzaMontada

                                        x: 8
                                        y: 8
                                        spacing: 8
                                        width: parent.width - 16

                                        Rectangle {
                                            radius: 6
                                            width: textoBadgeTamanho.implicitWidth + 14
                                            height: textoBadgeTamanho.implicitHeight + 6
                                            color: Estilo.cancelar.normal
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                id: textoBadgeTamanho

                                                text: modelData.tamanho
                                                color: "#ffffff"
                                                font.bold: true
                                                font.pixelSize: 10
                                                anchors.centerIn: parent
                                            }
                                        }

                                        Text {
                                            text: modelData.sabores.map(function(s) {
                                                return s.nome;
                                            }).join(" / ")
                                            font.pixelSize: 13
                                            font.bold: true
                                            color: Estilo.cores.texto
                                            width: parent.width - 200
                                            elide: Text.ElideRight
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: "R$ " + modelData.valorNum.toFixed(2).replace(".", ",")
                                            font.pixelSize: 12
                                            color: Estilo.cores.textoSecundario
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Button {
                                            width: 22
                                            height: 22
                                            padding: 0
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: removerPizzaMontada(index)

                                            contentItem: Text {
                                                text: "×"
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
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 5. Valor Total
            Rectangle {
                width: parent.width
                height: 65
                color: Estilo.cores.texto
                radius: Estilo.rounding.medio

                Column {
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        text: "VALOR TOTAL DO PEDIDO"
                        color: "#bdc3c7"
                        font.pixelSize: 10
                        font.bold: true
                        anchors.horizontalCenter: parent
                    }

                    Text {
                        text: "R$ " + valorTotalPedido.toFixed(2).replace(".", ",")
                        color: Estilo.confirmar.hover
                        font.pixelSize: 20
                        font.bold: true
                        anchors.horizontalCenter: parent
                    }

                }

            }

            // 6. Botões de Ação
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
                    enabled: pizzasMontadas.length > 0 || selecionados.length > 0
                    // BOTÃO CONFIRMAR: junta as pizzas já adicionadas com a
                    // pizza em andamento (se houver) e envia tudo de uma vez.
                    onClicked: {
                        var listaFinal = pizzasMontadas.slice();
                        if (selecionados.length > 0) {
                            listaFinal.push({
                                "sabores": selecionados.slice(),
                                "tamanho": tamanhoSelecionado,
                                "valorNum": valorAtualMaior
                            });
                        }
                        if (listaFinal.length === 0)
                            return ;

                        var itens = listaFinal.map(function(pizza) {
                            var nomesArray = pizza.sabores.map(function(item) {
                                return item.nome;
                            });
                            return {
                                "nome": nomesArray.join(" / ") + " (" + pizza.tamanho + ")",
                                "valor": "R$ " + pizza.valorNum.toFixed(2).replace(".", ","),
                                "observacao": ""
                            };
                        });
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
                        color: !btnConfirmar.enabled ? "#bdc3c7" : (btnConfirmar.down ? "#219150" : (btnConfirmar.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal))
                        border.color: !btnConfirmar.enabled ? "#bdc3c7" : "#219150"
                        border.width: 1
                    }

                }

            }

        }

    }

    background: Rectangle {
        color: Estilo.cores.fundoPagina
        radius: Estilo.rounding.popup
    }

}
