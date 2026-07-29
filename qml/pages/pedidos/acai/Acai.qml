import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../../components"
import "../../../components/Texto.js" as Texto

Page {
    id: telaAcai

    focus: true
    // "focus: true" sozinho não é suficiente: StackView assume o controle do
    // foco ao trocar de página, então é preciso pedir foco de novo quando
    // esta página vira a atual (senão digitar sem clicar antes não funciona).
    StackView.onActivated: forceActiveFocus()

    property var onPedidoSelecionado: null
    property var pilha: null
    // Tamanho do copo que está sendo montado agora ("300 ML"/"500 ML"/"700 ML").
    property string tamanhoSelecionado: "300 ML"
    // Adicionais do copo em montagem — um item por nome (com "quantidade"),
    // já que o mesmo adicional pode ser atribuído mais de uma vez ao mesmo
    // copo (ex: 2x Nutella). Mesmo padrão de Bebidas.qml.selecionados.
    property var adicionaisAtual: []
    // Copos já fechados nesta visita (cada um com seu próprio tamanho e
    // adicionais) — permite montar mais de um copo sem sair desta tela.
    // Cada item: { tamanho: "500 ML", valorNum: 15.0,
    // adicionais: [{nome, valorNum, quantidade}] }.
    property var coposMontados: []

    readonly property int totalAdicionaisAtual: {
        var soma = 0;
        for (var i = 0; i < adicionaisAtual.length; i++) {
            soma += adicionaisAtual[i].quantidade;
        }
        return soma;
    }
    readonly property real valorAdicionaisAtual: {
        var soma = 0;
        for (var i = 0; i < adicionaisAtual.length; i++) {
            soma += adicionaisAtual[i].valorNum * adicionaisAtual[i].quantidade;
        }
        return soma;
    }
    // Valor do copo em montagem (tamanho + adicionais) — só entra nos totais
    // (valorTotalPedido/Confirmar) enquanto tiver ao menos um adicional
    // escolhido. Um copo liso (sem adicional) só passa a valer quando o
    // atendente clica "Adicionar Copo" explicitamente: como o tamanho nunca
    // fica "vazio" (sempre há um valor default), não dá pra distinguir
    // "ninguém mexeu ainda" de "quer um copo liso" de outro jeito.
    readonly property real valorCopoAtual: totalAdicionaisAtual > 0 ? (precoTamanho(tamanhoSelecionado) + valorAdicionaisAtual) : 0
    readonly property real valorTotalPedido: {
        var soma = 0;
        for (var i = 0; i < coposMontados.length; i++) {
            soma += valorFinalCopo(coposMontados[i]);
        }
        return soma + valorCopoAtual;
    }

    // Valor do copo em montagem, incluindo adicionais ainda não commitados
    // via "Adicionar Copo" — usado só para a prévia exibida no cartão
    // "COPO ATUAL" (ao contrário de valorCopoAtual, não é filtrado por
    // totalAdicionaisAtual, já que aqui a prévia deve refletir o tamanho
    // mesmo com zero adicionais).
    function valorPreviaCopoAtual() {
        return precoTamanho(tamanhoSelecionado) + valorAdicionaisAtual;
    }

    function precoTamanho(nome) {
        for (var i = 0; i < modeloTamanhos.count; i++) {
            var item = modeloTamanhos.get(i);
            if (item.nome === nome)
                return parseValor(item.valor);
        }
        return 0;
    }

    // Quantidade atualmente escolhida de um adicional no copo em montagem
    // (0 se ainda não escolhido)
    function quantidadeAdicionalAtual(nome) {
        for (var i = 0; i < adicionaisAtual.length; i++) {
            if (adicionaisAtual[i].nome === nome)
                return adicionaisAtual[i].quantidade;
        }
        return 0;
    }

    // Adiciona mais uma unidade do adicional ao copo em montagem (nova
    // entrada se ainda não escolhido)
    function adicionarAdicionalAtual(nome, valorNum) {
        var lista = adicionaisAtual.slice();
        for (var i = 0; i < lista.length; i++) {
            if (lista[i].nome === nome) {
                lista[i] = {
                    "nome": nome,
                    "valorNum": valorNum,
                    "quantidade": lista[i].quantidade + 1
                };
                adicionaisAtual = lista;
                return ;
            }
        }
        lista.push({
            "nome": nome,
            "valorNum": valorNum,
            "quantidade": 1
        });
        adicionaisAtual = lista;
    }

    // Remove uma unidade do adicional; some da lista quando a quantidade
    // chega a zero
    function removerAdicionalAtual(nome) {
        var lista = [];
        for (var i = 0; i < adicionaisAtual.length; i++) {
            var item = adicionaisAtual[i];
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
        adicionaisAtual = lista;
    }

    // Fecha o copo em andamento (tamanho + adicionais atuais) e o guarda em
    // coposMontados, liberando os adicionais para montar o próximo copo sem
    // precisar reabrir esta tela. O tamanho permanece selecionado, já que o
    // próximo copo costuma ser do mesmo tamanho.
    function adicionarCopoAtual() {
        var lista = coposMontados.slice();
        lista.push({
            "tamanho": tamanhoSelecionado,
            "valorNum": precoTamanho(tamanhoSelecionado),
            "adicionais": adicionaisAtual.slice()
        });
        coposMontados = lista;
        adicionaisAtual = [];
    }

    function removerCopoMontado(indice) {
        var lista = coposMontados.slice();
        lista.splice(indice, 1);
        coposMontados = lista;
    }

    // Soma do valor de todos os adicionais (já multiplicados pela
    // quantidade) de um copo já montado.
    function valorExtrasCopo(copo) {
        var soma = 0;
        var adicionais = copo.adicionais || [];
        for (var i = 0; i < adicionais.length; i++) {
            soma += adicionais[i].valorNum * adicionais[i].quantidade;
        }
        return soma;
    }

    function valorFinalCopo(copo) {
        return copo.valorNum + valorExtrasCopo(copo);
    }

    // Resumo textual dos adicionais de um copo, exibido junto do tamanho no
    // cartão de "AÇAÍ ADICIONADOS" — agrega quantidade repetida como "×N".
    function resumoAdicionaisCopo(copo) {
        var adicionais = copo.adicionais || [];
        if (adicionais.length === 0)
            return "";

        var partes = adicionais.map(function (a) {
            return a.quantidade > 1 ? (a.nome + " ×" + a.quantidade) : a.nome;
        });
        return " — " + partes.join(", ");
    }

    function carregarAcai() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(raizProjeto + "data/cardapio/acai.json"));
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var dados = JSON.parse(xhr.responseText);
                        modeloTamanhos.clear();
                        var tamanhos = dados.tamanhos || [];
                        for (var i = 0; i < tamanhos.length; i++) {
                            modeloTamanhos.append(tamanhos[i]);
                        }
                        modeloAdicionaisBase.clear();
                        var adicionais = dados.adicionais || [];
                        for (var j = 0; j < adicionais.length; j++) {
                            modeloAdicionaisBase.append(adicionais[j]);
                        }
                        console.log("Adicionais de açaí carregados:", modeloAdicionaisBase.count);
                        filtrarAdicionais("");
                    } catch (e) {
                        console.error("Erro ao interpretar JSON:", e);
                    }
                } else {
                    console.error("Erro ao carregar acai.json, status:", xhr.status);
                }
            }
        };
        xhr.send();
    }

    function filtrarAdicionais(texto) {
        modeloFiltrado.clear();
        var busca = texto ? Texto.normalizar(texto.trim()) : "";
        var resultados = [];
        for (var i = 0; i < modeloAdicionaisBase.count; i++) {
            var item = modeloAdicionaisBase.get(i);
            var nomeLower = Texto.normalizar(item.nome);
            if (busca === "" || nomeLower.indexOf(busca) !== -1)
                resultados.push({
                    "nome": item.nome,
                    "valor": item.valor,
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

    function parseValor(strValor) {
        return parseFloat((strValor || "0").replace(",", "."));
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
        carregarAcai();
    }

    // Modelo base contendo os tamanhos, carregado de data/cardapio/acai.json
    ListModel {
        id: modeloTamanhos
    }

    // Modelo base contendo os adicionais, carregado de data/cardapio/acai.json
    ListModel {
        id: modeloAdicionaisBase
    }

    // Modelo auxiliar para exibir apenas os adicionais filtrados
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

        // ================= COLUNA DA ESQUERDA (Lista, Tamanho e Pesquisa) =================
        Column {
            width: parent.width * 0.52
            height: parent.height
            spacing: 12

            Row {
                spacing: 8
                Icone { nome: "fa6s.ice-cream"; cor: "#8e44ad"; tamanho: Estilo.fonte.titulo; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "Monte o Copo de Açaí"
                    font.pixelSize: Estilo.fonte.titulo
                    font.bold: true
                    color: "#8e44ad"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                text: totalAdicionaisAtual === 0 ? "Copo sem adicionais" : totalAdicionaisAtual + (totalAdicionaisAtual === 1 ? " adicional no copo atual" : " adicionais no copo atual")
                font.pixelSize: Estilo.fonte.padrao
                color: totalAdicionaisAtual > 0 ? "#6c3483" : Estilo.cores.textoSecundario
                font.bold: totalAdicionaisAtual > 0
            }

            // BARRA DE PESQUISA
            Search {
                id: campoBusca

                width: parent.width
                corDestaque: "#8e44ad"
                placeholderText: "Pesquisar adicional (ex: nutella, granola)..."
                onTextChanged: {
                    filtrarAdicionais(text);
                }
                // Enter com um só resultado na busca já adiciona esse
                // adicional (mesmo efeito do botão "+") e limpa a busca.
                onAccepted: {
                    if (modeloFiltrado.count === 1) {
                        var item = modeloFiltrado.get(0);
                        adicionarAdicionalAtual(item.nome, parseValor(item.valor));
                        campoBusca.text = "";
                    }
                }
            }

            // SELEÇÃO DE TAMANHO (3 Opções Exclusivas com fallback para 300 ML)
            Rectangle {
                width: parent.width
                height: 50
                color: "#ffffff"
                radius: Estilo.rounding.grande
                border.color: Estilo.cores.borda

                Row {
                    id: linhaTamanhos

                    // Ancorado às bordas (e não centralizado por conteúdo):
                    // a soma dos três CheckBox com o preço embutido no texto
                    // passa da largura desta coluna em telas menores, e o
                    // conteúdo vazava para fora do cartão dos dois lados —
                    // o rótulo "Tamanho:" saía cortado à esquerda e o
                    // "700 ML" à direita. Aqui a régua é a largura real
                    // disponível, e cada opção fica com uma fatia igual.
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    readonly property real larguraOpcao: (width - rotuloTamanho.width - (spacing * 3)) / 3

                    Text {
                        id: rotuloTamanho

                        text: "Tamanho:"
                        font.pixelSize: Estilo.fonte.padrao
                        font.bold: true
                        color: Estilo.cores.texto
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // --- CHECKBOX 300 ML ---
                    CheckBox {
                        id: chk300

                        text: "300 ML (R$ " + precoTamanho("300 ML").toFixed(2).replace(".", ",") + ")"
                        checked: tamanhoSelecionado === "300 ML"
                        width: linhaTamanhos.larguraOpcao
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: {
                            tamanhoSelecionado = "300 ML";
                        }

                        contentItem: Text {
                            text: chk300.text
                            font.pixelSize: Estilo.fonte.padrao
                            font.bold: true
                            color: Estilo.cores.texto
                            leftPadding: chk300.indicator.width + chk300.spacing
                            verticalAlignment: Text.AlignVCenter
                            // A largura da opção vem da coluna (ver
                            // linhaTamanhos.larguraOpcao), então em tela
                            // apertada o rótulo encolhe até o mínimo antes
                            // de recorrer às reticências — nunca vaza.
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: 9
                            elide: Text.ElideRight
                        }

                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: chk300.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 4
                            border.color: chk300.checked ? "#8e44ad" : "#bdc3c7"
                            border.width: 2
                            color: chk300.checked ? "#8e44ad" : "transparent"

                            Icone {
                                nome: "fa6s.check"
                                cor: "white"
                                tamanho: 12
                                anchors.centerIn: parent
                                visible: chk300.checked
                            }
                        }
                    }

                    // --- CHECKBOX 500 ML ---
                    CheckBox {
                        id: chk500

                        text: "500 ML (R$ " + precoTamanho("500 ML").toFixed(2).replace(".", ",") + ")"
                        checked: tamanhoSelecionado === "500 ML"
                        width: linhaTamanhos.larguraOpcao
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: {
                            tamanhoSelecionado = "500 ML";
                        }

                        contentItem: Text {
                            text: chk500.text
                            font.pixelSize: Estilo.fonte.padrao
                            font.bold: true
                            color: Estilo.cores.texto
                            leftPadding: chk500.indicator.width + chk500.spacing
                            verticalAlignment: Text.AlignVCenter
                            // A largura da opção vem da coluna (ver
                            // linhaTamanhos.larguraOpcao), então em tela
                            // apertada o rótulo encolhe até o mínimo antes
                            // de recorrer às reticências — nunca vaza.
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: 9
                            elide: Text.ElideRight
                        }

                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: chk500.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 4
                            border.color: chk500.checked ? "#8e44ad" : "#bdc3c7"
                            border.width: 2
                            color: chk500.checked ? "#8e44ad" : "transparent"

                            Icone {
                                nome: "fa6s.check"
                                cor: "white"
                                tamanho: 12
                                anchors.centerIn: parent
                                visible: chk500.checked
                            }
                        }
                    }

                    // --- CHECKBOX 700 ML ---
                    CheckBox {
                        id: chk700

                        text: "700 ML (R$ " + precoTamanho("700 ML").toFixed(2).replace(".", ",") + ")"
                        checked: tamanhoSelecionado === "700 ML"
                        width: linhaTamanhos.larguraOpcao
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: {
                            tamanhoSelecionado = "700 ML";
                        }

                        contentItem: Text {
                            text: chk700.text
                            font.pixelSize: Estilo.fonte.padrao
                            font.bold: true
                            color: Estilo.cores.texto
                            leftPadding: chk700.indicator.width + chk700.spacing
                            verticalAlignment: Text.AlignVCenter
                            // A largura da opção vem da coluna (ver
                            // linhaTamanhos.larguraOpcao), então em tela
                            // apertada o rótulo encolhe até o mínimo antes
                            // de recorrer às reticências — nunca vaza.
                            fontSizeMode: Text.HorizontalFit
                            minimumPixelSize: 9
                            elide: Text.ElideRight
                        }

                        indicator: Rectangle {
                            implicitWidth: 20
                            implicitHeight: 20
                            x: chk700.leftPadding
                            y: parent.height / 2 - height / 2
                            radius: 4
                            border.color: chk700.checked ? "#8e44ad" : "#bdc3c7"
                            border.width: 2
                            color: chk700.checked ? "#8e44ad" : "transparent"

                            Icone {
                                nome: "fa6s.check"
                                cor: "white"
                                tamanho: 12
                                anchors.centerIn: parent
                                visible: chk700.checked
                            }
                        }
                    }
                }
            }

            ListView {
                id: listaAdicionaisView

                width: parent.width
                height: parent.height - 225
                model: modeloFiltrado
                spacing: 8
                clip: true

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AlwaysOn
                    active: true
                }

                // Cada adicional tem um contador próprio (+ / -), permitindo
                // atribuí-lo ao mesmo copo mais de uma vez (ex: 2x Nutella)
                // sem reabrir esta tela — mesmo padrão de Bebidas.qml.
                delegate: Rectangle {
                    id: itemRow

                    property int quantidade: quantidadeAdicionalAtual(model.nome)

                    width: listaAdicionaisView.width - (listaAdicionaisView.ScrollBar.vertical.visible ? listaAdicionaisView.ScrollBar.vertical.width : 0)
                    height: 52
                    radius: Estilo.rounding.grande
                    color: quantidade > 0 ? "#f4ecf7" : "#ffffff"
                    border.color: quantidade > 0 ? "#8e44ad" : Estilo.cores.borda
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
                            onClicked: removerAdicionalAtual(model.nome)

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
                            onClicked: adicionarAdicionalAtual(model.nome, parseValor(model.valor))

                            contentItem: Text {
                                text: "+"
                                color: "#ffffff"
                                font.bold: true
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                radius: 6
                                color: parent.down ? "#6c3483" : (parent.hovered ? "#a569bd" : "#8e44ad")
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
                height: 180
                color: "#ffffff"
                radius: Estilo.rounding.painel
                border.color: Estilo.cores.bordaCard

                Column {
                    anchors.centerIn: parent
                    spacing: 10

                    Icone {
                        nome: "fa6s.ice-cream"
                        cor: "#8e44ad"
                        tamanho: 80
                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: coposMontados.length > 0 ? 1 : 0.35
                    }

                    Text {
                        text: coposMontados.length === 0 ? "Nenhum copo adicionado" : (coposMontados.length === 1 ? ("Açaí " + coposMontados[0].tamanho) : coposMontados.length + " copos adicionados")
                        font.pixelSize: Estilo.fonte.padrao
                        font.bold: true
                        color: Estilo.cores.texto
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            // 2. Resumo do copo em montagem
            Rectangle {
                width: parent.width
                height: 60
                color: "#ffffff"
                radius: Estilo.rounding.medio
                border.color: Estilo.cores.bordaCard

                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    width: parent.width - 20

                    Text {
                        text: "COPO ATUAL — " + tamanhoSelecionado
                        font.pixelSize: 11
                        font.bold: true
                        color: Estilo.cores.textoSecundario
                    }

                    Text {
                        text: (totalAdicionaisAtual === 0 ? "Sem adicionais" : totalAdicionaisAtual + " adicional(is)") + " · R$ " + valorPreviaCopoAtual().toFixed(2).replace(".", ",")
                        font.pixelSize: 14
                        font.bold: true
                        color: "#8e44ad"
                    }
                }
            }

            // 3. Botão para fechar o copo atual e começar o próximo, sem
            // sair desta tela — é isso que permite montar mais de um copo
            // de uma vez.
            Button {
                id: btnAdicionarCopo

                width: parent.width
                height: 42
                onClicked: adicionarCopoAtual()

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent

                    Icone {
                        nome: "fa6s.plus"
                        cor: "#ffffff"
                        tamanho: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Adicionar Copo (" + tamanhoSelecionado + ")"
                        font.pixelSize: 14
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.grande
                    color: btnAdicionarCopo.down ? "#219150" : (btnAdicionarCopo.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                    border.color: "#219150"
                    border.width: 1
                }
            }

            // 4. Copos já adicionados ao pedido — cada um pode ser removido
            // individualmente antes de confirmar.
            Rectangle {
                width: parent.width
                height: parent.height - 180 - 60 - 42 - 65 - 46 - (12 * 5)
                color: "#ffffff"
                radius: Estilo.rounding.medio
                border.color: Estilo.cores.bordaCard
                clip: true

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Text {
                        text: "AÇAÍ ADICIONADOS"
                        font.pixelSize: 11
                        font.bold: true
                        color: Estilo.cores.textoSecundario
                    }

                    Text {
                        text: "Nenhum copo adicionado ainda"
                        font.pixelSize: 13
                        color: "#bdc3c7"
                        font.italic: true
                        visible: coposMontados.length === 0
                    }

                    Flickable {
                        width: parent.width
                        height: parent.height - 24
                        clip: true
                        contentHeight: colunaCoposMontados.height
                        visible: coposMontados.length > 0
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        Column {
                            id: colunaCoposMontados

                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: coposMontados

                                // Badge do tamanho e adicionais ficam à esquerda; valor e botão
                                // de remover são ancorados na borda direita do cartão (posição
                                // fixa) — mesmo padrão usado em Pizzas.qml/Lanches.qml.
                                Rectangle {
                                    id: itemCopoMontado

                                    width: colunaCoposMontados.width
                                    height: 40
                                    radius: Estilo.rounding.grande
                                    color: Estilo.cores.fundoPagina
                                    border.color: Estilo.cores.bordaCard
                                    clip: true

                                    Rectangle {
                                        id: badgeTamanhoCopoMontado

                                        radius: 6
                                        width: textoBadgeTamanho.implicitWidth + 14
                                        height: textoBadgeTamanho.implicitHeight + 6
                                        color: "#8e44ad"
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

                                    // Remove só este copo montado.
                                    Button {
                                        id: btnRemoverCopoMontado

                                        width: 22
                                        height: 22
                                        padding: 0
                                        anchors.right: parent.right
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        onClicked: removerCopoMontado(index)

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
                                        id: textoValorCopoMontado

                                        text: "R$ " + valorFinalCopo(modelData).toFixed(2).replace(".", ",")
                                        font.pixelSize: 12
                                        color: Estilo.cores.textoSecundario
                                        anchors.right: btnRemoverCopoMontado.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: "Açaí " + modelData.tamanho + resumoAdicionaisCopo(modelData)
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: Estilo.cores.texto
                                        anchors.left: badgeTamanhoCopoMontado.right
                                        anchors.leftMargin: 8
                                        anchors.right: textoValorCopoMontado.left
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
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "R$ " + valorTotalPedido.toFixed(2).replace(".", ",")
                        color: Estilo.confirmar.hover
                        font.pixelSize: 20
                        font.bold: true
                        anchors.horizontalCenter: parent.horizontalCenter
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
                    enabled: coposMontados.length > 0 || totalAdicionaisAtual > 0
                    // Junta os copos já adicionados com o copo em andamento
                    // (se ele já tiver algum adicional) e envia tudo de uma vez.
                    onClicked: {
                        var listaFinal = coposMontados.slice();
                        if (totalAdicionaisAtual > 0) {
                            listaFinal.push({
                                "tamanho": tamanhoSelecionado,
                                "valorNum": precoTamanho(tamanhoSelecionado),
                                "adicionais": adicionaisAtual.slice()
                            });
                        }
                        if (listaFinal.length === 0)
                            return ;

                        var itens = listaFinal.map(function (copo) {
                            var adicionaisFlat = [];
                            var adicionais = copo.adicionais || [];
                            for (var i = 0; i < adicionais.length; i++) {
                                for (var q = 0; q < adicionais[i].quantidade; q++) {
                                    adicionaisFlat.push({
                                        "sabor": "Açaí",
                                        "nome": adicionais[i].nome,
                                        "valor": "R$ " + adicionais[i].valorNum.toFixed(2).replace(".", ",")
                                    });
                                }
                            }
                            return {
                                "nome": "Açaí (" + copo.tamanho + ")",
                                "valor": "R$ " + valorFinalCopo(copo).toFixed(2).replace(".", ","),
                                "observacao": "",
                                "adicionais": adicionaisFlat
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
                        color: !btnConfirmar.enabled ? "#bdc3c7" : (btnConfirmar.down ? "#6c3483" : (btnConfirmar.hovered ? "#a569bd" : "#8e44ad"))
                        border.color: !btnConfirmar.enabled ? "#bdc3c7" : "#6c3483"
                        border.width: 1
                    }
                }
            }
        }
    }
}
