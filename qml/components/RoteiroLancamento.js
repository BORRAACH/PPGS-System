.pragma library

// Quais perguntas o lançamento rápido faz para cada categoria do cardápio, e
// quais itens conseguem iniciar um lançamento.
//
// Mora aqui, e não dentro de PopupLancamentoRapido.qml, porque o popup de
// BUSCA precisa da resposta antes de o fluxo existir: é ela que decide se o
// botão "Lançar pedido" aparece e se o Enter faz alguma coisa, a cada item
// destacado. Com a regra dentro do popup do fluxo, ele teria que ser
// construído na abertura do app só para responder isso — 83 QObjects e ~20 ms
// (medidos) gastos antes do primeiro quadro, numa máquina de 2 núcleos, por
// uma tela que na maioria das vezes nem chega a ser aberta.
//
// .pragma library: uma instância só para o app inteiro, sem custo por objeto.

// Categorias que se vendem sozinhas — as demais (bordas e adicionais) entram
// pelo caminho invertido, escolhendo depois o item que as recebe.
var CATEGORIAS_ITEM = ["pizzas", "lanches", "bebidas", "acaiTamanhos", "outros"];

function vendeSozinho(chaveCategoria) {
    return CATEGORIAS_ITEM.indexOf(chaveCategoria || "") !== -1;
}

// Categoria do item BASE de um modificador: é ela que a etapa "base" lista.
function categoriaBaseDe(chaveModificador) {
    if (chaveModificador === "pizzaBordas" || chaveModificador === "pizzaAdicionais")
        return "pizzas";
    if (chaveModificador === "lanchesAdicionais")
        return "lanches";
    if (chaveModificador === "acaiAdicionais")
        return "acaiTamanhos";
    return "";
}

// As etapas, na ordem, para a categoria do item que abriu o fluxo. Lista vazia
// = esta categoria não sabe virar pedido (e aí o Enter da busca não faz nada).
function sequenciaDe(chaveCategoria) {
    switch (chaveCategoria) {
    case "pizzas":
        return ["tamanho", "borda", "adicionais", "tipo"];
    case "lanches":
        return ["pao", "adicionais", "tipo"];
    case "acaiTamanhos":
        return ["adicionais", "tipo"];
    case "bebidas":
    case "outros":
        return ["tipo"];
    // Caminho invertido: o modificador já está escolhido e o que falta é o
    // item em que ele vai. A etapa do próprio modificador some do roteiro.
    case "pizzaBordas":
        return ["base", "tamanho", "adicionais", "tipo"];
    case "pizzaAdicionais":
        return ["base", "tamanho", "borda", "tipo"];
    case "lanchesAdicionais":
        return ["base", "pao", "tipo"];
    case "acaiAdicionais":
        return ["base", "adicionais", "tipo"];
    }
    return [];
}

// Dá pra começar um lançamento a partir deste resultado de busca, por qualquer
// um dos dois caminhos?
function podeLancar(item) {
    return !!item && sequenciaDe(item.chaveCategoria || "").length > 0;
}
