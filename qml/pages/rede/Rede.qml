import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

// Mostra as máquinas atualmente conectadas na malha local (ver
// services/rede/redeService.py) — quem está compartilhando pedidos com esta
// instância agora, desde quando, e o endereço de cada uma.
Page {
    id: telaRede

    // ===== MEDIDAS DO LAYOUT =====
    // A lista de máquinas/histórico e o painel de impressora dividiam a
    // largura em dois — o segundo com 240px fixos. Numa tela estreita
    // sobravam ~200px para o primeiro, e o texto de estado vazio ("nenhuma
    // outra máquina conectada...") vazava para fora da coluna.
    readonly property real larguraUtil: width - Estilo.global.padding.xl * 2
    readonly property bool empilhado: larguraUtil < 760

    objectName: "telaRede"

    property var _todosPeers: []
    // Dados da impressora que esta máquina usaria agora (ver
    // BalcaoController.consultarImpressoraAtual/infoImpressoraPronta) — {}
    // antes da primeira resposta, e enquanto carregandoImpressora for true.
    property var infoImpressora: ({})
    property bool carregandoImpressora: false
    // Dados da impressora que a malha está de fato usando pra imprimir as
    // comandas agora (ver RedeService.impressoraPrincipal/
    // _recalcular_maquina_impressora) — pode ser esta máquina ou outra;
    // {} enquanto nenhuma máquina conhecida tem impressora.
    property var infoImpressoraPrincipal: ({})
    // Máquinas que anunciam impressora agora (esta + peers) — opções do
    // combo de seleção manual abaixo (ver RedeService.candidatosImpressora).
    property var candidatosImpressora: []

    function carregarPeers() {
        telaRede._todosPeers = redeController.listarPeers();
        modeloPeers.clear();
        for (var i = 0; i < telaRede._todosPeers.length; i++) {
            modeloPeers.append(telaRede._todosPeers[i]);
        }
    }

    // Lê o histórico da malha (ver services/rede/historicoEventos.py). É um
    // JSON local pequeno, já limitado pela retenção do próprio módulo, então
    // pode ser lido direto como a lista de peers.
    function carregarHistorico() {
        if (!redeController)
            return;

        var eventos = redeController.listarHistorico(200);
        modeloHistorico.clear();
        for (var i = 0; i < eventos.length; i++)
            modeloHistorico.append({ "evento": eventos[i] });
    }

    // Local, sem I/O externo (RedeService já mantém a eleição pronta) —
    // pode ser chamada direto, sem precisar de thread nem sinal de retorno.
    function carregarImpressoraPrincipal() {
        telaRede.infoImpressoraPrincipal = redeController.impressoraPrincipal();
    }

    // Idem — só lê o que o RedeService já mantém em memória.
    function carregarCandidatosImpressora() {
        telaRede.candidatosImpressora = redeController.candidatosImpressora();
    }

    // Chamado pelo combo de seleção manual (ver comboImpressoraPrincipal
    // abaixo): índice 0 é sempre "Automático" (volta pra eleição por
    // prioridade de porta); os demais mapeiam 1:1 pra candidatosImpressora.
    function selecionarImpressoraPrincipal(index) {
        var nomeMaquina = index <= 0 ? "" : telaRede.candidatosImpressora[index - 1].nomeMaquina;
        redeController.fixarImpressoraPrincipal(nomeMaquina);
    }

    // Só dispara a busca (services/printer/* roda lpstat/PowerShell, que
    // pode levar alguns segundos) — não bloqueia esta chamada. O resultado
    // chega depois pelo sinal infoImpressoraPronta, conectado abaixo.
    function carregarImpressora() {
        telaRede.carregandoImpressora = true;
        balcaoController.consultarImpressoraAtual();
    }

    // "3600" -> "1h 0min"; usado tanto na lista quanto atualizado a cada
    // tique do timer abaixo, sem precisar reconsultar a rede.
    function formatarDuracao(segundos) {
        segundos = Math.max(0, Math.floor(segundos));
        if (segundos < 60)
            return segundos + "s";
        var minutos = Math.floor(segundos / 60);
        if (minutos < 60)
            return minutos + "min";
        var horas = Math.floor(minutos / 60);
        return horas + "h " + (minutos % 60) + "min";
    }

    // Conexões declarativas, não .connect() soltos em Component.onCompleted
    // — redeController/balcaoController são globais que vivem pra sempre;
    // um Connections é filho desta página e se desliga sozinho quando ela
    // é destruída, em vez de acumular uma conexão morta a cada vez que
    // esta tela é recriada (todo clique na barra lateral, ver
    // LateralBar.qml/Balcao.qml).
    Connections {
        target: redeController

        function onPeersMudaram() {
            carregarPeers();
            carregarCandidatosImpressora();
            // Entrar/sair da malha é justamente um dos eventos do histórico
            // (ver historicoEventos.registrar_local em RedeService), então
            // vale recarregar junto.
            carregarHistorico();
        }

        function onImpressoraPrincipalMudou() {
            carregarImpressoraPrincipal();
            carregarCandidatosImpressora();
        }
    }

    Connections {
        target: balcaoController

        function onInfoImpressoraPronta(info) {
            telaRede.infoImpressora = info;
            telaRede.carregandoImpressora = false;
        }
    }

    Component.onCompleted: {
        // A lista de peers já é local (sem I/O externo) — carrega e mostra
        // a página na hora. A impressora só é buscada depois, em thread,
        // pra não atrasar a abertura da tela.
        carregarPeers();
        carregarHistorico();
        carregarImpressora();
        carregarImpressoraPrincipal();
        carregarCandidatosImpressora();
    }
    StackView.onActivated: {
        carregarPeers();
        carregarHistorico();
        carregarImpressora();
        carregarImpressoraPrincipal();
        carregarCandidatosImpressora();
    }

    // Só para as durações ("conectado há...") avançarem sozinhas na tela,
    // sem precisar reconsultar a rede a cada segundo.
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: relogio.agora = Date.now()
    }
    QtObject {
        id: relogio
        property real agora: Date.now()
    }

    background: Rectangle {
        color: Estilo.global.background
        radius: Estilo.global.radius.xl
    }

    ListModel {
        id: modeloPeers
    }

    ListModel {
        id: modeloHistorico
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
                Icone { nome: "fa6s.globe"; cor: Estilo.screen.rede.accent; tamanho: Estilo.global.fontSize.title; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "REDE LOCAL"
                    font.pixelSize: Estilo.global.fontSize.title
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.screen.rede.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Button {
                id: btnAtualizarRede

                padding: 8
                onClicked: {
                    telaRede.carregarPeers();
                    telaRede.carregarImpressora();
                    // Força uma nova checagem da impressora desta máquina
                    // agora (em vez de esperar o próximo tique de 30s do
                    // RedeService) — cobre o caso comum de acabar de
                    // plugar a impressora na USB e clicar em Atualizar
                    // esperando a reeleição imediata. O resultado chega
                    // depois, de forma assíncrona (ver
                    // RedeService.verificarImpressoraLocal); quando a
                    // eleição realmente mudar, impressoraPrincipalMudou
                    // (já conectado acima) atualiza infoImpressoraPrincipal
                    // sozinho — chamar aqui também cobre o caso de outra
                    // máquina já ter sido reeleita antes deste clique.
                    redeController.verificarImpressoraLocal();
                    telaRede.carregarImpressoraPrincipal();
                    telaRede.carregarCandidatosImpressora();
                }

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    Icone { nome: "fa6s.arrows-rotate"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Atualizar"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        verticalAlignment: Text.AlignVCenter
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: parent.down ? Estilo.screen.rede.pressed : (parent.hovered ? Estilo.screen.rede.hover : Estilo.screen.rede.base)
                }
            }
        }

        // --- ESTA MÁQUINA ---
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: linhaEstaMaquina.implicitHeight + 20
            radius: Estilo.global.radius.md
            color: Estilo.status.info.background
            border.color: Estilo.status.info.border
            border.width: Estilo.global.borderWidth.hairline

            RowLayout {
                id: linhaEstaMaquina
                anchors.fill: parent
                anchors.margins: 10
                spacing: Estilo.global.spacing.md

                Icone {
                    nome: "fa6s.desktop"
                    cor: Estilo.global.text
                    tamanho: Estilo.global.fontSize.title
                }

                ColumnLayout {
                    spacing: 2

                    Text {
                        text: "Esta máquina: " + redeController.nomeLocal + " (" + redeController.letraLocal + ")"
                        font.bold: true
                        font.pixelSize: Estilo.global.fontSize.lg
                        color: Estilo.global.text
                    }

                    Text {
                        text: "Compartilhando pedidos com " + redeController.quantidadeConectados + " máquina(s) na rede local"
                        font.pixelSize: Estilo.global.fontSize.xs
                        color: Estilo.global.textSecondary
                    }
                }
            }
        }

        // --- SERVIDOR CENTRAL (ppgs_server, máquina Alpine) ---
        // Diferente da malha local acima (P2P entre as máquinas do balcão),
        // este é o backend HTTP separado que guarda endereços de entrega
        // (ver services/pizzeriaServerService.py, usado por Entrega.qml) —
        // reflete pizzeriaServerController.conectado, que o service mantém
        // com um ping periódico de 30s.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: linhaServidorCentral.implicitHeight + 20
            radius: Estilo.global.radius.md
            color: pizzeriaServerController.conectado ? Estilo.status.success.background : Estilo.status.error.background
            border.color: pizzeriaServerController.conectado ? Estilo.status.success.border : Estilo.status.error.border
            border.width: Estilo.global.borderWidth.hairline

            RowLayout {
                id: linhaServidorCentral
                anchors.fill: parent
                anchors.margins: 10
                spacing: Estilo.global.spacing.md

                Icone {
                    nome: pizzeriaServerController.conectado ? "fa6s.server" : "fa6s.triangle-exclamation"
                    cor: pizzeriaServerController.conectado ? Estilo.status.success.content : Estilo.status.error.content
                    tamanho: Estilo.global.fontSize.title
                }

                ColumnLayout {
                    spacing: 2

                    Text {
                        text: pizzeriaServerController.conectado ? "Servidor central conectado" : "Servidor central inacessível"
                        font.bold: true
                        font.pixelSize: Estilo.global.fontSize.lg
                        color: pizzeriaServerController.conectado ? Estilo.status.success.content : Estilo.status.error.content
                    }

                    Text {
                        text: pizzeriaServerController.conectado ? ("Autofill de endereço disponível (" + pizzeriaServerController.urlServidor + ")") : ("Não foi possível falar com " + pizzeriaServerController.urlServidor + " — autofill de endereço na Entrega fica indisponível.")
                        font.pixelSize: Estilo.global.fontSize.xs
                        color: Estilo.global.textSecondary
                        wrapMode: Text.WordWrap
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Button {
                    padding: 8
                    onClicked: pizzeriaServerController.verificarConexao()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        Icone { nome: "fa6s.arrows-rotate"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.md; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Testar agora"
                            font.family: Estilo.global.fontFamily.title
                            font.pixelSize: Estilo.global.fontSize.sm
                            color: Estilo.global.textOnAccent
                            verticalAlignment: Text.AlignVCenter
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.screen.rede.pressed : (parent.hovered ? Estilo.screen.rede.hover : Estilo.screen.rede.base)
                    }
                }
            }
        }

        // --- MÁQUINAS CONECTADAS (esquerda) + IMPRESSORA DESTA MÁQUINA (direita) ---
        // Máquinas/histórico e impressora lado a lado enquanto couberem;
        // empilhados quando não couberem.
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: telaRede.empilhado ? 1 : 2
            columnSpacing: Estilo.global.spacing.xl
            rowSpacing: Estilo.global.spacing.xl

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Estilo.global.spacing.sm

                Text {
                    text: "Máquinas conectadas (" + modeloPeers.count + ")"
                    font.pixelSize: Estilo.global.fontSize.lg
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                ListView {
                    Layout.fillWidth: true
                    // Só a altura do conteúdo (com um teto): a malha tem no
                    // máximo 4 máquinas, e deixar esta lista esticar sobrava
                    // um vão enorme entre ela e o histórico logo abaixo. Quem
                    // cresce com a janela é o histórico, que é a lista longa.
                    Layout.preferredHeight: Math.max(90, Math.min(contentHeight, 220))
                    clip: true
                    spacing: Estilo.global.spacing.sm
                    model: modeloPeers

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    // Estado vazio: nenhuma outra instância do app foi
                    // encontrada ainda na rede local (pode levar alguns
                    // segundos após abrir).
                    Text {
                        anchors.centerIn: parent
                        visible: modeloPeers.count === 0
                        text: "Nenhuma outra máquina conectada ainda.\nAbra o sistema nas outras máquinas da rede local para elas aparecerem aqui."
                        horizontalAlignment: Text.AlignHCenter
                        // Preso à largura da lista e quebrando linha: as duas
                        // frases longas eram mais largas que a coluna numa
                        // tela estreita e vazavam pelos dois lados dela.
                        width: parent.width - Estilo.global.padding.xl * 2
                        wrapMode: Text.WordWrap
                        color: Estilo.global.textSecondary
                        font.pixelSize: Estilo.global.fontSize.lg
                    }

                    delegate: Rectangle {
                        width: ListView.view.width - (ListView.view.ScrollBar.vertical.visible ? ListView.view.ScrollBar.vertical.width : 0)
                        height: colunaPeer.implicitHeight + 20
                        radius: Estilo.global.radius.md
                        color: Estilo.global.surface
                        border.color: Estilo.global.borderCard
                        border.width: Estilo.global.borderWidth.hairline

                        RowLayout {
                            id: colunaPeer
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 10
                            spacing: Estilo.global.spacing.md

                            Icone {
                                nome: "fa6s.desktop"
                                cor: Estilo.global.text
                                tamanho: Estilo.global.fontSize.title
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: model.nome
                                    font.bold: true
                                    font.pixelSize: Estilo.global.fontSize.lg
                                    color: Estilo.global.text
                                }

                                Text {
                                    text: model.endereco
                                    font.pixelSize: Estilo.global.fontSize.xs
                                    color: Estilo.global.textSecondary
                                }
                            }

                            Text {
                                text: "conectado há " + telaRede.formatarDuracao(relogio.agora / 1000 - model.conectadoEm)
                                font.pixelSize: Estilo.global.fontSize.xs
                                color: Estilo.global.textSecondary
                            }
                        }
                    }
                }

                // --- HISTÓRICO DA MALHA ---
                // O que aconteceu na rede, de todas as máquinas, não só desta
                // (ver services/rede/historicoEventos.py: o histórico é um
                // domínio sincronizado, então quem entra na malha recebe o
                // acumulado de quem já estava). Antes desta tela, o único
                // rastro de "o que aconteceu" eram os prints em logs/app.log.
                Text {
                    text: "Histórico da rede"
                    font.pixelSize: Estilo.global.fontSize.lg
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Estilo.global.spacing.xs
                    model: modeloHistorico

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: modeloHistorico.count === 0
                        text: "Nada registrado ainda.\nComandas, cardápio, caixa e configurações aparecem aqui conforme forem mudando."
                        horizontalAlignment: Text.AlignHCenter
                        color: Estilo.global.textSecondary
                        font.pixelSize: Estilo.global.fontSize.lg
                    }

                    // `evento` é preenchido pelo Qt a partir do papel de mesmo
                    // nome do ListModel, por ser declarado required lá dentro
                    // (ver ItemHistorico.qml).
                    delegate: ItemHistorico {
                        width: ListView.view.width - (ListView.view.ScrollBar.vertical.visible ? ListView.view.ScrollBar.vertical.width : 0)
                        agoraSegundos: relogio.agora / 1000
                        formatarDuracao: telaRede.formatarDuracao
                    }
                }
            }

            // --- IMPRESSORA DESTA MÁQUINA ---
            ColumnLayout {
                Layout.preferredWidth: telaRede.empilhado ? telaRede.larguraUtil : 240
                Layout.fillWidth: telaRede.empilhado
                Layout.alignment: Qt.AlignTop
                spacing: Estilo.global.spacing.sm

                // --- IMPRESSORA PRINCIPAL (a que a malha está usando pra
                // imprimir agora — ver RedeService.impressoraPrincipal) ---
                Text {
                    text: "Impressora principal"
                    font.pixelSize: Estilo.global.fontSize.lg
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: colunaImpressoraPrincipal.implicitHeight + 20
                    radius: Estilo.global.radius.md
                    color: Estilo.global.surface
                    border.color: Estilo.global.borderCard
                    border.width: Estilo.global.borderWidth.hairline

                    ColumnLayout {
                        id: colunaImpressoraPrincipal
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: Estilo.global.spacing.xs

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Estilo.global.spacing.sm

                            Icone {
                                nome: telaRede.infoImpressoraPrincipal.nome ? "fa6s.print" : "fa6s.ban"
                                cor: telaRede.infoImpressoraPrincipal.nome ? Estilo.global.text : Estilo.global.textSecondary
                                tamanho: Estilo.global.fontSize.title
                            }

                            Text {
                                Layout.fillWidth: true
                                text: telaRede.infoImpressoraPrincipal.nome ? telaRede.infoImpressoraPrincipal.nome : "Nenhuma impressora disponível na rede"
                                font.bold: true
                                font.pixelSize: Estilo.global.fontSize.lg
                                color: Estilo.global.text
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !!telaRede.infoImpressoraPrincipal.fixadoManualmente
                            text: "Selecionada manualmente"
                            font.pixelSize: Estilo.global.fontSize.xs
                            font.italic: true
                            color: Estilo.screen.rede.accent
                        }

                        // Detalhes só fazem sentido quando alguma máquina da
                        // malha está de fato servindo de impressora agora.
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !!telaRede.infoImpressoraPrincipal.nome
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: telaRede.infoImpressoraPrincipal.local ? "Conectada nesta máquina" : ("Conectada na máquina " + telaRede.infoImpressoraPrincipal.maquina)
                                font.pixelSize: Estilo.global.fontSize.xs
                                color: Estilo.global.textSecondary
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!telaRede.infoImpressoraPrincipal.fabricante
                                text: telaRede.infoImpressoraPrincipal.fabricante + (telaRede.infoImpressoraPrincipal.modelo ? " · " + telaRede.infoImpressoraPrincipal.modelo : "")
                                font.pixelSize: Estilo.global.fontSize.xs
                                color: Estilo.global.textSecondary
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!telaRede.infoImpressoraPrincipal.tipoPorta
                                text: "Porta: " + telaRede.infoImpressoraPrincipal.porta + " (" + telaRede.infoImpressoraPrincipal.tipoPorta + ")"
                                font.pixelSize: Estilo.global.fontSize.xs
                                color: Estilo.global.textSecondary
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !telaRede.infoImpressoraPrincipal.nome
                            text: "Os pedidos continuam sendo salvos normalmente — só a impressão fica indisponível até alguma máquina da rede ter uma impressora conectada."
                            font.pixelSize: Estilo.global.fontSize.xs
                            color: Estilo.global.textSecondary
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Text {
                    text: "Escolher manualmente"
                    font.pixelSize: Estilo.global.fontSize.lg
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                ComboBox {
                    id: comboImpressoraPrincipal

                    Layout.fillWidth: true
                    // Índice 0 é sempre "Automático" — os demais mapeiam
                    // 1:1 pra telaRede.candidatosImpressora (ver
                    // selecionarImpressoraPrincipal).
                    model: ["Automático"].concat(telaRede.candidatosImpressora.map(function (c) {
                        return c.nomeMaquina + " — " + (c.nomeImpressora || "impressora");
                    }))
                    // Refaz o índice sempre que a lista de candidatos ou a
                    // fixação atual mudar — currentIndex não é um binding
                    // vivo pro usuário (o combo deixa o usuário mudar
                    // livremente), então é recalculado explicitamente aqui
                    // em vez de um binding direto.
                    function sincronizarSelecao() {
                        var nomeFixado = redeController.nomeMaquinaFixada;
                        if (!nomeFixado) {
                            currentIndex = 0;
                            return;
                        }
                        for (var i = 0; i < telaRede.candidatosImpressora.length; i++) {
                            if (telaRede.candidatosImpressora[i].nomeMaquina === nomeFixado) {
                                currentIndex = i + 1;
                                return;
                            }
                        }
                        currentIndex = 0;
                    }
                    Component.onCompleted: sincronizarSelecao()
                    Connections {
                        target: telaRede
                        function onCandidatosImpressoraChanged() {
                            comboImpressoraPrincipal.sincronizarSelecao();
                        }
                    }
                    onActivated: telaRede.selecionarImpressoraPrincipal(currentIndex)

                    // Ver o comentário do mesmo delegate em
                    // components/CamposPagamento.qml.
                    delegate: ItemDelegate {
                        width: comboImpressoraPrincipal.width
                        text: modelData
                        highlighted: comboImpressoraPrincipal.highlightedIndex === index
                        palette.text: Estilo.global.textInput
                        palette.highlightedText: Estilo.global.textInput
                    }

                    contentItem: Text {
                        text: comboImpressoraPrincipal.displayText
                        color: Estilo.global.textInput
                        leftPadding: 10
                        rightPadding: 10
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: Estilo.global.inputBackground
                        border.color: comboImpressoraPrincipal.activeFocus ? Estilo.screen.rede.accent : Estilo.global.border
                        border.width: comboImpressoraPrincipal.activeFocus ? 2 : 1
                        implicitHeight: 38
                    }
                }

                Text {
                    text: "Impressora desta máquina"
                    font.pixelSize: Estilo.global.fontSize.lg
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: colunaImpressora.implicitHeight + 20
                    radius: Estilo.global.radius.md
                    color: Estilo.global.surface
                    border.color: Estilo.global.borderCard
                    border.width: Estilo.global.borderWidth.hairline

                    ColumnLayout {
                        id: colunaImpressora
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: Estilo.global.spacing.xs

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Estilo.global.spacing.sm

                            Icone {
                                nome: telaRede.carregandoImpressora ? "fa6s.hourglass-half" : (telaRede.infoImpressora.encontrada ? "fa6s.print" : "fa6s.ban")
                                cor: telaRede.infoImpressora.encontrada ? Estilo.global.text : Estilo.global.textSecondary
                                tamanho: Estilo.global.fontSize.title
                            }

                            Text {
                                Layout.fillWidth: true
                                text: telaRede.carregandoImpressora ? "Verificando..." : (telaRede.infoImpressora.encontrada ? telaRede.infoImpressora.nome : "Nenhuma impressora encontrada")
                                font.bold: true
                                font.pixelSize: Estilo.global.fontSize.lg
                                color: Estilo.global.text
                                wrapMode: Text.WordWrap
                            }
                        }

                        // Detalhes só fazem sentido quando alguma impressora
                        // foi encontrada — ver BalcaoController.consultarImpressoraAtual.
                        ColumnLayout {
                            Layout.fillWidth: true
                            visible: !!telaRede.infoImpressora.encontrada
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                visible: !!telaRede.infoImpressora.fabricante
                                text: telaRede.infoImpressora.fabricante + (telaRede.infoImpressora.modelo ? " · " + telaRede.infoImpressora.modelo : "")
                                font.pixelSize: Estilo.global.fontSize.xs
                                color: Estilo.global.textSecondary
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!telaRede.infoImpressora.porta
                                text: "Porta: " + telaRede.infoImpressora.porta + (telaRede.infoImpressora.tipoPorta ? " (" + telaRede.infoImpressora.tipoPorta + ")" : "")
                                font.pixelSize: Estilo.global.fontSize.xs
                                color: Estilo.global.textSecondary
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!telaRede.infoImpressora.status
                                text: "Status: " + telaRede.infoImpressora.status
                                font.pixelSize: Estilo.global.fontSize.xs
                                color: Estilo.global.textSecondary
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                visible: !!telaRede.infoImpressora.padrao
                                text: "Impressora padrão do sistema"
                                font.pixelSize: Estilo.global.fontSize.xs
                                font.italic: true
                                color: Estilo.global.textSecondary
                            }

                            // "disponivel" vem False quando o SO ainda tem a
                            // fila instalada (porta usb/serial), mas o
                            // aparelho não está de fato conectado agora — ver
                            // InfoImpressora.disponivel. Essa impressora não
                            // entra na eleição de quem imprime pela malha
                            // (RedeService), mesmo aparecendo aqui.
                            Text {
                                Layout.fillWidth: true
                                visible: telaRede.infoImpressora.disponivel === false
                                text: "Instalada, mas não parece conectada agora — não concorre à eleição da malha."
                                font.pixelSize: Estilo.global.fontSize.xs
                                font.italic: true
                                color: Estilo.global.textSecondary
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !telaRede.carregandoImpressora && !telaRede.infoImpressora.encontrada
                            text: "Os pedidos continuam sendo salvos normalmente — só a impressão fica indisponível."
                            font.pixelSize: Estilo.global.fontSize.xs
                            color: Estilo.global.textSecondary
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
