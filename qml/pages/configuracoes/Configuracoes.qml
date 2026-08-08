import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"
import "impressora"

// Tela de Configurações — hoje só tem a seção de estilo da comanda impressa
// (EstiloImpressora.qml, em pages/configuracoes/impressora/), mas fica
// separada da Page em si para dar espaço a outras categorias de
// configuração no futuro (cada uma na sua própria subpasta), sem
// sobrecarregar este arquivo.
Page {
    id: telaConfiguracoes

    objectName: "telaConfiguracoes"

    readonly property color corDestaque: "#475569"

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
        color: Estilo.cores.fundoPagina
        radius: Estilo.rounding.popup
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        // --- CABEÇALHO ---
        Row {
            spacing: 8
            Icone { nome: "fa6s.gear"; cor: telaConfiguracoes.corDestaque; tamanho: Estilo.fonte.titulo; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "CONFIGURAÇÕES"
                font.pixelSize: Estilo.fonte.titulo
                font.bold: true
                color: telaConfiguracoes.corDestaque
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // --- ÁREA DE CONTEÚDO (rolável) ---
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: estiloImpressora.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            // O conteúdo encolhe bastante quando um campo da comanda volta de
            // uma fonte grande (8x = 8 linhas de altura numa linha só) pro
            // tamanho normal. Com StopAtBounds o Flickable NÃO corrige o
            // contentY sozinho nesse caso: se a tela estava rolada até o fim,
            // o usuário fica olhando pro vazio embaixo do conteúdo até
            // arrastar de volta na mão.
            onContentHeightChanged: returnToBounds()

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            EstiloImpressora {
                id: estiloImpressora

                width: parent.width
            }
        }

        // --- RODAPÉ: APLICAR + VOLTAR ---
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            Button {
                id: btnAplicar

                padding: 10
                Layout.preferredWidth: 230
                // Desabilitado quando não há nada a aplicar: é o que diferencia
                // "já está tudo gravado" de "falta aplicar", sem precisar de um
                // rótulo extra na tela.
                enabled: estiloImpressora.alteracoesPendentes
                onClicked: estiloImpressora.salvarNoBackend()

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    Icone {
                        nome: btnAplicar.enabled ? "fa6s.check" : "fa6s.circle-check"
                        cor: "#ffffff"
                        tamanho: Estilo.fonte.padrao
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: btnAplicar.enabled ? "Aplicar alterações" : "Tudo aplicado"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Estilo.confirmar.pressionado : (parent.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                    // Sem enabled, o verde vira um cinza esverdeado: continua
                    // legível como "este é o botão de aplicar", só que sem
                    // chamar atenção quando não há o que fazer.
                    opacity: parent.enabled ? 1 : 0.45
                }
            }

            Button {
                id: btnVoltar

                padding: 10
                Layout.preferredWidth: 200
                onClicked: telaConfiguracoes.confirmarSaida("inicio")

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.arrow-left"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Voltar para o Menu"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Estilo.cancelar.pressionado : (parent.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                    border.color: Estilo.cancelar.pressionado
                    border.width: 1
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
        padding: 25
        // Largura E altura fixadas a partir do conteúdo, pelo mesmo motivo
        // documentado em impressora/PopupEstiloCampo.qml: o Popup mede o
        // contentItem antes de os filhos com "width: parent.width" e
        // wrapMode terem se acertado, e sai menor que o conteúdo — aqui isso
        // deixava o texto vazando e os botões fora do fundo do popup.
        width: 380 + leftPadding + rightPadding
        contentWidth: 380
        contentHeight: colunaPendencias.implicitHeight
        // A altura também vai na mão: mesmo com contentHeight certo (medido:
        // 134), o Popup ficava com 92 de altura e desenhava o fundo por cima
        // de metade do conteúdo — os botões apareciam fora dele.
        height: contentHeight + topPadding + bottomPadding
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

        contentItem: Column {
            id: colunaPendencias

            spacing: 16
            width: 380

            Text {
                width: parent.width
                text: "Você alterou o modelo da comanda"
                font.pixelSize: 17
                font.bold: true
                color: Estilo.cores.texto
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: "As alterações ainda não valem para as próximas comandas. Aplicar agora?"
                font.pixelSize: 13
                color: Estilo.cores.textoSecundario
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: 8
                anchors.right: parent.right

                Button {
                    id: btnDescartar

                    text: "Descartar"
                    padding: 10
                    onClicked: {
                        // Relê do disco, jogando fora o que estava só em
                        // memória — é o que "descartar" significa aqui.
                        estiloImpressora.carregarConfiguracao();
                        popupPendencias.close();
                        telaConfiguracoes._irPara(telaConfiguracoes._destinoAposSalvar);
                    }

                    contentItem: Text {
                        text: btnDescartar.text
                        font.bold: true
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: parent.down ? Estilo.cancelar.pressionado : (parent.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                    }
                }

                Button {
                    id: btnAplicarESair

                    text: "Aplicar e sair"
                    padding: 10
                    onClicked: {
                        estiloImpressora.salvarNoBackend();
                        popupPendencias.close();
                        telaConfiguracoes._irPara(telaConfiguracoes._destinoAposSalvar);
                    }

                    contentItem: Text {
                        text: btnAplicarESair.text
                        font.bold: true
                        color: "#ffffff"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: parent.down ? Estilo.confirmar.pressionado : (parent.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                    }
                }
            }
        }
    }
}
