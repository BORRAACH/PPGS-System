import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0

// Cartão com o resultado da validação do endereço de entrega: selo de status,
// endereço oficial, zona de entrega, mensagens e as ações (Confirmar, Usar
// mesmo assim, Tentar outro). O estado é todo do DeliveryAddressValidator;
// aqui só se desenha. Separado dele para morar noutro ponto da tela — na
// Entrega, acima do Resumo da comanda —, longe dos campos.
//
// Endereço validado e completo confirma sozinho (ver
// DeliveryAddressValidator.confirmacaoAutomatica), e o cartão some 1 segundo
// depois — o tempo de ver o selo —, ou no ×. Volta quando a validação muda de
// estado (outra rua, número trocado, CEP corrigido): aí há resultado novo para
// ler.
Rectangle {
    id: cartao

    // O DeliveryAddressValidator de quem este cartão mostra o resultado.
    required property var validador

    // Fechado pelo × ou pelo tempo depois da confirmação.
    property bool dispensado: false
    readonly property bool mostrar: validador.status !== "" && !dispensado

    implicitHeight: colunaResultado.implicitHeight + Estilo.global.padding.md * 2
    radius: Estilo.global.radius.md
    color: validador.tomStatus.background
    border.color: validador.tomStatus.border
    border.width: Estilo.global.borderWidth.hairline
    // Some com um esmaecer curto, e só então sai do layout: sumir de uma vez
    // puxava o Resumo da comanda para cima sem aviso.
    opacity: mostrar ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation { duration: 200 }
    }

    Connections {
        target: cartao.validador

        function onStatusChanged() {
            esconder.stop();
            cartao.dispensado = false;
        }

        // Confirmado: fica 1 segundo para o atendente ver o selo e some. Uma
        // edição antes disso desfaz a confirmação, e o cartão fica.
        function onEnderecoConfirmadoChanged() {
            if (cartao.validador.enderecoConfirmado)
                esconder.restart();
            else
                esconder.stop();
        }
    }

    Timer {
        id: esconder

        interval: 1000
        onTriggered: cartao.dispensado = true
    }

    Column {
        id: colunaResultado

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Estilo.global.padding.md
        spacing: Estilo.global.spacing.xs

        RowLayout {
            width: parent.width
            spacing: Estilo.global.spacing.sm

            // Selo de status.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: linhaSelo.implicitWidth + Estilo.global.padding.md * 2
                implicitHeight: linhaSelo.implicitHeight + Estilo.global.padding.xs * 2
                radius: Estilo.global.radius.pill
                color: Estilo.global.background
                border.color: cartao.validador.tomStatus.border
                border.width: Estilo.global.borderWidth.hairline

                Row {
                    id: linhaSelo

                    anchors.centerIn: parent
                    spacing: Estilo.global.spacing.xs

                    Icone {
                        nome: cartao.validador.iconeStatus
                        cor: cartao.validador.tomStatus.content
                        tamanho: Estilo.global.fontSize.sm
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: cartao.validador.rotuloStatus
                        font.pixelSize: Estilo.global.fontSize.sm
                        font.bold: true
                        color: cartao.validador.tomStatus.content
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            // Fechar à mão. Sem foco: o clique não tira o teclado do campo.
            Botao {
                objectName: "fecharResultadoEndereco"
                Layout.alignment: Qt.AlignVCenter
                variante: "ghost"
                nomeIcone: "fa6s.xmark"
                tom: cartao.validador.tom
                padding: Estilo.global.padding.xs
                focusPolicy: Qt.NoFocus
                onClicked: {
                    esconder.stop();
                    cartao.dispensado = true;
                }
            }
        }

        Text {
            width: parent.width
            text: cartao.validador.resumoEndereco
            font.pixelSize: Estilo.global.fontSize.md
            font.bold: true
            color: Estilo.global.text
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: cartao.validador.resumoLocal
            font.pixelSize: Estilo.global.fontSize.sm
            color: Estilo.global.textSecondary
            wrapMode: Text.WordWrap
        }

        ProgressBar {
            width: parent.width
            visible: cartao.validador.status === "validando"
            indeterminate: true
        }

        Row {
            id: linhaZona

            width: parent.width
            visible: cartao.validador.zona === "dentro" && cartao.validador.tempoRotaMin !== null
            spacing: Estilo.global.spacing.xs

            Icone {
                id: iconeZona

                nome: "fa6s.motorcycle"
                cor: Estilo.status.success.content
                tamanho: Estilo.global.fontSize.sm
            }

            Text {
                width: linhaZona.width - iconeZona.width - linhaZona.spacing
                text: "Dentro da zona de entrega: cerca de " + Math.max(1, Math.round(cartao.validador.tempoRotaMin || 0)) + " min de carro"
                font.pixelSize: Estilo.global.fontSize.sm
                color: Estilo.status.success.content
                wrapMode: Text.WordWrap
            }
        }

        Repeater {
            model: cartao.validador.status === "validando" ? [] : cartao.validador.mensagens

            delegate: Row {
                id: linhaMensagem

                required property var modelData

                readonly property color cor: modelData.nivel === "info" ? Estilo.global.textSecondary
                                           : (modelData.nivel === "atencao" ? Estilo.status.warning.content : Estilo.status.error.content)

                width: colunaResultado.width
                spacing: Estilo.global.spacing.xs

                Icone {
                    id: iconeMensagem

                    nome: linhaMensagem.modelData.nivel === "info" ? "fa6s.circle-info"
                        : (linhaMensagem.modelData.nivel === "atencao" ? "fa6s.triangle-exclamation" : "fa6s.circle-xmark")
                    cor: linhaMensagem.cor
                    tamanho: Estilo.global.fontSize.sm
                }

                Text {
                    width: linhaMensagem.width - iconeMensagem.width - linhaMensagem.spacing
                    text: linhaMensagem.modelData.texto
                    font.pixelSize: Estilo.global.fontSize.sm
                    color: linhaMensagem.cor
                    wrapMode: Text.WordWrap
                }
            }
        }

        Flow {
            width: parent.width
            spacing: Estilo.global.spacing.sm
            visible: cartao.validador.status !== "validando"

            // Sem foco: o clique não tira o teclado do campo, e cada ação
            // já leva o foco para onde faz sentido.
            Botao {
                // Só sem a confirmação automática: com ela não há o que apertar.
                visible: !cartao.validador.confirmacaoAutomatica && cartao.validador.pronto && !cartao.validador.enderecoConfirmado
                text: "Confirmar"
                nomeIcone: "fa6s.check"
                variante: "primario"
                tom: Estilo.action.confirm
                focusPolicy: Qt.NoFocus
                onClicked: cartao.validador.concluir()
            }

            Botao {
                visible: cartao.validador.status !== "validado" && !cartao.validador.usarMesmoAssim
                text: "Usar mesmo assim"
                variante: "secundario"
                tom: Estilo.action.confirm
                focusPolicy: Qt.NoFocus
                onClicked: cartao.validador.usarAssimMesmo()
            }

            Botao {
                text: "Tentar outro"
                nomeIcone: "fa6s.rotate-left"
                variante: "ghost"
                tom: cartao.validador.tom
                focusPolicy: Qt.NoFocus
                onClicked: cartao.validador.tentarOutro()
            }
        }
    }
}
