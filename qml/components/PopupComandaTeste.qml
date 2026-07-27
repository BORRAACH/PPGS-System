import QtQuick
import QtQuick.Controls
import estilo 1.0

// Popup de confirmação usado por Balcao.qml/Entrega.qml quando o usuário
// tenta imprimir/lançar uma comanda totalmente em branco — pergunta se é
// uma comanda de teste (ex: pra testar se a impressora está respondendo)
// antes de deixar passar, já que uma comanda em branco não faz sentido
// como pedido de verdade.
Popup {
    id: popupComandaTeste

    // Guardados aqui (não em Balcao.qml/Entrega.qml) para que quem chamou
    // abrirPara() não precise manter esse estado por conta própria — o
    // handler de "respondido" só precisa ler de volta acaoPendente/dados.
    property string acaoPendente: ""
    property var dados: null

    signal respondido(bool teste)

    function abrirPara(acao, dadosPedido) {
        acaoPendente = acao;
        dados = dadosPedido;
        open();
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 25
    parent: Overlay.overlay
    anchors.centerIn: parent

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        radius: 16
        color: Estilo.cores.fundoPagina
        border.color: Estilo.cores.bordaCard
    }

    contentItem: Column {
        spacing: 20

        Row {
            spacing: 8
            Icone { nome: "fa6s.flask"; cor: Estilo.cores.texto; tamanho: 17; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "Comanda em branco"
                font.pixelSize: 17
                font.bold: true
                color: Estilo.cores.texto
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: "Nenhum campo foi preenchido. Deseja seguir mesmo assim como comanda de teste?"
            font.pixelSize: 13
            color: Estilo.cores.textoSecundario
            width: 320
            wrapMode: Text.Wrap
        }

        Row {
            spacing: 12
            anchors.right: parent.right

            Button {
                id: btnComandaNormal

                text: "Não, é normal"
                padding: 10
                onClicked: {
                    popupComandaTeste.close();
                    popupComandaTeste.respondido(false);
                }

                contentItem: Text {
                    text: btnComandaNormal.text
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Estilo.cores.textoSecundario : (parent.hovered ? "#95a5a6" : Estilo.cores.textoSecundario)
                }
            }

            Button {
                id: btnComandaTeste

                padding: 10
                onClicked: {
                    popupComandaTeste.close();
                    popupComandaTeste.respondido(true);
                }

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    Icone { nome: "fa6s.flask"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Sim, é teste"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Estilo.confirmar.pressionado : (parent.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                    border.color: Estilo.confirmar.pressionado
                    border.width: 1
                }
            }
        }
    }
}
