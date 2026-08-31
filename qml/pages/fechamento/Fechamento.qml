import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

// Fechamento de caixa diário — soma o total de todas as comandas lançadas
// no dia (Balcão/Entrega/Mesa, ver controllers/fechamentoController.py) e
// mostra de onde cada valor vem. Comandas suspeitas (ver
// comandaParserService.eh_suspeita) ganham borda vermelha na própria lista,
// em vez de uma área separada.
//
// O resumo é recalculado sozinho ao abrir a página (ou trocar de dia) —
// "hoje" sempre ao vivo, dias passados usam o cache local quando já existe
// (ver FechamentoController.obterFechamento). O botão "Fechar Caixa" força
// um recálculo na hora, pro caso de outra máquina ter lançado uma comanda
// nova enquanto esta tela já estava aberta.
Page {
    id: telaFechamento

    objectName: "telaFechamento"

    // ===== MEDIDAS DO LAYOUT =====
    // Esta tela é toda feita de Layouts, então já acompanhava a largura da
    // janela — mas só até certo ponto: um Layout nunca encolhe um filho
    // abaixo do tamanho que ele pede, e o cabeçalho (título + navegação de
    // data + quatro botões) mais os dois painéis lado a lado pediam bem mais
    // de 900px. O que passava disso simplesmente saía pela direita.
    readonly property real larguraUtil: width - Estilo.global.padding.xl * 2
    readonly property bool empilhado: larguraUtil < 900

    // Digitar qualquer letra/número em qualquer lugar da tela já começa a
    // busca, sem precisar clicar na barra primeiro. A página fica com o foco
    // do teclado (focus + o forceActiveFocus de StackView.onActivated abaixo)
    // e repassa a primeira tecla para o campo, que assume o foco a partir daí.
    //
    // event.text cobre exatamente o que se quer: vem preenchido para teclas
    // que produzem caractere e vazio para Shift/Ctrl/setas/F5. O filtro de
    // controle descarta Backspace, Tab, Enter e Esc, que também trazem texto
    // mas não são "começar a escrever". Ctrl/Alt pressionados ficam de fora
    // para não sequestrar atalhos.
    focus: true
    Keys.onPressed: function (event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return;
        if (!event.text || event.text.length === 0)
            return;
        if (event.text.charCodeAt(0) < 32 || event.key === Qt.Key_Delete)
            return;

        telaFechamento.comecarBusca(event.text);
        event.accepted = true;
    }

    // "AAAA-MM-DD" — sempre preenchida (ver hojeIso()/carregarDia()).
    property string dataSelecionada: ""
    // {data, total, quantidade, porTipo, abertas, extras} — {} antes da
    // primeira carga.
    property var resumoAtual: ({})

    // --- Busca no mapeamento por origem ---

    // O que está digitado na barra de busca. Filtra as comandas de todos os
    // tipos ao mesmo tempo (ver comandasDoTipo).
    property string termoBusca: ""

    // Nome de quem lançou a comanda; "" = todos. Junto com a busca por texto,
    // é o que decide quais comandas o "Mapeamento por origem" mostra.
    property string filtroUsuario: ""

    // Os nomes que o seletor oferece: os que aparecem nas comandas COM BAIXA
    // do dia, sem repetição e em ordem — as mesmas que o mapeamento lista, já
    // que uma comanda ainda sem baixa não entra em porTipo (ver
    // FechamentoController.calcularFechamento).
    //
    // Derivado do resumo, e não pedido ao Python: é a mesma lista que a tela
    // filtra, então não há como os dois discordarem. Trocar de dia refaz a
    // lista sozinho, e o seletor volta pra "Todos" quando o nome escolhido não
    // lançou nada no dia novo (ver components/FiltroUsuario.qml).
    readonly property var usuariosDoDia: {
        var vistos = {};
        for (var i = 0; i < telaFechamento.ordemTipos.length; i++) {
            var comandas = telaFechamento.infoTipo(telaFechamento.ordemTipos[i]).comandas || [];
            for (var j = 0; j < comandas.length; j++) {
                // Resumo em cache de antes deste campo existir não tem o nome —
                // ver FechamentoController._cache_atualizado, que manda
                // recalcular justamente por isso.
                var nome = ((comandas[j].usuario || "") + "").trim();
                if (nome !== "")
                    vistos[nome] = true;
            }
        }
        return Object.keys(vistos).sort();
    }
    // Normalizado uma vez por digitação, e não a cada comanda comparada: o
    // outro lado da comparação (o campo "busca" de cada comanda) já vem
    // normalizado do Python — ver FechamentoController._texto_de_busca.
    readonly property string _termoNormalizado: telaFechamento._normalizar(telaFechamento.termoBusca)
    readonly property bool buscando: telaFechamento._termoNormalizado !== ""

    // Comandas do dia que ainda não receberam baixa — vendas que existem mas
    // estão fora do caixa (ver services/rede/baixaComandas.py). A chave
    // "abertas" não existe em resumos gravados em cache por versões
    // anteriores, daí o valor padrão.
    readonly property var _abertas: telaFechamento.resumoAtual.abertas || ({
        "quantidade": 0,
        "total": 0
    })
    readonly property int quantidadeAberta: telaFechamento._abertas.quantidade || 0
    readonly property real totalAberto: telaFechamento._abertas.total || 0

    // Pagamentos de diária a funcionários lançados no dia — dinheiro que
    // sai do caixa fora de qualquer venda (ver services/rede/extrasCaixa.py
    // e FechamentoController._calcular_resumo_dia). A chave "extras" não
    // existe em resumos gravados em cache antes desta feature existir, daí
    // o valor padrão — mesmo cuidado de "_abertas" acima.
    readonly property var _extras: telaFechamento.resumoAtual.extras || ({
        "quantidade": 0,
        "total": 0,
        "itens": []
    })
    readonly property int quantidadeExtras: telaFechamento._extras.quantidade || 0
    readonly property real totalExtras: telaFechamento._extras.total || 0

    // Despesas do dia — contas do negócio pagas com dinheiro do caixa (gás,
    // embalagem, insumo comprado na hora). Ver services/rede/despesasCaixa.py.
    // Chave ausente em resumos gravados em cache antes desta feature existir,
    // daí o valor padrão — mesmo cuidado de "_extras" acima.
    readonly property var _despesas: telaFechamento.resumoAtual.despesas || ({
        "quantidade": 0,
        "total": 0,
        "itens": []
    })
    readonly property int quantidadeDespesas: telaFechamento._despesas.quantidade || 0
    readonly property real totalDespesas: telaFechamento._despesas.total || 0

    // Contagem manual de Cartão/Dinheiro/Pix do dia (ver
    // services/rede/contagemCaixa.py) — diferente de resumoAtual, não vem
    // do recálculo das comandas: é preenchida à parte por carregarDia() e
    // sobrescrita pelo popup de Contagem.
    property var contagemAtual: ({
        "cartao": 0,
        "dinheiro": 0,
        "pix": 0
    })
    // Verdadeira só durante gravarContagem() — ver o comentário lá e o uso
    // em onContagemAtualChanged.
    property bool gravandoContagem: false
    // Tudo que saiu da GAVETA hoje sem ser venda: diárias pagas a funcionário
    // e despesas do negócio. As duas coisas saem em dinheiro vivo, e é por
    // isso que se somam à cédula contada, e não ao cartão ou ao pix.
    readonly property real totalSaidasEmDinheiro: telaFechamento.totalExtras + telaFechamento.totalDespesas

    // O que TINHA na gaveta hoje: o que ainda está lá (contado à mão) mais o
    // que saiu dela para pagar diária e despesa.
    //
    // Somar pagamento a uma contagem de gaveta parece errado à primeira vista,
    // e é o contrário: sem isso, esse dinheiro aparece como falta em
    // diferencaCaixa — a gaveta acusa sumiço de um dinheiro cujo destino se
    // sabe exatamente qual foi, e quem confere fica caçando um buraco que não
    // existe.
    //
    // O campo digitado NÃO é alterado por isto, de propósito: ele é gravado em
    // disco e replicado na malha (ver contagemCaixa.py), então escrever a soma
    // dentro dele faria a diária ser somada de novo na próxima abertura da
    // tela, e de novo na seguinte. O que se guarda é o que a pessoa contou; a
    // soma é derivada.
    readonly property real dinheiroComSaidas: (telaFechamento.contagemAtual.dinheiro || 0)
        + telaFechamento.totalSaidasEmDinheiro

    readonly property real totalContagem: (telaFechamento.contagemAtual.cartao || 0)
        + telaFechamento.dinheiroComSaidas
        + (telaFechamento.contagemAtual.pix || 0)

    // Confere o caixa: o que foi contado à mão (Cartão+Dinheiro+Pix)
    // comparado com o que as comandas do dia dizem que foi vendido.
    // Positivo, sobrou dinheiro no caixa; negativo, faltou.
    //
    // Diária e despesa NÃO aparecem mais aqui como falta: elas já entraram na
    // contagem (ver dinheiroComSaidas). Antes apareciam, e o argumento era que
    // isso era o que se queria enxergar — mas na prática obrigava quem confere
    // a fazer a conta de cabeça toda vez para descontar o que ele mesmo tinha
    // acabado de lançar na tela.
    //
    // Cuidado ao ler o resultado: resumoAtual.total só conta comandas que
    // receberam baixa (ver FechamentoController._calcular_resumo_dia), então
    // comanda em aberto puxa isto pro lado de "sobrou" — o aviso de
    // "N comandas em aberto · R$ X fora do caixa", lá no total do dia, é
    // quem explica a diferença nesse caso.
    readonly property real diferencaCaixa: telaFechamento.totalContagem - (telaFechamento.resumoAtual.total || 0)
    // Empate conta como sobra: um caixa que bate exato não é falta.
    readonly property bool caixaSobrou: telaFechamento.diferencaCaixa >= 0

    // Lucro do dia: o que entrou na gaveta menos o que saiu dela em diária.
    // Conta diferente da de cima e independente dela — aqui o bruto não
    // entra, porque venda que ainda não virou dinheiro contado não é lucro
    // nenhum; o bruto serve pra conferir a gaveta (diferencaCaixa), não pra
    // dizer quanto sobrou no fim do dia.
    // O que entrou na gaveta menos o que saiu dela. Como as saídas agora entram
    // em totalContagem (ver dinheiroComSaidas) e são subtraídas aqui, elas se
    // anulam — e o lucro acaba sendo, exatamente, o dinheiro que sobrou:
    // cartão + dinheiro contado + pix.
    //
    // ISTO CORRIGE UM DESCONTO EM DOBRO que existia antes. A diária saía da
    // gaveta (logo, a contagem já era menor por causa dela) e ainda era
    // subtraída aqui — uma diária de R$ 80 tirava R$ 160 do lucro do dia. O
    // número que esta tela mostra ficou MAIOR por isso, e o valor novo é o
    // certo.
    readonly property real lucro: telaFechamento.totalContagem
        - telaFechamento.totalExtras
        - telaFechamento.totalDespesas

    readonly property var ordemTipos: ["Balcão", "Entrega", "Mesa"]
    readonly property var coresTipo: ({
        "Balcão": Estilo.orderType.balcao.base,
        "Entrega": Estilo.orderType.entrega.base,
        "Mesa": Estilo.orderType.mesa.base
    })

    function _doisDigitos(numero) {
        return numero < 10 ? "0" + numero : String(numero);
    }

    function _isoDeData(d) {
        return d.getFullYear() + "-" + _doisDigitos(d.getMonth() + 1) + "-" + _doisDigitos(d.getDate());
    }

    function hojeIso() {
        return _isoDeData(new Date());
    }

    function somarDias(iso, delta) {
        var partes = iso.split("-").map(Number);
        var d = new Date(partes[0], partes[1] - 1, partes[2]);
        d.setDate(d.getDate() + delta);
        return _isoDeData(d);
    }

    function formatarDataExibicao(iso) {
        if (!iso)
            return "";

        var partes = iso.split("-");
        return partes[2] + "/" + partes[1] + "/" + partes[0];
    }

    function mostrarNotificacao(mensagem, sucesso) {
        filaNotificacoes.notificar(mensagem, sucesso);
    }

    // Info de um tipo específico (Balcão/Entrega/Mesa) já com um valor
    // padrão seguro — nem toda comanda existe todo dia (ex: nenhuma
    // Entrega hoje), e porTipo só carrega as chaves que de fato tiveram
    // alguma comanda (ver FechamentoController._calcular_resumo_dia).
    function infoTipo(tipo) {
        var mapa = telaFechamento.resumoAtual.porTipo || {};
        return mapa[tipo] || {
            "total": 0,
            "quantidade": 0,
            "comandas": []
        };
    }

    // "Açaí" -> "acai". Mesma normalização que o Python aplica ao montar o
    // campo "busca" de cada comanda, para os dois lados da comparação
    // combinarem sem acento e sem diferença de caixa.
    function _normalizar(texto) {
        return (texto || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    }

    // As comandas de um tipo que casam com a busca atual — todas, quando não
    // há busca.
    //
    // É uma varredura simples pelo campo de busca de cada comanda. Não dá pra
    // usar busca binária aqui: ela exige dados ordenados pela chave procurada
    // e só responde "existe este valor exato", enquanto o que se quer é
    // "contém este trecho" em qualquer posição de qualquer campo — um termo
    // como "pizza" tem que achar comandas cujo texto NÃO começa por ele. Na
    // prática o custo não aparece: é um dia de comandas (dezenas a poucas
    // centenas), refiltrado a cada tecla em menos de um milissegundo.
    function comandasDoTipo(tipo) {
        var todas = telaFechamento.infoTipo(tipo).comandas || [];
        if (!telaFechamento.buscando && telaFechamento.filtroUsuario === "")
            return todas;

        var termo = telaFechamento._termoNormalizado;
        var achadas = [];
        for (var i = 0; i < todas.length; i++) {
            if (!telaFechamento._passaNoUsuario(todas[i]))
                continue;

            // Comandas de um resumo gravado em cache antes desta busca
            // existir não têm o campo — caem fora em vez de derrubar a tela.
            var alvo = todas[i].busca || "";
            if (!telaFechamento.buscando || alvo.indexOf(termo) >= 0)
                achadas.push(todas[i]);
        }
        return achadas;
    }

    // Quem lançou a comanda passa pelo seletor? "" = todos, inclusive as
    // comandas sem usuário nenhum; um nome escolhido casa exato.
    //
    // Diferente da busca por texto ao lado, este filtro também mexe nos
    // TOTAIS: totalDoTipo já soma o que comandasDoTipo devolve, então escolher
    // um usuário passa a mostrar quanto ele lançou em cada modalidade — que é
    // a pergunta que se faz ao filtrar o caixa por pessoa.
    function _passaNoUsuario(item) {
        if (telaFechamento.filtroUsuario === "")
            return true;
        return ((item.usuario || "") + "").trim() === telaFechamento.filtroUsuario;
    }

    function totalDoTipo(tipo) {
        if (!telaFechamento.buscando && telaFechamento.filtroUsuario === "")
            return telaFechamento.infoTipo(tipo).total || 0;

        var achadas = telaFechamento.comandasDoTipo(tipo);
        var soma = 0;
        for (var i = 0; i < achadas.length; i++)
            soma += Number(achadas[i].valor) || 0;
        return soma;
    }

    function totalEncontrado() {
        var total = 0;
        for (var i = 0; i < telaFechamento.ordemTipos.length; i++)
            total += telaFechamento.comandasDoTipo(telaFechamento.ordemTipos[i]).length;
        return total;
    }

    // Chamado pela captura de teclado da página: qualquer caractere digitado
    // fora de um campo de texto começa a busca (ver Keys.onPressed).
    function comecarBusca(texto) {
        campoBusca.forceActiveFocus();
        if (texto)
            campoBusca.insert(campoBusca.length, texto);
    }

    function limparBusca() {
        telaFechamento.termoBusca = "";
        campoBusca.text = "";
    }

    function carregarDia(iso) {
        // Digitação ainda pendente pertence ao dia que está na tela AGORA
        // (dataSelecionada só muda duas linhas abaixo) — sem esta descarga,
        // trocar de dia logo depois de digitar jogaria fora o valor, ou pior,
        // gravaria ele no dia novo quando o timer estourasse.
        telaFechamento.salvarContagemPendente();
        // A busca vale para o dia que está na tela: trocar de dia com um termo
        // antigo ainda filtrando esconderia comandas sem explicação.
        telaFechamento.limparBusca();
        telaFechamento.dataSelecionada = iso;
        telaFechamento.resumoAtual = fechamentoController.obterFechamento(iso);
        telaFechamento.contagemAtual = fechamentoController.obterContagem(iso);
    }

    // Chamado pelo botão "Salvar contagem" — sobrescreve a contagem do dia
    // visualizado e atualiza a tela na hora com o que foi de fato salvo. O
    // botão sobrevive ao salvamento automático porque é ele que dá o aviso
    // na tela: quem quer ver "salva" escrito com todas as letras clica.
    function salvarContagem(cartaoTexto, dinheiroTexto, pixTexto) {
        // Já vai gravar agora; deixar o timer de pé só faria uma segunda
        // gravação idêntica (e um segundo evento na malha) logo em seguida.
        salvamentoContagem.stop();
        telaFechamento.gravarContagem(cartaoTexto, dinheiroTexto, pixTexto);
        telaFechamento.mostrarNotificacao("Contagem de " + telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada) + " salva.", true);
    }

    // O caminho único de gravação da contagem: o botão acima e o salvamento
    // automático passam os dois por aqui.
    //
    // A bandeira existe por causa de onContagemAtualChanged, lá embaixo:
    // registrarContagem devolve a contagem salva e reescrever os campos com
    // ela é justamente o que mantém a tela honesta ao trocar de dia — mas
    // aqui a mudança veio do que o usuário está digitando neste instante, e
    // reescrever o campo focado no meio da digitação jogaria o cursor pro
    // fim da linha a cada pausa.
    function gravarContagem(cartaoTexto, dinheiroTexto, pixTexto) {
        telaFechamento.gravandoContagem = true;
        telaFechamento.contagemAtual = fechamentoController.registrarContagem(telaFechamento.dataSelecionada, cartaoTexto, dinheiroTexto, pixTexto);
        telaFechamento.gravandoContagem = false;
    }

    // Salvamento automático, disparado pelo timer depois que a digitação
    // para. Silencioso de propósito: um aviso a cada pausa de digitação, três
    // campos, viraria ruído — quem confere a gaveta digita e olha direto pro
    // "sobrou/faltou" logo abaixo, que já se atualiza junto. O rótulo discreto
    // ao lado do botão é a confirmação de que gravou.
    function salvarContagemAuto() {
        telaFechamento.gravarContagem(inputCartao.text, inputDinheiro.text, inputPix.text);
        avisoSalvoAuto.piscar();
    }

    // Antecipa o salvamento pendente (sair do campo, trocar de dia). Sem
    // nada pendente é um nada — o timer parado é a prova de que tudo que foi
    // digitado já está no disco.
    function salvarContagemPendente() {
        if (!salvamentoContagem.running)
            return;

        salvamentoContagem.stop();
        telaFechamento.salvarContagemAuto();
    }

    function fecharCaixa() {
        telaFechamento.resumoAtual = fechamentoController.calcularFechamento(telaFechamento.dataSelecionada);
        fechamentoController.imprimirFechamentoCaixa(telaFechamento.dataSelecionada);
        // Publica o resumo do dia (vendas por origem, produtos vendidos) no
        // servidor central. Fechar o mesmo caixa de novo reenvia tudo, e é o
        // envio mais recente que vale lá (ver
        // FechamentoController.enviarFechamentoServidor). O resultado chega
        // depois, pelo Connections de pizzeriaServerController mais abaixo.
        fechamentoController.enviarFechamentoServidor(telaFechamento.dataSelecionada);
        telaFechamento.mostrarNotificacao("Caixa de " + telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada) + " recalculado, salvo e enviado para impressão.", true);
    }

    function abrirFechamentoRapido() {
        if (!popupFechamentoRapido.abrirPara(telaFechamento.dataSelecionada))
            telaFechamento.mostrarNotificacao("Nenhuma comanda em aberto em " + telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada) + ".", true);
    }

    // Age sobre o dia visualizado (dataSelecionada), não necessariamente
    // hoje — permite lançar uma diária esquecida de um dia anterior, mesmo
    // comportamento do botão "Fechar Caixa".
    function abrirExtras() {
        popupExtras.abrirPara(telaFechamento.dataSelecionada);
    }

    function abrirDespesas() {
        popupDespesas.abrirPara(telaFechamento.dataSelecionada);
    }

    // Correção de uma comanda já fechada — único caminho pra isso agora
    // (ver ItemComandaDelegate.qml, que escondeu lápis/lixeira de comandas
    // fechadas na Consulta). Fila espelhada da de "Fechamento rápido", só
    // que sobre as que já têm baixa.
    function abrirEditarCaixa() {
        // O código é pedido AQUI, na porta, e não a cada "Editar" lá dentro:
        // abrir esta fila é assumir a intenção de mexer no caixa já fechado, e
        // quem corrige três comandas seguidas não precisa se identificar três
        // vezes. A fila aberta por este caminho já entra autorizada — ver
        // PopupFechamentoRapido.abrirParaFechadas.
        //
        // A contrapartida, registrada aqui para não ser descoberta depois: a
        // linha do histórico passa a dizer o DIA que foi aberto para edição,
        // não qual comanda foi corrigida. Os outros dois caminhos até a mesma
        // edição (Fechamento rápido e o clique numa comanda da lista do dia)
        // continuam pedindo o código por comanda, porque neles não houve porta
        // nenhuma antes.
        popupAutorizacao.solicitar("Editar caixa", telaFechamento.dataSelecionada, function () {
            if (!popupFechamentoRapido.abrirParaFechadas(telaFechamento.dataSelecionada))
                telaFechamento.mostrarNotificacao("Nenhuma comanda fechada em " + telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada) + ".", true);
        });
    }

    // Conexão declarativa, não um .connect() solto em Component.onCompleted
    // — mesmo motivo documentado em Balcao.qml/Rede.qml: fechamentoController
    // é global e vive pra sempre, então a conexão precisa estar presa ao
    // ciclo de vida desta página (Connections), não solta num closure.
    Connections {
        target: fechamentoController

        // Se outra máquina fechar o caixa do dia que está sendo exibido
        // aqui agora, recarrega sozinha — mesmo espírito de
        // SalaoController.mesasAtualizadas.
        function onFechamentoAtualizado(data) {
            if (data === telaFechamento.dataSelecionada)
                telaFechamento.carregarDia(data);
        }

        // Qualquer baixa (aqui ou em outra máquina da malha) muda o total do
        // dia e o contador de abertas. Recarregar o dia exibido cobre os
        // dois casos; o daqui só recarrega o que darBaixa() acabou de
        // recalcular, o que é barato e mantém um caminho só.
        function onBaixasAtualizadas() {
            telaFechamento.carregarDia(telaFechamento.dataSelecionada);
        }

        // Despesa lançada/editada/apagada em outra máquina — mesmo espírito
        // do handler de extras que o popup daqui já cobre pelo sinal
        // "concluido".
        function onDespesasAtualizadas() {
            telaFechamento.carregarDia(telaFechamento.dataSelecionada);
        }

        // Contagem editada em outra máquina, pro mesmo dia sendo exibido
        // aqui agora — mesmo espírito de onFechamentoAtualizado.
        function onContagemAtualizada(data) {
            if (data === telaFechamento.dataSelecionada)
                telaFechamento.carregarDia(data);
        }
    }

    // Resultado do envio do resumo do dia ao servidor central, disparado por
    // fecharCaixa(). Só aparece na tela porque é a única pista que o dono tem
    // de que a máquina Alpine não recebeu o fechamento — a impressão do cupom
    // acontece de qualquer jeito, então sem este aviso a falha passaria
    // despercebida.
    Connections {
        target: pizzeriaServerController

        function onFechamentoEnviado(ok, mensagem) {
            telaFechamento.mostrarNotificacao(mensagem, ok);
        }
    }

    // A reimpressão pedida pelo popup é assíncrona e pode acontecer em outra
    // máquina da malha (ver rede.solicitar_impressao) — o resultado só chega
    // por aqui, do mesmo jeito que em Balcao.qml/Entrega.qml.
    Connections {
        target: redeController
        // Só enquanto esta página está à vista: redeController é global e o
        // sinal é o mesmo de qualquer impressão do app — sem isto, imprimir
        // um pedido no Balcão enfileiraria um "Comanda reimpressa" aqui.
        enabled: telaFechamento.visible

        function onImpressaoResultado(sucesso, mensagem) {
            telaFechamento.mostrarNotificacao(sucesso ? ("Comanda reimpressa (" + mensagem + ")") : ("Falha ao reimprimir: " + mensagem), sucesso);
        }
    }

    // Os campos de Cartão/Dinheiro/Pix são TextField comuns (não bindings
    // declarativos): assim que o usuário digita algo, QML desfaz o binding
    // daquele campo com contagemAtual pra sempre (comportamento normal de
    // TextField) — sem isto, trocar de dia e voltar mostraria o valor
    // digitado no dia anterior em vez do que está salvo pra este dia.
    onContagemAtualChanged: {
        telaFechamento.escreverNoCampo(inputCartao, telaFechamento.contagemAtual.cartao);
        telaFechamento.escreverNoCampo(inputDinheiro, telaFechamento.contagemAtual.dinheiro);
        telaFechamento.escreverNoCampo(inputPix, telaFechamento.contagemAtual.pix);
    }

    // Escreve o valor salvo no campo, exceto no campo que está sendo digitado
    // agora durante um salvamento automático (ver gravarContagem). Nos outros
    // casos — troca de dia, contagem editada em outra máquina — o campo é
    // reescrito mesmo estando focado: ali o texto na tela é de outro dia ou
    // está desatualizado, e deixá-lo de pé seria mentir sobre o que está salvo.
    function escreverNoCampo(campo, valor) {
        if (telaFechamento.gravandoContagem && campo.activeFocus)
            return;

        // Zero deixa o campo VAZIO, com o "R$ 0,00" ficando por conta do
        // placeholder. Escrever o zero de verdade enchia os três campos de
        // "R$ 0,00" logo ao abrir a tela — e aí contar a gaveta começava por
        // apagar o que estava escrito, com o risco de sobrar um dígito do
        // valor antigo colado no novo. Vazio e zero contam a mesma coisa aqui
        // (totalContagem soma 0 nos dois casos), então não se perde nada.
        campo.text = valor ? Moeda.formatar(String(valor)) : "";
    }

    // Espera a digitação parar antes de gravar. Sem isso seria uma escrita em
    // disco E um evento publicado na malha (ver
    // FechamentoController.registrarContagem) a cada tecla digitada, com as
    // outras máquinas recebendo "R$ 1", "R$ 12", "R$ 120"... uma por uma.
    Timer {
        id: salvamentoContagem

        interval: 600
        onTriggered: telaFechamento.salvarContagemAuto()
    }

    // obterFechamento/obterContagem varrem as comandas do dia no disco e
    // remontam o resumo. Chamados direto de Component.onCompleted, seguravam
    // a tela inteira antes do primeiro pixel — agora entram depois do
    // primeiro quadro, com a página já desenhada (ver
    // components/CargaDiferida.qml).
    CargaDiferida {
        id: carga

        tarefa: function() {
            carregarDia(telaFechamento.dataSelecionada || hojeIso());
        }
    }

    Component.onCompleted: {
        // A data em si é só uma conta de calendário (nenhum acesso a disco), e
        // é ela que o cabeçalho mostra — fica aqui pra tela já nascer com o dia
        // certo escrito, em vez de piscar um campo de data vazio até a leitura
        // terminar.
        telaFechamento.dataSelecionada = hojeIso();
        carga.agendar();
    }
    StackView.onActivated: {
        carga.agendar();
        // Sem isto, a primeira tecla digitada ao chegar na tela não chega em
        // Keys.onPressed: o foco do teclado continua em quem estava antes na
        // pilha de telas. Fica FORA da tarefa diferida de propósito: mexer no
        // foco é parte de montar a tela, não de carregar dado, e adiar isso
        // perderia as primeiras teclas de quem já chega digitando.
        telaFechamento.forceActiveFocus();
    }

    background: Rectangle {
        color: Estilo.global.background
        radius: Estilo.global.radius.xl
    }

    // Rola quando os painéis empilham e a página fica mais alta que a
    // janela — sem isto, o bloco de sobra/falta (o último) ficava escondido
    // atrás do botão "Voltar para o Menu", sem jeito de alcançá-lo.
    Flickable {
        id: rolagemFechamento

        anchors.fill: parent
        anchors.margins: Estilo.global.padding.xl
        clip: true
        contentWidth: width
        contentHeight: colunaFechamento.height
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: colunaFechamento

            width: rolagemFechamento.width
            // Empilhada, a coluna cresce até onde o conteúdo pedir e o Flickable
            // rola; lado a lado, ela cabe na janela como sempre coube.
            height: telaFechamento.empilhado ? implicitHeight : rolagemFechamento.height
            spacing: Estilo.global.spacing.xl

            // --- CABEÇALHO ---
            // Duas colunas (título | controles) enquanto couberem lado a lado;
            // uma só quando não couberem, com os controles fluindo para as linhas
            // seguintes em vez de saírem pela borda.
            GridLayout {
                id: cabecalhoFechamento

                // Largura que os controles pediriam numa linha só. Medida a
                // partir dos filhos do Flow, e não chutada por um número
                // fixo: são seis blocos (navegação de data + cinco botões)
                // cujo tamanho depende da fonte e da escala do tema, e um
                // limiar cravado aqui erraria assim que qualquer um deles
                // mudasse de texto.
                readonly property real larguraNaturalControles: {
                    var total = 0;
                    var filhos = fluxoControles.children;
                    for (var i = 0; i < filhos.length; i++) {
                        if (filhos[i].visible)
                            total += filhos[i].implicitWidth + fluxoControles.spacing;
                    }
                    return Math.max(0, total - fluxoControles.spacing);
                }

                // Título e controles dividem a linha só quando cabem MESMO os
                // dois. Antes a segunda coluna simplesmente recebia o que
                // sobrava do título, e o Flow quebrava lá dentro — o que
                // largava o último botão sozinho numa linha, com espaço de
                // sobra ao lado do título.
                readonly property bool controlesCabemAoLado: telaFechamento.larguraUtil
                    >= linhaTituloFechamento.implicitWidth
                     + cabecalhoFechamento.larguraNaturalControles
                     + Estilo.global.spacing.xl

                Layout.fillWidth: true
                columns: (telaFechamento.empilhado || !cabecalhoFechamento.controlesCabemAoLado) ? 1 : 2
                columnSpacing: Estilo.global.spacing.xl
                rowSpacing: Estilo.global.spacing.md

                Row {
                    id: linhaTituloFechamento

                    spacing: Estilo.global.spacing.sm
                    Icone { nome: "fa6s.cash-register"; cor: Estilo.screen.caixa.accent; tamanho: Estilo.global.fontSize.title; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "FECHAMENTO DE CAIXA"
                        font.pixelSize: Estilo.global.fontSize.title
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.screen.caixa.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // Controles do dia: navegação de data e as ações do caixa.
                // Encostados à direita quando há espaço (como sempre foram), e
                // quebrando em linhas quando não há.
                Flow {
                    id: fluxoControles

                    // Numa linha própria ocupa a largura toda (é o que dá
                    // espaço para os cinco botões ficarem lado a lado);
                    // dividindo a linha com o título, fica encostado à
                    // direita, como sempre foi.
                    Layout.fillWidth: cabecalhoFechamento.columns === 1
                    Layout.maximumWidth: telaFechamento.larguraUtil
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    spacing: Estilo.global.spacing.md

                // --- NAVEGAÇÃO DE DATA ---
                Row {
                    spacing: Estilo.global.spacing.sm

                    Button {
                        text: "◀"
                        padding: 8
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: telaFechamento.carregarDia(telaFechamento.somarDias(telaFechamento.dataSelecionada, -1))

                        contentItem: Text {
                            text: parent.text
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            horizontalAlignment: Text.AlignHCenter
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
                            color: parent.down ? Estilo.screen.caixa.pressed : (parent.hovered ? Estilo.screen.caixa.hover : Estilo.screen.caixa.base)
                        }
                    }

                    Rectangle {
                        width: 130
                        height: 36
                        radius: Estilo.global.radius.sm
                        color: Estilo.global.surface
                        border.color: Estilo.global.borderCard
                        border.width: Estilo.global.borderWidth.hairline
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: telaFechamento.formatarDataExibicao(telaFechamento.dataSelecionada)
                            font.bold: true
                            font.pixelSize: Estilo.global.fontSize.lg
                            color: Estilo.global.text
                        }
                    }

                    Button {
                        text: "▶"
                        padding: 8
                        enabled: telaFechamento.dataSelecionada !== telaFechamento.hojeIso()
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: telaFechamento.carregarDia(telaFechamento.somarDias(telaFechamento.dataSelecionada, 1))

                        contentItem: Text {
                            text: parent.text
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            horizontalAlignment: Text.AlignHCenter
                            opacity: parent.enabled ? 1 : Estilo.global.opacity.disabled
                        }

                        background: Rectangle {
                            radius: Estilo.global.radius.pill
                            opacity: parent.enabled ? 1 : Estilo.global.opacity.disabled
                            color: parent.down ? Estilo.screen.caixa.pressed : (parent.hovered ? Estilo.screen.caixa.hover : Estilo.screen.caixa.base)
                        }
                    }
                }

                Button {
                    id: btnEditarCaixa

                    padding: Estilo.global.padding.md
                    focusPolicy: Qt.StrongFocus
                    enabled: telaFechamento.resumoAtual.quantidade > 0
                    onClicked: telaFechamento.abrirEditarCaixa()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.pen-to-square"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Editar caixa"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: {
                            if (!btnEditarCaixa.enabled)
                                return Estilo.global.border;
                            return btnEditarCaixa.down ? Estilo.action.save.pressed : (btnEditarCaixa.hovered ? Estilo.action.save.hover : Estilo.action.save.base);
                        }
                        border.color: btnEditarCaixa.activeFocus ? Estilo.global.text : "transparent"
                        border.width: btnEditarCaixa.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                    }
                }

                Button {
                    id: btnFechamentoRapido

                    padding: Estilo.global.padding.md
                    focusPolicy: Qt.StrongFocus
                    enabled: telaFechamento.quantidadeAberta > 0
                    onClicked: telaFechamento.abrirFechamentoRapido()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.list-check"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: telaFechamento.quantidadeAberta > 0
                                ? "Fechamento rápido (" + telaFechamento.quantidadeAberta + ")"
                                : "Fechamento rápido"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: {
                            if (!btnFechamentoRapido.enabled)
                                return Estilo.global.border;
                            return btnFechamentoRapido.down ? Estilo.action.review.pressed : (btnFechamentoRapido.hovered ? Estilo.action.review.hover : Estilo.action.review.base);
                        }
                        border.color: btnFechamentoRapido.activeFocus ? Estilo.global.text : "transparent"
                        border.width: btnFechamentoRapido.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                    }
                }

                Button {
                    id: btnExtras

                    padding: Estilo.global.padding.md
                    focusPolicy: Qt.StrongFocus
                    onClicked: telaFechamento.abrirExtras()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.hand-holding-dollar"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Extras"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnExtras.down ? Estilo.action.outflow.pressed : (btnExtras.hovered ? Estilo.action.outflow.hover : Estilo.action.outflow.base)
                        border.color: btnExtras.activeFocus ? Estilo.global.text : "transparent"
                        border.width: btnExtras.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                    }
                }

                Button {
                    id: btnDespesas

                    padding: Estilo.global.padding.md
                    focusPolicy: Qt.StrongFocus
                    onClicked: telaFechamento.abrirDespesas()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.receipt"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Despesas"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnDespesas.down ? Estilo.action.outflow.pressed : (btnDespesas.hovered ? Estilo.action.outflow.hover : Estilo.action.outflow.base)
                        border.color: btnDespesas.activeFocus ? Estilo.global.text : "transparent"
                        border.width: btnDespesas.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                    }
                }

                Button {
                    id: btnFecharCaixa

                    padding: Estilo.global.padding.md
                    focusPolicy: Qt.StrongFocus
                    onClicked: telaFechamento.fecharCaixa()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent
                        Icone { nome: "fa6s.lock"; cor: Estilo.global.textOnAccent; tamanho: Estilo.global.fontSize.lg; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Fechar Caixa"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.action.confirm.pressed : (parent.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                        border.color: parent.activeFocus ? Estilo.global.text : Estilo.action.confirm.pressed
                        border.width: parent.activeFocus ? Estilo.global.borderWidth.focus : Estilo.global.borderWidth.hairline
                    }
                }

                }
            }

            // --- TOTAL DO DIA (destaque) ---
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: colunaTotalDia.implicitHeight + 30
                radius: Estilo.global.radius.md
                color: Estilo.status.success.background
                border.color: Estilo.status.success.border
                border.width: Estilo.global.borderWidth.hairline

                ColumnLayout {
                    id: colunaTotalDia

                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "TOTAL DO DIA"
                        font.pixelSize: Estilo.global.fontSize.md
                        font.bold: true
                        color: Estilo.global.textSecondary
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "R$ " + (telaFechamento.resumoAtual.total || 0).toFixed(2).replace(".", ",")
                        font.pixelSize: Estilo.global.fontSize.display
                        font.bold: true
                        color: Estilo.finance.positive
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: (telaFechamento.resumoAtual.quantidade || 0) + (telaFechamento.resumoAtual.quantidade === 1 ? " comanda" : " comandas")
                        font.pixelSize: Estilo.global.fontSize.md
                        color: Estilo.global.textSecondary
                    }

                    // O que foi vendido mas ainda não entrou no caixa. Fica
                    // junto do total de propósito: sem isto, um dia com metade
                    // das comandas sem baixa mostraria um total menor sem
                    // nenhuma pista do motivo.
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 6
                        visible: telaFechamento.quantidadeAberta > 0
                        text: telaFechamento.quantidadeAberta
                            + (telaFechamento.quantidadeAberta === 1 ? " comanda em aberto · " : " comandas em aberto · ")
                            + "R$ " + telaFechamento.totalAberto.toFixed(2).replace(".", ",") + " fora do caixa"
                        font.pixelSize: Estilo.global.fontSize.md
                        font.bold: true
                        color: Estilo.finance.outflow
                    }
                }
            }

            // --- MAPEAMENTO POR ORIGEM (esquerda) + SUSPEITAS (direita) ---
            // Lado a lado enquanto couberem; empilhados quando não couberem — a
            // contagem de caixa passa a ficar embaixo do mapeamento, com a
            // rolagem da página dando conta da altura.
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: !telaFechamento.empilhado
                columns: telaFechamento.empilhado ? 1 : 2
                columnSpacing: Estilo.global.spacing.xl
                rowSpacing: Estilo.global.spacing.xl

                // --- MAPEAMENTO POR ORIGEM ---
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Estilo.global.spacing.md

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Estilo.global.spacing.sm

                        Text {
                            text: "Mapeamento por origem"
                            font.pixelSize: Estilo.global.fontSize.lg
                            font.bold: true
                            color: Estilo.global.textSecondary
                        }

                        Item { Layout.fillWidth: true }

                        // --- FILTRO POR USUÁRIO ---
                        // Quem lançou o pedido. Fica aqui em cima, e não junto
                        // da busca logo abaixo, porque não é a mesma coisa: a
                        // busca procura UMA comanda, este recorta o dia inteiro
                        // — inclusive os totais por modalidade (ver
                        // _passaNoUsuario).
                        //
                        // Escondido num dia sem usuário nenhum nas comandas:
                        // dia antigo, de antes do cadastro de usuários.
                        FiltroUsuario {
                            // Nomeado pelo mesmo motivo dos popups das telas:
                            // alcançável de fora para inspeção e teste.
                            objectName: "filtroUsuarioFechamento"
                            visible: telaFechamento.usuariosDoDia.length > 0
                            Layout.preferredWidth: 190
                            alturaCampo: 30
                            corDestaque: Estilo.screen.caixa.accent
                            usuarios: telaFechamento.usuariosDoDia
                            usuarioSelecionado: telaFechamento.filtroUsuario
                            // A lista se refaz sozinha por binding
                            // (comandasDoTipo lê filtroUsuario), então aqui
                            // basta gravar.
                            onSelecionou: function (usuario) {
                                telaFechamento.filtroUsuario = usuario;
                            }
                        }

                        Text {
                            // Aparece também quando só o filtro de usuário está
                            // ligado: nos dois casos há comanda escondida, e a
                            // contagem é o que diz quanto sobrou.
                            visible: telaFechamento.buscando || telaFechamento.filtroUsuario !== ""
                            text: {
                                var n = telaFechamento.totalEncontrado();
                                return n === 1 ? "1 comanda encontrada" : n + " comandas encontradas";
                            }
                            font.pixelSize: Estilo.global.fontSize.sm
                            color: telaFechamento.totalEncontrado() > 0 ? Estilo.global.textSecondary : Estilo.action.danger.base
                        }
                    }

                    // --- BUSCA ---
                    // Aceita modalidade (Balcão/Entrega/Mesa), nome do cliente,
                    // código, forma de pagamento, item pedido e valor — tudo o que
                    // o Python empacotou no campo "busca" de cada comanda.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: Estilo.global.radius.pill
                        color: Estilo.global.inputBackground
                        border.color: campoBusca.activeFocus ? Estilo.screen.caixa.accent : Estilo.global.borderCard
                        border.width: campoBusca.activeFocus ? 2 : 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 6
                            spacing: Estilo.global.spacing.sm

                            Icone {
                                nome: "fa6s.magnifying-glass"
                                cor: Estilo.global.textSecondary
                                tamanho: 13
                                Layout.alignment: Qt.AlignVCenter
                            }

                            TextField {
                                id: campoBusca

                                Layout.fillWidth: true
                                placeholderText: "Buscar por modalidade, cliente, pedido ou valor — é só começar a digitar"
                                font.pixelSize: Estilo.global.fontSize.md
                                // Preto explícito: sem isto o Qt usa palette.text,
                                // que no Windows vem do tema do sistema e some no
                                // fundo branco quando o tema é escuro (mesmo
                                // cuidado documentado em qml/estilo/Estilo.qml).
                                color: Estilo.global.text
                                background: Item {}
                                onTextChanged: telaFechamento.termoBusca = text
                                // Esc limpa e devolve o teclado para a página, para
                                // a próxima tecla começar uma busca nova.
                                Keys.onEscapePressed: {
                                    telaFechamento.limparBusca();
                                    telaFechamento.forceActiveFocus();
                                }
                            }

                            Button {
                                visible: telaFechamento.buscando
                                implicitWidth: 26
                                implicitHeight: 26
                                focusPolicy: Qt.NoFocus
                                Layout.alignment: Qt.AlignVCenter
                                onClicked: {
                                    telaFechamento.limparBusca();
                                    telaFechamento.forceActiveFocus();
                                }

                                contentItem: Icone {
                                    nome: "fa6s.xmark"
                                    cor: Estilo.global.textSecondary
                                    tamanho: 12
                                    anchors.centerIn: parent
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: parent.down ? Estilo.global.borderCard : "transparent"
                                }
                            }
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: colunaTipos.implicitHeight

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        ColumnLayout {
                            id: colunaTipos

                            width: parent.width
                            spacing: Estilo.global.spacing.lg

                            Repeater {
                                model: telaFechamento.ordemTipos

                                delegate: ColumnLayout {
                                    id: blocoTipo

                                    readonly property var info: telaFechamento.infoTipo(modelData)
                                    // Preso aqui porque lá dentro, na ListView de
                                    // comandas, "modelData" já é a comanda.
                                    readonly property string nomeTipo: modelData
                                    // Só as que casam com a busca (todas quando
                                    // não há busca) — ver comandasDoTipo.
                                    readonly property var comandas: telaFechamento.comandasDoTipo(modelData)
                                    // Fechado por padrão — a lista de comandas só
                                    // aparece quando o box do tipo é clicado (ver
                                    // areaCabecalhoTipo abaixo). Durante uma busca
                                    // abre sozinho: quem digitou quer ver o que
                                    // achou, não um bloco fechado com a contagem.
                                    property bool expandidoManual: false
                                    readonly property bool expandido: telaFechamento.buscando || expandidoManual

                                    Layout.fillWidth: true
                                    // Some por completo quando a busca não achou
                                    // nada aqui, para sobrar só o que interessa.
                                    visible: comandas.length > 0
                                    spacing: Estilo.global.spacing.xs

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: linhaCabecalhoTipo.implicitHeight + 16
                                        radius: Estilo.global.radius.sm
                                        color: Estilo.global.surface
                                        border.color: Estilo.global.borderCard
                                        border.width: Estilo.global.borderWidth.hairline

                                        MouseArea {
                                            id: areaCabecalhoTipo

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: blocoTipo.expandidoManual = !blocoTipo.expandidoManual
                                        }

                                        RowLayout {
                                            id: linhaCabecalhoTipo

                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: Estilo.global.spacing.sm

                                            Rectangle {
                                                width: 10
                                                height: 10
                                                radius: Estilo.global.radius.sm
                                                color: telaFechamento.coresTipo[modelData] || Estilo.global.text
                                                Layout.alignment: Qt.AlignVCenter
                                            }

                                            Text {
                                                text: modelData
                                                font.bold: true
                                                font.pixelSize: Estilo.global.fontSize.lg
                                                color: Estilo.global.text
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: blocoTipo.comandas.length + (blocoTipo.comandas.length === 1 ? " comanda" : " comandas")
                                                font.pixelSize: Estilo.global.fontSize.sm
                                                color: Estilo.global.textSecondary
                                            }

                                            Text {
                                                text: "R$ " + telaFechamento.totalDoTipo(blocoTipo.nomeTipo).toFixed(2).replace(".", ",")
                                                font.bold: true
                                                font.pixelSize: Estilo.global.fontSize.lg
                                                color: telaFechamento.coresTipo[modelData] || Estilo.global.text
                                            }

                                            Icone {
                                                nome: blocoTipo.expandido ? "fa6s.chevron-up" : "fa6s.chevron-down"
                                                cor: Estilo.global.textSecondary
                                                tamanho: 12
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }
                                    }

                                    // Altura = conteúdo inteiro (sem limite/scroll
                                    // próprio) — quem rola é só o Flickable de
                                    // fora, um scroll só pra "Mapeamento por
                                    // origem" inteiro, em vez de uma caixinha de
                                    // rolagem dentro da outra.
                                    ListView {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 18
                                        Layout.preferredHeight: contentHeight
                                        visible: blocoTipo.expandido
                                        interactive: false
                                        clip: true
                                        spacing: 4
                                        model: blocoTipo.comandas
                                        boundsBehavior: Flickable.StopAtBounds

                                        delegate: Rectangle {
                                            id: itemComandaTipo

                                            // Provável erro de digitação no pedido
                                            // (ver comandaParserService.eh_suspeita)
                                            // — só um aviso visual.
                                            readonly property bool suspeita: modelData.suspeita === true

                                            width: ListView.view.width
                                            height: 40
                                            radius: Estilo.global.radius.sm
                                            color: areaComanda.containsMouse ? Estilo.global.surface : Estilo.global.background
                                            border.color: itemComandaTipo.suspeita
                                                ? Estilo.status.error.content
                                                : (areaComanda.containsMouse ? (telaFechamento.coresTipo[blocoTipo.nomeTipo] || Estilo.global.border) : Estilo.global.borderCard)
                                            border.width: itemComandaTipo.suspeita ? 2 : 1

                                            // Abre a comanda pra conferir e, se
                                            // preciso, corrigir. Estas são as já
                                            // baixadas — as em aberto têm o botão
                                            // "Fechamento rápido" lá em cima — e
                                            // são justamente as que o caixa do
                                            // dia já está contando, ou seja, as
                                            // que um erro de digitação afeta.
                                            MouseArea {
                                                id: areaComanda

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: popupFechamentoRapido.abrirComanda(modelData.arquivo, telaFechamento.dataSelecionada)
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: Estilo.global.spacing.sm

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: (modelData.cliente && modelData.cliente.trim() !== "" ? modelData.cliente : "Sem nome") + " · " + modelData.dataHora
                                                    font.pixelSize: Estilo.global.fontSize.sm
                                                    color: Estilo.global.text
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: modelData.formaPagamento + (modelData.status ? " [" + modelData.status + "]" : "")
                                                    font.pixelSize: Estilo.global.fontSize.xs
                                                    color: Estilo.global.textSecondary
                                                }

                                                Text {
                                                    text: "R$ " + Number(modelData.valor).toFixed(2).replace(".", ",")
                                                    font.bold: true
                                                    font.pixelSize: Estilo.global.fontSize.sm
                                                    color: Estilo.global.text
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: (telaFechamento.resumoAtual.quantidade || 0) === 0
                                text: "Nenhuma comanda lançada neste dia."
                                font.italic: true
                                color: Estilo.global.textSecondary
                            }
                        }
                    }

                    // --- EXTRAS E DESPESAS, LADO A LADO ---
                    // Empilham quando a janela é estreita, pelo mesmo
                    // "empilhado" que já rege o resto desta tela — duas
                    // listas espremidas lado a lado numa tela de balcão
                    // cortariam os nomes no meio.
                    GridLayout {
                        Layout.fillWidth: true
                        visible: telaFechamento.quantidadeExtras > 0 || telaFechamento.quantidadeDespesas > 0
                        columns: telaFechamento.empilhado ? 1 : 2
                        columnSpacing: Estilo.global.spacing.sm
                        rowSpacing: Estilo.global.spacing.sm

    Rectangle {
                            Layout.fillWidth: true
                            visible: telaFechamento.quantidadeExtras > 0
                            implicitHeight: colunaExtras.implicitHeight + 20
                            radius: Estilo.global.radius.sm
                            color: Estilo.status.pending.background
                            border.color: Estilo.status.pending.border
                            border.width: Estilo.global.borderWidth.hairline

                            ColumnLayout {
                                id: colunaExtras

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: Estilo.global.spacing.xs

                                Row {
                                    spacing: Estilo.global.spacing.xs
                                    Icone { nome: "fa6s.hand-holding-dollar"; cor: Estilo.finance.outflow; tamanho: 14; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: "Diárias (somadas de volta à contagem)"
                                        font.bold: true
                                        font.pixelSize: Estilo.global.fontSize.md
                                        color: Estilo.finance.outflow
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Repeater {
                                    model: telaFechamento._extras.itens

                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Estilo.global.spacing.sm

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.funcionario
                                            font.pixelSize: Estilo.global.fontSize.sm
                                            color: Estilo.global.text
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: modelData.dataHora
                                            font.pixelSize: Estilo.global.fontSize.xs
                                            color: Estilo.global.textSecondary
                                        }

                                        Text {
                                            text: "R$ " + Number(modelData.valor).toFixed(2).replace(".", ",")
                                            font.bold: true
                                            font.pixelSize: Estilo.global.fontSize.sm
                                            color: Estilo.finance.outflow
                                        }

                                        Button {
                                            id: btnEditarExtra

                                            implicitWidth: 24
                                            implicitHeight: 24
                                            padding: 0
                                            onClicked: popupExtras.abrirParaEditar(modelData)

                                            contentItem: Icone {
                                                nome: "fa6s.pen"
                                                cor: Estilo.global.textSecondary
                                                tamanho: 11
                                                anchors.centerIn: parent
                                            }

                                            background: Rectangle {
                                                radius: Estilo.global.radius.pill
                                                color: btnEditarExtra.down ? Estilo.action.ghost.pressed : (btnEditarExtra.hovered ? Estilo.action.ghost.hover : Estilo.action.ghost.base)
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 2
                                    text: "Total em diárias: R$ " + telaFechamento.totalExtras.toFixed(2).replace(".", ",")
                                    font.bold: true
                                    font.pixelSize: Estilo.global.fontSize.md
                                    color: Estilo.finance.outflow
                                }
                            }
                        }

    Rectangle {
                            Layout.fillWidth: true
                            visible: telaFechamento.quantidadeDespesas > 0
                            implicitHeight: colunaDespesas.implicitHeight + 20
                            radius: Estilo.global.radius.sm
                            color: Estilo.status.pending.background
                            border.color: Estilo.status.pending.border
                            border.width: Estilo.global.borderWidth.hairline

                            ColumnLayout {
                                id: colunaDespesas

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: Estilo.global.spacing.xs

                                Row {
                                    spacing: Estilo.global.spacing.xs
                                    Icone { nome: "fa6s.receipt"; cor: Estilo.finance.outflow; tamanho: 14; anchors.verticalCenter: parent.verticalCenter }
                                    Text {
                                        text: "Despesas (somadas de volta à contagem)"
                                        font.bold: true
                                        font.pixelSize: Estilo.global.fontSize.md
                                        color: Estilo.finance.outflow
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Repeater {
                                    model: telaFechamento._despesas.itens

                                    delegate: RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Estilo.global.spacing.sm

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.nome
                                            font.pixelSize: Estilo.global.fontSize.sm
                                            color: Estilo.global.text
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: modelData.dataHora
                                            font.pixelSize: Estilo.global.fontSize.xs
                                            color: Estilo.global.textSecondary
                                        }

                                        Text {
                                            text: "R$ " + Number(modelData.valor).toFixed(2).replace(".", ",")
                                            font.bold: true
                                            font.pixelSize: Estilo.global.fontSize.sm
                                            color: Estilo.finance.outflow
                                        }

                                        Button {
                                            id: btnEditarDespesa

                                            implicitWidth: 24
                                            implicitHeight: 24
                                            padding: 0
                                            onClicked: popupDespesas.abrirParaEditar(modelData)

                                            contentItem: Icone {
                                                nome: "fa6s.pen"
                                                cor: Estilo.global.textSecondary
                                                tamanho: 11
                                                anchors.centerIn: parent
                                            }

                                            background: Rectangle {
                                                radius: Estilo.global.radius.pill
                                                color: btnEditarDespesa.down ? Estilo.action.ghost.pressed : (btnEditarDespesa.hovered ? Estilo.action.ghost.hover : Estilo.action.ghost.base)
                                            }
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 2
                                    text: "Total em despesas: R$ " + telaFechamento.totalDespesas.toFixed(2).replace(".", ",")
                                    font.bold: true
                                    font.pixelSize: Estilo.global.fontSize.md
                                    color: Estilo.finance.outflow
                                }
                            }
                        }
                    }
                }

                // --- CONTAGEM DE CAIXA ---
                ColumnLayout {
                    // Coluna estreita e fixa ao lado do mapeamento; empilhada,
                    // ocupa a largura toda.
                    Layout.preferredWidth: telaFechamento.empilhado ? telaFechamento.larguraUtil : 340
                    Layout.fillWidth: telaFechamento.empilhado
                    Layout.fillHeight: !telaFechamento.empilhado
                    Layout.alignment: Qt.AlignTop
                    spacing: Estilo.global.spacing.md

                    Row {
                        Layout.fillWidth: true
                        spacing: Estilo.global.spacing.xs
                        Icone { nome: "fa6s.calculator"; cor: Estilo.screen.caixa.base; tamanho: 16; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: "Contagem de caixa"
                            font.pixelSize: Estilo.global.fontSize.lg
                            font.bold: true
                            color: Estilo.screen.caixa.base
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: colunaContagem.implicitHeight + 20
                        radius: Estilo.global.radius.md
                        color: Estilo.global.surface
                        border.color: Estilo.global.borderCard
                        border.width: Estilo.global.borderWidth.hairline

                        ColumnLayout {
                            id: colunaContagem

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 10
                            spacing: Estilo.global.spacing.md

                            Column {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "Cartão (crédito/débito)"
                                    font.pixelSize: Estilo.global.fontSize.sm
                                    font.bold: true
                                    color: Estilo.global.textSecondary
                                }

                                TextField {
                                    id: inputCartao

                                    width: parent.width
                                    color: Estilo.global.textInput
                                    placeholderTextColor: Estilo.global.textPlaceholder
                                    placeholderText: "R$ 0,00"
                                    topPadding: 10
                                    bottomPadding: 10
                                    leftPadding: 10
                                    rightPadding: 10
                                    // Com sinal: contagem de caixa aceita valor
                                    // negativo (ver Moeda.validadorComSinal).
                                    validator: Moeda.validadorComSinal
                                    // Mesmo padrão de inputTroco/inputTaxaEntrega
                                    // em CamposPagamento.qml.
                                    onEditingFinished: {
                                        text = Moeda.formatar(text);
                                        // Sair do campo é sinal claro de que
                                        // acabou de digitar: não faz sentido
                                        // esperar o resto do timer.
                                        telaFechamento.salvarContagemPendente();
                                    }
                                    // Ao ganhar o foco o campo tira a máscara e
                                    // mostra o número puro ("500", "500,98") —
                                    // ver Moeda.paraEdicao. É atribuição
                                    // programática, então não dispara
                                    // textEdited nem agenda salvamento.
                                    onActiveFocusChanged: if (activeFocus)
                                        text = Moeda.paraEdicao(text)
                                    // textEdited, não textChanged: só dispara em
                                    // digitação de gente. textChanged pegaria
                                    // também o texto que onContagemAtualChanged
                                    // escreve aqui, e cada gravação agendaria a
                                    // próxima, pra sempre.
                                    onTextEdited: salvamentoContagem.restart()

                                    background: Rectangle {
                                        radius: Estilo.global.radius.pill
                                        color: Estilo.global.inputBackground
                                        border.color: inputCartao.activeFocus ? Estilo.screen.caixa.base : Estilo.global.border
                                        border.width: Estilo.global.borderWidth.hairline
                                    }
                                }
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "Dinheiro (o que está na gaveta agora)"
                                    font.pixelSize: Estilo.global.fontSize.sm
                                    font.bold: true
                                    color: Estilo.global.textSecondary
                                }

                                TextField {
                                    id: inputDinheiro

                                    width: parent.width
                                    color: Estilo.global.textInput
                                    placeholderTextColor: Estilo.global.textPlaceholder
                                    placeholderText: "R$ 0,00"
                                    topPadding: 10
                                    bottomPadding: 10
                                    leftPadding: 10
                                    rightPadding: 10
                                    validator: Moeda.validadorComSinal
                                    onEditingFinished: {
                                        text = Moeda.formatar(text);
                                        telaFechamento.salvarContagemPendente();
                                    }
                                    onActiveFocusChanged: if (activeFocus)
                                        text = Moeda.paraEdicao(text)
                                    onTextEdited: salvamentoContagem.restart()

                                    background: Rectangle {
                                        radius: Estilo.global.radius.pill
                                        color: Estilo.global.inputBackground
                                        border.color: inputDinheiro.activeFocus ? Estilo.screen.caixa.base : Estilo.global.border
                                        border.width: Estilo.global.borderWidth.hairline
                                    }
                                }

                                // O campo guarda o que foi contado; a soma com
                                // diárias e despesas é derivada (ver
                                // dinheiroComSaidas). Sem esta linha, a conta
                                // do "sobrou/faltou" logo abaixo não bateria
                                // com nenhum número visível na tela — e quem
                                // confere ficaria procurando o erro.
                                Text {
                                    width: parent.width
                                    visible: telaFechamento.totalSaidasEmDinheiro > 0
                                    text: "+ R$ " + telaFechamento.totalSaidasEmDinheiro.toFixed(2).replace(".", ",")
                                        + " pagos em diárias/despesas  =  R$ "
                                        + telaFechamento.dinheiroComSaidas.toFixed(2).replace(".", ",")
                                    font.pixelSize: Estilo.global.fontSize.xs
                                    color: Estilo.global.textSecondary
                                    wrapMode: Text.Wrap
                                }
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "Pix"
                                    font.pixelSize: Estilo.global.fontSize.sm
                                    font.bold: true
                                    color: Estilo.global.textSecondary
                                }

                                TextField {
                                    id: inputPix

                                    width: parent.width
                                    color: Estilo.global.textInput
                                    placeholderTextColor: Estilo.global.textPlaceholder
                                    placeholderText: "R$ 0,00"
                                    topPadding: 10
                                    bottomPadding: 10
                                    leftPadding: 10
                                    rightPadding: 10
                                    validator: Moeda.validadorComSinal
                                    onEditingFinished: {
                                        text = Moeda.formatar(text);
                                        telaFechamento.salvarContagemPendente();
                                    }
                                    onActiveFocusChanged: if (activeFocus)
                                        text = Moeda.paraEdicao(text)
                                    onTextEdited: salvamentoContagem.restart()

                                    background: Rectangle {
                                        radius: Estilo.global.radius.pill
                                        color: Estilo.global.inputBackground
                                        border.color: inputPix.activeFocus ? Estilo.screen.caixa.base : Estilo.global.border
                                        border.width: Estilo.global.borderWidth.hairline
                                    }
                                }
                            }

                            // Confirmação discreta do salvamento automático:
                            // aparece por um instante a cada gravação e some.
                            // A contagem grava sozinha, então sem nenhum sinal
                            // na tela o botão logo abaixo pareceria a única
                            // forma de salvar — e quem fechasse a tela sem
                            // clicar nele acharia que perdeu o que digitou.
                            Text {
                                id: avisoSalvoAuto

                                function piscar() {
                                    opacity = 1;
                                    sumir.restart();
                                }

                                Layout.fillWidth: true
                                text: "Salvo automaticamente"
                                font.pixelSize: Estilo.global.fontSize.xs
                                color: Estilo.global.textSecondary
                                horizontalAlignment: Text.AlignRight
                                opacity: 0

                                Behavior on opacity {
                                    NumberAnimation { duration: 300 }
                                }

                                Timer {
                                    id: sumir

                                    interval: 1600
                                    onTriggered: avisoSalvoAuto.opacity = 0
                                }
                            }

                            Button {
                                id: btnSalvarContagem

                                Layout.fillWidth: true
                                padding: Estilo.global.padding.md
                                onClicked: telaFechamento.salvarContagem(inputCartao.text, inputDinheiro.text, inputPix.text)

                                contentItem: Text {
                                    text: "Salvar contagem"
                                    font.family: Estilo.global.fontFamily.title
                                    color: Estilo.global.textOnAccent
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                background: Rectangle {
                                    radius: Estilo.global.radius.pill
                                    color: btnSalvarContagem.down ? Estilo.screen.caixa.pressed : (btnSalvarContagem.hovered ? Estilo.screen.caixa.hover : Estilo.screen.caixa.base)
                                }
                            }
                        }
                    }

                    // --- SOBROU / FALTOU (ver diferencaCaixa) ---
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Estilo.global.radius.md
                        color: telaFechamento.caixaSobrou ? Estilo.status.success.background : Estilo.status.error.background
                        border.color: telaFechamento.caixaSobrou ? Estilo.status.success.border : Estilo.status.error.border
                        border.width: Estilo.global.borderWidth.hairline

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            // O rótulo é colorido junto com o valor, ao
                            // contrário dos outros cartões desta tela: aqui ele
                            // não nomeia um campo fixo, é metade da resposta.
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: telaFechamento.caixaSobrou ? "SOBROU" : "FALTOU"
                                font.pixelSize: Estilo.global.fontSize.md
                                font.bold: true
                                color: telaFechamento.caixaSobrou ? Estilo.finance.positive : Estilo.finance.negative
                            }

                            // Sem sinal: quem diz a direção é o rótulo acima —
                            // "FALTOU R$ -100,00" se leria como o contrário.
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "R$ " + Math.abs(telaFechamento.diferencaCaixa).toFixed(2).replace(".", ",")
                                font.pixelSize: Estilo.global.fontSize.display
                                font.bold: true
                                color: telaFechamento.caixaSobrou ? Estilo.finance.positive : Estilo.finance.negative
                            }
                        }
                    }

                    // --- LUCRO (ver telaFechamento.lucro) ---
                    //
                    // Cartão neutro, ao contrário do de sobra/falta acima: o
                    // verde/vermelho de lá é um veredito sobre a gaveta ("está
                    // certa ou não"), e repetir a mesma moldura aqui faria dois
                    // julgamentos onde só existe um. Aqui só o número muda de
                    // cor, e só quando o dia de fato fecha no vermelho.
                    //
                    // Altura pelo conteúdo (implicitHeight, como o cartão da
                    // contagem): quem estica pra ocupar a sobra da coluna
                    // continua sendo um só, o de sobra/falta.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: colunaLucro.implicitHeight + 20
                        radius: Estilo.global.radius.md
                        color: Estilo.global.surface
                        border.color: Estilo.global.borderCard
                        border.width: Estilo.global.borderWidth.hairline

                        ColumnLayout {
                            id: colunaLucro

                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "LUCRO"
                                font.pixelSize: Estilo.global.fontSize.md
                                font.bold: true
                                color: Estilo.global.textSecondary
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "R$ " + telaFechamento.lucro.toFixed(2).replace(".", ",")
                                font.pixelSize: Estilo.global.fontSize.display
                                font.bold: true
                                color: telaFechamento.lucro >= 0 ? Estilo.finance.positive : Estilo.finance.negative
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: "contagem - diárias - despesas"
                                font.pixelSize: Estilo.global.fontSize.sm
                                color: Estilo.global.textSecondary
                            }
                        }
                    }
                }
            }

            // --- BOTÃO VOLTAR ---
            Button {
                id: btnVoltar

                padding: Estilo.global.padding.md
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 200
                onClicked: {
                    if (telaFechamento.StackView.view)
                        telaFechamento.StackView.view.irParaInicio();
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

    PopupFechamentoRapido {
        id: popupFechamentoRapido

        // O popup vive em Overlay.overlay, fora da hierarquia visual desta
        // página, então não alcança o StackView sozinho — e ele precisa da
        // pilha pra empurrar o formulário de edição.
        pilhaPrincipal: telaFechamento.StackView.view

        onConcluido: telaFechamento.carregarDia(telaFechamento.dataSelecionada)
    }

    // Guarda do botão "Editar caixa" (ver abrirEditarCaixa).
    PopupAutorizacao {
        id: popupAutorizacao
    }

    PopupExtras {
        id: popupExtras
        objectName: "popupExtras"

        onConcluido: telaFechamento.carregarDia(telaFechamento.dataSelecionada)
    }

    PopupDespesas {
        id: popupDespesas

        objectName: "popupDespesas"
        onConcluido: telaFechamento.carregarDia(telaFechamento.dataSelecionada)
    }

    FilaNotificacoes {
        id: filaNotificacoes
    }
}
