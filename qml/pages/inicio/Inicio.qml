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

    // Tamanho do cartão: os 120x120 de sempre, encolhendo só quando três
    // deles lado a lado não couberem mais na largura disponível — e nunca
    // abaixo de 90, onde o ícone e o rótulo deixariam de caber juntos.
    readonly property int ladoCartao: Math.max(90, Math.min(120, Math.floor((width - Estilo.global.spacing.xxl * 2 - 40) / 3)))

    Column {
        // "left/right" em vez de centerIn: com a largura amarrada ao pai, a
        // Flow de baixo sabe quanto espaço tem para decidir se os três
        // cartões cabem numa linha só (um Column centralizado teria largura
        // igual à do maior filho, e a conta seria circular).
        anchors.centerIn: parent
        width: parent.width - Estilo.global.padding.xl * 2
        spacing: Estilo.global.spacing.xxl

        Text {
            id: textoBoasVindas

            text: "Selecione o Tipo de Atendimento"
            font.pixelSize: Estilo.global.fontSize.xxl
            // Título da tela, mesma fonte de heading das outras páginas —
            // sem bold, que nela seria sintetizado (Caprasimo só tem o peso
            // 400). Ver Estilo.global.fontFamily.
            font.family: Estilo.global.fontFamily.title
            color: Estilo.global.text
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        // Flow, e não Row: quando os três cartões não couberem na largura
        // disponível, eles quebram para a linha de baixo em vez de sumirem
        // pela borda da tela. A largura é a da GRADE (só as colunas que
        // cabem), não a do pai — é isso que mantém os cartões centralizados
        // em qualquer quantidade de colunas, já que Flow sempre empilha a
        // partir da borda esquerda do próprio espaço.
        // (Os "anchors.horizontalCenter: parent" que havia aqui e nos filhos
        // eram inválidos — falta o ".horizontalCenter" do lado direito — e o
        // Qt os descartava com aviso a cada abertura, deixando tudo alinhado
        // à esquerda em vez de centralizado.)
        Flow {
            readonly property int colunas: Math.min(3, Responsivo.colunas(parent.width, telaInicio.ladoCartao, Estilo.global.spacing.xxl))

            spacing: Estilo.global.spacing.xxl
            width: colunas * telaInicio.ladoCartao + (colunas - 1) * spacing
            anchors.horizontalCenter: parent.horizontalCenter

            // Botão Balcão
            Button {
                id: btnBalcao

                implicitWidth: telaInicio.ladoCartao
                implicitHeight: telaInicio.ladoCartao
                padding: Estilo.global.padding.md
                onClicked: {
                    telaInicio.StackView.view.replace(null, "../balcao/Balcao.qml", {}, StackView.Immediate);
                }

                background: Rectangle {
                    id: bgBalcao

                    color: btnBalcao.pressed ? Estilo.orderType.balcao.surfacePressed : (btnBalcao.hovered ? Estilo.orderType.balcao.surfaceHover : Estilo.orderType.balcao.surface)
                    border.color: btnBalcao.hovered ? Estilo.orderType.balcao.base : Estilo.orderType.balcao.border
                    border.width: Estilo.global.borderWidth.thick
                    radius: Estilo.global.radius.lg

                    MultiEffect {
                        anchors.fill: parent
                        source: bgBalcao
                        shadowEnabled: true
                        shadowColor: Estilo.global.shadow
                        shadowBlur: btnBalcao.hovered ? Estilo.global.elevation.lg.blur : Estilo.global.elevation.sm.blur
                        shadowVerticalOffset: btnBalcao.pressed ? Estilo.global.elevation.sm.deslocamento : (btnBalcao.hovered ? Estilo.global.elevation.lg.deslocamento : Estilo.global.elevation.md.deslocamento)
                        shadowHorizontalOffset: 0
                        z: -1
                    }
                }

                contentItem: Column {
                    anchors.centerIn: parent
                    spacing: Estilo.global.spacing.sm

                    Icone {
                        nome: "fa6s.bag-shopping"
                        cor: Estilo.orderType.balcao.base
                        tamanho: Math.round(36 * Responsivo.escalaTexto)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "Balcão"
                        font.family: Estilo.global.fontFamily.title
                        font.pixelSize: Estilo.global.fontSize.lg
                        color: btnBalcao.pressed ? Estilo.orderType.balcao.labelPressed : Estilo.orderType.balcao.label
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            // Botão Entrega
            Button {
                id: btnEntrega

                implicitWidth: telaInicio.ladoCartao
                implicitHeight: telaInicio.ladoCartao
                padding: Estilo.global.padding.md
                onClicked: {
                    telaInicio.StackView.view.replace(null, "../entrega/Entrega.qml", {}, StackView.Immediate);
                }

                background: Rectangle {
                    id: bgEntrega

                    color: btnEntrega.pressed ? Estilo.orderType.entrega.surfacePressed : (btnEntrega.hovered ? Estilo.orderType.entrega.surfaceHover : Estilo.orderType.entrega.surface)
                    border.color: btnEntrega.hovered ? Estilo.orderType.entrega.base : Estilo.orderType.entrega.border
                    border.width: Estilo.global.borderWidth.thick
                    radius: Estilo.global.radius.lg

                    MultiEffect {
                        anchors.fill: parent
                        source: bgEntrega
                        shadowEnabled: true
                        shadowColor: Estilo.global.shadow
                        shadowBlur: btnEntrega.hovered ? Estilo.global.elevation.lg.blur : Estilo.global.elevation.sm.blur
                        shadowVerticalOffset: btnEntrega.pressed ? Estilo.global.elevation.sm.deslocamento : (btnEntrega.hovered ? Estilo.global.elevation.lg.deslocamento : Estilo.global.elevation.md.deslocamento)
                        shadowHorizontalOffset: 0
                        z: -1
                    }
                }

                contentItem: Column {
                    anchors.centerIn: parent
                    spacing: Estilo.global.spacing.sm

                    Icone {
                        nome: "fa6s.motorcycle"
                        cor: Estilo.orderType.entrega.base
                        tamanho: Math.round(36 * Responsivo.escalaTexto)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "Entrega"
                        font.family: Estilo.global.fontFamily.title
                        font.pixelSize: Estilo.global.fontSize.lg
                        color: btnEntrega.pressed ? Estilo.orderType.entrega.labelPressed : Estilo.orderType.entrega.label
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            // Botão Salão
            Button {
                id: btnSalao

                implicitWidth: telaInicio.ladoCartao
                implicitHeight: telaInicio.ladoCartao
                padding: Estilo.global.padding.md
                onClicked: {
                    telaInicio.StackView.view.replace(null, "../salao/Salao.qml", {}, StackView.Immediate);
                }

                background: Rectangle {
                    id: bgSalao

                    color: btnSalao.pressed ? Estilo.orderType.mesa.surfacePressed : (btnSalao.hovered ? Estilo.orderType.mesa.surfaceHover : Estilo.orderType.mesa.surface)
                    border.color: btnSalao.hovered ? Estilo.orderType.mesa.base : Estilo.orderType.mesa.border
                    border.width: Estilo.global.borderWidth.thick
                    radius: Estilo.global.radius.lg

                    MultiEffect {
                        anchors.fill: parent
                        source: bgSalao
                        shadowEnabled: true
                        shadowColor: Estilo.global.shadow
                        shadowBlur: btnSalao.hovered ? Estilo.global.elevation.lg.blur : Estilo.global.elevation.sm.blur
                        shadowVerticalOffset: btnSalao.pressed ? Estilo.global.elevation.sm.deslocamento : (btnSalao.hovered ? Estilo.global.elevation.lg.deslocamento : Estilo.global.elevation.md.deslocamento)
                        shadowHorizontalOffset: 0
                        z: -1
                    }
                }

                contentItem: Column {
                    anchors.centerIn: parent
                    spacing: Estilo.global.spacing.sm

                    Icone {
                        nome: "fa6s.utensils"
                        cor: Estilo.orderType.mesa.base
                        tamanho: Math.round(36 * Responsivo.escalaTexto)
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "Salão"
                        font.family: Estilo.global.fontFamily.title
                        font.pixelSize: Estilo.global.fontSize.lg
                        color: btnSalao.pressed ? Estilo.orderType.mesa.labelPressed : Estilo.orderType.mesa.label
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }
        }
    }
}
