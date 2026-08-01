// Reabrir uma comanda já salva no formulário original (Balcão ou Entrega),
// já preenchida, para edição estruturada e reimpressão.
//
// Mora aqui, e não dentro de Consulta.qml, porque hoje dois lugares abrem a
// mesma edição: a lista da Consulta e o popup de fechamento rápido
// (qml/pages/fechamento/PopupFechamentoRapido.qml). São ~15 campos mapeados
// um a um para as propriedades iniciais de cada formulário — duplicar isso
// significaria que acrescentar um campo novo a Balcao.qml/Entrega.qml
// passaria a exigir lembrar de mexer em dois lugares, e o segundo ficaria
// para trás em silêncio (a comanda editada simplesmente perderia o campo).
//
// Não usa ".pragma library" de propósito, ao contrário de Texto.js: um
// arquivo de biblioteca roda num escopo isolado, sem acesso às context
// properties do main.py — e aqui é preciso chamar consultaController.
//
// Os caminhos dos formulários são absolutos (a partir de "raizProjeto", ver
// main.py) porque uma URL relativa seria resolvida contra o arquivo que
// importa este script, e ele é importado de pastas diferentes.
//
// "manterBaixa" só interessa a quem chama do Fechamento: editar apaga a
// comanda e grava outra, e a nova nasce sem baixa (ver
// services/rede/baixaComandas.py). Quando a comanda editada JÁ estava
// conferida, passar true faz o formulário devolver a baixa pra comanda nova
// assim que ela é salva, em vez de deixá-la cair pra fora do caixa do dia.
// A Consulta omite o argumento e fica com o comportamento de sempre.
function abrir(pilhaPrincipal, nomeArquivo, manterBaixa) {
    if (!pilhaPrincipal)
        return false;

    var dados = consultaController.reconstruirComanda(nomeArquivo);
    if (!dados || !dados.itens)
        return false;

    // Comanda de Mesa já fechada (com a divisão da conta já impressa) não
    // tem como reabrir de volta num formulário estruturado — nem Balcao.qml
    // nem Entrega.qml sabem o que fazer com "mesa"/divisão. Quem chama já
    // esconde o botão "Editar" pra ela; isto é só defesa a mais.
    if (dados.tipo === "Mesa")
        return false;

    if (dados.tipo === "Entrega") {
        pilhaPrincipal.push(raizProjeto + "qml/pages/entrega/Entrega.qml", {
            "clienteNome": dados.cliente,
            "telefoneInicial": dados.telefone,
            "enderecoInicial": dados.endereco,
            "numeroInicial": dados.numero,
            "bairroInicial": dados.bairro,
            "observacaoInicial": dados.observacaoGeral,
            "formaPagamentoInicial": dados.formaPagamento,
            "trocoInicial": dados.troco,
            "statusPagamentoInicial": dados.statusPagamento,
            "taxaEntregaInicial": dados.taxaEntrega,
            "itensIniciais": dados.itens,
            "arquivoOriginal": nomeArquivo,
            "manterBaixaAoSalvar": manterBaixa === true
        });
    } else {
        pilhaPrincipal.push(raizProjeto + "qml/pages/balcao/Balcao.qml", {
            "clienteNome": dados.cliente,
            "formaPagamentoInicial": dados.formaPagamento,
            "trocoInicial": dados.troco,
            "statusPagamentoInicial": dados.statusPagamento,
            "itensIniciais": dados.itens,
            "arquivoOriginal": nomeArquivo,
            "manterBaixaAoSalvar": manterBaixa === true
        });
    }

    return true;
}
