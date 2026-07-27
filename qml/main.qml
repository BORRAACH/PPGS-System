import "./components"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0

ApplicationWindow {
    id: root

    width: 600
    height: 500
    visible: true
    visibility: Window.Maximized
    color: Qt.darker(Estilo.cores.fundoPagina, 1.8)
    title: "Sistema de Pedidos"

    RowLayout {
        anchors.fill: parent
        spacing: 0

        LateralBar {
            id: lateralBar

            stackView: stackView
        }

        // ÁREA DE CONTEÚDO DINÂMICO
        Rectangle {
            id: contentContainer

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            Layout.rightMargin: 8
            color: Estilo.cores.fundoPagina // Cor de fundo do app
            radius: Estilo.rounding.popup
            clip: true // Garante o corte dos elementos internos e da sombra

            StackView {
                id: stackView

                anchors.fill: parent

                // Sem animação de transição entre páginas — o app roda em
                // computadores fracos, e o slide padrão do StackView (dois
                // Item full-screen renderizando ao mesmo tempo durante a
                // animação) pesa demais neles. Troca instantânea em vez de
                // deslizar.
                pushEnter: Transition {}
                pushExit: Transition {}
                popEnter: Transition {}
                popExit: Transition {}
                replaceEnter: Transition {}
                replaceExit: Transition {}

                // Extraído para qml/pages/inicio/Inicio.qml: precisa ser um
                // destino de verdade, carregável por caminho como qualquer
                // outra página (ver LateralBar.qml) — não um Component
                // inline que só existe aqui — pra "Início" continuar
                // funcionando depois que a navegação passou a usar
                // replace(null, ...) em vez de push()/pop(null) (ver
                // comentário em LateralBar.qml).
                initialItem: "pages/inicio/Inicio.qml"
            }
        }
    }

    // --- NOTIFICAÇÃO GLOBAL DO RESULTADO DA IMPRESSÃO ---
    // Vive na janela raiz (não dentro de Balcao.qml/Entrega.qml) porque o
    // resultado de rede.solicitar_impressao (ver services/rede/redeService.py)
    // chega de forma assíncrona — às vezes segundos depois, via a máquina
    // que realmente tem a impressora — e o usuário já pode ter navegado
    // para outra tela nesse meio-tempo. Mesmo padrão visual (Rectangle
    // deslizante + Timer de auto-fechar) usado em Balcao.qml/Entrega.qml.
    Rectangle {
        id: notificacaoImpressao

        property string texto: ""
        property bool sucesso: true
        property bool aberta: false

        z: 2000
        radius: Estilo.rounding.medio
        color: sucesso ? Estilo.confirmar.normal : Estilo.cancelar.normal
        width: linhaNotificacaoImpressao.implicitWidth + 40
        height: 50
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: aberta ? 20 : -(height + 20)

        Behavior on anchors.bottomMargin {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }

        Row {
            id: linhaNotificacaoImpressao

            spacing: 8
            anchors.centerIn: parent

            Icone {
                nome: notificacaoImpressao.sucesso ? "fa6s.print" : "fa6s.circle-xmark"
                cor: "#ffffff"
                tamanho: Estilo.fonte.padrao
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: notificacaoImpressao.texto
                color: "#ffffff"
                font.bold: true
                font.pixelSize: Estilo.fonte.padrao
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    Timer {
        id: timerNotificacaoImpressao

        interval: 4000
        repeat: false
        onTriggered: notificacaoImpressao.aberta = false
    }

    Connections {
        target: redeController
        function onImpressaoResultado(sucesso, detalhe) {
            notificacaoImpressao.texto = sucesso ? ("Comanda impressa em " + detalhe) : ("Falha ao imprimir: " + detalhe);
            notificacaoImpressao.sucesso = sucesso;
            notificacaoImpressao.aberta = true;
            timerNotificacaoImpressao.restart();
        }
    }
}
