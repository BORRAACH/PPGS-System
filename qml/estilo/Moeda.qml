pragma Singleton

import QtQuick

// O formato de dinheiro do app num lugar só. Import: "import estilo 1.0"
// (o diretório qml/ já está no import path, configurado em main.py).
//
// Existe porque "R$ 45,00" é uma convenção compartilhada por muita gente que
// não se conhece: os campos de valor da linha de pedido, o troco e a taxa de
// entrega, os extras e as contagens do Fechamento, o troco por pessoa do
// Salão — e, do outro lado, services/comandaParserService.py, que lê esse
// mesmo texto de volta do cupom salvo. Cada campo tinha a sua cópia da
// limpeza e do toFixed(2), oito ao todo, e elas já tinham começado a
// divergir.
//
// O BUG QUE ISTO FECHA. Todos esses campos usavam um DoubleValidator, para o
// qual "R$ 45,00" é Invalid — o cifrão e o espaço não fazem parte de um
// número. E o Qt só emite `editingFinished` quando o conteúdo do campo é
// aceitável (acceptableInput). Como editingFinished era justamente onde a
// formatação e a gravação no modelo aconteciam, o efeito era: a digitação
// aparecia na tela, o campo mostrava o número novo, e o valor nunca saía
// dali. Na linha de pedido isso significava comanda impressa com o preço
// antigo, sem aviso nenhum. O validador daqui aceita o "R$ " que estes
// mesmos campos escrevem, e com isso o sinal volta a disparar.
QtObject {
    id: moeda

    // Uma instância só, compartilhada por todos os campos: QValidator não
    // guarda estado entre chamadas, então não há o que dar errado em dividir.
    //
    // O casamento parcial (Intermediate) é o que deixa digitar de letra em
    // letra; só o texto completo precisa bater com a expressão. Sem sinal
    // negativo e sem separador de milhar de propósito — é exatamente o que
    // formatar() produz e o que o parser do lado Python espera de volta.
    readonly property RegularExpressionValidator validador: RegularExpressionValidator {
        regularExpression: /^(R\$\s*)?\d*([.,]\d{0,2})?$/
    }

    // Igual ao de cima, mas deixa digitar o sinal de menos antes do número.
    // Separado de propósito: preço de item, troco e taxa de entrega são
    // valores que não existem negativos, e aceitar "-" ali só abriria porta
    // pra erro de digitação passar batido. Quem usa este é a contagem de
    // caixa do Fechamento, onde um valor negativo é uma correção legítima
    // (estorno de cartão, sangria já lançada em outro lugar) que precisa
    // entrar na conta puxando o total pra baixo.
    readonly property RegularExpressionValidator validadorComSinal: RegularExpressionValidator {
        regularExpression: /^(R\$\s*)?-?\d*([.,]\d{0,2})?$/
    }

    // "R$ 45,00" / "45,00" / "45.00" / "45" -> 45.0
    // Vazio, lixo ou incompleto (só "," por exemplo) -> 0.
    function paraNumero(texto) {
        if (!texto)
            return 0;

        var numero = parseFloat(String(texto).replace("R$", "").replace(/\s/g, "").replace(",", "."));
        return isNaN(numero) ? 0 : numero;
    }

    // O caminho de volta de formatar(): "R$ 45,00" -> "45", "R$ 45,98" ->
    // "45,98", "R$ -45,00" -> "-45". É o que se põe no campo quando ele ganha
    // o foco, pra quem clicou pra corrigir um valor encontrar o número puro em
    // vez de ter que desviar do "R$ " e dos centavos zerados antes de digitar.
    //
    // Os centavos só somem quando são ",00" — ",90" fica ",90" inteiro, senão
    // o campo diria "45,9" e a próxima tecla digitada valeria dez vezes mais
    // do que quem digitou quis.
    //
    // Campo vazio (ou entrada que não vira número) continua vazio, mesmo
    // critério de formatar().
    function paraEdicao(texto) {
        var limpo = String(texto || "").replace("R$", "").replace(/\s/g, "").replace(",", ".");
        if (limpo === "")
            return "";

        var numero = parseFloat(limpo);
        if (isNaN(numero))
            return "";

        return numero.toFixed(2).replace(".", ",").replace(/,00$/, "");
    }

    // O mesmo que formatar(), mas sem o "R$ ": "24,9" -> "24,90",
    // "24" -> "24,00", "" -> "".
    //
    // Existe por causa do CARDÁPIO, que é o único lugar do app onde o preço é
    // guardado sem o símbolo — os arquivos de data/cardapio/ trazem
    // `"valor": "13,00"`, e é esse texto que services/cardapioService.py lê de
    // volta (ver normalizar_preco). Escrever "R$ " ali faria o campo mostrar
    // uma coisa e o disco guardar outra.
    //
    // Campo vazio continua vazio, pelo mesmo motivo de formatar(): apagar o
    // preço é uma edição legítima, e escrever zero afirmaria algo que ninguém
    // pediu.
    function formatarSemSimbolo(texto) {
        var limpo = String(texto || "").replace("R$", "").replace(/\s/g, "").replace(",", ".");
        if (limpo === "")
            return "";

        var numero = parseFloat(limpo);
        return isNaN(numero) ? "" : numero.toFixed(2).replace(".", ",");
    }

    // O que o usuário digitou -> "R$ 45,00". Campo vazio (ou com entrada
    // incompleta demais para virar número) devolve "" em vez de "R$ 0,00":
    // apagar o preço é uma edição legítima — item de cortesia, valor a
    // combinar — e escrever zero ali afirmaria algo que ninguém pediu.
    function formatar(texto) {
        var limpo = String(texto || "").replace("R$", "").replace(/\s/g, "").replace(",", ".");
        if (limpo === "")
            return "";

        var numero = parseFloat(limpo);
        return isNaN(numero) ? "" : "R$ " + numero.toFixed(2).replace(".", ",");
    }
}
