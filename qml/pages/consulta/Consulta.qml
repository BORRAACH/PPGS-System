import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"
import "../../components/EdicaoComanda.js" as EdicaoComanda
// A normalização de texto (Texto.js) agora acontece dentro do índice de
// busca, não mais aqui — ver BuscaComandas.js.
import "BuscaComandas.js" as BuscaComandas

Page {
    id: telaConsulta

    objectName: "telaConsulta"

    focus: true

    // Comanda atualmente exibida no painel da direita (objeto simples com
    // tipo/arquivo/conteudo). null enquanto nada foi selecionado ainda.
    property var comandaSelecionada: null
    // Identifica a comanda destacada na lista pelo nome do arquivo (chave
    // estável), não pelo índice — a busca reordena a lista a qualquer
    // momento (inclusive ao ser limpa pelo Enter), o que deixaria um índice
    // guardado apontando para a comanda errada.
    property string arquivoSelecionado: ""
    // Lista bruta (mais recente primeiro), como veio do controller: SÓ os
    // últimos janelaCargaDias dias, não o acervo inteiro. Os dias anteriores
    // ficam em _diasNaoCarregados até alguém abrir a caixinha de um deles.
    property var _todasComandas: []

    // Quanto tempo pra trás a página carrega de verdade ao abrir. Comanda mais
    // antiga que isto continua na lista, mas só como a caixinha do dia dela:
    // o dia e a contagem, sem nenhum arquivo lido — a leitura acontece no
    // clique que abre a caixinha (ver carregarDia).
    //
    // POR QUE EXISTE ESTE LIMITE, e por que ele é separado do da busca. Montar
    // a lista custa, POR COMANDA, uma leitura de disco, uma decodificação do
    // cupom inteiro e meia dúzia de regex sobre ele (ver
    // consultaController._montar_comandas) — e isso acontecia com o acervo
    // INTEIRO a cada abertura da página, que só cresce e nunca diminui. A
    // janela de busca (janelaBuscaDias) não resolvia esse caso: ela recorta o
    // que a PESQUISA alcança, e a pesquisa é preguiçosa; o que travava era
    // quem abria a Consulta sem pesquisar nada, que é o uso mais comum.
    //
    // Dois dias porque é o que se olha sem procurar: as comandas de hoje, e as
    // de ontem que ficaram por conferir. Pedido mais antigo que isso se
    // procura pelo dia — e o dia está lá, na caixinha, a um clique.
    readonly property int janelaCargaDias: 2

    // Os dias mais antigos que a janela de carga, como vieram de
    // consultaController.listarDiasAnteriores: [{dia, chave, quantidade,
    // fechadas}], mais recente primeiro. Só rótulo e contagem — nenhuma
    // comanda destes dias foi lida do disco ainda.
    property var _diasNaoCarregados: []

    // Índice de busca de _todasComandas: o texto de cada comanda já
    // normalizado, mais duas listas ordenadas (por nome e por código) sobre as
    // quais a barra de pesquisa faz busca binária. Ver BuscaComandas.js.
    //
    // null = ainda não montado. É PREGUIÇOSO de propósito: montá-lo custa uma
    // normalização do cupom inteiro de cada comanda, e quem abre a Consulta só
    // pra olhar as comandas do dia (o uso mais comum) nunca pesquisa nada —
    // não faz sentido pagar isso no caminho de abertura da página, que esta
    // tela já trata com cuidado (ver CargaDiferida abaixo). Volta a null
    // sempre que a lista bruta muda.
    property var _indiceBusca: null
    // As comandas que o índice acima cobre: só as dentro da janela de busca
    // (ver janelaBuscaDias). Montada junto com o índice, pelo mesmo
    // _prepararIndiceBusca, e zerada junto com ele.
    //
    // Ela existe como propriedade, e não como variável local da busca, porque
    // é ela — e não _todasComandas — que a busca reordena e devolve: as
    // posições do índice são posições NESTA lista.
    property var _comandasBuscaveis: []

    // Quanto tempo pra trás a barra de pesquisa alcança. Comanda mais antiga
    // que isto continua na lista (na caixinha do dia dela, como sempre), mas
    // fica fora do índice e fora do resultado de qualquer pesquisa.
    //
    // POR QUE EXISTE UM LIMITE. Sem ele, tudo que a busca faz cresce junto
    // com o arquivo inteiro da pizzaria, que só aumenta e nunca diminui: o
    // índice normaliza o cupom inteiro de cada comanda (alguns milhares de
    // caracteres cada), a varredura por conteúdo passa por todas elas a cada
    // pesquisa, e o resultado — que é a lista inteira, porque a busca reordena
    // — vira um append por comanda no ListModel, criando um delegate para cada
    // uma (ver _preencherModelo e ColunaEsquerda.qml). Depois de alguns anos
    // de pedidos isso é lento por construção, e nenhuma estrutura de busca
    // conserta a parte de "montar uma saída de n itens".
    //
    // Com a janela, todos esses custos passam a depender do movimento de UMA
    // SEMANA, não do acervo: a pizzaria pode acumular comandas pra sempre que
    // a pesquisa continua custando o mesmo. E uma semana é o alcance que a
    // busca realmente serve — quem procura uma comanda pelo nome do cliente
    // está atrás de um pedido recente (conferir, reimprimir, cobrar); pedido
    // de meses atrás se procura pelo dia, na caixinha, que continua ali.
    readonly property int janelaBuscaDias: 7
    // "dd/mm/aaaa" do dia mais antigo que a busca alcança. Guardado num campo
    // (e não recalculado em cada binding) porque ColunaEsquerda.qml o exibe
    // ao usuário: é o texto que torna o limite explícito na tela. Recalculado
    // a cada leitura do disco, então acompanha a virada da meia-noite num app
    // que fica aberto a noite toda.
    property string diaLimiteBusca: _diaLimiteBusca()

    // Texto de busca atual: o campo de texto vive em ColunaEsquerda.qml, mas
    // o filtro precisa sobreviver a um "Atualizar" (que recarrega o disco).
    property string buscaAtual: ""
    // "todas" | "abertas" | "fechadas" — comanda aberta ainda não recebeu
    // baixa e está fora do caixa do dia (ver services/rede/baixaComandas.py).
    // O seletor vive em ColunaEsquerda.qml, mas o valor fica aqui pelo mesmo
    // motivo de buscaAtual: precisa sobreviver a um "Atualizar".
    property string filtroStatus: "todas"

    // Verdadeiro do pedido de carregamento até a última comanda entrar na
    // lista. ColunaEsquerda.qml mostra a caixa "Carregando..." enquanto
    // isso, e PainelDetalhe.qml segura a mensagem de lista vazia — que,
    // durante o carregamento, seria simplesmente mentira.
    property bool carregando: false

    // Comandas ainda não colocadas no modelo, e por onde o preenchimento em
    // lotes está (ver _preencherModelo/_proximoLote). Os grupos de dias
    // anteriores esperam o fim dos lotes: cada caixinha cria delegates, e
    // elas ficam abaixo da dobra, então não vale atrasar o que está à vista.
    property var _lotePendente: []
    property int _loteIndice: 0
    property var _gruposPendentes: []

    // Comandas por lote. Um número baixo devolve o controle à interface com
    // frequência (a caixa "Carregando..." continua girando, a busca continua
    // digitável); um alto termina antes, mas voltando a travar tudo num só
    // passo de JavaScript. 25 é o meio-termo que mantém cada lote na casa de
    // poucos milissegundos mesmo nas máquinas fracas da pizzaria.
    readonly property int _tamanhoLote: 25

    // Exposto para AreaPrincipal.qml/ColunaEsquerda.qml preencherem a lista.
    property alias modelo: modeloComandas

    // Comandas de dias anteriores, agrupadas — [{"dia": "01/08/2026",
    // "comandas": [...]}], mais recente primeiro. modeloComandas (acima)
    // passa a valer só para "hoje" (ver _agruparPorDia). Vazio durante uma
    // busca: pesquisar deve achar a comanda em qualquer dia sem precisar
    // abrir a caixinha certa primeiro (mesmo espírito de "busca só reordena,
    // nunca esconde" já documentado em aplicarFiltro).
    property var gruposAnteriores: []

    // "02/08/2026 10:00:00" -> "02/08/2026"; "" fica "" (comanda sem Data:
    // no cabeçalho — arquivo muito antigo/corrompido).
    function _diaDeDataHora(dataHora) {
        if (!dataHora)
            return "";
        var espaco = dataHora.indexOf(" ");
        return espaco === -1 ? dataHora : dataHora.substring(0, espaco);
    }

    // Date -> "dd/mm/aaaa", o mesmo formato que o cabeçalho do cupom usa (e
    // que _chaveDia abaixo sabe ler).
    function _formatarDia(d) {
        function doisDigitos(n) {
            return n < 10 ? "0" + n : String(n);
        }
        return doisDigitos(d.getDate()) + "/" + doisDigitos(d.getMonth() + 1) + "/" + d.getFullYear();
    }

    function _hojeFormatado() {
        return telaConsulta._formatarDia(new Date());
    }

    // Dia mais antigo que a busca alcança: hoje menos a janela inteira, então
    // uma comanda de exatamente uma semana atrás ainda é pesquisável.
    //
    // A conta sai do Date, e não de uma subtração na chave numérica de
    // _chaveDia, porque só ele sabe atravessar virada de mês e de ano (dia 3
    // de março menos 7 é 24 de fevereiro, e em ano bissexto é 25).
    function _diaLimiteBusca() {
        var d = new Date();
        d.setDate(d.getDate() - telaConsulta.janelaBuscaDias);
        return telaConsulta._formatarDia(d);
    }

    // "dd/mm/aaaa" -> número comparável, pra ordenar os dias anteriores do
    // mais recente pro mais antigo mesmo se a lista de entrada não vier
    // perfeitamente ordenada por dia (uma comanda sincronizada com atraso de
    // outra máquina tem "modificadoEm" de agora, mas um dia de dias atrás no
    // nome do arquivo — ver consultaController._montar_comandas).
    function _chaveDia(dia) {
        var partes = dia.split("/");
        if (partes.length !== 3)
            return 0;
        return Number(partes[2]) * 10000 + Number(partes[1]) * 100 + Number(partes[0]);
    }

    // Quantas comandas de um dia ainda não carregado passam no filtro de
    // status atual. Sai das duas contagens que listarDiasAnteriores já traz
    // (total e fechadas), sem abrir arquivo nenhum — é o que deixa a caixinha
    // de um dia velho mostrar o número CERTO mesmo com "Abertas" selecionado,
    // em vez de prometer comandas que sumiriam ao abrir.
    function _quantidadeNoFiltro(diaNaoCarregado) {
        if (telaConsulta.filtroStatus === "fechadas")
            return diaNaoCarregado.fechadas;
        if (telaConsulta.filtroStatus === "abertas")
            return diaNaoCarregado.quantidade - diaNaoCarregado.fechadas;
        return diaNaoCarregado.quantidade;
    }

    // O dia de uma comanda, para efeito de agrupamento. Vem do NOME do
    // arquivo (campo "dia", posto pelo controller), não do "Data:" do cupom:
    // é pelo nome que listarDiasAnteriores conta os dias antigos, e as duas
    // contas precisam bater — senão um cupom com data divergente do nome
    // abriria duas caixinhas do mesmo dia, uma vinda de cada lado. O
    // "Data:" fica de reserva para o arquivo cujo nome não segue o padrão.
    function _diaDoItem(item) {
        return item.dia ? item.dia : telaConsulta._diaDeDataHora(item.dataHora);
    }

    // Separa `lista` (já filtrada por status) em "hoje" (vai pro
    // modeloComandas, exibido direto) e o resto, agrupado por dia em
    // gruposAnteriores (cada grupo aninhado numa caixinha fechada por
    // padrão — ver ColunaEsquerda.qml, mesmo padrão de "Mapeamento por
    // origem" em Fechamento.qml).
    //
    // Depois dos dias que vieram carregados (os de dentro de janelaCargaDias)
    // entram os que NÃO vieram, como caixinhas vazias marcadas
    // "carregado: false" — mesma aparência, mesma contagem, e o conteúdo lido
    // do disco só quando alguém as abrir. Não há risco de um dia aparecer nas
    // duas listas: o controller usa o mesmo corte, pela mesma data, para
    // decidir o que carrega e o que apenas conta.
    function _agruparPorDia(lista) {
        var hojeStr = telaConsulta._hojeFormatado();
        var hoje = [];
        var mapaDias = {};
        var ordemDias = [];

        for (var i = 0; i < lista.length; i++) {
            var item = lista[i];
            var dia = telaConsulta._diaDoItem(item);
            // Sem data (arquivo antigo/corrompido) cai em "hoje" — melhor
            // continuar visível direto do que sumir dentro de uma caixinha
            // sem rótulo nenhum.
            if (dia === hojeStr || dia === "") {
                hoje.push(item);
                continue;
            }
            if (!mapaDias[dia]) {
                mapaDias[dia] = [];
                ordemDias.push(dia);
            }
            mapaDias[dia].push(item);
        }

        ordemDias.sort(function (a, b) {
            return telaConsulta._chaveDia(b) - telaConsulta._chaveDia(a);
        });

        var grupos = [];
        for (var k = 0; k < ordemDias.length; k++)
            grupos.push({
                "dia": ordemDias[k],
                "chave": "",
                "comandas": mapaDias[ordemDias[k]],
                "quantidade": mapaDias[ordemDias[k]].length,
                "carregado": true
            });

        for (var j = 0; j < telaConsulta._diasNaoCarregados.length; j++) {
            var anterior = telaConsulta._diasNaoCarregados[j];
            var quantidade = telaConsulta._quantidadeNoFiltro(anterior);
            // Dia inteiro fora do filtro não vira caixinha: uma caixa "0
            // comandas" que abre vazia é só ruído entre os dias que têm o que
            // mostrar.
            if (quantidade <= 0)
                continue;

            grupos.push({
                "dia": anterior.dia,
                "chave": anterior.chave,
                "comandas": [],
                "quantidade": quantidade,
                "carregado": false
            });
        }

        telaConsulta._preencherModelo(hoje, grupos);
    }

    // Lê do disco as comandas de UM dia ainda não carregado, já filtradas pelo
    // status selecionado. Chamado por ColunaEsquerda.qml na primeira vez que a
    // caixinha do dia é aberta — e só nela: o resultado fica no ListModel da
    // própria caixinha, então reabrir não relê nada.
    function carregarDia(chave) {
        return consultaController.listarComandasDoDia(chave).filter(telaConsulta._passaNoStatus);
    }

    // Único caminho que preenche a lista exibida.
    //
    // Durante o carregamento da página preenche aos poucos, um lote por
    // quadro: com algumas centenas de comandas, apender tudo de uma vez
    // segura a interface inteira num só passo de JavaScript — e é justamente
    // esse passo que cria os ItemComandaDelegate, já que a ListView de "hoje"
    // tem a altura amarrada ao contentHeight e por isso não recicla delegate
    // nenhum (ver ColunaEsquerda.qml).
    //
    // Fora do carregamento (busca/filtro, com a lista já em tela) preenche de
    // uma vez só: ali o usuário espera o resultado da tecla que acabou de
    // digitar, e ver a lista se remontando aos pedaços seria pior do que o
    // instante parado.
    function _preencherModelo(lista, grupos) {
        timerLote.stop();
        modeloComandas.clear();
        telaConsulta.gruposAnteriores = [];

        if (!telaConsulta.carregando) {
            for (var i = 0; i < lista.length; i++)
                modeloComandas.append(lista[i]);
            telaConsulta.gruposAnteriores = grupos;
            return;
        }

        telaConsulta._lotePendente = lista;
        telaConsulta._loteIndice = 0;
        telaConsulta._gruposPendentes = grupos;
        // O primeiro lote entra agora, não no próximo quadro: as comandas do
        // topo (as mais recentes, que são as que interessam) aparecem junto
        // com a tela, sem um piscar de lista vazia antes.
        telaConsulta._proximoLote();
    }

    function _proximoLote() {
        var lista = telaConsulta._lotePendente;
        var fim = Math.min(telaConsulta._loteIndice + telaConsulta._tamanhoLote, lista.length);
        for (var i = telaConsulta._loteIndice; i < fim; i++)
            modeloComandas.append(lista[i]);
        telaConsulta._loteIndice = fim;

        if (fim < lista.length) {
            timerLote.restart();
            return;
        }

        telaConsulta.gruposAnteriores = telaConsulta._gruposPendentes;
        telaConsulta._lotePendente = [];
        telaConsulta._gruposPendentes = [];
        telaConsulta.carregando = false;
    }

    // Monta "Nome do Cliente - horário" a partir dos campos já extraídos
    // pelo consultaController (lidos do cabeçalho do próprio cupom).
    function tituloComanda(item) {
        var cliente = item.cliente && item.cliente.trim() !== "" ? item.cliente.trim() : "Cliente não informado";
        return item.dataHora ? cliente + " - " + item.dataHora : cliente;
    }

    // Um item passa pelo seletor "Todas/Abertas/Fechadas"? Comanda aberta
    // ainda não recebeu baixa e está fora do caixa do dia.
    function _passaNoStatus(item) {
        if (telaConsulta.filtroStatus === "todas")
            return true;
        return (item.fechada === true) === (telaConsulta.filtroStatus === "fechadas");
    }

    // Monta, de uma vez só, a janela pesquisável e o índice sobre ela.
    //
    // É PREGUIÇOSO de propósito (chamado só na primeira pesquisa depois de
    // cada carregamento), e é justamente por isso que a janela da busca pode
    // ser MAIOR que a da carga: quem abre a Consulta só pra olhar as comandas
    // do dia — o uso mais comum — nunca paga por esta leitura, e quem pesquisa
    // já está esperando por um resultado. As duas janelas respondem a coisas
    // diferentes: janelaCargaDias é o que aparece sem pedir, janelaBuscaDias é
    // o quanto a pesquisa alcança quando alguém pede.
    //
    // A janela é recortada no controller, pela data embutida no NOME do
    // arquivo (ver listarComandasRecentes), e não aqui por uma passada sobre a
    // lista bruta: a lista bruta agora é só a janela de carga, e a busca
    // precisa enxergar mais do que ela. Ler o dia do nome também evita abrir
    // as comandas velhas só pra descobrir a data delas — que era metade do
    // custo que a janela existia pra evitar.
    //
    // A busca binária de verdade está em BuscaComandas.js, sobre o índice que
    // sai daqui.
    function _prepararIndiceBusca() {
        if (telaConsulta._indiceBusca !== null)
            return;

        var janela = consultaController.listarComandasRecentes(telaConsulta.janelaBuscaDias);
        telaConsulta._comandasBuscaveis = janela;
        telaConsulta._indiceBusca = BuscaComandas.construirIndice(janela, function (item) {
            return telaConsulta.tituloComanda(item);
        });
    }

    // Reordena as comandas pesquisáveis pela proximidade com o texto digitado
    // e repopula o modelo exibido na lista.
    //
    // DUAS COISAS ESCONDEM COMANDA AQUI, e as duas são explícitas na tela:
    //
    // - o filtro por status, escolha direta do usuário no seletor;
    // - a janela de busca, que tira do resultado tudo que é mais velho que
    //   janelaBuscaDias (o aviso em ColunaEsquerda.qml diz isso, com a data
    //   limite escrita por extenso).
    //
    // A busca em si continua sem esconder nada: dentro da janela ela só
    // reordena, e toda comanda da janela sai no resultado, casando ou não.
    // Comanda mais velha que a janela não some do aplicativo — ela continua na
    // caixinha do dia dela assim que o campo de pesquisa é limpo.
    //
    // A ordenação em si é busca binária sobre um índice ordenado, montado uma
    // vez por carregamento em vez de a cada tecla — ver BuscaComandas.js, que
    // explica o que a binária resolve (prefixo do nome do cliente e do código,
    // que é como se procura uma comanda na prática) e o que continua exigindo
    // varredura (achar um pedaço no meio do cupom) — varredura essa que agora
    // é sobre a janela, não sobre o acervo.
    function aplicarFiltro() {
        var busca = telaConsulta.buscaAtual.trim();

        if (busca === "") {
            var lista = telaConsulta._todasComandas.filter(telaConsulta._passaNoStatus);
            telaConsulta._agruparPorDia(lista);
            return;
        }

        telaConsulta._prepararIndiceBusca();

        var ordenadas = BuscaComandas.ordenar(telaConsulta._indiceBusca, telaConsulta._comandasBuscaveis, busca, telaConsulta._passaNoStatus);

        // Busca mostra tudo achatado, sem agrupar por dia — encontrar a
        // comanda certa não deveria exigir abrir a caixinha do dia certo
        // primeiro.
        telaConsulta._preencherModelo(ordenadas, []);
    }

    // Pede o recarregamento da lista sem fazê-lo agora: quem chama aqui é
    // sempre alguém que acabou de mexer na tela (abrir a página, apagar uma
    // comanda, receber um pedido da rede), e a leitura em si — ler todo o
    // pedidos/ do disco e remontar a lista — leva tempo suficiente pra
    // segurar o primeiro quadro da página inteira.
    //
    // A CargaDiferida resolve duas coisas de uma vez: segura a leitura até o
    // primeiro quadro da página estar na tela, pra interface aparecer antes
    // das comandas, e junta numa leitura só as chamadas em rajada (a página
    // chama duas vezes ao abrir,
    // por Component.onCompleted e StackView.onActivated, e a malha chama uma
    // vez por pedido recebido durante uma sincronização).
    function carregarComandas() {
        telaConsulta.carregando = true;
        telaConsulta.comandaSelecionada = null;
        telaConsulta.arquivoSelecionado = "";
        carga.agendar();
    }

    function _lerDoDisco() {
        // Duas chamadas, e as duas baratas: a primeira lê de verdade só os
        // últimos janelaCargaDias dias, e a segunda nem abre arquivo — conta
        // os dias antigos pela data no nome (ver
        // consultaController.listarDiasAnteriores). O acervo inteiro não é
        // mais tocado aqui, que é o ponto: este é o caminho de abertura da
        // página, e ele passa a custar o mesmo com um mês ou com dez anos de
        // pedidos guardados.
        telaConsulta._todasComandas = consultaController.listarComandasRecentes(telaConsulta.janelaCargaDias);
        telaConsulta._diasNaoCarregados = consultaController.listarDiasAnteriores(telaConsulta.janelaCargaDias);
        // O disco mudou, então o índice de busca envelheceu junto — e com ele
        // a janela pesquisável. Voltam a vazio em vez de serem remontados
        // aqui: a remontagem é o passo caro, e ela relê o disco (a janela da
        // busca é maior que a da carga), então só acontece se alguém
        // pesquisar.
        telaConsulta._indiceBusca = null;
        telaConsulta._comandasBuscaveis = [];
        // Refeito a cada leitura porque o app da pizzaria fica aberto a noite
        // toda: sem isto, o limite continuaria valendo o de ontem depois da
        // virada da meia-noite — e o aviso na tela estaria mentindo.
        telaConsulta.diaLimiteBusca = telaConsulta._diaLimiteBusca();
        telaConsulta.aplicarFiltro();
    }

    // Marca a comanda dada como selecionada (pelo nome do arquivo, não pela
    // posição na lista), preenchendo o painel de detalhe à direita — usado
    // tanto pelo clique num item (ItemComandaDelegate.qml) quanto pelo Enter
    // na busca, que seleciona o melhor match (ver ColunaEsquerda.qml).
    function selecionarComanda(item) {
        telaConsulta.arquivoSelecionado = item.arquivo;
        telaConsulta.comandaSelecionada = {
            "tipo": item.tipo,
            "arquivo": item.arquivo,
            "conteudo": item.conteudo,
            "cliente": item.cliente,
            "dataHora": item.dataHora,
            "codigo": item.codigo,
            "maquinaOrigem": item.maquinaOrigem,
            "emConflito": item.emConflito === true,
            "motivoConflito": item.motivoConflito
        };
    }

    // Reabre a comanda no formulário de Balcão ou Entrega (conforme o tipo
    // original) já preenchida, para edição estruturada e reimpressão. O
    // formulário guarda "arquivoOriginal" e apaga esse arquivo assim que a
    // versão editada é impressa com sucesso, para não deixar duplicata.
    // O mapeamento dos campos está em components/EdicaoComanda.js, que o
    // popup de fechamento rápido também usa.
    function editarComanda(nomeArquivo) {
        EdicaoComanda.abrir(telaConsulta.StackView.view, nomeArquivo);
    }

    // Permite digitar direto na tela para pesquisar, sem precisar clicar
    // antes na barra de busca — qualquer tecla "imprimível" (letras,
    // números, acentos) foca a barra (dentro de AreaPrincipal/ColunaEsquerda)
    // e já entra com o caractere digitado.
    Keys.onPressed: function (event) {
        var campoBusca = areaPrincipal.campoBusca;
        if (campoBusca && !campoBusca.activeFocus && event.key >= Qt.Key_Space && event.key <= Qt.Key_ydiaeresis) {
            campoBusca.forceActiveFocus();
            campoBusca.text += event.text;
            event.accepted = true;
        }
    }

    // Conexão declarativa, não um .connect() solto em Component.onCompleted
    // — mesmo motivo documentado em Balcao.qml/Rede.qml: consultaController
    // é global e vive pra sempre, então a conexão precisa estar presa ao
    // ciclo de vida desta página (Connections), não solta num closure.
    Connections {
        target: consultaController

        // Recarrega sozinho quando um pedido de outra máquina da rede
        // chega/some (ver redeController/consultaController.aplicarPedidoRemoto).
        function onComandasAtualizadas() {
            carregarComandas();
        }
    }

    // O selo Aberta/Fechada muda por uma ação que acontece na página de
    // Fechamento (ou em outra máquina da malha), não aqui — daí o segundo
    // controller. Sem isto, uma comanda baixada continuaria aparecendo como
    // aberta até alguém clicar em "Atualizar".
    Connections {
        target: fechamentoController

        function onBaixasAtualizadas() {
            carregarComandas();
        }
    }

    Component.onCompleted: {
        carregarComandas();
    }
    // "focus: true" sozinho não é suficiente: StackView assume o controle do
    // foco ao trocar de página, então é preciso pedir foco de novo quando
    // esta página vira a atual (senão digitar sem clicar antes não funciona).
    StackView.onActivated: {
        carregarComandas();
        forceActiveFocus();
    }

    background: Rectangle {
        color: Estilo.global.background
        radius: Estilo.global.radius.xl
    }

    ListModel {
        id: modeloComandas
    }

    // Era um Timer de 50ms chutado "na esperança" de que um quadro coubesse
    // nesse meio-tempo. CargaDiferida não chuta: espera o frameSwapped da
    // janela, o sinal que significa literalmente "este quadro foi entregue à
    // tela" — e nas máquinas lentas, onde um quadro leva bem mais de 50ms, é
    // justamente onde o chute falhava (ver components/CargaDiferida.qml).
    CargaDiferida {
        id: carga

        tarefa: function() {
            telaConsulta._lerDoDisco();
        }
    }

    // Um lote por quadro (ver _proximoLote). 16ms é o intervalo de um quadro
    // a 60Hz: o suficiente pra interface repintar e processar cliques entre
    // um lote e outro.
    Timer {
        id: timerLote

        interval: 16
        repeat: false
        onTriggered: telaConsulta._proximoLote()
    }

    PopupConfirmarExclusao {
        id: popupConfirmarExclusao

        onComandaApagada: telaConsulta.carregarComandas()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: Estilo.global.spacing.xl

        // --- CABEÇALHO ---
        RowLayout {
            Layout.fillWidth: true
            spacing: Estilo.global.spacing.xl

            Row {
                spacing: Estilo.global.spacing.sm
                Icone { nome: "fa6s.magnifying-glass"; cor: Estilo.screen.consulta.accent; tamanho: Estilo.global.fontSize.title; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "CONSULTA DE COMANDAS"
                    font.pixelSize: Estilo.global.fontSize.title
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.screen.consulta.accent
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Row {
                spacing: Estilo.global.spacing.xs
                Icone { nome: "fa6s.globe"; cor: Estilo.global.textSecondary; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    // O guard existe porque, no encerramento do app, as
                    // context properties são destruídas antes das telas: sem
                    // ele este binding roda uma última vez com
                    // redeController já nulo e deixa um TypeError no
                    // logs/app.log a cada fechamento — ruído bem no arquivo
                    // que se usa pra diagnosticar problema de rede.
                    text: (redeController ? redeController.quantidadeConectados : 0) + " conectado(s)"
                    font.pixelSize: Estilo.global.fontSize.lg
                    color: Estilo.global.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Button {
                id: btnAtualizar

                padding: 8
                onClicked: telaConsulta.carregarComandas()

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    Icone { nome: "fa6s.arrows-rotate"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Atualizar"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: parent.down ? Estilo.screen.consulta.pressed : (parent.hovered ? Estilo.screen.consulta.hover : Estilo.screen.consulta.base)
                }
            }
        }

        // --- ÁREA PRINCIPAL: LISTA (ESQUERDA) + DETALHE (DIREITA) ---
        AreaPrincipal {
            id: areaPrincipal

            Layout.fillWidth: true
            Layout.fillHeight: true
            pagina: telaConsulta
            popupExclusao: popupConfirmarExclusao
        }

        // --- BOTÃO VOLTAR ---
        Button {
            id: btnVoltar

            padding: Estilo.global.padding.md
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 200
            onClicked: {
                if (telaConsulta.StackView.view)
                    telaConsulta.StackView.view.irParaInicio();
            }

            contentItem: Row {
                spacing: Estilo.global.spacing.xs
                anchors.centerIn: parent
                Icone { nome: "fa6s.arrow-left"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "Voltar para o Menu"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                border.color: Estilo.action.danger.pressed
                border.width: Estilo.global.borderWidth.hairline
            }
        }
    }
}
