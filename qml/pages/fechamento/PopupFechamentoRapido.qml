import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"
import "../../components/EdicaoComanda.js" as EdicaoComanda
import "../consulta"

// Conferência de comandas do dia, uma de cada vez, mostrando a comanda
// inteira e oferecendo Baixa (fecha a comanda, e ela passa a contar no
// caixa), Editar (corrige valores/nome/pedidos), Reimprimir, Excluir
// (apaga de vez, com a mesma confirmação da Consulta) e Sair.
//
// Três modos de abertura, com a mesma moldura:
//
// - abrirPara(iso) — a FILA das comandas em aberto do dia, da mais recente
//   para a mais antiga (ver FechamentoController.listarComandasAbertas). As
//   setas ‹ › existem para poder pular uma comanda duvidosa e voltar nela
//   depois sem sair da fila — dar baixa não pode ser a única forma de
//   avançar, senão conferir a quinta comanda exigiria fechar as quatro
//   anteriores. Botão "Fechamento rápido" em Fechamento.qml.
// - abrirParaFechadas(iso) — o mesmo, mas a FILA das comandas que JÁ
//   receberam baixa (ver FechamentoController.listarComandasFechadas).
//   Simétrico ao anterior, pro botão "Editar caixa": toda comanda da fila já
//   chega com fechada=true, então "Baixa" fica oculto e "Editar" já passa
//   pelo painel de manter/reconferir a baixa (ver editarAtual()).
// - abrirComanda(arquivo, iso) — UMA comanda específica, clicada na lista do
//   dia em Fechamento.qml. Aqui entram também as que já receberam baixa, que
//   por definição não aparecem na fila de abertas — e são justamente elas
//   que costumam precisar de correção (uma comanda suspeita só é listada
//   como suspeita depois de baixada).
Popup {
    id: popupFechamentoRapido

    // Comandas em exibição, como vieram do controller. São recarregadas
    // inteiras a cada abertura, e não mantidas entre elas: outra máquina da
    // malha pode ter dado baixa ou lançado comandas nesse meio tempo.
    property var comandas: []
    property int indice: 0
    property string dataIso: ""

    readonly property var comandaAtual: indice >= 0 && indice < comandas.length ? comandas[indice] : null

    // Só a fila tem por onde navegar; com uma comanda só as setas e o
    // "Comanda N de M" não teriam o que fazer.
    readonly property bool modoFila: comandas.length > 1

    // Corrigir uma comanda é apagá-la e gravar outra, e a nova sai com a data
    // de agora (ver balcaoController._salvarComanda) — editar uma comanda de
    // ontem a tiraria do caixa de ontem e a jogaria no de hoje, mexendo em
    // dois dias de uma vez sem ninguém pedir. Por isso a correção fica presa
    // ao dia corrente; reimprimir, que não grava nada, não tem essa
    // restrição.
    readonly property bool ehHoje: dataIso === Qt.formatDate(new Date(), "yyyy-MM-dd")

    // Emitido quando alguma baixa foi dada — a página recarrega o dia.
    signal concluido

    function abrirPara(iso) {
        popupFechamentoRapido.dataIso = iso;
        popupFechamentoRapido.comandas = fechamentoController.listarComandasAbertas(iso);
        popupFechamentoRapido.indice = 0;
        popupFechamentoRapido.escolhendoBaixa = false;
        if (popupFechamentoRapido.comandas.length === 0)
            return false;

        open();
        return true;
    }

    function abrirParaFechadas(iso) {
        popupFechamentoRapido.dataIso = iso;
        popupFechamentoRapido.comandas = fechamentoController.listarComandasFechadas(iso);
        popupFechamentoRapido.indice = 0;
        popupFechamentoRapido.escolhendoBaixa = false;
        if (popupFechamentoRapido.comandas.length === 0)
            return false;

        open();
        return true;
    }

    function abrirComanda(arquivo, iso) {
        var dados = fechamentoController.obterComanda(arquivo);
        if (!dados || !dados.arquivo)
            return false;

        popupFechamentoRapido.dataIso = iso;
        popupFechamentoRapido.comandas = [dados];
        popupFechamentoRapido.indice = 0;
        popupFechamentoRapido.escolhendoBaixa = false;
        open();
        return true;
    }

    // Tira a comanda atual da fila depois da baixa, sem recarregar a lista
    // do disco: o índice fica onde está (que agora é a PRÓXIMA comanda),
    // exceto quando a baixada era a última, caso em que recua um.
    function _removerAtual() {
        var restantes = popupFechamentoRapido.comandas.slice();
        restantes.splice(popupFechamentoRapido.indice, 1);
        popupFechamentoRapido.comandas = restantes;
        if (popupFechamentoRapido.indice >= restantes.length)
            popupFechamentoRapido.indice = restantes.length - 1;
    }

    function darBaixaAtual() {
        var comanda = popupFechamentoRapido.comandaAtual;
        if (!comanda)
            return;

        if (!fechamentoController.darBaixa(comanda.arquivo))
            return;

        popupFechamentoRapido._removerAtual();
        popupFechamentoRapido.concluido();

        if (popupFechamentoRapido.comandas.length === 0)
            popupFechamentoRapido.close();
    }

    // A comanda já foi conferida e o atendente pediu pra corrigi-la: antes de
    // abrir o formulário é preciso saber o que fazer com a baixa, porque a
    // comanda corrigida é um arquivo NOVO e nasceria fora do caixa do dia.
    property bool escolhendoBaixa: false

    function editarAtual() {
        var comanda = popupFechamentoRapido.comandaAtual;
        if (!comanda)
            return;

        // Comanda ainda em aberto não tem baixa pra decidir — segue direto.
        if (!comanda.fechada) {
            popupFechamentoRapido._abrirEdicao(false);
            return;
        }

        popupFechamentoRapido.escolhendoBaixa = true;
    }

    function _abrirEdicao(manterBaixa) {
        var comanda = popupFechamentoRapido.comandaAtual;
        if (!comanda)
            return;

        // Fecha antes de empurrar o formulário: a edição sai da página de
        // Fechamento (é o mesmo caminho que a Consulta usa — ver
        // components/EdicaoComanda.js), e deixar o popup aberto por baixo
        // faria ele reaparecer sobre o formulário de Balcão/Entrega.
        popupFechamentoRapido.escolhendoBaixa = false;
        popupFechamentoRapido.close();
        EdicaoComanda.abrir(popupFechamentoRapido.pilhaPrincipal, comanda.arquivo, manterBaixa);
    }

    function reimprimirAtual() {
        var comanda = popupFechamentoRapido.comandaAtual;
        if (!comanda)
            return;

        // Nada de fechar o popup nem de recarregar a lista: reimprimir não
        // altera a comanda. O resultado chega depois, por
        // redeController.impressaoResultado, que Fechamento.qml escuta.
        fechamentoController.reimprimirComanda(comanda.arquivo);
    }

    // Abre a mesma confirmação usada na Consulta (ver
    // ItemComandaDelegate.qml/PopupConfirmarExclusao.qml) — comanda já
    // fechada não apaga mais direto por lá, então este é o único caminho
    // que sobrou pra corrigir um lançamento indevido apagando de vez.
    function excluirAtual() {
        var comanda = popupFechamentoRapido.comandaAtual;
        if (!comanda)
            return;

        var cliente = comanda.cliente && comanda.cliente.trim() !== "" ? comanda.cliente.trim() : "Cliente não informado";
        var titulo = comanda.dataHora ? cliente + " - " + comanda.dataHora : cliente;
        popupConfirmarExclusao.abrirPara(comanda.arquivo, titulo);
    }

    // Mesmo raciocínio de darBaixaAtual(): tira só a comanda apagada da
    // fila em memória, sem recarregar a lista inteira do disco.
    function _aoApagarAtual() {
        popupFechamentoRapido._removerAtual();
        popupFechamentoRapido.concluido();

        if (popupFechamentoRapido.comandas.length === 0)
            popupFechamentoRapido.close();
    }

    PopupConfirmarExclusao {
        id: popupConfirmarExclusao

        onComandaApagada: popupFechamentoRapido._aoApagarAtual()
    }

    // Preenche o ListModel que alimenta o ResumoComanda a partir da comanda
    // reconstruída do .txt. "borda" e "adicionais" entram como STRING JSON,
    // seguindo a mesma convenção de Balcao.qml/Entrega.qml: um objeto/array
    // atribuído a um role de ListModel vira um list-model aninhado em vez de
    // continuar sendo objeto/array.
    function _recarregarDetalhe() {
        modeloItens.clear();
        detalhe = ({});

        var comanda = popupFechamentoRapido.comandaAtual;
        if (!comanda)
            return;

        // Comanda de Mesa traz a divisão da conta, que _reconstruir_itens não
        // modela — cai no cupom, igual ao botão Editar, que também a recusa.
        if (comanda.tipo === "Mesa")
            return;

        var dados = consultaController.reconstruirComanda(comanda.arquivo);
        if (!dados || !dados.itens || dados.itens.length === 0)
            return;

        for (var i = 0; i < dados.itens.length; i++) {
            var item = dados.itens[i];
            modeloItens.append({
                "pedido": item.pedido || "",
                "observacao": item.observacao || "",
                "valor": item.valor || "",
                "borda": JSON.stringify(item.borda || null),
                "adicionais": JSON.stringify(item.adicionais || [])
            });
        }
        detalhe = dados;
    }

    // Campos de cabeçalho da comanda reconstruída ({} quando não houver
    // reconstrução — é o que faz o cupom aparecer no lugar do resumo).
    property var detalhe: ({})
    readonly property bool temDetalhe: modeloItens.count > 0

    onComandaAtualChanged: popupFechamentoRapido._recarregarDetalhe()

    ListModel {
        id: modeloItens

        // Todos os roles precisam existir já no primeiro elemento, senão
        // append() com objeto/null não os cria — mesmo motivo documentado em
        // Balcao.qml. O elemento em branco é removido pelo clear() de
        // _recarregarDetalhe antes do primeiro uso.
        ListElement {
            pedido: ""
            observacao: ""
            valor: ""
            borda: "null"
            adicionais: "[]"
        }
    }

    // StackView onde os formulários de edição são empurrados — preenchido
    // por Fechamento.qml, porque o popup vive em Overlay.overlay e não
    // enxerga a pilha pela hierarquia visual.
    property var pilhaPrincipal: null

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: 25
    parent: Overlay.overlay
    anchors.centerIn: parent
    // Dá foco de teclado ao conteúdo assim que o popup abre — sem isso, as
    // setas ‹ › e o F10 (ver Keys.onPressed em colunaConteudo) só
    // funcionariam depois de um clique qualquer dentro do popup.
    onOpened: colunaConteudo.forceActiveFocus()

    width: Math.min(760, parent ? parent.width * 0.9 : 760)
    height: Math.min(720, parent ? parent.height * 0.9 : 720)

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        radius: Estilo.rounding.popup
        color: Estilo.cores.fundoPagina
        border.color: Estilo.cores.bordaCard
    }

    contentItem: ColumnLayout {
        id: colunaConteudo

        spacing: Estilo.espacamento.maior
        focus: true
        // Setas ‹ › (mesma navegação dos botões btnAnterior/btnProxima, só
        // que sem precisar mirar neles) e F10 como atalho pro botão Baixa —
        // clicar num Button da QtQuick Controls não rouba o foco de teclado
        // (focusPolicy padrão é Qt.TabFocus, não Qt.ClickFocus), então isto
        // continua respondendo mesmo depois de clicar em Reimprimir/Editar/
        // Excluir dentro do próprio popup.
        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Left) {
                if (popupFechamentoRapido.modoFila && popupFechamentoRapido.indice > 0)
                    popupFechamentoRapido.indice--;
                event.accepted = true;
            } else if (event.key === Qt.Key_Right) {
                if (popupFechamentoRapido.modoFila && popupFechamentoRapido.indice < popupFechamentoRapido.comandas.length - 1)
                    popupFechamentoRapido.indice++;
                event.accepted = true;
            } else if (event.key === Qt.Key_F10) {
                // Mesma condição de visible do btnBaixa: comanda já
                // conferida não tem baixa a dar.
                if (popupFechamentoRapido.comandaAtual !== null && !popupFechamentoRapido.comandaAtual.fechada)
                    popupFechamentoRapido.darBaixaAtual();
                event.accepted = true;
            }
        }

        // --- CABEÇALHO: navegação e identificação da comanda ---
        // Item com âncoras, e não um RowLayout: as setas ficam presas às
        // bordas e o título no centro exato, independente do texto ("1 de 3"
        // é mais estreito que "10 de 12"). Num RowLayout as setas andariam
        // junto com a largura do título a cada comanda da fila — justo o
        // botão que se clica repetidamente.
        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(btnAnterior.implicitHeight, colunaTitulo.implicitHeight)

            Button {
                id: btnAnterior

                visible: popupFechamentoRapido.modoFila
                enabled: popupFechamentoRapido.indice > 0
                implicitWidth: 34
                implicitHeight: 34
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                onClicked: popupFechamentoRapido.indice--

                contentItem: Text {
                    text: "‹"
                    font.pixelSize: 20
                    font.bold: true
                    color: btnAnterior.enabled ? Estilo.cores.texto : Estilo.cores.borda
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.cheio
                    color: btnAnterior.down ? "#e5e7eb" : (btnAnterior.hovered ? "#f1f5f9" : "transparent")
                    border.color: btnAnterior.enabled ? Estilo.cores.borda : "transparent"
                    border.width: 1
                }
            }

            Column {
                id: colunaTitulo

                anchors.centerIn: parent
                spacing: 2

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Na fila, a posição; numa comanda só, o rótulo do que se
                    // está fazendo ali — "Comanda 1 de 1" não diz nada.
                    text: popupFechamentoRapido.modoFila
                        ? "Comanda " + (popupFechamentoRapido.indice + 1) + " de " + popupFechamentoRapido.comandas.length
                        : "Conferir comanda"
                    font.pixelSize: 17
                    font.bold: true
                    color: Estilo.cores.texto
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    Rectangle {
                        radius: 6
                        width: textoTipo.implicitWidth + 14
                        height: textoTipo.implicitHeight + 6
                        anchors.verticalCenter: parent.verticalCenter
                        color: {
                            if (!popupFechamentoRapido.comandaAtual)
                                return "transparent";
                            var tipo = popupFechamentoRapido.comandaAtual.tipo;
                            return tipo === "Entrega" ? "#0284c7" : (tipo === "Mesa" ? "#0d9488" : "#d97706");
                        }

                        Text {
                            id: textoTipo

                            text: popupFechamentoRapido.comandaAtual ? popupFechamentoRapido.comandaAtual.tipo : ""
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 11
                            anchors.centerIn: parent
                        }
                    }

                    Text {
                        text: popupFechamentoRapido.comandaAtual ? popupFechamentoRapido.comandaAtual.codigo : ""
                        visible: text !== ""
                        font.pixelSize: 12
                        font.family: "monospace"
                        color: Estilo.cores.textoSecundario
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Button {
                id: btnProxima

                visible: popupFechamentoRapido.modoFila
                enabled: popupFechamentoRapido.indice < popupFechamentoRapido.comandas.length - 1
                implicitWidth: 34
                implicitHeight: 34
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                onClicked: popupFechamentoRapido.indice++

                contentItem: Text {
                    text: "›"
                    font.pixelSize: 20
                    font.bold: true
                    color: btnProxima.enabled ? Estilo.cores.texto : Estilo.cores.borda
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.cheio
                    color: btnProxima.down ? "#e5e7eb" : (btnProxima.hovered ? "#f1f5f9" : "transparent")
                    border.color: btnProxima.enabled ? Estilo.cores.borda : "transparent"
                    border.width: 1
                }
            }
        }

        // --- VALOR EM DESTAQUE ---
        // É o número que decide a baixa; ele está no meio do cupom abaixo,
        // mas ficar caçando a linha "Valor do pedido:" a cada comanda da
        // fila é justamente o que este popup existe pra evitar.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 54
            radius: Estilo.rounding.medio
            color: "#f0fdf4"
            border.color: "#bbf7d0"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Estilo.preenchimento.grande
                anchors.rightMargin: Estilo.preenchimento.grande
                spacing: Estilo.espacamento.normal

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (!popupFechamentoRapido.comandaAtual)
                            return "";
                        var cliente = popupFechamentoRapido.comandaAtual.cliente;
                        return cliente && cliente.trim() !== "" ? cliente.trim() : "Cliente não informado";
                    }
                    font.pixelSize: Estilo.fonte.padrao
                    font.bold: true
                    color: Estilo.cores.texto
                    elide: Text.ElideRight
                }

                Text {
                    text: popupFechamentoRapido.comandaAtual ? popupFechamentoRapido.comandaAtual.dataHora : ""
                    font.pixelSize: 12
                    color: Estilo.cores.textoSecundario
                }

                // Agora que comandas já baixadas também chegam aqui (pela
                // lista do dia, não só pela fila de abertas), o popup precisa
                // dizer em qual das duas situações esta está — é o que decide
                // se aparece o botão Baixa e se a correção vai perguntar
                // sobre a conferência.
                Rectangle {
                    visible: popupFechamentoRapido.comandaAtual !== null
                    implicitWidth: textoConferida.implicitWidth + 16
                    implicitHeight: textoConferida.implicitHeight + 6
                    radius: Estilo.rounding.cheio
                    color: popupFechamentoRapido.comandaAtual && popupFechamentoRapido.comandaAtual.fechada ? Estilo.confirmar.normal : "#b45309"

                    Text {
                        id: textoConferida

                        anchors.centerIn: parent
                        text: popupFechamentoRapido.comandaAtual && popupFechamentoRapido.comandaAtual.fechada ? "CONFERIDA" : "EM ABERTO"
                        font.pixelSize: 11
                        font.bold: true
                        color: "#ffffff"
                    }
                }

                Text {
                    text: popupFechamentoRapido.comandaAtual
                        ? "R$ " + popupFechamentoRapido.comandaAtual.valor.toFixed(2).replace(".", ",")
                        : ""
                    font.pixelSize: 22
                    font.bold: true
                    color: "#16a34a"
                }
            }
        }

        // --- A COMANDA ---
        // Exibida na mesma linguagem visual da pré-comanda de Balcão/Entrega
        // (components/ResumoComanda.qml), e não como o cupom da impressora:
        // conferir uma comanda não deveria exigir ler ESC/POS formatado em
        // colunas na tela. A diferença pra pré-comanda é que aqui nada fica
        // de fora — dados do cliente, frações de pizza meio a meio,
        // adicionais por sabor, borda e observações aparecem todos.
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: popupFechamentoRapido.temDetalhe
            clip: true
            contentWidth: width
            contentHeight: resumoDetalhado.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            ResumoComanda {
                id: resumoDetalhado

                width: parent.width
                detalhado: true
                itens: modeloItens
                corDestaque: {
                    if (!popupFechamentoRapido.comandaAtual)
                        return Estilo.confirmar.normal;

                    var tipo = popupFechamentoRapido.comandaAtual.tipo;
                    return tipo === "Entrega" ? "#e67e22" : (tipo === "Mesa" ? "#0d9488" : Estilo.confirmar.normal);
                }
                cliente: popupFechamentoRapido.detalhe.cliente || ""
                telefone: popupFechamentoRapido.detalhe.telefone || ""
                endereco: popupFechamentoRapido.detalhe.endereco || ""
                bairro: popupFechamentoRapido.detalhe.bairro || ""
                observacaoGeral: popupFechamentoRapido.detalhe.observacaoGeral || ""
                formaPagamento: popupFechamentoRapido.detalhe.formaPagamento || ""
                troco: popupFechamentoRapido.detalhe.troco || ""
                pago: popupFechamentoRapido.detalhe.statusPagamento === "PG"
                taxaEntrega: popupFechamentoRapido.detalhe.taxaEntrega || ""
                mostrarTaxaEntrega: popupFechamentoRapido.comandaAtual !== null && popupFechamentoRapido.comandaAtual.tipo === "Entrega"
            }
        }

        // --- CUPOM INTEIRO (reserva) ---
        // Só quando não há o que estruturar: comanda de Mesa, que traz a
        // divisão da conta e não volta pra um formulário (mesma razão de o
        // botão Editar não aparecer pra ela), ou reconstrução que voltou
        // vazia. Fonte monoespaçada e sem quebra automática, para as colunas
        // com "|" ficarem alinhadas como saem na impressora — mesmo
        // tratamento de qml/pages/consulta/PainelDetalhe.qml.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !popupFechamentoRapido.temDetalhe
            radius: Estilo.rounding.medio
            color: "#ffffff"
            border.color: Estilo.cores.bordaCard

            Flickable {
                anchors.fill: parent
                anchors.margins: Estilo.preenchimento.normal
                clip: true
                contentWidth: Math.max(width, textoCupom.implicitWidth)
                contentHeight: Math.max(height, textoCupom.implicitHeight)
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                ScrollBar.horizontal: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                Text {
                    id: textoCupom

                    text: popupFechamentoRapido.comandaAtual ? popupFechamentoRapido.comandaAtual.conteudo : ""
                    font.family: "monospace"
                    font.pixelSize: 13
                    color: "#34495e"
                    wrapMode: Text.NoWrap
                }
            }
        }

        // --- ESCOLHA DA BAIXA AO CORRIGIR UMA COMANDA JÁ CONFERIDA ---
        // Corrigir é apagar e gravar de novo, e a comanda nova nasce sem
        // baixa (ver services/rede/baixaComandas.py) — ou seja, some do caixa
        // do dia até alguém reconferir. Isso é o certo quando a baixa foi
        // dada por engano, e é justamente o errado quando a correção é só um
        // valor digitado torto. Como as duas intenções são indistinguíveis
        // daqui, quem decide é quem está corrigindo.
        //
        // Faixa dentro do próprio popup, e não um popup em cima do popup:
        // são duas escolhas curtas, e empilhar modal sobre modal só
        // acrescentaria uma camada pra fechar.
        Rectangle {
            Layout.fillWidth: true
            visible: popupFechamentoRapido.escolhendoBaixa
            implicitHeight: colunaEscolhaBaixa.implicitHeight + Estilo.preenchimento.grande * 2
            radius: Estilo.rounding.medio
            color: Estilo.cores.avisoFundo
            border.color: Estilo.cores.avisoBorda
            border.width: 1

            Column {
                id: colunaEscolhaBaixa

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Estilo.preenchimento.grande
                anchors.rightMargin: Estilo.preenchimento.grande
                spacing: Estilo.espacamento.menor

                Text {
                    width: parent.width
                    text: "Esta comanda já foi conferida e conta no caixa do dia. A comanda corrigida é gravada como uma comanda nova — o que fazer com a conferência?"
                    font.pixelSize: 13
                    color: Estilo.cores.avisoTexto
                    wrapMode: Text.WordWrap
                }

                Row {
                    spacing: Estilo.espacamento.normal

                    Button {
                        id: btnManterConferida

                        padding: 8
                        onClicked: popupFechamentoRapido._abrirEdicao(true)

                        contentItem: Text {
                            text: "Manter conferida"
                            font.bold: true
                            color: "#ffffff"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.padrao
                            color: btnManterConferida.down ? Estilo.confirmar.pressionado : (btnManterConferida.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                        }
                    }

                    Button {
                        id: btnReconferirDepois

                        padding: 8
                        onClicked: popupFechamentoRapido._abrirEdicao(false)

                        contentItem: Text {
                            text: "Reconferir depois"
                            font.bold: true
                            color: Estilo.cores.avisoTexto
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.padrao
                            color: btnReconferirDepois.down ? "#fde68a" : (btnReconferirDepois.hovered ? "#fef9c3" : "transparent")
                            border.color: Estilo.cores.avisoBorda
                            border.width: 1
                        }
                    }

                    Button {
                        id: btnCancelarEscolha

                        padding: 8
                        onClicked: popupFechamentoRapido.escolhendoBaixa = false

                        contentItem: Text {
                            text: "Cancelar"
                            color: Estilo.cores.textoSecundario
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.padrao
                            color: btnCancelarEscolha.hovered ? "#f1f5f9" : "transparent"
                        }
                    }
                }
            }
        }

        // Editar grava a comanda de novo com a data de AGORA, então corrigir
        // uma comanda de ontem a mudaria de dia — tiraria do caixa de ontem e
        // somaria no de hoje. Em vez de deixar isso acontecer em silêncio, a
        // correção fica presa ao dia corrente e o motivo aparece na tela.
        Text {
            Layout.fillWidth: true
            visible: !popupFechamentoRapido.ehHoje
            text: "Só dá para corrigir comandas do dia de hoje: a comanda corrigida é gravada de novo com a data de agora, e sairia do caixa deste dia."
            font.pixelSize: 12
            color: Estilo.cores.avisoTexto
            wrapMode: Text.WordWrap
        }

        // --- AÇÕES ---
        RowLayout {
            Layout.fillWidth: true
            spacing: Estilo.espacamento.normal

            Button {
                id: btnBaixa

                padding: 10
                // Comanda já conferida não tem baixa a dar.
                visible: popupFechamentoRapido.comandaAtual !== null && !popupFechamentoRapido.comandaAtual.fechada
                onClicked: popupFechamentoRapido.darBaixaAtual()

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    Icone {
                        nome: "fa6s.check"
                        cor: "#ffffff"
                        tamanho: Estilo.fonte.padrao
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Baixa"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: btnBaixa.down ? Estilo.confirmar.pressionado : (btnBaixa.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                    border.color: Estilo.confirmar.pressionado
                    border.width: 1
                }
            }

            Button {
                id: btnEditar

                padding: 10
                // Comanda de Mesa não reabre num formulário: a divisão da
                // conta já impressa não volta pra Balcao.qml/Entrega.qml —
                // mesma regra de ItemComandaDelegate.qml na Consulta.
                visible: popupFechamentoRapido.comandaAtual !== null && popupFechamentoRapido.comandaAtual.tipo !== "Mesa"
                enabled: popupFechamentoRapido.ehHoje
                onClicked: popupFechamentoRapido.editarAtual()

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    Icone {
                        nome: "fa6s.pen"
                        cor: btnEditar.enabled ? "#ffffff" : Estilo.cores.textoSecundario
                        tamanho: Estilo.fonte.padrao
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Editar"
                        font.bold: true
                        color: btnEditar.enabled ? "#ffffff" : Estilo.cores.textoSecundario
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: {
                        if (!btnEditar.enabled)
                            return Estilo.cores.borda;

                        return btnEditar.down ? "#6d28d9" : (btnEditar.hovered ? "#8b5cf6" : "#7c3aed");
                    }
                }
            }

            Button {
                id: btnReimprimir

                padding: 10
                // Sem restrição de dia, ao contrário de Editar: reimprimir
                // reenvia o .txt como está, sem gravar nem alterar nada.
                visible: popupFechamentoRapido.comandaAtual !== null
                onClicked: popupFechamentoRapido.reimprimirAtual()

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    Icone {
                        nome: "fa6s.print"
                        cor: Estilo.cores.texto
                        tamanho: Estilo.fonte.padrao
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Reimprimir"
                        font.bold: true
                        color: Estilo.cores.texto
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: btnReimprimir.down ? "#e5e7eb" : (btnReimprimir.hovered ? "#f1f5f9" : "transparent")
                    border.color: Estilo.cores.borda
                    border.width: 1
                }
            }

            Button {
                id: btnExcluir

                padding: 10
                visible: popupFechamentoRapido.comandaAtual !== null
                onClicked: popupFechamentoRapido.excluirAtual()

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent
                    Icone {
                        nome: "fa6s.trash-can"
                        cor: "#ffffff"
                        tamanho: Estilo.fonte.padrao
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Excluir"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: btnExcluir.down ? Estilo.cancelar.pressionado : (btnExcluir.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                    border.color: Estilo.cancelar.pressionado
                    border.width: 1
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Button {
                id: btnSair

                padding: 10
                onClicked: popupFechamentoRapido.close()

                contentItem: Text {
                    text: "Sair"
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: btnSair.down ? "#6b7280" : (btnSair.hovered ? "#95a5a6" : Estilo.cores.textoSecundario)
                }
            }
        }
    }
}
