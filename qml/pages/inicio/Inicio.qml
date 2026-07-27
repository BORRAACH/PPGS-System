import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import estilo 1.0
import "../../components"

// Tela inicial ("Início" na barra lateral) — extraída de dentro de
// qml/main.qml (era o initialItem inline da StackView) para virar um
// destino igual a qualquer outro (ver LateralBar.qml), depois que a
// navegação passou a usar replace(null, ...) em vez de push()/pop(null)
// para não acumular telas nunca destruídas (ver o comentário em
// LateralBar.qml). Enquanto Início era só o "fundo" da pilha, pop(null)
// bastava pra voltar a ele; agora que replace(null, ...) troca a pilha
// INTEIRA a cada navegação (inclusive o que estava embaixo), só sobra
// alguma coisa pra "voltar" se Início também for um destino de verdade,
// recarregado como qualquer outra tela.
Item {
    id: telaInicio

    objectName: "pageHome"
    anchors.fill: parent

    Column {
        anchors.centerIn: parent
        spacing: 25

        Text {
            id: textoBoasVindas

            text: "Selecione o Tipo de Atendimento"
            font.pixelSize: 20
            font.bold: true
            color: Estilo.cores.texto
            anchors.horizontalCenter: parent
        }

        Row {
            spacing: 20
            anchors.horizontalCenter: parent

            // Botão Balcão
            Button {
                id: btnBalcao

                implicitWidth: 120
                implicitHeight: 120
                padding: 10
                onClicked: {
                    telaInicio.StackView.view.replace(null, "../balcao/Balcao.qml", {}, StackView.Immediate);
                }

                background: Rectangle {
                    id: bgBalcao

                    color: btnBalcao.pressed ? "#35d97706" : (btnBalcao.hovered ? "#20d97706" : "#0ad97706")
                    border.color: btnBalcao.hovered ? "#d97706" : "#fcd34d"
                    border.width: 2
                    radius: Estilo.rounding.medio

                    MultiEffect {
                        anchors.fill: parent
                        source: bgBalcao
                        shadowEnabled: true
                        shadowColor: "#20000000"
                        shadowBlur: btnBalcao.hovered ? 0.8 : 0.4
                        shadowVerticalOffset: btnBalcao.pressed ? 1 : (btnBalcao.hovered ? 4 : 2)
                        shadowHorizontalOffset: 0
                        z: -1
                    }
                }

                contentItem: Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Icone {
                        nome: "fa6s.bag-shopping"
                        cor: "#d97706"
                        tamanho: 36
                        anchors.horizontalCenter: parent
                    }

                    Text {
                        text: "Balcão"
                        font.pixelSize: Estilo.fonte.padrao
                        font.bold: true
                        color: btnBalcao.pressed ? "#92400e" : "#b45309"
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent
                    }
                }
            }

            // Botão Entrega
            Button {
                id: btnEntrega

                implicitWidth: 120
                implicitHeight: 120
                padding: 10
                onClicked: {
                    telaInicio.StackView.view.replace(null, "../entrega/Entrega.qml", {}, StackView.Immediate);
                }

                background: Rectangle {
                    id: bgEntrega

                    color: btnEntrega.pressed ? "#350284c7" : (btnEntrega.hovered ? "#200284c7" : "#0a0284c7")
                    border.color: btnEntrega.hovered ? "#0284c7" : "#7dd3fc"
                    border.width: 2
                    radius: Estilo.rounding.medio

                    MultiEffect {
                        anchors.fill: parent
                        source: bgEntrega
                        shadowEnabled: true
                        shadowColor: "#20000000"
                        shadowBlur: btnEntrega.hovered ? 0.8 : 0.4
                        shadowVerticalOffset: btnEntrega.pressed ? 1 : (btnEntrega.hovered ? 4 : 2)
                        shadowHorizontalOffset: 0
                        z: -1
                    }
                }

                contentItem: Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Icone {
                        nome: "fa6s.motorcycle"
                        cor: "#0284c7"
                        tamanho: 36
                        anchors.horizontalCenter: parent
                    }

                    Text {
                        text: "Entrega"
                        font.pixelSize: Estilo.fonte.padrao
                        font.bold: true
                        color: btnEntrega.pressed ? "#075985" : "#0369a1"
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent
                    }
                }
            }

            // Botão Salão
            Button {
                id: btnSalao

                implicitWidth: 120
                implicitHeight: 120
                padding: 10
                onClicked: {
                    telaInicio.StackView.view.replace(null, "../salao/Salao.qml", {}, StackView.Immediate);
                }

                background: Rectangle {
                    id: bgSalao

                    color: btnSalao.pressed ? "#350d9488" : (btnSalao.hovered ? "#200d9488" : "#0a0d9488")
                    border.color: btnSalao.hovered ? "#0d9488" : "#5eead4"
                    border.width: 2
                    radius: Estilo.rounding.medio

                    MultiEffect {
                        anchors.fill: parent
                        source: bgSalao
                        shadowEnabled: true
                        shadowColor: "#20000000"
                        shadowBlur: btnSalao.hovered ? 0.8 : 0.4
                        shadowVerticalOffset: btnSalao.pressed ? 1 : (btnSalao.hovered ? 4 : 2)
                        shadowHorizontalOffset: 0
                        z: -1
                    }
                }

                contentItem: Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Icone {
                        nome: "fa6s.utensils"
                        cor: "#0d9488"
                        tamanho: 36
                        anchors.horizontalCenter: parent
                    }

                    Text {
                        text: "Salão"
                        font.pixelSize: Estilo.fonte.padrao
                        font.bold: true
                        color: btnSalao.pressed ? "#115e59" : "#0f766e"
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent
                    }
                }
            }
        }
    }
}
