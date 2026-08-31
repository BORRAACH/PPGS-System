import QtQuick
import QtQuick.Controls
import estilo 1.0
import "MontagemExtras.js" as Extras

// Bordas e adicionais de um item que JÁ ESTÁ na comanda, aberto pelo menu de
// botão direito da linha do pedido (ver components/LinhaPedido.qml).
//
// POR QUE EXISTE: até aqui, borda e adicional só podiam ser escolhidos no
// momento em que o item era montado — dentro de Pizzas.qml, Lanches.qml,
// Acai.qml. Esquecer o bacon, ou o cliente lembrar dele depois, obrigava a
// refazer o item inteiro pela seleção de pedido, apagando junto a observação e
// o preço que já tivessem sido ajustados na linha.
//
// Não substitui aqueles popups: eles atendem o fluxo de montagem, em que o
// item ainda não existe e a escolha é parte de criá-lo. Este atende o item
// pronto, e por isso trabalha com o que a LINHA tem — nome montado, valor
// total, borda e adicionais já atribuídos — em vez de com o objeto rico que só
// existe dentro da tela de categoria.
//
// Máquina de estados navegada por clique, como a do popup de montagem:
//
//   lista -> escolher -> [onde, só p/ adicional em pizza de vários sabores]
//                     -> [quantidade, só p/ adicional de açaí]
//                     -> atribui
//
// Depois de atribuir, o adicional volta para a lista e a borda FECHA o popup.
// A diferença é a quantidade que cabe em cada um: adicionais são vários, e
// quem está pondo três não quer reabrir o popup três vezes; borda é uma só,
// então escolher já é terminar.
Popup {
    id: popupExtras

    // --- Entrada: o que a linha da comanda tem hoje ---
    property string nomeItem: ""
    // "bordas" ou "adicionais" — qual das duas o menu pediu.
    property string modo: "adicionais"
    // Da análise do nome do item (cardapioController.analisarItemComanda):
    // os sabores da pizza e a categoria do cardápio de onde sai cada lista.
    property var sabores: []
    property string chaveCategoria: ""
    property string categoriaBordas: ""
    property string categoriaAdicionais: ""
    // {nome, valor} ou null; [{sabor, nome, valor}].
    property var bordaAtual: null
    property var adicionaisAtuais: []

    // --- Saída ---
    // function(borda, adicionais, deltaValor) — o estado NOVO inteiro, mais
    // quanto o valor da linha tem de mudar. Quem abriu grava no modelo: só a
    // tela sabe em qual linha, e o popup não deve conhecer modeloPedidos.
    signal aplicado(var borda, var adicionais, real deltaValor)

    property string etapa: "lista"
    // O item escolhido na etapa "escolher", esperando destino ou quantidade.
    property var itemEscolhido: null
    property int quantidade: 1

    readonly property bool ehPizza: chaveCategoria === "pizzas"
    readonly property bool ehAcai: chaveCategoria === "acaiTamanhos"
    // Só faz sentido perguntar "em que parte?" quando há mais de uma parte.
    readonly property bool perguntaOnde: ehPizza && sabores.length > 1
    readonly property string categoriaAtual: modo === "bordas" ? categoriaBordas : categoriaAdicionais

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    // Mesmo motivo do popup de montagem: com a lista presa à altura da janela,
    // a sobra vira rolagem em vez de empurrar o botão de fechar para fora da
    // tela — num popup modal isso deixaria o atendente sem saída além do Esc.
    height: Math.min(implicitHeight, Responsivo.alturaPopup(implicitHeight))

    onOpened: {
        etapa = "lista";
        itemEscolhido = null;
        quantidade = 1;
        carregarOpcoes();
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
        id: modeloOpcoes
    }

    // Relido a cada abertura, e não guardado como o popup de montagem faz: o
    // cardápio muda em disco (tela de Cardápio, ou a malha gravando o que veio
    // de outra máquina) e um preço velho aqui vira preço errado no cupom.
    function carregarOpcoes() {
        modeloOpcoes.clear();
        if (!categoriaAtual)
            return;

        var itens = cardapioController.listarDaCategoria(categoriaAtual, "");
        for (var i = 0; i < itens.length; i++) {
            modeloOpcoes.append({
                "nome": itens[i].nome,
                "valor": Extras.precoDe(itens[i])
            });
        }
    }

    function titulo() {
        if (etapa === "escolher")
            return popupExtras.modo === "bordas" ? "Escolha a borda" : "Escolha o adicional";
        if (etapa === "onde")
            return "Em que parte da pizza?";
        if (etapa === "quantidade")
            return "Quantos?";
        return popupExtras.modo === "bordas" ? "Borda" : "Adicionais";
    }

    function voltar() {
        if (etapa === "quantidade")
            etapa = perguntaOnde ? "onde" : "escolher";
        else if (etapa === "onde")
            etapa = "escolher";
        else
            etapa = "lista";
    }

    function escolherItem(nome, valor) {
        itemEscolhido = {
            "nome": nome,
            "valor": valor
        };
        quantidade = 1;

        if (popupExtras.modo === "bordas") {
            aplicarBorda();
            return;
        }
        if (perguntaOnde) {
            etapa = "onde";
            return;
        }
        // Sem parte a escolher, o adicional vai no próprio item: o nome do
        // sabor é o do item (é contra ele que a impressão casa o adicional,
        // ver comandaTextoService._extras_adicionais).
        definirDestino(sabores.length > 0 ? sabores[0] : popupExtras.nomeItem);
    }

    // `sabor` vazio = pizza inteira (ver comandaTextoService.
    // SUFIXO_ADICIONAL_INTEIRA).
    function definirDestino(sabor) {
        itemEscolhido = Extras.comSabor(itemEscolhido, sabor);
        if (ehAcai) {
            etapa = "quantidade";
            return;
        }
        aplicarAdicional();
    }

    function aplicarBorda() {
        // Uma pizza tem no máximo uma borda, então escolher outra TROCA a que
        // estava — e o valor da linha tem de perder a antiga junto com ganhar
        // a nova, senão o cupom cobra as duas.
        var delta = Extras.valorNum(itemEscolhido.valor) - Extras.valorNum(bordaAtual ? bordaAtual.valor : "");
        var nova = {
            "nome": itemEscolhido.nome,
            "valor": itemEscolhido.valor
        };
        bordaAtual = nova;
        popupExtras.aplicado(nova, adicionaisAtuais, delta);
        // Fecha em vez de voltar para a lista, ao contrário do adicional: uma
        // pizza tem UMA borda, então escolher já é terminar — a lista atrás
        // não teria mais nada a oferecer além da que se acabou de pôr.
        popupExtras.close();
    }

    function aplicarAdicional() {
        var lista = Extras.comAdicional(adicionaisAtuais, itemEscolhido, quantidade);
        var delta = Extras.valorNum(itemEscolhido.valor) * quantidade;
        adicionaisAtuais = lista;
        itemEscolhido = null;
        quantidade = 1;
        etapa = "lista";
        popupExtras.aplicado(bordaAtual, lista, delta);
    }

    function removerBorda() {
        var delta = -Extras.valorNum(bordaAtual ? bordaAtual.valor : "");
        bordaAtual = null;
        popupExtras.aplicado(null, adicionaisAtuais, delta);
    }

    function removerAdicional(indice) {
        var lista = adicionaisAtuais.slice();
        var removido = lista.splice(indice, 1)[0];
        adicionaisAtuais = lista;
        popupExtras.aplicado(bordaAtual, lista, -Extras.valorNum(removido ? removido.valor : ""));
    }

    contentItem: Flickable {
        contentWidth: width
        contentHeight: coluna.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        implicitWidth: coluna.implicitWidth
        implicitHeight: coluna.implicitHeight

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Column {
            id: coluna

            width: Responsivo.larguraPopup(420)
            spacing: Estilo.global.spacing.lg

            Text {
                text: popupExtras.titulo()
                font.pixelSize: Estilo.global.fontSize.title
                font.family: Estilo.global.fontFamily.title
                color: Estilo.global.text
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // O nome do item fica visível em todas as etapas: o popup é aberto
            // por clique numa linha entre várias parecidas, e é fácil perder de
            // vista em qual delas se está mexendo.
            Text {
                text: popupExtras.nomeItem
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.textSecondary
            }

            // ---------- ETAPA 1: o que o item já tem ----------
            Column {
                visible: popupExtras.etapa === "lista"
                width: parent.width
                spacing: Estilo.global.spacing.sm

                Text {
                    visible: !linhasAtuais.temAlgum
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: popupExtras.modo === "bordas" ? "Nenhuma borda neste item." : "Nenhum adicional neste item."
                    font.pixelSize: Estilo.global.fontSize.md
                    color: Estilo.global.textPlaceholder
                }

                Column {
                    id: linhasAtuais

                    width: parent.width
                    spacing: Estilo.global.spacing.xs

                    readonly property bool temAlgum: popupExtras.modo === "bordas" ? !!popupExtras.bordaAtual : popupExtras.adicionaisAtuais.length > 0

                    // Borda: no máximo uma, então não vale uma ListView.
                    LinhaExtraAtual {
                        visible: popupExtras.modo === "bordas" && !!popupExtras.bordaAtual
                        width: parent.width
                        nome: popupExtras.bordaAtual ? popupExtras.bordaAtual.nome : ""
                        valor: popupExtras.bordaAtual ? popupExtras.bordaAtual.valor : ""
                        onRemover: popupExtras.removerBorda()
                    }

                    Repeater {
                        model: popupExtras.modo === "adicionais" ? popupExtras.adicionaisAtuais : []

                        delegate: LinhaExtraAtual {
                            width: linhasAtuais.width
                            nome: modelData.nome
                            valor: modelData.valor
                            // Numa pizza de vários sabores, a parte importa
                            // tanto quanto o nome: "bacon" sozinho não diz se
                            // é na metade da calabresa ou na pizza toda.
                            destino: popupExtras.perguntaOnde ? (modelData.sabor ? modelData.sabor : "pizza inteira") : ""
                            onRemover: popupExtras.removerAdicional(index)
                        }
                    }
                }

            }

            // ---------- ETAPA 2: escolher no cardápio ----------
            ListView {
                visible: popupExtras.etapa === "escolher"
                width: parent.width
                height: Math.min(300, count * 54)
                clip: true
                spacing: Estilo.global.spacing.xs
                model: modeloOpcoes

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                delegate: Button {
                    width: ListView.view.width
                    height: 48
                    padding: Estilo.global.padding.md
                    onClicked: popupExtras.escolherItem(model.nome, model.valor)

                    contentItem: Row {
                        spacing: Estilo.global.spacing.md

                        Text {
                            text: model.nome
                            font.pixelSize: Estilo.global.fontSize.lg
                            font.bold: true
                            color: Estilo.global.text
                            width: parent.width - 110
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: model.valor
                            font.pixelSize: Estilo.global.fontSize.lg
                            font.bold: true
                            color: Estilo.action.confirm.base
                            anchors.verticalCenter: parent.verticalCenter
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

            // ---------- ETAPA 3: em que parte da pizza ----------
            Column {
                visible: popupExtras.etapa === "onde"
                width: parent.width
                spacing: Estilo.global.spacing.xs

                Repeater {
                    model: popupExtras.sabores

                    delegate: BotaoDestino {
                        width: parent.width
                        texto: (index + 1) + "/" + popupExtras.sabores.length + " — " + modelData
                        onEscolhido: popupExtras.definirDestino(modelData)
                    }
                }

                BotaoDestino {
                    width: parent.width
                    texto: "Pizza inteira"
                    destaque: true
                    // Sabor vazio é como a impressão reconhece o adicional que
                    // vale para a pizza toda.
                    onEscolhido: popupExtras.definirDestino("")
                }
            }

            // ---------- ETAPA 4: quantidade (só açaí) ----------
            Row {
                visible: popupExtras.etapa === "quantidade"
                spacing: Estilo.global.spacing.xl
                anchors.horizontalCenter: parent.horizontalCenter

                Button {
                    text: "-"
                    width: 44
                    height: 44
                    enabled: popupExtras.quantidade > 1
                    onClicked: popupExtras.quantidade -= 1

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                        border.color: Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                        opacity: parent.enabled ? 1 : Estilo.global.opacity.disabled
                    }
                }

                Text {
                    text: popupExtras.quantidade
                    width: 50
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Estilo.global.fontSize.title
                    font.bold: true
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    text: "+"
                    width: 44
                    height: 44
                    onClicked: popupExtras.quantidade += 1

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                        border.color: Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }

                Button {
                    text: "OK"
                    width: 70
                    height: 44
                    onClicked: popupExtras.aplicarAdicional()

                    contentItem: Text {
                        text: parent.text
                        font.pixelSize: Estilo.global.fontSize.lg
                        font.bold: true
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.md
                        color: parent.down ? Estilo.action.confirm.pressed : Estilo.action.confirm.base
                    }
                }
            }

            // ---------- Rodapé ----------
            //
            // Acrescentar à esquerda, Concluir à direita: o verde fica no fim
            // da linha, que é onde a mão já procura o botão que encerra, e o
            // que abre mais uma etapa não disputa esse lugar com ele.
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Estilo.global.spacing.lg

                Button {
                    text: "Voltar"
                    width: 120
                    height: 44
                    visible: popupExtras.etapa !== "lista"
                    onClicked: popupExtras.voltar()

                    background: Rectangle {
                        radius: Estilo.global.radius.md
                        color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                        border.color: Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }

                Button {
                    width: 200
                    height: 44
                    visible: popupExtras.etapa === "lista"
                    text: popupExtras.modo === "bordas" ? (popupExtras.bordaAtual ? "Trocar a borda" : "Escolher borda") : "Acrescentar adicional"
                    // Cardápio sem nenhuma opção da categoria: o botão fica
                    // apagado em vez de abrir uma etapa vazia.
                    enabled: modeloOpcoes.count > 0
                    onClicked: popupExtras.etapa = "escolher"

                    contentItem: Text {
                        text: parent.text
                        font.pixelSize: Estilo.global.fontSize.lg
                        font.bold: true
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.md
                        color: parent.down ? Estilo.category.adicional.pressed : (parent.hovered ? Estilo.category.adicional.hover : Estilo.category.adicional.base)
                        opacity: parent.enabled ? 1 : Estilo.global.opacity.disabled
                    }
                }

                Button {
                    text: "Concluir"
                    width: 140
                    height: 44
                    visible: popupExtras.etapa === "lista"
                    onClicked: popupExtras.close()

                    contentItem: Text {
                        text: parent.text
                        font.pixelSize: Estilo.global.fontSize.lg
                        font.bold: true
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.md
                        color: parent.down ? Estilo.action.confirm.pressed : (parent.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                    }
                }
            }
        }
    }

    // Uma linha do que o item já tem, com o botão de tirar.
    component LinhaExtraAtual: Rectangle {
        id: linhaAtual

        property string nome: ""
        property string valor: ""
        property string destino: ""

        signal remover()

        height: 44
        radius: Estilo.global.radius.md
        color: Estilo.global.surface
        border.color: Estilo.global.border
        border.width: Estilo.global.borderWidth.hairline

        Row {
            anchors.fill: parent
            anchors.leftMargin: Estilo.global.padding.md
            anchors.rightMargin: Estilo.global.padding.sm
            spacing: Estilo.global.spacing.sm

            Column {
                width: parent.width - 150
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: linhaAtual.nome
                    font.pixelSize: Estilo.global.fontSize.md
                    font.bold: true
                    color: Estilo.global.text
                    elide: Text.ElideRight
                    width: parent.width
                }

                Text {
                    visible: linhaAtual.destino !== ""
                    text: linhaAtual.destino
                    font.pixelSize: Estilo.global.fontSize.sm
                    color: Estilo.global.textSecondary
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Text {
                text: linhaAtual.valor
                width: 80
                horizontalAlignment: Text.AlignRight
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.action.confirm.base
                anchors.verticalCenter: parent.verticalCenter
            }

            Button {
                width: 34
                height: 34
                anchors.verticalCenter: parent.verticalCenter
                onClicked: linhaAtual.remover()

                contentItem: Text {
                    text: "×"
                    font.pixelSize: Estilo.global.fontSize.xl
                    font.bold: true
                    color: Estilo.action.danger.base
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: parent.hovered ? Estilo.global.surfaceHover : "transparent"
                    border.color: Estilo.global.border
                    border.width: Estilo.global.borderWidth.hairline
                }
            }
        }
    }

    component BotaoDestino: Button {
        id: botaoDestino

        property string texto: ""
        property bool destaque: false

        signal escolhido()

        height: 48
        onClicked: botaoDestino.escolhido()

        contentItem: Text {
            text: botaoDestino.texto
            font.pixelSize: Estilo.global.fontSize.lg
            font.bold: true
            color: botaoDestino.destaque ? Estilo.global.textOnAccent : Estilo.global.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            radius: Estilo.global.radius.md
            color: botaoDestino.destaque ? (botaoDestino.down ? Estilo.category.adicional.pressed : Estilo.category.adicional.base) : (botaoDestino.down ? Estilo.global.surfacePressed : (botaoDestino.hovered ? Estilo.global.surfaceHover : Estilo.global.surface))
            border.color: Estilo.global.border
            border.width: Estilo.global.borderWidth.hairline
        }
    }
}
