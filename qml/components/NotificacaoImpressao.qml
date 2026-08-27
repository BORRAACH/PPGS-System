import QtQuick
import estilo 1.0

// A faixa que sobe do canto inferior direito com o resultado de uma impressão
// (ver redeController.impressaoResultado). Verde quando saiu, vermelha quando
// falhou — e a falha é a que mais importa: a mensagem traz o motivo, e é ela
// que o atendente precisa conseguir ler inteiro.
//
// Extraída de main.qml, onde era inline. Como componente, dá para exercitá-la
// com uma mensagem comprida sem subir o app inteiro — que é como o laço de
// binding abaixo passou despercebido.
//
// O LAÇO QUE ISTO CORRIGE. A largura da faixa vinha da largura do Row, que
// vinha da largura do Text, que vinha da largura da FAIXA. Circular: o Qt
// quebra um laço desses deixando um dos lados num valor velho, e o resultado
// era a faixa calculada estreita enquanto o texto desenhava no tamanho de
// verdade — a mensagem saía POR FORA do retângulo vermelho. Só aparecia com
// mensagem longa, que é justamente o caso de erro ("Falha ao imprimir: ...").
//
// Agora o teto de largura sai de `larguraDisponivel`, que vem de fora e não
// depende de nada aqui dentro. A cadeia ficou de mão única: janela -> texto ->
// linha -> faixa.
Rectangle {
    id: faixa

    // Largura da janela. Quem hospeda passa; o teto da faixa sai daqui.
    property real larguraDisponivel: 0
    property string texto: ""
    property bool sucesso: true
    property bool aberta: false

    readonly property real _margem: 20
    readonly property real _larguraMaxima: Math.max(120, faixa.larguraDisponivel - faixa._margem * 2)

    function mostrar(sucessoAgora, detalhe) {
        faixa.texto = sucessoAgora ? ("Comanda impressa em " + detalhe)
                                   : ("Falha ao imprimir: " + detalhe);
        faixa.sucesso = sucessoAgora;
        faixa.aberta = true;
        temporizador.restart();
    }

    z: 2000
    radius: Estilo.global.radius.lg
    color: faixa.sucesso ? Estilo.action.confirm.base : Estilo.action.danger.base
    width: Math.min(linha.implicitWidth + 40, faixa._larguraMaxima)
    height: Math.max(40, linha.implicitHeight + 20)
    anchors.right: parent.right
    anchors.rightMargin: faixa._margem
    anchors.bottom: parent.bottom
    anchors.bottomMargin: faixa.aberta ? faixa._margem : -(height + faixa._margem)

    Timer {
        id: temporizador

        interval: 4000
        repeat: false
        onTriggered: faixa.aberta = false
    }

    Row {
        id: linha

        spacing: Estilo.global.spacing.sm
        anchors.centerIn: parent

        Icone {
            id: icone

            nome: faixa.sucesso ? "fa6s.print" : "fa6s.circle-xmark"
            cor: Estilo.global.textOnAccent
            tamanho: Estilo.global.fontSize.lg
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: rotulo

            text: faixa.texto
            color: Estilo.global.textOnAccent
            font.bold: true
            font.pixelSize: Estilo.global.fontSize.lg
            // O teto vem da JANELA, nunca da faixa — é o que desfaz o laço.
            width: Math.min(implicitWidth, faixa._larguraMaxima - icone.width - linha.spacing - 40)
            // Quebra em vez de cortar: a mensagem de falha diz POR QUE não
            // imprimiu, e um "Falha ao imprimir: nenhuma impres…" esconde
            // exatamente a parte que resolve o problema. A faixa cresce em
            // altura, que é o que sobra de espaço no canto da tela.
            wrapMode: Text.Wrap
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Behavior on anchors.bottomMargin {
        NumberAnimation {
            duration: Estilo.global.motion.slow
            easing.type: Easing.OutCubic
        }
    }
}
