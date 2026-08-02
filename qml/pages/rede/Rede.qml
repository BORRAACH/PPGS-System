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
        carregarImpressora();
        carregarImpressoraPrincipal();
        carregarCandidatosImpressora();
    }
    StackView.onActivated: {
        carregarPeers();
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
        color: Estilo.cores.fundoPagina
        radius: Estilo.rounding.popup
    }

    ListModel {
        id: modeloPeers
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
                Icone { nome: "fa6s.globe"; cor: "#0ea5e9"; tamanho: Estilo.fonte.titulo; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "REDE LOCAL"
                    font.pixelSize: Estilo.fonte.titulo
                    font.bold: true
                    color: "#0ea5e9"
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
                    spacing: 6
                    Icone { nome: "fa6s.arrows-rotate"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Atualizar"
                        font.bold: true
                        color: "#ffffff"
                        verticalAlignment: Text.AlignVCenter
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? "#0369a1" : (parent.hovered ? "#0ea5e9" : "#0284c7")
                }
            }
        }

        // --- ESTA MÁQUINA ---
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: linhaEstaMaquina.implicitHeight + 20
            radius: Estilo.rounding.grande
            color: "#f0f9ff"
            border.color: "#bae6fd"
            border.width: 1

            RowLayout {
                id: linhaEstaMaquina
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                Icone {
                    nome: "fa6s.desktop"
                    cor: Estilo.cores.texto
                    tamanho: Estilo.fonte.titulo
                }

                ColumnLayout {
                    spacing: 2

                    Text {
                        text: "Esta máquina: " + redeController.nomeLocal + " (" + redeController.letraLocal + ")"
                        font.bold: true
                        font.pixelSize: Estilo.fonte.padrao
                        color: Estilo.cores.texto
                    }

                    Text {
                        text: "Compartilhando pedidos com " + redeController.quantidadeConectados + " máquina(s) na rede local"
                        font.pixelSize: 11
                        color: Estilo.cores.textoSecundario
                    }
                }
            }
        }

        // --- MÁQUINAS CONECTADAS (esquerda) + IMPRESSORA DESTA MÁQUINA (direita) ---
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 15

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                Text {
                    text: "Máquinas conectadas (" + modeloPeers.count + ")"
                    font.pixelSize: Estilo.fonte.padrao
                    font.bold: true
                    color: Estilo.cores.textoSecundario
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
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
                        color: Estilo.cores.textoSecundario
                        font.pixelSize: Estilo.fonte.padrao
                    }

                    delegate: Rectangle {
                        width: ListView.view.width - (ListView.view.ScrollBar.vertical.visible ? ListView.view.ScrollBar.vertical.width : 0)
                        height: colunaPeer.implicitHeight + 20
                        radius: Estilo.rounding.grande
                        color: "#ffffff"
                        border.color: Estilo.cores.bordaCard
                        border.width: 1

                        RowLayout {
                            id: colunaPeer
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 10
                            spacing: 10

                            Icone {
                                nome: "fa6s.desktop"
                                cor: Estilo.cores.texto
                                tamanho: Estilo.fonte.titulo
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    text: model.nome
                                    font.bold: true
                                    font.pixelSize: Estilo.fonte.padrao
                                    color: Estilo.cores.texto
                                }

                                Text {
                                    text: model.endereco
                                    font.pixelSize: 11
                                    color: Estilo.cores.textoSecundario
                                }
                            }

                            Text {
                                text: "conectado há " + telaRede.formatarDuracao(relogio.agora / 1000 - model.conectadoEm)
                                font.pixelSize: 11
                                color: Estilo.cores.textoSecundario
                            }
                        }
                    }
                }
            }

            // --- IMPRESSORA DESTA MÁQUINA ---
            ColumnLayout {
                Layout.preferredWidth: 240
                Layout.alignment: Qt.AlignTop
                spacing: 8

                // --- IMPRESSORA PRINCIPAL (a que a malha está usando pra
                // imprimir agora — ver RedeService.impressoraPrincipal) ---
                Text {
                    text: "Impressora principal"
                    font.pixelSize: Estilo.fonte.padrao
                    font.bold: true
                    color: Estilo.cores.textoSecundario
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: colunaImpressoraPrincipal.implicitHeight + 20
                    radius: Estilo.rounding.grande
                    color: "#ffffff"
                    border.color: Estilo.cores.bordaCard
                    border.width: 1

                    ColumnLayout {
                        id: colunaImpressoraPrincipal
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Icone {
                                nome: telaRede.infoImpressoraPrincipal.nome ? "fa6s.print" : "fa6s.ban"
                                cor: telaRede.infoImpressoraPrincipal.nome ? Estilo.cores.texto : Estilo.cores.textoSecundario
                                tamanho: Estilo.fonte.titulo
                            }

                            Text {
                                Layout.fillWidth: true
                                text: telaRede.infoImpressoraPrincipal.nome ? telaRede.infoImpressoraPrincipal.nome : "Nenhuma impressora disponível na rede"
                                font.bold: true
                                font.pixelSize: Estilo.fonte.padrao
                                color: Estilo.cores.texto
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !!telaRede.infoImpressoraPrincipal.fixadoManualmente
                            text: "Selecionada manualmente"
                            font.pixelSize: 11
                            font.italic: true
                            color: "#0ea5e9"
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
                                font.pixelSize: 11
                                color: Estilo.cores.textoSecundario
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!telaRede.infoImpressoraPrincipal.fabricante
                                text: telaRede.infoImpressoraPrincipal.fabricante + (telaRede.infoImpressoraPrincipal.modelo ? " · " + telaRede.infoImpressoraPrincipal.modelo : "")
                                font.pixelSize: 11
                                color: Estilo.cores.textoSecundario
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!telaRede.infoImpressoraPrincipal.tipoPorta
                                text: "Porta: " + telaRede.infoImpressoraPrincipal.porta + " (" + telaRede.infoImpressoraPrincipal.tipoPorta + ")"
                                font.pixelSize: 11
                                color: Estilo.cores.textoSecundario
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !telaRede.infoImpressoraPrincipal.nome
                            text: "Os pedidos continuam sendo salvos normalmente — só a impressão fica indisponível até alguma máquina da rede ter uma impressora conectada."
                            font.pixelSize: 11
                            color: Estilo.cores.textoSecundario
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Text {
                    text: "Escolher manualmente"
                    font.pixelSize: Estilo.fonte.padrao
                    font.bold: true
                    color: Estilo.cores.textoSecundario
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
                        palette.text: Estilo.cores.textoInput
                        palette.highlightedText: Estilo.cores.textoInput
                    }

                    contentItem: Text {
                        text: comboImpressoraPrincipal.displayText
                        color: Estilo.cores.textoInput
                        leftPadding: 10
                        rightPadding: 10
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: "#ffffff"
                        border.color: comboImpressoraPrincipal.activeFocus ? "#0ea5e9" : Estilo.cores.borda
                        border.width: comboImpressoraPrincipal.activeFocus ? 2 : 1
                        implicitHeight: 38
                    }
                }

                Text {
                    text: "Impressora desta máquina"
                    font.pixelSize: Estilo.fonte.padrao
                    font.bold: true
                    color: Estilo.cores.textoSecundario
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: colunaImpressora.implicitHeight + 20
                    radius: Estilo.rounding.grande
                    color: "#ffffff"
                    border.color: Estilo.cores.bordaCard
                    border.width: 1

                    ColumnLayout {
                        id: colunaImpressora
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Icone {
                                nome: telaRede.carregandoImpressora ? "fa6s.hourglass-half" : (telaRede.infoImpressora.encontrada ? "fa6s.print" : "fa6s.ban")
                                cor: telaRede.infoImpressora.encontrada ? Estilo.cores.texto : Estilo.cores.textoSecundario
                                tamanho: Estilo.fonte.titulo
                            }

                            Text {
                                Layout.fillWidth: true
                                text: telaRede.carregandoImpressora ? "Verificando..." : (telaRede.infoImpressora.encontrada ? telaRede.infoImpressora.nome : "Nenhuma impressora encontrada")
                                font.bold: true
                                font.pixelSize: Estilo.fonte.padrao
                                color: Estilo.cores.texto
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
                                font.pixelSize: 11
                                color: Estilo.cores.textoSecundario
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!telaRede.infoImpressora.porta
                                text: "Porta: " + telaRede.infoImpressora.porta + (telaRede.infoImpressora.tipoPorta ? " (" + telaRede.infoImpressora.tipoPorta + ")" : "")
                                font.pixelSize: 11
                                color: Estilo.cores.textoSecundario
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !!telaRede.infoImpressora.status
                                text: "Status: " + telaRede.infoImpressora.status
                                font.pixelSize: 11
                                color: Estilo.cores.textoSecundario
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                visible: !!telaRede.infoImpressora.padrao
                                text: "Impressora padrão do sistema"
                                font.pixelSize: 11
                                font.italic: true
                                color: Estilo.cores.textoSecundario
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
                                font.pixelSize: 11
                                font.italic: true
                                color: Estilo.cores.textoSecundario
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !telaRede.carregandoImpressora && !telaRede.infoImpressora.encontrada
                            text: "Os pedidos continuam sendo salvos normalmente — só a impressão fica indisponível."
                            font.pixelSize: 11
                            color: Estilo.cores.textoSecundario
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
