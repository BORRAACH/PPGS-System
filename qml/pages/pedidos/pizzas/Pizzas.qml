import QtQuick
import QtQuick.Controls

Page {
    // 2. Atualiza os preços internos das pizzas já selecionadas para o novo tamanho

    id: telaPizzas

    property var onPedidoSelecionado: null
    property var pilha: null
    // Lista para guardar os objetos das pizzas selecionadas
    property var selecionados: []
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

    function carregarPizzas() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("pizzas.json"));
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

    // Modelo base contendo os sabores, carregado do pizzas.json na mesma pasta do .qml
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
                font.pixelSize: 22
                font.bold: true
                color: "#e74c3c"
            }

            Text {
                text: selecionados.length === limiteSabores ? "⚠️ Limite máximo de " + limiteSabores + " sabores atingido!" : selecionados.length + " de " + limiteSabores + " sabores selecionados"
                font.pixelSize: 14
                color: selecionados.length === limiteSabores ? "#d32f2f" : "#7f8c8d"
                font.bold: selecionados.length > 0
            }

            // BARRA DE PESQUISA
            TextField {
                id: campoBusca

                width: parent.width
                height: 42
                placeholderText: "🔍 Pesquisar sabor (ex: calabresa, chocolate)..."
                placeholderTextColor: "#95a5a6"
                font.pixelSize: 14
                leftPadding: 14
                rightPadding: 14
                color: "#2c3e50"
                selectByMouse: true
                enabled: selecionados.length < limiteSabores
                onTextChanged: {
                    filtrarPizzas(text);
                }

                background: Rectangle {
                    radius: 8
                    color: campoBusca.enabled ? "#ffffff" : "#f0f0f0"
                    border.color: campoBusca.activeFocus ? "#e74c3c" : "#cccccc"
                    border.width: campoBusca.activeFocus ? 2 : 1
                }

            }

            // SELEÇÃO DE TAMANHO (3 Opções Exclusivas com fallback para Grande)
            Rectangle {
                width: parent.width
                height: 50
                color: "#ffffff"
                radius: 8
                border.color: "#cccccc"

                Row {
                    anchors.centerIn: parent
                    spacing: 18

                    Text {
                        text: "Tamanho:"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#2c3e50"
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
                            font.pixelSize: 14
                            font.bold: true
                            color: "#2c3e50"
                            leftPadding: chkGrande.indicator.width + chkGrande.spacing
                            verticalAlignment: Text.AlignVCenter
                        }

                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: chkGrande.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 4
                            border.color: chkGrande.checked ? "#27ae60" : "#bdc3c7"
                            border.width: 2
                            color: chkGrande.checked ? "#27ae60" : "transparent"

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
                            font.pixelSize: 14
                            font.bold: true
                            color: chkBroto.enabled ? "#2c3e50" : "#bdc3c7"
                            leftPadding: chkBroto.indicator.width + chkBroto.spacing
                            verticalAlignment: Text.AlignVCenter
                        }

                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: chkBroto.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 4
                            border.color: chkBroto.enabled ? (chkBroto.checked ? "#27ae60" : "#bdc3c7") : "#e0e0e0"
                            border.width: 2
                            color: chkBroto.enabled ? (chkBroto.checked ? "#27ae60" : "transparent") : "#f0f0f0"

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
                            font.pixelSize: 14
                            font.bold: true
                            color: chkMini.enabled ? "#2c3e50" : "#bdc3c7"
                            leftPadding: chkMini.indicator.width + chkMini.spacing
                            verticalAlignment: Text.AlignVCenter
                        }

                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: chkMini.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 4
                            border.color: chkMini.enabled ? (chkMini.checked ? "#27ae60" : "#bdc3c7") : "#e0e0e0"
                            border.width: 2
                            color: chkMini.enabled ? (chkMini.checked ? "#27ae60" : "transparent") : "#f0f0f0"

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
                            border.color: btnItem.checado ? "#27ae60" : "#bdc3c7"
                            border.width: 2
                            color: btnItem.checado ? "#27ae60" : "transparent"
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
                            font.pixelSize: 14
                            font.bold: true
                            color: "#2c3e50"
                            // Ajuste proporcional para não encostar nos preços
                            width: parent.width - 120
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "R$ " + model.valor
                            font.pixelSize: 14
                            color: "#27ae60"
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }

                    }

                    background: Rectangle {
                        radius: 8
                        color: btnItem.checado ? "#d5f5e3" : (btnItem.down ? "#e0e0e0" : (btnItem.hovered ? "#f1f1f1" : "#ffffff"))
                        border.color: btnItem.checado ? "#27ae60" : "#cccccc"
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
                radius: 12
                border.color: "#e0e0e0"

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
                radius: 10
                border.color: "#e0e0e0"
                clip: true

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Text {
                        text: "LEGENDA (" + tamanhoSelecionado.toUpperCase() + ")"
                        font.pixelSize: 11
                        font.bold: true
                        color: "#7f8c8d"
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
                                color: "#e74c3c"
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
                                color: "#2c3e50"
                                width: parent.width - 100
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: "R$ " + modelData.valorNum.toFixed(2).replace(".", ",")
                                font.pixelSize: 12
                                color: "#7f8c8d"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                        }

                    }

                }

            }

            // 3. Valor Total
            Rectangle {
                width: parent.width
                height: 65
                color: "#2c3e50"
                radius: 10

                Column {
                    anchors.centerIn: parent
                    spacing: 2

                    Text {
                        text: "VALOR TOTAL (" + tamanhoSelecionado.toUpperCase() + ")"
                        color: "#bdc3c7"
                        font.pixelSize: 10
                        font.bold: true
                        anchors.horizontalCenter: parent
                    }

                    Text {
                        text: "R$ " + valorAtualMaior.toFixed(2).replace(".", ",")
                        color: "#2ecc71"
                        font.pixelSize: 20
                        font.bold: true
                        anchors.horizontalCenter: parent
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
                        radius: 8
                        color: btnVoltar.down ? "#c0392b" : (btnVoltar.hovered ? "#d63031" : "#e74c3c")
                        border.color: "#c0392b"
                        border.width: 1
                    }

                }

                // BOTÃO CONFIRMAR
                Button {
                    id: btnConfirmar

                    width: (parent.width - parent.spacing) / 2
                    height: 46
                    enabled: selecionados.length > 0
                    // BOTÃO CONFIRMAR
                    onClicked: {
                        if (selecionados.length === 0)
                            return ;

                        var nomesArray = selecionados.map(function(item) {
                            return item.nome;
                        });
                        var nomeFinal = nomesArray.join(" / ") + " (" + tamanhoSelecionado + ")";
                        var valorFinal = "R$ " + valorAtualMaior.toFixed(2).replace(".", ",");
                        if (typeof onPedidoSelecionado === "function")
                            onPedidoSelecionado(nomeFinal, valorFinal); // <-- chama o callback recebido
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
                        radius: 8
                        color: !btnConfirmar.enabled ? "#bdc3c7" : (btnConfirmar.down ? "#219150" : (btnConfirmar.hovered ? "#2ecc71" : "#27ae60"))
                        border.color: !btnConfirmar.enabled ? "#bdc3c7" : "#219150"
                        border.width: 1
                    }

                }

            }

        }

    }

    background: Rectangle {
        color: "#f8f9fa"
        radius: 20
    }

}
