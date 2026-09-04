import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../components"

// Um item da lista de comandas em ColunaEsquerda.qml: mostra o resumo
// (tipo + cliente/hora) e abre, no botão DIREITO, um menu com Editar,
// Reimprimir e Excluir para aquela comanda.
//
// Antes o botão direito ligava um "modo de edição" que fazia aparecer um lápis
// e uma lixeira em TODAS as linhas ao mesmo tempo. Duas coisas de errado nisso:
// os botões apareciam em comandas que ninguém ia mexer (e a lixeira encostada
// no item errado é um clique de distância do arrependimento), e não havia lugar
// para uma terceira ação sem espremer mais um ícone de 32px na linha. O menu
// pertence à comanda em que se clicou, e cresce sem apertar nada.
//
// Comanda já fechada não mostra Editar nem Excluir: uma vez baixada ela já
// conta no caixa do dia, e nem esta tela nem a de Fechamento corrigem o que
// já foi fechado — quando o lançamento está errado mesmo, o caminho é apagar
// pela tela de Fechamento (PopupFechamentoRapido.qml), que registra a
// exclusão no histórico do dia. Reimprimir aparece sempre: não grava nada.
Rectangle {
    id: itemComanda

    // Referência à página Consulta.qml, para ler/gravar o estado
    // compartilhado (seleção atual) e chamar editarComanda/tituloComanda.
    property var pagina
    property var popupExclusao
    // Instância única, compartilhada por todas as linhas (ver ColunaEsquerda):
    // um popup por item seria um popup por comanda do dia.
    property var popupCopias
    property bool selecionado: pagina ? model.arquivo === pagina.arquivoSelecionado : false

    // Comanda sobre a qual as máquinas da rede discordam (ver
    // services/rede/indicePedidos.py). O amarelo vence o estado de seleção
    // e o de hover: é a informação mais importante do item — enquanto o
    // conflito não for resolvido, o valor do caixa do dia pode estar
    // diferente em cada máquina.
    readonly property bool emConflito: model.emConflito === true

    // Provável erro de digitação no pedido (ver
    // comandaParserService.eh_suspeita) — só um aviso visual, não impede
    // nada; emConflito continua tendo prioridade porque ali o próprio valor
    // do caixa pode estar divergindo entre máquinas.
    readonly property bool suspeita: model.suspeita === true

    width: ListView.view.width - (ListView.view.ScrollBar.vertical.visible ? ListView.view.ScrollBar.vertical.width : 0)
    height: colunaItem.implicitHeight + 20
    radius: Estilo.global.radius.md
    color: emConflito
        ? Estilo.status.warning.background
        : (selecionado ? Estilo.screen.consulta.soft : (mouseAreaItem.containsMouse ? Estilo.global.surfaceHover : Estilo.global.surface))
    border.color: emConflito
        ? Estilo.status.warning.border
        : (suspeita ? Estilo.status.error.content : (selecionado ? Estilo.screen.consulta.base : Estilo.global.borderCard))
    border.width: (emConflito || selecionado || suspeita) ? 2 : 1

    MouseArea {
        id: mouseAreaItem

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
                // Seleciona ANTES de abrir o menu: o painel de detalhe ao lado
                // passa a mostrar a comanda em que se clicou, e é ele que
                // confirma que o menu vai agir sobre a comanda certa.
                pagina.selecionarComanda(model);
                menuComanda.popup();
                return;
            }
            pagina.selecionarComanda(model);
        }
    }

    // --- MENU DO BOTÃO DIREITO ---
    // Aberto sobre o cursor (popup() sem argumentos), não ancorado ao item: a
    // lista rola, e um menu preso à linha ficaria fora de lugar assim que ela
    // se mexesse.
    //
    // Estilizado por inteiro (fundo, itens, separador) porque o Menu padrão do
    // Qt Quick Controls não segue nada do app: canto reto, fonte do sistema e
    // as cores da palette herdada — a mesma herança do tema do sistema que já
    // tinha deixado os campos brancos no Windows (ver o delegate do ComboBox em
    // components/CamposPagamento.qml).
    //
    // Os ícones vêm do componente Icone, e não de `icon.name`: neste app eles
    // são desenhados por services/iconProvider.py e chegam por
    // "image://qtaicon/<nome>" — `icon.name` procura no tema de ícones do
    // sistema, que na máquina da pizzaria não tem nenhum deles.
    Menu {
        id: menuComanda

        // Copiados na abertura do menu, não lidos de `model` nos handlers: o
        // menu vive além do clique, e `model` dentro de um delegate deixa de
        // valer se a lista se recarregar (uma comanda nova chegando pela malha)
        // enquanto ele está aberto — os itens agiriam sobre a linha que tomou
        // o lugar desta.
        property string arquivoAlvo: ""
        property string tituloAlvo: ""
        property bool alvoFechada: false
        property bool alvoMesa: false

        // Uma ação do menu: ícone à esquerda, rótulo, e a cor que diz o que ela
        // faz. Inline component porque as três são a MESMA coisa com outro
        // texto — repetir o contentItem/background três vezes era como as três
        // acabariam divergindo na próxima mexida.
        component AcaoDoMenu: MenuItem {
            id: acao

            property string icone: ""
            property color corTexto: Estilo.global.text

            // Um item escondido não pode ocupar altura: sem isto, a comanda
            // fechada abria um menu com dois buracos onde estariam Editar e
            // Excluir.
            height: visible ? implicitHeight : 0
            implicitHeight: 40
            implicitWidth: Math.max(180, conteudoAcao.implicitWidth + Estilo.global.padding.lg * 2)

            contentItem: Row {
                id: conteudoAcao

                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Estilo.global.padding.lg
                spacing: Estilo.global.spacing.sm

                Icone {
                    nome: acao.icone
                    cor: acao.corTexto
                    tamanho: Estilo.global.fontSize.lg
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: acao.text
                    font.pixelSize: Estilo.global.fontSize.md
                    font.family: Estilo.global.fontFamily.title
                    color: acao.corTexto
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            background: Rectangle {
                anchors.fill: parent
                anchors.margins: Estilo.global.spacing.xs
                radius: Estilo.global.radius.md
                color: acao.down
                    ? Estilo.global.surfacePressed
                    : (acao.hovered ? Estilo.global.surfaceHover : "transparent")
            }
        }

        // Mesmo raio dos painéis, e não o dos popups: um menu é menor e o raio
        // de popup (20) o deixaria com cara de balão.
        background: Rectangle {
            implicitWidth: 180
            radius: Estilo.global.radius.lg
            color: Estilo.global.background
            border.color: Estilo.global.borderCard
            border.width: Estilo.global.borderWidth.hairline
        }

        onAboutToShow: {
            menuComanda.arquivoAlvo = model.arquivo;
            menuComanda.tituloAlvo = itemComanda.pagina.tituloComanda(model);
            menuComanda.alvoFechada = model.fechada === true;
            menuComanda.alvoMesa = model.tipo === "Mesa";
        }

        AcaoDoMenu {
            // Comanda de Mesa já fechada (com a divisão da conta já impressa)
            // não tem como reabrir num formulário estruturado — ver o guard
            // equivalente em Consulta.qml:editarComanda().
            visible: !menuComanda.alvoMesa && !menuComanda.alvoFechada
            text: "Editar"
            icone: "fa6s.pen"
            corTexto: Estilo.global.text
            onTriggered: itemComanda.pagina.editarComanda(menuComanda.arquivoAlvo)
        }

        AcaoDoMenu {
            // Sempre disponível, inclusive em comanda fechada: reimprimir não
            // grava nada — nem arquivo, nem código sequencial, nem evento na
            // malha (ver FechamentoController.reimprimirComanda).
            text: "Reimprimir…"
            icone: "fa6s.print"
            corTexto: Estilo.global.text
            onTriggered: {
                var arquivo = menuComanda.arquivoAlvo;
                itemComanda.popupCopias.abrirPara(menuComanda.tituloAlvo, function (copias) {
                    fechamentoController.reimprimirComanda(arquivo, copias);
                });
            }
        }

        MenuSeparator {
            visible: !menuComanda.alvoFechada
            height: visible ? implicitHeight : 0
            padding: 0
            topPadding: Estilo.global.spacing.xs
            bottomPadding: Estilo.global.spacing.xs

            contentItem: Rectangle {
                implicitHeight: Estilo.global.borderWidth.hairline
                color: Estilo.global.borderCard
            }
        }

        AcaoDoMenu {
            // Vermelha, como a lixeira que ela substituiu: é a única aqui que
            // não tem desfazer, e a cor é o que separa "mexer" de "perder".
            // Mesma restrição do Editar — comanda já fechada só se corrige pelo
            // Fechamento, nunca apaga direto pela Consulta.
            visible: !menuComanda.alvoFechada
            text: "Excluir"
            icone: "fa6s.trash-can"
            corTexto: Estilo.action.danger.base
            onTriggered: itemComanda.popupExclusao.abrirPara(menuComanda.arquivoAlvo, menuComanda.tituloAlvo)
        }
    }

    Column {
        id: colunaItem

        x: 10
        y: 10
        width: parent.width - 20
        spacing: 4

        Row {
            spacing: Estilo.global.spacing.sm

            Rectangle {
                radius: Estilo.global.radius.sm
                width: textoBadgeItem.implicitWidth + 14
                height: textoBadgeItem.implicitHeight + 6
                color: model.tipo === "Entrega" ? Estilo.orderType.entrega.base : (model.tipo === "Mesa" ? Estilo.orderType.mesa.base : Estilo.orderType.balcao.base)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    id: textoBadgeItem

                    text: model.tipo
                    color: Estilo.global.textOnAccent
                    font.bold: true
                    font.pixelSize: Estilo.global.fontSize.xs
                    anchors.centerIn: parent
                }
            }

            // Aberta = ainda sem baixa, fora do caixa do dia; fechada = já
            // conferida no fechamento rápido (ver
            // services/rede/baixaComandas.py). Verde só na fechada: é o
            // estado "resolvido", e o cinza deixa a aberta parecer o que ela
            // é — pendente, sem ser um alerta.
            Rectangle {
                radius: Estilo.global.radius.sm
                width: textoBadgeStatus.implicitWidth + 14
                height: textoBadgeStatus.implicitHeight + 6
                color: model.fechada ? Estilo.action.confirm.base : Estilo.global.textSecondary
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    id: textoBadgeStatus

                    text: model.fechada ? "Fechada" : "Aberta"
                    color: Estilo.global.textOnAccent
                    font.bold: true
                    font.pixelSize: Estilo.global.fontSize.xs
                    anchors.centerIn: parent
                }
            }

            // Código impresso no cabeçalho da comanda (o mesmo que está no
            // papel) + máquina onde ela foi lançada. É o que permite
            // conferir uma comanda entre duas máquinas sem depender de
            // nomes de arquivo: o código é idêntico nas duas.
            Text {
                text: model.maquinaOrigem
                    ? model.codigo + " · " + model.maquinaOrigem
                    : model.codigo
                visible: model.codigo !== ""
                font.pixelSize: Estilo.global.fontSize.xs
                font.family: "monospace"
                color: itemComanda.emConflito ? Estilo.status.warning.content : Estilo.global.textSecondary
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }

            Icone {
                nome: "fa6s.triangle-exclamation"
                cor: Estilo.status.warning.border
                tamanho: 12
                visible: itemComanda.emConflito
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: pagina.tituloComanda(model)
            font.pixelSize: Estilo.global.fontSize.sm
            font.bold: true
            color: Estilo.global.text
            elide: Text.ElideRight
            width: colunaItem.width
        }
    }
}
