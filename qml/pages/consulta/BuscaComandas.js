.pragma library
.import "../../components/Texto.js" as Texto

// Busca da barra de pesquisa da Consulta, por busca binária sobre um índice
// ordenado — mesma ideia de services/buscaCardapio.py, aplicada às comandas.
//
// O QUE MUDOU. Antes, cada tecla digitada percorria TODAS as comandas
// chamando Texto.normalizar() no título, no código e no CUPOM INTEIRO de
// cada uma, e só então ordenava pelo resultado. Normalizar é caro: é um laço
// caractere a caractere montando string nova (ver Texto.js), e o cupom tem
// alguns milhares de caracteres. Com algumas centenas de comandas isso é
// ordem de milhão de iterações por tecla — o motivo pelo qual a barra
// precisou de um debounce de 200 ms pra ficar utilizável nas máquinas fracas
// da pizzaria (ver ColunaEsquerda.qml).
//
// Agora o texto normalizado é calculado UMA vez por comanda, quando o índice
// é montado, e as teclas seguintes só comparam strings prontas.
//
// SOBRE A BUSCA BINÁRIA, e sobre o que ela não resolve. Ela responde
// exatamente uma pergunta: "quais chaves começam com este prefixo?" — dois
// limites inferiores sobre a lista ordenada dão o intervalo inteiro em
// O(log n). É o caminho de quem digita "mar" esperando Marcos, e de quem
// digita "A2912" esperando aquela comanda: o começo do nome do cliente e o
// começo do código são as duas formas como se procura uma comanda na prática.
//
// O que ela NÃO responde, por construção: "quais comandas CONTÊM este
// pedaço" — achar "Marcos" por "cos", ou achar um telefone no meio do cupom.
// Nenhuma ordenação de chaves ajuda aí, e essa busca por conteúdo é o que a
// própria barra promete ("Pesquisar por cliente ou conteúdo..."). Daí as
// faixas de relevância: prefixo pela binária, o resto por varredura — só que
// agora a varredura é um indexOf sobre string já normalizada, não uma
// normalização inteira.
//
// E POR QUE A VARREDURA NÃO SOME. Dentro do que lhe é dado, a busca desta
// tela REORDENA, nunca esconde (é uma decisão explícita, documentada em
// Consulta.qml:aplicarFiltro): o resultado é sempre a lista inteira que
// entrou, reordenada. Uma saída de n itens custa no mínimo O(n) pra ser
// montada, então nenhuma estrutura de busca deixaria esta função sublinear no
// que recebe. O que a binária economiza é o trabalho POR ITEM na faixa que
// mais importa, e o que o índice economiza é a normalização repetida — que
// era o custo real.
//
// QUEM SEGURA O n, ENTÃO. Não é este arquivo: é quem monta o índice. Como o
// O(n) da varredura e o O(n log n) do índice são pisos, a única forma de a
// pesquisa não piorar pra sempre conforme a pizzaria acumula anos de pedidos
// é o n não ser o acervo inteiro. Consulta.qml só entrega aqui as comandas
// dos últimos dias (ver janelaBuscaDias/_prepararIndiceBusca lá), então
// `comandas` abaixo é o movimento de uma semana, e não o histórico — o custo
// de pesquisar passa a depender de quanto a pizzaria vende por semana, que é
// estável, em vez de há quanto tempo ela existe, que não é.
//
// Este módulo não sabe nada de datas de propósito: ele ordena o que recebe.
// Quem recorta a janela é a tela, que é quem tem como avisar o usuário — e o
// aviso existe (ver ColunaEsquerda.qml).

// Faixas de relevância, da melhor para a pior. A ordem dos valores é a ordem
// em que as comandas aparecem na lista.
var PREFIXO = 0; // nome ou código COMEÇAM com o termo (achado pela binária)
var NOME = 1; // termo no meio do nome do cliente
var CODIGO = 2; // termo no meio do código
var CONTEUDO = 3; // termo no corpo do cupom
var SEM_MATCH = 4; // não casou — continua na lista, no fim, na ordem de sempre

var _TOTAL_FAIXAS = 5;

// ---------- Índice ----------

