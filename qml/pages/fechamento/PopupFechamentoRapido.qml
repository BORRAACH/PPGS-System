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
//   chega com fechada=true, então "Baixa" fica oculto e "Editar" abre o popup
//   de manter/reconferir a baixa (PopupManterBaixa.qml, ver editarAtual()).
// - abrirComanda(arquivo, iso) — UMA comanda específica, clicada na lista do
//   dia em Fechamento.qml. Aqui entram também as que já receberam baixa, que
//   por definição não aparecem na fila de abertas — e são justamente elas
//   que costumam precisar de correção (uma comanda suspeita só é listada
//   como suspeita depois de baixada).
Popup {
    id: popupFechamentoRapido

    // Nomeado como os outros popups desta tela — deixa a fila alcançável de
    // fora para inspeção e teste.
    objectName: "popupFechamentoRapido"

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

    // Verdadeira quando quem abriu esta fila já pediu o código do usuário na
    // porta — hoje só o botão "Editar caixa" de Fechamento.qml faz isso (ver
    // abrirEditarCaixa). Nesse caso o "Editar" de cada comanda não pergunta de
    // novo: seria o mesmo código, digitado três vezes para corrigir três
    // comandas da mesma fila.
    //
    // Nos outros dois caminhos até aqui — "Fechamento rápido" e o clique numa
    // comanda da lista do dia — não houve porta nenhuma antes, então continua
    // valendo pedir por comanda. É por isso que isto é uma propriedade e não
    // uma decisão fixa: o guarda pertence à ENTRADA do fluxo, e as três
    // entradas são diferentes.
    property bool jaAutorizado: false

    function abrirPara(iso) {
        popupFechamentoRapido.dataIso = iso;
        popupFechamentoRapido.comandas = fechamentoController.listarComandasAbertas(iso);
        popupFechamentoRapido.indice = 0;
        popupFechamentoRapido.jaAutorizado = false;
        if (popupFechamentoRapido.comandas.length === 0)
            return false;

        open();
        return true;
    }

    function abrirParaFechadas(iso) {
        popupFechamentoRapido.dataIso = iso;
        popupFechamentoRapido.comandas = fechamentoController.listarComandasFechadas(iso);
        popupFechamentoRapido.indice = 0;
        // Só o botão "Editar caixa" chama isto, e ele já pediu o código.
        popupFechamentoRapido.jaAutorizado = true;
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
        popupFechamentoRapido.jaAutorizado = false;
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

    function editarAtual() {
        var comanda = popupFechamentoRapido.comandaAtual;
        if (!comanda)
            return;

        // Editar é apagar a comanda antiga e gravar uma nova (ver
        // components/EdicaoComanda.js): destrutivo, esteja a comanda conferida
        // ou ainda aberta. Por isso o código vale para os dois casos — um
        // botão "Editar" que às vezes pede e às vezes não seria impossível de
        // prever no balcão.
        //
        // A exceção é a fila que já entrou autorizada na porta (ver
        // jaAutorizado, lá em cima): aí o código já foi dado uma vez e vale
        // para esta fila inteira.
        if (popupFechamentoRapido.jaAutorizado) {
            popupFechamentoRapido._seguirParaEdicao(comanda);
            return;
        }

        var rotulo = comanda.fechada ? "Editar comanda fechada" : "Editar comanda";
        popupAutorizacao.solicitar(rotulo, comanda.arquivo, function () {
            popupFechamentoRapido._seguirParaEdicao(comanda);
        });
    }

    // O que acontece depois de a edição estar liberada, venha a liberação da
    // porta ou do código pedido agora.
    function _seguirParaEdicao(comanda) {
        // Comanda ainda em aberto não tem baixa pra decidir — segue direto
        // pro formulário.
        if (!comanda.fechada) {
            popupFechamentoRapido._abrirEdicao(false);
            return;
        }

        popupManterBaixa.open();
    }

    function _abrirEdicao(manterBaixa) {
        var comanda = popupFechamentoRapido.comandaAtual;
        if (!comanda)
            return;

        // Fecha antes de empurrar o formulário: a edição sai da página de
        // Fechamento (é o mesmo caminho que a Consulta usa — ver
        // components/EdicaoComanda.js), e deixar o popup aberto por baixo
        // faria ele reaparecer sobre o formulário de Balcão/Entrega.
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

    // Guarda da edição de comanda fechada (ver editarAtual). A exclusão daqui
    // já é guardada dentro do próprio PopupConfirmarExclusao acima.
    PopupAutorizacao {
        id: popupAutorizacao
    }

    // O que fazer com a conferência ao corrigir uma comanda já baixada —
    // aberto por editarAtual() depois que o código do usuário passa.
    PopupManterBaixa {
        id: popupManterBaixa

        onEscolhido: function (manterBaixa) {
            popupFechamentoRapido._abrirEdicao(manterBaixa);
        }
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
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    // Dá foco de teclado ao conteúdo assim que o popup abre — sem isso, as
    // setas ‹ › e o F10 (ver Keys.onPressed em colunaConteudo) só
    // funcionariam depois de um clique qualquer dentro do popup.
    onOpened: colunaConteudo.forceActiveFocus()

    width: Math.min(760, parent ? parent.width * 0.9 : 760)
    height: Math.min(720, parent ? parent.height * 0.9 : 720)

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    contentItem: ColumnLayout {
        id: colunaConteudo

        spacing: Estilo.global.spacing.xl
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
                    font.pixelSize: Estilo.global.fontSize.xxl
                    font.family: Estilo.global.fontFamily.title
                    color: btnAnterior.enabled ? Estilo.global.text : Estilo.global.border
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnAnterior.down ? Estilo.action.ghost.pressed : (btnAnterior.hovered ? Estilo.action.ghost.hover : Estilo.action.ghost.base)
                    border.color: btnAnterior.enabled ? Estilo.global.border : "transparent"
                    border.width: Estilo.global.borderWidth.hairline
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
                    font.pixelSize: Estilo.global.fontSize.xl
                    font.bold: true
                    color: Estilo.global.text
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Estilo.global.spacing.sm

                    Rectangle {
                        radius: Estilo.global.radius.sm
                        width: textoTipo.implicitWidth + 14
                        height: textoTipo.implicitHeight + 6
                        anchors.verticalCenter: parent.verticalCenter
                        color: {
                            if (!popupFechamentoRapido.comandaAtual)
                                return "transparent";
                            var tipo = popupFechamentoRapido.comandaAtual.tipo;
                            return tipo === "Entrega" ? Estilo.orderType.entrega.base : (tipo === "Mesa" ? Estilo.orderType.mesa.base : Estilo.orderType.balcao.base);
                        }

                        Text {
                            id: textoTipo

                            text: popupFechamentoRapido.comandaAtual ? popupFechamentoRapido.comandaAtual.tipo : ""
                            color: Estilo.global.textOnAccent
                            font.bold: true
                            font.pixelSize: Estilo.global.fontSize.xs
                            anchors.centerIn: parent
                        }
                    }

                    Text {
                        text: popupFechamentoRapido.comandaAtual ? popupFechamentoRapido.comandaAtual.codigo : ""
                        visible: text !== ""
                        font.pixelSize: Estilo.global.fontSize.sm
                        font.family: "monospace"
                        color: Estilo.global.textSecondary
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
                    font.pixelSize: Estilo.global.fontSize.xxl
                    font.family: Estilo.global.fontFamily.title
                    color: btnProxima.enabled ? Estilo.global.text : Estilo.global.border
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnProxima.down ? Estilo.action.ghost.pressed : (btnProxima.hovered ? Estilo.action.ghost.hover : Estilo.action.ghost.base)
                    border.color: btnProxima.enabled ? Estilo.global.border : "transparent"
                    border.width: Estilo.global.borderWidth.hairline
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
            radius: Estilo.global.radius.lg
            color: Estilo.status.success.background
            border.color: Estilo.status.success.border

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Estilo.global.padding.xl
                anchors.rightMargin: Estilo.global.padding.xl
                spacing: Estilo.global.spacing.lg

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (!popupFechamentoRapido.comandaAtual)
                            return "";
                        var cliente = popupFechamentoRapido.comandaAtual.cliente;
                        return cliente && cliente.trim() !== "" ? cliente.trim() : "Cliente não informado";
                    }
                    font.pixelSize: Estilo.global.fontSize.lg
                    font.bold: true
                    color: Estilo.global.text
                    elide: Text.ElideRight
                }

                Text {
                    text: popupFechamentoRapido.comandaAtual ? popupFechamentoRapido.comandaAtual.dataHora : ""
                    font.pixelSize: Estilo.global.fontSize.sm
                    color: Estilo.global.textSecondary
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
                    radius: Estilo.global.radius.pill
                    color: popupFechamentoRapido.comandaAtual && popupFechamentoRapido.comandaAtual.fechada ? Estilo.action.confirm.base : Estilo.finance.outflow

                    Text {
                        id: textoConferida

                        anchors.centerIn: parent
                        text: popupFechamentoRapido.comandaAtual && popupFechamentoRapido.comandaAtual.fechada ? "CONFERIDA" : "EM ABERTO"
                        font.pixelSize: Estilo.global.fontSize.xs
                        font.bold: true
                        color: Estilo.global.textOnAccent
                    }
                }

                Text {
                    text: popupFechamentoRapido.comandaAtual
                        ? "R$ " + popupFechamentoRapido.comandaAtual.valor.toFixed(2).replace(".", ",")
                        : ""
                    font.pixelSize: Estilo.global.fontSize.title
                    font.bold: true
                    color: Estilo.finance.positive
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
                        return Estilo.action.confirm.base;

                    var tipo = popupFechamentoRapido.comandaAtual.tipo;
                    return tipo === "Entrega" ? Estilo.orderType.entrega.base : (tipo === "Mesa" ? Estilo.orderType.mesa.base : Estilo.orderType.balcao.base);
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
            radius: Estilo.global.radius.lg
            color: Estilo.global.surface
            border.color: Estilo.global.borderCard

            Flickable {
                anchors.fill: parent
                anchors.margins: Estilo.global.padding.md
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
                    font.pixelSize: Estilo.global.fontSize.md
                    color: Estilo.printer.ink
                    wrapMode: Text.NoWrap
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
            font.pixelSize: Estilo.global.fontSize.sm
            color: Estilo.status.warning.content
            wrapMode: Text.WordWrap
        }

        // --- AÇÕES ---
        RowLayout {
            Layout.fillWidth: true
            spacing: Estilo.global.spacing.lg

            Button {
                id: btnBaixa

                padding: Estilo.global.padding.md
                // Comanda já conferida não tem baixa a dar.
                visible: popupFechamentoRapido.comandaAtual !== null && !popupFechamentoRapido.comandaAtual.fechada
                onClicked: popupFechamentoRapido.darBaixaAtual()

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent
                    Icone {
                        nome: "fa6s.check"
                        cor: Estilo.global.textOnAccent
                        tamanho: Estilo.global.fontSize.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Baixa"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnBaixa.down ? Estilo.action.confirm.pressed : (btnBaixa.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                    border.color: Estilo.action.confirm.pressed
                    border.width: Estilo.global.borderWidth.hairline
                }
            }

            Button {
                id: btnEditar

                padding: Estilo.global.padding.md
                // Comanda de Mesa não reabre num formulário: a divisão da
                // conta já impressa não volta pra Balcao.qml/Entrega.qml —
                // mesma regra de ItemComandaDelegate.qml na Consulta.
                visible: popupFechamentoRapido.comandaAtual !== null && popupFechamentoRapido.comandaAtual.tipo !== "Mesa"
                enabled: popupFechamentoRapido.ehHoje
                onClicked: popupFechamentoRapido.editarAtual()

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent
                    Icone {
                        nome: "fa6s.pen"
                        cor: btnEditar.enabled ? Estilo.global.textOnAccent : Estilo.global.textSecondary
                        tamanho: Estilo.global.fontSize.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Editar"
                        font.family: Estilo.global.fontFamily.title
                        color: btnEditar.enabled ? Estilo.global.textOnAccent : Estilo.global.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: {
                        if (!btnEditar.enabled)
                            return Estilo.global.border;

                        return btnEditar.down ? Estilo.action.review.pressed : (btnEditar.hovered ? Estilo.action.review.hover : Estilo.action.review.base);
                    }
                }
            }

            Button {
                id: btnReimprimir

                padding: Estilo.global.padding.md
                // Sem restrição de dia, ao contrário de Editar: reimprimir
                // reenvia o .txt como está, sem gravar nem alterar nada.
                visible: popupFechamentoRapido.comandaAtual !== null
                onClicked: popupFechamentoRapido.reimprimirAtual()

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent
                    Icone {
                        nome: "fa6s.print"
                        cor: Estilo.global.text
                        tamanho: Estilo.global.fontSize.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Reimprimir"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnReimprimir.down ? Estilo.action.ghost.pressed : (btnReimprimir.hovered ? Estilo.action.ghost.hover : Estilo.action.ghost.base)
                    border.color: Estilo.global.border
                    border.width: Estilo.global.borderWidth.hairline
                }
            }

            Button {
                id: btnExcluir

                padding: Estilo.global.padding.md
                visible: popupFechamentoRapido.comandaAtual !== null
                onClicked: popupFechamentoRapido.excluirAtual()

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent
                    Icone {
                        nome: "fa6s.trash-can"
                        cor: Estilo.global.textOnAccent
                        tamanho: Estilo.global.fontSize.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Excluir"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnExcluir.down ? Estilo.action.danger.pressed : (btnExcluir.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                    border.color: Estilo.action.danger.pressed
                    border.width: Estilo.global.borderWidth.hairline
                }
            }

            Item {
                Layout.fillWidth: true
            }

            Button {
                id: btnSair

                padding: Estilo.global.padding.md
                onClicked: popupFechamentoRapido.close()

                contentItem: Text {
                    text: "Sair"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnSair.down ? Estilo.action.neutral.pressed : (btnSair.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                }
            }
        }
    }
}
