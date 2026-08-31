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
    // Faixa aceita pro tamanho em pixels, espelhada do Python
    // (comandaEstiloService.TAMANHO_FONTE_MIN_PX/MAX_PX) como o padrão acima:
    // quem edita é o PopupEstiloCampo, e ele conversa com esta tela, não com o
    // controller.
    property int tamanhoFonteMin: 8
    property int tamanhoFonteMax: 200
    // Família da fonte usada pra DESENHAR a comanda. Vazio = a fonte da própria
    // impressora, que é o padrão: nesse caso o cupom sai como texto, do jeito
    // de sempre. Com uma família escolhida, a comanda passa a ser desenhada
    // como imagem antes de ser enviada (ver services/comandaImagemService.py).
    property string fonteImpressao: ""
    // Catálogo vindo do Python ([{chave, rotulo}]) — a opção padrão seguida
    // das famílias da máquina que IMPRIME (ver comandaEstiloController.
    // listarFontes), que não é necessariamente esta.
    property var fontesDisponiveis: []
    // De onde veio esse catálogo: {maquina, local, conhecida}. Só serve pra
    // tela explicar a lista; a escolha em si não depende dele.
    property var origemFontes: ({
        "maquina": "",
        "local": false,
        "conhecida": false
    })
    // A família escolhida existe NESTA máquina? A lista oferecida é a da
    // máquina que imprime (ver listarFontes), que pode ser outra — e o Qt
    // substitui calado uma fonte que não tem. Sem esta checagem a prévia
    // mostraria uma tipografia que não é nem a da tela nem a do papel.
    // Reconsultada a cada troca de fonte, e não por binding: é uma chamada
    // ao Python, não um valor que muda sozinho.
    property bool fonteExisteAqui: false

    // A família que a prévia usa de fato. Cai na monoespaçada quando não há
    // fonte escolhida (aí quem desenha é a impressora, com a fonte dela) ou
    // quando esta máquina não tem a escolhida.
    readonly property string fontePrevia: raiz.fonteImpressao !== "" && raiz.fonteExisteAqui ? raiz.fonteImpressao : "monospace"

    // Disposição usada pra DESENHAR a comanda (ver
    // comandaEstiloService.MODELOS_IMPRESSAO). Só tem efeito quando há fonte
    // escolhida: sem ela quem desenha é a impressora, que só sabe empilhar
    // caracteres numa grade.
    property string modeloImpressao: "classico"
    // Catálogo vindo do Python ([{chave, rotulo, descricao}]). Diferente das
    // fontes, não depende de máquina nenhuma — os modelos são código.
    property var modelosImpressao: []
    // A descrição do modelo escolhido, pra linha de ajuda abaixo do combo.
    readonly property string descricaoModelo: {
        for (var i = 0; i < raiz.modelosImpressao.length; i++) {
            if (raiz.modelosImpressao[i].chave === raiz.modeloImpressao)
                return raiz.modelosImpressao[i].descricao;
        }
        return "";
    }
    // O modelo em três colunas está de fato valendo? Só quando escolhido E com
    // fonte, já que ele só existe no caminho de imagem. É o que a prévia
    // consulta pra não prometer uma disposição que o papel não vai ter.
    readonly property bool tabelaEmColunas: raiz.modeloImpressao === "rascunho" && raiz.fonteImpressao !== ""
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
    // A chave PRINCIPAL da seleção — a âncora. É ela que as setas movem, que
    // posiciona os controles flutuantes e que o Shift+clique usa como ponto de
    // partida do intervalo. "" quando não há nada selecionado.
    property string chaveSelecionada: ""

    // TODAS as chaves selecionadas, incluindo a principal. Uma lista, e não só
    // a principal, porque estilizar quinze campos um a um era o trabalho que
    // esta tela dava: agora dá para pegar várias linhas e ligar o negrito de
    // todas de uma vez.
    //
    // Guardadas por chave como a principal, e pelo mesmo motivo: com índice a
    // seleção ficaria presa à posição, e mover um campo faria o destaque
    // saltar para o campo que desceu no lugar dele.
    property var chavesSelecionadas: []
    // Linha ordenável que CONTÉM o que está selecionado — as setas mexem
    // sempre nela. Coincide com chaveSelecionada na maioria dos campos, mas
    // difere nas sub-linhas da tabela de itens: selecionar "Nome do pedido"
    // estiliza aquela linha e move a tabela inteira, que é a única coisa que
    // faz sentido (uma linha da tabela não tem posição própria no cupom).
    property string donoSelecionado: ""
    property string tipoComanda: "Entrega"
    // [{ nome, documento }] — ver comandaEstiloService.DOCUMENTO_POR_TIPO.
    property var tiposComanda: []
    // Papel impresso que está sendo editado: "pedido" (a comanda de venda,
    // compartilhada por Balcão/Entrega/Mesa), "extra" (recibo de pagamento
    // de diária) ou "fechamento" (cupom de fechamento de caixa). Decide
    // quais campos entram no papel da prévia — trocar de documento troca a
    // comanda inteira na tela, enquanto trocar de tipo DENTRO do mesmo
    // documento só acende/apaga campos (a regra antiga, de campoNoTipo).
    property string documentoAtual: "pedido"

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
    property var documentosPorChave: ({})
    property var estilizavelPorChave: ({})

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
        // Faltava aqui, e era só por isso que o campo não tinha como ser
        // editado: sem exemplo, linhasDoCampo devolve lista vazia, o campo não
        // desenha linha nenhuma no papel da prévia — e a prévia é a ÚNICA porta
        // de entrada para o popup de estilo. Ele já estava em CAMPOS e em
        // CAMPOS_ORDENAVEIS o tempo todo, e já saía impresso na comanda.
        "usuario": { "prefixo": "Usuário: ", "valor": "Ana Paula" },
        "observacao_entrega": { "prefixo": "Observação: ", "valor": "INTERFONE QUEBRADO" },
        "forma_pagamento": { "prefixo": "Forma de pagamento: ", "valor": "Dinheiro" },
        "troco_para": { "prefixo": "Troco para: ", "valor": "R$ 100,00" },
        "status": { "prefixo": "Status: ", "valor": "NP" },
        "taxa_entrega": { "prefixo": "Taxa de entrega: ", "valor": "R$ 5,00" },
        "valor_total": { "prefixo": "Valor do pedido: ", "valor": "R$ 45,00" },
        "troco_a_dar": { "prefixo": "Troco a dar: ", "valor": "R$ 55,00" },
        // Recibo de pagamento de diária (ver
        // fechamentoController._montar_recibo_extra).
        "extra_titulo": { "prefixo": "", "valor": "RECIBO DE PAGAMENTO" },
        "extra_subtitulo": { "prefixo": "", "valor": "FUNCIONÁRIO EXTRA" },
        // Hora à esquerda e data à direita da MESMA linha, como no papel —
        // o espaçamento aqui é ilustrativo, quem alinha de verdade é o
        // controller, contra a largura do papel.
        "extra_hora_data": { "prefixo": "", "valor": "22:40                    14/08/2026" },
        "extra_recebi": { "prefixo": "RECEBI DE ", "valor": "Grande Sabor" },
        "extra_valor": { "prefixo": "A QUANTIA DE ", "valor": "R$ 120,00" },
        "extra_assina_nome": { "prefixo": "", "valor": "Maria Souza" },
        // Cupom de fechamento de caixa (ver
        // fechamentoController._montar_recibo_fechamento).
        "fech_titulo": { "prefixo": "", "valor": "FECHAMENTO DE CAIXA" },
        "fech_data": { "prefixo": "Data: ", "valor": "14/08/2026" },
        "fech_bruto": { "prefixo": "Total bruto vendido: ", "valor": "R$ 1250,00" },
        "fech_liquido": { "prefixo": "Total líquido (bruto - extras): ", "valor": "R$ 1130,00" },
        "fech_lucro": { "prefixo": "", "valor": "SOBROU: R$ 430,00" },
        "fech_lucro_real": { "prefixo": "", "valor": "LUCRO: R$ 1560,00" }
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
    onFonteImpressaoChanged: {
        raiz.marcarPendente();
        // Mesma guarda de salvarNoBackend: ao fechar o app o QML pode
        // sobreviver um instante ao controller, e aqui isso viraria um
        // TypeError no console bem na hora de sair.
        raiz.fonteExisteAqui = !!comandaEstiloController && raiz.fonteImpressao !== ""
            && comandaEstiloController.fonteDisponivelAqui(raiz.fonteImpressao);
        // Trocar a fonte muda a ESCALA de todo campo da prévia de uma vez (de
        // multiplicador inteiro para pixels livres, ou o contrário), e não o
        // estilo de um campo em particular — é exatamente o caso que
        // versaoConfig existe para cobrir.
        raiz.versaoConfig += 1;
    }
    // Mesmo caso da fonte: o modelo muda a tabela de itens inteira na prévia
    // (uma linha por item vira três colunas), não o estilo de um campo.
    onModeloImpressaoChanged: {
        raiz.marcarPendente();
        raiz.versaoConfig += 1;
    }

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

    // Os campos que vivem DENTRO da tabela de itens. Só eles são afetados pelo
    // teto de tamanho do modelo em colunas (ver tamanhoFonteDesenhado).
    readonly property var camposDaTabelaItens: ({
        "pedido": true,
        "pedido_tamanho": true,
        "observacao_item": true,
        "adicional_item": true,
        "borda_item": true
    })

    // O tamanho que o campo REALMENTE sai no papel, que nem sempre é o
    // configurado: no modelo em colunas o conteúdo da tabela é limitado ao
    // tamanho normal, porque ampliação não cabe numa coluna estreita (ver
    // comandaImagemService._estilo_de_campo). É este o número que a prévia usa
    // — mostrar o configurado ali prometeria uma letra que a comanda não tem.
    // Quem EDITA o tamanho continua lendo obterTamanhoFonte, que devolve o
    // valor guardado: o teto é de desenho, não apaga a escolha de ninguém.
    function tamanhoFonteDesenhado(campo) {
        var tamanho = raiz.obterTamanhoFonte(campo);
        if (raiz.tabelaEmColunas && raiz.camposDaTabelaItens[campo])
            return Math.min(tamanho, raiz.tamanhoFontePadrao);

        return tamanho;
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
            "separadores_campo": raiz.separadoresPorCampo,
            "fonte_impressao": raiz.fonteImpressao,
            "modelo_impressao": raiz.modeloImpressao
        });
        raiz.alteracoesPendentes = false;
    }

    // A comanda de exemplo repartida por campo, no formato que
    // ComandaEstiloController.imprimirComandaExemplo espera:
    // { chave: [ [{t, c}, ...], ... ] }.
    //
    // Só os campos que ESTE tipo de comanda imprime — os apagados na prévia
    // (um telefone numa comanda de Balcão) não sairiam no papel de verdade, e
    // um teste que imprime o que a comanda real não imprime não testa nada.
    // Os campos dos outros documentos já ficaram de fora antes, em
    // reconstruirModeloOrdem: o modelo só tem os do documento atual.
    //
    // A ORDEM não é montada aqui: quem a resolve, junto com as divisórias e o
    // espaçamento, é comandaTextoService.montar_linhas_por_ordem no Python —
    // o mesmo código que monta uma comanda de verdade. Daqui vai só o texto.
    function renderizadoresExemplo() {
        var mapa = {};
        for (var i = 0; i < modeloOrdemSecoes.count; i++) {
            var chave = modeloOrdemSecoes.get(i).chave;
            if (!raiz.campoNoTipo(chave, raiz.tipoComanda))
                continue;

            // Sempre a tabela em texto, mesmo com o modelo em colunas
            // escolhido: ver linhasItensClassicas.
            var linhas = chave === "itens" ? raiz.linhasItensClassicas() : raiz.linhasDoCampo(chave);
            if (!linhas.length)
                continue;

            var linhasDoPapel = [];
            for (var j = 0; j < linhas.length; j++)
                linhasDoPapel.push(linhas[j].segmentos);
            mapa[chave] = linhasDoPapel;
        }
        return mapa;
    }

    // Manda a comanda de exemplo pra impressora da malha.
    //
    // GRAVA ANTES, quando há edição pendente: quem imprime é o Python, com a
    // configuração que está em disco — sem gravar, o papel sairia com o estilo
    // ANTERIOR ao que está na tela, que é o contrário do que um teste serve
    // pra mostrar. É a mesma gravação do botão "Aplicar alterações", só
    // antecipada.
    function imprimirExemplo() {
        if (!comandaEstiloController)
            return;

        if (raiz.alteracoesPendentes)
            raiz.salvarNoBackend();

        comandaEstiloController.imprimirComandaExemplo(raiz.renderizadoresExemplo());
    }

    // Só o catálogo de fontes, sem mexer no resto da configuração — usado ao
    // abrir a tela e sempre que a máquina que imprime mudar (a eleição muda
    // sozinha quando alguém pluga a impressora em outro computador, e aí as
    // fontes oferecidas passam a ser as de lá).
    function recarregarFontes() {
        raiz.origemFontes = comandaEstiloController.origemFontes();
        raiz.fontesDisponiveis = comandaEstiloController.listarFontes();
    }

    function carregarConfiguracao() {
        var config = comandaEstiloController.obterConfiguracao();
        var campos = comandaEstiloController.listarCampos();
        var camposOrdenaveis = comandaEstiloController.listarCamposOrdenaveis();
        raiz.tamanhoFontePadrao = comandaEstiloController.tamanhoFontePadrao();
        raiz.tamanhoFonteMin = comandaEstiloController.tamanhoFonteMinimo();
        raiz.tamanhoFonteMax = comandaEstiloController.tamanhoFonteMaximo();
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
        var documentos = {};
        var estilizaveis = {};
        for (var j = 0; j < camposOrdenaveis.length; j++) {
            var ordenavel = camposOrdenaveis[j];
            rotulos[ordenavel.chave] = ordenavel.rotulo;
            categorias[ordenavel.chave] = ordenavel.categoria;
            tipos[ordenavel.chave] = ordenavel.tipos;
            documentos[ordenavel.chave] = ordenavel.documento;
            estilizaveis[ordenavel.chave] = ordenavel.estilizavel;
        }
        raiz.rotulosPorChave = rotulos;
        raiz.categoriasPorChave = categorias;
        raiz.tiposPorChave = tipos;
        raiz.documentosPorChave = documentos;
        raiz.estilizavelPorChave = estilizaveis;

        // Depois dos mapas acima (documentoDoTipo depende de tiposComanda) e
        // antes de montar o modelo, que é filtrado por documento.
        raiz.documentoAtual = raiz.documentoDoTipo(raiz.tipoComanda);
        raiz.reconstruirModeloOrdem();

        raiz.espacamentoSecoes = config.espacamento_secoes !== undefined ? config.espacamento_secoes : 1;
        raiz.espacamentoCorte = config.espacamento_corte !== undefined ? config.espacamento_corte : 4;
        raiz.linhasSeparadorPadrao = config.linhas_separador !== undefined ? config.linhas_separador : 1;
        // A escolha antes da lista, de propósito: é a atribuição de
        // fontesDisponiveis que manda o combo refazer o índice, e ela precisa
        // encontrar fonteImpressao já com o valor novo.
        raiz.fonteImpressao = config.fonte_impressao !== undefined ? config.fonte_impressao : "";
        raiz.recarregarFontes();
        // Mesma ordem, pelo mesmo motivo: a lista depois da escolha, pro combo
        // achar o índice certo ao se reler.
        raiz.modeloImpressao = config.modelo_impressao !== undefined ? config.modelo_impressao : "classico";
        raiz.modelosImpressao = comandaEstiloController.listarModelosImpressao();
        // Cópia, não a referência de dentro de configAtual: as exceções são
        // editadas por reatribuição (definirExcecaoSeparador) e não devem
        // mexer no dict que veio do Python.
        var excecoes = {};
        var lidas = config.separadores_campo || {};
        for (var chaveExcecao in lidas)
            excecoes[chaveExcecao] = lidas[chaveExcecao];
        raiz.separadoresPorCampo = excecoes;

        raiz.limparSelecao();

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

    function documentoDe(chave) {
        return raiz.documentosPorChave[chave] || "pedido";
    }

    function documentoDoTipo(tipo) {
        for (var i = 0; i < raiz.tiposComanda.length; i++) {
            if (raiz.tiposComanda[i].nome === tipo)
                return raiz.tiposComanda[i].documento;
        }
        return "pedido";
    }

    // Enche o modelo do papel com os campos do documento atual, na ordem em
    // que aparecem na ordem GLOBAL (configAtual.ordem_secoes, que guarda os
    // três papéis numa lista só). Os campos dos outros documentos ficam de
    // fora da prévia — não são "campos apagados" como os que o tipo não
    // imprime, são campos de outro papel, que nunca sairiam nesta comanda.
    function reconstruirModeloOrdem() {
        var ordem = raiz.configAtual.ordem_secoes || [];
        modeloOrdemSecoes.clear();
        for (var i = 0; i < ordem.length; i++) {
            if (raiz.documentoDe(ordem[i]) !== raiz.documentoAtual)
                continue;

            modeloOrdemSecoes.append({
                "chave": ordem[i],
                "rotulo": raiz.rotuloDe(ordem[i])
            });
        }

        // Só depois do laço de append(): durante ele o count cresce aos
        // poucos e o cálculo sairia sobre um modelo pela metade.
        raiz.recalcularSeparadores();
    }

    // Trocar de tipo dentro do mesmo documento (Balcão -> Entrega) não
    // remonta nada: os campos são os mesmos, só mudam de opacidade. Trocar
    // de documento troca o papel inteiro, e aí a seleção anterior deixa de
    // existir na tela.
    onTipoComandaChanged: {
        var documento = raiz.documentoDoTipo(raiz.tipoComanda);
        if (documento === raiz.documentoAtual)
            return;

        raiz.documentoAtual = documento;
        raiz.limparSelecao();
        raiz.reconstruirModeloOrdem();
    }

    // Devolve à ordem global (configAtual.ordem_secoes) o que o modelo do
    // papel diz agora. Reescreve NO LUGAR: cada posição que hoje é ocupada
    // por uma chave deste documento recebe a próxima chave do modelo, e as
    // dos outros documentos ficam onde estavam. Assim mover um campo do
    // fechamento nunca embaralha a comanda de venda, mesmo que as chaves
    // dos dois estejam intercaladas na lista (o que um JSON antigo, ou uma
    // mesclagem de _mesclar_ordem, pode produzir).
    function _reescreverOrdemGlobal() {
        var visiveis = [];
        for (var i = 0; i < modeloOrdemSecoes.count; i++)
            visiveis.push(modeloOrdemSecoes.get(i).chave);

        var completa = raiz.configAtual.ordem_secoes || [];
        var nova = [];
        var proxima = 0;
        for (var j = 0; j < completa.length; j++) {
            if (raiz.documentoDe(completa[j]) === raiz.documentoAtual)
                nova.push(visiveis[proxima++]);
            else
                nova.push(completa[j]);
        }
        raiz.configAtual.ordem_secoes = nova;
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

        raiz._reescreverOrdemGlobal();
        raiz.marcarPendente();
        raiz.recalcularSeparadores();
    }

    // --- ARRASTAR PARA REORDENAR ---
    // Índice do campo que está sendo arrastado agora, ou -1. Fica na raiz
    // porque o delegate arrastado é destruído e recriado a cada passo (o
    // Repeater refaz a lista ao mover no ListModel), e um estado guardado nele
    // sumiria no meio do arrasto.
    property int indiceArrastado: -1

    // Qual campo ocupa a posição `y` (em coordenadas de colunaPapel), ou -1
    // fora da coluna.
    //
    // Percorre os filhos em vez de dividir a altura total pelo número de
    // linhas: os campos têm alturas DIFERENTES (um bloco como a tabela de
    // itens vale por várias linhas, e um campo com fonte 4x é quatro vezes
    // mais alto), então qualquer conta baseada em altura média erraria o alvo
    // justo nos casos em que se costuma arrastar.
    function indiceNaPosicao(y) {
        for (var i = 0; i < colunaPapel.children.length; i++) {
            var filho = colunaPapel.children[i];
            if (!filho || filho.chave === undefined || !filho.visible)
                continue;
            if (y >= filho.y && y <= filho.y + filho.height)
                return filho.index;
        }
        return -1;
    }

    // Leva o campo arrastado UM passo na direção do destino, e devolve o novo
    // índice dele.
    //
    // Um passo por vez, e não um salto direto para o destino: mover no
    // ListModel dispara a Transition de `move` da coluna, e vários saltos
    // seguidos deixavam a animação correndo atrás do cursor. Como isto é
    // chamado a cada movimento do mouse, um passo por evento acompanha o
    // arrasto sem acumular animação pendente.
    function arrastarPara(destino) {
        var origem = raiz.indiceArrastado;
        if (origem < 0 || destino < 0 || destino === origem)
            return origem;

        var passo = destino > origem ? 1 : -1;
        raiz.moverCampoOrdem(origem, passo);
        raiz.indiceArrastado = origem + passo;
        return raiz.indiceArrastado;
    }

    function moverSelecionado(delta) {
        if (raiz.donoSelecionado === "")
            return;

        var indice = raiz.indiceDaChave(raiz.donoSelecionado);
        if (indice >= 0)
            raiz.moverCampoOrdem(indice, delta);
    }

    function estaSelecionada(chave) {
        return chave !== "" && raiz.chavesSelecionadas.indexOf(chave) >= 0;
    }

    function limparSelecao() {
        raiz.chaveSelecionada = "";
        raiz.donoSelecionado = "";
        raiz.chavesSelecionadas = [];
    }

    // As chaves estilizáveis na ordem em que aparecem no papel — é essa ordem,
    // e não a da lista de campos, que o Shift+clique precisa: quem arrasta o
    // mouse por cinco linhas espera pegar as cinco que viu, não as que estão
    // entre elas num catálogo interno.
    //
    // Montada na hora, a cada intervalo pedido, em vez de mantida em cache: a
    // ordem muda a cada campo movido, e um cache aqui seria mais uma coisa
    // para lembrar de invalidar.
    function chavesVisiveis() {
        var vistas = {};
        var lista = [];
        for (var i = 0; i < modeloOrdemSecoes.count; i++) {
            var linhas = raiz.linhasDoCampo(modeloOrdemSecoes.get(i).chave);
            for (var j = 0; j < linhas.length; j++) {
                var chave = linhas[j].campoEstilo;
                if (chave === "" || vistas[chave])
                    continue;
                vistas[chave] = true;
                lista.push(chave);
            }
        }
        return lista;
    }

    // Só o que dá para estilizar de fato — a seleção pode incluir âncoras de
    // posição (a tabela de itens, os blocos do fechamento), que têm lugar no
    // papel mas nenhum atributo próprio. Passar uma âncora ao popup faria ele
    // gravar um estilo em uma chave que nada lê.
    function chavesEstilizaveisSelecionadas() {
        var lista = [];
        for (var i = 0; i < raiz.chavesSelecionadas.length; i++) {
            if (raiz.podeEstilizar(raiz.chavesSelecionadas[i]))
                lista.push(raiz.chavesSelecionadas[i]);
        }
        return lista;
    }

    // `modificadores` vem do clique (mouse.modifiers):
    //   sem nada  — troca a seleção por esta linha, o comportamento de sempre
    //   Ctrl      — junta/tira esta linha, para escolher campos espalhados
    //   Shift     — pega o intervalo da âncora até aqui, para uma sequência
    function selecionar(chave, dono, modificadores) {
        modificadores = modificadores || 0;

        if (modificadores & Qt.ShiftModifier)
            raiz._selecionarIntervalo(chave);
        else if (modificadores & Qt.ControlModifier)
            raiz._alternarSelecao(chave, dono);
        else
            raiz._selecionarSozinha(chave, dono);

        cartaoComanda.forceActiveFocus(Qt.MouseFocusReason);
    }

    function _selecionarSozinha(chave, dono) {
        raiz.chaveSelecionada = chave;
        raiz.donoSelecionado = dono;
        raiz.chavesSelecionadas = chave === "" ? [] : [chave];
    }

    function _alternarSelecao(chave, dono) {
        if (chave === "")
            return;

        var lista = raiz.chavesSelecionadas.slice();
        var posicao = lista.indexOf(chave);

        if (posicao < 0) {
            lista.push(chave);
            // A recém-chegada vira a âncora: é a linha em que a pessoa está
            // olhando, e é dela que um Shift+clique seguinte deve partir.
            raiz.chaveSelecionada = chave;
            raiz.donoSelecionado = dono;
        } else {
            lista.splice(posicao, 1);
            // Tirando a âncora, a âncora passa a ser a última que sobrou —
            // deixar `chaveSelecionada` apontando para fora da seleção
            // esconderia os controles flutuantes sem motivo aparente.
            if (chave === raiz.chaveSelecionada) {
                raiz.chaveSelecionada = lista.length > 0 ? lista[lista.length - 1] : "";
                raiz.donoSelecionado = raiz.chaveSelecionada === "" ? "" : raiz.donoDaChave(raiz.chaveSelecionada);
            }
        }

        raiz.chavesSelecionadas = lista;
    }

    function _selecionarIntervalo(chave) {
        if (chave === "")
            return;

        // Sem âncora ainda, Shift+clique é um clique comum — não há de onde
        // partir o intervalo.
        if (raiz.chaveSelecionada === "") {
            raiz._selecionarSozinha(chave, raiz.donoDaChave(chave));
            return;
        }

        var visiveis = raiz.chavesVisiveis();
        var inicio = visiveis.indexOf(raiz.chaveSelecionada);
        var fim = visiveis.indexOf(chave);
        if (inicio < 0 || fim < 0) {
            raiz._selecionarSozinha(chave, raiz.donoDaChave(chave));
            return;
        }

        if (inicio > fim) {
            var troca = inicio;
            inicio = fim;
            fim = troca;
        }

        // A âncora NÃO muda: assim dá para esticar e encolher o mesmo
        // intervalo com Shift+clique sucessivos, em vez de cada clique virar
        // um começo novo.
        raiz.chavesSelecionadas = visiveis.slice(inicio, fim + 1);
    }

    // Qual linha ordenável CONTÉM esta chave — o "dono", que é quem as setas
    // movem. Reconstruído a partir da ordem porque _alternarSelecao e
    // _selecionarIntervalo precisam dele para chaves que não vieram de um
    // clique direto.
    function donoDaChave(chave) {
        for (var i = 0; i < modeloOrdemSecoes.count; i++) {
            var dono = modeloOrdemSecoes.get(i).chave;
            if (dono === chave)
                return dono;
            var linhas = raiz.linhasDoCampo(dono);
            for (var j = 0; j < linhas.length; j++) {
                if (linhas[j].campoEstilo === chave)
                    return dono;
            }
        }
        return chave;
    }

    // Abre o editor de estilo para TUDO que está selecionado. Ponto único
    // porque três caminhos levam até ele (o botão, o duplo clique na linha e o
    // duplo clique num segmento), e cada um montando a própria lista era como
    // um deles ficaria para trás ao mudar a regra.
    function abrirEstiloDaSelecao() {
        var chaves = raiz.chavesEstilizaveisSelecionadas();
        if (chaves.length === 0)
            return;

        var rotulo = chaves.length === 1
            ? raiz.rotuloDe(chaves[0])
            : chaves.length + " campos selecionados";
        popupEstiloCampo.abrirPara(chaves, rotulo);
    }

    function podeEstilizar(chave) {
        // "itens", "divisao_conta" e os dois blocos do fechamento são âncoras
        // de posição puras: existem no catálogo de ordenáveis, mas não em
        // CAMPOS (não têm atributos de estilo próprios). O que tem estilo ali
        // dentro são as sub-linhas. Quem é âncora vem do Python
        // ("estilizavel", ver listarCamposOrdenaveis) em vez de uma lista
        // repetida aqui — os campos estilizáveis que não são ordenáveis (os
        // de dentro da tabela de itens) não aparecem nesse mapa, e por isso
        // o padrão de um chave desconhecida é `true`.
        if (chave === "")
            return false;

        var estilizavel = raiz.estilizavelPorChave[chave];
        return estilizavel === undefined ? true : estilizavel;
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
        return raiz.repetirVezes(caractere, raiz.colunasPapel);
    }

    function repetirVezes(caractere, vezes) {
        var texto = "";
        for (var i = 0; i < vezes; i++)
            texto += caractere;
        return texto;
    }

    // Um segmento pode trazer "clique" para ser selecionável sozinho, em vez
    // de devolver o clique para a sub-linha que o contém — é o que permite
    // estilizar o tamanho da pizza, que divide a linha com o nome do item.
    // Cada linha do papel é uma lista de segmentos {t: texto, c: campo de
    // estilo ou ""}. Um campo comum vira uma linha só, com o prefixo sem
    // estilo e o valor estilizado; a tabela de itens e a divisão da conta
    // viram vários. `campoEstilo` é o que o clique naquela sub-linha
    // seleciona ("" = a sub-linha não tem estilo próprio, então o clique
    // seleciona a linha ordenável dona dela).
    // Preenche `texto` até `largura` com espaços, ou corta o que passar. Usado
    // só pela prévia da tabela em colunas: a prévia é monoespaçada, então
    // contar caracteres é o que alinha as colunas na tela.
    function preencherColuna(texto, largura) {
        var conteudo = texto.length > largura ? texto.substring(0, largura) : texto;
        while (conteudo.length < largura)
            conteudo += " ";
        return conteudo;
    }

    // A tabela de itens do modelo "rascunho" (ver
    // comandaImagemService._bloco_tabela_rascunho): Pedido, Observação e Valor
    // lado a lado, como na lista de itens do Balcão/Entrega/Salão.
    //
    // É uma APROXIMAÇÃO, e não pode deixar de ser: no papel as colunas são
    // medidas em dots e o texto é proporcional, aqui são caracteres de uma
    // fonte monoespaçada. O que a prévia promete é a disposição — o que está em
    // qual coluna, e o que desce recuado embaixo —, não a quebra de linha exata.
    //
    // As larguras seguem a mesma conta do Python: a coluna do Valor recebe o
    // que o maior valor precisa, e Pedido/Observação dividem o resto na
    // proporção 41:37 de Responsivo.gradePedido.
    function linhasItensEmColunas() {
        var larguraValor = 9;
        var util = raiz.colunasPapel - 2 - larguraValor;
        var larguraPedido = Math.round(util * 41 / 78);
        var larguraObservacao = util - larguraPedido;

        return [
            // Cabeçalho sem estilo próprio (campoEstilo vazio): os rótulos são
            // desenho da tabela, não conteúdo da comanda — clicar neles
            // seleciona o bloco de itens, como em qualquer sub-linha sem campo.
            { "campoEstilo": "", "segmentos": [{
                "t": raiz.preencherColuna("Pedido", larguraPedido) + " " + raiz.preencherColuna("Observação", larguraObservacao) + " " + "Valor",
                "c": ""
            }] },
            { "campoEstilo": "pedido", "segmentos": [
                { "t": raiz.preencherColuna("PIZZA CALABRESA", larguraPedido), "c": "pedido" },
                { "t": " ", "c": "" },
                { "t": raiz.preencherColuna("SEM CEBOLA", larguraObservacao), "c": "observacao_item", "clique": "observacao_item" },
                { "t": " R$ 45,00", "c": "" }
            ] },
            // O tamanho desce junto do nome, dentro da coluna do Pedido — no
            // papel ele é a continuação do mesmo texto, que quebra quando não
            // cabe. Sai no estilo de "pedido", e não no de "pedido_tamanho":
            // este modelo desenha o item como um texto corrido só, e é a única
            // configuração de estilo que ele não honra (ver
            // comandaImagemService._bloco_tabela_rascunho).
            { "campoEstilo": "pedido", "segmentos": [{ "t": raiz.preencherColuna("(BROTO)", larguraPedido), "c": "pedido" }] },
            { "campoEstilo": "adicional_item", "segmentos": [{ "t": "  + BACON (R$ 5,00)", "c": "adicional_item" }] },
            { "campoEstilo": "borda_item", "segmentos": [{ "t": "  * BORDA CATUPIRY (R$ 8,00)", "c": "borda_item" }] }
        ];
    }

    // A tabela de itens como ela é MONTADA EM TEXTO, que é o que vai parar no
    // arquivo da comanda em qualquer modelo (ver comandaTextoService.
    // formatar_tabela). O modelo em colunas não muda isto: ele redesenha esta
    // mesma tabela na hora de imprimir (comandaImagemService), lendo os itens
    // de volta daqui. Por isso a impressão de teste manda SEMPRE estas linhas,
    // e nunca as de linhasItensEmColunas — que são a prévia de um DESENHO, e
    // como texto no papel não seriam relidas como tabela nenhuma.
    function linhasItensClassicas() {
        return [
            // O tamanho sai colado no nome do item, na mesma linha (ver
            // comandaTextoService.formatar_coluna_pedido), entao ele e um
            // SEGMENTO e nao uma sub-linha propria. "clique" e o que o
            // torna alcancavel: sem ele o clique cairia na sub-linha
            // inteira e selecionaria "pedido", e nao haveria como abrir o
            // estilo do tamanho por lugar nenhum.
            //
            // BROTO, e nao GRANDE: o grande nao sai escrito no papel (ver
            // comandaTextoService.TAMANHO_OMITIDO), e uma previa com
            // "(GRANDE)" mostraria um campo que a comanda de verdade nunca
            // imprime.
            { "campoEstilo": "pedido", "segmentos": [
                { "t": "- PIZZA CALABRESA ", "c": "pedido" },
                { "t": "(BROTO)", "c": "pedido_tamanho", "clique": "pedido_tamanho" },
                { "t": " | R$ 45,00", "c": "pedido" }
            ] },
            { "campoEstilo": "adicional_item", "segmentos": [{ "t": "  + BACON (R$ 5,00)", "c": "adicional_item" }] },
            { "campoEstilo": "borda_item", "segmentos": [{ "t": "  * BORDA CATUPIRY (R$ 8,00)", "c": "borda_item" }] },
            { "campoEstilo": "observacao_item", "segmentos": [{ "t": "  SEM CEBOLA", "c": "observacao_item" }] }
        ];
    }

    function linhasDoCampo(chave) {
        if (chave === "itens")
            return raiz.tabelaEmColunas ? raiz.linhasItensEmColunas() : raiz.linhasItensClassicas();

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

        // Bloco "POR ORIGEM" do fechamento: um título mais um grupo por
        // origem que teve venda no dia (aqui, um só de exemplo). Os dois
        // espaços de recuo das formas de pagamento ficam FORA do segmento
        // estilizado, igual ao f-string que os imprime.
        if (chave === "fech_por_origem") {
            return [
                { "campoEstilo": "fech_origem_titulo", "segmentos": [{ "t": "POR ORIGEM", "c": "fech_origem_titulo" }] },
                { "campoEstilo": "fech_origem_nome", "segmentos": [{ "t": "Balcão: R$ 620,00", "c": "fech_origem_nome" }] },
                { "campoEstilo": "fech_origem_forma", "segmentos": [
                    { "t": "  ", "c": "" },
                    { "t": "Dinheiro: R$ 300,00", "c": "fech_origem_forma" }
                ] },
                { "campoEstilo": "fech_origem_forma", "segmentos": [
                    { "t": "  ", "c": "" },
                    { "t": "Pix: R$ 200,00", "c": "fech_origem_forma" }
                ] },
                { "campoEstilo": "fech_origem_forma", "segmentos": [
                    { "t": "  ", "c": "" },
                    { "t": "Cartão: R$ 120,00", "c": "fech_origem_forma" }
                ] }
            ];
        }

        if (chave === "fech_diarias") {
            return [
                { "campoEstilo": "fech_diarias_titulo", "segmentos": [{ "t": "PAGAMENTOS DE DIÁRIA", "c": "fech_diarias_titulo" }] },
                { "campoEstilo": "fech_diarias_item", "segmentos": [{ "t": "Maria Souza - 14/08/2026 22:40 - R$ 120,00", "c": "fech_diarias_item" }] }
            ];
        }

        // Bloco "ALTERAÇÕES APÓS A BAIXA": uma comanda já fechada que foi
        // corrigida ou apagada depois, e quem fez (ver
        // FechamentoController._linhas_alteracoes_do_dia). Como no bloco de
        // origens, os dois espaços de recuo ficam FORA do segmento estilizado.
        if (chave === "fech_edicoes") {
            return [
                { "campoEstilo": "fech_edicoes_titulo", "segmentos": [{ "t": "ALTERAÇÕES APÓS A BAIXA", "c": "fech_edicoes_titulo" }] },
                { "campoEstilo": "fech_edicoes_item", "segmentos": [{ "t": "Corrigida - A3F2 - João da Silva", "c": "fech_edicoes_item" }] },
                { "campoEstilo": "fech_edicoes_autor", "segmentos": [
                    { "t": "  ", "c": "" },
                    { "t": "Maria Souza - 14/08/2026 22:51:04", "c": "fech_edicoes_autor" }
                ] },
                { "campoEstilo": "fech_edicoes_autor", "segmentos": [
                    { "t": "  ", "c": "" },
                    { "t": "R$ 45,00 -> R$ 52,00", "c": "fech_edicoes_autor" }
                ] }
            ];
        }

        // Bloco "SENDO" do recibo de diária: o valor discriminado nas verbas
        // de _DISCRIMINACAO_DIARIA, com o total por último num estilo próprio
        // (ver fechamentoController._montar_recibo_extra). Os pontos são
        // ilustrativos — quem os conta de verdade é o controller, contra a
        // largura do papel.
        if (chave === "extra_discriminacao") {
            return [
                { "campoEstilo": "extra_discriminacao_item", "segmentos": [{ "t": "SENDO", "c": "extra_discriminacao_item" }] },
                { "campoEstilo": "extra_discriminacao_item", "segmentos": [{ "t": "FGTS........................... R$ 9,60", "c": "extra_discriminacao_item" }] },
                { "campoEstilo": "extra_discriminacao_item", "segmentos": [{ "t": "FÉRIAS......................... R$ 9,20", "c": "extra_discriminacao_item" }] },
                { "campoEstilo": "extra_discriminacao_item", "segmentos": [{ "t": "1/3 SOBRE AS FÉRIAS............ R$ 3,07", "c": "extra_discriminacao_item" }] },
                { "campoEstilo": "extra_discriminacao_item", "segmentos": [{ "t": "13º SALÁRIO.................... R$ 9,20", "c": "extra_discriminacao_item" }] },
                { "campoEstilo": "extra_discriminacao_item", "segmentos": [{ "t": "SALÁRIO LÍQUIDO............... R$ 88,93", "c": "extra_discriminacao_item" }] },
                { "campoEstilo": "extra_discriminacao_total", "segmentos": [{ "t": "TOTAL A RECEBER.............. R$ 120,00", "c": "extra_discriminacao_total" }] }
            ];
        }

        // As quatro linhas da quitação compartilham um estilo só — é um
        // parágrafo, não quatro campos, e quebrá-lo em quatro chaves daria ao
        // dono quatro botões de estilo para manter iguais entre si.
        if (chave === "extra_quitacao") {
            return [
                { "campoEstilo": "extra_quitacao", "segmentos": [{ "t": "DANDO TOTAL QUITAÇÃO A EMPRESA,", "c": "extra_quitacao" }] },
                { "campoEstilo": "extra_quitacao", "segmentos": [{ "t": "SOBRE OS VALORES ACIMA", "c": "extra_quitacao" }] },
                { "campoEstilo": "extra_quitacao", "segmentos": [{ "t": "DISCRIMINADOS", "c": "extra_quitacao" }] },
                { "campoEstilo": "extra_quitacao", "segmentos": [{ "t": "DO MAIS NADA A RECLAMAR", "c": "extra_quitacao" }] }
            ];
        }

        // As duas primeiras linhas são o espaço em branco pra assinar (do
        // próprio bloco, não espaçamento entre seções) e não têm estilo:
        // clicar nelas seleciona o bloco inteiro.
        if (chave === "extra_assinatura") {
            return [
                { "campoEstilo": "", "segmentos": [{ "t": "", "c": "" }] },
                { "campoEstilo": "", "segmentos": [{ "t": "", "c": "" }] },
                { "campoEstilo": "extra_assinatura", "segmentos": [{ "t": raiz.repetirVezes("_", 30), "c": "extra_assinatura" }] },
                { "campoEstilo": "", "segmentos": [{ "t": "(assinatura)", "c": "" }] }
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

    // A máquina que imprime é eleita pela malha e pode trocar enquanto esta
    // tela está aberta (alguém pluga a impressora em outro computador, ou o
    // dono fixa outra máquina na tela de Rede). Quando isso acontece, as
    // fontes oferecidas passam a ser as de lá — recarregar só o catálogo, e
    // não a configuração inteira, pra não jogar fora o que já foi editado
    // aqui e ainda não foi aplicado.
    Connections {
        target: redeController

        function onImpressoraPrincipalMudou() {
            raiz.recarregarFontes();
        }
    }

    ListModel {
        id: modeloOrdemSecoes
    }

    // Mede uma linha cheia do papel (40 colunas) na fonte monoespaçada da
    // prévia — de onde saem a largura do papel e a altura de uma linha em
    // branco, em vez de números mágicos que descolariam da fonte.
    TextMetrics {
        id: metricaPapel

        // A MESMA família da prévia: é esta medida que define a largura do
        // papel na tela (40 colunas) e a altura de uma linha em branco. Se ela
        // continuasse na monoespaçada, o cartão do papel e as linhas de traço
        // ficariam de larguras diferentes assim que a comanda passasse a ser
        // escrita noutra fonte.
        font.family: raiz.fontePrevia
        font.pixelSize: raiz.tamanhoBasePapel
        text: raiz.repetir("0")
    }

    // Largura de uma linha de 40 colunas na fonte base — o PISO da largura do
    // papel, nunca o teto.
    //
    // É constante de propósito: depende só da métrica da fonte, e de nada que
    // esteja dentro do papel. É isso que permite as larguras subirem do
    // conteúdo para o papel (linha -> coluna -> papel) sem laço de binding;
    // antes elas desciam do papel para as linhas, e por isso um campo com
    // fonte ampliada não tinha como alargar o papel — só era cortado pelo
    // clip.
    readonly property real larguraLinhaBase: Math.ceil(metricaPapel.width) + 10

    // --- CABEÇALHO DA SEÇÃO + RESTAURAR PADRÕES ---
    RowLayout {
        width: raiz.width
        spacing: Estilo.global.spacing.xl

        Row {
            spacing: Estilo.global.spacing.sm
            Icone { nome: "fa6s.receipt"; cor: raiz.corDestaque; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: raiz.documentoAtual === "extra" ? "MODELO DO RECIBO DE DIÁRIA"
                    : (raiz.documentoAtual === "fechamento" ? "MODELO DO FECHAMENTO DE CAIXA" : "MODELO DA COMANDA IMPRESSA")
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
            raiz.limparSelecao();
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

                // Seletor de papel/tipo: para Balcão/Entrega/Mesa troca quais
                // campos aparecem acesos, porque nenhuma comanda real usa os
                // 16 ao mesmo tempo (Balcão não tem endereço, Mesa não tem
                // telefone); para Extras e Fechamento troca o papel inteiro,
                // que tem campos próprios (ver documentoAtual).
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

                            required property var modelData

                            readonly property bool _ativo: raiz.tipoComanda === botaoTipo.modelData.nome

                            padding: Estilo.global.padding.sm
                            focusPolicy: Qt.NoFocus
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: raiz.tipoComanda = botaoTipo.modelData.nome

                            contentItem: Text {
                                text: botaoTipo.modelData.nome
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
                text: {
                    if (raiz.chaveSelecionada === "")
                        return "Clique numa linha da comanda para selecioná-la; os controles aparecem ao lado dela — as setas mudam a posição, e \"Estilo…\" abre negrito, sublinhado, fundo preto e tamanho da fonte. Ctrl+clique junta outras linhas à seleção e Shift+clique pega tudo de uma até a outra, para estilizar várias de uma vez.";

                    // Com mais de uma linha, o que interessa é quantas são e o
                    // que ainda dá para fazer com elas — dizer o rótulo de uma
                    // só esconderia as outras.
                    if (raiz.chavesSelecionadas.length > 1)
                        return raiz.chavesSelecionadas.length + " linhas selecionadas — \"Estilo…\" vale para todas. As setas movem uma linha de cada vez; deixe só uma selecionada para usá-las.";

                    return "Selecionado: " + raiz.rotuloDe(raiz.chaveSelecionada)
                        + (raiz.donoSelecionado !== raiz.chaveSelecionada
                           ? " — as setas movem a " + raiz.rotuloDe(raiz.donoSelecionado).toLowerCase() + " inteira."
                           : "")
                        + " Ctrl+clique junta outras linhas; Shift+clique pega o intervalo.";
                }
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

                        // Nomeado pelo mesmo motivo dos popups das outras telas:
                        // deixa a largura do papel medível de fora, que é a única
                        // forma de testar que ele acompanha o conteúdo.
                        objectName: "papelPrevia"

                        anchors.left: parent.left
                        anchors.top: parent.top
                        // Acompanha a linha mais larga do cupom, com o piso de
                        // 40 colunas: um campo em fonte 4x é 4x mais largo que
                        // o papel de base, e antes disso ele simplesmente
                        // sumia atrás do clip. A conta bate com a de antes
                        // quando nada está ampliado (larguraLinhaBase + 20 =
                        // 40 colunas + 30), então o papel só cresce quando
                        // precisa.
                        width: Math.max(raiz.larguraLinhaBase, colunaPapel.implicitWidth) + 20
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

                            objectName: "colunaPapelPrevia"

                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.topMargin: 12
                            // Sem "width: parent.width - 20": a largura sobe
                            // daqui para o papel, não desce dele para cá (ver
                            // larguraLinhaBase). Como Column, a implicitWidth
                            // já é a do filho mais largo.
                            width: Math.max(raiz.larguraLinhaBase, implicitWidth)
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

                                    // Idem: Column, largura do filho mais largo.
                                    width: Math.max(raiz.larguraLinhaBase, implicitWidth)
                                    spacing: 0
                                    // Campo que este tipo de comanda não imprime:
                                    // continua visível e movível, só apagado.
                                    opacity: linhaOrdem._noTipo ? 1 : Estilo.global.opacity.muted

                                    SeparadorPapel {
                                        largura: raiz.larguraLinhaBase
                                        separador: linhaOrdem._separador.tipo
                                        repeticoes: linhaOrdem._separador.linhas
                                        linhasEmBranco: raiz.espacamentoSecoes
                                        alturaLinha: metricaPapel.height
                                        tamanhoFonte: raiz.tamanhoBasePapel
                                        familia: raiz.fontePrevia
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
                                            readonly property bool _selecionada: raiz.estaSelecionada(subLinha._campoClique)
                                            // A âncora (ver chaveSelecionada) é a única que
                                            // posiciona os controles flutuantes: com várias
                                            // linhas acesas, todas disputariam o mesmo
                                            // Binding e os botões parariam na que o Qt
                                            // avaliasse por último.
                                            readonly property bool _ehAncora: raiz.chaveSelecionada === subLinha._campoClique
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

                                            // A largura vem do CONTEÚDO, com o piso
                                            // de 40 colunas — é daqui que a largura do
                                            // papel sobe.
                                            width: Math.max(raiz.larguraLinhaBase, conteudoSubLinha.implicitWidth)
                                            height: Math.max(metricaPapel.height, conteudoSubLinha.implicitHeight)

                                            // A faixa de destaque/clique cobre o papel
                                            // inteiro, e não só esta linha: com uma
                                            // linha ampliada esticando o papel, as
                                            // curtas ficariam com um realce mais estreito
                                            // que as vizinhas. Ler colunaPapel.width aqui
                                            // não fecha laço — subLinha é Item, e a
                                            // implicitWidth de um Item não vem dos filhos.
                                            readonly property real _larguraFaixa: Math.max(subLinha.width, colunaPapel.width)

                                            Binding {
                                                when: subLinha._ehAncora && subLinha._ancora
                                                target: raiz
                                                property: "yLinhaSelecionada"
                                                value: colunaPapel.y + linhaOrdem.y + subLinha.y
                                                restoreMode: Binding.RestoreNone
                                            }

                                            Binding {
                                                when: subLinha._ehAncora && subLinha._ancora
                                                target: raiz
                                                property: "alturaLinhaSelecionada"
                                                value: subLinha.height
                                                restoreMode: Binding.RestoreNone
                                            }

                                            Rectangle {
                                                x: -6
                                                width: subLinha._larguraFaixa + 12
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
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
                                                // Acima de areaSubLinha, que é
                                                // declarada depois e cobre a linha
                                                // toda: sem isto, o MouseArea de um
                                                // segmento com "clique" ficaria
                                                // embaixo dela e nunca receberia o
                                                // clique. O resto da linha continua
                                                // caindo na areaSubLinha — um Row sem
                                                // MouseArea não intercepta nada.
                                                z: 1

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
                                                            font.family: raiz.fontePrevia
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
                                                            familia: raiz.fontePrevia
                                                        }

                                                        // Só existe no segmento que
                                                        // pede seleção própria (ver
                                                        // "clique" em linhasDoCampo).
                                                        // Nos demais nem é criado, e o
                                                        // clique segue para a
                                                        // areaSubLinha por baixo.
                                                        MouseArea {
                                                            readonly property string _campo: segmento.modelData.clique || ""

                                                            anchors.fill: parent
                                                            enabled: _campo !== ""
                                                            visible: enabled
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: function (mouse) {
                                                                raiz.selecionar(_campo, linhaOrdem.chave, mouse.modifiers);
                                                            }
                                                            onDoubleClicked: function (mouse) {
                                                                raiz.selecionar(_campo, linhaOrdem.chave, mouse.modifiers);
                                                                raiz.abrirEstiloDaSelecao();
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: areaSubLinha

                                                // Quanto o ponteiro precisa andar antes de
                                                // virar arrasto. Sem folga, a mão treme no
                                                // clique e o campo troca de lugar sozinho;
                                                // com folga demais, arrastar parece travado.
                                                readonly property int _folgaArrasto: 6

                                                property real _yPressao: 0
                                                property bool _arrastando: false

                                                x: -6
                                                width: subLinha._larguraFaixa + 12
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                hoverEnabled: true
                                                cursorShape: areaSubLinha._arrastando ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                                                onPressed: function (mouse) {
                                                    areaSubLinha._yPressao = mouse.y;
                                                    areaSubLinha._arrastando = false;
                                                }

                                                onPositionChanged: function (mouse) {
                                                    if (!pressed)
                                                        return;

                                                    // Ctrl/Shift são para montar seleção
                                                    // múltipla — arrastar com eles pressionados
                                                    // seria reordenar quando se quis marcar.
                                                    if (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
                                                        return;

                                                    if (!areaSubLinha._arrastando) {
                                                        if (Math.abs(mouse.y - areaSubLinha._yPressao) < areaSubLinha._folgaArrasto)
                                                            return;
                                                        areaSubLinha._arrastando = true;
                                                        raiz.indiceArrastado = linhaOrdem.index;
                                                        // Arrastar é mexer NESTE campo: deixá-lo
                                                        // selecionado é o que faz os controles
                                                        // flutuantes seguirem junto.
                                                        raiz.selecionar(subLinha._campoClique, linhaOrdem.chave, 0);
                                                    }

                                                    var ponto = areaSubLinha.mapToItem(colunaPapel, mouse.x, mouse.y);
                                                    raiz.arrastarPara(raiz.indiceNaPosicao(ponto.y));
                                                }

                                                onReleased: {
                                                    areaSubLinha._arrastando = false;
                                                    raiz.indiceArrastado = -1;
                                                }

                                                // Um arrasto termina em "released", não em
                                                // "clicked" — mas o Qt emite os dois, e sem esta
                                                // guarda soltar o campo noutro lugar também
                                                // refazia a seleção com os modificadores que
                                                // estivessem pressionados na hora.
                                                onClicked: function (mouse) {
                                                    if (areaSubLinha._arrastando)
                                                        return;
                                                    raiz.selecionar(subLinha._campoClique, linhaOrdem.chave, mouse.modifiers);
                                                }
                                                // Atalho: quem já sabe o que quer
                                                // mexer chega no popup direto.
                                                onDoubleClicked: function (mouse) {
                                                    raiz.selecionar(subLinha._campoClique, linhaOrdem.chave, mouse.modifiers);
                                                    raiz.abrirEstiloDaSelecao();
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
                                largura: raiz.larguraLinhaBase
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

                        // Quantas linhas as setas conseguem mover: uma. Mover
                        // várias de uma vez não tem significado único — cada
                        // uma iria para um lugar diferente, e as que estão
                        // longe uma da outra passariam por cima das do meio.
                        // O estilo, esse sim, se aplica a todas.
                        readonly property bool _umaSo: raiz.chavesSelecionadas.length <= 1

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
                                enabled: raiz.donoSelecionado !== "" && controlesLinha._umaSo
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
                                enabled: raiz.donoSelecionado !== "" && controlesLinha._umaSo
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
                                enabled: raiz.chavesEstilizaveisSelecionadas().length > 0
                                opacity: enabled ? 1 : Estilo.global.opacity.disabled
                                onClicked: raiz.abrirEstiloDaSelecao()

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

                        // Título próprio: daqui pra baixo não é mais
                        // espaçamento, e um bloco sem título ficaria pendurado
                        // no anterior.
                        Text {
                            text: "FONTE"
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.bold: true
                            color: raiz.corDestaque
                        }

                        Column {
                            spacing: Estilo.global.spacing.md

                            Text {
                                width: 400
                                text: "Fonte usada para desenhar a comanda"
                                font.pixelSize: Estilo.global.fontSize.md
                                color: Estilo.global.text
                            }

                            // De qual máquina saiu a lista abaixo. Sem isto, o
                            // dono não teria como entender por que a lista é
                            // essa (são as fontes de OUTRO computador) nem por
                            // que ela muda quando a impressora troca de lugar.
                            Text {
                                width: 400
                                wrapMode: Text.WordWrap
                                text: !raiz.origemFontes.conhecida ? "Nenhuma máquina com impressora foi encontrada agora — sem saber quais fontes ela tem, só a opção padrão é oferecida." : raiz.origemFontes.local ? "Fontes instaladas nesta máquina, que é a que está imprimindo. Cada opção aparece escrita na própria fonte." : "Fontes instaladas em " + raiz.origemFontes.maquina + ", a máquina que está imprimindo. Cada opção aparece escrita na própria fonte, mas as que esta máquina não tem são mostradas na fonte comum."
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.textSecondary
                            }

                            ComboBox {
                                id: comboFonte

                                // Nomeado pelo mesmo motivo do popup lá
                                // embaixo: deixa o seletor alcançável de fora
                                // para inspeção e teste.
                                objectName: "comboFonteComanda"
                                width: 400
                                model: raiz.fontesDisponiveis
                                textRole: "rotulo"
                                valueRole: "chave"

                                // Mesmo padrão do combo de impressora em
                                // pages/rede/Rede.qml: currentIndex não é um
                                // binding vivo (o usuário mexe nele à vontade),
                                // então é recalculado explicitamente sempre que
                                // a configuração é relida — abrir a tela ou
                                // "Restaurar padrões".
                                function sincronizarSelecao() {
                                    for (var i = 0; i < raiz.fontesDisponiveis.length; i++) {
                                        if (raiz.fontesDisponiveis[i].chave === raiz.fonteImpressao) {
                                            currentIndex = i;
                                            return;
                                        }
                                    }
                                    // A fonte gravada não existe nesta máquina
                                    // (veio de outra pela malha). Cai na opção
                                    // padrão, que é o que a impressão também
                                    // faz — mas SEM escrever em fonteImpressao:
                                    // apagar aqui a escolha do dono a desfaria
                                    // em todas as máquinas na próxima gravação.
                                    currentIndex = 0;
                                }

                                Component.onCompleted: sincronizarSelecao()
                                Connections {
                                    target: raiz

                                    function onFontesDisponiveisChanged() {
                                        comboFonte.sincronizarSelecao();
                                    }

                                    // Também quando só a escolha muda sem a
                                    // lista mudar — é o caso de "Restaurar
                                    // padrões", que devolve a fonte pro vazio.
                                    function onFonteImpressaoChanged() {
                                        comboFonte.sincronizarSelecao();
                                    }
                                }
                                onActivated: raiz.fonteImpressao = currentValue

                                // Cada opção escrita NA PRÓPRIA FONTE, que é
                                // o que faz a lista responder sozinha a
                                // pergunta que se tem ao abri-la: com que cara
                                // esta fonte sai? Ler "Figtree" escrito na
                                // fonte do app não diz nada sobre a Figtree.
                                //
                                // A opção padrão (chave vazia) fica na fonte da
                                // interface de propósito: ela não é uma
                                // família, é a ausência de escolha — quem
                                // desenha ali é a impressora, e não há prévia
                                // possível de uma fonte que mora dentro dela.
                                //
                                // Ressalva que a linha de aviso abaixo do combo
                                // explica ao usuário: as famílias listadas são
                                // as da MÁQUINA QUE IMPRIME, e o Qt desenha
                                // aqui com o que ESTA máquina tem. Numa fonte
                                // que só existe lá, ele substitui em silêncio e
                                // a prévia mostra outra coisa.
                                delegate: ItemDelegate {
                                    width: comboFonte.width
                                    text: modelData.rotulo
                                    font.family: modelData.chave !== "" ? modelData.chave : comboFonte.font.family
                                    // Fixo, e não herdado da família: fontes
                                    // diferentes têm alturas de traço bem
                                    // diferentes, e deixar cada uma escolher a
                                    // sua faria a lista pular de tamanho a cada
                                    // linha.
                                    font.pixelSize: Estilo.global.fontSize.lg
                                    highlighted: comboFonte.highlightedIndex === index
                                    palette.text: Estilo.global.textInput
                                    palette.highlightedText: Estilo.global.textInput
                                }

                                // O campo fechado também mostra a escolhida na
                                // fonte dela: depois de escolher, é ele que
                                // fica na tela, e voltar para a fonte da
                                // interface desfaria a prévia no instante em
                                // que ela passa a valer.
                                contentItem: Text {
                                    text: comboFonte.displayText
                                    font.family: raiz.fonteImpressao !== "" ? raiz.fonteImpressao : comboFonte.font.family
                                    font.pixelSize: Estilo.global.fontSize.lg
                                    color: Estilo.global.textInput
                                    leftPadding: 10
                                    rightPadding: 10
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: Estilo.global.inputBackground
                                    border.color: comboFonte.activeFocus ? raiz.corDestaque : Estilo.global.border
                                    border.width: comboFonte.activeFocus ? 2 : 1
                                    implicitHeight: 38
                                }
                            }

                            Text {
                                width: 400
                                wrapMode: Text.WordWrap
                                text: raiz.fonteImpressao === "" ? "A impressora desenha as letras com a fonte que ela tem gravada. É o formato de sempre, e o mais rápido." : "A comanda é desenhada como imagem antes de ser impressa, o que deixa a impressão mais lenta."
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.textSecondary
                            }

                            // O que esperar da prévia agora que ela é escrita
                            // na fonte escolhida. São duas ressalvas
                            // diferentes, e nenhuma delas se descobre
                            // olhando: uma fonte que só existe na outra
                            // máquina o Qt substituiria calado, e no modelo
                            // clássico o papel alinha caractere a caractere,
                            // coisa que o texto na tela não faz.
                            Text {
                                width: 400
                                wrapMode: Text.WordWrap
                                visible: raiz.fonteImpressao !== ""
                                text: !raiz.fonteExisteAqui ? "A comanda de exemplo continua na fonte de medida: esta máquina não tem a fonte escolhida instalada, e escrever numa substituta mostraria uma tipografia que não é a do papel." : (raiz.modeloImpressao === "rascunho" ? "A comanda de exemplo está escrita nesta fonte." : "A comanda de exemplo está escrita nesta fonte. No papel, o modelo clássico ainda encaixa cada caractere numa coluna de largura fixa, então o alinhamento sai mais certo do que aparece aqui.")
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.textSecondary
                            }
                        }

                        // Título próprio pelo mesmo motivo do bloco FONTE
                        // acima: daqui pra baixo não se escolhe mais a
                        // tipografia, e sim a DISPOSIÇÃO do que é desenhado.
                        Text {
                            text: "MODELO"
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.bold: true
                            color: raiz.corDestaque
                        }

                        Column {
                            spacing: Estilo.global.spacing.md

                            Text {
                                width: 400
                                text: "Como a comanda é desenhada"
                                font.pixelSize: Estilo.global.fontSize.md
                                color: Estilo.global.text
                            }

                            ComboBox {
                                id: comboModelo

                                // Nomeado pelo mesmo motivo do combo de fonte
                                // acima: deixa o seletor alcançável de fora
                                // para inspeção e teste.
                                objectName: "comboModeloComanda"
                                width: 400
                                model: raiz.modelosImpressao
                                textRole: "rotulo"
                                valueRole: "chave"
                                // Desabilitado sem fonte escolhida porque aí
                                // não há desenho nenhum a dispor: quem monta o
                                // cupom é a impressora. Deixar o combo ativo
                                // faria a escolha parecer surtir efeito.
                                enabled: raiz.fonteImpressao !== ""
                                opacity: enabled ? 1 : 0.5

                                // Mesmo padrão do combo de fonte: currentIndex
                                // não é binding vivo, então é recalculado a
                                // cada releitura da configuração.
                                function sincronizarSelecao() {
                                    for (var i = 0; i < raiz.modelosImpressao.length; i++) {
                                        if (raiz.modelosImpressao[i].chave === raiz.modeloImpressao) {
                                            currentIndex = i;
                                            return;
                                        }
                                    }
                                    // Modelo gravado que esta versão do app não
                                    // conhece (veio de uma máquina mais nova
                                    // pela malha). Mostra o primeiro, SEM
                                    // escrever em modeloImpressao — apagar aqui
                                    // a escolha do dono a desfaria em todas as
                                    // máquinas na próxima gravação, e é a mesma
                                    // regra que o Python segue ao desenhar.
                                    currentIndex = 0;
                                }

                                Component.onCompleted: sincronizarSelecao()
                                Connections {
                                    target: raiz

                                    function onModelosImpressaoChanged() {
                                        comboModelo.sincronizarSelecao();
                                    }

                                    // Também quando só a escolha muda: é o caso
                                    // de "Restaurar padrões".
                                    function onModeloImpressaoChanged() {
                                        comboModelo.sincronizarSelecao();
                                    }
                                }
                                onActivated: raiz.modeloImpressao = currentValue

                                delegate: ItemDelegate {
                                    width: comboModelo.width
                                    text: modelData.rotulo
                                    font.pixelSize: Estilo.global.fontSize.lg
                                    highlighted: comboModelo.highlightedIndex === index
                                    palette.text: Estilo.global.textInput
                                    palette.highlightedText: Estilo.global.textInput
                                }

                                contentItem: Text {
                                    text: comboModelo.displayText
                                    font.pixelSize: Estilo.global.fontSize.lg
                                    color: Estilo.global.textInput
                                    leftPadding: 10
                                    rightPadding: 10
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: Estilo.global.inputBackground
                                    border.color: comboModelo.activeFocus ? raiz.corDestaque : Estilo.global.border
                                    border.width: comboModelo.activeFocus ? 2 : 1
                                    implicitHeight: 38
                                }
                            }

                            Text {
                                width: 400
                                wrapMode: Text.WordWrap
                                text: raiz.fonteImpressao === "" ? "Só vale com uma fonte escolhida acima: sem ela quem monta o cupom é a própria impressora, e não há desenho a dispor." : raiz.descricaoModelo
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.textSecondary
                            }

                            // Ressalvas que só o modelo em colunas tem. Ficam
                            // aqui, e não no catálogo do Python, porque são
                            // sobre o que a TELA mostra e sobre estilos que
                            // esta mesma tela deixa configurar logo acima.
                            Text {
                                width: 400
                                wrapMode: Text.WordWrap
                                visible: raiz.tabelaEmColunas
                                text: "Nas três colunas o texto sai sempre no tamanho normal, mesmo em campos configurados maiores — ampliação não cabe numa coluna estreita. Recibos de extra e de fechamento não têm tabela de itens e continuam saindo no modelo clássico."
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.textSecondary
                            }
                        }

                        // Título próprio: a prévia responde "como vai ficar",
                        // e daqui pra baixo é "como ficou de verdade" — o
                        // papel na mão, que é o único juiz de fonte e
                        // disposição numa impressora térmica.
                        Text {
                            text: "TESTE"
                            font.pixelSize: Estilo.global.fontSize.xl
                            font.bold: true
                            color: raiz.corDestaque
                        }

                        Column {
                            spacing: Estilo.global.spacing.md

                            Text {
                                width: 400
                                wrapMode: Text.WordWrap
                                text: "Imprime a comanda de exemplo acima, com a fonte, o modelo e os estilos escolhidos. Sai marcada como COMANDA DE TESTE, não é gravada e não aparece na Consulta."
                                font.pixelSize: Estilo.global.fontSize.md
                                color: Estilo.global.text
                            }

                            Button {
                                id: btnImprimirExemplo

                                // Nomeado pelo mesmo motivo dos combos acima:
                                // deixa o botão alcançável de fora para
                                // inspeção e teste.
                                objectName: "botaoImprimirExemplo"
                                padding: 8
                                focusPolicy: Qt.NoFocus
                                // Sem máquina eleita não há pra onde mandar, e
                                // o clique só renderia a notificação de erro
                                // que a malha devolve alguns instantes depois.
                                enabled: raiz.origemFontes.conhecida
                                opacity: enabled ? 1 : 0.5
                                onClicked: raiz.imprimirExemplo()

                                contentItem: Row {
                                    spacing: Estilo.global.spacing.xs
                                    Icone {
                                        nome: "fa6s.print"
                                        cor: Estilo.global.textOnAccent
                                        tamanho: Estilo.global.fontSize.lg
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: "Imprimir comanda de exemplo"
                                        font.family: Estilo.global.fontFamily.title
                                        color: Estilo.global.textOnAccent
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: btnImprimirExemplo.down ? Estilo.action.confirm.pressed : (btnImprimirExemplo.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                                }
                            }

                            // Onde o papel vai sair, e o que o clique faz
                            // antes de imprimir. As duas coisas surpreendem se
                            // não estiverem escritas: a impressora costuma
                            // estar em OUTRA máquina, e o teste grava as
                            // alterações pendentes pra que o papel mostre o
                            // que está na tela (ver imprimirExemplo).
                            Text {
                                width: 400
                                wrapMode: Text.WordWrap
                                text: !raiz.origemFontes.conhecida ? "Nenhuma máquina com impressora foi encontrada agora — não há pra onde mandar o teste." : (raiz.origemFontes.local ? "Sai na impressora desta máquina." : "Sai na impressora de " + raiz.origemFontes.maquina + ", que é a máquina que está imprimindo.") + (raiz.alteracoesPendentes ? " As alterações pendentes são gravadas antes, para o papel sair com o que está na tela." : "")
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.textSecondary
                            }
                        }
                    }
                }
            }
        }

    }

    PopupEstiloCampo {
        id: popupEstiloCampo

        // Nomeado pelo mesmo motivo dos popups das outras telas: deixa o
        // editor alcançável de fora para inspeção e teste.
        objectName: "popupEstiloCampo"

        controlador: raiz
    }

}
