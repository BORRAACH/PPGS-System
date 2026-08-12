import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../../components"

// Configuração da comanda impressa: a ORDEM em que os campos saem no cupom
// e o ESTILO ESC/POS de cada um (negrito/sublinhado/fundo preto/fonte
// grande), mais o espaçamento entre seções e antes do corte automático.
//
// Tudo isso é editado numa peça só: um modelo do cupom desenhado na tela,
// que é ao mesmo tempo a prévia e a superfície de edição. Clicar numa linha
// a seleciona e faz os controles (mover pra cima/baixo e "Estilo…")
// aparecerem ao lado dela, na faixa à direita do papel; mover um campo
// remonta a comanda na hora — inclusive as linhas tracejadas, que dependem
// de quais campos ficaram vizinhos (ver separadorEntre() abaixo). A
// espessura dessas divisórias é o contador do bloco ESPAÇAMENTO, e cada
// linha pode fugir dele pelos botões "Traços acima" (ver linhasTracoAntes).
//
// Antes existiam três blocos separados pra isso (uma lista de 18 campos só
// pra estilo, uma prévia estática do cupom, e uma lista de 16 campos com
// dois botões de seta em cada linha). A prévia estática tinha o problema de
// ser escrita à mão: não seguia a ordem configurada e foi ficando
// desatualizada em relação ao que a impressora realmente cuspia.
//
// Lida/gravada por comandaEstiloController (ver
// services/comandaEstiloService.py), que balcaoController.py/
// entregaController.py/salaoController.py consultam ao montar a comanda.
//
// Não é uma Page própria — é o conteúdo embutido por ../Configuracoes.qml
// dentro da área rolável da tela de Configurações.
Column {
    id: raiz

    readonly property color corDestaque: Estilo.screen.config.accent
    // Largura da comanda em caracteres — a mesma de "-" * 40 e do
    // MARCADOR_ITENS ("=" * 40) em services/comandaTextoService.py. Sai daqui
    // a largura do papel na tela, então a prévia não pode divergir do que é
    // impresso (antes o papel desenhava traços de 28 contra 40 do Python).
    readonly property int colunasPapel: 40
    readonly property int tamanhoBasePapel: 12

    property int espacamentoSecoes: 1
    property int espacamentoCorte: 4
    property int tamanhoFontePadrao: 24
    // Espessura padrão de cada divisória tracejada, e as exceções por campo
    // ({chave: nº de traços antes dela}) que ignoram a regra automática de
    // categoria. Espelham "linhas_separador"/"separadores_campo" do JSON —
    // ver comandaEstiloService.linhas_separador_antes, que é a mesma regra do
    // lado do Python.
    property int linhasSeparadorPadrao: 1
    property int maxLinhasSeparador: 5
    // Reatribuído inteiro (nunca mutado no lugar) pelas funções que mexem
    // nele, pelo mesmo motivo de `separadores` logo abaixo: é um objeto JS
    // comum, e só a atribuição emite o sinal que faz a prévia se redesenhar.
    property var separadoresPorCampo: ({})
    // Estado local desta sessão de edição — cliques só mexem aqui
    // (instantâneo, sem chamar o Python). Só vira gravação em disco quando o
    // usuário clica em "Aplicar alterações" (ver ../Configuracoes.qml), ou
    // quando ele confirma a saída com edições pendentes. Gravar a cada clique
    // deixava os controles com sensação de atraso, porque a chamada síncrona
    // pro Python bloqueava o próximo frame de renderização até terminar.
    property var configAtual: ({
        "campos": {}
    })
    // "A configuração inteira foi trocada" — incrementado só por
    // carregarConfiguracao() (abrir a tela, restaurar padrões), que é quando
    // TODOS os campos da prévia precisam se reler de uma vez. Uma edição de um
    // campo só não passa por aqui: emite campoEstiloAlterado, e apenas a
    // prévia daquele campo se atualiza (ver PreviaCampoTexto.qml).
    property int versaoConfig: 0

    // --- Estado da prévia interativa ---

    // Guardada por CHAVE, nunca por índice: com índice o destaque ficaria
    // preso à posição, e mover um campo faria a seleção "saltar" pro campo
    // que desceu no lugar dele.
    property string chaveSelecionada: ""
    // Linha ordenável que CONTÉM o que está selecionado — as setas mexem
    // sempre nela. Coincide com chaveSelecionada na maioria dos campos, mas
    // difere nas sub-linhas da tabela de itens: selecionar "Nome do pedido"
    // estiliza aquela linha e move a tabela inteira, que é a única coisa que
    // faz sentido (uma linha da tabela não tem posição própria no cupom).
    property string donoSelecionado: ""
    property string tipoComanda: "Entrega"
    property var tiposComanda: []

    // Posição da linha destacada DENTRO do papel, para os controles
    // flutuantes (setas + "Estilo…") ficarem na altura dela. Escrita pela
    // própria sub-linha selecionada, via Binding, somando os y da cadeia
    // colunaPapel → linhaOrdem → subLinha: escrito assim (e não com
    // mapToItem, que não é reativo) o valor reavalia sozinho quando qualquer
    // um desses y muda — reordenar a comanda, mexer no espaçamento entre
    // seções ou aumentar a fonte de um campo acima empurra a linha, e os
    // botões acompanham, inclusive durante a animação de troca de posição.
    property real yLinhaSelecionada: 0
    property real alturaLinhaSelecionada: 0

    // Divisória que vem ANTES de cada linha da ordem, como
    // { tipo: "" | "-" | "=", linhas: nº de repetições }.
    // Recalculado inteiro e ATRIBUÍDO (nunca .push()) — atribuir um array
    // novo é o que emite separadoresChanged e faz as bindings dos delegates
    // reavaliarem. Guardar isto aqui, em vez de cada delegate espiar o
    // vizinho anterior com modeloOrdemSecoes.get(index - 1), é de propósito:
    // esse proxy de linha não é seguro dentro de binding, e a vizinhança
    // fica consistente por construção ao ser calculada de uma vez sobre o
    // modelo inteiro.
    property var separadores: []
    // Só a última linha precisa disso: quando a tabela de itens é o último
    // campo da ordem, ainda sai um "=" de fechamento embaixo dela (ver o
    // "if itens_anterior:" no fim de montar_linhas_por_ordem). Esse caso não
    // é expressável como "separador antes de mim", então vira um item extra
    // depois do Repeater.
    property string ultimaChaveOrdem: ""

    // Mapas montados em carregarConfiguracao() a partir dos slots do
    // controller — evita duplicar aqui CATEGORIA_CAMPO/TIPOS_POR_CAMPO/
    // rótulos, que divergiriam do Python na primeira vez que alguém
    // acrescentasse um campo lá.
    property var categoriasPorChave: ({})
    property var tiposPorChave: ({})
    property var rotulosPorChave: ({})

    spacing: 25

    // Textos de exemplo de cada campo. Os prefixos são os REAIS impressos
    // pelos controllers ("Forma de pagamento: ", não "Pagamento: ") — a
    // prévia só vale se o que está na tela for o que sai no papel.
    readonly property var exemplos: ({
        "id_pedido": { "prefixo": "ID: ", "valor": "A291201" },
        "cliente": { "prefixo": "Cliente: ", "valor": "João da Silva" },
        "mesa": { "prefixo": "Mesa: ", "valor": "5" },
        "telefone": { "prefixo": "Telefone: ", "valor": "(11) 91234-5678" },
        "endereco": { "prefixo": "Endereço: ", "valor": "Rua Exemplo, 123" },
        "bairro": { "prefixo": "Bairro: ", "valor": "Centro" },
        "data": { "prefixo": "Data: ", "valor": "25/07/2026 20:15:00" },
        "observacao_entrega": { "prefixo": "Observação: ", "valor": "INTERFONE QUEBRADO" },
        "forma_pagamento": { "prefixo": "Forma de pagamento: ", "valor": "Dinheiro" },
        "troco_para": { "prefixo": "Troco para: ", "valor": "R$ 100,00" },
        "status": { "prefixo": "Status: ", "valor": "NP" },
        "taxa_entrega": { "prefixo": "Taxa de entrega: ", "valor": "R$ 5,00" },
        "valor_total": { "prefixo": "Valor do pedido: ", "valor": "R$ 45,00" },
        "troco_a_dar": { "prefixo": "Troco a dar: ", "valor": "R$ 55,00" }
    })

    // Emitido quando o estilo de UM campo muda, para só a prévia daquele campo
    // se reler (ver PreviaCampoTexto.recarregarEstilo). versaoConfig continua
    // existindo para o caso oposto — "mudou tudo", em carregarConfiguracao().
    signal campoEstiloAlterado(string chave)

    // Há edições que ainda não foram gravadas em disco nem enviadas à malha.
    // Só o botão "Aplicar alterações" (ver ../Configuracoes.qml) zera isto.
    property bool alteracoesPendentes: false

    function marcarPendente() {
        raiz.alteracoesPendentes = true;
    }

    // Os dois espaçamentos são mexidos direto pelos botões -/+ do bloco
    // ESPAÇAMENTO (raiz.espacamentoSecoes += 1), sem passar por função — daí
    // a pendência ser marcada aqui. carregarConfiguracao() também os escreve,
    // e por isso zera a flag no fim.
    onEspacamentoSecoesChanged: raiz.marcarPendente()
    onEspacamentoCorteChanged: raiz.marcarPendente()

    function obterAtributo(campo, atributo) {
        var atributosCampo = raiz.configAtual.campos[campo];
        return !!(atributosCampo && atributosCampo[atributo]);
    }

    function definirAtributoLocal(campo, atributo, valor) {
        if (!raiz.configAtual.campos[campo])
            raiz.configAtual.campos[campo] = {};

        raiz.configAtual.campos[campo][atributo] = valor;
        raiz.marcarPendente();
        raiz.campoEstiloAlterado(campo);
    }

    function obterTamanhoFonte(campo) {
        var atributosCampo = raiz.configAtual.campos[campo];
        var valor = atributosCampo && atributosCampo.tamanho_fonte;
        return valor ? valor : raiz.tamanhoFontePadrao;
    }

    function definirTamanhoFonteLocal(campo, valor) {
        if (!raiz.configAtual.campos[campo])
            raiz.configAtual.campos[campo] = {};

        raiz.configAtual.campos[campo].tamanho_fonte = valor;
        raiz.marcarPendente();
        raiz.campoEstiloAlterado(campo);
    }

    // Espelha comandaEstiloService._multiplicador_fonte (Python): o ESC/POS
    // só tem multiplicadores inteiros de 1x a 8x, então a prévia mostra o
    // tamanho que realmente vai sair impresso, não o valor em pixels puro.
    // Arredonda para cima (não para o mais próximo) — um valor até 1.5x a
    // base arredondado "pro mais próximo" volta pra 1x, dando a impressão de
    // que a mudança não fez nada.
    function multiplicadorFonte(tamanhoPx) {
        if (!tamanhoPx || tamanhoPx <= raiz.tamanhoFontePadrao)
            return 1;

        var multiplicador = Math.ceil(tamanhoPx / raiz.tamanhoFontePadrao);
        return Math.max(1, Math.min(8, multiplicador));
    }

    function salvarNoBackend() {
        // Guarda contra o app inteiro sendo fechado enquanto esta tela está
        // aberta: nesse caso o QML pode ser destruído depois que o contexto
        // já derrubou os controllers, e comandaEstiloController chega aqui
        // como null — sem essa checagem, isso aparece como TypeError no
        // console (inofensivo, mas evitável) bem na hora de fechar o app.
        if (!comandaEstiloController)
            return;

        comandaEstiloController.salvarConfiguracaoCompleta({
            "campos": raiz.configAtual.campos,
            "ordem_secoes": raiz.configAtual.ordem_secoes,
            "espacamento_secoes": raiz.espacamentoSecoes,
            "espacamento_corte": raiz.espacamentoCorte,
            "linhas_separador": raiz.linhasSeparadorPadrao,
            "separadores_campo": raiz.separadoresPorCampo
        });
        raiz.alteracoesPendentes = false;
    }

    function carregarConfiguracao() {
        var config = comandaEstiloController.obterConfiguracao();
        var campos = comandaEstiloController.listarCampos();
        var camposOrdenaveis = comandaEstiloController.listarCamposOrdenaveis();
        raiz.tamanhoFontePadrao = comandaEstiloController.tamanhoFontePadrao();
        raiz.maxLinhasSeparador = comandaEstiloController.maxLinhasSeparador();
        raiz.tiposComanda = comandaEstiloController.listarTiposComanda();
        raiz.configAtual = config;

        // Rótulos dos 18 campos estilizáveis — inclui os 4 que só existem
        // dentro da tabela de itens (pedido/observacao_item/borda_item/
        // adicional_item) e por isso não aparecem no catálogo de ordenáveis.
        var rotulos = {};
        for (var i = 0; i < campos.length; i++)
            rotulos[campos[i].chave] = campos[i].rotulo;

        var categorias = {};
        var tipos = {};
        for (var j = 0; j < camposOrdenaveis.length; j++) {
            var ordenavel = camposOrdenaveis[j];
            rotulos[ordenavel.chave] = ordenavel.rotulo;
            categorias[ordenavel.chave] = ordenavel.categoria;
            tipos[ordenavel.chave] = ordenavel.tipos;
        }
        raiz.rotulosPorChave = rotulos;
        raiz.categoriasPorChave = categorias;
        raiz.tiposPorChave = tipos;

        // A ordem em si vem de config.ordem_secoes (lista de chaves), não da
        // ordem devolvida por listarCamposOrdenaveis() — essa é só o
        // catálogo.
        var ordem = config.ordem_secoes || [];
        modeloOrdemSecoes.clear();
        for (var k = 0; k < ordem.length; k++) {
            modeloOrdemSecoes.append({
                "chave": ordem[k],
                "rotulo": rotulos[ordem[k]] || ordem[k]
            });
        }

        raiz.espacamentoSecoes = config.espacamento_secoes !== undefined ? config.espacamento_secoes : 1;
        raiz.espacamentoCorte = config.espacamento_corte !== undefined ? config.espacamento_corte : 4;
        raiz.linhasSeparadorPadrao = config.linhas_separador !== undefined ? config.linhas_separador : 1;
        // Cópia, não a referência de dentro de configAtual: as exceções são
        // editadas por reatribuição (definirExcecaoSeparador) e não devem
        // mexer no dict que veio do Python.
        var excecoes = {};
        var lidas = config.separadores_campo || {};
        for (var chaveExcecao in lidas)
            excecoes[chaveExcecao] = lidas[chaveExcecao];
        raiz.separadoresPorCampo = excecoes;

        raiz.chaveSelecionada = "";
        raiz.donoSelecionado = "";
        // Só depois do laço de append(): durante ele o count cresce aos
        // poucos e o cálculo sairia sobre um modelo pela metade.
        raiz.recalcularSeparadores();

        // A prévia inteira precisa se reler: acabou de chegar outra
        // configuração (abrir a tela, ou "Restaurar padrões").
        raiz.versaoConfig += 1;
        // Por último: escrever os espaçamentos acima disparou
        // onEspacamentoSecoesChanged/onEspacamentoCorteChanged, e o que acabou
        // de ser lido do disco não é uma edição pendente.
        raiz.alteracoesPendentes = false;
    }

    function categoriaDe(chave) {
        return raiz.categoriasPorChave[chave] || "";
    }

    // Espelha comandaEstiloService.linhas_separador_antes: quantas linhas de
    // traço vêm ANTES de `chaveAtual`. Uma exceção gravada para o campo manda
    // sozinha — inclusive um 0 (tira a divisória que a categoria pediria) e
    // inclusive na primeira linha da comanda.
    function linhasTracoAntes(chaveAnterior, chaveAtual) {
        var excecao = raiz.separadoresPorCampo[chaveAtual];
        if (excecao !== undefined)
            return excecao;

        if (chaveAnterior === "")
            return 0;

        return raiz.categoriaDe(chaveAtual) !== raiz.categoriaDe(chaveAnterior) ? raiz.linhasSeparadorPadrao : 0;
    }

    // Espelha a regra de separadores de
    // comandaTextoService.montar_linhas_por_ordem. Função pura de duas
    // chaves: devolve a divisória que vem ANTES de `chaveAtual`.
    // A tabela de itens é cercada pelo marcador "=" dos DOIS lados — daí o
    // teste também olhar `chaveAnterior`.
    function separadorEntre(chaveAnterior, chaveAtual) {
        // A tabela de itens vem antes de tudo de propósito: no Python o ramo
        // `if eh_itens or itens_anterior` nem consulta
        // linhas_separador_antes, então essas duas posições ignoram a
        // espessura configurada e qualquer exceção — o marcador sai sempre
        // uma vez só (é assim que consultaController.reconstruirComanda acha
        // a tabela depois). A guarda de "primeira linha" também fica de fora:
        // a tabela ganha o marcador de abertura mesmo sendo a primeira coisa
        // da comanda.
        if (chaveAtual === "itens" || chaveAnterior === "itens")
            return { "tipo": "=", "linhas": 1 };

        var tracos = raiz.linhasTracoAntes(chaveAnterior, chaveAtual);
        return { "tipo": tracos > 0 ? "-" : "", "linhas": tracos };
    }

    // Se este campo tem exceção gravada, ou está seguindo a regra automática.
    function temExcecaoSeparador(chave) {
        return chave !== "" && raiz.separadoresPorCampo[chave] !== undefined;
    }

    // Posição cuja divisória é o marcador da tabela de itens: não tem
    // espessura ajustável (ver separadorEntre acima).
    function separadorFixo(chave) {
        var indice = raiz.indiceDaChave(chave);
        if (indice < 0)
            return false;

        var divisoria = raiz.separadores[indice];
        return !!divisoria && divisoria.tipo === "=";
    }

    // Quantos traços a posição de `chave` mostra hoje — venha de exceção ou
    // da regra automática. É o número que os botões +/- da prévia partem.
    function linhasTracoDe(chave) {
        var indice = raiz.indiceDaChave(chave);
        if (indice < 0)
            return 0;

        var divisoria = raiz.separadores[indice];
        return divisoria && divisoria.tipo === "-" ? divisoria.linhas : 0;
    }

    // Muda a espessura padrão das divisórias. Precisa recalcular à mão: os
    // separadores são um array já computado (ver recalcularSeparadores), não
    // uma binding que reavaliaria sozinha ao ler linhasSeparadorPadrao.
    function definirLinhasSeparadorPadrao(valor) {
        raiz.linhasSeparadorPadrao = Math.max(0, Math.min(raiz.maxLinhasSeparador, valor));
        raiz.marcarPendente();
        raiz.recalcularSeparadores();
    }

    // Grava (ou apaga, com `valor` negativo) a exceção de `chave`. Reatribui
    // o objeto inteiro em vez de mutá-lo: é isso que emite
    // separadoresPorCampoChanged e faz a prévia reavaliar.
    function definirExcecaoSeparador(chave, valor) {
        if (chave === "")
            return;

        var novo = {};
        for (var k in raiz.separadoresPorCampo)
            novo[k] = raiz.separadoresPorCampo[k];

        if (valor < 0)
            delete novo[chave];
        else
            novo[chave] = Math.min(raiz.maxLinhasSeparador, valor);

        raiz.separadoresPorCampo = novo;
        raiz.marcarPendente();
        raiz.recalcularSeparadores();
    }

    // Chamada de forma SÍNCRONA por quem mexe na ordem (nunca via
    // Qt.callLater, que renderizaria um frame com os índices já novos e os
    // separadores ainda velhos).
    function recalcularSeparadores() {
        var novo = [];
        var anterior = "";
        for (var i = 0; i < modeloOrdemSecoes.count; i++) {
            var chave = modeloOrdemSecoes.get(i).chave;
            novo.push(raiz.separadorEntre(anterior, chave));
            anterior = chave;
        }
        raiz.separadores = novo;
        raiz.ultimaChaveOrdem = anterior;
    }

    function indiceDaChave(chave) {
        for (var i = 0; i < modeloOrdemSecoes.count; i++) {
            if (modeloOrdemSecoes.get(i).chave === chave)
                return i;
        }
        return -1;
    }

    // Troca de posição a linha `indice` do modeloOrdemSecoes com sua
    // vizinha (indice + delta) e reflete a nova ordem em
    // configAtual.ordem_secoes — só em memória, igual ao resto desta tela
    // (ver salvarNoBackend()).
    function moverCampoOrdem(indice, delta) {
        var novoIndice = indice + delta;
        if (novoIndice < 0 || novoIndice >= modeloOrdemSecoes.count)
            return;

        modeloOrdemSecoes.move(indice, novoIndice, 1);

        var nova = [];
        for (var i = 0; i < modeloOrdemSecoes.count; i++)
            nova.push(modeloOrdemSecoes.get(i).chave);
        raiz.configAtual.ordem_secoes = nova;
        raiz.marcarPendente();
        raiz.recalcularSeparadores();
    }

    function moverSelecionado(delta) {
        if (raiz.donoSelecionado === "")
            return;

        var indice = raiz.indiceDaChave(raiz.donoSelecionado);
        if (indice >= 0)
            raiz.moverCampoOrdem(indice, delta);
    }

    function selecionar(chave, dono) {
        raiz.chaveSelecionada = chave;
        raiz.donoSelecionado = dono;
        cartaoComanda.forceActiveFocus(Qt.MouseFocusReason);
    }

    function podeEstilizar(chave) {
        // "itens" e "divisao_conta" são âncoras de posição puras: existem no
        // catálogo de ordenáveis, mas não em CAMPOS (não têm atributos de
        // estilo próprios). O que tem estilo ali dentro são as sub-linhas.
        return chave !== "" && chave !== "itens" && chave !== "divisao_conta";
    }

    function campoNoTipo(chave, tipo) {
        var lista = raiz.tiposPorChave[chave];
        if (!lista)
            return true;

        for (var i = 0; i < lista.length; i++) {
            if (lista[i] === tipo)
                return true;
        }
        return false;
    }

    function rotuloDe(chave) {
        return raiz.rotulosPorChave[chave] || chave;
    }

    function repetir(caractere) {
        var texto = "";
        for (var i = 0; i < raiz.colunasPapel; i++)
            texto += caractere;
        return texto;
    }

    // Cada linha do papel é uma lista de segmentos {t: texto, c: campo de
    // estilo ou ""}. Um campo comum vira uma linha só, com o prefixo sem
    // estilo e o valor estilizado; a tabela de itens e a divisão da conta
    // viram vários. `campoEstilo` é o que o clique naquela sub-linha
    // seleciona ("" = a sub-linha não tem estilo próprio, então o clique
    // seleciona a linha ordenável dona dela).
    function linhasDoCampo(chave) {
        if (chave === "itens") {
            return [
                { "campoEstilo": "pedido", "segmentos": [{ "t": "- PIZZA G. CALABRESA (GRANDE) | R$ 45,00", "c": "pedido" }] },
                { "campoEstilo": "adicional_item", "segmentos": [{ "t": "  + BACON (R$ 5,00)", "c": "adicional_item" }] },
                { "campoEstilo": "borda_item", "segmentos": [{ "t": "  * BORDA CATUPIRY (R$ 8,00)", "c": "borda_item" }] },
                { "campoEstilo": "observacao_item", "segmentos": [{ "t": "  SEM CEBOLA", "c": "observacao_item" }] }
            ];
        }

        if (chave === "divisao_conta") {
            // salaoController monta cada linha de divisão com o nome no
            // estilo de "cliente" e o status no estilo de "status" — daí os
            // segmentos misturados. Nenhuma das duas linhas tem estilo
            // próprio (campoEstilo vazio): clicar nelas seleciona o bloco.
            return [
                { "campoEstilo": "", "segmentos": [{ "t": "DIVISÃO DA CONTA", "c": "" }] },
                { "campoEstilo": "", "segmentos": [
                    { "t": "João", "c": "cliente" },
                    { "t": ": R$ 22,50 [Pix] [", "c": "" },
                    { "t": "PG", "c": "status" },
                    { "t": "]", "c": "" }
                ] }
            ];
        }

        var exemplo = raiz.exemplos[chave];
        if (!exemplo)
            return [];

        return [{ "campoEstilo": chave, "segmentos": [
            { "t": exemplo.prefixo, "c": "" },
            { "t": exemplo.valor, "c": chave }
        ] }];
    }

    // São seis chamadas seguidas ao comandaEstiloController mais a montagem
    // dos rótulos dos 18 campos — tudo antes do primeiro pixel, se rodasse
    // direto daqui (ver components/CargaDiferida.qml).
    CargaDiferida {
        id: carga

        tarefa: function() {
            carregarConfiguracao();
        }
    }

    Component.onCompleted: carga.agendar()
    // Cobre o caso de a Page ser realmente destruída (botão Voltar, botão
    // Início, fechar o app) — o caso de "empurrada pra baixo na pilha por
    // outra tela da barra lateral" (sem ser destruída) é coberto por
    // StackView.onDeactivated em ../Configuracoes.qml, já que este item
    // continua vivo nesse caso.
    // Rede de segurança para o fim da vida da tela (Voltar, Início, fechar o
    // app): fechar o app não dá chance de perguntar nada, e perder o que foi
    // editado é pior que gravar. Só grava se houver pendência — sem essa
    // guarda, toda saída de Configurações regravava o arquivo e publicava a
    // configuração inteira na malha, mesmo sem ninguém ter mexido em nada.
    Component.onDestruction: {
        if (raiz.alteracoesPendentes)
            raiz.salvarNoBackend();
    }

    ListModel {
        id: modeloOrdemSecoes
    }

    // Mede uma linha cheia do papel (40 colunas) na fonte monoespaçada da
    // prévia — de onde saem a largura do papel e a altura de uma linha em
    // branco, em vez de números mágicos que descolariam da fonte.
    TextMetrics {
        id: metricaPapel

        font.family: "monospace"
        font.pixelSize: raiz.tamanhoBasePapel
        text: raiz.repetir("0")
    }

    // --- CABEÇALHO DA SEÇÃO + RESTAURAR PADRÕES ---
    RowLayout {
        width: raiz.width
        spacing: Estilo.global.spacing.xl

        Row {
            spacing: Estilo.global.spacing.sm
            Icone { nome: "fa6s.receipt"; cor: raiz.corDestaque; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "MODELO DA COMANDA IMPRESSA"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: raiz.corDestaque
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Item {
            Layout.fillWidth: true
        }

        Button {
            id: btnRestaurar

            padding: 8
            focusPolicy: Qt.NoFocus
            onClicked: {
                comandaEstiloController.restaurarPadroes();
                raiz.carregarConfiguracao();
            }

            contentItem: Row {
                spacing: Estilo.global.spacing.xs
                Icone { nome: "fa6s.arrow-rotate-left"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "Restaurar padrões"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
            }
        }
    }

    // --- CARTÃO DA COMANDA INTERATIVA ---
    Rectangle {
        id: cartaoComanda

        width: parent.width
        height: colunaCartao.implicitHeight + Estilo.global.padding.xl * 2
        radius: Estilo.global.radius.lg
        color: Estilo.global.surface
        // Anel de foco na convenção do resto do app (border.width 2 quando
        // focado): comunica que as setas do teclado agora controlam ESTE
        // cartão. A linha selecionada usa outra afordância (fundo + barra de
        // acento à esquerda) pros dois estados não se confundirem.
        border.color: activeFocus ? raiz.corDestaque : Estilo.global.borderCard
        border.width: activeFocus ? 2 : 1
        activeFocusOnTab: true

        // As setas ficam AQUI, não em `raiz`: raiz é o contentItem do
        // Flickable de ../Configuracoes.qml, então dar foco a ele tornaria
        // ↑/↓ globais — quem estivesse ajustando "linhas em branco antes do
        // corte" lá embaixo reordenaria a comanda sem querer.
        Keys.onUpPressed: function (evento) {
            raiz.moverSelecionado(-1);
            evento.accepted = true;
        }
        Keys.onDownPressed: function (evento) {
            raiz.moverSelecionado(1);
            evento.accepted = true;
        }
        Keys.onEscapePressed: function (evento) {
            raiz.chaveSelecionada = "";
            raiz.donoSelecionado = "";
            evento.accepted = true;
        }

        Column {
            id: colunaCartao

            anchors.fill: parent
            anchors.margins: Estilo.global.padding.xl
            spacing: Estilo.global.spacing.lg

            // --- Barra de controles ---
            RowLayout {
                width: parent.width
                spacing: Estilo.global.spacing.xxl

                // Seletor de tipo de comanda: troca quais campos aparecem
                // acesos, porque nenhuma comanda real usa os 16 ao mesmo
                // tempo (Balcão não tem endereço, Mesa não tem telefone).
                Row {
                    spacing: Estilo.global.spacing.xs
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        text: "Tipo:"
                        font.pixelSize: Estilo.global.fontSize.md
                        color: Estilo.global.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Repeater {
                        model: raiz.tiposComanda

                        delegate: Button {
                            id: botaoTipo

                            required property string modelData

                            readonly property bool _ativo: raiz.tipoComanda === botaoTipo.modelData

                            padding: Estilo.global.padding.sm
                            focusPolicy: Qt.NoFocus
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: raiz.tipoComanda = botaoTipo.modelData

                            contentItem: Text {
                                text: botaoTipo.modelData
                                font.pixelSize: Estilo.global.fontSize.md
                                font.family: Estilo.global.fontFamily.title
                                color: botaoTipo._ativo ? Estilo.global.textOnAccent : Estilo.global.text
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            background: Rectangle {
                                radius: Estilo.global.radius.pill
                                color: botaoTipo._ativo ? raiz.corDestaque : (botaoTipo.hovered ? Estilo.global.surfaceHover : Estilo.global.surface)
                                border.color: botaoTipo._ativo ? raiz.corDestaque : Estilo.global.border
                                border.width: Estilo.global.borderWidth.hairline
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            Text {
                width: parent.width
                text: raiz.chaveSelecionada === "" ? "Clique numa linha da comanda para selecioná-la; os controles aparecem ao lado dela — as setas mudam a posição, e \"Estilo…\" abre negrito, sublinhado, fundo preto e tamanho da fonte." :("Selecionado: " + raiz.rotuloDe(raiz.chaveSelecionada) + (raiz.donoSelecionado !== raiz.chaveSelecionada ? " — as setas movem a " + raiz.rotuloDe(raiz.donoSelecionado).toLowerCase() + " inteira." : ""))
                font.pixelSize: Estilo.global.fontSize.sm
                color: Estilo.global.textSecondary
                wrapMode: Text.WordWrap
            }

            // --- Papel + painel de espaçamento, lado a lado ---
            // Duas colunas quando a tela dá conta das duas larguras, uma só
            // (painel embaixo do papel) quando não dá. A tela de Configurações
            // não rola na horizontal (contentWidth: width no Flickable de
            // ../Configuracoes.qml), então sem esse recuo o painel
            // simplesmente sumiria pela borda direita numa janela estreita.
            //
            // `columns` só pode depender de larguras que NÃO saiam deste
            // layout, senão vira loop de binding: faixaPapel mede o papel (que
            // vem da métrica da fonte) e os controles, e painelEspacamento tem
            // largura própria — nenhum dos dois estica com a coluna.
            GridLayout {
                id: grade

                // Sem width: parent.width de propósito — o layout fica do
                // tamanho do conteúdo. Esticado até a borda do cartão ele
                // reparte a sobra entre as células, e o painel descolava do
                // papel (as duas colunas ficavam maiores que os itens dentro
                // delas, mesmo com os itens travados no próprio tamanho).
                columns: raiz.width >= faixaPapel.implicitWidth + columnSpacing + painelEspacamento.implicitWidth ? 2 : 1
                columnSpacing: Estilo.global.spacing.xxl
                rowSpacing: Estilo.global.spacing.xxl

                // Reserva a faixa dos controles flutuantes junto do papel: eles
                // moram AQUI dentro (não no cartão), então a largura da coluna
                // já os inclui e o painel ao lado nunca cai por cima deles.
                Item {
                    id: faixaPapel

                    implicitWidth: papel.width + Estilo.global.spacing.lg + controlesLinha.implicitWidth
                    implicitHeight: papel.height
                    Layout.alignment: Qt.AlignTop

                    Rectangle {
                        id: papel

                        anchors.left: parent.left
                        anchors.top: parent.top
                        width: Math.ceil(metricaPapel.width) + 30
                        height: colunaPapel.implicitHeight + 24
                        radius: Estilo.global.radius.xs
                        color: Estilo.printer.paper
                        border.color: Estilo.printer.paperBorder
                        // Campos com fonte bem maior (multiplicador alto) podem ficar
                        // mais largos que o papel — contém em vez de vazar
                        // visualmente pra fora do cartão.
                        clip: true

                        Column {
                            id: colunaPapel

                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.topMargin: 12
                            width: parent.width - 20
                            // Zero de propósito: o espaçamento entre seções da
                            // comanda é dado por linhas em branco de verdade (as
                            // mesmas que o Python emite), não por spacing do
                            // Positioner — senão a prévia mostraria um respiro que
                            // não existe no papel.
                            spacing: 0

                            // Só `move`: `add` faria a comanda inteira animar
                            // entrando a cada vez que a tela abre e a cada
                            // "Restaurar padrões", porque carregarConfiguracao()
                            // faz clear() + 16 append(). Anima só y (nunca height:
                            // animar altura faz o contentHeight do Flickable de fora
                            // tremer junto com a barra de rolagem).
                            move: Transition {
                                NumberAnimation {
                                    property: "y"
                                    duration: Estilo.global.motion.fast
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Repeater {
                                model: modeloOrdemSecoes

                                delegate: Column {
                                    id: linhaOrdem

                                    // required é tudo-ou-nada: declarar qualquer
                                    // propriedade required num delegate faz o Qt
                                    // parar de injetar "model" (e os nomes dos
                                    // papéis) como propriedade de contexto. Como aqui
                                    // ainda há um Repeater aninhado (as sub-linhas),
                                    // esse é o modo certo — evita que o "model" de
                                    // dentro esconda o de fora.
                                    required property int index
                                    required property string chave
                                    required property string rotulo

                                    readonly property var _separador: raiz.separadores[linhaOrdem.index] || ({ "tipo": "", "linhas": 0 })
                                    readonly property bool _noTipo: raiz.campoNoTipo(linhaOrdem.chave, raiz.tipoComanda)

                                    width: colunaPapel.width
                                    spacing: 0
                                    // Campo que este tipo de comanda não imprime:
                                    // continua visível e movível, só apagado.
                                    opacity: linhaOrdem._noTipo ? 1 : Estilo.global.opacity.muted

                                    SeparadorPapel {
                                        largura: linhaOrdem.width
                                        separador: linhaOrdem._separador.tipo
                                        repeticoes: linhaOrdem._separador.linhas
                                        linhasEmBranco: raiz.espacamentoSecoes
                                        alturaLinha: metricaPapel.height
                                        tamanhoFonte: raiz.tamanhoBasePapel
                                        traco: raiz.repetir("-")
                                        marcador: raiz.repetir("=")
                                    }

                                    Repeater {
                                        model: raiz.linhasDoCampo(linhaOrdem.chave)

                                        delegate: Item {
                                            id: subLinha

                                            required property var modelData
                                            required property int index

                                            // Sub-linha sem estilo próprio (as da
                                            // divisão da conta) devolve o clique pro
                                            // bloco que a contém.
                                            readonly property string _campoClique: subLinha.modelData.campoEstilo !== "" ? subLinha.modelData.campoEstilo : linhaOrdem.chave
                                            readonly property bool _selecionada: raiz.chaveSelecionada === subLinha._campoClique
                                            // Quem posiciona os controles flutuantes.
                                            // Nas sub-linhas sem estilo próprio o
                                            // _campoClique é o mesmo para todas (o
                                            // bloco inteiro acende junto), então sem
                                            // este filtro haveria dois Bindings
                                            // disputando yLinhaSelecionada — os
                                            // botões ficariam na linha que o Qt
                                            // avaliasse por último. A primeira do
                                            // bloco vence.
                                            readonly property bool _ancora: subLinha.modelData.campoEstilo !== "" || subLinha.index === 0

                                            width: linhaOrdem.width
                                            height: Math.max(metricaPapel.height, conteudoSubLinha.implicitHeight)

                                            Binding {
                                                when: subLinha._selecionada && subLinha._ancora
                                                target: raiz
                                                property: "yLinhaSelecionada"
                                                value: colunaPapel.y + linhaOrdem.y + subLinha.y
                                                restoreMode: Binding.RestoreNone
                                            }

                                            Binding {
                                                when: subLinha._selecionada && subLinha._ancora
                                                target: raiz
                                                property: "alturaLinhaSelecionada"
                                                value: subLinha.height
                                                restoreMode: Binding.RestoreNone
                                            }

                                            Rectangle {
                                                anchors.fill: parent
                                                anchors.leftMargin: -6
                                                anchors.rightMargin: -6
                                                radius: Estilo.global.radius.xs
                                                color: subLinha._selecionada ? Estilo.screen.config.softStrong : (areaSubLinha.containsMouse ? Estilo.screen.config.soft : "transparent")
                                            }

                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.leftMargin: -6
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 3
                                                height: parent.height
                                                radius: Estilo.global.radius.xs
                                                color: raiz.corDestaque
                                                visible: subLinha._selecionada
                                            }

                                            Row {
                                                id: conteudoSubLinha

                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 0

                                                Repeater {
                                                    model: subLinha.modelData.segmentos

                                                    delegate: Item {
                                                        id: segmento

                                                        required property var modelData

                                                        width: segmento.modelData.c === "" ? textoSimples.implicitWidth : campoEstilizado.implicitWidth
                                                        height: segmento.modelData.c === "" ? textoSimples.implicitHeight : campoEstilizado.implicitHeight

                                                        // Trecho sem estilo configurável (o rótulo
                                                        // "Cliente: ", os colchetes da divisão).
                                                        Text {
                                                            id: textoSimples

                                                            visible: segmento.modelData.c === ""
                                                            text: segmento.modelData.t
                                                            font.family: "monospace"
                                                            font.pixelSize: raiz.tamanhoBasePapel
                                                            color: Estilo.printer.ink
                                                        }

                                                        PreviaCampoTexto {
                                                            id: campoEstilizado

                                                            visible: segmento.modelData.c !== ""
                                                            controlador: raiz
                                                            campo: segmento.modelData.c
                                                            texto: segmento.modelData.t
                                                            tamanhoBase: raiz.tamanhoBasePapel
                                                        }
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: areaSubLinha

                                                anchors.fill: parent
                                                anchors.leftMargin: -6
                                                anchors.rightMargin: -6
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: raiz.selecionar(subLinha._campoClique, linhaOrdem.chave)
                                                // Atalho: quem já sabe o que quer
                                                // mexer chega no popup direto.
                                                onDoubleClicked: {
                                                    raiz.selecionar(subLinha._campoClique, linhaOrdem.chave);
                                                    if (raiz.podeEstilizar(subLinha._campoClique))
                                                        popupEstiloCampo.abrirPara(subLinha._campoClique, raiz.rotuloDe(subLinha._campoClique));
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Marcador de fechamento da tabela de itens quando ela é
                            // o ÚLTIMO campo da ordem — o único separador que não
                            // vem "antes de alguém" (ver ultimaChaveOrdem).
                            SeparadorPapel {
                                largura: colunaPapel.width
                                separador: raiz.ultimaChaveOrdem === "itens" ? "=" : ""
                                linhasEmBranco: raiz.espacamentoSecoes
                                alturaLinha: metricaPapel.height
                                tamanhoFonte: raiz.tamanhoBasePapel
                                traco: raiz.repetir("-")
                                marcador: raiz.repetir("=")
                            }
                        }
                        }

                    // --- Controles da linha selecionada ---
                    // Irmão do papel dentro de faixaPapel, não filho dele: o
                    // papel tem clip: true e cortaria os botões, fora que eles
                    // tapariam o texto do cupom. Como o papel está ancorado em
                    // (0,0) desta faixa, as coordenadas aqui saem diretas —
                    // yLinhaSelecionada já é medido dentro do papel.
                    Column {
                        id: controlesLinha
    
                        readonly property int _lado: 34

                        spacing: Estilo.global.spacing.sm
                        visible: raiz.chaveSelecionada !== ""
                        x: papel.width + Estilo.global.spacing.lg
                        y: raiz.yLinhaSelecionada + (raiz.alturaLinhaSelecionada - height) / 2

                        // Sem Behavior on y aqui, de propósito. O deslizar ao reordenar já
                        // vem de graça: quem anima é o campo dentro do papel (a Transition
                        // de move em colunaPapel), e como yLinhaSelecionada é a soma dos y
                        // dessa cadeia, este binding acompanha quadro a quadro. Um Behavior
                        // por cima disso não só era redundante como quebrava o
                        // posicionamento: a animação dele escreve em y enquanto o binding
                        // ainda está reavaliando (yLinhaSelecionada chega em duas etapas,
                        // conforme o layout do papel assenta), e essa escrita derruba o
                        // binding — os botões congelavam na primeira posição intermediária
                        // e nunca mais achavam a linha.

                        // focusPolicy: Qt.NoFocus em todos os botões daqui: sem isso o
                        // Button do Controls 2 rouba o activeFocus no clique, o cartão
                        // perde o anel e as setas do teclado param de funcionar logo
                        // depois do primeiro clique no ▲.
                        Row {
                            spacing: Estilo.global.spacing.xs

                            Button {
                                width: controlesLinha._lado
                                height: controlesLinha._lado
                                focusPolicy: Qt.NoFocus
                                enabled: raiz.donoSelecionado !== ""
                                opacity: enabled ? 1 : Estilo.global.opacity.disabled
                                onClicked: raiz.moverSelecionado(-1)

                                contentItem: Icone {
                                    nome: "fa6s.chevron-up"
                                    cor: raiz.corDestaque
                                    tamanho: 13
                                    anchors.centerIn: parent
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                                    border.color: Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }
                            }

                            Button {
                                width: controlesLinha._lado
                                height: controlesLinha._lado
                                focusPolicy: Qt.NoFocus
                                enabled: raiz.donoSelecionado !== ""
                                opacity: enabled ? 1 : Estilo.global.opacity.disabled
                                onClicked: raiz.moverSelecionado(1)

                                contentItem: Icone {
                                    nome: "fa6s.chevron-down"
                                    cor: raiz.corDestaque
                                    tamanho: 13
                                    anchors.centerIn: parent
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                                    border.color: Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }
                            }

                            Button {
                                id: btnEstilo

                                height: controlesLinha._lado
                                padding: Estilo.global.padding.md
                                focusPolicy: Qt.NoFocus
                                enabled: raiz.podeEstilizar(raiz.chaveSelecionada)
                                opacity: enabled ? 1 : Estilo.global.opacity.disabled
                                onClicked: popupEstiloCampo.abrirPara(raiz.chaveSelecionada, raiz.rotuloDe(raiz.chaveSelecionada))

                                contentItem: Row {
                                    spacing: Estilo.global.spacing.xs
                                    Icone { nome: "fa6s.pen"; cor: Estilo.global.textOnAccent; tamanho: 12; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: "Estilo…"
                                        font.pixelSize: Estilo.global.fontSize.md
                                        font.family: Estilo.global.fontFamily.title
                                        color: Estilo.global.textOnAccent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.screen.config.pressed : (parent.hovered ? Estilo.screen.config.hover : raiz.corDestaque)
                                }
                            }
                        }

                        // --- Traços da divisória ACIMA desta linha ---
                        // Mexe sempre no dono (a linha ordenável), nunca na sub-linha:
                        // uma linha da tabela de itens não tem divisória própria, quem
                        // tem é a tabela.
                        Row {
                            id: ajusteTracos

                            readonly property bool _fixo: raiz.separadorFixo(raiz.donoSelecionado)
                            readonly property int _atual: raiz.linhasTracoDe(raiz.donoSelecionado)

                            spacing: Estilo.global.spacing.xs

                            Text {
                                text: "Traços acima:"
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.textSecondary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Button {
                                width: 26
                                height: 26
                                focusPolicy: Qt.NoFocus
                                anchors.verticalCenter: parent.verticalCenter
                                enabled: !ajusteTracos._fixo && ajusteTracos._atual > 0
                                opacity: enabled ? 1 : Estilo.global.opacity.disabled
                                onClicked: raiz.definirExcecaoSeparador(raiz.donoSelecionado, ajusteTracos._atual - 1)

                                contentItem: Text {
                                    text: "−"
                                    font.pixelSize: Estilo.global.fontSize.lg
                                    font.family: Estilo.global.fontFamily.title
                                    color: Estilo.global.text
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                                    border.color: Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }
                            }

                            Text {
                                // "fixo" nas duas bordas da tabela de itens, onde a
                                // divisória é o marcador "=" e não tem espessura
                                // ajustável (ver separadorEntre).
                                width: 24
                                text: ajusteTracos._fixo ? "—" : ajusteTracos._atual
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Estilo.global.fontSize.md
                                // Negrito só quando este campo tem exceção gravada: é o
                                // que distingue "eu escolhi este número aqui" de "está
                                // seguindo o padrão de ESPAÇAMENTO lá embaixo".
                                font.bold: raiz.temExcecaoSeparador(raiz.donoSelecionado)
                                color: Estilo.global.text
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Button {
                                width: 26
                                height: 26
                                focusPolicy: Qt.NoFocus
                                anchors.verticalCenter: parent.verticalCenter
                                enabled: !ajusteTracos._fixo && ajusteTracos._atual < raiz.maxLinhasSeparador
                                opacity: enabled ? 1 : Estilo.global.opacity.disabled
                                onClicked: raiz.definirExcecaoSeparador(raiz.donoSelecionado, ajusteTracos._atual + 1)

                                contentItem: Text {
                                    text: "+"
                                    font.pixelSize: Estilo.global.fontSize.lg
                                    font.family: Estilo.global.fontFamily.title
                                    color: Estilo.global.text
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                                    border.color: Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }
                            }

                            // Só aparece quando há exceção — no caso comum (tudo
                            // automático) não ocupa espaço nem pede explicação.
                            Button {
                                width: 26
                                height: 26
                                focusPolicy: Qt.NoFocus
                                anchors.verticalCenter: parent.verticalCenter
                                visible: raiz.temExcecaoSeparador(raiz.donoSelecionado)
                                onClicked: raiz.definirExcecaoSeparador(raiz.donoSelecionado, -1)

                                contentItem: Icone {
                                    nome: "fa6s.arrow-rotate-left"
                                    cor: Estilo.global.textSecondary
                                    tamanho: 11
                                    anchors.centerIn: parent
                                }

                                ToolTip {
                                    text: "Voltar ao padrão automático"
                                    visible: parent.hovered
                                    delay: 400
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                                    border.color: Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }
                            }
                        }
                    }
                }

                // --- Painel de espaçamento (2ª coluna) ---
                Rectangle {
                    id: painelEspacamento

                    // Largura própria, não Layout.fillWidth: é ela que
                    // `columns` mede pra saber se as duas colunas cabem, e
                    // esticar com a coluna realimentaria essa conta.
                    implicitWidth: colunaEspacamento.implicitWidth + Estilo.global.padding.xl * 2
                    implicitHeight: colunaEspacamento.implicitHeight + Estilo.global.padding.xl * 2
                    Layout.alignment: Qt.AlignTop
                    radius: Estilo.global.radius.lg
                    color: Estilo.global.surface
                    border.color: Estilo.global.borderCard
                    border.width: Estilo.global.borderWidth.hairline

                    Column {
                        id: colunaEspacamento

                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: Estilo.global.padding.xl
                        spacing: Estilo.global.spacing.xl

                        Text {
                            text: "ESPAÇAMENTO"
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.bold: true
                            color: raiz.corDestaque
                        }

                        // Linhas em branco entre seções da comanda
                        Row {
                            spacing: Estilo.global.spacing.xl

                            Text {
                                width: 300
                                text: "Linhas em branco entre seções da comanda"
                                font.pixelSize: Estilo.global.fontSize.md
                                color: Estilo.global.text
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Button {
                                text: "-"
                                width: 32
                                height: 32
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: {
                                    if (raiz.espacamentoSecoes > 0)
                                        raiz.espacamentoSecoes -= 1;
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                                    border.color: Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }
                            }

                            Text {
                                width: 30
                                text: raiz.espacamentoSecoes
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Estilo.global.fontSize.lg
                                font.bold: true
                                color: Estilo.global.text
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Button {
                                text: "+"
                                width: 32
                                height: 32
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: raiz.espacamentoSecoes += 1

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                                    border.color: Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }
                            }
                        }

                        // Espessura padrão das divisórias tracejadas. É só o PADRÃO: uma
                        // linha com exceção gravada pelos botões da prévia ignora este
                        // número (ver linhasTracoAntes).
                        Row {
                            spacing: Estilo.global.spacing.xl

                            Text {
                                width: 300
                                text: "Linhas tracejadas em cada divisória"
                                font.pixelSize: Estilo.global.fontSize.md
                                color: Estilo.global.text
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Button {
                                text: "-"
                                width: 32
                                height: 32
                                anchors.verticalCenter: parent.verticalCenter
                                enabled: raiz.linhasSeparadorPadrao > 0
                                opacity: enabled ? 1 : Estilo.global.opacity.disabled
                                onClicked: raiz.definirLinhasSeparadorPadrao(raiz.linhasSeparadorPadrao - 1)

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                                    border.color: Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }
                            }

                            Text {
                                width: 30
                                text: raiz.linhasSeparadorPadrao
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Estilo.global.fontSize.lg
                                font.bold: true
                                color: Estilo.global.text
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Button {
                                text: "+"
                                width: 32
                                height: 32
                                anchors.verticalCenter: parent.verticalCenter
                                enabled: raiz.linhasSeparadorPadrao < raiz.maxLinhasSeparador
                                opacity: enabled ? 1 : Estilo.global.opacity.disabled
                                onClicked: raiz.definirLinhasSeparadorPadrao(raiz.linhasSeparadorPadrao + 1)

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                                    border.color: Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }
                            }
                        }

                        // Linhas em branco antes do corte automático
                        Row {
                            spacing: Estilo.global.spacing.xl

                            Text {
                                width: 300
                                text: "Linhas em branco antes do corte automático"
                                font.pixelSize: Estilo.global.fontSize.md
                                color: Estilo.global.text
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Button {
                                text: "-"
                                width: 32
                                height: 32
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: {
                                    if (raiz.espacamentoCorte > 0)
                                        raiz.espacamentoCorte -= 1;
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                                    border.color: Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }
                            }

                            Text {
                                width: 30
                                text: raiz.espacamentoCorte
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Estilo.global.fontSize.lg
                                font.bold: true
                                color: Estilo.global.text
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Button {
                                text: "+"
                                width: 32
                                height: 32
                                anchors.verticalCenter: parent.verticalCenter
                                onClicked: raiz.espacamentoCorte += 1

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                                    border.color: Estilo.global.border
                                    border.width: Estilo.global.borderWidth.hairline
                                }
                            }
                        }
                    }
                }
            }
        }

    }

    PopupEstiloCampo {
        id: popupEstiloCampo

        controlador: raiz
    }

}
