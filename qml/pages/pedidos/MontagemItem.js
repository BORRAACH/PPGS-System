.pragma library

// Montagem do item de pedido: transforma o que o atendente escolheu no objeto
// que as telas de venda (Balcão/Entrega/Salão) põem em modeloPedidos.
//
// Existe porque o NOME e o VALOR montados aqui são contrato com o Python, não
// texto solto de tela. services/comandaTextoService.py:dividir_sabores
// reparseia o nome impresso — o sufixo "(...)" final vira o tamanho e " / "
// separa os sabores de uma meio a meio — e a contagem de produtos vendidos do
// fechamento (fechamentoController._calcular_resumo_dia) agrupa as vendas por
// esse mesmo texto. Montar o nome de forma diferente em dois lugares não dá
// erro nenhum na hora: dá comanda impressa errada e relatório de vendas
// errado, dias depois, sem stack trace.
//
// Antes disso, cada página de categoria (pizzas/lanches/acai/bebidas/outros)
// montava o seu no corpo do próprio btnConfirmar, e o lançamento rápido pelo
// Ctrl+S (ver qml/components/PopupLancamentoRapido.qml) seria um sexto lugar.
//
// É .pragma library de propósito: nada aqui lê id, binding ou controller — são
// funções puras sobre objetos JS, o que também as torna testáveis sem UI.

// Todo valor que sai daqui é string no formato do cupom.
function formatarMoeda(valorNum) {
    return "R$ " + valorNum.toFixed(2).replace(".", ",");
}

// "24,90" (como está no JSON do cardápio) ou "R$ 24,90" -> 24.9.
// Devolve 0 no que não der pra ler, em vez de NaN: um preço ilegível vira uma
// linha de R$ 0,00 que o atendente vê e corrige, e não um total inteiro
// contaminado por NaN.
function parseValor(texto) {
    if (typeof texto === "number")
        return texto;

    var limpo = String(texto || "").replace("R$", "").trim().replace(",", ".");
    var numero = parseFloat(limpo);
    return isNaN(numero) ? 0 : numero;
}

function _somaAdicionais(adicionais) {
    var soma = 0;
    var lista = adicionais || [];
    for (var i = 0; i < lista.length; i++)
        soma += lista[i].valorNum;
    return soma;
}

// {sabores: [{nome, valorNum}], tamanho: "Grande", valorNum,
//  borda: {nome, valorNum} | null, adicionais: [{sabor, nome, valorNum}]}
//
// `valorNum` é o preço BASE da pizza e continua sendo responsabilidade de quem
// chama: numa meio a meio é o MAIOR entre os sabores, não a soma (regra da
// casa, ver valorAtualMaior em pizzas/Pizzas.qml).
function montarPizza(pizza) {
    var nomes = (pizza.sabores || []).map(function (sabor) {
        return sabor.nome;
    });

    var borda = pizza.borda ? {
        "nome": pizza.borda.nome,
        "valor": formatarMoeda(pizza.borda.valorNum)
    } : null;

    var adicionais = (pizza.adicionais || []).map(function (adicional) {
        return {
            "sabor": adicional.sabor,
            "nome": adicional.nome,
            "valor": formatarMoeda(adicional.valorNum)
        };
    });

    var total = pizza.valorNum + (pizza.borda ? pizza.borda.valorNum : 0) + _somaAdicionais(pizza.adicionais);

    return {
        // " / " entre os sabores e o tamanho entre parênteses no fim: as duas
        // coisas que dividir_sabores procura do outro lado.
        "nome": nomes.join(" / ") + " (" + pizza.tamanho + ")",
        "valor": formatarMoeda(total),
        "observacao": "",
        "borda": borda,
        "adicionais": adicionais
    };
}

// {nome, resumoPao: "" | "frances" | "baby", valorNum,
//  adicionais: [{nome, valorNum}]}
//
// Recebe `resumoPao` já resolvido (e não o rótulo do pão) porque a tabela que
// traduz um no outro é local de lanches/Lanches.qml. O pão de hambúrguer é o
// padrão e não aparece no nome — daí o resumo vazio.
function montarLanche(lanche) {
    // O "sabor" do adicional é o nome BASE do lanche, sem o sufixo do pão: é
    // contra ele que comandaTextoService._extras_adicionais casa o adicional
    // na hora de imprimir, e dividir_sabores trataria um "( frances )" final
    // como tamanho, não como parte do nome.
    var adicionais = (lanche.adicionais || []).map(function (adicional) {
        return {
            "sabor": lanche.nome,
            "nome": adicional.nome,
            "valor": formatarMoeda(adicional.valorNum)
        };
    });

    var total = lanche.valorNum + _somaAdicionais(lanche.adicionais);

    return {
        "nome": lanche.resumoPao ? (lanche.nome + " ( " + lanche.resumoPao + " )") : lanche.nome,
        "valor": formatarMoeda(total),
        "observacao": "",
        "adicionais": adicionais
    };
}

// {tamanho: "500 ML", valorNum, adicionais: [{nome, valorNum, quantidade}]}
//
// Único caso em que o adicional tem quantidade: ela vira N linhas iguais na
// comanda (é assim que o cupom mostra "2x granola"), e o valor conta N vezes.
function montarAcai(copo) {
    var adicionais = [];
    var soma = 0;
    var lista = copo.adicionais || [];

    for (var i = 0; i < lista.length; i++) {
        var quantidade = lista[i].quantidade || 1;
        soma += lista[i].valorNum * quantidade;
        for (var q = 0; q < quantidade; q++) {
            adicionais.push({
                "sabor": "Açaí",
                "nome": lista[i].nome,
                "valor": formatarMoeda(lista[i].valorNum)
            });
        }
    }

    return {
        "nome": "Açaí (" + copo.tamanho + ")",
        "valor": formatarMoeda(copo.valorNum + soma),
        "observacao": "",
        "adicionais": adicionais
    };
}

// {nome, valorNum} — bebidas e "outros", que não têm borda nem adicional.
//
// Não emite as chaves "borda"/"adicionais" de propósito: é o formato que as
// telas de venda já recebem hoje dessas duas categorias, e elas resolvem a
// ausência com `|| null` / `|| []`. Emitir vazio mudaria o objeto sem mudar o
// resultado, e esconderia a diferença real entre as categorias.
function montarSimples(item) {
    return {
        "nome": item.nome,
        "valor": formatarMoeda(item.valorNum),
        "observacao": ""
    };
}
