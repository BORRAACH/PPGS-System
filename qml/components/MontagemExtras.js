.pragma library

// Manipulação da borda e dos adicionais de um item que já está na comanda —
// usada por components/PopupExtrasItem.qml.
//
// Separada do popup pelo mesmo motivo de MontagemItem.js: o que sai daqui é
// CONTRATO COM O PYTHON, não estado de tela. O objeto do adicional
// ({sabor, nome, valor}) é lido por comandaTextoService._extras_adicionais na
// hora de imprimir e reconstruído por comandaParserService.reconstruir_itens
// ao reabrir a comanda; montá-lo diferente aqui não dá erro na hora, dá
// adicional que some do cupom.
//
// Sendo funções puras sobre objetos JS, também dá para exercitá-las sem UI.

// "R$ 12,50" ou "12,50" -> 12.5. Devolve 0 no que não der para ler, pelo mesmo
// motivo de MontagemItem.parseValor: um preço ilegível vira R$ 0,00 visível na
// linha, e não um total inteiro contaminado por NaN.
function valorNum(texto) {
    if (typeof texto === "number")
        return texto;

    var limpo = String(texto || "").replace("R$", "").trim().replace(",", ".");
    var numero = parseFloat(limpo);
    return isNaN(numero) ? 0 : numero;
}

function formatarMoeda(valorNumero) {
    return "R$ " + valorNumero.toFixed(2).replace(".", ",");
}

// O preço de uma entrada do cardápio (ver services/buscaCardapio.py): bordas e
// adicionais têm um preço só, então é sempre o primeiro da lista. As categorias
// com vários preços (pizza por tamanho, lanche por pão) não passam por aqui —
// nenhuma delas é borda nem adicional.
function precoDe(entrada) {
    var precos = (entrada && entrada.precos) || [];
    return precos.length > 0 ? precos[0].valor : "";
}

// O item escolhido no cardápio, carimbado com o destino dentro do pedido.
//
// `sabor` VAZIO é o adicional que vale para o item inteiro (ver
// comandaTextoService.SUFIXO_ADICIONAL_INTEIRA); com nome de sabor, vale só
// para aquela parte.
function comSabor(item, sabor) {
    return {
        "nome": item.nome,
        "valor": item.valor,
        "sabor": sabor
    };
}

// A lista de adicionais com `item` acrescentado `quantidade` vezes.
//
// Repetido em vez de guardar um campo de quantidade porque é assim que o cupom
// mostra "2x granola": uma linha por unidade (ver MontagemItem.montarAcai, que
// já expande a quantidade do mesmo jeito). Um campo novo aqui teria de ser
// entendido também pela impressão e pela leitura de volta, para dizer o que a
// repetição já diz.
//
// Devolve uma lista NOVA, sem mexer na recebida: quem chama guarda a lista numa
// property de QML, e mutar no lugar não emite sinal nenhum — a tela ficaria
// mostrando o estado anterior.
function comAdicional(adicionais, item, quantidade) {
    var lista = (adicionais || []).slice();
    var vezes = Math.max(1, quantidade || 1);

    for (var i = 0; i < vezes; i++) {
        lista.push({
            "sabor": item.sabor || "",
            "nome": item.nome,
            "valor": item.valor
        });
    }
    return lista;
}

// O valor da linha depois de somar `delta`, no formato do cupom. Nunca desce de
// zero: um total negativo no papel seria mais confuso do que o engano que o
// causou, e o caminho até aqui é sempre "tirar o que foi posto", que fecha em
// zero no pior caso.
function valorAjustado(valorAtual, delta) {
    return formatarMoeda(Math.max(0, valorNum(valorAtual) + delta));
}

// ---------- A ponte com a linha da comanda ----------
//
// "borda" e "adicionais" são STRING JSON no modelo, e não objeto/array (ver o
// ListElement de Balcao.qml/Entrega.qml/Salao.qml): um array atribuído a um
// role vira um model aninhado, que chega no Python como QAbstractListModel em
// vez de lista. Estas duas funções são o único lugar que precisa saber disso —
// as três telas chamam daqui e não repetem o JSON.stringify de cada lado.

function _comoObjeto(texto, padrao) {
    if (!texto)
        return padrao;
    if (typeof texto !== "string")
        return texto;

    try {
        var lido = JSON.parse(texto);
        return lido === null ? padrao : lido;
    } catch (e) {
        // Linha com JSON corrompido (editado à mão, versão futura): segue com
        // o padrão em vez de derrubar a tela. O pior caso é o popup abrir
        // vazio, e não o atendente perder a comanda inteira.
        console.warn("[extras] Não foi possível ler o campo da linha:", e);
        return padrao;
    }
}

function bordaDaLinha(modelo, indice) {
    var linha = modelo.get(indice);
    return linha ? _comoObjeto(linha.borda, null) : null;
}

function adicionaisDaLinha(modelo, indice) {
    var linha = modelo.get(indice);
    return linha ? _comoObjeto(linha.adicionais, []) : [];
}

// Grava o estado novo na linha e corrige o valor dela em `delta`.
//
// O valor da linha é o TOTAL do item (base + borda + adicionais, ver
// MontagemItem.montarPizza), e é dele que saem tanto o total da tela quanto o
// que vai impresso. Por isso o delta: o preço base não está guardado em lugar
// nenhum depois que o item foi montado, então só dá para somar e subtrair o
// que muda — que é exatamente o que uma atribuição ou remoção faz.
function gravarNaLinha(modelo, indice, borda, adicionais, delta) {
    if (indice < 0 || indice >= modelo.count)
        return;

    modelo.setProperty(indice, "borda", JSON.stringify(borda || null));
    modelo.setProperty(indice, "adicionais", JSON.stringify(adicionais || []));
    if (delta !== 0)
        modelo.setProperty(indice, "valor", valorAjustado(modelo.get(indice).valor, delta));
}