// Monta o índice de `comandas`. `titulo` é a função que compõe o nome
// exibido (Consulta.qml:tituloComanda) — fica lá porque os delegates da
// lista também a usam pra desenhar a linha.
//
// Custa O(n log n) e roda UMA vez por carregamento da lista, não por tecla.
// Quem chama monta preguiçosamente, na primeira busca (ver
// Consulta.qml:_prepararIndiceBusca): quem só abre a Consulta pra olhar as
// comandas do dia nunca paga por isto.
//
// `comandas` é a janela pesquisável, não o acervo — o laço abaixo normaliza o
// cupom inteiro de cada item que recebe, e é por isso que a janela é recortada
// ANTES desta chamada, e não filtrada depois.
function construirIndice(comandas, titulo) {
    var entradas = new Array(comandas.length);

    for (var i = 0; i < comandas.length; i++) {
        var item = comandas[i];
        entradas[i] = {
            "pos": i,
            "nome": Texto.normalizar(titulo(item)),
            "codigo": Texto.normalizar(item.codigo || ""),
            "conteudo": Texto.normalizar(item.conteudo || "")
        };
    }

    return {
        "entradas": entradas,
        // Duas cópias da MESMA lista de entradas, cada uma ordenada por uma
        // chave. São arrays de referências, não de cópias das comandas: o
        // custo extra é um ponteiro por comanda.
        "porNome": _ordenadoPor(entradas, "nome"),
        "porCodigo": _ordenadoPor(entradas, "codigo")
    };
}

function _ordenadoPor(entradas, campo) {
    // Comparador explícito, e não o sort() padrão: a ordem que sai daqui tem
    // que ser exatamente a mesma que _limiteInferior() assume ao comparar com
    // "<" abaixo. O padrão do JavaScript por acaso coincide (ordena por
    // unidade de código UTF-16), mas depender de coincidência num invariante
    // de busca binária é como a estrutura silenciosamente para de achar item.
    return entradas.slice().sort(function (a, b) {
        if (a[campo] < b[campo])
            return -1;
        if (a[campo] > b[campo])
            return 1;
        return 0;
    });
}

// ---------- Busca binária ----------

// Menor posição de `ordenado` cuja chave é >= `alvo` (o lower_bound clássico).
// Se nenhuma for, devolve o tamanho da lista.
function _limiteInferior(ordenado, campo, alvo) {
    var inicio = 0;
    var fim = ordenado.length;

    while (inicio < fim) {
        // >> 1 em vez de Math.floor(/2): é divisão inteira por 2 e evita o
        // arredondamento de ponto flutuante. Só valeria até 2^31 posições —
        // uma pizzaria não chega perto de dois bilhões de comandas.
        var meio = (inicio + fim) >> 1;
        if (ordenado[meio][campo] < alvo)
            inicio = meio + 1;
        else
            fim = meio;
    }

    return inicio;
}

// [inicio, fim) das entradas cuja chave começa com `prefixo`.
//
// O truque do limite superior: toda chave que começa com o prefixo é menor
// que o prefixo com o último caractere incrementado ("mar" -> "mas"), então
// um segundo limite inferior acha o fim da faixa sem varrer nada. Duas
// binárias, O(log n), e não uma binária seguida de caminhada — com muitos
// homônimos ("Maria", "Mariana", "Mario"...) caminhar seria O(k) sobre uma
// faixa que pode ser grande.
function _faixaPorPrefixo(ordenado, campo, prefixo) {
    if (prefixo === "")
        return [0, ordenado.length];

    var ultimo = prefixo.charCodeAt(prefixo.length - 1);
    var limite = prefixo.slice(0, prefixo.length - 1) + String.fromCharCode(ultimo + 1);

    return [_limiteInferior(ordenado, campo, prefixo), _limiteInferior(ordenado, campo, limite)];
}

// ---------- Ordenação por relevância ----------

