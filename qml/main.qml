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
    // --- CONSULTA RÁPIDA AO CARDÁPIO (Ctrl+S) ---
    // Vive na janela raiz pelo mesmo motivo da notificação de impressão
    // abaixo: é global. Uma instância por página morreria na troca de tela, e
    // o atalho só valeria nas páginas que lembrassem de declará-lo.

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

    // Qt.ApplicationShortcut, e não o contexto padrão (janela): sem isso o
    // atalho não dispara quando o foco está dentro de um popup modal — que é
    // exatamente onde o atendente está ao montar um pedido pelo popup de
    // seleção. Ctrl+S não conflita com nada: as telas de pedido usam Ctrl+A e
    // Ctrl+R, e o app não tem "salvar" por teclado.
    Shortcut {
        // Alterna: com o popup aberto, o mesmo Ctrl+S fecha. Sem isto a
        // segunda batida no atalho seria um no-op silencioso, e o atendente
        // fica com a mão no teclado — Esc é outro alcance.
        // `visible`, e não `opened`: `opened` só fica true quando a transição
        // de entrada TERMINA, então num estilo com animação de popup a batida
        // seguinte cairia no `open()` de novo em vez de fechar. O estilo hoje
        // é o Fusion (fixado em Config/preConfig.py), que não anima popup, mas
        // `visible` é verdade nos dois casos e não depende disso.

        sequence: "Ctrl+S"
        context: Qt.ApplicationShortcut
        // Uma ativação por batida, não uma por repetição do teclado. O padrão
        // de Shortcut.autoRepeat é TRUE: segurar Ctrl+S faz o Qt disparar
        // onActivated a cada repetição que o sistema manda (no Windows, a
        // primeira vem em ~250-500 ms e depois até ~30 por segundo), e como
        // este onActivated ALTERNA, o resultado é abre/fecha/abre/fecha —
        // terminando fechado em número par de repetições. Ou seja: o atalho
        // "não funciona" exatamente para quem segura a tecla, que é o que se
        // faz quando a máquina demora a responder — e as máquinas do balcão
        // são justamente as lentas (2 núcleos). Aqui não passa despercebido
        // porque a primeira abertura ainda lê os arquivos do cardápio e monta
        // o índice (ver services/buscaCardapio.py).
        autoRepeat: false
        // A guarda do fluxo de lançamento não é preciosismo: com ele aberto
        // (digamos, na etapa "borda"), um Ctrl+S batido por reflexo fecharia a
        // BUSCA por baixo dele — e o onOpened da busca limpa o termo, então o
        // fluxo ficaria órfão sobre uma tela que já se esqueceu do que estava
        // fazendo.
        onActivated: {
            if (popupBuscaCardapio.fluxoAtivo)
                return ;

            popupBuscaCardapio.visible ? popupBuscaCardapio.close() : popupBuscaCardapio.open();
        }
    }

    PopupBuscaCardapio {
        id: popupBuscaCardapio

        pilhaPrincipal: stackView
        // A tela de destino é quem tem a fila de notificações; o lançamento
        // acabou de trazer o atendente pra ela (ou já estava nela).
        onLancamentoConcluido: function(mensagem, sucesso) {
            if (stackView.currentItem && stackView.currentItem.mostrarNotificacao)
                stackView.currentItem.mostrarNotificacao(mensagem, sucesso);

        }
    }

    // O resultado de qualquer impressão do app, em qualquer tela — daí morar
    // aqui e não numa página (ver components/NotificacaoImpressao.qml).
    NotificacaoImpressao {
        id: notificacaoImpressao

        larguraDisponivel: root.width
    }

    Connections {
        function onImpressaoResultado(sucesso, detalhe) {
            notificacaoImpressao.mostrar(sucesso, detalhe);
        }

        target: redeController
    }

}
