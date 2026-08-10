import QtQuick
import estilo 1.0

// Empilha notificações temporárias (sucesso/erro) no canto inferior
// direito da página que a instanciar — usada por Balcao.qml/Entrega.qml
// tanto para o resultado de salvar/lançar o pedido quanto para o
// resultado assíncrono da impressão (rede.impressaoResultado).
//
// Antes, cada página tinha um único banner reaproveitado (mesmo
// Rectangle sempre, só trocando texto/cor) — se duas notificações
// chegassem perto uma da outra (ex: "Pedido salvo com sucesso!" e, um
// pouco depois, o resultado de verdade da impressão), a segunda
// simplesmente reiniciava o mesmo banner por cima da primeira, sem dar
// tempo de ler nenhuma delas direito. Aqui cada chamada a notificar()
// empilha um item novo e independente, que entra sozinho, some sozinho
// depois de alguns segundos, e empurra os anteriores pra cima — nunca
// dois no mesmo lugar.
Item {
    id: raiz

    anchors.fill: parent
    // Acima de qualquer conteúdo da página, mas não intercepta cliques
    // fora dos próprios balões (só a Column com os balões tem área real).
    z: 1000

    property int _proximoId: 0

    function notificar(mensagem, sucesso) {
        modeloToasts.append({
            "texto": mensagem,
            "sucesso": sucesso,
            "chave": raiz._proximoId
        });
        raiz._proximoId += 1;
    }

    ListModel {
        id: modeloToasts
    }

    Column {
        id: colunaToasts

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 20
        spacing: Estilo.global.spacing.md

        // Item novo nasce transparente e desliza de baixo pra cima até o
        // lugar dele na pilha (mesma sensação de "subir" do banner único
        // antigo, só que agora empilhando em vez de substituir).
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Estilo.global.motion.normal }
            NumberAnimation { property: "y"; from: colunaToasts.height + 20; duration: Estilo.global.motion.normal; easing.type: Easing.OutCubic }
        }
        // Reacomoda os itens que sobraram quando um é removido do meio/topo.
        // Column (Positioner) não tem uma transição "remove" própria (só
        // Views como ListView têm) — o fade-out de saída é feito à mão no
        // delegate abaixo, antes de tirar o item do modelo de verdade.
        move: Transition {
            NumberAnimation { property: "y"; duration: Estilo.global.motion.normal; easing.type: Easing.OutCubic }
        }

        Repeater {
            model: modeloToasts

            delegate: Rectangle {
                id: itemToast

                radius: Estilo.global.radius.lg
                color: model.sucesso ? Estilo.action.confirm.base : Estilo.action.danger.base
                width: linhaToast.implicitWidth + 40
                height: 50

                Row {
                    id: linhaToast

                    spacing: Estilo.global.spacing.sm
                    anchors.centerIn: parent

                    Icone {
                        nome: model.sucesso ? "fa6s.circle-check" : "fa6s.circle-xmark"
                        cor: Estilo.global.textOnAccent
                        tamanho: Estilo.global.fontSize.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: model.texto
                        color: Estilo.global.textOnAccent
                        font.bold: true
                        font.pixelSize: Estilo.global.fontSize.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Behavior on opacity {
                    NumberAnimation { duration: Estilo.global.motion.fast }
                }

                Timer {
                    interval: 3000
                    running: true
                    onTriggered: itemToast.opacity = 0
                }

                // Só some do modelo de verdade depois do fade acima
                // terminar — senão o item piscaria pra fora sem transição.
                Timer {
                    interval: 3150
                    running: true
                    onTriggered: modeloToasts.remove(index)
                }
            }
        }
    }
}
