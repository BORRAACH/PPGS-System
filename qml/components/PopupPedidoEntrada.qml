import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0

// "Terminal04 quer entrar na rede": a aprovação de uma máquina nova, com o
// código de 6 dígitos para conferir na tela dela (ver
// services/rede/seguranca.py, SessaoPareamento).
//
// Mora em components/ e é instanciado em main.qml, e não só em Rede.qml, porque
// o pedido chega com o atendente em qualquer tela — e expira em dois minutos.
// A tela Rede tem uma instância própria com abrirAoReceber: false, aberta pelo
// botão do pedido na lista, para quem fechou o popup e voltou depois.
//
// Aceitar passa pelo PopupAutorizacao: uma máquina aprovada recebe todas as
// comandas e o cadastro de clientes, então liberar isso é uma ação tão
// protegida quanto apagar uma comanda.
Item {
    id: raiz

    // A instância de main.qml abre sozinha quando um pedido chega.
    property bool abrirAoReceber: true

    // Resultado para quem hospeda mostrar (a tela atual tem a fila de
    // notificações — mesmo arranjo do lançamento rápido em main.qml).
    signal resultado(string mensagem, bool sucesso)

    function abrirPara(idPedido, nomeMaquina, codigo) {
        popup.idPedido = idPedido;
        popup.nomeMaquina = nomeMaquina;
        popup.codigo = codigo;
        popup.open();
    }

    function _pedidoAindaExiste() {
        var pedidos = redeController.pedidosEntrada;
        for (var i = 0; i < pedidos.length; i++) {
            if (pedidos[i].id === popup.idPedido)
                return true;
        }
        return false;
    }

    Connections {
        target: redeController

        function onPedidoEntradaRecebido(idPedido, nomeMaquina, codigo) {
            if (raiz.abrirAoReceber)
                raiz.abrirPara(idPedido, nomeMaquina, codigo);
        }

        // Pedido expirado, cancelado pela máquina nova, ou já decidido noutra
        // janela: o popup não pode ficar oferecendo aceitar algo que não existe.
        function onPareamentoMudou() {
            if (popup.visible && !raiz._pedidoAindaExiste())
                popup.close();
        }
    }

    Popup {
        id: popup

        property string idPedido: ""
        property string nomeMaquina: ""
        property string codigo: ""

        modal: true
        focus: true
        // Só Esc fecha: um clique fora sem querer não pode sumir com um pedido
        // que alguém está do outro lado esperando.
        closePolicy: Popup.CloseOnEscape
        padding: Estilo.global.padding.popup
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

        contentItem: ColumnLayout {
            spacing: Estilo.global.spacing.lg
            width: Responsivo.larguraPopup(380)

            Row {
                spacing: Estilo.global.spacing.sm

                Icone {
                    nome: "fa6s.shield-halved"
                    cor: Estilo.screen.rede.accent
                    tamanho: 18
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Máquina pedindo para entrar na rede"
                    font.pixelSize: Estilo.global.fontSize.xl
                    font.bold: true
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                Layout.fillWidth: true
                text: "'" + popup.nomeMaquina + "' quer entrar na rede desta pizzaria. Se for aprovada, ela recebe todas as comandas e o cadastro de clientes."
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.textSecondary
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: "Confira se este código aparece na tela de '" + popup.nomeMaquina + "':"
                font.pixelSize: Estilo.global.fontSize.md
                font.bold: true
                color: Estilo.global.text
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: popup.codigo
                font.pixelSize: Estilo.global.fontSize.title * 1.6
                font.family: Estilo.global.fontFamily.title
                font.letterSpacing: 6
                color: Estilo.screen.rede.accent
            }

            Text {
                Layout.fillWidth: true
                text: "Se o código for diferente, recuse: alguém pode estar tentando se passar por essa máquina."
                font.pixelSize: Estilo.global.fontSize.xs
                color: Estilo.status.error.content
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Estilo.global.spacing.md

                Item {
                    Layout.fillWidth: true
                }

                Botao {
                    text: "Recusar"
                    variante: "secundario"
                    tom: Estilo.action.danger
                    onClicked: {
                        redeController.recusarPedido(popup.idPedido);
                        popup.close();
                        raiz.resultado("Entrada de '" + popup.nomeMaquina + "' recusada.", true);
                    }
                }

                Botao {
                    text: "Os códigos são iguais — aceitar"
                    variante: "primario"
                    nomeIcone: "fa6s.check"
                    tom: Estilo.screen.rede
                    onClicked: {
                        var idPedido = popup.idPedido;
                        var nome = popup.nomeMaquina;
                        popup.close();
                        autorizacao.solicitar("Aprovar máquina na rede", nome, function () {
                            var ok = redeController.aceitarPedido(idPedido);
                            raiz.resultado(ok ? ("'" + nome + "' entrou na rede.")
                                              : ("Não foi possível aprovar '" + nome + "' — o pedido pode ter expirado."), ok);
                        });
                    }
                }
            }
        }
    }

    PopupAutorizacao {
        id: autorizacao
    }
}