// Devolve as comandas reordenadas pela proximidade com `termo`, sem esconder
// nenhuma. `aceita(item)` é o filtro de status da tela — o único que de fato
// tira comanda da lista.
//
// `comandas` tem que ser EXATAMENTE o array passado a construirIndice: as
// posições guardadas no índice são posições nele. Na Consulta isso é
// _comandasBuscaveis (a janela), não _todasComandas.
//
// O índice cobre todas as comandas da janela, inclusive as que o filtro de
// status esconde: reconstruí-lo a cada troca de "Todas/Abertas/Fechadas"
// custaria a normalização inteira de novo, e descartar no fim custa uma
// comparação.
function ordenar(indice, comandas, termo, aceita) {
    var alvo = Texto.normalizar(termo);
    var i;

    if (alvo === "") {
        var todas = [];
        for (i = 0; i < comandas.length; i++)
            if (aceita(comandas[i]))
                todas.push(comandas[i]);
        return todas;
    }

    var total = comandas.length;
    var faixa = new Array(total);
    // Onde o termo aparece dentro do campo que casou. Ordena dentro da faixa:
    // casar no começo da palavra vale mais que casar no meio.
    var distancia = new Array(total);
    for (i = 0; i < total; i++) {
        faixa[i] = SEM_MATCH;
        distancia[i] = 0;
    }

    // --- Faixa do prefixo: as duas binárias, o caminho comum ---
    // Código primeiro: é o campo mais específico que existe (quem digita
    // "A291201" quer exatamente aquela comanda), então ele marca antes e o
    // nome não sobrescreve.
    _marcarPrefixo(indice.porCodigo, "codigo", alvo, faixa);
    _marcarPrefixo(indice.porNome, "nome", alvo, faixa);

    // --- Faixas restantes: varredura sobre o texto já normalizado ---
    // Posição 0 já foi coberta pela binária acima, daí o "> 0": um indexOf
    // que devolve 0 aqui é uma comanda que a faixa do prefixo pegou.
    for (i = 0; i < total; i++) {
        if (faixa[i] === PREFIXO)
            continue;

        var entrada = indice.entradas[i];
        var posicao = entrada.nome.indexOf(alvo);
        if (posicao > 0) {
            faixa[i] = NOME;
            distancia[i] = posicao;
            continue;
        }

        posicao = entrada.codigo.indexOf(alvo);
        if (posicao > 0) {
            faixa[i] = CODIGO;
            distancia[i] = posicao;
            continue;
        }

        posicao = entrada.conteudo.indexOf(alvo);
        if (posicao !== -1) {
            faixa[i] = CONTEUDO;
            distancia[i] = posicao;
        }
    }

    return _achatar(faixa, distancia, comandas, aceita);
}

// Comanda sem código (arquivo antigo) tem chave "" e nunca entra numa faixa:
// "" é menor que qualquer alvo não vazio, então o limite inferior já a deixa
// de fora — e ordenar() devolve antes de chegar aqui quando o alvo é vazio.
function _marcarPrefixo(ordenado, campo, alvo, faixa) {
    var limites = _faixaPorPrefixo(ordenado, campo, alvo);

    for (var i = limites[0]; i < limites[1]; i++)
        faixa[ordenado[i].pos] = PREFIXO;
}

// Junta as faixas na ordem, aplicando o filtro de status. Dentro de cada
// faixa: as do meio do texto saem por distância (casar mais cedo vale mais),
// e o empate — que é o caso COMUM, não a exceção: pesquisar "291" acha o
// mesmo pedaço na mesma posição do código de todas as comandas — cai na
// ordem da lista bruta, mais recente primeiro.
//
// O desempate por `a - b` é explícito de propósito. O sort() do motor de
// JavaScript do Qt NÃO é estável (verificado neste projeto: com todas as
// pontuações iguais, ele devolvia a lista embaralhada), então a versão
// anterior desta busca, que ordenava tudo por uma pontuação só, deixava a
// ordem entre comandas empatadas por conta do algoritmo de ordenação — e
// empate é o caso comum. Na prática isso embaralhava as comandas do dia
// assim que alguém pesquisava qualquer coisa que não separasse todo mundo.
function _achatar(faixa, distancia, comandas, aceita) {
    var baldes = [];
    var f;
    for (f = 0; f < _TOTAL_FAIXAS; f++)
        baldes.push([]);

    for (var i = 0; i < comandas.length; i++)
        if (aceita(comandas[i]))
            baldes[faixa[i]].push(i);

    for (f = NOME; f <= CONTEUDO; f++)
        baldes[f].sort(function (a, b) {
            return distancia[a] - distancia[b] || a - b;
        });

    var resultado = [];
    for (f = 0; f < _TOTAL_FAIXAS; f++)
        for (var k = 0; k < baldes[f].length; k++)
            resultado.push(comandas[baldes[f][k]]);

    return resultado;
}
