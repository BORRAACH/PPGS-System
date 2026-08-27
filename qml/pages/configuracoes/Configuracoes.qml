import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"
import "impressora"
import "usuarios"

// Tela de Configurações — coluna de seções à esquerda, conteúdo da seção
// escolhida à direita, no formato das telas de preferências de IDE. Cada
// seção mora na sua própria subpasta (impressora/, usuarios/), e este arquivo
// só sabe listá-las e mostrar a que está selecionada.
//
// Acrescentar uma seção é uma entrada em `secoes` mais um filho na área de
// conteúdo — a coluna da esquerda é montada por Repeater a partir da lista.
//
// AS SEÇÕES FICAM TODAS INSTANCIADAS, escondidas por `visible`, e não trocadas
// por um Loader. Não é detalhe de estilo: EstiloImpressora guarda as edições
// em memória até alguém clicar em "Aplicar alterações" (ver
// alteracoesPendentes), então destruí-la ao trocar de seção jogaria fora o
// trabalho da pessoa sem avisar — e o rodapé, o StackView.onDeactivated e o
// popup de pendências lá embaixo todos apontam para essa mesma instância.
Page {
    id: telaConfiguracoes

    objectName: "telaConfiguracoes"

    readonly property color corDestaque: Estilo.screen.config.accent

    // A coluna da esquerda sai daqui. "chave" amarra o item da lista ao filho
    // correspondente na área de conteúdo.
    readonly property var secoes: [
        { "chave": "impressao", "titulo": "Estilo de impressão", "icone": "fa6s.receipt" },
        { "chave": "usuarios", "titulo": "Usuários", "icone": "fa6s.user-lock" }
    ]
    property string secaoAtual: "impressao"

    // Numa janela estreita não cabem a coluna de seções e o conteúdo lado a
    // lado — a coluna vira uma fileira de abas em cima. Mesmo recurso que o
    // rodapé daqui já usa para empilhar os botões, e que Fechamento.qml chama
    // de "empilhado".
    readonly property bool estreito: width < 620

    // Para onde ir depois que o usuário decidir o que fazer com as edições
    // pendentes (ver confirmarSaida/popupPendencias) — "" quando ninguém
    // está esperando por essa decisão.
    property string _destinoAposSalvar: ""

    // As edições ficam só em memória enquanto o usuário mexe nos controles;
    // gravar em disco e publicar na malha é o que o botão "Aplicar
    // alterações" faz. Sair com algo pendente pergunta antes, em vez de
    // gravar em silêncio: o que está na tela pode ser um teste que a pessoa
    // não quer valendo para as próximas comandas.
    function confirmarSaida(destino) {
        if (!estiloImpressora.alteracoesPendentes) {
            telaConfiguracoes._irPara(destino);
            return;
        }

        telaConfiguracoes._destinoAposSalvar = destino;
        popupPendencias.open();
    }

    function _irPara(destino) {
        if (destino === "inicio" && telaConfiguracoes.StackView.view)
            telaConfiguracoes.StackView.view.irParaInicio();
    }

    // Sair pela barra lateral não passa por confirmarSaida (a página só é
    // empurrada para baixo na pilha, sem clique em nenhum botão daqui), e não
    // dá para abrir um popup de uma tela que está saindo de cena — então aqui
    // o pendente é gravado, que é o menos pior entre gravar sem perguntar e
    // descartar o trabalho sem avisar.
    StackView.onDeactivated: {
        if (estiloImpressora.alteracoesPendentes)
            estiloImpressora.salvarNoBackend();
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
        Row {
            spacing: Estilo.global.spacing.sm
            Icone { nome: "fa6s.gear"; cor: telaConfiguracoes.corDestaque; tamanho: Estilo.global.fontSize.title; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "CONFIGURAÇÕES"
                font.pixelSize: Estilo.global.fontSize.title
                font.family: Estilo.global.fontFamily.title
                color: telaConfiguracoes.corDestaque
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // --- CORPO: COLUNA DE SEÇÕES + CONTEÚDO ---
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: telaConfiguracoes.estreito ? 1 : 2
            columnSpacing: Estilo.global.spacing.xl
            rowSpacing: Estilo.global.spacing.lg

            // --- COLUNA DE OPÇÕES ---
            GridLayout {
                id: colunaOpcoes

                // Alinhada ao topo, não esticada: a lista tem a altura dos
                // seus itens, e centralizá-la verticalmente ao lado de um
                // painel alto faria os links flutuarem no meio do vazio.
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: telaConfiguracoes.estreito
                Layout.preferredWidth: telaConfiguracoes.estreito ? -1 : 200
                // Deitada quando a coluna vira fileira de abas.
                columns: telaConfiguracoes.estreito ? telaConfiguracoes.secoes.length : 1
                columnSpacing: Estilo.global.spacing.sm
                rowSpacing: 4

                Repeater {
                    model: telaConfiguracoes.secoes

                    Button {
                        id: itemSecao

                        required property var modelData

                        readonly property bool selecionada: telaConfiguracoes.secaoAtual === itemSecao.modelData.chave
                        // Marca de "tem coisa aqui que ainda não foi
                        // aplicada". Sem ela, quem mexe no estilo da comanda e
                        // pula para Usuários perde de vista o pendente: o botão
                        // "Aplicar alterações" do rodapé é da seção de
                        // impressão e some junto com ela.
                        readonly property bool pendente: itemSecao.modelData.chave === "impressao"
                            && estiloImpressora.alteracoesPendentes

                        Layout.fillWidth: true
                        padding: Estilo.global.padding.md
                        onClicked: telaConfiguracoes.secaoAtual = itemSecao.modelData.chave

                        contentItem: Row {
                            spacing: Estilo.global.spacing.sm

                            Icone {
                                nome: itemSecao.modelData.icone
                                cor: itemSecao.selecionada ? telaConfiguracoes.corDestaque : Estilo.global.textSecondary
                                tamanho: Estilo.global.fontSize.md
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: itemSecao.modelData.titulo
                                font.pixelSize: Estilo.global.fontSize.md
                                font.bold: itemSecao.selecionada
                                color: itemSecao.selecionada ? telaConfiguracoes.corDestaque : Estilo.global.text
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Rectangle {
                                visible: itemSecao.pendente
                                width: 7
                                height: 7
                                radius: 3.5
                                color: Estilo.status.warning.border
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.md
                            color: {
                                if (itemSecao.selecionada)
                                    return Estilo.screen.config.soft;
                                return itemSecao.hovered ? Estilo.global.surface : "transparent";
                            }
                        }
                    }
                }
            }

            // --- CONTEÚDO DA SEÇÃO (rolável) ---
            Flickable {
                id: areaSecao

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                // Rolagem horizontal SÓ na seção de impressão: a prévia do
                // cupom tem a largura FÍSICA do papel (40 colunas numa fonte
                // monoespaçada — ver EstiloImpressora.colunasPapel), que não é
                // uma medida de interface e não pode encolher junto com a
                // janela sem deixar de representar o que a impressora vai
                // imprimir; ali a saída certa é arrastar até o resto do papel,
                // não espremê-lo.
                //
                // Nas outras seções isso seria o contrário do que se quer:
                // texto e listas devem quebrar linha dentro da área, e herdar
                // a largura do papel jogava metade da lista de usuários pra
                // fora da tela.
                contentWidth: telaConfiguracoes.secaoAtual === "impressao"
                    ? Math.max(width, colunaSecoes.implicitWidth)
                    : width
                contentHeight: colunaSecoes.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                // O conteúdo encolhe bastante quando um campo da comanda volta
                // de uma fonte grande (8x = 8 linhas de altura numa linha só)
                // pro tamanho normal, e também ao trocar de seção. Com
                // StopAtBounds o Flickable NÃO corrige o contentY sozinho
                // nesses casos: se a tela estava rolada até o fim, o usuário
                // fica olhando pro vazio embaixo do conteúdo até arrastar de
                // volta na mão.
                onContentHeightChanged: returnToBounds()

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                ScrollBar.horizontal: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                // Só a seção escolhida fica visível. Um ColumnLayout ignora
                // filho invisível ao medir, então a área rolável passa a ter
                // exatamente a altura da seção à vista — sem sobra de rolagem
                // vinda da que está escondida.
                ColumnLayout {
                    id: colunaSecoes

                    // Exatamente a área rolável — é contentWidth que decide
                    // se há papel a mais para arrastar, e a coluna só o
                    // acompanha.
                    width: areaSecao.contentWidth
                    spacing: Estilo.global.spacing.xxl

                    EstiloImpressora {
                        id: estiloImpressora

                        visible: telaConfiguracoes.secaoAtual === "impressao"
                        // Acompanha a área rolável, não a janela: quando o
                        // papel é mais largo que a tela, o conteúdo continua
                        // inteiro e é a rolagem que dá acesso ao resto.
                        Layout.fillWidth: true
                        Layout.preferredWidth: Math.max(colunaSecoes.width, implicitWidth)
                        Layout.maximumWidth: Math.max(colunaSecoes.width, implicitWidth)
                    }

                    GerenciarUsuarios {
                        visible: telaConfiguracoes.secaoAtual === "usuarios"
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // --- RODAPÉ: APLICAR + VOLTAR ---
        // Os dois botões somam 430px fixos: lado a lado enquanto couberem,
        // um sobre o outro quando não couberem.
        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            columns: telaConfiguracoes.width < 500 ? 1 : 2
            columnSpacing: Estilo.global.spacing.lg
            rowSpacing: Estilo.global.spacing.lg

            Button {
                id: btnAplicar

                padding: Estilo.global.padding.md
                Layout.preferredWidth: Math.min(230, telaConfiguracoes.width - Estilo.global.padding.xl * 2)
                // Aplica o estilo da comanda, e só ele — na seção de Usuários
                // não há nada para aplicar (cada Confirmar de lá já grava e
                // publica na hora), então o botão sai de cena junto com a
                // seção. O pendente não fica invisível por causa disso: a
                // coluna da esquerda marca a seção com um ponto.
                visible: telaConfiguracoes.secaoAtual === "impressao"
                // Desabilitado quando não há nada a aplicar: é o que diferencia
                // "já está tudo gravado" de "falta aplicar", sem precisar de um
                // rótulo extra na tela.
                enabled: estiloImpressora.alteracoesPendentes
                onClicked: estiloImpressora.salvarNoBackend()

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
                    color: parent.down ? Estilo.action.confirm.pressed : (parent.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                    // Sem enabled, o verde vira um cinza esverdeado: continua
                    // legível como "este é o botão de aplicar", só que sem
                    // chamar atenção quando não há o que fazer.
                    opacity: parent.enabled ? 1 : Estilo.global.opacity.disabled
                }
            }

            Button {
                id: btnVoltar

                padding: Estilo.global.padding.md
                Layout.preferredWidth: Math.min(200, telaConfiguracoes.width - Estilo.global.padding.xl * 2)
                onClicked: telaConfiguracoes.confirmarSaida("inicio")

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.arrow-left"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Voltar para o Menu"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                    border.color: Estilo.action.danger.pressed
                    border.width: Estilo.global.borderWidth.hairline
                }
            }
        }
    }

    // --- SAIR COM EDIÇÕES PENDENTES ---
    Popup {
        id: popupPendencias

        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
        padding: Estilo.global.padding.popup
        // Largura E altura fixadas a partir do conteúdo, pelo mesmo motivo
        // documentado em impressora/PopupEstiloCampo.qml: o Popup mede o
        // contentItem antes de os filhos com "width: parent.width" e
        // wrapMode terem se acertado, e sai menor que o conteúdo — aqui isso
        // deixava o texto vazando e os botões fora do fundo do popup.
        width: Responsivo.larguraPopup(380) + leftPadding + rightPadding
        contentWidth: Responsivo.larguraPopup(380)
        contentHeight: colunaPendencias.implicitHeight
        // A altura também vai na mão: mesmo com contentHeight certo (medido:
        // 134), o Popup ficava com 92 de altura e desenhava o fundo por cima
        // de metade do conteúdo — os botões apareciam fora dele.
        height: contentHeight + topPadding + bottomPadding
        parent: Overlay.overlay
        anchors.centerIn: parent

        Overlay.modal: Rectangle {
            color: Estilo.global.overlay
        }

        background: Rectangle {
            radius: Estilo.global.radius.xl
            color: Estilo.global.background
            border.color: Estilo.global.borderCard
        }

        contentItem: Column {
            id: colunaPendencias

            spacing: 16
            width: Responsivo.larguraPopup(380)

            Text {
                width: parent.width
                text: "Você alterou o modelo da comanda"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: "As alterações ainda não valem para as próximas comandas. Aplicar agora?"
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.textSecondary
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: Estilo.global.spacing.sm
                anchors.right: parent.right

                Button {
                    id: btnDescartar

                    text: "Descartar"
                    padding: Estilo.global.padding.md
                    onClicked: {
                        // Relê do disco, jogando fora o que estava só em
                        // memória — é o que "descartar" significa aqui.
                        estiloImpressora.carregarConfiguracao();
                        popupPendencias.close();
                        telaConfiguracoes._irPara(telaConfiguracoes._destinoAposSalvar);
                    }

                    contentItem: Text {
                        text: btnDescartar.text
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                    }
                }

                Button {
                    id: btnAplicarESair

                    text: "Aplicar e sair"
                    padding: Estilo.global.padding.md
                    onClicked: {
                        estiloImpressora.salvarNoBackend();
                        popupPendencias.close();
                        telaConfiguracoes._irPara(telaConfiguracoes._destinoAposSalvar);
                    }

                    contentItem: Text {
                        text: btnAplicarESair.text
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.action.confirm.pressed : (parent.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                    }
                }
            }
        }
    }
}
