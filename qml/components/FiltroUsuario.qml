import QtQuick
import QtQuick.Controls
import estilo 1.0

// Seletor "mostrar só as comandas de quem lançou" — usado pela Consulta (na
// coluna da esquerda, ao lado do filtro de status) e pelo Fechamento (no
// bloco "Mapeamento por origem", ao lado da busca). Mora aqui, e não em cada
// tela, pelo mesmo motivo de components/ComboBoxPagamento.qml: as duas
// precisam da MESMA lista, do mesmo rótulo e da mesma regra de "todos", e
// duas cópias divergiriam na primeira mexida.
//
// A lista de nomes vem de fora, das comandas que a tela tem em mãos — não de
// um cadastro. É de propósito: o que interessa filtrar é quem aparece
// naquelas comandas, e um nome de usuário que não lançou nada ali só ofereceria
// um filtro que devolve lista vazia. Quem monta a lista é a tela, que sabe
// quais comandas está exibindo.
//
// O VALOR VAZIO É "TODOS". Uma comanda pode não ter usuário nenhum (comanda
// de teste, ou gravada antes de o cadastro existir, ver
// comandaParserService.PADRAO_USUARIO) e essas ficam visíveis só em "Todos" —
// não há opção "sem usuário". Oferecer uma exigiria um valor de sentinela que
// nenhum nome de usuário pudesse colidir, e o caso é raro o bastante pra não
// valer esse peso: em "Todos" elas continuam à vista, como sempre estiveram.
ComboBox {
    id: raiz

    // Nomes distintos, já ordenados, das comandas que a tela está exibindo.
    property var usuarios: []

    // O valor que está valendo AGORA; "" = todos.
    //
    // Só a tela escreve nele (por binding). Este componente nunca atribui aqui
    // — pede a mudança pelo sinal abaixo e espera o valor voltar. Escrever
    // direto quebraria o binding da página no primeiro clique, e a partir dali
    // o seletor deixaria de acompanhar quem o controla (é o que acontece com
    // qualquer property "de mão dupla" em QML).
    property string usuarioSelecionado: ""

    // Pedida a troca do filtro. Quem instancia grava o valor e refaz a lista —
    // a tela é que sabe o que "filtrar" significa nela (a Consulta remonta o
    // modelo, o Fechamento só reavalia os bindings).
    signal selecionou(string usuario)
    property color corDestaque: Estilo.global.focusRing
    // Mesma altura dos controles vizinhos de cada tela (o filtro de status na
    // Consulta, o campo de busca no Fechamento).
    property real alturaCampo: 30

    readonly property string _rotuloTodos: "Todos os usuários"

    // A opção "Todos" na frente, sempre — inclusive quando não há usuário
    // nenhum nas comandas do dia: um seletor de uma opção só é estranho, mas
    // some-lo faria a tela piscar um controle a menos quando a lista muda.
    readonly property var _opcoes: [raiz._rotuloTodos].concat(raiz.usuarios)

    model: _opcoes

    // Qual opção aparece marcada. É BINDING, e não uma atribuição num handler
    // de "a lista mudou", e isso importa: um handler desses roda ANTES de o
    // binding de _opcoes se refazer (testado — ele enxergava a lista do dia
    // anterior e mantinha selecionado um nome que já tinha saído), e logo
    // depois o próprio ComboBox zera o currentIndex ao trocar de model,
    // desfazendo o que o handler tinha escrito. Como binding, a conta é sempre
    // sobre `usuarios` — que é justamente a property que acabou de mudar.
    //
    // O ComboBox escreve em currentIndex sozinho quando alguém escolhe uma
    // opção; isso não derruba o binding (escrita vinda do C++ não derruba), e
    // o valor volta a bater na próxima vez que a tela confirmar a escolha.
    currentIndex: {
        var indice = raiz.usuarios.indexOf(raiz.usuarioSelecionado);
        // +1 porque "Todos" ocupa a posição 0 de _opcoes.
        return raiz.usuarioSelecionado !== "" && indice >= 0 ? indice + 1 : 0;
    }

    // Primeira posição é "Todos", e o valor dela é a string vazia.
    onActivated: raiz.selecionou(raiz.currentIndex === 0 ? "" : raiz.usuarios[raiz.currentIndex - 1])

    // O nome escolhido saiu da lista (a tela trocou de dia, e ninguém daquele
    // nome lançou nada nele). Deixar o filtro de pé esconderia a lista inteira
    // sem explicação, então ele é desfeito — o combo já voltou pra "Todos"
    // sozinho pelo binding acima, o que falta é avisar a tela.
    //
    // Lido de `usuarios`, e não de _opcoes, pelo mesmo motivo do comentário do
    // currentIndex: aqui _opcoes ainda pode ser a lista velha.
    onUsuariosChanged: {
        if (raiz.usuarioSelecionado !== "" && raiz.usuarios.indexOf(raiz.usuarioSelecionado) < 0)
            raiz.selecionou("");
    }

    contentItem: Row {
        leftPadding: 10
        rightPadding: 10
        spacing: Estilo.global.spacing.xs

        Icone {
            nome: "fa6s.user"
            // Apagado enquanto está em "Todos": o ícone aceso é o sinal de que
            // há um filtro escondendo comanda, e ele precisa ser visível sem
            // ler o texto do campo.
            cor: raiz.usuarioSelecionado === "" ? Estilo.global.textMuted : raiz.corDestaque
            tamanho: Estilo.global.fontSize.sm
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            width: raiz.width - 20 - Estilo.global.fontSize.sm - raiz.spacing - 22
            text: raiz.displayText
            font.pixelSize: Estilo.global.fontSize.sm
            font.bold: raiz.usuarioSelecionado !== ""
            color: Estilo.global.textInput
            verticalAlignment: Text.AlignVCenter
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
        }
    }

    // Mesma seta dos outros seletores da casa, embrulhada pelo mesmo motivo
    // documentado em ComboBoxPagamento: o Icone é uma Image que se anuncia com
    // o tamanho do bitmap superamostrado, e como indicator isso vira piso de
    // altura do combo.
    indicator: Item {
        implicitWidth: seta.tamanho
        implicitHeight: seta.tamanho
        x: raiz.width - width - 8
        y: raiz.topPadding + (raiz.availableHeight - height) / 2

        Icone {
            id: seta

            nome: "fa6s.chevron-down"
            cor: Estilo.global.textSecondary
            tamanho: Estilo.global.fontSize.sm
            anchors.centerIn: parent
        }
    }

    delegate: ItemDelegate {
        id: opcao

        required property var modelData
        required property int index

        width: ListView.view ? ListView.view.width : raiz.width
        height: 32
        highlighted: raiz.highlightedIndex === opcao.index

        contentItem: Text {
            text: opcao.modelData
            font.pixelSize: Estilo.global.fontSize.sm
            font.family: Estilo.global.fontFamily.title
            // A escolhida na cor de destaque da tela, como na lista de formas
            // de pagamento: saber qual está valendo sem contar a posição.
            color: raiz.currentIndex === opcao.index ? raiz.corDestaque : Estilo.global.text
            leftPadding: Estilo.global.padding.md
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
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
        // Teto pra uma pizzaria com muita gente cadastrada não abrir uma lista
        // maior que a janela.
        implicitHeight: Math.min(listaOpcoes.contentHeight + padding * 2, 280)

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
        // Fundo de campo enquanto filtra, transparente em "Todos" — o mesmo
        // que o filtro de status da Consulta faz com o botão ativo: um filtro
        // ligado tem que se distinguir de um desligado à distância.
        color: raiz.usuarioSelecionado === "" ? "transparent" : Estilo.global.inputBackground
        border.color: raiz.activeFocus || raiz.usuarioSelecionado !== "" ? raiz.corDestaque : Estilo.global.border
        border.width: raiz.activeFocus ? Estilo.global.borderWidth.thick : Estilo.global.borderWidth.hairline
        implicitHeight: raiz.alturaCampo
    }
}
