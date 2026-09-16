.pragma library

// Formatação dos números dos gráficos da página de Estatística
// (qml/pages/estatistica/Estatistica.qml). Fora dos componentes porque os
// quatro gráficos formatam do mesmo jeito — e porque o Canvas desenha o texto
// dos eixos com estas funções, não com Text.

// "R$ 1.234,50" — o padrão do projeto (ver comandaTextoService).
function moeda(valor) {
    var numero = Number(valor) || 0;
    var negativo = numero < 0;
    var partes = Math.abs(numero).toFixed(2).split(".");
    var inteiros = partes[0].replace(/\B(?=(\d{3})+(?!\d))/g, ".");
    return (negativo ? "-R$ " : "R$ ") + inteiros + "," + partes[1];
}

// "R$ 1,2 mil" para os rótulos dos eixos, onde o valor inteiro não cabe.
function moedaCurta(valor) {
    var numero = Number(valor) || 0;
    if (Math.abs(numero) >= 1000)
        return "R$ " + (numero / 1000).toFixed(1).replace(".", ",") + " mil";
    return "R$ " + numero.toFixed(0);
}

function numero(valor) {
    return String(Math.round(Number(valor) || 0));
}

// O formatador pedido pelo gráfico ("moeda" ou "numero"), na versão cheia ou
// na curta (eixos).
function formatar(valor, formato, curto) {
    if (formato === "moeda")
        return curto ? moedaCurta(valor) : moeda(valor);
    return numero(valor);
}

// "15/09" a partir de "2026-09-15" — o rótulo do eixo dos dias.
function diaCurto(dataIso) {
    var partes = String(dataIso || "").split("-");
    return partes.length === 3 ? partes[2] + "/" + partes[1] : String(dataIso || "");
}

// O teto do eixo: o primeiro valor "redondo" acima do maior dado, para as
// linhas de grade caírem em números legíveis (10, 25, 50, 100...).
function tetoDoEixo(maximo) {
    var valor = Number(maximo) || 0;
    if (valor <= 0)
        return 1;
    var magnitude = Math.pow(10, Math.floor(Math.log(valor) / Math.LN10));
    var passos = [1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 7.5, 10];
    for (var i = 0; i < passos.length; i++) {
        if (valor <= passos[i] * magnitude)
            return passos[i] * magnitude;
    }
    return 10 * magnitude;
}
