import QtQuick
import QtQuick.Controls
import "../pages/pedidos/MontagemItem.js" as Montagem
import "DestinoPedido.js" as Destino
import "RoteiroLancamento.js" as Roteiro
import estilo 1.0

// Lançamento rápido de pedido a partir da busca do Ctrl+S: recebe o item que o
// atendente escolheu em PopupBuscaCardapio e conduz as perguntas que faltam
// (tamanho, pão, borda, adicionais, tipo de pedido, mesa) até entregar o item
// montado à tela de venda.
//
// Por que um popup próprio, e não empurrar as páginas de categoria
// (pages/pedidos/pizzas/Pizzas.qml e cia.) numa pilha:
//  - elas são telas de "escolha o item", e aqui o item JÁ está escolhido — o
//    atendente teria que achar a mesma pizza de novo, que é justo o passo que
//    a busca acabou de fazer;
//  - elas dependem de uma `pilha` (o StackView LOCAL de cada tela de venda),
//    que um popup global não tem;
//  - custam caro pra abrir (Pizzas.qml lê promoções em XHR síncrono e monta
//    uma grade de 74 sabores) e isso aconteceria a cada Enter, numa máquina de
//    2 núcleos.
//
// A ORDEM das etapas depende da categoria, então o estado é uma sequência de
// nomes calculada uma vez em `abrirPara` — não um encadeado de ifs como em
// pizzas/PopupAdicionaisBordas.qml, que tem um roteiro fixo.
//
// Nada aqui monta o item aos poucos: as escolhas ficam em `escolhas` e o item
// só é montado no fim, em _concluir(). Isso é obrigatório, não estilo — o
// PREÇO depende do tipo de pedido, que é a última pergunta: uma comanda de
// mesa não usa a promoção do dia (ver usarPromocoes: false em Salao.qml) e usa
// o preço de mesa das bebidas quando existe (ver comandaDeMesa/precoEfetivo em
// bebidas/Bebidas.qml).
Popup {
    id: popupLancamento

    // O StackView de main.qml — é por ele que se descobre a tela atual e se
    // navega até a de destino. Injetado de fora porque um .qml separado não
    // enxerga o `id: stackView` da janela raiz (mesmo contrato de
    // EdicaoComanda.js:abrir(pilhaPrincipal, ...)).
    property var pilhaPrincipal: null

    // O resultado da busca que abriu o fluxo, no formato de
    // cardapioController.buscar() — ver services/buscaCardapio.py.
    property var itemBusca: null

    // O item que de fato vai virar linha de pedido. Igual a `itemBusca` no
    // caminho direto; no caminho invertido (o atendente buscou uma borda ou um
    // adicional) é a pizza/lanche/açaí escolhido depois, na etapa "base".
    property var itemBase: null

    // Já nasce com a forma completa: os bindings do cabeçalho leem
    // escolhas.adicionais.length antes de qualquer abrirPara(), e um objeto
    // vazio faria isso estourar na criação do componente.
    property var escolhas: ({
        "borda": null,
        "adicionais": [],
        "chavePreco": "",
        "rotuloPreco": "",
        "tipo": "",
        "mesaId": ""
    })
    property var sequencia: []
    // -1 = nenhuma etapa. A ordem entre este e `sequencia` importa: trocar a
    // sequência com um índice antigo apontando para dentro dela faz `etapa`
    // assumir, por um instante, uma etapa da sequência NOVA na posição da
    // ANTIGA — e o modelo se remonta para uma etapa cujos dados ainda não
    // existem. Por isso `indiceEtapa` sempre é zerado primeiro.
    property int indiceEtapa: -1

    readonly property string etapa: indiceEtapa >= 0 && indiceEtapa < sequencia.length ? sequencia[indiceEtapa] : ""
    readonly property string chaveCategoria: itemBusca ? (itemBusca.chaveCategoria || "") : ""

    // Etapas em que dá pra seguir sem escolher nada: a borda é opcional (não
    // escolher é "Sem borda") e os adicionais também. Uma propriedade só,
    // consultada pelo botão do rodapé, pelo Tab e pela dica de teclado — as
    // três precisam concordar, e antes cada uma repetia a condição.
    readonly property bool podePular: etapa === "adicionais" || etapa === "borda"

    signal concluido(string mensagem, bool sucesso)

    modal: true
    focus: true
    // Nem CloseOnEscape nem CloseOnPressOutside: Esc aqui VOLTA uma etapa (ver
    // Keys.onEscapePressed), e um clique fora cairia sobre o popup de busca,
    // que continua visível atrás — abortar o fluxo por isso seria surpresa.
    closePolicy: Popup.NoAutoClose
    padding: 0
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(Math.round(Responsivo.largura * 0.6), 520)

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.surface
        border.color: Estilo.global.borderCard
        border.width: Estilo.global.borderWidth.hairline
    }

    // --- Catálogos auxiliares, lidos sob demanda e guardados ---
    // Cada etapa de borda/adicional precisa da lista da sua categoria. Ler uma
    // vez por abertura de popup seria uma chamada ao Python por Enter; o cache
    // por chave deixa isso em uma vez por sessão do app.
    property var _cacheCategorias: ({})

    function _itensDe(chave) {
        if (!popupLancamento._cacheCategorias[chave])
            popupLancamento._cacheCategorias[chave] = cardapioController.listarDaCategoria(chave, "");
        return popupLancamento._cacheCategorias[chave];
    }

    // O roteiro de etapas mora em RoteiroLancamento.js: o popup de busca
    // precisa dele antes deste popup existir (ver o comentário no topo do .js).
    function podeIniciar(item) {
        return Roteiro.podeLancar(item);
    }

    function abrirPara(item) {
        if (!item)
            return false;

        var sequencia = Roteiro.sequenciaDe(item.chaveCategoria || "");
        if (sequencia.length === 0)
            return false;

        popupLancamento.itemBusca = item;
        popupLancamento.escolhas = {
            "borda": null,
            "adicionais": [],
            "chavePreco": "",
            "rotuloPreco": "",
            "tipo": "",
            "mesaId": ""
        };

        // No caminho invertido o item base ainda não existe; no direto, é o
        // próprio item da busca.
        if (Roteiro.vendeSozinho(item.chaveCategoria || "")) {
            popupLancamento.itemBase = item;
        } else {
            popupLancamento.itemBase = null;
            // O modificador buscado já entra como escolha feita.
            var valorModificador = Montagem.parseValor(item.precos.length ? item.precos[0].valor : "");
            if (item.chaveCategoria === "pizzaBordas")
                popupLancamento.escolhas.borda = { "nome": item.nome, "valorNum": valorModificador };
            else
                popupLancamento.escolhas.adicionais = [{ "nome": item.nome, "valorNum": valorModificador }];
        }

        // Zera o índice ANTES de trocar a sequência — ver o comentário em
        // `indiceEtapa`.
        popupLancamento.indiceEtapa = -1;
        popupLancamento.sequencia = sequencia;
        popupLancamento._avancar();
        if (popupLancamento.indiceEtapa >= 0)
            popupLancamento.open();
        return popupLancamento.indiceEtapa >= 0;
    }

    // Uma etapa que não tem escolha real não vale uma tela: um item de preço
    // único não pergunta tamanho, e uma categoria de adicionais vazia no JSON
    // não pergunta adicional. Pular acontece nos dois sentidos, senão o
    // "voltar" pararia numa etapa que a ida tinha pulado.
    function _opcoesDaEtapa(nome) {
        if (nome === "tamanho" || nome === "pao")
            return popupLancamento.itemBase ? popupLancamento.itemBase.precos : [];
        if (nome === "borda")
            return popupLancamento._itensDe("pizzaBordas");
        if (nome === "adicionais") {
            if (popupLancamento._chaveDoBase() === "lanches")
                return popupLancamento._itensDe("lanchesAdicionais");
            if (popupLancamento._chaveDoBase() === "acaiTamanhos")
                return popupLancamento._itensDe("acaiAdicionais");
            return popupLancamento._itensDe("pizzaAdicionais");
        }
        if (nome === "base")
            return popupLancamento._itensDe(Roteiro.categoriaBaseDe(popupLancamento.chaveCategoria));
        return [1]; // tipo/mesa nunca são puladas
    }

    function _chaveDoBase() {
        if (popupLancamento.itemBase)
            return popupLancamento.itemBase.chaveCategoria;
        return Roteiro.categoriaBaseDe(popupLancamento.chaveCategoria);
    }

    // PURA: não mexe em `escolhas`. É consultada também pelo binding de
    // `primeiraEtapa`, e um efeito colateral dentro de binding roda em hora
    // imprevisível.
    function _devePular(nome) {
        var opcoes = popupLancamento._opcoesDaEtapa(nome);
        if (opcoes.length === 0)
            return true;
        // Escolha única com uma opção só: decide sozinha e segue.
        return (nome === "tamanho" || nome === "pao") && opcoes.length === 1;
    }

    // A escolha que uma etapa pulada faz por conta própria — só na ida, que é
    // quando ela é de fato tomada.
    function _adotarEscolhaUnica(nome) {
        if (nome !== "tamanho" && nome !== "pao")
            return;

        var opcoes = popupLancamento._opcoesDaEtapa(nome);
        if (opcoes.length === 1) {
            popupLancamento.escolhas.chavePreco = opcoes[0].chave;
            popupLancamento.escolhas.rotuloPreco = opcoes[0].rotulo;
        }
    }

    // Não há etapa anterior visível — o "Voltar" daqui sai do fluxo e devolve
    // à busca. Olha as anteriores uma a uma porque uma etapa pulada não conta
    // como anterior: voltar para ela cairia numa tela sem escolha nenhuma.
    readonly property bool primeiraEtapa: {
        for (var i = indiceEtapa - 1; i >= 0; i--) {
            if (!popupLancamento._devePular(sequencia[i]))
                return false;
        }
        return true;
    }

    function _avancar() {
        var i = popupLancamento.indiceEtapa + 1;
        while (i < popupLancamento.sequencia.length && popupLancamento._devePular(popupLancamento.sequencia[i])) {
            popupLancamento._adotarEscolhaUnica(popupLancamento.sequencia[i]);
            i += 1;
        }

        if (i >= popupLancamento.sequencia.length) {
            popupLancamento._concluir();
            return;
        }
        popupLancamento.indiceEtapa = i;
    }

    function voltar() {
        var i = popupLancamento.indiceEtapa - 1;
        while (i >= 0 && popupLancamento._devePular(popupLancamento.sequencia[i]))
            i -= 1;

        if (i < 0) {
            popupLancamento.close();
            return;
        }
        popupLancamento.indiceEtapa = i;
    }

    // --- Preço: resolvido só aqui, com o tipo de pedido já conhecido ---

    // A lista de preços que vale para `tipo`. Uma comanda de mesa não usa a
    // promoção do dia — Salao.qml passa usarPromocoes: false ao popup de
    // seleção, e o mesmo tem que valer aqui, senão toda pizza em promoção sai
    // mais barata pelo caminho rápido do que o salão cobra.
    function _tabelaDePrecos(item, tipo) {
        if (tipo === "Salão" && item.emPromocao && item.precosTabela && item.precosTabela.length > 0)
            return item.precosTabela;
        return item.precos;
    }

    function _precoPorChave(item, chaveCampo, tipo) {
        var tabela = popupLancamento._tabelaDePrecos(item, tipo);
        for (var i = 0; i < tabela.length; i++) {
            if (tabela[i].chave === chaveCampo)
                return Montagem.parseValor(tabela[i].valor);
        }
        return tabela.length > 0 ? Montagem.parseValor(tabela[0].valor) : 0;
    }

    // Bebida numa comanda de mesa usa "valorMesa" quando esse preço existe —
    // nem toda bebida tem, e aí vale o preço normal (mesma regra de
    // Bebidas.precoEfetivo).
    function _precoSimples(item, tipo) {
        var tabela = popupLancamento._tabelaDePrecos(item, tipo);
        if (tipo === "Salão") {
            for (var i = 0; i < tabela.length; i++) {
                if (tabela[i].chave === "valorMesa")
                    return Montagem.parseValor(tabela[i].valor);
            }
        }
        return tabela.length > 0 ? Montagem.parseValor(tabela[0].valor) : 0;
    }

    // Os preços do item base na ordem em que a etapa de tamanho/pão os lista.
    //
    // Pizza sai do MAIOR pro menor (Grande, Broto, Mini): a grande é a mais
    // vendida, e deixá-la em primeiro poupa uma tecla no caminho comum. Os
    // campos vêm de cardapioService.CATEGORIAS em ordem crescente de tamanho,
    // então inverter é o que dá "maior primeiro" — e continua dando se um
    // tamanho novo for acrescentado lá na posição certa.
    //
    // Os pães do lanche não têm ordem de grandeza (Hambúrguer/Francês/Baby),
    // então ficam como estão. Cópia antes de inverter: `precos` vem do item
    // guardado em cache, e reverse() mexe no array no lugar.
    function _precosNaOrdemDaEtapa() {
        if (!popupLancamento.itemBase)
            return [];

        var precos = popupLancamento.itemBase.precos.slice();
        if (popupLancamento.itemBase.chaveCategoria === "pizzas")
            precos.reverse();
        return precos;
    }

    function _resumoPao(chaveCampo) {
        if (chaveCampo === "valor.pao_frances")
            return "frances";
        if (chaveCampo === "valor.pao_baby")
            return "baby";
        return "";
    }

    function _montarItem() {
        var base = popupLancamento.itemBase;
        var tipo = popupLancamento.escolhas.tipo;
        var chave = base.chaveCategoria;

        if (chave === "pizzas") {
            var preco = popupLancamento._precoPorChave(base, popupLancamento.escolhas.chavePreco, tipo);
            return Montagem.montarPizza({
                "sabores": [{ "nome": base.nome, "valorNum": preco }],
                "tamanho": popupLancamento.escolhas.rotuloPreco,
                "valorNum": preco,
                "borda": popupLancamento.escolhas.borda,
                // O "sabor" do adicional tem que ser o nome do sabor, é por ele
                // que a impressão casa o adicional com a linha da pizza.
                "adicionais": popupLancamento.escolhas.adicionais.map(function (a) {
                    return { "sabor": base.nome, "nome": a.nome, "valorNum": a.valorNum };
                })
            });
        }

        if (chave === "lanches") {
            return Montagem.montarLanche({
                "nome": base.nome,
                "resumoPao": popupLancamento._resumoPao(popupLancamento.escolhas.chavePreco),
                "valorNum": popupLancamento._precoPorChave(base, popupLancamento.escolhas.chavePreco, tipo),
                "adicionais": popupLancamento.escolhas.adicionais
            });
        }

        if (chave === "acaiTamanhos") {
            return Montagem.montarAcai({
                "tamanho": base.nome,
                "valorNum": popupLancamento._precoSimples(base, tipo),
                "adicionais": popupLancamento.escolhas.adicionais.map(function (a) {
                    return { "nome": a.nome, "valorNum": a.valorNum, "quantidade": 1 };
                })
            });
        }

        return Montagem.montarSimples({
            "nome": base.nome,
            "valorNum": popupLancamento._precoSimples(base, tipo)
        });
    }

    // --- Entrega do item ao destino ---

    function _telaAtual() {
        return popupLancamento.pilhaPrincipal ? popupLancamento.pilhaPrincipal.currentItem : null;
    }

    function _tipoDaTelaAtual() {
        var atual = popupLancamento._telaAtual();
        return Destino.tipoDaTela(atual ? atual.objectName : "");
    }

    function _concluir() {
        var itens = [popupLancamento._montarItem()];
        var tipo = popupLancamento.escolhas.tipo;
        var atual = popupLancamento._telaAtual();
        var tipoAtual = popupLancamento._tipoDaTelaAtual();

        // Já estamos na tela certa: acrescenta ao pedido em andamento, sem
        // navegar e sem perder o que estiver preenchido.
        if (tipo === tipoAtual) {
            if (tipo === "Salão" && popupLancamento.escolhas.mesaId !== "__atual__")
                atual.aplicarLancamentoRapido(popupLancamento.escolhas.mesaId, itens);
            else
                atual.acrescentarItens(itens);

            popupLancamento.close();
            popupLancamento.concluido(itens[0].nome + " lançado em " + tipo + ".", true);
            return;
        }

        // Sair daqui destrói a página atual (replace) e leva junto o que
        // estiver digitado — só vale perguntar quando há algo a perder.
        if (tipoAtual !== "" && atual.temPedidoEmAndamento()) {
            dialogoPedidoAberto.itensPendentes = itens;
            dialogoPedidoAberto.tipoDestino = tipo;
            dialogoPedidoAberto.tipoAtual = tipoAtual;
            dialogoPedidoAberto.open();
            return;
        }

        popupLancamento._navegar(tipo, itens);
    }

    // O diálogo de "já existe um pedido aberto" está na tela? Também serve pra
    // não deixar o Ctrl+S alcançar o fluxo enquanto a pergunta está no ar.
    readonly property bool confirmandoSaida: dialogoPedidoAberto.visible

    // As duas saídas da pergunta. Nomeadas (e não escritas dentro do onClicked
    // de cada botão) porque são o desfecho do fluxo inteiro — vale poder
    // chamá-las de um teste sem ter que achar o botão certo.
    function resolverLancandoAqui() {
        var itens = dialogoPedidoAberto.itensPendentes;
        popupLancamento._telaAtual().acrescentarItens(itens);
        dialogoPedidoAberto.close();
        popupLancamento.close();
        popupLancamento.concluido(itens[0].nome + " lançado em " + dialogoPedidoAberto.tipoAtual + ".", true);
    }

    function resolverNavegando() {
        dialogoPedidoAberto.close();
        popupLancamento._navegar(dialogoPedidoAberto.tipoDestino, dialogoPedidoAberto.itensPendentes);
    }

    function _navegar(tipo, itens) {
        // Duas formas do MESMO item, e o destino decide qual recebe:
        //
        //  - Balcão e Entrega copiam `itensIniciais` para o modelo no próprio
        //    Component.onCompleted, lendo a chave "pedido" (a propriedade
        //    nasceu para a Consulta reabrir uma comanda salva);
        //  - o Salão não pode copiar na criação (carregar a mesa substitui o
        //    modelo inteiro depois), então ele acrescenta via acrescentarItens
        //    já com a tela montada — e essa função espera a chave "nome", que
        //    é o que as páginas de categoria produzem.
        //
        // Mandar a forma errada não dá erro: dá linha de pedido em branco.
        var props;
        if (tipo === "Salão") {
            props = {
                "itensLancamento": itens,
                "mesaInicialId": popupLancamento.escolhas.mesaId === "__atual__" ? "" : popupLancamento.escolhas.mesaId
            };
        } else {
            props = { "itensIniciais": Destino.paraItensIniciais(itens) };
        }

        // replace(null, ...), não push: a pilha principal vive em profundidade
        // 1 (ver o comentário do StackView em main.qml) e um push deixaria uma
        // página órfã embaixo que ninguém desempilha.
        popupLancamento.pilhaPrincipal.replace(null, raizProjeto + Destino.paginaDoTipo(tipo), props, StackView.Immediate);
        popupLancamento.close();
        popupLancamento.concluido(itens[0].nome + " lançado em " + tipo + ".", true);
    }

    // --- Escolha de cada etapa ---

    function escolher(valor) {
        var nome = popupLancamento.etapa;

        if (nome === "tamanho" || nome === "pao") {
            popupLancamento.escolhas.chavePreco = valor.chave;
            popupLancamento.escolhas.rotuloPreco = valor.rotulo;
        } else if (nome === "borda") {
            popupLancamento.escolhas.borda = valor === null ? null : {
                "nome": valor.nome,
                "valorNum": Montagem.parseValor(valor.precos.length ? valor.precos[0].valor : "")
            };
        } else if (nome === "base") {
            popupLancamento.itemBase = valor;
        } else if (nome === "tipo") {
            popupLancamento.escolhas.tipo = valor;
            // Salão precisa saber em qual mesa; as outras duas não têm o que
            // perguntar. A etapa entra aqui, fora da sequência, porque só
            // existe dependendo desta resposta.
            //
            // RECOMPÕE a cauda em vez de só acrescentar: com o botão Voltar dá
            // pra passar por aqui mais de uma vez, e acrescentar cegamente
            // deixava "mesa" pendurada num pedido de Balcão (o fluxo perguntava
            // a mesa de um pedido que não é de mesa) ou duplicada ao reescolher
            // Salão.
            var etapas = popupLancamento.sequencia.slice();
            if (etapas[etapas.length - 1] === "mesa")
                etapas.pop();
            if (valor === "Salão")
                etapas.push("mesa");
            // "tipo" não muda de posição, então `etapa` continua apontando pra
            // ela enquanto isto é reatribuído.
            popupLancamento.sequencia = etapas;
        } else if (nome === "mesa") {
            popupLancamento.escolhas.mesaId = valor;
        }

        popupLancamento._avancar();
    }

    // Adicionais é a única etapa de várias escolhas — alterna e não avança.
    function alternarAdicional(item) {
        var valorNum = Montagem.parseValor(item.precos.length ? item.precos[0].valor : "");
        var lista = [];
        var achou = false;
        for (var i = 0; i < popupLancamento.escolhas.adicionais.length; i++) {
            var atual = popupLancamento.escolhas.adicionais[i];
            if (atual.nome === item.nome)
                achou = true;
            else
                lista.push(atual);
        }
        if (!achou)
            lista.push({ "nome": item.nome, "valorNum": valorNum });

        // Reatribuição, não push: é o que faz a lista da etapa repintar.
        var novas = popupLancamento.escolhas;
        novas.adicionais = lista;
        popupLancamento.escolhas = novas;
        modeloEtapa.recarregar();
    }

    function _adicionalMarcado(nome) {
        for (var i = 0; i < popupLancamento.escolhas.adicionais.length; i++) {
            if (popupLancamento.escolhas.adicionais[i].nome === nome)
                return true;
        }
        return false;
    }

    // --- Linhas exibidas na etapa atual ---
    // Um formato só ({rotulo, sublinha, valor, marcado}) para todas as etapas:
    // é o que permite uma lista só, com um teclado só, em vez de seis blocos
    // de UI quase iguais.
    QtObject {
        id: modeloEtapa

        property var linhas: []

        function recarregar() {
            modeloEtapa.linhas = modeloEtapa._montar();
        }

        function _montar() {
            var nome = popupLancamento.etapa;
            var saida = [];
            var i;

            // Rede de segurança: no caminho invertido o item base só existe
            // depois da etapa "base", e qualquer reavaliação fora de ordem
            // cairia aqui com itemBase nulo.
            if (nome === "")
                return saida;

            if (nome === "tamanho" || nome === "pao") {
                if (!popupLancamento.itemBase)
                    return saida;

                var precos = popupLancamento._precosNaOrdemDaEtapa();
                for (i = 0; i < precos.length; i++) {
                    saida.push({
                        "rotulo": precos[i].rotulo,
                        "sublinha": precos[i].valor,
                        "valor": precos[i],
                        "marcado": precos[i].chave === popupLancamento.escolhas.chavePreco
                    });
                }
                return saida;
            }

            if (nome === "borda") {
                var bordaAtual = popupLancamento.escolhas.borda;
                saida.push({ "rotulo": "Sem borda", "sublinha": "", "valor": null, "marcado": bordaAtual === null });
                var bordas = popupLancamento._itensDe("pizzaBordas");
                for (i = 0; i < bordas.length; i++) {
                    saida.push({
                        "rotulo": bordas[i].nome,
                        "sublinha": bordas[i].resumoPrecos,
                        "valor": bordas[i],
                        "marcado": !!bordaAtual && bordaAtual.nome === bordas[i].nome
                    });
                }
                return saida;
            }

            if (nome === "adicionais") {
                // Primeira da lista, como o "Sem borda" da etapa de borda: a
                // resposta mais comum é "nenhum", e ela é a única que estava
                // atrás do Tab/do botão do rodapé em vez de estar sob o dedo.
                // Com ela no topo, o Enter resolve a etapa sem tirar a mão da
                // fileira de teclas.
                //
                // valor null é o que a distingue de um adicional de verdade
                // (ver _acionarFoco) — mesma convenção do "Sem borda".
                saida.push({
                    "rotulo": "Sem adicionais",
                    "sublinha": "",
                    "valor": null,
                    "marcado": popupLancamento.escolhas.adicionais.length === 0
                });

                var lista = popupLancamento._opcoesDaEtapa("adicionais");
                for (i = 0; i < lista.length; i++)
                    saida.push({ "rotulo": lista[i].nome, "sublinha": lista[i].resumoPrecos, "valor": lista[i], "marcado": popupLancamento._adicionalMarcado(lista[i].nome) });
                return saida;
            }

            if (nome === "base") {
                var bases = popupLancamento._opcoesDaEtapa("base");
                for (i = 0; i < bases.length; i++) {
                    saida.push({
                        "rotulo": bases[i].nome,
                        "sublinha": bases[i].resumoPrecos,
                        "valor": bases[i],
                        "marcado": !!popupLancamento.itemBase && popupLancamento.itemBase.nome === bases[i].nome
                    });
                }
                return saida;
            }

            if (nome === "tipo") {
                var tipos = ["Balcão", "Entrega", "Salão"];
                var tipoAtual = popupLancamento._tipoDaTelaAtual();
                for (i = 0; i < tipos.length; i++) {
                    saida.push({
                        "rotulo": tipos[i],
                        // Dizer que vai somar ao pedido aberto evita a dúvida
                        // de "isso vai criar um pedido novo?".
                        "sublinha": tipos[i] === tipoAtual ? "acrescenta ao pedido desta tela" : "",
                        "valor": tipos[i],
                        "marcado": tipos[i] === popupLancamento.escolhas.tipo
                    });
                }
                return saida;
            }

            if (nome === "mesa") {
                // "" também é o valor de "Nova mesa", então só marca quando o
                // atendente já passou por esta etapa alguma vez.
                var mesaEscolhida = popupLancamento.escolhas.tipo === "Salão" ? popupLancamento.escolhas.mesaId : null;
                var atual = popupLancamento._telaAtual();
                if (atual && atual.objectName === "telaSalao" && atual.mesaAtualId !== "")
                    saida.push({ "rotulo": "Mesa aberta nesta tela", "sublinha": "", "valor": "__atual__", "marcado": mesaEscolhida === "__atual__" });

                saida.push({ "rotulo": "Nova mesa", "sublinha": "", "valor": "", "marcado": false });
                var mesas = salaoController.listarMesasAbertas();
                for (i = 0; i < mesas.length; i++) {
                    saida.push({
                        "rotulo": "Mesa " + mesas[i].mesa + (mesas[i].cliente ? (" — " + mesas[i].cliente) : ""),
                        "sublinha": mesas[i].quantidadeItens + " item(ns)",
                        "valor": mesas[i].id,
                        "marcado": mesaEscolhida === mesas[i].id
                    });
                }
                return saida;
            }

            return saida;
        }
    }

    readonly property string tituloEtapa: {
        switch (etapa) {
        case "tamanho": return "Tamanho";
        case "pao": return "Tipo de pão";
        case "borda": return "Borda";
        case "adicionais": return "Adicionais";
        case "base": return chaveCategoria === "lanchesAdicionais" ? "Em qual lanche?"
                          : (chaveCategoria === "acaiAdicionais" ? "Em qual açaí?" : "Em qual pizza?");
        case "tipo": return "Tipo de pedido";
        case "mesa": return "Mesa";
        }
        return "";
    }

    property int indiceFoco: 0

    onEtapaChanged: {
        popupLancamento.indiceFoco = 0;
        modeloEtapa.recarregar();
    }

    onOpened: {
        modeloEtapa.recarregar();
        conteudo.forceActiveFocus();
    }

    onClosed: {
        popupLancamento.itemBusca = null;
        popupLancamento.itemBase = null;
        popupLancamento.sequencia = [];
        popupLancamento.indiceEtapa = 0;
    }

    // As linhas da etapa atual, no formato {rotulo, sublinha, valor, marcado}.
    // Pública para a ListView abaixo e para os testes conseguirem percorrer o
    // fluxo sem clicar em nada.
    function linhasDaEtapa() {
        return modeloEtapa.linhas;
    }

    function _mover(passo) {
        if (modeloEtapa.linhas.length === 0)
            return;

        var destino = popupLancamento.indiceFoco + passo;
        popupLancamento.indiceFoco = Math.max(0, Math.min(modeloEtapa.linhas.length - 1, destino));
        listaEtapa.positionViewAtIndex(popupLancamento.indiceFoco, ListView.Contain);
    }

    function _acionarFoco() {
        if (modeloEtapa.linhas.length === 0)
            return;

        var linha = modeloEtapa.linhas[popupLancamento.indiceFoco];
        if (popupLancamento.etapa === "adicionais") {
            // "Sem adicionais" (valor null) não alterna nada: ele é uma
            // RESPOSTA à etapa, e por isso avança, ao contrário dos adicionais
            // de verdade, que se acumulam.
            //
            // Limpa o que já estava marcado antes de seguir: quem marcou dois
            // e depois escolheu "Sem adicionais" mudou de ideia, e seguir com
            // os dois marcados cobraria por eles.
            if (linha.valor === null) {
                popupLancamento.escolhas.adicionais = [];
                popupLancamento._avancar();
                return;
            }
            popupLancamento.alternarAdicional(linha.valor);
            return;
        }

        popupLancamento.escolher(linha.valor);
    }

    contentItem: FocusScope {
        id: conteudo

        implicitHeight: colunaConteudo.implicitHeight
        focus: true

        Keys.onUpPressed: popupLancamento._mover(-1)
        Keys.onDownPressed: popupLancamento._mover(1)
        Keys.onReturnPressed: popupLancamento._acionarFoco()
        Keys.onEnterPressed: popupLancamento._acionarFoco()
        Keys.onEscapePressed: popupLancamento.voltar()
        // Alt+← volta uma etapa, ao lado do Esc e do botão "Voltar".
        //
        // É o Alt da ESQUERDA: no teclado ABNT2 o da direita é o AltGr, que
        // serve pra digitar caractere, e o Qt não separa os dois em
        // `modifiers` — os dois chegam como Qt.AltModifier. O que os distingue
        // é o modificador EXTRA que o AltGr carrega: GroupSwitchModifier no
        // X11 e Ctrl+Alt no Windows. Exigir a ausência dos dois deixa passar
        // só o Alt esquerdo, nas duas plataformas em que este app roda.
        Keys.onLeftPressed: function (evento) {
            var comAlt = (evento.modifiers & Qt.AltModifier) !== 0;
            var ehAltGr = (evento.modifiers & (Qt.GroupSwitchModifier | Qt.ControlModifier)) !== 0;

            if (!comAlt || ehAltGr) {
                evento.accepted = false;
                return;
            }

            popupLancamento.voltar();
            evento.accepted = true;
        }
        // Tab segue em frente nas etapas opcionais: nos adicionais o Enter
        // marca/desmarca, então sem ele não haveria como dizer "terminei de
        // marcar"; na borda ele é o mesmo que o botão "Pular", que fica do
        // outro lado do rodapé.
        //
        // Precisa ser onTabPressed, e não um `if (evento.key === Qt.Key_Tab)`
        // dentro de Keys.onPressed: o Tab é consumido pela navegação de foco
        // do Qt ANTES de chegar ao handler genérico, então aquele ramo nunca
        // rodava — o popup simplesmente não avançava. Nas etapas de escolha
        // obrigatória o evento é devolvido (accepted = false) para o Tab
        // seguir servindo de navegação normal.
        Keys.onTabPressed: function (evento) {
            if (!popupLancamento.podePular) {
                evento.accepted = false;
                return;
            }

            popupLancamento._avancar();
            evento.accepted = true;
        }

        Column {
            id: colunaConteudo

            width: parent.width
            spacing: 0

            // --- Cabeçalho: o item em montagem e a etapa atual ---
            Rectangle {
                width: parent.width
                height: cabecalho.implicitHeight + Estilo.global.padding.xl * 2
                color: "transparent"

                Column {
                    id: cabecalho

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Estilo.global.padding.xl
                    spacing: Estilo.global.spacing.xs

                    Row {
                        spacing: Estilo.global.spacing.sm

                        Icone {
                            nome: popupLancamento.itemBusca ? popupLancamento.itemBusca.icone : ""
                            cor: popupLancamento.itemBusca ? popupLancamento.itemBusca.cor : Estilo.global.text
                            tamanho: Estilo.global.fontSize.lg
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: popupLancamento.itemBase ? popupLancamento.itemBase.nome
                                : (popupLancamento.itemBusca ? popupLancamento.itemBusca.nome : "")
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.text
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, cabecalho.width - 40)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        text: popupLancamento.tituloEtapa
                        font.pixelSize: Estilo.global.fontSize.md
                        color: Estilo.global.textSecondary
                    }

                    // Só aparece quando há escolha feita — no primeiro passo não
                    // ocupa espaço nem pede explicação.
                    Text {
                        width: cabecalho.width
                        visible: text !== ""
                        text: {
                            var partes = [];
                            if (popupLancamento.escolhas.rotuloPreco)
                                partes.push(popupLancamento.escolhas.rotuloPreco);
                            if (popupLancamento.escolhas.borda)
                                partes.push(popupLancamento.escolhas.borda.nome);
                            for (var i = 0; i < popupLancamento.escolhas.adicionais.length; i++)
                                partes.push("+ " + popupLancamento.escolhas.adicionais[i].nome);
                            return partes.join("   ·   ");
                        }
                        font.pixelSize: Estilo.global.fontSize.sm
                        color: Estilo.screen.config.accent
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Estilo.global.divider
            }

            // --- Lista da etapa ---
            ListView {
                id: listaEtapa

                width: parent.width
                height: Math.min(contentHeight, Math.round(Responsivo.altura * 0.45))
                model: modeloEtapa.linhas
                clip: true
                reuseItems: true
                currentIndex: popupLancamento.indiceFoco

                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    id: linhaEtapa

                    required property int index
                    required property var modelData

                    width: listaEtapa.width - (listaEtapa.ScrollBar.vertical.visible ? listaEtapa.ScrollBar.vertical.width : 0)
                    height: 44
                    color: linhaEtapa.index === popupLancamento.indiceFoco ? Estilo.global.surfacePressed
                         : (areaLinha.containsMouse ? Estilo.global.surfaceHover : "transparent")

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Estilo.global.padding.xl
                        anchors.rightMargin: Estilo.global.padding.xl
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Estilo.global.spacing.sm

                        // Presente em todas as etapas: é o que dá sentido ao
                        // botão Voltar. Sem indicar a escolha vigente, voltar
                        // uma etapa mostrava a mesma lista de antes, sem pista
                        // do que estava valendo — não dava pra saber o que se
                        // estava desfazendo. Quadrado onde se marca mais de um
                        // (adicionais), círculo onde a escolha é única.
                        Icone {
                            readonly property bool _multipla: popupLancamento.etapa === "adicionais"

                            nome: linhaEtapa.modelData.marcado
                                ? (_multipla ? "fa6s.square-check" : "fa6s.circle-check")
                                : (_multipla ? "fa6s.square" : "fa6s.circle")
                            cor: linhaEtapa.modelData.marcado ? Estilo.action.confirm.base : Estilo.global.textMuted
                            tamanho: Estilo.global.fontSize.lg
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: linhaEtapa.modelData.rotulo
                            font.pixelSize: Estilo.global.fontSize.lg
                            color: Estilo.global.text
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Estilo.global.padding.xl + (listaEtapa.ScrollBar.vertical.visible ? listaEtapa.ScrollBar.vertical.width : 0)
                        anchors.verticalCenter: parent.verticalCenter
                        text: linhaEtapa.modelData.sublinha
                        font.pixelSize: Estilo.global.fontSize.sm
                        color: Estilo.global.textSecondary
                    }

                    MouseArea {
                        id: areaLinha

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            popupLancamento.indiceFoco = linhaEtapa.index;
                            popupLancamento._acionarFoco();
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Estilo.global.divider
            }

            // --- Rodapé ---
            Item {
                width: parent.width
                height: 52

                // Presente em TODAS as etapas, inclusive na primeira — ali ele
                // devolve à busca, que continua aberta atrás. Sem um botão à
                // vista, desfazer uma escolha dependia de saber que Esc volta,
                // e quem não sabe fica preso indo até o fim do fluxo.
                Botao {
                    id: btnVoltar

                    anchors.left: parent.left
                    anchors.leftMargin: Estilo.global.padding.xl
                    anchors.verticalCenter: parent.verticalCenter
                    text: popupLancamento.primeiraEtapa ? "Voltar à busca" : "Voltar"
                    nomeIcone: "fa6s.arrow-left"
                    variante: "ghost"
                    // Sem isto o Button do Controls 2 fica no caminho do Tab e
                    // rouba o foco no clique — e aí as setas, o Enter e o
                    // proprio Tab param de responder (mesmo motivo documentado
                    // nos botoes de configuracoes/impressora/EstiloImpressora.qml).
                    focusPolicy: Qt.NoFocus
                    onClicked: popupLancamento.voltar()
                }

                Text {
                    anchors.left: btnVoltar.right
                    anchors.leftMargin: Estilo.global.spacing.md
                    anchors.right: btnAvancar.visible ? btnAvancar.left : parent.right
                    anchors.rightMargin: Estilo.global.spacing.md
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        var partes = popupLancamento.etapa === "adicionais"
                            ? ["Enter marca", "Tab continua"]
                            : ["↑ ↓ navegar", "Enter escolher"];
                        if (popupLancamento.podePular && popupLancamento.etapa !== "adicionais")
                            partes.push("Tab pula");
                        partes.push("Alt+← volta");
                        return partes.join("   ·   ");
                    }
                    font.pixelSize: Estilo.global.fontSize.sm
                    color: Estilo.global.textSecondary
                    elide: Text.ElideRight
                }

                Botao {
                    id: btnAvancar

                    anchors.right: parent.right
                    anchors.rightMargin: Estilo.global.padding.xl
                    anchors.verticalCenter: parent.verticalCenter
                    visible: popupLancamento.podePular
                    text: popupLancamento.etapa === "adicionais" ? "Continuar" : "Pular"
                    variante: "secundario"
                    focusPolicy: Qt.NoFocus
                    onClicked: popupLancamento._avancar()
                }
            }
        }
    }

    // Perguntar só quando há o que perder: a tela atual é de venda, tem pedido
    // em andamento, e o destino escolhido é outro. Sair daqui é replace(), que
    // destrói a página sem salvar nada.
    Dialogo {
        id: dialogoPedidoAberto

        property var itensPendentes: []
        property string tipoDestino: ""
        property string tipoAtual: ""

        titulo: "Já existe um pedido aberto"
        corpo: "A tela de " + tipoAtual + " tem um pedido em andamento. Abrir " + tipoDestino + " descarta o que está nela."
        nomeIcone: "fa6s.triangle-exclamation"

        Botao {
            text: "Voltar"
            variante: "ghost"
            onClicked: dialogoPedidoAberto.close()
        }

        Botao {
            text: "Lançar em " + dialogoPedidoAberto.tipoAtual
            variante: "secundario"
            onClicked: popupLancamento.resolverLancandoAqui()
        }

        Botao {
            text: "Abrir " + dialogoPedidoAberto.tipoDestino
            tom: Estilo.action.danger
            onClicked: popupLancamento.resolverNavegando()
        }
    }
}
