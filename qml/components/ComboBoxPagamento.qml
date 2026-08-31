import QtQuick
import QtQuick.Controls
import estilo 1.0

// Seletor de forma de pagamento — extraído de components/CamposPagamento.qml
// (Balcão/Entrega) e de pages/salao/PopupFecharConta.qml, onde era
// byte-a-byte idêntico exceto pela largura e pela cor de destaque do foco.
// Mesmo motivo de existir de components/SpinnerCopias.qml.
//
// A lista suspensa segue o padrão do menu de contexto da Consulta (ver
// pages/consulta/ItemComandaDelegate.qml): fundo do app com canto arredondado
// e borda própria, fonte de título, realce com raio, e um ícone por opção.
//
// O Popup e o delegate PADRÃO do Qt Quick Controls não serviam: canto reto,
// fonte do sistema e as cores da palette herdada — a mesma herança do tema do
// sistema que já tinha deixado os campos brancos no Windows, e que aqui abria
// as opções praticamente invisíveis.
//
// O campo FECHADO continua só com o texto. O ícone entra na lista, onde há
// espaço: no Salão este combo tem 110px, e enfiar ícone e seta ao lado de
// "Crédito" ali deixaria o texto elidido justo na hora de conferir a conta.
ComboBox {
    id: raiz

    property color corDestaque: Estilo.global.focusRing
    // Altura do campo fechado. Vem de fora porque cada tela alinha o combo com
    // o campo vizinho (o troco no Balcão, o valor da divisão no Salão).
    //
    // `real`, e não `int`: o que chega aqui é o implicitHeight de um TextField,
    // que é fracionário (a altura da linha da fonte mais o padding). Truncar
    // deixava o combo um pixel mais baixo que o vizinho em algumas fontes.
    property real alturaCampo: 42

    // Ícone de cada forma. "fa6b.pix" é a marca do Pix de verdade (fa6b = Font
    // Awesome brands); crédito e débito precisam de ícones DIFERENTES, senão a
    // única coisa que os separa na lista continua sendo ler a palavra.
    readonly property var iconesPagamento: ({
        "Pix": "fa6b.pix",
        "Crédito": "fa6s.credit-card",
        "Débito": "fa6s.money-check-dollar",
        "Dinheiro": "fa6s.money-bill-wave"
    })

    // Uma forma que não esteja no mapa (opção nova, comanda antiga) cai num
    // ícone genérico em vez de sumir com a linha.
    function iconeDe(forma) {
        return raiz.iconesPagamento[forma] || "fa6s.receipt";
    }

    // Sem font.pixelSize: o campo fechado herda a fonte do app, que é a mesma
    // dos TextField ao lado dele (troco, taxa de entrega, valor da divisão) —
    // nenhum deles declara tamanho. Declarar um aqui deixava a forma de
    // pagamento escrita menor que os vizinhos na mesma linha.
    contentItem: Text {
        text: raiz.displayText
        color: Estilo.global.textInput
        leftPadding: 10
        rightPadding: 10
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    // A seta do estilo padrão não acompanha a paleta do app — esta é a mesma
    // dos outros seletores da casa.
    //
    // POR QUE ELA VEM EMBRULHADA NUM Item: o Icone é uma Image servida pelo
    // provider de ícones (services/iconProvider.py), que rasteriza em 3x pra
    // não borrar em tela HiDPI — e é o tamanho desse bitmap, não o tamanho
    // desenhado, que a Image anuncia como implícito (implicitHeight é
    // read-only numa Image, então não dá pra corrigir lá). Num Control do Qt
    // Quick o implícito do indicator vira PISO da altura: o combo não
    // conseguia ficar mais baixo que três setas empilhadas (39px com a seta de
    // 13), e por isso saía mais alto que o troco e a taxa ao lado sempre que a
    // fonte do sistema deixava esses campos abaixo desse piso. O Item declara
    // o tamanho de verdade e a conta do Control volta a fechar.
    indicator: Item {
        implicitWidth: seta.tamanho
        implicitHeight: seta.tamanho
        x: raiz.width - width - 12
        y: raiz.topPadding + (raiz.availableHeight - height) / 2

        Icone {
            id: seta

            nome: "fa6s.chevron-down"
            cor: Estilo.global.textSecondary
            tamanho: Estilo.global.fontSize.md
            anchors.centerIn: parent
        }
    }

    delegate: ItemDelegate {
        id: opcao

        required property var modelData
        required property int index

        width: ListView.view ? ListView.view.width : raiz.width
        height: 40
        highlighted: raiz.highlightedIndex === opcao.index

        contentItem: Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Estilo.global.padding.md
            spacing: Estilo.global.spacing.sm

            Icone {
                nome: raiz.iconeDe(opcao.modelData)
                cor: raiz.currentIndex === opcao.index ? raiz.corDestaque : Estilo.global.text
                tamanho: Estilo.global.fontSize.lg
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: opcao.modelData
                font.pixelSize: Estilo.global.fontSize.md
                font.family: Estilo.global.fontFamily.title
                // A escolhida fica na cor de destaque da tela: numa lista de
                // quatro, saber qual está valendo sem contar a posição é o que
                // evita trocar a forma de pagamento por engano.
                color: raiz.currentIndex === opcao.index ? raiz.corDestaque : Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        background: Rectangle {
            anchors.fill: parent
            anchors.margins: Estilo.global.spacing.xs
            radius: Estilo.global.radius.md
            color: opcao.down
                ? Estilo.global.surfacePressed
                : (opcao.hovered || opcao.highlighted ? Estilo.global.surfaceHover : "transparent")
        }
    }

    popup: Popup {
        y: raiz.height + Estilo.global.spacing.xs
        width: raiz.width
        padding: Estilo.global.spacing.xs
        // Teto de altura para uma lista longa não passar da janela; com as
        // quatro formas de hoje ela nunca chega perto.
        implicitHeight: Math.min(listaOpcoes.contentHeight + padding * 2, 320)

        contentItem: ListView {
            id: listaOpcoes

            clip: true
            implicitHeight: contentHeight
            model: raiz.popup.visible ? raiz.delegateModel : null
            currentIndex: raiz.highlightedIndex

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }
        }

        background: Rectangle {
            radius: Estilo.global.radius.lg
            color: Estilo.global.background
            border.color: Estilo.global.borderCard
            border.width: Estilo.global.borderWidth.hairline
        }
    }

    background: Rectangle {
        radius: Estilo.global.radius.pill
        color: Estilo.global.inputBackground
        border.color: raiz.activeFocus ? raiz.corDestaque : Estilo.global.border
        border.width: raiz.activeFocus ? Estilo.global.borderWidth.thick : Estilo.global.borderWidth.hairline
        implicitHeight: raiz.alturaCampo
    }
}
