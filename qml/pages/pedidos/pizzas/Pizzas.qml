import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../../components"
import "../../../components/Texto.js" as Texto

Page {
    // 2. Atualiza os preços internos das pizzas já selecionadas para o novo tamanho

    id: telaPizzas

    focus: true
    // "focus: true" sozinho não é suficiente: StackView assume o controle do
    // foco ao trocar de página, então é preciso pedir foco de novo quando
    // esta página vira a atual (senão digitar sem clicar antes não funciona).
    StackView.onActivated: forceActiveFocus()

    property var onPedidoSelecionado: null
    property var pilha: null
    // false quando aberta a partir de Salao.qml (via Pedido.qml) — comanda
    // de mesa não usa a promoção de pizza do dia (ver carregarPizzas()).
    property bool usarPromocoes: true
    // Sabores escolhidos para a pizza que está sendo montada agora
    property var selecionados: []
    // Pizzas já fechadas nesta visita (cada uma com seus sabores e tamanho
    // próprios) — permite montar mais de uma pizza sem sair desta tela.
    // Cada item: { sabores: [...], tamanho: "Grande", valorNum: 45.0,
    // borda: null | {nome, valorNum}, adicionais: [{sabor, nome, valorNum}] }.
    // Borda/adicionais só podem ser atribuídos aqui, nunca à pizza ainda em
    // montagem (ver btnAdicionaisBordas) — ela só ganha uma posição estável
    // nesta lista depois de "Adicionar Pizza".
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
            soma += valorFinalPizza(pizzasMontadas[i]);
        }
        return soma + valorAtualMaior;
    }

    // Fecha a pizza em andamento (sabores + tamanho atuais) e a guarda em
    // pizzasMontadas, liberando a seleção de sabores para montar a próxima
    // pizza sem precisar reabrir esta tela.
    function adicionarPizzaAtual() {
        if (selecionados.length === 0)
            return;

        var lista = pizzasMontadas.slice();
        lista.push({
            "sabores": selecionados.slice(),
            "tamanho": tamanhoSelecionado,
            "valorNum": valorAtualMaior,
            "borda": null,
            "adicionais": []
        });
        pizzasMontadas = lista;
        selecionados = [];
    }

    function removerPizzaMontada(indice) {
        var lista = pizzasMontadas.slice();
        lista.splice(indice, 1);
        pizzasMontadas = lista;
    }

    // Soma do valor da borda (se houver) + todos os adicionais de uma pizza
    // já montada — usado no total do pedido e no cartão de cada pizza.
    function valorExtrasPizza(pizza) {
        var soma = pizza.borda ? pizza.borda.valorNum : 0;
        var adicionais = pizza.adicionais || [];
        for (var i = 0; i < adicionais.length; i++) {
            soma += adicionais[i].valorNum;
        }
        return soma;
    }

    function valorFinalPizza(pizza) {
        return pizza.valorNum + valorExtrasPizza(pizza);
    }

    // Resumo textual da borda/adicionais de uma pizza, exibido junto dos
    // sabores no cartão de "PIZZAS ADICIONADAS".
    function resumoExtrasPizza(pizza) {
        var partes = [];
        if (pizza.borda)
            partes.push(pizza.borda.nome);

        var adicionais = pizza.adicionais || [];
        for (var i = 0; i < adicionais.length; i++) {
            partes.push("+ " + adicionais[i].nome + " (" + adicionais[i].sabor + ")");
        }
        return partes.length > 0 ? " — " + partes.join(", ") : "";
    }

    // Chamadas pelo PopupAdicionaisBordas ao concluir a escolha — sempre
    // reconstroem o item e reatribuem pizzasMontadas (em vez de mutar o
    // array/objeto in-place), porque QML só percebe a mudança de uma
    // "property var" quando ela é reatribuída, não quando seu conteúdo é
    // alterado por dentro.
    function atribuirBorda(indicePizza, borda) {
        if (indicePizza < 0 || indicePizza >= pizzasMontadas.length)
            return;

        var lista = pizzasMontadas.slice();
        var atual = lista[indicePizza];
        lista[indicePizza] = {
            "sabores": atual.sabores,
            "tamanho": atual.tamanho,
            "valorNum": atual.valorNum,
            "borda": borda,
            "adicionais": atual.adicionais
        };
        pizzasMontadas = lista;
    }

    function atribuirAdicional(indicePizza, nomeSabor, adicional) {
        if (indicePizza < 0 || indicePizza >= pizzasMontadas.length)
            return;

        var lista = pizzasMontadas.slice();
        var atual = lista[indicePizza];
        var adicionaisNovos = (atual.adicionais || []).slice();
        adicionaisNovos.push({
            "sabor": nomeSabor,
            "nome": adicional.nome,
            "valorNum": adicional.valorNum
        });
        lista[indicePizza] = {
            "sabores": atual.sabores,
            "tamanho": atual.tamanho,
            "valorNum": atual.valorNum,
            "borda": atual.borda,
            "adicionais": adicionaisNovos
        };
        pizzasMontadas = lista;
    }

    // "promo_seg_qui.json" vale de segunda a quinta (getDay() 1-4);
    // "promo_sex_dom.json" vale de sexta a domingo (5, 6 ou 0) — ver
    // data/cardapio/promocoes/.
    function arquivoPromocaoAtual() {
        var diaSemana = new Date().getDay();
        return (diaSemana >= 1 && diaSemana <= 4) ? "promo_seg_qui.json" : "promo_sex_dom.json";
    }

    // Devolve {nome: {valorMini, valorBroto, valorGrande}} da promoção do
    // dia, ou {} se não existir/estiver ilegível — carregamento de pizzas
    // nunca deve travar por causa de uma promoção com problema. Síncrono
    // (3º argumento "false" do open()) de propósito: é um arquivo local
    // pequeno, e carregarPizzas() precisa do resultado pronto ANTES de
    // montar modeloPizzas, em vez de encadear dois callbacks assíncronos.
    function carregarPrecosPromocionais() {
        var arquivo = arquivoPromocaoAtual();
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(raizProjeto + "data/cardapio/promocoes/" + arquivo), false);
        xhr.send();
        if (xhr.status !== 200 && xhr.status !== 0)
            return {};

        try {
            var lista = JSON.parse(xhr.responseText);
        } catch (e) {
            console.error("Erro ao interpretar " + arquivo + ":", e);
            return {};
        }

        var porNome = {};
        for (var i = 0; i < lista.length; i++) {
            if (lista[i] && lista[i].nome)
                porNome[lista[i].nome] = lista[i];
        }
        return porNome;
    }

    function carregarPizzas() {
        var promocoes = usarPromocoes ? carregarPrecosPromocionais() : {};
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(raizProjeto + "data/cardapio/pizzas.json"));
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var dados = JSON.parse(xhr.responseText);
                        modeloPizzas.clear();
                        for (var i = 0; i < dados.length; i++) {
                            var item = dados[i];
                            // Sabor em promoção hoje: os três preços da
                            // promoção substituem os do cardápio normal —
                            // nome/ingredientes/id continuam vindo de
                            // pizzas.json (a promoção não precisa repetir
                            // isso, só o preço).
                            var promo = promocoes[item.nome];
                            if (promo) {
                                item = {
                                    "id": item.id,
                                    "nome": item.nome,
                                    "ingredientes": item.ingredientes,
                                    "valorMini": promo.valorMini !== undefined ? promo.valorMini : item.valorMini,
                                    "valorBroto": promo.valorBroto !== undefined ? promo.valorBroto : item.valorBroto,
                                    "valorGrande": promo.valorGrande !== undefined ? promo.valorGrande : item.valorGrande
                                };
                            }
                            modeloPizzas.append(item);
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
        var busca = texto ? Texto.normalizar(texto.trim()) : "";
        // Verifica rigorosamente se a quantidade atual atingiu o limite permitido pelo tamanho
        var limiteAtingido = (selecionados.length >= limiteSabores);
        var resultados = [];
        for (var i = 0; i < modeloPizzas.count; i++) {
            var item = modeloPizzas.get(i);
            var nomeLower = Texto.normalizar(item.nome);
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
        resultados.sort(function (a, b) {
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
        return selecionados.some(function (item) {
            return item.nome === nome;
        });
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

    PopupAdicionaisBordas {
        id: popupAdicionaisBordas

        pizzasMontadas: telaPizzas.pizzasMontadas
        onAtribuirBorda: function (indicePizza, borda) {
            telaPizzas.atribuirBorda(indicePizza, borda);
        }
        onAtribuirAdicional: function (indicePizza, nomeSabor, adicional) {
            telaPizzas.atribuirAdicional(indicePizza, nomeSabor, adicional);
        }
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

            Row {
                spacing: 8
                Icone {
                    nome: "fa6s.pizza-slice"
                    cor: Estilo.cancelar.normal
                    tamanho: Estilo.fonte.titulo
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "Escolha até " + limiteSabores + (limiteSabores === 1 ? " Sabor" : " Sabores")
                    font.pixelSize: Estilo.fonte.titulo
                    font.bold: true
                    color: Estilo.cancelar.normal
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                spacing: 6
                Icone {
                    nome: "fa6s.triangle-exclamation"
                    cor: "#d32f2f"
                    tamanho: Estilo.fonte.padrao
                    visible: selecionados.length === limiteSabores
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: selecionados.length === limiteSabores ? "Limite máximo de " + limiteSabores + " sabores atingido!" : selecionados.length + " de " + limiteSabores + " sabores selecionados"
                    font.pixelSize: Estilo.fonte.padrao
                    color: selecionados.length === limiteSabores ? "#d32f2f" : Estilo.cores.textoSecundario
                    font.bold: selecionados.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // BARRA DE PESQUISA
            Search {
                id: campoBusca

                width: parent.width
                corDestaque: Estilo.cancelar.normal
                placeholderText: "Pesquisar sabor (ex: calabresa, chocolate)..."
                enabled: selecionados.length < limiteSabores
                onTextChanged: {
                    filtrarPizzas(text);
                }
                // Enter com um só resultado na busca já seleciona esse sabor
                // (mesmo efeito de um clique) e limpa a busca.
                onAccepted: {
                    if (modeloFiltrado.count === 1) {
                        var item = modeloFiltrado.get(0);
                        if (!isSelecionado(item.nome) && selecionados.length < limiteSabores) {
                            var lista = selecionados.slice();
                            lista.push({
                                "nome": item.nome,
                                "valorNum": parseValor(item.valor)
                            });
                            selecionados = lista;
                        }
                        campoBusca.text = "";
                    }
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

                            Icone {
                                nome: "fa6s.check"
                                cor: "white"
                                tamanho: 12
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

                            Icone {
                                nome: "fa6s.check"
                                cor: "white"
                                tamanho: 12
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

                            Icone {
                                nome: "fa6s.check"
                                cor: "white"
                                tamanho: 12
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
                            listaTemp = listaTemp.filter(function (item) {
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

                            Icone {
                                nome: "fa6s.check"
                                cor: "white"
                                tamanho: 12
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
                            return;

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

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    opacity: btnAdicionarPizza.enabled ? 1 : 0.6

                    Icone {
                        nome: "fa6s.plus"
                        cor: "#ffffff"
                        tamanho: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Adicionar Pizza (" + tamanhoSelecionado + ")"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.grande
                    color: !btnAdicionarPizza.enabled ? "#bdc3c7" : (btnAdicionarPizza.down ? "#219150" : (btnAdicionarPizza.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal))
                    border.color: !btnAdicionarPizza.enabled ? "#bdc3c7" : "#219150"
                    border.width: 1
                }
            }

            // 3.1. Borda/adicional só fazem sentido numa pizza que já tem
            // sabores e tamanho fechados — por isso opera sobre
            // pizzasMontadas, não sobre a pizza em andamento (selecionados).
            Button {
                id: btnAdicionaisBordas

                width: parent.width
                height: 42
                enabled: pizzasMontadas.length > 0
                onClicked: popupAdicionaisBordas.open()

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    opacity: btnAdicionaisBordas.enabled ? 1 : 0.6

                    Icone {
                        nome: "fa6s.plus"
                        cor: "#ffffff"
                        tamanho: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Adicionais ou Bordas"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.grande
                    color: !btnAdicionaisBordas.enabled ? "#bdc3c7" : (btnAdicionaisBordas.down ? "#0f766e" : (btnAdicionaisBordas.hovered ? "#14b8a6" : "#0d9488"))
                    border.color: !btnAdicionaisBordas.enabled ? "#bdc3c7" : "#0f766e"
                    border.width: 1
                }
            }

            // 4. Pizzas já adicionadas ao pedido — cada uma pode ser
            // removida individualmente antes de confirmar.
            Rectangle {
                width: parent.width
                height: parent.height - 210 - 110 - 42 - 42 - 65 - 46 - (12 * 6)
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

                                // Badge do tamanho e sabores ficam à esquerda; valor e botão de
                                // remover são ancorados na borda direita do cartão (posição
                                // fixa), em vez de entrarem num Row somado aos sabores — assim
                                // eles nunca "vazam" para fora do retângulo, e o texto dos
                                // sabores ocupa exatamente o espaço que sobra entre o badge e o
                                // valor (mesmo padrão usado em Lanches.qml).
                                Rectangle {
                                    id: itemPizzaMontada

                                    width: colunaPizzasMontadas.width
                                    height: 40
                                    radius: Estilo.rounding.grande
                                    color: Estilo.cores.fundoPagina
                                    border.color: Estilo.cores.bordaCard
                                    clip: true

                                    Rectangle {
                                        id: badgeTamanhoPizzaMontada

                                        radius: 6
                                        width: textoBadgeTamanho.implicitWidth + 14
                                        height: textoBadgeTamanho.implicitHeight + 6
                                        color: Estilo.cancelar.normal
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
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

                                    // Remove só esta pizza montada.
                                    Button {
                                        id: btnRemoverPizzaMontada

                                        width: 22
                                        height: 22
                                        padding: 0
                                        anchors.right: parent.right
                                        anchors.rightMargin: 5
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

                                    Text {
                                        id: textoValorPizzaMontada

                                        text: "R$ " + valorFinalPizza(modelData).toFixed(2).replace(".", ",")
                                        font.pixelSize: 12
                                        color: Estilo.cores.textoSecundario
                                        anchors.right: btnRemoverPizzaMontada.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: modelData.sabores.map(function (s) {
                                            return s.nome;
                                        }).join(" / ") + resumoExtrasPizza(modelData)
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: Estilo.cores.texto
                                        anchors.left: badgeTamanhoPizzaMontada.right
                                        anchors.leftMargin: 8
                                        anchors.right: textoValorPizzaMontada.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        elide: Text.ElideRight
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
                                "valorNum": valorAtualMaior,
                                "borda": null,
                                "adicionais": []
                            });
                        }
                        if (listaFinal.length === 0)
                            return;

                        var itens = listaFinal.map(function (pizza) {
                            var nomesArray = pizza.sabores.map(function (item) {
                                return item.nome;
                            });
                            var borda = pizza.borda ? {
                                "nome": pizza.borda.nome,
                                "valor": "R$ " + pizza.borda.valorNum.toFixed(2).replace(".", ",")
                            } : null;
                            var adicionais = (pizza.adicionais || []).map(function (adicional) {
                                return {
                                    "sabor": adicional.sabor,
                                    "nome": adicional.nome,
                                    "valor": "R$ " + adicional.valorNum.toFixed(2).replace(".", ",")
                                };
                            });
                            return {
                                "nome": nomesArray.join(" / ") + " (" + pizza.tamanho + ")",
                                "valor": "R$ " + valorFinalPizza(pizza).toFixed(2).replace(".", ","),
                                "observacao": "",
                                "borda": borda,
                                "adicionais": adicionais
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
