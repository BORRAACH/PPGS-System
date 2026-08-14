.pragma library

// Para onde vai um item recém-montado, e como ele entra no modeloPedidos da
// tela de venda. Usado pelo lançamento rápido do Ctrl+S (ver
// PopupLancamentoRapido.qml) e pelas próprias telas de venda.
//
// Existe porque o mesmo item tem DUAS formas neste app, e confundi-las não dá
// erro nenhum — dá linha em branco na comanda:
//
//   - o que as páginas de categoria devolvem: {nome, valor, observacao,
//     borda (objeto), adicionais (array)};
//   - o que as roles de modeloPedidos guardam: {pedido, observacao, valor,
//     borda (string JSON), adicionais (string JSON)}.
//
// A propriedade `itensIniciais` de Balcao/Entrega lê a SEGUNDA forma (nasceu
// para a Consulta reabrir uma comanda salva, onde a chave já é "pedido"), por
// isso paraItensIniciais() existe.

// Rótulo do tipo de pedido a partir do objectName da Page. "" quando a tela
// atual não é de venda (Início, Consulta, Fechamento, Configurações...).
//
// Lista branca, não negra: uma tela nova qualquer nasce como "não é de venda",
// que é o palpite seguro — o pior que acontece é o lançamento rápido navegar
// quando poderia ter acrescentado.
function tipoDaTela(objectName) {
    if (objectName === "telaBalcao")
        return "Balcão";
    if (objectName === "telaEntrega")
        return "Entrega";
    if (objectName === "telaSalao")
        return "Salão";
    return "";
}

// Caminho da página de cada tipo, relativo à raiz do projeto (ver a context
// property `raizProjeto`, definida em main.py).
function paginaDoTipo(tipo) {
    if (tipo === "Balcão")
        return "qml/pages/balcao/Balcao.qml";
    if (tipo === "Entrega")
        return "qml/pages/entrega/Entrega.qml";
    if (tipo === "Salão")
        return "qml/pages/salao/Salao.qml";
    return "";
}

function _comoLinha(item) {
    return {
        "pedido": item.nome,
        "observacao": item.observacao || "",
        "valor": item.valor,
        // String, nunca objeto/array: um array atribuído a um role de
        // ListModel vira um list-model aninhado (não um JS array de verdade),
        // e isso quebra tanto a leitura em coletarDadosPedido() quanto o envio
        // pro Python.
        "borda": JSON.stringify(item.borda || null),
        "adicionais": JSON.stringify(item.adicionais || [])
    };
}

// Acrescenta `itens` ao fim do pedido, reaproveitando a primeira linha ainda
// em branco. É o caminho do lançamento rápido: diferente de inserirEmModelo(),
// aqui não existe "a linha que abriu a seleção" — o atendente nem estava
// mexendo na lista.
//
// Devolve o índice da última linha escrita, para quem quiser rolar até ela.
function acrescentarAoModelo(modeloPedidos, itens) {
    if (!itens || itens.length === 0)
        return -1;

    var indice = -1;
    for (var i = 0; i < modeloPedidos.count; i++) {
        if (modeloPedidos.get(i).pedido === "") {
            indice = i;
            break;
        }
    }

    var ultimo = -1;
    for (var j = 0; j < itens.length; j++) {
        var linha = _comoLinha(itens[j]);
        if (indice >= 0) {
            // setProperty role a role: setProperty com um objeto inteiro não
            // cria role que não exista, e aqui todas já existem.
            modeloPedidos.setProperty(indice, "pedido", linha.pedido);
            modeloPedidos.setProperty(indice, "observacao", linha.observacao);
            modeloPedidos.setProperty(indice, "valor", linha.valor);
            modeloPedidos.setProperty(indice, "borda", linha.borda);
            modeloPedidos.setProperty(indice, "adicionais", linha.adicionais);
            ultimo = indice;
            indice = -1;
        } else {
            modeloPedidos.append(linha);
            ultimo = modeloPedidos.count - 1;
        }
    }
    return ultimo;
}

// Escreve `itens` a partir de `indice`, reaproveitando essa linha e inserindo
// as demais logo abaixo dela. É o caminho do popup de seleção das telas de
// venda, onde a posição da linha que abriu a seleção precisa ser preservada.
function inserirEmModelo(modeloPedidos, indice, itens) {
    if (indice < 0 || !itens || itens.length === 0)
        return;

    var primeira = _comoLinha(itens[0]);
    modeloPedidos.setProperty(indice, "pedido", primeira.pedido);
    modeloPedidos.setProperty(indice, "observacao", primeira.observacao);
    modeloPedidos.setProperty(indice, "valor", primeira.valor);
    modeloPedidos.setProperty(indice, "borda", primeira.borda);
    modeloPedidos.setProperty(indice, "adicionais", primeira.adicionais);

    for (var i = 1; i < itens.length; i++)
        modeloPedidos.insert(indice + i, _comoLinha(itens[i]));
}

// Há alguma linha com pedido preenchido? É o que decide se sair da tela
// descarta trabalho do atendente.
function temPedidoEmAndamento(modeloPedidos) {
    for (var i = 0; i < modeloPedidos.count; i++) {
        if (modeloPedidos.get(i).pedido !== "")
            return true;
    }
    return false;
}

// {nome, ...} -> {pedido, ...}, para a propriedade `itensIniciais` das telas
// de venda. Borda e adicionais vão CRUS (objeto/array): quem faz o
// JSON.stringify é o Component.onCompleted de cada tela.
function paraItensIniciais(itens) {
    return (itens || []).map(function (item) {
        return {
            "pedido": item.nome,
            "observacao": item.observacao || "",
            "valor": item.valor,
            "borda": item.borda || null,
            "adicionais": item.adicionais || []
        };
    });
}
