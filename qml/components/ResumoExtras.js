.pragma library

// Formatação da borda e dos adicionais na hora de MOSTRAR um item já montado:
// as linhas "+ Bacon (R$ 5,00)" e "* Borda Catupiry (R$ 8,00)" que aparecem
// recuadas sob o item nos painéis de resumo do pedido.
//
// POR QUE ISTO SAIU DE DENTRO DE ResumoComanda.qml, que era o dono delas: ele
// não é o único painel de resumo. A tela de Salão tem o seu próprio ("RESUMO
// DA MESA", em pages/salao/Salao.qml), montado à parte porque não exibe forma
// de pagamento nem status — no Salão isso é por pessoa, só na hora de fechar a
// conta. Presas dentro do componente, estas funções não tinham como ser
// chamadas de lá, e o resumo da mesa listava o item sem os extras: um total
// que não batia com o que estava escrito na tela.
//
// O FORMATO É O DO CUPOM, de propósito — mesmos prefixos e mesmo separador de
// sabores de services/comandaTextoService.py (PREFIXO_ADICIONAL, PREFIXO_BORDA,
// SEPARADOR_SABORES). O resumo na tela existe pra conferir o que vai sair no
// papel; escrito de outro jeito, ele deixaria de servir pra isso.
//
// Sendo funções puras sobre objetos JS, dão pra exercitar sem UI — mesmo
// espírito de MontagemExtras.js, que cuida do outro lado (montar e gravar os
// extras na linha do pedido).

// Separador de pizzas meio a meio. Tem espaço dos dois lados de propósito, o
// que o distingue de nomes como "Atum c/ Cebola".
var SEPARADOR_SABORES = " / ";

// "borda" e "adicionais" chegam como STRING JSON quando a origem é o ListModel
// de Balcao.qml/Entrega.qml/Salao.qml (um array atribuído a um role vira um
// list-model aninhado, por isso a convenção — ver o comentário longo em
// Balcao.qml), mas como objeto/array de verdade quando vêm direto de um
// QVariantMap do Python. Aceitar os dois evita obrigar cada chamador a
// converter antes.
function comoObjeto(valor, padrao) {
    if (valor === undefined || valor === null || valor === "")
        return padrao;

    if (typeof valor !== "string")
        return valor;

    try {
        var lido = JSON.parse(valor);
        return lido === null || lido === undefined ? padrao : lido;
    } catch (erro) {
        return padrao;
    }
}

// Prefixo "+" igual ao do cupom (PREFIXO_ADICIONAL).
function textoAdicional(adicional) {
    var valor = adicional.valor || "";
    return "+ " + (adicional.nome || "") + (valor ? " (" + valor + ")" : "");
}

// Os sabores de um item, e o tamanho entre parênteses no fim quando houver.
// Mesma leitura que comandaTextoService.dividir_sabores faz do outro lado.
function saboresDe(pedido) {
    var corpo = pedido;
    var tamanho = "";

    var casou = /^(.*)\s\(([^)]+)\)$/.exec(pedido);
    if (casou) {
        corpo = casou[1];
        tamanho = casou[2];
    }

    return {
        "sabores": corpo.split(SEPARADOR_SABORES).filter(function (s) {
            return s.trim() !== "";
        }),
        "tamanho": tamanho
    };
}

// Adicionais atribuídos a um sabor específico, já formatados. Mesma comparação
// sem diferenciar caixa de comandaTextoService._extras_adicionais: o nome do
// sabor pode vir em caixa alta (reconstruído de uma comanda já impressa)
// enquanto o adicional guardou o nome como veio de Pizzas.qml.
function extrasDoSabor(adicionais, sabor) {
    var alvo = (sabor || "").trim().toUpperCase();
    var extras = [];
    for (var i = 0; i < adicionais.length; i++) {
        var adicional = adicionais[i];
        if (!adicional || (adicional.sabor || "").trim().toUpperCase() !== alvo)
            continue;

        extras.push(textoAdicional(adicional));
    }
    return extras;
}

// Todos os adicionais do item numa lista só, sem separar por fração — é o que
// o modo compacto mostra, já que ali o item ocupa uma linha só e não há fração
// a que pendurar cada um. Numa pizza dividida o sabor vai junto, senão
// "+ Bacon" não diria em qual metade ele entra.
function extrasDoItem(pedido, adicionaisBrutos) {
    var adicionais = comoObjeto(adicionaisBrutos, []);
    var varios = saboresDe(pedido).sabores.length > 1;
    var extras = [];

    for (var i = 0; i < adicionais.length; i++) {
        var adicional = adicionais[i];
        if (!adicional)
            continue;

        var texto = textoAdicional(adicional);
        var sabor = (adicional.sabor || "").trim();
        extras.push(varios && sabor ? texto + " — " + sabor : texto);
    }
    return extras;
}

// Desmonta um item nas linhas que ele ocupa, do mesmo jeito que
// comandaTextoService.montar_grupos monta pro papel: uma pizza meio a meio (ou
// em mais partes) vira uma linha "1/N - Sabor" por sabor, com o tamanho junto
// só na primeira, e cada adicional aparece logo abaixo da fração a que
// pertence. Item comum vira uma linha só.
function linhasDoItem(pedido, adicionaisBrutos) {
    var adicionais = comoObjeto(adicionaisBrutos, []);
    var partes = saboresDe(pedido);
    var sabores = partes.sabores;
    var tamanho = partes.tamanho;

    if (sabores.length <= 1)
        return [{
            "texto": pedido,
            "extras": extrasDoSabor(adicionais, sabores.length ? sabores[0] : pedido)
        }];

    var linhas = [];
    for (var i = 0; i < sabores.length; i++) {
        var nome = i === 0 && tamanho ? sabores[i] + " (" + tamanho + ")" : sabores[i];
        // "1/N" em todas, não "1/N, 2/N, ...": é a fração da pizza que aquele
        // sabor ocupa, não a posição dele na lista — mesma leitura do cupom
        // (comandaTextoService.montar_grupos).
        linhas.push({
            "texto": "1/" + sabores.length + " - " + nome,
            "extras": extrasDoSabor(adicionais, sabores[i])
        });
    }
    return linhas;
}

// Borda da pizza (nível do item inteiro, não de um sabor) — "" quando não
// houver. Prefixo "*" igual ao do cupom (PREFIXO_BORDA).
function linhaBorda(bordaBruta) {
    var borda = comoObjeto(bordaBruta, null);
    if (!borda || !borda.nome)
        return "";

    return "* " + borda.nome + (borda.valor ? " (" + borda.valor + ")" : "");
}
