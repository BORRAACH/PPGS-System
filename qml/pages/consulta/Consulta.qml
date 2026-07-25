import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

Page {
    id: telaConsulta

    objectName: "telaConsulta"

    // Comanda atualmente exibida no painel da direita (objeto simples com
    // tipo/arquivo/conteudo). null enquanto nada foi selecionado ainda.
    property var comandaSelecionada: null
    property int indiceSelecionado: -1
    // Lista bruta (mais recente primeiro), como veio do controller — a busca
    // reordena a partir dela sem precisar reconsultar o disco a cada tecla.
    property var _todasComandas: []
    // Texto de busca atual: o campo de texto vive em ColunaEsquerda.qml, mas
    // o filtro precisa sobreviver a um "Atualizar" (que recarrega o disco).
    property string buscaAtual: ""

    // Exposto para AreaPrincipal.qml/ColunaEsquerda.qml preencherem a lista.
    property alias modelo: modeloComandas

    // Monta "Nome do Cliente - horário" a partir dos campos já extraídos
    // pelo consultaController (lidos do cabeçalho do próprio cupom).
    function tituloComanda(item) {
        var cliente = item.cliente && item.cliente.trim() !== "" ? item.cliente.trim() : "Cliente não informado";
        return item.dataHora ? cliente + " - " + item.dataHora : cliente;
    }

    // Distância de edição clássica (Levenshtein) — usada como medida de
    // "proximidade" para textos que não contêm a busca como substring.
    function distanciaLevenshtein(a, b) {
        var m = a.length;
        var n = b.length;
        if (m === 0)
            return n;

        if (n === 0)
            return m;

        var linhaAnterior = [];
        for (var j = 0; j <= n; j++) {
            linhaAnterior.push(j);
        }
        for (var i = 1; i <= m; i++) {
            var linhaAtual = [i];
            for (var k = 1; k <= n; k++) {
                var custo = a[i - 1] === b[k - 1] ? 0 : 1;
                linhaAtual.push(Math.min(linhaAnterior[k] + 1, linhaAtual[k - 1] + 1, linhaAnterior[k - 1] + custo));
            }
            linhaAnterior = linhaAtual;
        }
        return linhaAnterior[n];
    }

    // Quanto menor, mais "perto" da busca: substring encontrada pontua pela
    // posição do match (aparecer logo no início vale mais que no meio);
    // sem substring, cai para distância de edição — sempre pior que
    // qualquer substring encontrada, mas ainda ordena por proximidade.
    function pontuarTexto(texto, busca) {
        if (busca === "")
            return 0;

        var t = (texto || "").toLowerCase();
        var posicao = t.indexOf(busca);
        if (posicao !== -1)
            return posicao;

        return 100000 + telaConsulta.distanciaLevenshtein(t, busca);
    }

    // Combina o nome exibido (cliente + horário) e o conteúdo do cupom,
    // com uma leve penalidade para matches que só aparecem no conteúdo —
    // pesquisar pelo nome do cliente deve priorizar aquele cliente.
    function pontuarComanda(item, busca) {
        if (busca === "")
            return 0;

        var pontoTitulo = telaConsulta.pontuarTexto(telaConsulta.tituloComanda(item), busca);
        var pontoConteudo = telaConsulta.pontuarTexto(item.conteudo, busca) + 500;
        return Math.min(pontoTitulo, pontoConteudo);
    }

    // Reordena _todasComandas pela proximidade com o texto pesquisado (sem
    // esconder nenhuma comanda) e repopula o modelo exibido na lista.
    function aplicarFiltro() {
        var busca = telaConsulta.buscaAtual.trim().toLowerCase();
        var lista = telaConsulta._todasComandas.slice();
        if (busca !== "") {
            lista.sort(function (a, b) {
                return telaConsulta.pontuarComanda(a, busca) - telaConsulta.pontuarComanda(b, busca);
            });
        }
        modeloComandas.clear();
        for (var i = 0; i < lista.length; i++) {
            modeloComandas.append(lista[i]);
        }
    }

    function carregarComandas() {
        telaConsulta._todasComandas = consultaController.listarComandas();
        telaConsulta.comandaSelecionada = null;
        telaConsulta.indiceSelecionado = -1;
        telaConsulta.aplicarFiltro();
    }

    // Reabre a comanda no formulário de Balcão ou Entrega (conforme o tipo
    // original) já preenchida, para edição estruturada e reimpressão. O
    // formulário guarda "arquivoOriginal" e apaga esse arquivo assim que a
    // versão editada é impressa com sucesso, para não deixar duplicata.
    function editarComanda(nomeArquivo) {
        var dados = consultaController.reconstruirComanda(nomeArquivo);
        if (!dados || !dados.itens)
            return;

        var pilhaPrincipal = telaConsulta.StackView.view;
        if (!pilhaPrincipal)
            return;

        if (dados.tipo === "Entrega") {
            pilhaPrincipal.push("../entrega/Entrega.qml", {
                "clienteNome": dados.cliente,
                "telefoneInicial": dados.telefone,
                "enderecoInicial": dados.endereco,
                "numeroInicial": dados.numero,
                "bairroInicial": dados.bairro,
                "observacaoInicial": dados.observacaoGeral,
                "formaPagamentoInicial": dados.formaPagamento,
                "trocoInicial": dados.troco,
                "statusPagamentoInicial": dados.statusPagamento,
                "itensIniciais": dados.itens,
                "arquivoOriginal": nomeArquivo
            });
        } else {
            pilhaPrincipal.push("../balcao/Balcao.qml", {
                "clienteNome": dados.cliente,
                "formaPagamentoInicial": dados.formaPagamento,
                "trocoInicial": dados.troco,
                "statusPagamentoInicial": dados.statusPagamento,
                "itensIniciais": dados.itens,
                "arquivoOriginal": nomeArquivo
            });
        }
    }

    Component.onCompleted: {
        carregarComandas();
        // Recarrega sozinho quando um pedido de outra máquina da rede
        // chega/some (ver redeController/consultaController.aplicarPedidoRemoto).
        consultaController.comandasAtualizadas.connect(carregarComandas);
    }
    StackView.onActivated: carregarComandas()

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
                    text: redeController.quantidadeConectados + " conectado(s)"
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
                    telaConsulta.StackView.view.pop();
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
