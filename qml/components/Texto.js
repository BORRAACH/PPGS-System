.pragma library

// Normaliza texto para comparacao de busca: minusculas e sem acentos, para
// que letras acentuadas (a-agudo, a-til, a-circunflexo, c-cedilha etc.)
// sejam tratadas como a mesma letra base. NFD separa a letra base do sinal
// diacritico (um "combining mark" a parte); o laco abaixo descarta esses
// combining marks comparando o codigo de cada caractere com o intervalo
// Unicode deles (0x0300 a 0x036F), sem depender de escapes de regex.
function normalizar(texto) {
    var base = (texto || "").normalize("NFD");
    var resultado = "";
    for (var i = 0; i < base.length; i++) {
        var codigo = base.charCodeAt(i);
        if (codigo < 0x0300 || codigo > 0x036f)
            resultado += base[i];
    }
    return resultado.toLowerCase();
}


// Capitaliza a primeira letra da string e toda letra que venha logo depois de
// um espaco: "maria alice" vira "Maria Alice". Usado nos campos de nome de
// cliente de Balcao, Entrega e Salao.
//
// So LEVANTA letras, nunca abaixa: "maria ALICE" vira "Maria ALICE", e quem
// digitou tudo em maiuscula continua com tudo em maiuscula. A regra pedida foi
// "deixar maiuscula a primeira letra", e abaixar o resto por conta propria
// destruiria o que a pessoa escreveu de proposito.
//
// A regra e literalmente "depois de um espaco", entao "maria de souza" vira
// "Maria De Souza" — as particulas (de, da, dos) tambem sobem. Fica assim de
// caso pensado: uma lista de excecoes erraria em sobrenome que comeca com elas
// e em apelido do balcao, e o atendente sempre pode abaixar a letra na mao.
//
// Dois espacos seguidos continuam sendo dois espacos, e o texto NUNCA muda de
// tamanho — e disso que capitalizarCampo depende para devolver o cursor ao
// lugar certo.
function capitalizarNomes(texto) {
    var origem = texto || "";
    var resultado = "";
    var comecoDePalavra = true;

    for (var i = 0; i < origem.length; i++) {
        var caractere = origem[i];
        resultado += comecoDePalavra ? _maiusculaSegura(caractere) : caractere;
        comecoDePalavra = (caractere === " ");
    }

    return resultado;
}

// A maiuscula de um caractere, mas so quando ela ocupa o mesmo espaco que ele.
// Existe por causa das letras que crescem ao subir — o "s-tzet" alemao vira
// "SS", ligaduras viram duas letras — e que fariam a string mudar de tamanho,
// levando o cursor de capitalizarCampo para o lugar errado. Nenhuma delas
// aparece num nome brasileiro; a guarda esta aqui para o dia em que aparecer,
// e o custo dela e o caractere sair como foi digitado.
function _maiusculaSegura(caractere) {
    var maiuscula = caractere.toUpperCase();
    return maiuscula.length === caractere.length ? maiuscula : caractere;
}

// Aplica capitalizarNomes a um TextField, preservando a posicao do cursor.
//
// Sem devolver o cursor, escrever "maria alice" seria impossivel: cada
// atribuicao a "text" joga o cursor para o fim, entao corrigir uma letra no
// meio do nome mandaria a proxima tecla para o final da linha. Como
// capitalizarNomes nunca muda o tamanho do texto, a posicao guardada continua
// valendo depois da troca.
//
// Sai cedo quando nada muda, e e isso que impede o laco: atribuir "text"
// dispara onTextChanged de novo, e na segunda passada o texto ja esta
// capitalizado.
//
// ATENCAO ao usar isto em delegate cujo texto vem do model ("text:
// model.algo"): atribuir "text" quebra esse binding, e o campo passa a ser uma
// segunda fonte do mesmo dado — o que a comanda imprime sai do model, nao do
// campo. O binding sobrevive a digitacao (escrever no model continua
// atualizando o campo), entao nesses casos capitalize escrevendo no MODEL e
// devolva o cursor na mao. Ver campoObservacao em components/LinhaPedido.qml e
// campoNomeDivisao em qml/pages/salao/PopupFecharConta.qml.
//
// O que NAO acontece, para nao ser reinvestigado depois: um delegate nao passa
// a mostrar o texto da linha vizinha quando alguem apaga um item do meio da
// lista. Tanto Repeater quanto ListView mantem o delegate colado ao ITEM, nao
// a posicao — o indice muda, o delegate acompanha.
function capitalizarCampo(campo) {
    if (!campo)
        return;

    var formatado = capitalizarNomes(campo.text);
    if (formatado === campo.text)
        return;

    var cursor = campo.cursorPosition;
    campo.text = formatado;
    campo.cursorPosition = cursor;
}


// Levanta SO a primeira letra da string: "sem cebola" vira "Sem cebola". Usado
// nos campos de observacao — a de cada item (components/LinhaPedido.qml) e a
// geral do pedido (Entrega.qml).
//
// Regra diferente da de capitalizarNomes de proposito: observacao e frase, nao
// nome. "sem cebola e sem azeitona" precisa virar "Sem cebola e sem azeitona",
// nunca "Sem Cebola E Sem Azeitona" — capitalizar cada palavra de uma frase
// deixa o cupom mais dificil de ler justamente na linha que a cozinha precisa
// ler rapido.
//
// A "primeira letra" e o primeiro caractere que nao e espaco: quem comeca a
// digitar com a barra de espaco encostada continua tendo a frase capitalizada,
// em vez de nada acontecer porque a posicao zero era um espaco.
//
// Como capitalizarNomes, so levanta e nunca abaixa, e nunca muda o tamanho da
// string — e disso que a devolucao do cursor depende.
function capitalizarFrase(texto) {
    var origem = texto || "";

    for (var i = 0; i < origem.length; i++) {
        if (origem[i] === " ")
            continue;
        return origem.slice(0, i) + _maiusculaSegura(origem[i]) + origem.slice(i + 1);
    }

    return origem;
}

// capitalizarFrase aplicada a um TextField, preservando o cursor — mesma
// mecanica (e mesmas ressalvas sobre delegate) de capitalizarCampo.
function capitalizarCampoFrase(campo) {
    if (!campo)
        return;

    var formatado = capitalizarFrase(campo.text);
    if (formatado === campo.text)
        return;

    var cursor = campo.cursorPosition;
    campo.text = formatado;
    campo.cursorPosition = cursor;
}
