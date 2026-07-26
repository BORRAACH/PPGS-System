import QtQuick

// "Área principal" de Consulta.qml: lista de comandas à esquerda
// (ColunaEsquerda.qml) e o detalhe da comanda selecionada à direita
// (PainelDetalhe.qml).
Row {
    id: areaPrincipal

    // Referência à página Consulta.qml e ao popup de exclusão, repassados
    // para os dois filhos.
    property var pagina
    property var popupExclusao
    // Repassado de ColunaEsquerda.qml para Consulta.qml poder focar a busca
    // ao digitar sem clicar (ver Consulta.qml Keys.onPressed).
    property alias campoBusca: colunaEsquerda.campoBusca

    spacing: 20

    ColunaEsquerda {
        id: colunaEsquerda

        width: areaPrincipal.width * 0.36
        height: areaPrincipal.height
        pagina: areaPrincipal.pagina
        popupExclusao: areaPrincipal.popupExclusao
        model: areaPrincipal.pagina.modelo
    }

    PainelDetalhe {
        width: areaPrincipal.width * 0.64 - areaPrincipal.spacing
        height: areaPrincipal.height
        pagina: areaPrincipal.pagina
        totalComandas: colunaEsquerda.totalComandas
    }
}
