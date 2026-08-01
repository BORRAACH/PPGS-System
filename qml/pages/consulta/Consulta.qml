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

    // Exposto para AreaPrincipal.qml/ColunaEsquerda.qml preencherem a lista.
    property alias modelo: modeloComandas

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
        }
        modeloComandas.clear();
        for (var j = 0; j < lista.length; j++) {
            modeloComandas.append(lista[j]);
        }
    }

    function carregarComandas() {
        telaConsulta._todasComandas = consultaController.listarComandas();
        telaConsulta.comandaSelecionada = null;
        telaConsulta.arquivoSelecionado = "";
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
        color: Estilo.cores.fundoPagina
        radius: Estilo.rounding.popup
    }

    ListModel {
        id: modeloComandas
    }

    PopupConfirmarExclusao {
        id: popupConfirmarExclusao

        onComandaApagada: telaConsulta.carregarComandas()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        // --- CABEÇALHO ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 15

            Row {
                spacing: 8
                Icone { nome: "fa6s.magnifying-glass"; cor: "#7c3aed"; tamanho: Estilo.fonte.titulo; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "CONSULTA DE COMANDAS"
                    font.pixelSize: Estilo.fonte.titulo
                    font.bold: true
                    color: "#7c3aed"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Row {
                spacing: 6
                Icone { nome: "fa6s.globe"; cor: Estilo.cores.textoSecundario; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    // O guard existe porque, no encerramento do app, as
                    // context properties são destruídas antes das telas: sem
                    // ele este binding roda uma última vez com
                    // redeController já nulo e deixa um TypeError no
                    // logs/app.log a cada fechamento — ruído bem no arquivo
                    // que se usa pra diagnosticar problema de rede.
                    text: (redeController ? redeController.quantidadeConectados : 0) + " conectado(s)"
                    font.pixelSize: Estilo.fonte.padrao
                    color: Estilo.cores.textoSecundario
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Button {
                id: btnAtualizar

                padding: 8
                onClicked: telaConsulta.carregarComandas()

                contentItem: Row {
                    spacing: 6
                    Icone { nome: "fa6s.arrows-rotate"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "Atualizar"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? "#6d28d9" : (parent.hovered ? "#8b5cf6" : "#7c3aed")
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

            padding: 10
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 200
            onClicked: {
                if (telaConsulta.StackView.view)
                    telaConsulta.StackView.view.irParaInicio();
            }

            contentItem: Row {
                spacing: 6
                anchors.centerIn: parent
                Icone { nome: "fa6s.arrow-left"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "Voltar para o Menu"
                    font.bold: true
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            background: Rectangle {
                radius: Estilo.rounding.padrao
                color: parent.down ? Estilo.cancelar.pressionado : (parent.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                border.color: Estilo.cancelar.pressionado
                border.width: 1
            }
        }
    }
}
