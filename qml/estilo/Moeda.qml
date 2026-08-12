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

    // "R$ 45,00" / "45,00" / "45.00" / "45" -> 45.0
    // Vazio, lixo ou incompleto (só "," por exemplo) -> 0.
    function paraNumero(texto) {
        if (!texto)
            return 0;

        var numero = parseFloat(String(texto).replace("R$", "").replace(/\s/g, "").replace(",", "."));
        return isNaN(numero) ? 0 : numero;
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
