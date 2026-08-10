import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"
import "../../components/Texto.js" as Texto
import "../../components/EdicaoComanda.js" as EdicaoComanda

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
    // Lista bruta (mais recente primeiro), como veio do controller — a busca
    // reordena a partir dela sem precisar reconsultar o disco a cada tecla.
    property var _todasComandas: []
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

    function _hojeFormatado() {
        var d = new Date();
        function doisDigitos(n) {
            return n < 10 ? "0" + n : String(n);
        }
        return doisDigitos(d.getDate()) + "/" + doisDigitos(d.getMonth() + 1) + "/" + d.getFullYear();
    }

    // "dd/mm/aaaa" -> número comparável, pra ordenar os dias anteriores do
    // mais recente pro mais antigo mesmo se a lista de entrada não vier
    // perfeitamente ordenada por dia (uma comanda sincronizada com atraso de
    // outra máquina tem "modificadoEm" de agora, mas "dataHora" de um dia
    // passado — ver consultaController.listarComandas).
    function _chaveDia(dia) {
        var partes = dia.split("/");
        if (partes.length !== 3)
            return 0;
        return Number(partes[2]) * 10000 + Number(partes[1]) * 100 + Number(partes[0]);
    }

    // Separa `lista` (já filtrada por status) em "hoje" (vai pro
    // modeloComandas, exibido direto) e o resto, agrupado por dia em
    // gruposAnteriores (cada grupo aninhado numa caixinha fechada por
    // padrão — ver ColunaEsquerda.qml, mesmo padrão de "Mapeamento por
    // origem" em Fechamento.qml).
    function _agruparPorDia(lista) {
        var hojeStr = telaConsulta._hojeFormatado();
        var hoje = [];
        var mapaDias = {};
        var ordemDias = [];

        for (var i = 0; i < lista.length; i++) {
            var item = lista[i];
            var dia = telaConsulta._diaDeDataHora(item.dataHora);
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
                "comandas": mapaDias[ordemDias[k]]
            });

        telaConsulta._preencherModelo(hoje, grupos);
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

    // Quanto menor, mais "perto" da busca: substring encontrada pontua pela
    // posição do match (aparecer logo no início vale mais que no meio).
    // Sem substring, entra num "balde" de pontuação fixa (sem calcular
    // distância de edição contra o conteúdo inteiro do cupom, que seria
    // O(tamanho do texto x tamanho da busca) por comanda — caro demais para
    // rodar a cada tecla numa lista que só cresce). indexOf sozinho é
    // O(tamanho do texto), suficiente para ordenar por relevância.
    function pontuarTexto(texto, busca) {
        if (busca === "")
            return 0;

        var t = Texto.normalizar(texto);
        var posicao = t.indexOf(busca);
        return posicao !== -1 ? posicao : 100000;
    }

    // Combina o nome exibido (cliente + horário), o código da comanda e o
    // conteúdo do cupom, com uma leve penalidade para matches que só
    // aparecem no conteúdo — pesquisar pelo nome do cliente deve priorizar
    // aquele cliente.
    //
    // O código entra sem penalidade nenhuma (é o campo mais específico que
    // existe: quem digita "A291201" quer exatamente aquela comanda). Ele
    // aparece no conteúdo do cupom também, mas só por lá herdaria a
    // penalidade de 500 e afundaria abaixo de qualquer comanda cujo nome de
    // cliente casasse por acaso — justo no caso em que a busca é mais
    // precisa, que é conferir uma comanda entre duas máquinas.
    function pontuarComanda(item, busca) {
        if (busca === "")
            return 0;

        var pontoTitulo = telaConsulta.pontuarTexto(telaConsulta.tituloComanda(item), busca);
        var pontoCodigo = item.codigo ? telaConsulta.pontuarTexto(item.codigo, busca) : 100000;
        var pontoConteudo = telaConsulta.pontuarTexto(item.conteudo, busca) + 500;
        return Math.min(pontoTitulo, pontoCodigo, pontoConteudo);
    }

    // Reordena _todasComandas pela proximidade com o texto pesquisado (sem
    // esconder nenhuma comanda) e repopula o modelo exibido na lista.
    //
    // O filtro por status é a única coisa aqui que de fato ESCONDE comandas —
    // é uma escolha explícita do usuário no seletor, diferente da busca, que
    // só reordena.
    function aplicarFiltro() {
        var busca = Texto.normalizar(telaConsulta.buscaAtual.trim());
        var lista = telaConsulta._todasComandas;

        if (telaConsulta.filtroStatus !== "todas") {
            var querFechadas = telaConsulta.filtroStatus === "fechadas";
            lista = lista.filter(function (item) {
                return (item.fechada === true) === querFechadas;
            });
        }

        if (busca !== "") {
            // Calcula a pontuação de cada comanda uma única vez — O(n) — em
            // vez de deixar o comparador do sort recalculá-la a cada
            // comparação, o que custaria O(n log n) avaliações de pontuação.
            var comPontuacao = [];
            for (var i = 0; i < lista.length; i++) {
                comPontuacao.push({
                    "item": lista[i],
                    "pontuacao": telaConsulta.pontuarComanda(lista[i], busca)
                });
            }
            comPontuacao.sort(function (a, b) {
                return a.pontuacao - b.pontuacao;
            });
            lista = comPontuacao.map(function (par) {
                return par.item;
            });

            // Busca mostra tudo achatado, sem agrupar por dia — encontrar a
            // comanda certa não deveria exigir abrir a caixinha do dia
            // certo primeiro.
            telaConsulta._preencherModelo(lista, []);
            return;
        }

        telaConsulta._agruparPorDia(lista);
    }

    // Pede o recarregamento da lista sem fazê-lo agora: quem chama aqui é
    // sempre alguém que acabou de mexer na tela (abrir a página, apagar uma
    // comanda, receber um pedido da rede), e a leitura em si — ler todo o
    // pedidos/ do disco e remontar a lista — leva tempo suficiente pra
    // segurar o primeiro quadro da página inteira.
    //
    // O timer resolve duas coisas de uma vez: devolve o controle ao loop de
    // eventos, pra interface aparecer antes das comandas, e junta numa
    // leitura só as chamadas em rajada (a página chama duas vezes ao abrir,
    // por Component.onCompleted e StackView.onActivated, e a malha chama uma
    // vez por pedido recebido durante uma sincronização).
    function carregarComandas() {
        telaConsulta.carregando = true;
        telaConsulta.comandaSelecionada = null;
        telaConsulta.arquivoSelecionado = "";
        timerCarregar.restart();
    }

    function _lerDoDisco() {
        telaConsulta._todasComandas = consultaController.listarComandas();
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

    // 50ms, e não 0/1ms, porque o objetivo é que um quadro chegue mesmo a ser
    // desenhado antes da leitura começar — um timer curto demais dispara
    // dentro do mesmo ciclo em que a página está sendo montada, e a tela
    // continuaria aparecendo só depois das comandas, que é justamente o que
    // isto veio resolver. Perto do tempo da leitura, é pausa que ninguém vê.
    Timer {
        id: timerCarregar

        interval: 50
        repeat: false
        onTriggered: telaConsulta._lerDoDisco()
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
                        font.bold: true
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.sm
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
                    font.bold: true
                    color: Estilo.global.textOnAccent
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            background: Rectangle {
                radius: Estilo.global.radius.sm
                color: parent.down ? Estilo.action.danger.pressed : (parent.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                border.color: Estilo.action.danger.pressed
                border.width: Estilo.global.borderWidth.hairline
            }
        }
    }
}
