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
