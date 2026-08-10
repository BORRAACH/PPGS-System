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
Item {
    id: caixaStatus

    // Cada etapa é uma linha, identificada por `id` — a mesma etapa é
    // anunciada duas vezes (ao começar e ao terminar) e a segunda substitui a
    // primeira em vez de empilhar.
    property int segundosVisivel: 4

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

    function registrar(idEtapa, texto, estado) {
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
        color: Estilo.global.surface
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
    }
}
