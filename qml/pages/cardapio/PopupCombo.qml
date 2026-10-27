import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../components"
import "../../components/Texto.js" as Texto

// Formulário de um combo promocional (novo ou existente), usado por
// Cardapio.qml na aba "Combos". O que um combo é e como o desconto é
// calculado está em services/combosService.py; este popup só monta o objeto
// no mesmo formato do combos.json e valida o que dá para valer antes de
// fechar — o Python revalida na gravação.
//
// Datas aparecem como dd/mm/aaaa (como o atendente lê) e viajam como
// "AAAA-MM-DD" (como o combos.json guarda e compara).
Popup {
    id: raiz

    // -1 = combo novo; >= 0 = índice em Cardapio.qml.combos
    property int indiceEditando: -1
    property string idCombo: ""
    property string erro: ""
    property color corDestaque: Estilo.global.text

    // Estado do formulário que não é só texto de um campo
    property var diasSelecionados: []
    property var datasAvulsas: []
    property var pizzasMarcadas: ({})
    property int quantidade: 2
    property bool ativo: true

    readonly property var rotulosDias: ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
    // Os tamanhos de pizza do cardápio; um combo antigo com outro tamanho
    // ganha o dele na lista ao abrir (ver abrirPara), para não perdê-lo.
    property var tamanhos: ["Mini", "Broto", "Grande"]
    readonly property var formatoPreco: /^(?:R\$\s*)?\d{1,5}([.,]\d{1,2})?$/
    readonly property int totalMarcadas: Object.keys(pizzasMarcadas).length

    // Texto dos campos, expostos para teste e para quem precisar preencher o
    // formulário de fora.
    property alias textoNome: campoNome.text
    property alias textoValor: campoValor.text
    property alias textoInicio: campoInicio.text
    property alias textoFim: campoFim.text
    property alias textoNovaData: campoNovaData.text
    property alias indiceTamanho: selTamanho.currentIndex

    signal confirmado(int indice, var combo)

    // Campo com máscara vazio devolve só a máscara ("//"), não "": sem
    // isto, um período em branco parecia uma data inválida.
    function semMascara(texto) {
        return String(texto || "").replace(/[\/_\s]/g, "") === "" ? "" : String(texto).trim();
    }

    // "25/12/2026" -> "2026-12-25"; vazio -> ""; inválida (ou inexistente,
    // como 31/02) -> null.
    function paraIso(texto) {
        texto = semMascara(texto);
        if (texto === "")
            return "";

        var m = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(texto);
        if (!m)
            return null;

        var d = parseInt(m[1], 10), mes = parseInt(m[2], 10), a = parseInt(m[3], 10);
        var data = new Date(a, mes - 1, d);
        if (data.getFullYear() !== a || data.getMonth() !== mes - 1 || data.getDate() !== d)
            return null;

        return m[3] + "-" + m[2] + "-" + m[1];
    }

    function paraBr(iso) {
        var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso || ""));
        return m ? m[3] + "/" + m[2] + "/" + m[1] : "";
    }

    function abrirPara(indice, combo) {
        indiceEditando = indice;
        idCombo = combo ? combo.id : "";
        erro = "";
        var agenda = combo && combo.agenda ? combo.agenda : {};

        campoNome.text = combo ? combo.nome : "";
        campoValor.text = combo ? Moeda.formatar(combo.valor) : "";
        quantidade = combo ? combo.quantidade : 2;
        ativo = combo ? combo.ativo : true;
        var lista = ["Mini", "Broto", "Grande"];
        var tamanhoDoCombo = combo ? combo.tamanho : "Grande";
        if (lista.indexOf(tamanhoDoCombo) < 0)
            lista.push(tamanhoDoCombo);
        tamanhos = lista;
        selTamanho.currentIndex = lista.indexOf(tamanhoDoCombo);

        diasSelecionados = (agenda.dias || []).slice();
        datasAvulsas = (agenda.datas || []).slice();
        campoInicio.text = paraBr(agenda.inicio);
        campoFim.text = paraBr(agenda.fim);
        campoNovaData.text = "";
        campoBuscaPizza.text = "";

        var marcadas = {};
        var nomes = combo ? combo.pizzas : [];
        for (var i = 0; i < nomes.length; i++)
            marcadas[nomes[i]] = true;
        pizzasMarcadas = marcadas;

        carregarPizzas();
        open();
        campoNome.forceActiveFocus();
    }

    // Todas as pizzas do cardápio, mais as marcadas que não existem mais lá
    // (pizza renomeada ou removida) — assim o dono vê e pode desmarcar o que
    // ficou órfão em vez de o combo guardar um nome fantasma sem ninguém ver.
    property var nomesPizzas: []

    function carregarPizzas() {
        var nomes = [];
        var vistos = {};
        var itens = cardapioController.listarItens("pizzas");
        for (var i = 0; i < itens.length; i++) {
            var nome = itens[i].nome || "";
            if (nome !== "" && !vistos[nome]) {
                vistos[nome] = true;
                nomes.push(nome);
            }
        }
        for (var marcada in pizzasMarcadas) {
            if (!vistos[marcada])
                nomes.push(marcada);
        }
        nomesPizzas = nomes;
        filtrarPizzas();
    }

    function filtrarPizzas() {
        modeloPizzas.clear();
        var busca = Texto.normalizar(campoBuscaPizza.text.trim());
        for (var i = 0; i < nomesPizzas.length; i++) {
            if (busca === "" || Texto.normalizar(nomesPizzas[i]).indexOf(busca) !== -1)
                modeloPizzas.append({"nome": nomesPizzas[i]});

        }
    }

    function marcar(nome, marcado) {
        var copia = Object.assign({}, pizzasMarcadas);
        if (marcado)
            copia[nome] = true;
        else
            delete copia[nome];
        pizzasMarcadas = copia;
    }

    function marcarVisiveis(marcado) {
        var copia = Object.assign({}, pizzasMarcadas);
        for (var i = 0; i < modeloPizzas.count; i++) {
            if (marcado)
                copia[modeloPizzas.get(i).nome] = true;
            else
                delete copia[modeloPizzas.get(i).nome];
        }
        pizzasMarcadas = copia;
    }

    function alternarDia(dia) {
        var lista = diasSelecionados.slice();
        var posicao = lista.indexOf(dia);
        if (posicao >= 0)
            lista.splice(posicao, 1);
        else
            lista.push(dia);
        lista.sort();
        diasSelecionados = lista;
    }

    // Atalho para o caso comum: marca exatamente estes dias.
    function definirDias(dias) {
        diasSelecionados = dias.slice();
    }

    function adicionarData() {
        var iso = paraIso(campoNovaData.text);
        if (iso === null || iso === "") {
            erro = "Informe a data avulsa como dd/mm/aaaa (ex: 25/12/2026).";
            return;
        }
        erro = "";
        if (datasAvulsas.indexOf(iso) === -1) {
            var lista = datasAvulsas.slice();
            lista.push(iso);
            lista.sort();
            datasAvulsas = lista;
        }
        campoNovaData.text = "";
    }

    function removerData(iso) {
        datasAvulsas = datasAvulsas.filter(function (d) {
            return d !== iso;
        });
    }

    function confirmar() {
        var nome = campoNome.text.trim();
        if (nome === "") {
            erro = "Dê um nome ao combo.";
            return;
        }
        if (!formatoPreco.test(campoValor.text.trim())) {
            erro = "O valor do combo precisa ser um preço como 69,90.";
            return;
        }
        var valor = Moeda.formatarSemSimbolo(campoValor.text);
        if (valor === "" || Moeda.paraNumero(valor) <= 0) {
            erro = "O valor do combo precisa ser maior que zero.";
            return;
        }
        if (selTamanho.currentIndex < 0) {
            erro = "Escolha o tamanho das pizzas.";
            return;
        }
        if (totalMarcadas === 0) {
            erro = "Marque ao menos uma pizza que participa do combo.";
            return;
        }
        var inicio = paraIso(campoInicio.text);
        var fim = paraIso(campoFim.text);
        if (inicio === null || fim === null) {
            erro = "As datas do período precisam estar como dd/mm/aaaa.";
            return;
        }
        if (inicio !== "" && fim !== "" && inicio > fim) {
            erro = "O período termina antes de começar.";
            return;
        }
        // Campo digitado e esquecido sem apertar "Adicionar": avisa em vez de
        // perder a data em silêncio.
        if (semMascara(campoNovaData.text) !== "") {
            erro = "Há uma data avulsa digitada que não foi adicionada. Toque em \"Adicionar\" ou apague.";
            return;
        }
        // Sem dia, período nem data o combo vale todo dia: é válido, e a lista
        // mostra "Todos os dias" para não passar despercebido.
        confirmado(indiceEditando, {
            "id": idCombo,
            "nome": nome,
            "valor": valor,
            "quantidade": quantidade,
            "tamanho": tamanhos[selTamanho.currentIndex],
            "pizzas": Object.keys(pizzasMarcadas),
            "ativo": ativo,
            "agenda": {
                "dias": diasSelecionados,
                "inicio": inicio,
                "fim": fim,
                "datas": datasAvulsas
            }
        });
        close();
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    height: Math.min(implicitHeight, Responsivo.alturaPopup(implicitHeight))

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    ListModel {
        id: modeloPizzas
    }

    // Campo de texto no estilo dos formulários do cardápio
    component CampoCombo: TextField {
        id: campo

        height: 40
        font.pixelSize: Estilo.global.fontSize.lg
        color: Estilo.global.textInput
        leftPadding: 12
        rightPadding: 12
        selectByMouse: true
        placeholderTextColor: Estilo.global.textPlaceholder

        background: Rectangle {
            radius: Estilo.global.radius.pill
            color: Estilo.global.inputBackground
            border.color: campo.activeFocus ? raiz.corDestaque : Estilo.global.border
            border.width: campo.activeFocus ? 2 : 1
        }
    }

    component Rotulo: Text {
        font.pixelSize: Estilo.global.fontSize.sm
        font.bold: true
        color: Estilo.global.textSecondary
    }

    // Botão-pílula pequeno (chip) ligado/desligado
    component Chip: Button {
        id: chip

        property bool marcado: false

        padding: 10
        implicitHeight: 34

        contentItem: Text {
            text: chip.text
            font.pixelSize: Estilo.global.fontSize.md
            font.bold: chip.marcado
            color: chip.marcado ? Estilo.global.textOnAccent : Estilo.global.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            radius: Estilo.global.radius.pill
            color: chip.marcado ? raiz.corDestaque : (chip.hovered ? Estilo.global.surfaceHover : Estilo.global.surface)
            border.color: chip.marcado ? raiz.corDestaque : Estilo.global.border
            border.width: Estilo.global.borderWidth.hairline
        }
    }

    contentItem: Flickable {
        contentWidth: width
        contentHeight: colunaCombo.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        implicitWidth: colunaCombo.implicitWidth
        implicitHeight: colunaCombo.implicitHeight

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Column {
            id: colunaCombo

            spacing: 16
            width: Responsivo.larguraPopup(520)

            Row {
                spacing: Estilo.global.spacing.sm

                Icone {
                    nome: "fa6s.tags"
                    cor: raiz.corDestaque
                    tamanho: 17
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: raiz.indiceEditando < 0 ? "Novo combo" : "Editar combo"
                    font.pixelSize: Estilo.global.fontSize.xl
                    font.bold: true
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // --- NOME ---
            Column {
                width: parent.width
                spacing: 5

                Rotulo {
                    text: "Nome do combo"
                }

                CampoCombo {
                    id: campoNome

                    width: parent.width
                    placeholderText: "Ex: Duas grandes"
                }
            }

            // --- VALOR / QUANTIDADE / TAMANHO ---
            Row {
                width: parent.width
                spacing: Estilo.global.spacing.lg

                Column {
                    width: (parent.width - parent.spacing * 2) * 0.4
                    spacing: 5

                    Rotulo {
                        text: "Valor do combo"
                    }

                    CampoCombo {
                        id: campoValor

                        width: parent.width
                        placeholderText: "0,00"
                        validator: Moeda.validador
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        onActiveFocusChanged: {
                            if (activeFocus) {
                                text = Moeda.paraEdicao(text);
                                selectAll();
                            } else {
                                text = Moeda.formatar(text);
                            }
                        }
                    }
                }

                Column {
                    width: (parent.width - parent.spacing * 2) * 0.3
                    spacing: 5

                    Rotulo {
                        text: "Nº de pizzas"
                    }

                    SpinBox {
                        width: parent.width
                        height: 40
                        from: 2
                        to: 10
                        editable: true
                        value: raiz.quantidade
                        onValueModified: raiz.quantidade = value
                    }
                }

                Column {
                    width: (parent.width - parent.spacing * 2) * 0.3
                    spacing: 5

                    Rotulo {
                        text: "Tamanho"
                    }

                    ComboBox {
                        id: selTamanho

                        width: parent.width
                        height: 40
                        model: raiz.tamanhos
                    }
                }
            }

            // --- ATIVO ---
            Row {
                spacing: Estilo.global.spacing.md

                Switch {
                    id: chaveAtivo

                    checked: raiz.ativo
                    onToggled: raiz.ativo = checked
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: raiz.ativo ? "Combo ativo" : "Combo desativado (não aplica desconto)"
                    font.pixelSize: Estilo.global.fontSize.md
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // --- DIAS DA SEMANA ---
            Column {
                width: parent.width
                spacing: 8

                Rotulo {
                    text: "Dias da semana (vazio = todos os dias)"
                }

                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: raiz.rotulosDias

                        delegate: Chip {
                            required property int index
                            required property string modelData

                            text: modelData
                            marcado: raiz.diasSelecionados.indexOf(index) >= 0
                            onClicked: raiz.alternarDia(index)
                        }
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 6

                    Chip {
                        text: "Seg–Qui"
                        onClicked: raiz.definirDias([1, 2, 3, 4])
                    }

                    Chip {
                        text: "Sex–Dom"
                        onClicked: raiz.definirDias([5, 6, 0])
                    }

                    Chip {
                        text: "Seg–Sex"
                        onClicked: raiz.definirDias([1, 2, 3, 4, 5])
                    }

                    Chip {
                        text: "Fim de semana"
                        onClicked: raiz.definirDias([0, 6])
                    }

                    Chip {
                        text: "Limpar"
                        onClicked: raiz.definirDias([])
                    }
                }
            }

            // --- PERÍODO ---
            Column {
                width: parent.width
                spacing: 5

                Rotulo {
                    text: "Período (opcional) — combina com os dias da semana"
                }

                Row {
                    spacing: Estilo.global.spacing.md

                    // Rótulos próprios: com inputMask o placeholder dá lugar
                    // ao "__/__/____" e não diria qual campo é qual.
                    Column {
                        spacing: 4

                        Rotulo {
                            text: "De"
                        }

                        CampoCombo {
                            id: campoInicio

                            width: (colunaCombo.width - Estilo.global.spacing.md) / 2
                            inputMask: "99/99/9999;_"
                        }
                    }

                    Column {
                        spacing: 4

                        Rotulo {
                            text: "Até"
                        }

                        CampoCombo {
                            id: campoFim

                            width: (colunaCombo.width - Estilo.global.spacing.md) / 2
                            inputMask: "99/99/9999;_"
                        }
                    }
                }
            }

            // --- DATAS AVULSAS ---
            Column {
                width: parent.width
                spacing: 8

                Rotulo {
                    text: "Datas avulsas, como feriados (valem mesmo fora dos dias acima)"
                }

                Row {
                    spacing: Estilo.global.spacing.md

                    CampoCombo {
                        id: campoNovaData

                        width: colunaCombo.width - btnAddData.width - Estilo.global.spacing.md
                        placeholderText: "dd/mm/aaaa"
                        inputMask: "99/99/9999;_"
                        onAccepted: raiz.adicionarData()
                    }

                    Button {
                        id: btnAddData

                        height: 40
                        padding: 14
                        onClicked: raiz.adicionarData()

                        contentItem: Text {
                            text: "Adicionar"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
                            color: btnAddData.down ? Qt.darker(raiz.corDestaque, 1.2) : (btnAddData.hovered ? Qt.lighter(raiz.corDestaque, 1.1) : raiz.corDestaque)
                        }
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: raiz.datasAvulsas

                        delegate: Chip {
                            required property string modelData

                            text: raiz.paraBr(modelData) + "  ✕"
                            marcado: true
                            onClicked: raiz.removerData(modelData)
                        }
                    }
                }
            }

            // --- PIZZAS ELEGÍVEIS ---
            Column {
                width: parent.width
                spacing: 8

                Rotulo {
                    text: "Pizzas que participam (" + raiz.totalMarcadas + " marcadas)"
                }

                CampoCombo {
                    id: campoBuscaPizza

                    width: parent.width
                    placeholderText: "Buscar pizza..."
                    onTextChanged: raiz.filtrarPizzas()
                }

                Row {
                    spacing: 6

                    Chip {
                        text: "Marcar todas da busca"
                        onClicked: raiz.marcarVisiveis(true)
                    }

                    Chip {
                        text: "Desmarcar da busca"
                        onClicked: raiz.marcarVisiveis(false)
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 220
                    radius: Estilo.global.radius.md
                    color: Estilo.global.surface
                    border.color: Estilo.global.border
                    border.width: Estilo.global.borderWidth.hairline

                    ListView {
                        id: listaPizzas

                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true
                        model: modeloPizzas
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        delegate: CheckBox {
                            required property string nome

                            width: listaPizzas.width
                            height: 34
                            text: nome
                            checked: raiz.pizzasMarcadas[nome] === true
                            onToggled: raiz.marcar(nome, checked)

                            contentItem: Text {
                                leftPadding: parent.indicator.width + 8
                                text: parent.text
                                font.pixelSize: Estilo.global.fontSize.md
                                color: Estilo.global.text
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Row {
                spacing: Estilo.global.spacing.sm
                visible: raiz.erro !== ""
                width: parent.width

                Icone {
                    nome: "fa6s.triangle-exclamation"
                    cor: Estilo.action.danger.base
                    tamanho: 13
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: raiz.erro
                    font.pixelSize: Estilo.global.fontSize.sm
                    color: Estilo.action.danger.base
                    width: parent.width - 21
                    wrapMode: Text.WordWrap
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                spacing: Estilo.global.spacing.lg
                anchors.right: parent.right

                Button {
                    id: btnCancelar

                    text: "Cancelar"
                    padding: Estilo.global.padding.md
                    onClicked: raiz.close()

                    contentItem: Text {
                        text: btnCancelar.text
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnCancelar.down ? Estilo.action.neutral.pressed : (btnCancelar.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                    }
                }

                Button {
                    id: btnSalvar

                    padding: Estilo.global.padding.md
                    onClicked: raiz.confirmar()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent

                        Icone {
                            nome: "fa6s.floppy-disk"
                            cor: Estilo.global.textOnAccent
                            tamanho: Estilo.global.fontSize.lg
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "Salvar"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnSalvar.down ? Estilo.action.confirm.pressed : (btnSalvar.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                        border.color: Estilo.action.confirm.pressed
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }
            }
        }
    }
}
