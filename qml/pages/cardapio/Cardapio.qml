import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"
import "../../components/Texto.js" as Texto

// Tela de edição do cardápio: adiciona, altera e remove os itens de
// data/cardapio/*.json — os mesmos arquivos que as telas de pedido
// (qml/pages/pedidos/) leem para montar as listas de pizzas, lanches,
// bebidas e outros.
//
// A tela não conhece o formato de cada arquivo: pede a lista de categorias e
// os campos de cada uma ao cardapioController (ver services/cardapioService.py)
// e monta lista e formulário a partir dessa descrição. É por isso que pizza
// (três preços por tamanho), lanche (três preços por tipo de pão) e bebida
// (um preço só) cabem na mesma tela sem um caminho de código por categoria.
//
// Toda alteração confirmada grava o arquivo inteiro na hora — não existe
// "salvar" separado no fim. São poucos itens por categoria, e gravar item a
// item evita perder a edição de quem fecha a tela pela barra lateral.
Page {
    id: telaCardapio

    objectName: "telaCardapio"

    // Categorias e seus campos, como descritos em services/cardapioService.py
    property var categorias: []
    property int indiceCategoria: 0
    // Itens da categoria atual, no formato plano que o controller devolve
    // (ex: {"nome": "X-Egg", "valor.pao_baby": "16,00"}). É a lista já
    // gravada em disco: só é substituída depois de uma gravação bem-sucedida.
    property var itens: []
    readonly property var categoriaAtual: indiceCategoria >= 0 && indiceCategoria < categorias.length ? categorias[indiceCategoria] : null
    readonly property color corDestaque: categoriaAtual ? categoriaAtual.cor : Estilo.cores.texto

    focus: true
    // Mesmo motivo das telas de pedido: o StackView assume o controle do foco
    // ao trocar de página, então é preciso pedir foco de novo para o atalho de
    // digitar direto na busca (Keys.onPressed abaixo) continuar funcionando.
    StackView.onActivated: forceActiveFocus()

    function carregarCategorias() {
        categorias = cardapioController.listarCategorias();
        selecionarCategoria(0);
    }

    function selecionarCategoria(indice) {
        indiceCategoria = indice;
        campoBusca.text = "";
        carregarItens();
    }

    function carregarItens() {
        itens = categoriaAtual ? cardapioController.listarItens(categoriaAtual.chave) : [];
        filtrar(campoBusca.text);
    }

    // Mantém a ordem do arquivo (não ordena por nome como as telas de
    // pedido): aqui a lista é a cara do JSON que está sendo editado, e itens
    // pulando de lugar a cada alteração dificultaria achar o que acabou de
    // ser mexido.
    function filtrar(texto) {
        modeloVisiveis.clear();
        var busca = texto ? Texto.normalizar(texto.trim()) : "";
        for (var i = 0; i < itens.length; i++) {
            var item = itens[i];
            var alvo = Texto.normalizar((item.nome || "") + " " + (item.ingredientes || ""));
            if (busca !== "" && alvo.indexOf(busca) === -1)
                continue;

            modeloVisiveis.append({
                "indiceItem": i,
                "nome": item.nome || "",
                "detalhe": item.ingredientes || "",
                "precos": resumoPrecos(item)
            });
        }
    }

    // "Mini R$ 24,90   Broto R$ 34,90   Grande R$ 54,90" para pizza,
    // "R$ 6,50" para bebida — montado a partir dos campos de preço da
    // categoria ("preco" espelha o tipo PRECO de services/cardapioService.py).
    function resumoPrecos(item) {
        var campos = categoriaAtual ? categoriaAtual.campos : [];
        var partes = [];
        for (var i = 0; i < campos.length; i++) {
            if (campos[i].tipo !== "preco")
                continue;

            var valor = item[campos[i].chave];
            if (!valor)
                continue;

            partes.push((campos[i].curto ? campos[i].curto + " " : "") + "R$ " + valor);
        }
        return partes.join("   ");
    }

    // Abre o formulário para um item existente (indice >= 0) ou para um item
    // novo (indice === -1). Os nomes dos outros itens vão junto para o popup
    // barrar duplicata antes de fechar.
    function abrirEditor(indice) {
        var nomes = [];
        for (var i = 0; i < itens.length; i++) {
            if (i !== indice)
                nomes.push(itens[i].nome || "");
        }
        popupItem.abrirPara(indice, indice >= 0 ? itens[indice] : null, categoriaAtual, nomes);
    }

    function aplicarItem(indice, item) {
        var lista = itens.slice();
        if (indice < 0)
            lista.push(item);
        else
            lista[indice] = item;
        gravar(lista, indice < 0 ? "Item adicionado ao cardápio!" : "Item atualizado!");
    }

    function removerItem(indice) {
        var lista = itens.slice();
        lista.splice(indice, 1);
        gravar(lista, "Item removido do cardápio!");
    }

    // Grava a lista inteira da categoria. Em caso de erro (preço inválido,
    // arquivo sem permissão de escrita...) o controller devolve a mensagem e
    // nada muda na tela — o que está sendo exibido continua sendo o que está
    // no disco.
    function gravar(lista, mensagemSucesso) {
        if (!categoriaAtual)
            return;

        var erro = cardapioController.salvarItens(categoriaAtual.chave, lista);
        if (erro) {
            filaNotificacoes.notificar(erro, false);
            return;
        }
        // Relê do disco em vez de assumir "lista": o controller normaliza os
        // preços ao gravar (ex: "24.9" vira "24,90"), e a tela deve mostrar o
        // que ficou gravado de verdade.
        carregarItens();
        filaNotificacoes.notificar(mensagemSucesso, true);
    }

    // Mesmo atalho das telas de pedido: digitar qualquer caractere
    // "imprimível" já foca a barra de busca e entra com o que foi digitado.
    Keys.onPressed: function (event) {
        if (!campoBusca.activeFocus && event.key >= Qt.Key_Space && event.key <= Qt.Key_ydiaeresis) {
            campoBusca.forceActiveFocus();
            campoBusca.text += event.text;
            event.accepted = true;
        }
    }

    // Recarrega sozinho quando o cardápio muda por qualquer outro caminho
    // que não este formulário: uma alteração salva em outra máquina da
    // malha (ver services/cardapioService.py CardapioController, evento
    // "cardapio_alterado" em services/rede/eventos.py) ou, mais raro, outra
    // janela/aba desta mesma máquina. Se a categoria alterada não é a que
    // está aberta agora, não precisa recarregar — ela já vai vir certa da
    // próxima vez que for selecionada.
    function aoCardapioAlterado(chaveCategoria) {
        if (telaCardapio.categoriaAtual && telaCardapio.categoriaAtual.chave === chaveCategoria)
            carregarItens();
    }

    // Conexão declarativa, não um .connect() solto em Component.onCompleted
    // — mesmo motivo documentado em Balcao.qml/Rede.qml: cardapioController
    // é global e vive pra sempre, então a conexão precisa estar presa ao
    // ciclo de vida desta página (Connections), não solta num closure.
    Connections {
        target: cardapioController

        function onCardapioAlterado(chaveCategoria) {
            aoCardapioAlterado(chaveCategoria);
        }
    }

    Component.onCompleted: {
        carregarCategorias();
    }

    // Itens exibidos na lista (todos, ou só os que casam com a busca)
    ListModel {
        id: modeloVisiveis
    }

    background: Rectangle {
        color: Estilo.cores.fundoPagina
        radius: Estilo.rounding.popup
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        // --- CABEÇALHO ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 15

            Row {
                spacing: 8

                Icone {
                    nome: "fa6s.book-open"
                    cor: telaCardapio.corDestaque
                    tamanho: Estilo.fonte.titulo
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "CARDÁPIO"
                    font.pixelSize: Estilo.fonte.titulo
                    font.bold: true
                    color: telaCardapio.corDestaque
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: telaCardapio.itens.length === 1 ? "1 item nesta categoria" : telaCardapio.itens.length + " itens nesta categoria"
                font.pixelSize: 13
                color: Estilo.cores.textoSecundario
            }
        }

        // --- ABAS DE CATEGORIA ---
        Row {
            Layout.fillWidth: true
            spacing: 10

            Repeater {
                model: telaCardapio.categorias

                delegate: Button {
                    id: btnCategoria

                    // Capturados aqui (em vez de usar "modelData"/"index"
                    // direto lá dentro) porque contentItem e background são
                    // outro escopo, onde o modelo do Repeater não chega.
                    readonly property var categoria: modelData
                    readonly property bool ativa: telaCardapio.indiceCategoria === index

                    height: 42
                    padding: 14
                    onClicked: telaCardapio.selecionarCategoria(index)

                    contentItem: Row {
                        spacing: 8

                        Icone {
                            nome: btnCategoria.categoria.icone
                            cor: btnCategoria.ativa ? "#ffffff" : btnCategoria.categoria.cor
                            tamanho: Estilo.fonte.padrao
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: btnCategoria.categoria.rotulo
                            font.pixelSize: Estilo.fonte.padrao
                            font.bold: true
                            color: btnCategoria.ativa ? "#ffffff" : Estilo.cores.texto
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.grande
                        color: btnCategoria.ativa ? btnCategoria.categoria.cor : (btnCategoria.hovered ? "#f1f1f1" : "#ffffff")
                        border.color: btnCategoria.ativa ? btnCategoria.categoria.cor : Estilo.cores.borda
                        border.width: btnCategoria.ativa ? 2 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }
                    }
                }
            }
        }

        // --- BUSCA + ADICIONAR ---
        // Row simples (não RowLayout) igual ColunaEsquerda.qml (Consulta):
        // dentro de um RowLayout, o "height: 42" do Search.qml (a barra de
        // busca padrão de todas as telas) é sobrescrito pelo próprio layout
        // — que gerencia a altura dos filhos sozinho e ignora height direto
        // (ver aviso do qmllint: "height on an item managed by a layout") —
        // e a barra saía mais baixa e com o arredondamento do canto
        // proporcionalmente diferente do resto do app.
        Row {
            id: linhaBusca

            // Sem "height:" explícito aqui — dentro de um ColumnLayout,
            // isso levaria o mesmo aviso do qmllint que motivou trocar o
            // RowLayout por um Row logo abaixo. A altura de 42 já vem de
            // sobra da altura dos próprios filhos (Search/Button).
            Layout.fillWidth: true
            spacing: 12

            Search {
                id: campoBusca

                width: linhaBusca.width - btnAdicionar.width - linhaBusca.spacing
                corDestaque: telaCardapio.corDestaque
                placeholderText: "Pesquisar no cardápio (nome ou ingrediente)..."
                onTextChanged: telaCardapio.filtrar(text)
            }

            Button {
                id: btnAdicionar

                height: 42
                padding: 14
                enabled: telaCardapio.categoriaAtual !== null
                onClicked: telaCardapio.abrirEditor(-1)

                contentItem: Row {
                    spacing: 8

                    Icone {
                        nome: "fa6s.plus"
                        cor: "#ffffff"
                        tamanho: Estilo.fonte.padrao
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: telaCardapio.categoriaAtual ? telaCardapio.categoriaAtual.novoRotulo : "Novo item"
                        font.pixelSize: Estilo.fonte.padrao
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.grande
                    color: btnAdicionar.down ? Qt.darker(telaCardapio.corDestaque, 1.2) : (btnAdicionar.hovered ? Qt.lighter(telaCardapio.corDestaque, 1.1) : telaCardapio.corDestaque)
                }
            }
        }

        // --- LISTA DE ITENS ---
        ListView {
            id: listaItens

            Layout.fillWidth: true
            Layout.fillHeight: true
            model: modeloVisiveis
            spacing: 8
            clip: true

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            // Mensagem para os dois casos de lista vazia: categoria sem
            // nenhum item ainda e busca sem resultado.
            Text {
                anchors.centerIn: parent
                visible: modeloVisiveis.count === 0
                text: telaCardapio.itens.length === 0 ? "Nenhum item cadastrado nesta categoria." : "Nenhum item encontrado para esta busca."
                font.pixelSize: 13
                font.italic: true
                color: "#bdc3c7"
            }

            delegate: Rectangle {
                id: linhaItem

                // Mesmo motivo do delegate das abas acima: os botões de ação
                // e os textos abaixo leem estas propriedades, não o "model"
                // do ListView (que não chega no escopo do contentItem/
                // background dos botões).
                readonly property int indiceItem: model.indiceItem
                readonly property string nome: model.nome
                readonly property string detalhe: model.detalhe
                readonly property string precos: model.precos

                width: listaItens.width - (listaItens.ScrollBar.vertical.visible ? listaItens.ScrollBar.vertical.width : 0)
                height: 64
                radius: Estilo.rounding.grande
                color: areaItem.containsMouse ? "#f7f7f7" : "#ffffff"
                border.color: Estilo.cores.borda
                border.width: 1

                // Clicar em qualquer lugar da linha abre o mesmo formulário do
                // botão de editar — o botão fica só como pista visual.
                MouseArea {
                    id: areaItem

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: telaCardapio.abrirEditor(linhaItem.indiceItem)
                }

                Row {
                    id: acoesItem

                    spacing: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter

                    Button {
                        id: btnEditar

                        width: 32
                        height: 32
                        padding: 0
                        onClicked: telaCardapio.abrirEditor(linhaItem.indiceItem)

                        contentItem: Icone {
                            nome: "fa6s.pen"
                            cor: "#ffffff"
                            tamanho: 13
                            anchors.centerIn: parent
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.padrao
                            color: btnEditar.down ? Qt.darker(telaCardapio.corDestaque, 1.2) : (btnEditar.hovered ? Qt.lighter(telaCardapio.corDestaque, 1.1) : telaCardapio.corDestaque)
                        }
                    }

                    Button {
                        id: btnRemover

                        width: 32
                        height: 32
                        padding: 0
                        onClicked: popupRemocao.abrirPara(linhaItem.indiceItem, linhaItem.nome)

                        contentItem: Icone {
                            nome: "fa6s.trash-can"
                            cor: "#ffffff"
                            tamanho: 13
                            anchors.centerIn: parent
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.padrao
                            color: btnRemover.down ? Estilo.cancelar.pressionado : (btnRemover.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                        }
                    }
                }

                Text {
                    id: textoPrecos

                    text: linhaItem.precos
                    font.pixelSize: 12
                    font.bold: true
                    color: Estilo.confirmar.normal
                    anchors.right: acoesItem.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Nome e ingredientes ocupam exatamente o espaço entre a borda
                // esquerda e o resumo de preços — assim um nome (ou uma lista
                // de ingredientes) comprido é cortado com reticências em vez
                // de passar por cima dos preços e dos botões.
                Column {
                    spacing: 3
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: textoPrecos.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        width: parent.width
                        text: linhaItem.nome
                        font.pixelSize: Estilo.fonte.padrao
                        font.bold: true
                        color: Estilo.cores.texto
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: linhaItem.detalhe !== ""
                        text: linhaItem.detalhe
                        font.pixelSize: 12
                        color: Estilo.cores.textoSecundario
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // --- BOTÃO VOLTAR ---
        Button {
            id: btnVoltar

            padding: 10
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 200
            onClicked: {
                if (telaCardapio.StackView.view)
                    telaCardapio.StackView.view.pop();
            }

            contentItem: Row {
                spacing: 6
                anchors.centerIn: parent

                Icone {
                    nome: "fa6s.arrow-left"
                    cor: "#ffffff"
                    tamanho: Estilo.fonte.padrao
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Voltar para o Menu"
                    font.bold: true
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            background: Rectangle {
                radius: Estilo.rounding.padrao
                color: btnVoltar.down ? Estilo.cancelar.pressionado : (btnVoltar.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                border.color: Estilo.cancelar.pressionado
                border.width: 1
            }
        }
    }

    // --- FORMULÁRIO DE ITEM (ADICIONAR/EDITAR) ---
    PopupItemCardapio {
        id: popupItem

        onConfirmado: function (indice, item) {
            telaCardapio.aplicarItem(indice, item);
        }
    }

    // --- CONFIRMAÇÃO DE REMOÇÃO ---
    PopupConfirmarRemocaoItem {
        id: popupRemocao

        onConfirmada: function (indice) {
            telaCardapio.removerItem(indice);
        }
    }

    // --- NOTIFICAÇÕES DE GRAVAÇÃO DO CARDÁPIO ---
    FilaNotificacoes {
        id: filaNotificacoes
    }
}
