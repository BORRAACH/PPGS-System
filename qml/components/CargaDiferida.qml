import QtQuick
import QtQuick.Window

// Adia trabalho pesado (ler o disco, consultar um controller, preencher um
// ListModel grande) para depois que o primeiro quadro da página já está na
// tela.
//
// POR QUE ISTO EXISTE
//
// As páginas são criadas por StackView.replace() (ver components/LateralBar.qml),
// e tudo que roda em Component.onCompleted / StackView.onActivated acontece
// ANTES de o Qt sequer sincronizar a cena — ou seja, antes do primeiro pixel
// da página nova. Uma leitura de trezentas comandas do disco ali dentro não
// "demora a preencher a lista": ela segura a página inteira, e o atendente
// fica olhando a tela ANTERIOR congelada, achando que o clique não pegou.
//
// Com este componente a ordem passa a ser sempre a mesma, não importa a
// página: primeiro o esqueleto estático (cabeçalho, botões, campos, estado
// vazio) aparece e volta a responder ao mouse/teclado; só então o trabalho
// pesado começa.
//
// O GATILHO É O QUADRO, NÃO UM TIMER
//
// Um Timer de 0ms só devolve o controle ao loop de eventos — nada garante que
// um quadro tenha sido desenhado nessa volta, e numa máquina lenta o trabalho
// pesado pode muito bem entrar na frente do desenho de novo. O sinal
// frameSwapped da janela é a única coisa que significa literalmente "este
// quadro foi entregue à tela", que é a promessa que este componente faz.
//
// COMO USAR
//
//     CargaDiferida {
//         id: carga
//         tarefa: function () { carregarTudo(); }
//     }
//     Component.onCompleted: carga.agendar()
//     StackView.onActivated: carga.agendar()
Item {
    id: carga

    // O trabalho a fazer: uma function() sem argumentos.
    property var tarefa: null
    // Trava de segurança. Janela minimizada, oculta ou num compositor parado
    // não desenha quadro nenhum, e sem isto os dados nunca chegariam — a tela
    // ficaria eternamente vazia. Ao estourar este prazo a tarefa roda assim
    // mesmo.
    property int prazoMaximoMs: 500
    // true entre agendar() e a execução — a página pode ligar nisto o próprio
    // indicador de "carregando..." (ver pages/consulta/Consulta.qml).
    readonly property bool pendente: _pendente

    property bool _pendente: false

    // Pede a execução da tarefa depois do próximo quadro.
    //
    // Chamar várias vezes antes de ela rodar resulta numa execução só — o que
    // importa em duas situações reais: toda abertura de página dispara
    // Component.onCompleted E StackView.onActivated (duas chamadas), e uma
    // sincronização da malha local pode disparar um sinal de "recarregue" por
    // pedido recebido (uma rajada).
    function agendar() {
        if (!carga.tarefa)
            return ;

        carga._pendente = true;
        travaDeSeguranca.restart();
    }

    // Executa agora, sem esperar quadro nenhum — para quem já sabe que a tela
    // está de pé e quer resposta imediata (um botão "Atualizar", por exemplo).
    function executarAgora() {
        travaDeSeguranca.stop();
        execucao.stop();
        carga._pendente = false;
        if (carga.tarefa)
            carga.tarefa();

    }

    // Não ocupa espaço nem recebe eventos: é só um lugar para pendurar os
    // timers e enxergar a janela (Window.window, abaixo).
    visible: false
    width: 0
    height: 0

    // O trabalho nunca roda dentro do handler de frameSwapped: no loop de
    // renderização em thread separada esse sinal nasce na thread de render, e
    // o que se quer aqui é uma volta limpa do loop de eventos da interface,
    // com o quadro já entregue. Este Timer de 0ms é essa volta.
    Timer {
        id: execucao

        interval: 0
        repeat: false
        onTriggered: carga.executarAgora()
    }

    Timer {
        id: travaDeSeguranca

        interval: carga.prazoMaximoMs
        repeat: false
        onTriggered: execucao.restart()
    }

    Connections {
        // Só fica ligado enquanto existe tarefa pendente: um Connections vivo
        // no frameSwapped custaria uma travessia de QML por quadro, o dia
        // inteiro, justamente nas máquinas em que cada milissegundo conta.
        // Window.window é null enquanto a página ainda não entrou na janela;
        // a própria ligação se refaz sozinha quando ela entra.
        target: carga._pendente ? carga.Window.window : null
        ignoreUnknownSignals: true

        function onFrameSwapped() {
            execucao.restart();
        }
    }

}
