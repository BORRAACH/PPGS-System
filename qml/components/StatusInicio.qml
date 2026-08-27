import QtQuick
import QtQuick.Controls
import estilo 1.0

// Caixa no canto inferior direito que mostra o andamento do que o app faz
// sozinho ao abrir: subir a malha local, checar atualizações, procurar
// impressora (ver services/statusInicializacaoService.py e main.py).
//
// Essas tarefas rodavam ANTES da janela existir, e por isso não precisavam se
// explicar — o usuário só via a tela preta demorar. Agora que a interface abre
// primeiro e elas acontecem por trás, sem isto aqui a malha ficaria pronta em
// algum momento sem ninguém saber quando.
//
// Fica em main.qml, sobre o StackView, para acompanhar o usuário em qualquer
// tela em que ele esteja quando uma etapa terminar.
//
// FECHA NO CLIQUE, a qualquer momento — inclusive com etapa em andamento. A
// caixa não tem poder nenhum sobre as tarefas: elas são threads e timers do
// Python (ver main.py), e isto aqui é só a janela por onde elas falam. Fechar
// esconde a janela, não interrompe o trabalho.
//
// Depois de fechada no clique, só o RESULTADO a traz de volta: um "Iniciando
// X..." que chegasse em seguida reabriria a caixa que o usuário acabou de
// mandar sair da frente, e ele a fecharia de novo até desistir de fechar. O
// aviso de conclusão (ou de falha) reabre, porque é o que ele pediu ao fechar
// — "me avisa quando terminar".
Item {
    id: caixaStatus

    // Cada etapa é uma linha, identificada por `id` — a mesma etapa é
    // anunciada duas vezes (ao começar e ao terminar) e a segunda substitui a
    // primeira em vez de empilhar.
    property int segundosVisivel: 4

    // Fechada pelo usuário e ainda sem resultado nenhum para contar. Enquanto
    // for true, os avisos de "começou" são engolidos (ver registrar) — o de
    // "terminou" reabre a caixa e zera isto.
    property bool _fechadaNoClique: false

    // Só ocupa o canto: sem isto o Item cobriria a janela inteira e roubaria
    // cliques das telas por baixo.
    width: fundo.width
    height: fundo.height
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: 20
    anchors.bottomMargin: 20
    z: 1900
    visible: modeloEtapas.count > 0

    function _indiceDe(idEtapa) {
        for (var i = 0; i < modeloEtapas.count; i++) {
            if (modeloEtapas.get(i).idEtapa === idEtapa)
                return i;
        }
        return -1;
    }

    // Sai da frente agora. O que estava rodando continua rodando: quem trabalha
    // é o Python (ver main.py), e a etapa vai se anunciar de novo quando
    // terminar — `registrar` vai encontrar o modelo vazio e recriar a linha,
    // que é a "outra caixa" com o resultado.
    function fechar() {
        modeloEtapas.clear();
        timerSumir.stop();
        caixaStatus._fechadaNoClique = true;
    }

    function registrar(idEtapa, texto, estado) {
        // Uma etapa que só COMEÇOU não reabre o que o usuário fechou. A linha
        // não se perde por isso: quando ela terminar, o aviso de conclusão
        // chega, não encontra a linha no modelo e a cria — com o resultado já
        // dentro, que é o que interessa a quem fechou a caixa.
        if (caixaStatus._fechadaNoClique && estado === "andamento")
            return;

        caixaStatus._fechadaNoClique = false;

        var indice = caixaStatus._indiceDe(idEtapa);
        if (indice >= 0) {
            modeloEtapas.set(indice, { "idEtapa": idEtapa, "texto": texto, "estado": estado });
        } else {
            modeloEtapas.append({ "idEtapa": idEtapa, "texto": texto, "estado": estado });
        }

        // O timer de sumiço só começa a contar quando NADA mais está em
        // andamento: some assim que a última etapa termina, mas não no meio
        // de uma sequência.
        timerSumir.restart();
    }

    function _algumaEmAndamento() {
        for (var i = 0; i < modeloEtapas.count; i++) {
            if (modeloEtapas.get(i).estado === "andamento")
                return true;
        }
        return false;
    }

    ListModel {
        id: modeloEtapas
    }

    Connections {
        target: statusController

        function onEtapaAtualizada(idEtapa, texto, estado) {
            caixaStatus.registrar(idEtapa, texto, estado);
        }
    }

    Timer {
        id: timerSumir

        interval: caixaStatus.segundosVisivel * 1000
        onTriggered: {
            // Enquanto houver etapa rodando, continua esperando — uma
            // atualização com internet ruim pode levar 15s, e a caixa sumir
            // no meio deixaria o usuário sem saber que ainda está acontecendo.
            if (caixaStatus._algumaEmAndamento()) {
                timerSumir.restart();
                return;
            }
            modeloEtapas.clear();
        }
    }

    Rectangle {
        id: fundo

        width: 280
        height: colunaEtapas.implicitHeight + 20
        radius: Estilo.global.radius.lg
        color: areaFechar.containsMouse ? Estilo.global.surfaceHover : Estilo.global.surface
        border.color: Estilo.global.borderCard
        border.width: Estilo.global.borderWidth.hairline
        opacity: caixaStatus.visible ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Estilo.global.motion.normal
            }
        }

        Column {
            id: colunaEtapas

            x: 10
            y: 10
            width: parent.width - 20
            spacing: Estilo.global.spacing.xs

            Repeater {
                model: modeloEtapas

                delegate: Row {
                    id: linhaEtapa

                    required property string texto
                    required property string estado

                    width: colunaEtapas.width
                    spacing: Estilo.global.spacing.sm

                    // Indicador de estado: gira enquanto está em andamento,
                    // vira ✓ ou ✕ quando termina.
                    Item {
                        width: 16
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter

                        BusyIndicator {
                            anchors.fill: parent
                            running: linhaEtapa.estado === "andamento"
                            visible: running
                        }

                        Icone {
                            anchors.centerIn: parent
                            visible: linhaEtapa.estado !== "andamento"
                            nome: linhaEtapa.estado === "concluido" ? "fa6s.circle-check" : "fa6s.circle-xmark"
                            cor: linhaEtapa.estado === "concluido" ? Estilo.action.confirm.base : Estilo.action.danger.base
                            tamanho: 14
                        }
                    }

                    Text {
                        width: linhaEtapa.width - 24
                        text: linhaEtapa.texto
                        font.pixelSize: Estilo.global.fontSize.sm
                        color: linhaEtapa.estado === "falha" ? Estilo.action.danger.base : Estilo.global.text
                        wrapMode: Text.WordWrap
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // A caixa inteira é o botão de fechar, e não um × de 22px no canto: ela
        // é um aviso passageiro, não uma janela, e no balcão quem aponta é o
        // dedo. Por cima de tudo (último filho) de propósito: nenhuma linha é
        // clicável, e assim nem o BusyIndicator de 16px, que é um Control e
        // pode aceitar o evento, cria um ponto morto onde o clique não fecha.
        MouseArea {
            id: areaFechar

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: caixaStatus.fechar()
        }
    }
}
