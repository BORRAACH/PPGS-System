import QtQuick
import estilo 1.0

// Uma divisória do cupom na prévia (ver EstiloImpressora.qml): a linha de
// traços em si, envolta pelas linhas em branco de `espacamento_secoes` dos
// dois lados — exatamente como comandaTextoService.montar_linhas_por_ordem
// monta em volta de cada separador.
//
// `separador` vale "" (nenhuma divisória aqui), "-" (linhas de traço) ou "="
// (fronteira da tabela de itens, o MARCADOR_ITENS do Python).
Column {
    id: raizSeparador

    property real largura: 0
    property string separador: ""
    // Quantas linhas de traço empilhadas — configurável para o "-" (ver
    // linhasTracoAntes em EstiloImpressora.qml), sempre 1 para o "=", que o
    // Python nunca repete (consultaController.reconstruirComanda acha a
    // tabela de itens contando marcadores).
    property int repeticoes: 1
    property int linhasEmBranco: 0
    property real alturaLinha: 0
    property int tamanhoFonte: 12
    // A família em que o papel inteiro está sendo escrito (ver
    // EstiloImpressora.fontePrevia). A divisória precisa da mesma: são 40
    // caracteres, e a largura deles tem que bater com a das linhas de texto.
    property string familia: "monospace"
    // Recebidas prontas em vez de montadas aqui: quem chama já tem a
    // largura da comanda em caracteres (colunasPapel) e repete o caractere
    // uma vez só, em vez de uma vez por linha da comanda.
    property string traco: ""
    property string marcador: ""

    width: largura
    spacing: 0
    // Column ignora filhos invisíveis inclusive no spacing — por isso
    // `visible: false` em vez de `height: 0`, que deixaria um buraco
    // fantasma do tamanho de um spacing onde não há divisória nenhuma.
    visible: separador !== "" && repeticoes > 0

    Item {
        width: 1
        height: raizSeparador.linhasEmBranco * raizSeparador.alturaLinha
        visible: raizSeparador.linhasEmBranco > 0
    }

    Repeater {
        model: raizSeparador.repeticoes

        delegate: Text {
            text: raizSeparador.separador === "=" ? raizSeparador.marcador : raizSeparador.traco
            font.family: raizSeparador.familia
            font.pixelSize: raizSeparador.tamanhoFonte
            color: Estilo.printer.ink
        }
    }

    Item {
        width: 1
        height: raizSeparador.linhasEmBranco * raizSeparador.alturaLinha
        visible: raizSeparador.linhasEmBranco > 0
    }
}
