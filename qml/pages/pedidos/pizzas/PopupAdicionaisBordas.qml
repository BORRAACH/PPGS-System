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
// Bordas valem para a pizza inteira; adicionais valem para um sabor
// específico dela (ver comandaTextoService.montar_grupos, que imprime a
// borda abaixo de todos os sabores e o adicional abaixo do sabor a que foi
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
    property bool adicionaisCarregados: false

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 25
    parent: Overlay.overlay
    anchors.centerIn: parent
    onOpened: {
        etapa = "categoria";
        categoriaAtual = "";
        itemSelecionado = null;
        indicePizzaSelecionada = -1;
        carregarAdicionais();
    }

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        radius: Estilo.rounding.popup
        color: Estilo.cores.fundoPagina
        border.color: Estilo.cores.bordaCard
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
                modeloAdicionais.append(adicionais[j]);
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

    function selecionarItem(nome, valorTexto) {
        itemSelecionado = {
            "nome": nome,
            "valorNum": parseValor(valorTexto)
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
            etapa = "sabores";
            return;
        }

        // Só um sabor: não há o que escolher, atribui direto a ele.
        if (typeof onAtribuirAdicional === "function")
            onAtribuirAdicional(indice, pizza.sabores[0].nome, itemSelecionado);
        popupAdicionaisBordas.close();
    }

    function selecionarSabor(nomeSabor) {
        if (typeof onAtribuirAdicional === "function")
            onAtribuirAdicional(indicePizzaSelecionada, nomeSabor, itemSelecionado);
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

    contentItem: Column {
        id: colunaPopup

        width: 380
        spacing: 16

        Text {
            text: popupAdicionaisBordas.tituloEtapa()
            font.pixelSize: Estilo.fonte.titulo
            font.bold: true
            color: Estilo.cores.texto
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // ---------- ETAPA 1: categoria (Bordas / Adicionais) ----------
        Row {
            visible: popupAdicionaisBordas.etapa === "categoria"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 15

            Button {
                width: 170
                height: 110
                onClicked: popupAdicionaisBordas.selecionarCategoria("bordas")

                contentItem: Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Icone {
                        nome: "fa6s.bread-slice"
                        cor: "#ffffff"
                        tamanho: 32
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "Bordas"
                        font.pixelSize: 15
                        font.bold: true
                        color: "#ffffff"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.medio
                    color: parent.down ? Qt.darker("#d97706", 1.2) : (parent.hovered ? Qt.lighter("#d97706", 1.1) : "#d97706")
                }
            }

            Button {
                width: 170
                height: 110
                onClicked: popupAdicionaisBordas.selecionarCategoria("adicionais")

                contentItem: Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Icone {
                        nome: "fa6s.layer-group"
                        cor: "#ffffff"
                        tamanho: 32
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "Adicionais"
                        font.pixelSize: 15
                        font.bold: true
                        color: "#ffffff"
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.medio
                    color: parent.down ? Qt.darker("#0d9488", 1.2) : (parent.hovered ? Qt.lighter("#0d9488", 1.1) : "#0d9488")
                }
            }
        }

        // ---------- ETAPA 2: lista de itens (bordas ou adicionais) ----------
        ListView {
            visible: popupAdicionaisBordas.etapa === "itens"
            width: parent.width
            height: Math.min(300, count * 54)
            clip: true
            spacing: 6
            model: popupAdicionaisBordas.categoriaAtual === "bordas" ? modeloBordas : modeloAdicionais

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Button {
                width: ListView.view.width
                height: 48
                padding: 10
                onClicked: popupAdicionaisBordas.selecionarItem(model.nome, model.valor)

                contentItem: Row {
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

                background: Rectangle {
                    radius: Estilo.rounding.grande
                    color: parent.down ? Estilo.cores.bordaCard : (parent.hovered ? "#f1f1f1" : "#ffffff")
                    border.color: Estilo.cores.borda
                    border.width: 1
                }
            }
        }

        // ---------- ETAPA 3: lista de pizzas já adicionadas ----------
        ListView {
            visible: popupAdicionaisBordas.etapa === "pizzas"
            width: parent.width
            height: Math.min(300, count * 54)
            clip: true
            spacing: 6
            model: popupAdicionaisBordas.pizzasMontadas

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Button {
                width: ListView.view.width
                height: 48
                padding: 10
                onClicked: popupAdicionaisBordas.selecionarPizza(index)

                contentItem: Text {
                    text: popupAdicionaisBordas.nomesSaboresPizza(modelData)
                    font.pixelSize: Estilo.fonte.padrao
                    font.bold: true
                    color: Estilo.cores.texto
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.grande
                    color: parent.down ? Estilo.cores.bordaCard : (parent.hovered ? "#f1f1f1" : "#ffffff")
                    border.color: Estilo.cores.borda
                    border.width: 1
                }
            }
        }

        // ---------- ETAPA 4: sabores da pizza escolhida (só p/ adicional) ----------
        ListView {
            visible: popupAdicionaisBordas.etapa === "sabores"
            width: parent.width
            height: Math.min(300, count * 54)
            clip: true
            spacing: 6
            model: popupAdicionaisBordas.indicePizzaSelecionada >= 0 ? popupAdicionaisBordas.pizzasMontadas[popupAdicionaisBordas.indicePizzaSelecionada].sabores : []

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Button {
                width: ListView.view.width
                height: 48
                padding: 10
                onClicked: popupAdicionaisBordas.selecionarSabor(modelData.nome)

                contentItem: Text {
                    text: modelData.nome
                    font.pixelSize: Estilo.fonte.padrao
                    font.bold: true
                    color: Estilo.cores.texto
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.grande
                    color: parent.down ? Estilo.cores.bordaCard : (parent.hovered ? "#f1f1f1" : "#ffffff")
                    border.color: Estilo.cores.borda
                    border.width: 1
                }
            }
        }

        // ---------- Rodapé: Voltar/Cancelar ----------
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Button {
                text: "Voltar"
                visible: popupAdicionaisBordas.etapa !== "categoria"
                padding: 10
                width: 150
                onClicked: popupAdicionaisBordas.voltar()

                contentItem: Text {
                    text: "Voltar"
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Estilo.voltar.pressionado : (parent.hovered ? Estilo.voltar.hover : Estilo.cancelar.normal)
                }
            }

            Button {
                text: "Cancelar"
                padding: 10
                width: 150
                onClicked: popupAdicionaisBordas.close()

                contentItem: Text {
                    text: "Cancelar"
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Qt.darker(Estilo.cores.textoSecundario, 1.2) : (parent.hovered ? Qt.lighter(Estilo.cores.textoSecundario, 1.1) : Estilo.cores.textoSecundario)
                }
            }
        }
    }
}
