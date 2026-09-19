import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../../components"

// Popup de atribuição de borda/adicional a uma pizza já adicionada em
// Pizzas.qml (pizzasMontadas) — máquina de estados navegada só por clique:
//
//   categoria -> itens -> pizzas -> [sabores, só p/ adicional em pizza
//                                    meio a meio] -> atribui e fecha
//
// Bordas valem para a pizza inteira. Adicionais têm dois preços (ver
// services/cardapioService.py, pizzaAdicionais): o de METADE, quando é
// marcado um sabor só de uma pizza de vários, e o de INTEIRA, quando são
// marcados dois ou mais — aí o adicional vai para a pizza toda, com sabor
// vazio (ver comandaTextoService.montar_grupos: a borda e o adicional inteiro
// saem abaixo de todos os sabores, o de metade abaixo do sabor a que foi
// atribuído).
Popup {
    id: popupAdicionaisBordas

    // Lista de pizzas já montadas (Pizzas.qml.pizzasMontadas) — só leitura
    // aqui, a atribuição de fato acontece via onAtribuirBorda/
    // onAtribuirAdicional, que quem abriu o popup implementa.
    property var pizzasMontadas: []
    // function(indicePizza, {nome, valorNum})
    property var onAtribuirBorda: null
    // function(indicePizza, nomeSabor, {nome, valorNum})
    property var onAtribuirAdicional: null

    property string etapa: "categoria"
    property string categoriaAtual: ""
    property var itemSelecionado: null
    property int indicePizzaSelecionada: -1
    // Nomes dos sabores marcados na etapa "sabores".
    property var saboresMarcados: []
    property bool adicionaisCarregados: false

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    // A lista de adicionais cresce com o cardápio: presa à altura da janela,
    // a sobra vira rolagem do conteúdo em vez de empurrar os botões de
    // confirmar/cancelar para fora da tela — num popup modal, isso deixaria
    // o atendente sem saída a não ser pelo Esc.
    height: Math.min(implicitHeight, Responsivo.alturaPopup(implicitHeight))
    onOpened: {
        etapa = "categoria";
        categoriaAtual = "";
        itemSelecionado = null;
        indicePizzaSelecionada = -1;
        saboresMarcados = [];
        carregarAdicionais();
    }

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    ListModel {
        id: modeloBordas
    }

    ListModel {
        id: modeloAdicionais
    }

    // Síncrono de propósito (3º argumento "false"): arquivo local pequeno,
    // mesmo padrão de Pizzas.qml.carregarPrecosPromocionais — evita ter que
    // encadear callback assíncrono só pra abrir um popup.
    function carregarAdicionais() {
        if (adicionaisCarregados)
            return;

        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(raizProjeto + "data/cardapio/adicionais.json"), false);
        xhr.send();
        if (xhr.status !== 200 && xhr.status !== 0)
            return;

        try {
            var dados = JSON.parse(xhr.responseText);
            var bordas = dados.bordas || [];
            var adicionais = dados.adicionais || [];
            for (var i = 0; i < bordas.length; i++) {
                modeloBordas.append(bordas[i]);
            }
            for (var j = 0; j < adicionais.length; j++) {
                // Sem preço de metade cadastrado, a metade custa o mesmo que a
                // inteira. Preenchido aqui para todo item ter o mesmo papel
                // no ListModel, que não aceita papel ausente em alguns itens.
                modeloAdicionais.append({
                    "nome": adicionais[j].nome,
                    "valor": adicionais[j].valor,
                    "valorMetade": adicionais[j].valorMetade || adicionais[j].valor
                });
            }
            adicionaisCarregados = true;
        } catch (e) {
            console.error("Erro ao interpretar adicionais.json:", e);
        }
    }

    function parseValor(strValor) {
        return parseFloat((strValor || "0").replace(",", "."));
    }

    function nomesSaboresPizza(pizza) {
        return pizza.sabores.map(function (s) {
            return s.nome;
        }).join(" / ") + " (" + pizza.tamanho + ")";
    }

    function selecionarCategoria(categoria) {
        categoriaAtual = categoria;
        etapa = "itens";
    }

    function selecionarItem(nome, valorTexto, valorMetadeTexto) {
        itemSelecionado = {
            "nome": nome,
            "valorNum": parseValor(valorTexto),
            "valorMetadeNum": parseValor(valorMetadeTexto || valorTexto)
        };
        etapa = "pizzas";
    }

    function selecionarPizza(indice) {
        if (categoriaAtual === "bordas") {
            if (typeof onAtribuirBorda === "function")
                onAtribuirBorda(indice, itemSelecionado);
            popupAdicionaisBordas.close();
            return;
        }

        var pizza = pizzasMontadas[indice];
        if (!pizza)
            return;

        if (pizza.sabores.length > 1) {
            indicePizzaSelecionada = indice;
            saboresMarcados = [];
            etapa = "sabores";
            return;
        }

        // Só um sabor: não há o que escolher, atribui direto a ele — que é a
        // pizza toda, então com o preço de inteira.
        if (typeof onAtribuirAdicional === "function")
            onAtribuirAdicional(indice, pizza.sabores[0].nome, itemSelecionado);
        popupAdicionaisBordas.close();
    }

    function alternarSabor(nomeSabor) {
        var lista = saboresMarcados.slice();
        var posicao = lista.indexOf(nomeSabor);
        if (posicao >= 0)
            lista.splice(posicao, 1);
        else
            lista.push(nomeSabor);
        saboresMarcados = lista;
    }

    // Um sabor marcado é uma metade; dois ou mais, a pizza inteira (sabor
    // vazio, ver o topo do arquivo).
    function confirmarSabores() {
        if (saboresMarcados.length === 0)
            return;

        if (typeof onAtribuirAdicional === "function") {
            if (saboresMarcados.length === 1) {
                onAtribuirAdicional(indicePizzaSelecionada, saboresMarcados[0], {
                    "nome": itemSelecionado.nome,
                    "valorNum": itemSelecionado.valorMetadeNum
                });
            } else {
                onAtribuirAdicional(indicePizzaSelecionada, "", {
                    "nome": itemSelecionado.nome,
                    "valorNum": itemSelecionado.valorNum
                });
            }
        }
        popupAdicionaisBordas.close();
    }

    function voltar() {
        if (etapa === "sabores")
            etapa = "pizzas";
        else if (etapa === "pizzas")
            etapa = "itens";
        else if (etapa === "itens")
            etapa = "categoria";
    }

    function tituloEtapa() {
        if (etapa === "categoria")
            return "Adicionais ou Bordas";
        if (etapa === "itens")
            return categoriaAtual === "bordas" ? "Escolha a Borda" : "Escolha o Adicional";
        if (etapa === "pizzas")
            return "Em qual pizza?";
        return "Em qual sabor?";
    }

    contentItem: Flickable {
        contentWidth: width
        contentHeight: colunaPopup.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        implicitWidth: colunaPopup.implicitWidth
        implicitHeight: colunaPopup.implicitHeight

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Column {
            id: colunaPopup

            width: Responsivo.larguraPopup(380)
            spacing: 16

            Text {
                text: popupAdicionaisBordas.tituloEtapa()
                font.pixelSize: Estilo.global.fontSize.title
                font.family: Estilo.global.fontFamily.title
                color: Estilo.global.text
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // ---------- ETAPA 1: categoria (Bordas / Adicionais) ----------
            Row {
                visible: popupAdicionaisBordas.etapa === "categoria"
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Estilo.global.spacing.xl

                Button {
                    width: 170
                    height: 110
                    onClicked: popupAdicionaisBordas.selecionarCategoria("bordas")

                    contentItem: Column {
                        anchors.centerIn: parent
                        spacing: Estilo.global.spacing.sm

                        Icone {
                            nome: "fa6s.bread-slice"
                            cor: Estilo.global.textOnAccent
                            tamanho: 32
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "Bordas"
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.bold: true
                            color: Estilo.global.textOnAccent
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.lg
                        color: parent.down ? Estilo.category.borda.pressed : (parent.hovered ? Estilo.category.borda.hover : Estilo.category.borda.base)
                    }
                }

                Button {
                    width: 170
                    height: 110
                    onClicked: popupAdicionaisBordas.selecionarCategoria("adicionais")

                    contentItem: Column {
                        anchors.centerIn: parent
                        spacing: Estilo.global.spacing.sm

                        Icone {
                            nome: "fa6s.layer-group"
                            cor: Estilo.global.textOnAccent
                            tamanho: 32
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Text {
                            text: "Adicionais"
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.bold: true
                            color: Estilo.global.textOnAccent
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.lg
                        color: parent.down ? Estilo.category.adicional.pressed : (parent.hovered ? Estilo.category.adicional.hover : Estilo.category.adicional.base)
                    }
                }
            }

            // ---------- ETAPA 2: lista de itens (bordas ou adicionais) ----------
            ListView {
                visible: popupAdicionaisBordas.etapa === "itens"
                width: parent.width
                height: Math.min(300, count * 54)
                clip: true
                spacing: Estilo.global.spacing.xs
                model: popupAdicionaisBordas.categoriaAtual === "bordas" ? modeloBordas : modeloAdicionais

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                delegate: Button {
                    width: ListView.view.width
                    height: 48
                    padding: Estilo.global.padding.md
                    onClicked: popupAdicionaisBordas.selecionarItem(model.nome, model.valor, model.valorMetade)

                    contentItem: Row {
                        spacing: Estilo.global.spacing.md

                        Text {
                            text: model.nome
                            font.pixelSize: Estilo.global.fontSize.lg
                            font.bold: true
                            color: Estilo.global.text
                            width: parent.width - 120
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                text: "R$ " + model.valor
                                font.pixelSize: Estilo.global.fontSize.lg
                                color: Estilo.action.confirm.base
                                font.bold: true
                            }

                            Text {
                                visible: popupAdicionaisBordas.categoriaAtual === "adicionais" && model.valorMetade !== model.valor
                                text: "metade R$ " + model.valorMetade
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.textSecondary
                            }
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.md
                        color: parent.down ? Estilo.global.surfacePressed : (parent.hovered ? Estilo.global.surfaceHover : Estilo.global.surface)
                        border.color: Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }
            }

            // ---------- ETAPA 3: lista de pizzas já adicionadas ----------
            ListView {
                visible: popupAdicionaisBordas.etapa === "pizzas"
                width: parent.width
                height: Math.min(300, count * 54)
                clip: true
                spacing: Estilo.global.spacing.xs
                model: popupAdicionaisBordas.pizzasMontadas

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                delegate: Button {
                    width: ListView.view.width
                    height: 48
                    padding: Estilo.global.padding.md
                    onClicked: popupAdicionaisBordas.selecionarPizza(index)

                    contentItem: Text {
                        text: popupAdicionaisBordas.nomesSaboresPizza(modelData)
                        font.pixelSize: Estilo.global.fontSize.lg
                        font.bold: true
                        color: Estilo.global.text
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.md
                        color: parent.down ? Estilo.global.surfacePressed : (parent.hovered ? Estilo.global.surfaceHover : Estilo.global.surface)
                        border.color: Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }
            }

            // ---------- ETAPA 4: sabores da pizza escolhida (só p/ adicional) ----------
            Text {
                visible: popupAdicionaisBordas.etapa === "sabores"
                width: parent.width
                text: "Marque um sabor para pôr o adicional só naquela metade, ou dois ou mais para pôr na pizza inteira."
                font.pixelSize: Estilo.global.fontSize.sm
                color: Estilo.global.textSecondary
                wrapMode: Text.Wrap
            }

            ListView {
                visible: popupAdicionaisBordas.etapa === "sabores"
                width: parent.width
                height: Math.min(300, count * 54)
                clip: true
                spacing: Estilo.global.spacing.xs
                model: popupAdicionaisBordas.indicePizzaSelecionada >= 0 ? popupAdicionaisBordas.pizzasMontadas[popupAdicionaisBordas.indicePizzaSelecionada].sabores : []

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                delegate: Button {
                    readonly property bool marcado: popupAdicionaisBordas.saboresMarcados.indexOf(modelData.nome) >= 0

                    width: ListView.view.width
                    height: 48
                    padding: Estilo.global.padding.md
                    onClicked: popupAdicionaisBordas.alternarSabor(modelData.nome)

                    contentItem: Row {
                        spacing: Estilo.global.spacing.md

                        Icone {
                            nome: marcado ? "fa6s.square-check" : "fa6s.square"
                            cor: marcado ? Estilo.category.adicional.base : Estilo.global.textSecondary
                            tamanho: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: modelData.nome
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
                        color: parent.down ? Estilo.global.surfacePressed : (parent.hovered ? Estilo.global.surfaceHover : Estilo.global.surface)
                        border.color: marcado ? Estilo.category.adicional.base : Estilo.global.border
                        border.width: marcado ? 2 : Estilo.global.borderWidth.hairline
                    }
                }
            }

            // ---------- Rodapé: Voltar/Cancelar ----------
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Estilo.global.spacing.lg

                Button {
                    text: "Voltar"
                    visible: popupAdicionaisBordas.etapa !== "categoria"
                    padding: Estilo.global.padding.md
                    width: 150
                    onClicked: popupAdicionaisBordas.voltar()

                    contentItem: Text {
                        text: "Voltar"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.action.back.pressed : (parent.hovered ? Estilo.action.back.hover : Estilo.action.danger.base)
                    }
                }

                Button {
                    visible: popupAdicionaisBordas.etapa === "sabores"
                    enabled: popupAdicionaisBordas.saboresMarcados.length > 0
                    padding: Estilo.global.padding.md
                    width: 150
                    onClicked: popupAdicionaisBordas.confirmarSabores()

                    contentItem: Text {
                        text: popupAdicionaisBordas.saboresMarcados.length > 1 ? "Pizza inteira" : "Metade"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        opacity: parent.enabled ? 1 : Estilo.global.opacity.disabled
                        color: parent.down ? Estilo.category.adicional.pressed : (parent.hovered ? Estilo.category.adicional.hover : Estilo.category.adicional.base)
                    }
                }

                Button {
                    text: "Cancelar"
                    padding: Estilo.global.padding.md
                    width: 150
                    onClicked: popupAdicionaisBordas.close()

                    contentItem: Text {
                        text: "Cancelar"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Qt.darker(Estilo.global.textSecondary, 1.2) : (parent.hovered ? Qt.lighter(Estilo.global.textSecondary, 1.1) : Estilo.global.textSecondary)
                    }
                }
            }
        }

    }
}
