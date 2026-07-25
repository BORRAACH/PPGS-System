import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../../components"

Page {
    id: telaLanches

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
    // Tipos de pão disponíveis para qualquer lanche
    readonly property var tiposPao: [
        {
            "nome": "Pão de Hambúrguer",
            "icone": "fa6s.burger",
            "cor": "#e67e22",
            // Pão padrão do lanche: não aparece no nome do pedido.
            "resumo": ""
        },
        {
            "nome": "Pão Francês",
            "icone": "fa6s.bread-slice",
            "cor": "#8e44ad",
            "resumo": "frances"
        },
        {
            "nome": "Pão Baby",
            "icone": "fa6s.bread-slice",
            "cor": "#16a085",
            "resumo": "baby"
        }
    ]
    // Propriedade computada para o valor somado de todos os lanches selecionados
    readonly property real valorAtual: {
        var soma = 0;
        for (var i = 0; i < selecionados.length; i++) {
            soma += selecionados[i].valorNum;
        }
        return soma;
    }

    // Cor do badge de um tipo de pão, usada na pré-comanda
    function corPao(nomePao) {
        for (var i = 0; i < tiposPao.length; i++) {
            if (tiposPao[i].nome === nomePao)
                return tiposPao[i].cor;
        }
        return Estilo.cores.textoSecundario;
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

    // Confirma o pão escolhido no popup para o lanche pendente e o adiciona
    // à lista de selecionados. Chamado pelos botões de popupPao.
    function confirmarPao(nomePao) {
        if (!paoPendente)
            return ;

        selecionados = selecionados.concat([{
            "nome": paoPendente.nome,
            "valorNum": paoPendente.valorNum,
            "paoTipo": nomePao
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
                            modeloLanches.append(dados[i]);
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
        var busca = texto ? texto.trim().toLowerCase() : "";
        var resultados = [];
        for (var i = 0; i < modeloLanches.count; i++) {
            var item = modeloLanches.get(i);
            var nomeLower = item.nome.toLowerCase();
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
        padding: 25
        parent: Overlay.overlay
        anchors.centerIn: parent

        Overlay.modal: Rectangle {
            color: "#99000000"
        }

        background: Rectangle {
            radius: Estilo.rounding.popup
            color: Estilo.cores.fundoPagina
            border.color: Estilo.cores.bordaCard
        }

        onClosed: {
            paoPendente = null;
        }

        contentItem: Column {
            spacing: 18

            Text {
                text: paoPendente ? ("Qual pão para \"" + paoPendente.nome + "\"?") : ""
                font.pixelSize: 18
                font.bold: true
                color: Estilo.cores.texto
                wrapMode: Text.WordWrap
                width: 300
                horizontalAlignment: Text.AlignHCenter
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Column {
                spacing: 10
                width: 300
                anchors.horizontalCenter: parent.horizontalCenter

                Repeater {
                    model: tiposPao

                    delegate: Button {
                        width: 300
                        height: 46
                        onClicked: confirmarPao(modelData.nome)

                        contentItem: Row {
                            spacing: 8
                            anchors.centerIn: parent
                            Icone { nome: modelData.icone; cor: "#ffffff"; tamanho: 15; anchors.verticalCenter: parent.verticalCenter }
                            Text {
                                text: modelData.nome
                                font.pixelSize: 15
                                font.bold: true
                                color: "#ffffff"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.grande
                            color: parent.down ? Qt.darker(modelData.cor, 1.2) : (parent.hovered ? Qt.lighter(modelData.cor, 1.1) : modelData.cor)

                            Behavior on color {
                                ColorAnimation {
                                    duration: 100
                                }
                            }
                        }
                    }
                }
            }

            Button {
                id: btnCancelarPao

                text: "Cancelar"
                padding: 10
                width: 300
                anchors.horizontalCenter: parent.horizontalCenter
                onClicked: popupPao.close()

                contentItem: Text {
                    text: btnCancelarPao.text
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Estilo.cores.textoSecundario : (parent.hovered ? "#95a5a6" : Estilo.cores.textoSecundario)
                }
            }
        }
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
                Icone { nome: "fa6s.burger"; cor: "#e67e22"; tamanho: Estilo.fonte.titulo; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "Escolha o(s) Lanche(s)"
                    font.pixelSize: Estilo.fonte.titulo
                    font.bold: true
                    color: "#e67e22"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                text: selecionados.length === 0 ? "Nenhum lanche selecionado" : selecionados.length + (selecionados.length === 1 ? " lanche selecionado" : " lanches selecionados")
                font.pixelSize: Estilo.fonte.padrao
                color: selecionados.length > 0 ? "#d35400" : Estilo.cores.textoSecundario
                font.bold: selecionados.length > 0
            }

            // BARRA DE PESQUISA
            TextField {
                id: campoBusca

                width: parent.width
                height: 42
                placeholderText: "Pesquisar lanche (ex: bacon, salada)..."
                placeholderTextColor: "#95a5a6"
                font.pixelSize: Estilo.fonte.padrao
                leftPadding: 14
                rightPadding: 14
                color: Estilo.cores.texto
                selectByMouse: true
                onTextChanged: {
                    filtrarLanches(text);
                }

                background: Rectangle {
                    radius: Estilo.rounding.grande
                    color: "#ffffff"
                    border.color: campoBusca.activeFocus ? "#e67e22" : Estilo.cores.borda
                    border.width: campoBusca.activeFocus ? 2 : 1
                }
            }

            ListView {
                id: listaLanchesView

                width: parent.width
                height: parent.height - 155
                model: modeloFiltrado
                spacing: 8
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
                    padding: 10
                    onClicked: {
                        paoPendente = {
                            "nome": model.nome,
                            "valorNum": parseValor(model.valor)
                        };
                        popupPao.open();
                    }

                    contentItem: Row {
                        spacing: 10

                        Rectangle {
                            width: 20
                            height: 20
                            radius: btnItem.quantidade > 0 ? 10 : 4
                            border.color: btnItem.quantidade > 0 ? "#e67e22" : "#bdc3c7"
                            border.width: 2
                            color: btnItem.quantidade > 0 ? "#e67e22" : "transparent"
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                text: btnItem.quantidade
                                color: "white"
                                font.bold: true
                                font.pixelSize: 11
                                anchors.centerIn: parent
                                visible: btnItem.quantidade > 0
                            }
                        }

                        Text {
                            text: model.nome
                            font.pixelSize: Estilo.fonte.padrao
                            font.bold: true
                            color: Estilo.cores.texto
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
                        color: btnItem.quantidade > 0 ? "#fdebd0" : (btnItem.down ? Estilo.cores.bordaCard : (btnItem.hovered ? "#f1f1f1" : "#ffffff"))
                        border.color: btnItem.quantidade > 0 ? "#e67e22" : Estilo.cores.borda
                        border.width: btnItem.quantidade > 0 ? 2 : 1
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
                        nome: "fa6s.burger"
                        cor: "#e67e22"
                        tamanho: 90
                        anchors.horizontalCenter: parent.horizontalCenter
                        opacity: selecionados.length > 0 ? 1 : 0.35
                    }

                    Text {
                        text: selecionados.length === 0 ? "Nenhum lanche selecionado" : (selecionados.length === 1 ? selecionados[0].nome : selecionados.length + " lanches selecionados")
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
            // lista de comandas em Consulta.qml (badge colorido + título +
            // valor) — aqui o badge mostra o pão escolhido para cada lanche.
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
                        text: "Nenhum lanche selecionado"
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

                                // Badge do pão e nome ficam à esquerda; valor e botão de
                                // remover são ancorados na borda direita do cartão (posição
                                // fixa) em vez de entrarem numa Row somada ao nome — assim
                                // eles nunca "vazam" para fora do retângulo, e o nome ocupa
                                // exatamente o espaço que sobra entre o badge e o valor.
                                Rectangle {
                                    id: itemPreComanda

                                    width: colunaPreComanda.width
                                    height: 40
                                    radius: Estilo.rounding.grande
                                    color: Estilo.cores.fundoPagina
                                    border.color: Estilo.cores.bordaCard
                                    clip: true

                                    Rectangle {
                                        id: badgePaoPreComanda

                                        radius: 6
                                        width: textoBadgePao.implicitWidth + 14
                                        height: textoBadgePao.implicitHeight + 6
                                        color: corPao(modelData.paoTipo)
                                        anchors.left: parent.left
                                        anchors.leftMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter

                                        Text {
                                            id: textoBadgePao

                                            text: modelData.paoTipo
                                            color: "#ffffff"
                                            font.bold: true
                                            font.pixelSize: 10
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
                                        id: textoValorPreComanda

                                        text: "R$ " + modelData.valorNum.toFixed(2).replace(".", ",")
                                        font.pixelSize: 12
                                        color: Estilo.cores.textoSecundario
                                        anchors.right: btnRemoverPreComanda.left
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: modelData.nome
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: Estilo.cores.texto
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
                            return {
                                "nome": resumo ? (item.nome + " ( " + resumo + " )") : item.nome,
                                "valor": "R$ " + item.valorNum.toFixed(2).replace(".", ","),
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
                        color: !btnConfirmar.enabled ? "#bdc3c7" : (btnConfirmar.down ? "#d35400" : (btnConfirmar.hovered ? "#f39c12" : "#e67e22"))
                        border.color: !btnConfirmar.enabled ? "#bdc3c7" : "#d35400"
                        border.width: 1
                    }
                }
            }
        }
    }
}
