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
    // Há edições nesta categoria que ainda não foram gravadas em disco nem
    // publicadas na malha. Só aplicarAlteracoes() zera isto.
    property bool alteracoesPendentes: false
    // Itens da categoria atual, no formato plano que o controller devolve
    // (ex: {"nome": "X-Egg", "valor.pao_baby": "16,00"}). É a lista já
    // gravada em disco: só é substituída depois de uma gravação bem-sucedida.
    property var itens: []
    readonly property var categoriaAtual: indiceCategoria >= 0 && indiceCategoria < categorias.length ? categorias[indiceCategoria] : null
    // Aba "Combos" (services/combosService.py): não é uma categoria de
    // cardápio — tem formato e tela próprios —, mas segue a mesma regra de
    // edição: mexe em memória e só vai ao disco (e à malha) em
    // aplicarAlteracoes(). Enquanto está ligada, `alteracoesPendentes` fala
    // dos combos, não dos itens da categoria.
    property bool modoCombos: false
    property var combos: []
    property var disponiveisHoje: []
    // Ligada só durante a nossa própria gravação: salvarCombos() emite
    // cardapioAlterado("combos") na hora, e sem isto o aviso de "mudou em
    // outra máquina" disparava contra a edição que acabamos de gravar.
    property bool gravandoCombos: false
    readonly property color corDestaque: modoCombos ? Estilo.category.pizza.base : (categoriaAtual ? telaCardapio.corDaCategoria(categoriaAtual.chave) : Estilo.global.text)

    // A cor de cada categoria é resolvida aqui pela chave, e não lida do
    // "cor" que services/cardapioService.py devolve junto: cor é decisão de
    // apresentação, e mantê-la no Python deixava duas paletas concorrentes —
    // o cardápio ficava com as cores antigas enquanto o resto do app seguia
    // os tokens. O Python continua mandando "cor"; esta tela só ignora.
    function corDaCategoria(chave) {
        switch (chave) {
        case "pizzas":
            return Estilo.category.pizza.base;
        case "pizzaBordas":
            return Estilo.category.borda.base;
        case "pizzaAdicionais":
            return Estilo.category.adicional.base;
        case "lanches":
        case "lanchesAdicionais":
            return Estilo.category.lanche.base;
        case "bebidas":
            return Estilo.category.bebida.base;
        case "acaiTamanhos":
        case "acaiAdicionais":
            return Estilo.category.acai.base;
        default:
            return Estilo.category.outros.base;
        }
    }

    focus: true
    // Mesmo motivo das telas de pedido: o StackView assume o controle do foco
    // ao trocar de página, então é preciso pedir foco de novo para o atalho de
    // digitar direto na busca (Keys.onPressed abaixo) continuar funcionando.
    StackView.onActivated: forceActiveFocus()
    // Redes de segurança para o fim da vida da tela. Fechar o app ou trocar de
    // página não dá chance de perguntar nada, e perder o que foi cadastrado é
    // pior que gravar — mesmo raciocínio de configuracoes/Configuracoes.qml.
    // As duas são guardadas por `alteracoesPendentes` dentro de
    // aplicarAlteracoes(): sem isso, toda saída da tela regravaria o arquivo e
    // publicaria a categoria inteira na malha sem ninguém ter mexido em nada.
    StackView.onDeactivated: aplicarAlteracoes()
    Component.onDestruction: aplicarAlteracoes()

    function carregarCategorias() {
        categorias = cardapioController.listarCategorias();
        selecionarCategoria(0);
    }

    function selecionarCategoria(indice) {
        // Trocar de categoria troca a lista inteira, e o que estivesse
        // pendente sumiria sem aviso. Aplicar antes é o mesmo raciocínio de
        // sair da tela: perder o que foi digitado é pior que gravar. Se a
        // gravação falhar, fica onde está, com o erro na tela.
        if (!aplicarAlteracoes())
            return;

        modoCombos = false;
        indiceCategoria = indice;
        campoBusca.text = "";
        carregarItens();
    }

    function abrirCombos() {
        // Mesmo motivo de selecionarCategoria: não deixar uma edição
        // pendente da categoria atual sumir ao trocar de aba.
        if (!aplicarAlteracoes())
            return;

        modoCombos = true;
        carregarCombos();
    }

    function carregarCombos() {
        combos = cardapioController.listarCombos();
        disponiveisHoje = cardapioController.disponibilidadeCombosHoje(combos);
    }

    function _editarCombos(lista, mensagem) {
        combos = lista;
        disponiveisHoje = cardapioController.disponibilidadeCombosHoje(lista);
        alteracoesPendentes = true;
        filaNotificacoes.notificar(mensagem, true);
    }

    function aplicarCombo(indice, combo) {
        var lista = combos.slice();
        if (indice < 0)
            lista.push(combo);
        else
            lista[indice] = combo;
        _editarCombos(lista, indice < 0 ? "Combo adicionado — falta aplicar." : "Combo atualizado — falta aplicar.");
    }

    function removerCombo(indice) {
        var lista = combos.slice();
        lista.splice(indice, 1);
        _editarCombos(lista, "Combo removido — falta aplicar.");
    }

    function alternarComboAtivo(indice) {
        var lista = combos.slice();
        lista[indice] = Object.assign({}, lista[indice], {"ativo": !lista[indice].ativo});
        _editarCombos(lista, lista[indice].ativo ? "Combo ativado — falta aplicar." : "Combo desativado — falta aplicar.");
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
        _editarLocal(lista, indice < 0 ? "Item adicionado — falta aplicar." : "Item atualizado — falta aplicar.");
    }

    function removerItem(indice) {
        var lista = itens.slice();
        lista.splice(indice, 1);
        _editarLocal(lista, "Item removido — falta aplicar.");
    }

    // Mexe SÓ na lista em memória. O disco (e a malha) são tocados uma vez
    // só, por aplicarAlteracoes(), pelo mesmo motivo da tela de estilo da
    // comanda: gravar a cada clique fazia o app inteiro se reiniciar no meio
    // do cadastro, porque o dev_watch observa .json (ver PREFIXOS_IGNORADOS
    // em dev_watch.py, que também precisou ser corrigido) — e mesmo sem isso,
    // cada clique publicava o cardápio inteiro na malha.
    function _editarLocal(lista, mensagem) {
        itens = lista;
        alteracoesPendentes = true;
        filtrar(campoBusca.text);
        filaNotificacoes.notificar(mensagem, true);
    }

    // Grava a lista inteira da categoria. Em caso de erro (preço inválido,
    // arquivo sem permissão de escrita...) o controller devolve a mensagem, a
    // pendência CONTINUA e nada se perde — quem chama usa o retorno pra
    // decidir se pode seguir (trocar de categoria, sair da tela).
    function aplicarAlteracoes() {
        if (modoCombos) {
            if (!alteracoesPendentes)
                return true;

            gravandoCombos = true;
            var erroCombos = cardapioController.salvarCombos(combos);
            gravandoCombos = false;
            if (erroCombos) {
                filaNotificacoes.notificar(erroCombos, false);
                return false;
            }

            alteracoesPendentes = false;
            // Relê do disco: o Python normaliza (preço "69.9" vira "69,90",
            // ids novos) e a tela deve mostrar o que ficou gravado.
            carregarCombos();
            filaNotificacoes.notificar("Combos aplicados!", true);
            return true;
        }

        if (!categoriaAtual || !alteracoesPendentes)
            return true;

        var erro = cardapioController.salvarItens(categoriaAtual.chave, itens);
        if (erro) {
            filaNotificacoes.notificar(erro, false);
            return false;
        }

        alteracoesPendentes = false;
        // Relê do disco em vez de assumir "itens": o controller normaliza os
        // preços ao gravar (ex: "24.9" vira "24,90"), e a tela deve mostrar o
        // que ficou gravado de verdade.
        carregarItens();
        filaNotificacoes.notificar("Alterações aplicadas ao cardápio!", true);
        return true;
    }

    // Mesmo atalho das telas de pedido: digitar qualquer caractere
    // "imprimível" já foca a barra de busca e entra com o que foi digitado.
    Keys.onPressed: function (event) {
        if (!telaCardapio.modoCombos && !campoBusca.activeFocus && event.key >= Qt.Key_Space && event.key <= Qt.Key_ydiaeresis) {
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
        if (chaveCategoria === "combos") {
            if (!telaCardapio.modoCombos || telaCardapio.gravandoCombos)
                return;

            if (telaCardapio.alteracoesPendentes) {
                filaNotificacoes.notificar("Os combos mudaram em outra máquina — aplique suas alterações para ver o que chegou.", false);
                return;
            }
            carregarCombos();
            return;
        }

        if (telaCardapio.modoCombos || !telaCardapio.categoriaAtual || telaCardapio.categoriaAtual.chave !== chaveCategoria)
            return;

        // Recarregar por cima de uma edição não aplicada apagaria o que o dono
        // está montando agora. O que veio da malha espera ele aplicar.
        if (telaCardapio.alteracoesPendentes) {
            filaNotificacoes.notificar("Esta categoria mudou em outra máquina — aplique suas alterações para ver o que chegou.", false);
            return;
        }

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

    // listarCategorias() lê os data/cardapio/*.json pelo Python e
    // selecionarCategoria(0) ainda preenche a lista de itens em cima disso —
    // trabalho demais pra rodar antes do primeiro pixel da página (ver
    // components/CargaDiferida.qml).
    CargaDiferida {
        id: carga

        tarefa: function() {
            carregarCategorias();
        }
    }

    Component.onCompleted: carga.agendar()

    // Itens exibidos na lista (todos, ou só os que casam com a busca)
    ListModel {
        id: modeloVisiveis
    }

    background: Rectangle {
        color: Estilo.global.background
        radius: Estilo.global.radius.xl
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: Estilo.global.spacing.xl

        // --- CABEÇALHO ---
        RowLayout {
            Layout.fillWidth: true
            spacing: Estilo.global.spacing.xl

            Row {
                spacing: Estilo.global.spacing.sm

                Icone {
                    nome: "fa6s.book-open"
                    cor: telaCardapio.corDestaque
                    tamanho: Estilo.global.fontSize.title
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "CARDÁPIO"
                    font.pixelSize: Estilo.global.fontSize.title
                    font.family: Estilo.global.fontFamily.title
                    color: telaCardapio.corDestaque
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: telaCardapio.modoCombos ? (telaCardapio.combos.length === 1 ? "1 combo" : telaCardapio.combos.length + " combos") : (telaCardapio.itens.length === 1 ? "1 item nesta categoria" : telaCardapio.itens.length + " itens nesta categoria")
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.textSecondary
            }
        }

        // --- ABAS DE CATEGORIA ---
        // Flow, e não Row: são sete categorias, e numa tela estreita a fila
        // inteira era mais larga que a janela — as últimas ficavam fora de
        // alcance, sem rolagem horizontal nenhuma. Agora elas quebram para a
        // linha de baixo.
        Flow {
            Layout.fillWidth: true
            spacing: Estilo.global.spacing.md

            Repeater {
                model: telaCardapio.categorias

                delegate: Button {
                    id: btnCategoria

                    // Capturados aqui (em vez de usar "modelData"/"index"
                    // direto lá dentro) porque contentItem e background são
                    // outro escopo, onde o modelo do Repeater não chega.
                    readonly property var categoria: modelData
                    readonly property bool ativa: telaCardapio.indiceCategoria === index && !telaCardapio.modoCombos

                    height: 42
                    padding: 14
                    onClicked: telaCardapio.selecionarCategoria(index)

                    contentItem: Row {
                        spacing: Estilo.global.spacing.sm

                        Icone {
                            nome: btnCategoria.categoria.icone
                            cor: btnCategoria.ativa ? Estilo.global.textOnAccent : telaCardapio.corDaCategoria(btnCategoria.categoria.chave)
                            tamanho: Estilo.global.fontSize.lg
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: btnCategoria.categoria.rotulo
                            font.pixelSize: Estilo.global.fontSize.lg
                            font.family: Estilo.global.fontFamily.title
                            color: btnCategoria.ativa ? Estilo.global.textOnAccent : Estilo.global.text
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnCategoria.ativa ? telaCardapio.corDaCategoria(btnCategoria.categoria.chave) : (btnCategoria.hovered ? Estilo.global.surfaceHover : Estilo.global.surface)
                        border.color: btnCategoria.ativa ? telaCardapio.corDaCategoria(btnCategoria.categoria.chave) : Estilo.global.border
                        border.width: btnCategoria.ativa ? 2 : 1

                        Behavior on color {
                            ColorAnimation {
                                duration: Estilo.global.motion.instant
                            }
                        }
                    }
                }
            }

            // A aba de combos fica depois das categorias de propósito: não é
            // um tipo de item do cardápio (ver modoCombos).
            Button {
                id: btnAbaCombos

                readonly property bool ativa: telaCardapio.modoCombos

                height: 42
                padding: 14
                onClicked: telaCardapio.abrirCombos()

                contentItem: Row {
                    spacing: Estilo.global.spacing.sm

                    Icone {
                        nome: "fa6s.tags"
                        cor: btnAbaCombos.ativa ? Estilo.global.textOnAccent : Estilo.category.pizza.base
                        tamanho: Estilo.global.fontSize.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Combos"
                        font.pixelSize: Estilo.global.fontSize.lg
                        font.family: Estilo.global.fontFamily.title
                        color: btnAbaCombos.ativa ? Estilo.global.textOnAccent : Estilo.global.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnAbaCombos.ativa ? Estilo.category.pizza.base : (btnAbaCombos.hovered ? Estilo.global.surfaceHover : Estilo.global.surface)
                    border.color: btnAbaCombos.ativa ? Estilo.category.pizza.base : Estilo.global.border
                    border.width: btnAbaCombos.ativa ? 2 : 1
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

            visible: !telaCardapio.modoCombos

            // Sem "height:" explícito aqui — dentro de um ColumnLayout,
            // isso levaria o mesmo aviso do qmllint que motivou trocar o
            // RowLayout por um Row logo abaixo. A altura de 42 já vem de
            // sobra da altura dos próprios filhos (Search/Button).
            Layout.fillWidth: true
            spacing: Estilo.global.spacing.lg

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
                    spacing: Estilo.global.spacing.sm

                    Icone {
                        nome: "fa6s.plus"
                        cor: Estilo.global.textOnAccent
                        tamanho: Estilo.global.fontSize.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: telaCardapio.categoriaAtual ? telaCardapio.categoriaAtual.novoRotulo : "Novo item"
                        font.pixelSize: Estilo.global.fontSize.lg
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnAdicionar.down ? Qt.darker(telaCardapio.corDestaque, 1.2) : (btnAdicionar.hovered ? Qt.lighter(telaCardapio.corDestaque, 1.1) : telaCardapio.corDestaque)
                }
            }
        }

        // --- LISTA DE ITENS ---
        // --- ABA COMBOS ---
        SecaoCombos {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: telaCardapio.modoCombos
            combos: telaCardapio.combos
            disponiveisHoje: telaCardapio.disponiveisHoje
            corDestaque: telaCardapio.corDestaque
            onNovo: popupCombo.abrirPara(-1, null)
            onEditar: function (indice) {
                popupCombo.abrirPara(indice, telaCardapio.combos[indice]);
            }
            onRemover: function (indice) {
                popupRemocaoCombo.abrirPara(indice, telaCardapio.combos[indice].nome);
            }
            onAlternarAtivo: function (indice) {
                telaCardapio.alternarComboAtivo(indice);
            }
        }

        ListView {
            id: listaItens

            visible: !telaCardapio.modoCombos
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: modeloVisiveis
            spacing: Estilo.global.spacing.sm
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
                font.pixelSize: Estilo.global.fontSize.md
                font.italic: true
                color: Estilo.global.textMuted
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
                radius: Estilo.global.radius.md
                color: areaItem.containsMouse ? Estilo.global.surfaceHover : Estilo.global.surface
                border.color: Estilo.global.border
                border.width: Estilo.global.borderWidth.hairline

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

                    spacing: Estilo.global.spacing.sm
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
                            cor: Estilo.global.textOnAccent
                            tamanho: 13
                            anchors.centerIn: parent
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
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
                            cor: Estilo.global.textOnAccent
                            tamanho: 13
                            anchors.centerIn: parent
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
                            color: btnRemover.down ? Estilo.action.danger.pressed : (btnRemover.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                        }
                    }
                }

                Text {
                    id: textoPrecos

                    text: linhaItem.precos
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.bold: true
                    color: Estilo.action.confirm.base
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
                        font.pixelSize: Estilo.global.fontSize.lg
                        font.bold: true
                        color: Estilo.global.text
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: linhaItem.detalhe !== ""
                        text: linhaItem.detalhe
                        font.pixelSize: Estilo.global.fontSize.sm
                        color: Estilo.global.textSecondary
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // --- APLICAR / VOLTAR ---
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Estilo.global.spacing.lg

            Button {
                id: btnAplicar

                padding: Estilo.global.padding.md
                Layout.preferredWidth: 230
                // Desabilitado quando não há nada a aplicar: é o que diferencia
                // "já está tudo gravado" de "falta aplicar", sem precisar de um
                // rótulo extra na tela (mesmo botão de Configuracoes.qml).
                enabled: telaCardapio.alteracoesPendentes
                onClicked: telaCardapio.aplicarAlteracoes()

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent

                    Icone {
                        nome: btnAplicar.enabled ? "fa6s.check" : "fa6s.circle-check"
                        cor: Estilo.global.textOnAccent
                        tamanho: Estilo.global.fontSize.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: btnAplicar.enabled ? "Aplicar alterações" : "Tudo aplicado"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnAplicar.down ? Estilo.action.confirm.pressed : (btnAplicar.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                    opacity: btnAplicar.enabled ? 1 : Estilo.global.opacity.disabled
                }
            }

            Button {
                id: btnVoltar

                padding: Estilo.global.padding.md
                Layout.preferredWidth: 200
                onClicked: {
                    if (telaCardapio.StackView.view)
                        telaCardapio.StackView.view.irParaInicio();
                }

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent

                    Icone {
                        nome: "fa6s.arrow-left"
                        cor: Estilo.global.textOnAccent
                        tamanho: Estilo.global.fontSize.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Voltar para o Menu"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnVoltar.down ? Estilo.action.danger.pressed : (btnVoltar.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                    border.color: Estilo.action.danger.pressed
                    border.width: Estilo.global.borderWidth.hairline
                }
            }
        }
    }

    // --- FORMULÁRIO DE ITEM (ADICIONAR/EDITAR) ---
    PopupItemCardapio {
        id: popupItem

        corDestaque: telaCardapio.corDestaque
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

    // --- FORMULÁRIO DE COMBO ---
    PopupCombo {
        id: popupCombo

        corDestaque: telaCardapio.corDestaque
        onConfirmado: function (indice, combo) {
            telaCardapio.aplicarCombo(indice, combo);
        }
    }

    PopupConfirmarRemocaoItem {
        id: popupRemocaoCombo

        titulo: "Remover este combo?"
        aviso: "Ele deixa de dar desconto nos pedidos novos. Comandas já feitas não mudam."

        onConfirmada: function (indice) {
            telaCardapio.removerCombo(indice);
        }
    }

    // --- NOTIFICAÇÕES DE GRAVAÇÃO DO CARDÁPIO ---
    FilaNotificacoes {
        id: filaNotificacoes
    }
}
