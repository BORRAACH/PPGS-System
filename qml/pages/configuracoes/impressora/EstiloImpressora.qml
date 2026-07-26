import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../../components"

// Configuração de estilo ESC/POS da comanda impressa: quais campos (nome do
// cliente, do pedido, forma de pagamento etc.) saem em negrito/sublinhado/
// fonte grande/fundo preto (modo reverso), e o espaçamento entre seções e
// antes do corte automático. Lida/gravada por comandaEstiloController (ver
// services/comandaEstiloService.py), que balcaoController.py/
// entregaController.py consultam ao montar a comanda.
//
// Não é uma Page própria — é o conteúdo embutido por
// ../Configuracoes.qml dentro da área rolável da tela de Configurações.
Column {
    id: raiz

    readonly property color corDestaque: "#475569"
    property int espacamentoSecoes: 1
    property int espacamentoCorte: 4
    property int tamanhoFontePadrao: 24
    // Estado local desta sessão de edição — cliques no popup só mexem aqui
    // (instantâneo, sem chamar o Python). Só vira gravação em disco de fato
    // em salvarNoBackend(), chamado ao sair da tela (ver
    // Component.onDestruction abaixo e StackView.onDeactivated em
    // ../Configuracoes.qml). Gravar a cada clique deixava os controles com
    // uma sensação de atraso, porque a chamada síncrona pro Python bloqueava
    // o próximo frame de renderização até terminar.
    property var configAtual: ({
        "campos": {}
    })
    // Incrementado a cada mudança local (ver tocar()) só para servir de
    // dependência de binding — configAtual é um objeto JS comum, então
    // mutá-lo (definirAtributoLocal/definirTamanhoFonteLocal) não emite
    // nenhum sinal de mudança de propriedade sozinho. A lista de campos e a
    // prévia da comanda leem esta propriedade para saber quando reavaliar
    // suas bindings (ver PreviaCampoTexto.qml).
    property int versaoConfig: 0

    spacing: 25

    function tocar() {
        raiz.versaoConfig += 1;
    }

    function obterAtributo(campo, atributo) {
        var atributosCampo = raiz.configAtual.campos[campo];
        return !!(atributosCampo && atributosCampo[atributo]);
    }

    // Iguais a obterAtributo()/obterTamanhoFonte(), mas recebendo
    // versaoConfig como argumento extra (sem usá-lo no corpo) — configAtual
    // é um objeto JS comum, então mutá-lo não emite nenhum sinal de mudança
    // de propriedade sozinho. Ler versaoConfig (uma property de verdade)
    // dentro da própria expressão de binding de quem chama esta função é o
    // que cria a dependência que faltava, sem recorrer a um "comma
    // expression" (que o qmllint reprova). Usadas pela lista de campos e
    // pela prévia da comanda (PreviaCampoTexto.qml).
    function obterAtributoReativo(campo, atributo, versao) {
        return raiz.obterAtributo(campo, atributo);
    }

    function obterTamanhoFonteReativo(campo, versao) {
        return raiz.obterTamanhoFonte(campo);
    }

    function definirAtributoLocal(campo, atributo, valor) {
        if (!raiz.configAtual.campos[campo])
            raiz.configAtual.campos[campo] = {};

        raiz.configAtual.campos[campo][atributo] = valor;
        raiz.tocar();
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
        raiz.tocar();
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
            "espacamento_secoes": raiz.espacamentoSecoes,
            "espacamento_corte": raiz.espacamentoCorte
        });
    }

    function carregarConfiguracao() {
        var config = comandaEstiloController.obterConfiguracao();
        var campos = comandaEstiloController.listarCampos();
        raiz.tamanhoFontePadrao = comandaEstiloController.tamanhoFontePadrao();
        raiz.configAtual = config;

        modeloCampos.clear();
        for (var i = 0; i < campos.length; i++) {
            modeloCampos.append({
                "chave": campos[i].chave,
                "rotulo": campos[i].rotulo
            });
        }

        raiz.espacamentoSecoes = config.espacamento_secoes !== undefined ? config.espacamento_secoes : 1;
        raiz.espacamentoCorte = config.espacamento_corte !== undefined ? config.espacamento_corte : 4;
    }

    Component.onCompleted: carregarConfiguracao()
    // Cobre o caso de a Page ser realmente destruída (botão Voltar, botão
    // Início, fechar o app) — o caso de "empurrada pra baixo na pilha por
    // outra tela da barra lateral" (sem ser destruída) é coberto por
    // StackView.onDeactivated em ../Configuracoes.qml, já que este item
    // continua vivo nesse caso.
    Component.onDestruction: raiz.salvarNoBackend()

    ListModel {
        id: modeloCampos
    }

    // --- CABEÇALHO DA SEÇÃO + RESTAURAR PADRÕES ---
    RowLayout {
        width: raiz.width
        spacing: 15

        Row {
            spacing: 8
            Icone { nome: "fa6s.receipt"; cor: raiz.corDestaque; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: "ESTILO DA COMANDA IMPRESSA"
                font.pixelSize: 16
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
            onClicked: {
                comandaEstiloController.restaurarPadroes();
                raiz.carregarConfiguracao();
            }

            contentItem: Row {
                spacing: 6
                Icone { nome: "fa6s.arrow-rotate-left"; cor: "#ffffff"; tamanho: Estilo.fonte.padrao; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "Restaurar padrões"
                    font.bold: true
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            background: Rectangle {
                radius: Estilo.rounding.padrao
                color: parent.down ? Estilo.cancelar.pressionado : (parent.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
            }
        }
    }

    // --- LISTA DE CAMPOS + PRÉVIA DA COMANDA ---
    Row {
        width: parent.width
        spacing: Estilo.espacamento.grande

        // Lista de campos: cada item abre popupEstiloCampo com as
        // alterações disponíveis (negrito, sublinhado, fundo preto, tamanho
        // de fonte) — em vez da tabela antiga com um checkbox por atributo
        // já visível de cara, o que ficava apertado e difícil de escanear
        // com 14 campos x 3 atributos + tamanho de fonte.
        Rectangle {
            id: cardLista

            width: parent.width - cardPreviaComanda.width - parent.spacing
            height: colunaLista.implicitHeight + Estilo.preenchimento.grande * 2
            radius: Estilo.rounding.painel
            color: "#ffffff"
            border.color: Estilo.cores.bordaCard
            border.width: 1

            Column {
                id: colunaLista

                anchors.fill: parent
                anchors.margins: Estilo.preenchimento.grande
                spacing: Estilo.espacamento.normal

                Text {
                    text: "ESTILO POR CAMPO"
                    font.pixelSize: 15
                    font.bold: true
                    color: raiz.corDestaque
                }

                Text {
                    width: parent.width
                    text: "Toque em um campo para escolher negrito, sublinhado, fundo preto e tamanho da fonte."
                    font.pixelSize: 12
                    color: Estilo.cores.textoSecundario
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: modeloCampos

                    delegate: Rectangle {
                        id: linhaCampo

                        // Capturado aqui (em vez de acessar "model" direto lá
                        // embaixo) porque o Repeater aninhado abaixo tem seu
                        // próprio "model" (a lista de atributos), que
                        // esconderia o "model" deste Repeater externo.
                        property string chave: model.chave

                        // Propriedades QML de verdade (ao contrário de
                        // configAtual) — os badges abaixo dependem destas,
                        // então mudanças feitas no popup para este campo
                        // atualizam os badges sem precisar recriar a linha
                        // (ver obterAtributoReativo() acima).
                        readonly property bool _negrito: raiz.obterAtributoReativo(chave, "negrito", raiz.versaoConfig)
                        readonly property bool _sublinhado: raiz.obterAtributoReativo(chave, "sublinhado", raiz.versaoConfig)
                        readonly property bool _fundoPreto: raiz.obterAtributoReativo(chave, "fundo_preto", raiz.versaoConfig)
                        readonly property int _tamanhoFonte: raiz.obterTamanhoFonteReativo(chave, raiz.versaoConfig)

                        width: colunaLista.width
                        height: 46
                        radius: Estilo.rounding.padrao
                        color: areaClique.containsMouse ? Estilo.cores.fundoPagina : "#ffffff"
                        border.color: Estilo.cores.bordaCard
                        border.width: 1

                        MouseArea {
                            id: areaClique

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popupEstiloCampo.abrirPara(linhaCampo.chave, model.rotulo)
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 10

                            Text {
                                width: parent.width - badges.width - iconeAbrir.width - 20
                                anchors.verticalCenter: parent.verticalCenter
                                text: model.rotulo
                                font.pixelSize: 13
                                color: Estilo.cores.texto
                                elide: Text.ElideRight
                            }

                            Row {
                                id: badges

                                spacing: 6
                                anchors.verticalCenter: parent.verticalCenter

                                Label {
                                    visible: linhaCampo._negrito
                                    text: "N"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: "#ffffff"
                                    padding: 4
                                    background: Rectangle { radius: Estilo.rounding.cheio; color: raiz.corDestaque }
                                }

                                Label {
                                    visible: linhaCampo._sublinhado
                                    text: "S"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: "#ffffff"
                                    padding: 4
                                    background: Rectangle { radius: Estilo.rounding.cheio; color: raiz.corDestaque }
                                }

                                Label {
                                    visible: linhaCampo._fundoPreto
                                    text: "F"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: "#ffffff"
                                    padding: 4
                                    background: Rectangle { radius: Estilo.rounding.cheio; color: raiz.corDestaque }
                                }

                                Text {
                                    visible: linhaCampo._tamanhoFonte !== raiz.tamanhoFontePadrao
                                    text: raiz.multiplicadorFonte(linhaCampo._tamanhoFonte) + "x"
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Estilo.cores.textoSecundario
                                }
                            }

                            Icone {
                                id: iconeAbrir

                                nome: "fa6s.chevron-right"
                                cor: Estilo.cores.textoSecundario
                                tamanho: 13
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }

        // Comanda teste: prévia lado a lado com a lista, mostrando ao vivo
        // como cada campo estilizado sai impresso — inclusive o tamanho de
        // fonte já convertido pro multiplicador ESC/POS real (ver
        // multiplicadorFonte() acima), não o valor em pixels puro digitado.
        Rectangle {
            id: cardPreviaComanda

            width: 380
            height: colunaPreviaComanda.implicitHeight + Estilo.preenchimento.grande * 2
            radius: Estilo.rounding.painel
            color: "#ffffff"
            border.color: Estilo.cores.bordaCard
            border.width: 1

            Column {
                id: colunaPreviaComanda

                anchors.fill: parent
                anchors.margins: Estilo.preenchimento.grande
                spacing: Estilo.espacamento.normal

                Row {
                    spacing: 8
                    Icone { nome: "fa6s.receipt"; cor: raiz.corDestaque; tamanho: 14; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        text: "COMANDA TESTE"
                        font.pixelSize: 15
                        font.bold: true
                        color: raiz.corDestaque
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Estilo.cores.bordaCard
                }

                // Área com fundo de papel, largura fixa que lembra o rolo
                // de 40 colunas da impressora térmica.
                Rectangle {
                    width: parent.width
                    height: colunaPapel.implicitHeight + 20
                    radius: 4
                    color: "#fdfdf7"
                    border.color: "#e5e0c8"
                    // Campos com fonte bem maior (multiplicador alto) podem
                    // ficar mais largos que o papel — contém em vez de
                    // vazar visualmente pra fora do card.
                    clip: true

                    Column {
                        id: colunaPapel

                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.topMargin: 10
                        width: parent.width - 20
                        spacing: 3

                        Row {
                            spacing: 4
                            Text { text: "Cliente: "; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                            PreviaCampoTexto { controlador: raiz; campo: "cliente"; texto: "João da Silva" }
                        }

                        Row {
                            spacing: 4
                            Text { text: "Telefone: "; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                            PreviaCampoTexto { controlador: raiz; campo: "telefone"; texto: "(11) 91234-5678" }
                        }

                        Row {
                            spacing: 4
                            Text { text: "Endereço: "; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                            PreviaCampoTexto { controlador: raiz; campo: "endereco"; texto: "Rua Exemplo, 123" }
                        }

                        Row {
                            spacing: 4
                            Text { text: "Bairro: "; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                            PreviaCampoTexto { controlador: raiz; campo: "bairro"; texto: "Centro" }
                        }

                        Row {
                            spacing: 4
                            Text { text: "Data: "; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                            PreviaCampoTexto { controlador: raiz; campo: "data"; texto: "25/07/2026 20:15:00" }
                        }

                        Text { text: "-".repeat(28); font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }

                        PreviaCampoTexto { controlador: raiz; campo: "pedido"; texto: "- PIZZA G. CALABRESA (GRANDE)" }
                        PreviaCampoTexto { controlador: raiz; campo: "observacao_item"; texto: "  SEM CEBOLA" }

                        Text { text: "-".repeat(28); font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }

                        Row {
                            spacing: 4
                            Text { text: "Obs.: "; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                            PreviaCampoTexto { controlador: raiz; campo: "observacao_entrega"; texto: "Interfone quebrado" }
                        }

                        Text { text: "-".repeat(28); font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }

                        Row {
                            spacing: 4
                            Text { text: "Pagamento: "; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                            PreviaCampoTexto { controlador: raiz; campo: "forma_pagamento"; texto: "Dinheiro" }
                        }

                        Row {
                            spacing: 4
                            Text { text: "Troco para: "; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                            PreviaCampoTexto { controlador: raiz; campo: "troco_para"; texto: "R$ 100,00" }
                        }

                        Text { text: "-".repeat(28); font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }

                        Row {
                            spacing: 4
                            Text { text: "Taxa entrega: "; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                            PreviaCampoTexto { controlador: raiz; campo: "taxa_entrega"; texto: "R$ 5,00" }
                        }

                        Row {
                            spacing: 4
                            Text { text: "Valor: "; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                            PreviaCampoTexto { controlador: raiz; campo: "valor_total"; texto: "R$ 45,00" }
                            Text { text: " ["; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                            PreviaCampoTexto { controlador: raiz; campo: "status"; texto: "NP" }
                            Text { text: "]"; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                        }

                        Row {
                            spacing: 4
                            Text { text: "Troco a dar: "; font.family: "monospace"; font.pixelSize: 12; color: Estilo.cores.texto }
                            PreviaCampoTexto { controlador: raiz; campo: "troco_a_dar"; texto: "R$ 55,00" }
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

    // --- ESPAÇAMENTO ---
    Rectangle {
        width: parent.width
        height: colunaEspacamento.implicitHeight + Estilo.preenchimento.grande * 2
        radius: Estilo.rounding.painel
        color: "#ffffff"
        border.color: Estilo.cores.bordaCard
        border.width: 1

        Column {
            id: colunaEspacamento

            anchors.fill: parent
            anchors.margins: Estilo.preenchimento.grande
            spacing: Estilo.espacamento.maior

            Text {
                text: "ESPAÇAMENTO"
                font.pixelSize: 15
                font.bold: true
                color: raiz.corDestaque
            }

            // Linhas em branco entre seções da comanda
            Row {
                spacing: 15

                Text {
                    width: 300
                    text: "Linhas em branco entre seções da comanda"
                    font.pixelSize: 13
                    color: Estilo.cores.texto
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
                        radius: Estilo.rounding.padrao
                        color: parent.down ? Estilo.cores.bordaCard : "#ffffff"
                        border.color: Estilo.cores.borda
                        border.width: 1
                    }
                }

                Text {
                    width: 30
                    text: raiz.espacamentoSecoes
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 14
                    font.bold: true
                    color: Estilo.cores.texto
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    text: "+"
                    width: 32
                    height: 32
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: raiz.espacamentoSecoes += 1

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: parent.down ? Estilo.cores.bordaCard : "#ffffff"
                        border.color: Estilo.cores.borda
                        border.width: 1
                    }
                }
            }

            // Linhas em branco antes do corte automático
            Row {
                spacing: 15

                Text {
                    width: 300
                    text: "Linhas em branco antes do corte automático"
                    font.pixelSize: 13
                    color: Estilo.cores.texto
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
                        radius: Estilo.rounding.padrao
                        color: parent.down ? Estilo.cores.bordaCard : "#ffffff"
                        border.color: Estilo.cores.borda
                        border.width: 1
                    }
                }

                Text {
                    width: 30
                    text: raiz.espacamentoCorte
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 14
                    font.bold: true
                    color: Estilo.cores.texto
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    text: "+"
                    width: 32
                    height: 32
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: raiz.espacamentoCorte += 1

                    background: Rectangle {
                        radius: Estilo.rounding.padrao
                        color: parent.down ? Estilo.cores.bordaCard : "#ffffff"
                        border.color: Estilo.cores.borda
                        border.width: 1
                    }
                }
            }
        }
    }
}
