import QtQuick
import QtQuick.Controls
import estilo 1.0

// Lista de sugestões de autocomplete presa logo abaixo de um TextField —
// usada pelos campos Endereço e Bairro da Entrega.qml.
//
// Não segue o padrão dos outros popups do projeto (modal + centralizado +
// scrim, ver PopupSalvarEndereco.qml) de propósito: um dropdown de sugestões
// não pode roubar o foco nem escurecer a tela — o atendente continua
// digitando no campo enquanto a lista abre e fecha embaixo. Visual e
// navegação vêm de FiltroUsuario.qml (o popup do ComboBox) e de
// PopupBuscaCardapio.qml (setas movem a seleção sem tirar o foco do campo).
//
// Quem decide QUANDO buscar não é este componente: o debounce e a chamada ao
// pizzeriaServerController ficam com o dono do campo, que chama mostrar()
// com o que a resposta trouxe. Aqui só mora a parte de tela.
Popup {
    id: lista

    // O TextField sob o qual a lista abre. É também o pai do popup: um
    // Popup se posiciona em relação ao parent mas renderiza na camada de
    // overlay da janela — por isso a lista não é cortada nem rolada pelo
    // Flickable que envolve o formulário da Entrega.
    required property Item campo
    // Array JS puro, nunca ListModel — mesma armadilha documentada em
    // PopupBuscaCardapio.qml: array serve de model direto pra ListView.
    property var sugestoes: []
    // -1 = nada destacado ainda: Enter sem seta antes segue o fluxo normal
    // do campo (ir pro próximo), em vez de aceitar uma sugestão que o
    // atendente talvez nem tenha olhado.
    property int indiceSelecionado: -1

    // Emitido com o texto da sugestão aceita (clique ou Enter). Quem escuta
    // preenche o campo — o popup não escreve em campo.text sozinho, senão o
    // dono não teria onde cancelar o debounce que a escrita re-dispara.
    signal escolhida(string texto)

    parent: campo
    y: campo.height + Estilo.global.spacing.xs
    width: campo.width
    // Sem modal e sem foco: o teclado continua inteiro no campo, e as setas
    // chegam aqui por delegação (ver mover, chamado dos Keys do campo).
    modal: false
    focus: false
    closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
    padding: Estilo.global.spacing.xs
    // Mesmo teto de altura do popup de FiltroUsuario.qml.
    height: Math.min(listaOpcoes.contentHeight + padding * 2, 280)

    // Abre com as sugestões novas, ou fecha quando não veio nenhuma — a
    // resposta vazia é o que tira a lista da frente quando o termo digitado
    // não casa mais com nada.
    function mostrar(novas) {
        lista.sugestoes = novas || [];
        lista.indiceSelecionado = -1;
        if (lista.sugestoes.length > 0)
            lista.open();
        else
            lista.close();
    }

    // Move o destaque com clamp nas pontas — mesma mecânica do mover() de
    // PopupBuscaCardapio.qml.
    function mover(passo) {
        if (!lista.opened || lista.sugestoes.length === 0)
            return;

        var destino = lista.indiceSelecionado + passo;
        if (destino < 0)
            destino = 0;
        if (destino > lista.sugestoes.length - 1)
            destino = lista.sugestoes.length - 1;
        lista.indiceSelecionado = destino;
        listaOpcoes.positionViewAtIndex(destino, ListView.Contain);
    }

    // Aceita a sugestão destacada. Devolve false quando não há destaque —
    // é o que deixa o Enter do campo distinguir "aceitar sugestão" de
    // "seguir pro próximo campo" com um if só.
    function confirmar() {
        if (lista.indiceSelecionado < 0 || lista.indiceSelecionado >= lista.sugestoes.length)
            return false;

        lista.escolhida(lista.sugestoes[lista.indiceSelecionado]);
        lista.close();
        return true;
    }

    contentItem: ListView {
        id: listaOpcoes

        clip: true
        model: lista.sugestoes
        spacing: 2
        // Mesmo motivo de PopupBuscaCardapio.qml: a máquina do balcão tem 2
        // núcleos, reaproveitar delegate poupa reconstrução ao rolar.
        reuseItems: true

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        delegate: Rectangle {
            id: linhaSugestao

            required property int index
            // Model é array JS: o item chega inteiro em modelData.
            required property var modelData

            readonly property bool selecionada: index === lista.indiceSelecionado

            width: ListView.view.width
            height: textoSugestao.implicitHeight + Estilo.global.padding.sm * 2
            radius: Estilo.global.radius.md
            color: selecionada ? Estilo.global.surfacePressed : (areaSugestao.containsMouse ? Estilo.global.surfaceHover : "transparent")

            Text {
                id: textoSugestao

                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Estilo.global.padding.sm
                anchors.rightMargin: Estilo.global.padding.sm
                text: linhaSugestao.modelData
                font.pixelSize: Estilo.global.fontSize.md
                color: Estilo.global.text
                elide: Text.ElideRight
            }

            MouseArea {
                id: areaSugestao

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    lista.indiceSelecionado = linhaSugestao.index;
                    lista.confirmar();
                }
            }
        }
    }

    background: Rectangle {
        radius: Estilo.global.radius.lg
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
        border.width: Estilo.global.borderWidth.hairline
    }
}
