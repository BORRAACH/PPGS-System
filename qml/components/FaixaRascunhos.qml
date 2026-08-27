import QtQuick
import QtQuick.Controls
import estilo 1.0

// Faixa de "pedidos em andamento" no topo de Balcão e Entrega: os pedidos que
// começaram a ser tirados e ainda não foram impressos nem lançados (ver
// services/rascunhosPedido.py).
//
// Decalque da faixa de mesas abertas de pages/salao/Salao.qml, e de propósito:
// quem já sabe usar uma sabe usar a outra. Componente compartilhado, como
// SpinnerCopias.qml e ComboBoxPagamento.qml — as duas telas mostram a MESMA
// faixa, com todos os rascunhos dos dois tipos.
//
// POR QUE COMPARTILHADA, e não uma por tela: o atendente que está no Balcão
// precisa ver que há um pedido de entrega pela metade esperando. Uma faixa por
// tela esconderia metade do trabalho pendente atrás de um clique na barra
// lateral, que é justamente onde ele se perderia.
//
// Não sabe salvar nem navegar: avisa por sinal e quem a hospeda decide. É o
// mesmo desenho do callback de PopupAutorizacao — quem tem o formulário na mão
// é a tela, não a faixa.
//
// Sem botão de "novo pedido", ao contrário da faixa do Salão: começar outro
// pedido é sair da tela e voltar, que já devolve o formulário em branco (a
// barra lateral recria a página) — e o rascunho de agora continua na faixa,
// porque sair salva em vez de descartar.
Item {
    id: faixa

    // Nomeada pelo mesmo motivo dos popups das outras telas: deixa a faixa
    // alcançável de fora para inspeção e teste.
    objectName: "faixaRascunhos"

    // "Balcão" ou "Entrega" — o tipo da tela que hospeda esta faixa. Serve
    // para o clique saber se retoma aqui mesmo ou troca de tela.
    property string tipoAtual: ""
    // Id do rascunho que está aberto no formulário agora, para destacá-lo.
    property string rascunhoAtualId: ""

    property var rascunhos: []

    // Retomar um rascunho. `tipo` vem junto porque a tela precisa saber se
    // basta repovoar o formulário ou se tem de navegar para a outra.
    signal retomar(string id, string tipo)

    // Um rascunho foi descartado pelo × do card. Só a tela sabe se era o que
    // está aberto no formulário, e só ela tem como esvaziá-lo — a faixa não
    // alcança os campos (mesmo desenho de `retomar`).
    signal descartado(string id)

    function recarregar() {
        faixa.rascunhos = rascunhosController.listarRascunhos();
    }

    // Ícone por tipo, os mesmos que a tela Início usa nos cartões de Balcão e
    // Entrega — é por eles que se reconhece o tipo sem ler.
    function _icone(tipo) {
        return tipo === "Entrega" ? "fa6s.motorcycle" : "fa6s.bag-shopping";
    }

    function _cor(tipo) {
        return tipo === "Entrega" ? Estilo.screen.entrega.accent : Estilo.screen.balcao.accent;
    }

    implicitHeight: Responsivo.baixa ? 88 : 110

    Component.onCompleted: faixa.recarregar()

    // Podado por idade em outra abertura, ou apagado por outra tela — a faixa
    // acompanha em vez de mostrar um card que já não abre.
    Connections {
        target: rascunhosController

        function onRascunhosAtualizados() {
            faixa.recarregar();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Estilo.global.radius.md
        color: Estilo.global.surface
        border.color: Estilo.global.borderCard
        border.width: Estilo.global.borderWidth.hairline

        Text {
            anchors.centerIn: parent
            visible: faixa.rascunhos.length === 0
            text: "Nenhum pedido em andamento."
            font.italic: true
            color: Estilo.global.textSecondary
        }

        ListView {
            id: listaRascunhos

            anchors.fill: parent
            anchors.margins: 8
            orientation: ListView.Horizontal
            spacing: Estilo.global.spacing.md
            clip: true
            model: faixa.rascunhos

            delegate: Rectangle {
                id: cardRascunho

                required property var modelData

                readonly property bool ehAtual: cardRascunho.modelData.id === faixa.rascunhoAtualId

                width: Responsivo.compacto ? 140 : 170
                height: ListView.view.height
                radius: Estilo.global.radius.md
                color: cardRascunho.ehAtual
                    ? Estilo.global.surfaceHover
                    : (areaCard.containsMouse ? Estilo.global.surfaceHover : Estilo.global.background)
                border.color: cardRascunho.ehAtual
                    ? faixa._cor(cardRascunho.modelData.tipo)
                    : Estilo.global.borderCard
                border.width: cardRascunho.ehAtual ? 2 : 1

                MouseArea {
                    id: areaCard

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: faixa.retomar(cardRascunho.modelData.id, cardRascunho.modelData.tipo)
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    width: parent.width - 16

                    Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.horizontalCenter: parent.horizontalCenter

                        Icone {
                            nome: faixa._icone(cardRascunho.modelData.tipo)
                            cor: faixa._cor(cardRascunho.modelData.tipo)
                            tamanho: Estilo.global.fontSize.md
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: cardRascunho.modelData.tipo
                            font.pixelSize: Estilo.global.fontSize.sm
                            font.family: Estilo.global.fontFamily.title
                            color: faixa._cor(cardRascunho.modelData.tipo)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        text: cardRascunho.modelData.cliente && cardRascunho.modelData.cliente.trim() !== ""
                            ? cardRascunho.modelData.cliente
                            : "Sem nome"
                        font.pixelSize: Estilo.global.fontSize.md
                        color: Estilo.global.text
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        text: cardRascunho.modelData.quantidadeItens
                            + (cardRascunho.modelData.quantidadeItens === 1 ? " item" : " itens")
                        font.pixelSize: Estilo.global.fontSize.xs
                        color: Estilo.global.textSecondary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "R$ " + cardRascunho.modelData.valorTotal.toFixed(2).replace(".", ",")
                        font.pixelSize: Estilo.global.fontSize.md
                        font.bold: true
                        color: Estilo.global.text
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                // Descartar. Fica por cima de areaCard (declarada antes,
                // então perde a disputa de z-order), senão o clique aqui
                // também abriria o rascunho no formulário — mesma solução
                // do botão de excluir mesa aberta no Salão.
                Button {
                    id: btnDescartar

                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 4
                    width: 22
                    height: 22
                    padding: 0
                    onClicked: {
                        var id = cardRascunho.modelData.id;
                        rascunhosController.excluirRascunho(id);
                        // Avisa a tela ANTES de recarregar: se este era o
                        // rascunho aberto, ela precisa esvaziar o formulário e
                        // soltar o id. Sem isso o autosave o gravava de volta
                        // três segundos depois, com o mesmo id — o card sumia
                        // e reaparecia sozinho.
                        faixa.descartado(id);
                        faixa.recarregar();
                    }

                    contentItem: Icone {
                        nome: "fa6s.xmark"
                        cor: Estilo.action.danger.base
                        tamanho: 11
                        anchors.centerIn: parent
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnDescartar.hovered ? Estilo.status.error.background : "transparent"
                    }
                }
            }
        }
    }
}
