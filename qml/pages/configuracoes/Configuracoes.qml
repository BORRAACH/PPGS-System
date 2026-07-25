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

    // Grava a configuração de estilo pendente quando o usuário sai desta
    // tela clicando em outro ícone da barra lateral — nesse caso a página
    // só é empurrada pra baixo na pilha (não destruída), então
    // EstiloImpressora.qml continua viva e seu Component.onDestruction (que
    // cobre Voltar/Início/fechar o app) não dispara.
    StackView.onDeactivated: estiloImpressora.salvarNoBackend()

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

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            EstiloImpressora {
                id: estiloImpressora

                width: parent.width
            }
        }

        // --- BOTÃO VOLTAR ---
        Button {
            id: btnVoltar

            padding: 10
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 200
            onClicked: {
                if (telaConfiguracoes.StackView.view)
                    telaConfiguracoes.StackView.view.pop();
            }

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
