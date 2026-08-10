import QtQuick
import estilo 1.0

// "Área principal" de Consulta.qml: lista de comandas à esquerda
// (ColunaEsquerda.qml) e o detalhe da comanda selecionada à direita
// (PainelDetalhe.qml).
//
// Em tela larga os dois convivem lado a lado, como sempre. Quando o espaço
// não comporta os dois (tablet, janela estreita), eles passam a se revezar:
// a lista ocupa a tela inteira e, ao escolher uma comanda, o detalhe toma o
// lugar dela — com um "Voltar para a lista" no topo para desfazer a escolha.
// Espremer 36% e 64% de uma tela de 600px daria duas colunas de ~200 e ~350,
// estreitas demais tanto para ler a lista quanto para conferir a comanda.
Row {
    id: areaPrincipal

    // Referência à página Consulta.qml e ao popup de exclusão, repassados
    // para os dois filhos.
    property var pagina
    property var popupExclusao
    // Repassado de ColunaEsquerda.qml para Consulta.qml poder focar a busca
    // ao digitar sem clicar (ver Consulta.qml Keys.onPressed).
    property alias campoBusca: colunaEsquerda.campoBusca

    // Abaixo disto, lista e detalhe se revezam em vez de dividir a largura.
    readonly property bool revezando: width < 780
    readonly property bool mostrandoDetalhe: pagina && pagina.comandaSelecionada !== null

    spacing: Estilo.global.spacing.xxl

    ColunaEsquerda {
        id: colunaEsquerda

        width: areaPrincipal.revezando ? areaPrincipal.width : areaPrincipal.width * 0.36
        height: areaPrincipal.height
        visible: !areaPrincipal.revezando || !areaPrincipal.mostrandoDetalhe
        pagina: areaPrincipal.pagina
        popupExclusao: areaPrincipal.popupExclusao
        model: areaPrincipal.pagina.modelo
    }

    PainelDetalhe {
        width: areaPrincipal.revezando ? areaPrincipal.width : areaPrincipal.width * 0.64 - areaPrincipal.spacing
        height: areaPrincipal.height
        // No modo lado a lado o painel fica sempre visível (mostrando o
        // "selecione uma comanda"); no revezamento, só depois de escolher.
        visible: !areaPrincipal.revezando || areaPrincipal.mostrandoDetalhe
        pagina: areaPrincipal.pagina
        totalComandas: colunaEsquerda.totalComandas
        // O caminho de volta só existe quando a lista saiu de cena.
        mostrarVoltarParaLista: areaPrincipal.revezando
    }
}
