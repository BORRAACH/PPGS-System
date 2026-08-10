import "./components"
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0

ApplicationWindow {
    // Paleta fixa para a janela inteira (herdada por todos os controles,
    // inclusive os popups de ComboBox/Menu, que não são filhos visuais das
    // páginas). No Windows, a paleta padrão vem do tema do sistema: em
    // máquinas com tema escuro, "text" e "placeholderText" chegavam claros e
    // sumiam no fundo branco dos inputs.

    id: root

    width: 600
    height: 500
    visible: true
    visibility: Window.Maximized
    color: Estilo.global.chrome
    title: "Sistema de Pedidos"
    // Isto é a rede de segurança; cada input também declara a própria "color"
    // (ver Estilo.global.textInput), de modo que nenhum campo dependa só
    // desta herança.
    palette.text: Estilo.global.textInput
    palette.placeholderText: Estilo.global.textPlaceholder
    palette.base: Estilo.global.inputBackground
    palette.windowText: Estilo.global.text

    // --- MEDIDA DA JANELA PARA O RESTO DO APP ---
    // Este é o ÚNICO ponto que alimenta o singleton Responsivo (ver
    // qml/estilo/Responsivo.qml); dali saem as escalas de fonte/espaço que
    // todas as telas já consomem por baixo, via Estilo.*, e as decisões de
    // empilhar layout. Um singleton não enxerga a janela sozinho — precisa
    // que alguém que a enxergue lhe conte, e a raiz é quem sempre a enxerga.
    // Binding declarativo, e não "onWidthChanged: Responsivo.largura = width":
    // o binding também vale no primeiro frame, antes de qualquer
    // redimensionamento acontecer.
    Binding {
        target: Responsivo
        property: "largura"
        value: root.width
        restoreMode: Binding.RestoreNone
    }

    Binding {
        target: Responsivo
        property: "altura"
        value: root.height
        restoreMode: Binding.RestoreNone
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        LateralBar {
            id: lateralBar

            stackView: stackView
        }

        // ÁREA DE CONTEÚDO DINÂMICO
        Rectangle {
            id: contentContainer

            Layout.fillWidth: true
            Layout.fillHeight: true
            // A moldura em volta do conteúdo é a primeira coisa a sumir em
            // tela pequena: são 8px de cada lado que valem mais como espaço
            // de trabalho do que como respiro.
            Layout.topMargin: Responsivo.compacto ? 0 : Math.round(8 * Responsivo.escalaEspaco)
            Layout.bottomMargin: Layout.topMargin
            Layout.rightMargin: Layout.topMargin
            color: Estilo.global.background // Cor de fundo do app
            radius: Estilo.global.radius.xl
            clip: true // Garante o corte dos elementos internos e da sombra

            StackView {
                // Volta para a tela inicial a partir de qualquer página (é o
                // que os botões "Voltar para o Menu" chamam, via
                // StackView.view.irParaInicio()).
                // Precisa ser replace(null, ...), não pop(): desde que a
                // navegação passou a trocar a pilha inteira a cada tela (ver
                // LateralBar.qml), esta pilha vive permanentemente com
                // profundidade 1 — não existe mais nada "embaixo" para onde
                // voltar, e o pop() que estas telas usavam era um no-op
                // silencioso (devolve null e deixa a tela como está).

                id: stackView

                // O caminho é resolvido a partir DESTE arquivo, então fica
                // igual para todas as páginas, não importa a pasta delas.
                function irParaInicio() {
                    if (currentItem && currentItem.objectName === "pageHome")
                        return ;

                    replace(null, "pages/inicio/Inicio.qml", {
                    }, StackView.Immediate);
                }

                anchors.fill: parent
                // Extraído para qml/pages/inicio/Inicio.qml: precisa ser um
                // destino de verdade, carregável por caminho como qualquer
                // outra página (ver LateralBar.qml) — não um Component
                // inline que só existe aqui — pra "Início" continuar
                // funcionando depois que a navegação passou a usar
                // replace(null, ...) em vez de push()/pop(null) (ver
                // comentário em LateralBar.qml).
                initialItem: "pages/inicio/Inicio.qml"

                // Sem animação de transição entre páginas — o app roda em
                // computadores fracos, e o slide padrão do StackView (dois
                // Item full-screen renderizando ao mesmo tempo durante a
                // animação) pesa demais neles. Troca instantânea em vez de
                // deslizar.
                pushEnter: Transition {
                }

                pushExit: Transition {
                }

                popEnter: Transition {
                }

                popExit: Transition {
                }

                replaceEnter: Transition {
                }

                replaceExit: Transition {
                }

            }

        }

    }

    // --- NOTIFICAÇÃO GLOBAL DO RESULTADO DA IMPRESSÃO ---
    // Vive na janela raiz (não dentro de Balcao.qml/Entrega.qml) porque o
    // resultado de rede.solicitar_impressao (ver services/rede/redeService.py)
    // chega de forma assíncrona — às vezes segundos depois, via a máquina
    // que realmente tem a impressora — e o usuário já pode ter navegado
    // para outra tela nesse meio-tempo. Mesmo padrão visual (Rectangle
    // deslizante + Timer de auto-fechar) usado em Balcao.qml/Entrega.qml.
    // Andamento do que o app faz sozinho ao abrir (malha local, atualizações,
    // impressora). Fica aqui, e não numa tela específica, porque essas tarefas
    // terminam segundos depois da abertura, com o usuário já em qualquer tela.
    StatusInicio {
    }

    Rectangle {
        id: notificacaoImpressao

        property string texto: ""
        property bool sucesso: true
        property bool aberta: false

        z: 2000
        radius: Estilo.global.radius.lg
        color: sucesso ? Estilo.action.confirm.base : Estilo.action.danger.base
        // Cresce com o texto até onde a janela permite; passando disso, é o
        // texto que encolhe (elide, abaixo) em vez de a faixa vazar pela
        // esquerda da tela.
        width: Math.min(linhaNotificacaoImpressao.implicitWidth + 40, root.width - 40)
        height: Math.max(40, linhaNotificacaoImpressao.implicitHeight + 20)
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: aberta ? 20 : -(height + 20)

        Row {
            id: linhaNotificacaoImpressao

            spacing: Estilo.global.spacing.sm
            anchors.centerIn: parent

            Icone {
                id: iconeNotificacaoImpressao

                nome: notificacaoImpressao.sucesso ? "fa6s.print" : "fa6s.circle-xmark"
                cor: Estilo.global.textOnAccent
                tamanho: Estilo.global.fontSize.lg
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: notificacaoImpressao.texto
                color: Estilo.global.textOnAccent
                font.bold: true
                font.pixelSize: Estilo.global.fontSize.lg
                // Limitado ao que sobra da faixa depois do ícone: o nome da
                // máquina que imprimiu pode ser longo, e sem isto a faixa
                // ficava mais larga que a janela.
                width: Math.min(implicitWidth, notificacaoImpressao.width - iconeNotificacaoImpressao.width - parent.spacing - 40)
                elide: Text.ElideRight
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

    Timer {
        id: timerNotificacaoImpressao

        interval: 4000
        repeat: false
        onTriggered: notificacaoImpressao.aberta = false
    }

    Connections {
        function onImpressaoResultado(sucesso, detalhe) {
            notificacaoImpressao.texto = sucesso ? ("Comanda impressa em " + detalhe) : ("Falha ao imprimir: " + detalhe);
            notificacaoImpressao.sucesso = sucesso;
            notificacaoImpressao.aberta = true;
            timerNotificacaoImpressao.restart();
        }

        target: redeController
    }

}
