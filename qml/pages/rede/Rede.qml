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
    // Máquinas que podem hospedar o ppgs_server (esta + os peers conectados).
    property var maquinasServidor: []
    function carregarMaquinasServidor() {
        maquinasServidor = redeController.maquinasDisponiveis();
    }

    Connections {
        target: redeController

        function onServidorDesignadoMudou() {
            carregarMaquinasServidor();
        }

        function onPeersMudaram() {
            carregarMaquinasServidor();
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

    // Nada disto é local de graça como parecia: listarPeers/listarHistorico/
    // candidatosImpressora atravessam a ponte pro Python e mexem em estado do
    // RedeService, e carregarImpressora ainda dispara a busca da impressora.
    // Somado, é tempo suficiente pra segurar o primeiro quadro da tela inteira
    // — daí passarem todos pela CargaDiferida (ver components/CargaDiferida.qml).
    CargaDiferida {
        id: carga

        tarefa: function() {
            carregarPeers();
            carregarHistorico();
            carregarImpressora();
            carregarImpressoraPrincipal();
            carregarCandidatosImpressora();
            carregarMaquinasServidor();
        }
    }

    Component.onCompleted: carga.agendar()
    StackView.onActivated: carga.agendar()

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

    // Única área de rolagem da página (mesmo desenho do Flickable de
    // Fechamento.qml). Antes a coluna era ancorada direto na página, e o que
    // não coubesse na janela simplesmente não tinha como ser alcançado: a
    // tela ganhou o card da chave da malha e a seção de onde o servidor roda,
    // e as duas juntas passam da altura da janela mesmo numa tela grande — o
    // fim da lista de máquinas e o histórico ficavam fora do alcance.
    Flickable {
        id: rolagemRede

        anchors.fill: parent
        anchors.margins: 20
        clip: true
        contentWidth: width
        contentHeight: colunaRede.height
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: colunaRede

            width: rolagemRede.width
            // Sobrando espaço, a coluna ocupa a janela inteira e o histórico
            // estica pra preencher (é o que ele sempre fez, e é a lista que
            // vale a pena crescer). Faltando, ela cresce até onde o conteúdo
            // pedir e a rolagem cuida do resto — em vez de espremer as seções
            // de baixo até sumirem.
            height: Math.max(implicitHeight, rolagemRede.height)
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
                        telaRede.carregarMaquinasServidor();
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

            // --- SERVIDOR CENTRAL (ppgs_server) ---
            // O backend que guarda endereços de entrega (ver
            // services/pizzeriaServerService.py, usado por Entrega.qml). Ele roda
            // numa das máquinas da malha, escutando só em 127.0.0.1 — as outras
            // chegam nele por dentro da própria malha, então não há endereço nem
            // porta pra configurar aqui, só a máquina escolhida no card abaixo.
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
                            text: {
                                if (pizzeriaServerController.conectado)
                                    return "Autofill de endereço disponível (rodando em " + pizzeriaServerController.maquinaServidor + ", pela malha)";
                                if (!pizzeriaServerController.maquinaServidor)
                                    return "Nenhuma máquina foi escolhida para rodar o servidor — escolha uma abaixo.";
                                return "Não foi possível falar com o servidor em '" + pizzeriaServerController.maquinaServidor + "' — autofill de endereço na Entrega fica indisponível.";
                            }
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

            // --- ONDE O SERVIDOR RODA ---
            // Escolher aqui é o que dispara todo o preparo na máquina escolhida
            // (clone, toolchain, build, migration, start — ver
            // services/servidor/servidorLocal.py), em segundo plano.
            //
            // Esta máquina aparece SEMPRE, mesmo sem nenhum peer conectado e
            // mesmo com a malha fora do ar: é o caso da pizzaria que abriu com um
            // computador só ligado, ou da primeira instalação. Sem isso haveria
            // um impasse — não dá pra escolher uma máquina para o servidor
            // enquanto não houver rede, e a rede não é necessária pra rodar o
            // servidor localmente.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: colunaServidor.implicitHeight + 20
                radius: Estilo.global.radius.md
                color: Estilo.global.surface
                border.color: Estilo.global.borderCard
                border.width: Estilo.global.borderWidth.hairline

                ColumnLayout {
                    id: colunaServidor
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: Estilo.global.spacing.sm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Estilo.global.spacing.md

                        Icone { nome: "fa6s.database"; cor: Estilo.screen.rede.accent; tamanho: Estilo.global.fontSize.title }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: "Onde o servidor roda"
                                font.bold: true
                                font.pixelSize: Estilo.global.fontSize.lg
                                color: Estilo.global.text
                            }

                            Text {
                                Layout.fillWidth: true
                                text: redeController.maquinaServidor
                                      ? ("Guardando endereços e clientes em '" + redeController.maquinaServidor + "'.")
                                      : "Nenhuma máquina escolhida — o autofill de endereço na Entrega fica indisponível até escolher uma."
                                font.pixelSize: Estilo.global.fontSize.xs
                                color: Estilo.global.textSecondary
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    // Estado vazio explícito: só esta máquina na rede. O botão
                    // abaixo continua valendo — é justamente o caso que ele cobre.
                    Text {
                        Layout.fillWidth: true
                        visible: telaRede.maquinasServidor.length <= 1
                        text: "Nenhuma outra máquina está na rede agora. Você pode rodar o servidor nesta mesma máquina — as outras passam a usá-lo assim que entrarem na rede."
                        font.pixelSize: Estilo.global.fontSize.xs
                        color: Estilo.global.textSecondary
                        wrapMode: Text.WordWrap
                    }

                    // Uma linha por máquina candidata (esta + peers conectados).
                    Repeater {
                        model: telaRede.maquinasServidor

                        Rectangle {
                            required property var modelData

                            Layout.fillWidth: true
                            implicitHeight: linhaMaquina.implicitHeight + 16
                            radius: Estilo.global.radius.sm
                            color: modelData.hospeda ? Estilo.screen.rede.soft : Estilo.global.background
                            border.color: modelData.hospeda ? Estilo.screen.rede.accent : Estilo.global.border
                            border.width: Estilo.global.borderWidth.hairline

                            RowLayout {
                                id: linhaMaquina
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: Estilo.global.spacing.md

                                Icone {
                                    nome: modelData.hospeda ? "fa6s.server" : "fa6s.desktop"
                                    cor: modelData.hospeda ? Estilo.screen.rede.accent : Estilo.global.textSecondary
                                    tamanho: Estilo.global.fontSize.lg
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: modelData.nome + (modelData.local ? " (esta máquina)" : "")
                                        font.bold: modelData.hospeda
                                        font.pixelSize: Estilo.global.fontSize.sm
                                        color: Estilo.global.text
                                    }

                                    // Só a máquina que hospeda tem preparo pra
                                    // contar, e só ela sabe em que passo está —
                                    // as outras veem apenas o nome.
                                    Text {
                                        Layout.fillWidth: true
                                        visible: modelData.hospeda && modelData.local && servidorLocalController.etapa.length > 0
                                        text: servidorLocalController.etapa + (servidorLocalController.detalhe ? " — " + servidorLocalController.detalhe : "")
                                        font.pixelSize: Estilo.global.fontSize.xs
                                        color: (servidorLocalController.estado === "falha"
                                                 || servidorLocalController.estado === "parado")
                                               ? Estilo.status.error.content : Estilo.global.textSecondary
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                Rotulo {
                                    visible: modelData.hospeda
                                    texto: {
                                        if (!modelData.local)
                                            return "Servidor";
                                        if (servidorLocalController.estado === "rodando")
                                            return "No ar";
                                        if (servidorLocalController.estado === "preparando")
                                            return "Preparando";
                                        if (servidorLocalController.estado === "aguardando_chave")
                                            return "Falta a chave";
                                        if (servidorLocalController.estado === "falha")
                                            return "Falhou";
                                        if (servidorLocalController.estado === "parado")
                                            return "Parado";
                                        return "Servidor";
                                    }
                                    tom: (servidorLocalController.estado === "falha"
                                           || servidorLocalController.estado === "parado")
                                         ? Estilo.status.error : Estilo.status.info
                                }

                                Botao {
                                    visible: !modelData.hospeda
                                    text: modelData.local ? "Rodar nesta máquina" : "Rodar aqui"
                                    variante: "primario"
                                    tom: Estilo.screen.rede
                                    onClicked: redeController.designarServidor(modelData.nome)
                                }
                            }
                        }
                    }

                    // A deploy key é o único passo que uma pessoa precisa fazer à
                    // mão: o GitHub não tem como aceitar esta máquina antes de
                    // alguém cadastrar a chave pública dela.
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: servidorLocalController.chavePublicaDeploy.length > 0
                        spacing: Estilo.global.spacing.xs

                        Text {
                            Layout.fillWidth: true
                            text: "Cadastre esta chave como deploy key (somente leitura) em github.com/BORRAACH/PPGS-Server → Settings → Deploy keys, e depois clique em \"Tentar de novo\":"
                            font.pixelSize: Estilo.global.fontSize.xs
                            color: Estilo.global.textSecondary
                            wrapMode: Text.WordWrap
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: textoChaveDeploy.implicitHeight + 16
                            radius: Estilo.global.radius.sm
                            color: Estilo.global.inputBackground
                            border.color: Estilo.global.border
                            border.width: Estilo.global.borderWidth.hairline

                            TextEdit {
                                id: textoChaveDeploy
                                anchors.fill: parent
                                anchors.margins: 8
                                text: servidorLocalController.chavePublicaDeploy
                                // Só leitura, mas selecionável: é assim que a
                                // chave sai daqui pro navegador.
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                font.pixelSize: Estilo.global.fontSize.xs
                                font.family: "monospace"
                                color: Estilo.global.textInput
                            }
                        }
                    }

                    // Só faz sentido na máquina que hospeda: é ela que precisa
                    // estar de pé quando o expediente começa. Numa máquina que
                    // não hospeda, abrir sozinha com o Windows não coloca
                    // servidor nenhum no ar.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: redeController.servidorAqui && servidorLocalController.autostartDisponivel
                        spacing: Estilo.global.spacing.sm

                        CheckBox {
                            id: chkIniciarComWindows

                            padding: 0
                            implicitWidth: 22
                            implicitHeight: 22
                            checked: servidorLocalController.iniciarComWindows
                            onClicked: servidorLocalController.definirIniciarComWindows(checked)

                            contentItem: Item {}
                            indicator: Rectangle {
                                implicitWidth: 22
                                implicitHeight: 22
                                radius: Estilo.global.radius.xs
                                border.color: chkIniciarComWindows.checked ? Estilo.screen.rede.base : Estilo.global.borderStrong
                                border.width: Estilo.global.borderWidth.thick
                                color: chkIniciarComWindows.checked ? Estilo.screen.rede.base : "transparent"

                                Icone {
                                    nome: "fa6s.check"
                                    cor: Estilo.global.textOnAccent
                                    tamanho: 13
                                    anchors.centerIn: parent
                                    visible: chkIniciarComWindows.checked
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                text: "Iniciar com o Windows"
                                font.pixelSize: Estilo.global.fontSize.sm
                                font.bold: true
                                color: Estilo.global.text
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "O sistema abre sozinho quando esta máquina liga, e sobe o servidor central junto."
                                font.pixelSize: Estilo.global.fontSize.xs
                                color: Estilo.global.textSecondary
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: redeController.servidorAqui
                        spacing: Estilo.global.spacing.sm

                        Item { Layout.fillWidth: true }

                        // Enquanto prepara, a única ação útil é desistir: o
                        // preparo pode levar de segundos a quase uma hora, e sem
                        // saída o usuário só teria a opção de fechar o sistema.
                        Botao {
                            visible: servidorLocalController.estado === "preparando"
                            text: "Cancelar"
                            variante: "primario"
                            nomeIcone: "fa6s.xmark"
                            tom: Estilo.action.danger
                            onClicked: servidorLocalController.cancelarPreparo()
                        }

                        // Parar um servidor no ar derruba o autofill de endereço
                        // de TODAS as máquinas da malha, não só desta — por isso
                        // passa por confirmação, diferente de cancelar um preparo.
                        Botao {
                            visible: servidorLocalController.estado === "rodando"
                            text: "Parar"
                            variante: "primario"
                            nomeIcone: "fa6s.stop"
                            tom: Estilo.action.danger
                            onClicked: dialogoPararServidor.open()
                        }

                        Botao {
                            visible: servidorLocalController.estado !== "preparando"
                            text: servidorLocalController.estado === "rodando" ? "Tentar de novo" : "Iniciar servidor"
                            variante: "secundario"
                            nomeIcone: servidorLocalController.estado === "rodando" ? "fa6s.arrows-rotate" : "fa6s.play"
                            tom: Estilo.screen.rede
                            onClicked: servidorLocalController.refazerPreparo()
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
                        // Um piso próprio, e não só fillHeight: dentro da
                        // rolagem da página a coluna passa a ter a altura do
                        // conteúdo, e uma ListView não tem altura de conteúdo
                        // nenhuma (implicitHeight zero) — sem este piso o
                        // histórico sumiria justamente quando a tela ficasse
                        // cheia demais pra caber, que é quando a rolagem
                        // entra. Com espaço sobrando o fillHeight continua
                        // valendo e ele estica como sempre esticou.
                        Layout.preferredHeight: 260
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

    // Confirmação de parada do servidor. Dialogo.qml já centraliza na tela e
    // escurece o fundo (ver qml/components/Dialogo.qml).
    Dialogo {
        id: dialogoPararServidor

        titulo: "Parar o servidor?"
        nomeIcone: "fa6s.triangle-exclamation"
        corpo: "O cadastro de endereços fica indisponível em todas as máquinas enquanto o servidor estiver parado — o autofill da tela Entrega para de funcionar. Nenhum endereço é apagado, e você pode iniciar o servidor de novo a qualquer momento."

        Botao {
            text: "Continuar rodando"
            variante: "secundario"
            tom: Estilo.screen.rede
            onClicked: dialogoPararServidor.close()
        }

        Botao {
            text: "Parar servidor"
            variante: "primario"
            nomeIcone: "fa6s.stop"
            tom: Estilo.action.danger
            onClicked: {
                servidorLocalController.pararServidor();
                dialogoPararServidor.close();
            }
        }
    }
}
