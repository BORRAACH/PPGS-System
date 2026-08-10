import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../../components"
import "../../../components/Texto.js" as Texto

Page {
    id: telaLanches

    focus: true
    // "focus: true" sozinho não é suficiente: StackView assume o controle do
    // foco ao trocar de página, então é preciso pedir foco de novo quando
    // esta página vira a atual (senão digitar sem clicar antes não funciona).
    StackView.onActivated: forceActiveFocus()

    property var onPedidoSelecionado: null
    property var pilha: null
    // Lista para guardar os lanches selecionados — ao contrário de antes,
    // agora é possível selecionar mais de um lanche simultaneamente. Cada
    // lanche selecionado vira uma linha de pedido separada em Balcao/Entrega,
    // com o tipo de pão escolhido gravado na observação.
    property var selecionados: []
    // Lanche aguardando a escolha do pão no popup (nome + valorNum). null
    // quando nenhum popup de pão está em andamento.
    property var paoPendente: null
    // Tipos de pão disponíveis para qualquer lanche. "chave" indica o papel
    // (role) do modeloLanches/modeloFiltrado/paoPendente onde está o preço
    // daquele pão para o lanche em questão — cada pão tem seu próprio valor,
    // vindo direto de lanches.json (valor.pao_hamburguer/pao_frances/pao_baby).
    readonly property var tiposPao: [
        {
            "nome": "Pão de Hambúrguer",
            "icone": "fa6s.burger",
            "cor": Estilo.bread.hamburguer,
            // Pão padrão do lanche: não aparece no nome do pedido.
            "resumo": "",
            "chave": "valorHamburguer"
        },
        {
            "nome": "Pão Francês",
            "icone": "fa6s.bread-slice",
            "cor": Estilo.bread.frances,
            "resumo": "frances",
            "chave": "valorFrances"
        },
        {
            "nome": "Pão Baby",
            "icone": "fa6s.bread-slice",
            "cor": Estilo.bread.baby,
            "resumo": "baby",
            "chave": "valorBaby"
        }
    ]
    // Propriedade computada para o valor somado de todos os lanches selecionados
    readonly property real valorAtual: {
        var soma = 0;
        for (var i = 0; i < selecionados.length; i++) {
            soma += valorFinalLanche(selecionados[i]);
        }
        return soma;
    }

    // Soma do valor de todos os adicionais atribuídos a um lanche
    // selecionado — usado no total do pedido e no cartão da pré-comanda.
    function valorExtrasLanche(item) {
        var adicionais = item.adicionais || [];
        var soma = 0;
        for (var i = 0; i < adicionais.length; i++) {
            soma += adicionais[i].valorNum;
        }
        return soma;
    }

    function valorFinalLanche(item) {
        return item.valorNum + valorExtrasLanche(item);
    }

    // Resumo textual dos adicionais de um lanche, anexado ao nome dele no
    // cartão da pré-comanda (mesmo padrão de resumoExtrasPizza em
    // Pizzas.qml).
    function resumoAdicionaisLanche(item) {
        var adicionais = item.adicionais || [];
        if (adicionais.length === 0)
            return "";
        return " — " + adicionais.map(function (a) {
            return "+ " + a.nome;
        }).join(", ");
    }

    // Chamada pelo PopupAdicionaisLanches ao concluir a escolha — sempre
    // reconstrói o item e reatribui selecionados (em vez de mutar o
    // array/objeto in-place), porque QML só percebe a mudança de uma
    // "property var" quando ela é reatribuída, não quando seu conteúdo é
    // alterado por dentro.
    function atribuirAdicionalLanche(indice, adicional) {
        if (indice < 0 || indice >= selecionados.length)
            return;

        var lista = selecionados.slice();
        var atual = lista[indice];
        var adicionaisNovos = (atual.adicionais || []).slice();
        adicionaisNovos.push({
            "nome": adicional.nome,
            "valorNum": adicional.valorNum
        });
        lista[indice] = {
            "nome": atual.nome,
            "valorNum": atual.valorNum,
            "paoTipo": atual.paoTipo,
            "adicionais": adicionaisNovos
        };
        selecionados = lista;
    }

    // Cor do badge de um tipo de pão, usada na pré-comanda
    function corPao(nomePao) {
        for (var i = 0; i < tiposPao.length; i++) {
            if (tiposPao[i].nome === nomePao)
                return tiposPao[i].cor;
        }
        return Estilo.global.textSecondary;
    }

    // Resumo do tipo de pão para anexar ao nome do pedido (ex: "frances",
    // "baby"). Vazio para o pão de hambúrguer, que é o padrão implícito e
    // não precisa ser destacado no nome.
    function resumoPao(nomePao) {
        for (var i = 0; i < tiposPao.length; i++) {
            if (tiposPao[i].nome === nomePao)
                return tiposPao[i].resumo;
        }
        return "";
    }

    // Nome do papel (role) em que o preço daquele pão está guardado
    // (modeloLanches/modeloFiltrado/paoPendente), ex: "valorFrances".
    function chavePao(nomePao) {
        for (var i = 0; i < tiposPao.length; i++) {
            if (tiposPao[i].nome === nomePao)
                return tiposPao[i].chave;
        }
        return "valorHamburguer";
    }

    // Confirma o pão escolhido no popup para o lanche pendente e o adiciona
    // à lista de selecionados. O preço só é conhecido agora, pois cada pão
    // tem seu próprio valor (paoPendente carrega os 3 preços do lanche).
    // Chamado pelos botões de popupPao.
    function confirmarPao(nomePao) {
        if (!paoPendente)
            return ;

        selecionados = selecionados.concat([{
            "nome": paoPendente.nome,
            "valorNum": parseValor(paoPendente[chavePao(nomePao)]),
            "paoTipo": nomePao,
            "adicionais": []
        }]);
        paoPendente = null;
        popupPao.close();
    }

    function carregarLanches() {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(raizProjeto + "data/cardapio/lanches.json"));
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200 || xhr.status === 0) {
                    try {
                        var dados = JSON.parse(xhr.responseText);
                        modeloLanches.clear();
                        for (var i = 0; i < dados.length; i++) {
                            // O preço de cada pão vem direto do JSON (valor.pao_hamburguer/
                            // pao_frances/pao_baby) — achatado aqui em papéis (roles)
                            // separados, já que o ListModel não lida bem com objetos
                            // aninhados dentro de bindings do QML.
                            modeloLanches.append({
                                "nome": dados[i].nome,
                                "ingredientes": dados[i].ingredientes,
                                "valorHamburguer": dados[i].valor.pao_hamburguer,
                                "valorFrances": dados[i].valor.pao_frances,
                                "valorBaby": dados[i].valor.pao_baby
                            });
                        }
                        console.log("Lanches carregados:", modeloLanches.count);
                        filtrarLanches("");
                    } catch (e) {
                        console.error("Erro ao interpretar JSON:", e);
                    }
                } else {
                    console.error("Erro ao carregar lanches.json, status:", xhr.status);
                }
            }
        };
        xhr.send();
    }

    function filtrarLanches(texto) {
        modeloFiltrado.clear();
        var busca = texto ? Texto.normalizar(texto.trim()) : "";
        var resultados = [];
        for (var i = 0; i < modeloLanches.count; i++) {
            var item = modeloLanches.get(i);
            var nomeLower = Texto.normalizar(item.nome);
            if (busca === "" || nomeLower.indexOf(busca) !== -1)
                resultados.push({
                    "nome": item.nome,
                    "valorHamburguer": item.valorHamburguer,
                    "valorFrances": item.valorFrances,
                    "valorBaby": item.valorBaby,
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
                "valorHamburguer": resultados[j].valorHamburguer,
                "valorFrances": resultados[j].valorFrances,
                "valorBaby": resultados[j].valorBaby
            });
        }
    }

    function parseValor(strValor) {
        return parseFloat(strValor.replace(",", "."));
    }

    // Quantas unidades de um lanche (de qualquer tipo de pão) já foram
    // selecionadas — usado só para o indicador visual da lista, já que o
    // mesmo lanche pode ser escolhido várias vezes (inclusive com pães
    // diferentes em cada unidade).
    function quantidadeDe(nome) {
        var quantidade = 0;
        for (var i = 0; i < selecionados.length; i++) {
            if (selecionados[i].nome === nome)
                quantidade++;
        }
        return quantidade;
    }

    // Remove uma unidade específica (por índice) da pré-comanda — precisa
    // ser por índice, e não por nome, pois duas unidades do mesmo lanche
    // podem ter pães diferentes.
    function removerIndice(indice) {
        var lista = selecionados.slice();
        lista.splice(indice, 1);
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
        carregarLanches();
    }

    // Modelo base contendo os lanches, carregado de data/cardapio/lanches.json
    // (caminho absoluto a partir de "raizProjeto", exposto pelo main.py)
    ListModel {
        id: modeloLanches
    }

    // Modelo auxiliar para exibir apenas os itens filtrados
    ListModel {
        id: modeloFiltrado
    }

    // --- POPUP DE ESCOLHA DO PÃO ---
    // Aberto sempre que um lanche é marcado na lista. Cancelar/fechar sem
    // escolher desfaz a seleção (o lanche não entra em "selecionados").
    Popup {
        id: popupPao

        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: Estilo.global.padding.popup
        parent: Overlay.overlay
        anchors.centerIn: parent

        Overlay.modal: Rectangle {
            color: Estilo.global.overlay
        }

        background: Rectangle {
            radius: Estilo.global.radius.xl
            color: Estilo.global.background
            border.color: Estilo.global.borderCard
        }

        onClosed: {
            paoPendente = null;
        }

        contentItem: Column {
            spacing: 18

            Text {
                text: paoPendente ? ("Qual pão para \"" + paoPendente.nome + "\"?") : ""
                font.pixelSize: Estilo.global.fontSize.xxl
                font.bold: true
                color: Estilo.global.text
                wrapMode: Text.WordWrap
                width: 300
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Column {
                spacing: Estilo.global.spacing.md
                width: 300
                anchors.horizontalCenter: parent.horizontalCenter

                Repeater {
                    model: tiposPao

                    delegate: Button {
                        width: 300
                        height: 46
                        onClicked: confirmarPao(modelData.nome)

                        // Cada pão tem seu próprio preço (vindo de lanches.json),
                        // por isso o valor aparece junto do botão em vez de só
                        // depois de escolhido.
                        contentItem: Item {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16

                            Icone {
                                id: iconePao
                                nome: modelData.icone
                                cor: Estilo.global.textOnAccent
                                tamanho: 15
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                id: textoPrecoPao

                                text: paoPendente ? ("R$ " + parseValor(paoPendente[modelData.chave]).toFixed(2).replace(".", ",")) : ""
                                font.pixelSize: Estilo.global.fontSize.xl
                                font.bold: true
                                color: Estilo.global.textOnAccent
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // Nome ancorado entre o ícone e o preço (com margem
                            // garantida) e não numa Row, para nunca "colar" no
                            // preço quando o nome do pão for mais longo.
                            Text {
                                text: modelData.nome
                                font.pixelSize: Estilo.global.fontSize.xl
                                font.bold: true
                                color: Estilo.global.textOnAccent
                                anchors.left: iconePao.right
                                anchors.leftMargin: 8
                                anchors.right: textoPrecoPao.left
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                            }
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.md
                            color: parent.down ? Qt.darker(modelData.cor, 1.2) : (parent.hovered ? Qt.lighter(modelData.cor, 1.1) : modelData.cor)

                            Behavior on color {
                                ColorAnimation {
                                    duration: Estilo.global.motion.instant
                                }
                            }
                        }
                    }
                }
            }

            Button {
                id: btnCancelarPao

                text: "Cancelar"
                padding: Estilo.global.padding.md
                width: 300
                anchors.horizontalCenter: parent.horizontalCenter
                onClicked: popupPao.close()

                contentItem: Text {
                    text: btnCancelarPao.text
                    font.bold: true
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.sm
                    color: parent.down ? Estilo.action.neutral.pressed : (parent.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                }
            }
        }
    }

    PopupAdicionaisLanches {
        id: popupAdicionaisLanches

        lanchesSelecionados: telaLanches.selecionados
        onAtribuirAdicional: function (indice, adicional) {
            telaLanches.atribuirAdicionalLanche(indice, adicional);
        }
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
    readonly property int alturaBlocosDireita: 210 + 65 + 42 + 46 + Estilo.global.spacing.lg * 4
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
            columns: telaLanches.empilhado ? 1 : 2
            columnSpacing: Estilo.global.spacing.xxl
            rowSpacing: Estilo.global.spacing.xxl

            // ================= COLUNA DA ESQUERDA (Lista e Pesquisa) =================
            Column {
                Layout.preferredWidth: telaLanches.larguraColunaEsquerda
                Layout.preferredHeight: telaLanches.alturaColunaEsquerda
                Layout.alignment: Qt.AlignTop
                spacing: Estilo.global.spacing.lg

                Row {
                    spacing: Estilo.global.spacing.sm
                    Icone { nome: "fa6s.burger"; cor: Estilo.category.lanche.base; tamanho: Estilo.global.fontSize.title; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Escolha o(s) Lanche(s)"
                        font.pixelSize: Estilo.global.fontSize.title
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.category.lanche.base
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    text: selecionados.length === 0 ? "Nenhum lanche selecionado" : selecionados.length + (selecionados.length === 1 ? " lanche selecionado" : " lanches selecionados")
                    font.pixelSize: Estilo.global.fontSize.lg
                    color: selecionados.length > 0 ? Estilo.category.lanche.pressed : Estilo.global.textSecondary
                    font.bold: selecionados.length > 0
                }

                // BARRA DE PESQUISA
                Search {
                    id: campoBusca

                    width: parent.width
                    corDestaque: Estilo.category.lanche.base
                    placeholderText: "Pesquisar lanche (ex: bacon, salada)..."
                    onTextChanged: {
                        filtrarLanches(text);
                    }
                    // Enter com um só resultado na busca já escolhe esse lanche
                    // (abre o popup de pão, como um clique) e limpa a busca.
                    onAccepted: {
                        if (modeloFiltrado.count === 1) {
                            var item = modeloFiltrado.get(0);
                            paoPendente = {
                                "nome": item.nome,
                                "valorHamburguer": item.valorHamburguer,
                                "valorFrances": item.valorFrances,
                                "valorBaby": item.valorBaby
                            };
                            popupPao.open();
                            campoBusca.text = "";
                        }
                    }
                }

                ListView {
                    id: listaLanchesView

                    width: parent.width
                    // O desconto é o que cabeçalho/busca/filtros ocupam acima
                    // dela; o piso evita que a lista suma numa janela baixa.
                    height: Math.max(160, parent.height - 155)
                    model: modeloFiltrado
                    spacing: Estilo.global.spacing.sm
                    clip: true

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AlwaysOn
                        active: true
                    }

                    // Clicar num lanche sempre adiciona mais uma unidade (após
                    // escolher o pão) — não faz mais toggle de seleção, o que
                    // permite pedir o mesmo lanche várias vezes seguidas. A
                    // remoção acontece na pré-comanda (à direita), unidade por
                    // unidade.
                    delegate: Button {
                        id: btnItem

                        property int quantidade: quantidadeDe(model.nome)

                        width: listaLanchesView.width - (listaLanchesView.ScrollBar.vertical.visible ? listaLanchesView.ScrollBar.vertical.width : 0)
                        padding: Estilo.global.padding.md
                        onClicked: {
                            paoPendente = {
                                "nome": model.nome,
                                "valorHamburguer": model.valorHamburguer,
                                "valorFrances": model.valorFrances,
                                "valorBaby": model.valorBaby
                            };
                            popupPao.open();
                        }

                        // Mesmo estilo (Row com spacing 10) da lista de sabores em
                        // Pizzas.qml — sem preço aqui, já que cada pão tem seu
                        // próprio valor, só mostrado depois de escolhido (na
                        // pré-comanda, à direita).
                        contentItem: Row {
                            spacing: Estilo.global.spacing.md

                            Rectangle {
                                width: 20
                                height: 20
                                radius: btnItem.quantidade > 0 ? 10 : 4
                                border.color: btnItem.quantidade > 0 ? Estilo.category.lanche.base : Estilo.global.textDisabled
                                border.width: Estilo.global.borderWidth.thick
                                color: btnItem.quantidade > 0 ? Estilo.category.lanche.base : "transparent"
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    text: btnItem.quantidade
                                    color: Estilo.global.textOnAccent
                                    font.bold: true
                                    font.pixelSize: Estilo.global.fontSize.xs
                                    anchors.centerIn: parent
                                    visible: btnItem.quantidade > 0
                                }
                            }

                            Text {
                                text: model.nome
                                font.pixelSize: Estilo.global.fontSize.lg
                                font.bold: true
                                color: Estilo.global.text
                                width: parent.width - 30
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.md
                            color: btnItem.quantidade > 0 ? Estilo.category.lanche.soft : (btnItem.down ? Estilo.global.surfacePressed : (btnItem.hovered ? Estilo.global.surfaceHover : Estilo.global.surface))
                            border.color: btnItem.quantidade > 0 ? Estilo.category.lanche.base : Estilo.global.border
                            border.width: btnItem.quantidade > 0 ? 2 : 1
                        }
                    }
                }
            }

            // ================= COLUNA DA DIREITA (Visualização, Legenda e Total) =================
            Column {
                Layout.preferredWidth: telaLanches.larguraColunaDireita
                Layout.preferredHeight: telaLanches.alturaColunaDireita
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
                            nome: "fa6s.burger"
                            cor: Estilo.category.lanche.base
                            tamanho: 90
                            anchors.horizontalCenter: parent.horizontalCenter
                            opacity: selecionados.length > 0 ? 1 : Estilo.global.opacity.muted
                        }

                        Text {
                            text: selecionados.length === 0 ? "Nenhum lanche selecionado" : (selecionados.length === 1 ? selecionados[0].nome : selecionados.length + " lanches selecionados")
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

                // 3. Adicionais — opera sobre "selecionados", já que Lanches
                // não tem uma etapa separada de "montar e fechar" como Pizzas
                // (cada lanche entra em "selecionados" assim que o pão é
                // escolhido em popupPao).
                Button {
                    id: btnAdicionaisLanche

                    width: parent.width
                    height: 42
                    enabled: selecionados.length > 0
                    onClicked: popupAdicionaisLanches.open()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        opacity: btnAdicionaisLanche.enabled ? 1 : Estilo.global.opacity.subtle

                        Icone {
                            nome: "fa6s.plus"
                            cor: Estilo.global.textOnAccent
                            tamanho: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "Adicionais"
                            font.pixelSize: Estilo.global.fontSize.lg
                            font.bold: true
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.md
                        color: !btnAdicionaisLanche.enabled ? Estilo.global.surfaceDisabled : (btnAdicionaisLanche.down ? Estilo.category.lanche.pressed : (btnAdicionaisLanche.hovered ? Estilo.category.lanche.hover : Estilo.category.lanche.base))
                        border.color: !btnAdicionaisLanche.enabled ? Estilo.global.surfaceDisabled : Estilo.category.lanche.pressed
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }

                // 4. Pré-comanda: prévia do pedido que será enviado para
                // Balcao.qml/Entrega.qml, no mesmo formato de cartão usado pela
                // lista de comandas em Consulta.qml (badge colorido + título +
                // valor) — aqui o badge mostra o pão escolhido para cada lanche.
                Rectangle {
                    width: parent.width
                    // O que sobra da coluna depois dos blocos de altura fixa
                    // (ver telaLanches.alturaBlocosDireita).
                    height: Math.max(120, parent.height - telaLanches.alturaBlocosDireita)
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
                            text: "Nenhum lanche selecionado"
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

                                    // Badge do pão e nome ficam à esquerda; valor e botão de
                                    // remover são ancorados na borda direita do cartão (posição
                                    // fixa) em vez de entrarem numa Row somada ao nome — assim
                                    // eles nunca "vazam" para fora do retângulo, e o nome ocupa
                                    // exatamente o espaço que sobra entre o badge e o valor.
                                    Rectangle {
                                        id: itemPreComanda

                                        width: colunaPreComanda.width
                                        height: 40
                                        radius: Estilo.global.radius.md
                                        color: Estilo.global.background
                                        border.color: Estilo.global.borderCard
                                        clip: true

                                        Rectangle {
                                            id: badgePaoPreComanda

                                            radius: Estilo.global.radius.sm
                                            width: textoBadgePao.implicitWidth + 14
                                            height: textoBadgePao.implicitHeight + 6
                                            color: corPao(modelData.paoTipo)
                                            anchors.left: parent.left
                                            anchors.leftMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter

                                            Text {
                                                id: textoBadgePao

                                                text: modelData.paoTipo
                                                color: Estilo.global.textOnAccent
                                                font.bold: true
                                                font.pixelSize: Estilo.global.fontSize.xs
                                                anchors.centerIn: parent
                                            }
                                        }

                                        // Remove só esta unidade (por índice, já que duas
                                        // unidades do mesmo lanche podem ter pães diferentes).
                                        Button {
                                            id: btnRemoverPreComanda

                                            width: 22
                                            height: 22
                                            padding: 0
                                            anchors.right: parent.right
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: removerIndice(index)

                                            contentItem: Text {
                                                text: "×"
                                                color: Estilo.global.textOnAccent
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
                                            id: textoValorPreComanda

                                            text: "R$ " + valorFinalLanche(modelData).toFixed(2).replace(".", ",")
                                            font.pixelSize: Estilo.global.fontSize.sm
                                            color: Estilo.global.textSecondary
                                            anchors.right: btnRemoverPreComanda.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: modelData.nome + resumoAdicionaisLanche(modelData)
                                            font.pixelSize: Estilo.global.fontSize.md
                                            font.bold: true
                                            color: Estilo.global.text
                                            anchors.left: badgePaoPreComanda.right
                                            anchors.leftMargin: 8
                                            anchors.right: textoValorPreComanda.left
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

                // 5. Botões de Ação
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
                            color: Estilo.global.textOnAccent
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
                        enabled: selecionados.length > 0
                        onClicked: {
                            if (selecionados.length === 0)
                                return ;

                            // Envia sempre um array de itens — mesmo com 1 lanche
                            // selecionado — para que Balcao/Entrega tratem todos
                            // os casos (1 ou mais lanches) da mesma forma. O pão
                            // escolhido vai anexado ao nome do pedido (ex:
                            // "Hambúrguer ( frances )"), não na observação. O pão
                            // de hambúrguer é o padrão e não aparece no nome.
                            var itens = selecionados.map(function(item) {
                                var resumo = resumoPao(item.paoTipo);
                                // "sabor" usa o nome BASE do lanche (sem o
                                // sufixo do pão) porque é contra ele que
                                // comandaTextoService._extras_adicionais casa o
                                // adicional na hora de imprimir (ver
                                // dividir_sabores, que trata um sufixo final
                                // "(...)" como tamanho, não como parte do nome).
                                var adicionais = (item.adicionais || []).map(function (a) {
                                    return {
                                        "sabor": item.nome,
                                        "nome": a.nome,
                                        "valor": "R$ " + a.valorNum.toFixed(2).replace(".", ",")
                                    };
                                });
                                return {
                                    "nome": resumo ? (item.nome + " ( " + resumo + " )") : item.nome,
                                    "valor": "R$ " + valorFinalLanche(item).toFixed(2).replace(".", ","),
                                    "observacao": "",
                                    "adicionais": adicionais
                                };
                            });
                            if (typeof onPedidoSelecionado === "function")
                                onPedidoSelecionado(itens);
                            pilha.pop(null);
                        }

                        contentItem: Text {
                            text: "Confirmar"
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.bold: true
                            color: Estilo.global.textOnAccent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            opacity: btnConfirmar.enabled ? 1 : Estilo.global.opacity.subtle
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.md
                            color: !btnConfirmar.enabled ? Estilo.global.surfaceDisabled : (btnConfirmar.down ? Estilo.category.lanche.pressed : (btnConfirmar.hovered ? Estilo.category.lanche.hover : Estilo.category.lanche.base))
                            border.color: !btnConfirmar.enabled ? Estilo.global.surfaceDisabled : Estilo.category.lanche.pressed
                            border.width: Estilo.global.borderWidth.hairline
                        }
                    }
                }
            }
        }

    }
}
