import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../components"

// Um item da lista de comandas em ColunaEsquerda.qml: mostra o resumo
// (tipo + cliente/hora), serve de atalho no botão direito para o botão
// "Editar" ao lado da barra de pesquisa e, no modo de edição, os botões de
// editar/apagar rápidos.
Rectangle {
    id: itemComanda

    // Referência à página Consulta.qml, para ler/gravar o estado
    // compartilhado (seleção atual) e chamar editarComanda/tituloComanda.
    property var pagina
    property var popupExclusao
    property bool modoEdicao: false
    property bool selecionado: pagina ? model.arquivo === pagina.arquivoSelecionado : false

    // Emitido no clique com o botão direito — ColunaEsquerda.qml conecta a
    // este sinal para alternar o modo de edição, mesma ação do botão
    // "Editar" ao lado da barra de pesquisa.
    signal alternarModoEdicao

    // Comanda sobre a qual as máquinas da rede discordam (ver
    // services/rede/indicePedidos.py). O amarelo vence o estado de seleção
    // e o de hover: é a informação mais importante do item — enquanto o
    // conflito não for resolvido, o valor do caixa do dia pode estar
    // diferente em cada máquina.
    readonly property bool emConflito: model.emConflito === true

    width: ListView.view.width - (ListView.view.ScrollBar.vertical.visible ? ListView.view.ScrollBar.vertical.width : 0)
    height: colunaItem.implicitHeight + 20
    radius: Estilo.rounding.grande
    color: emConflito
        ? Estilo.cores.avisoFundo
        : (selecionado ? "#ede9fe" : (mouseAreaItem.containsMouse ? "#f5f5f5" : "#ffffff"))
    border.color: emConflito
        ? Estilo.cores.avisoBorda
        : (selecionado ? "#7c3aed" : Estilo.cores.bordaCard)
    border.width: (emConflito || selecionado) ? 2 : 1

    MouseArea {
        id: mouseAreaItem

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
                itemComanda.alternarModoEdicao();
                return;
            }
            pagina.selecionarComanda(model);
        }
    }

    // --- BOTÕES DE EDITAR/APAGAR (modo de edição) ---
    Row {
        id: linhaAcoesItem

        visible: itemComanda.modoEdicao
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Button {
            id: btnEditarItem

            // Comanda de Mesa já fechada (com a divisão da conta já
            // impressa) não tem como reabrir de volta num formulário
            // estruturado — ver o guard equivalente em
            // Consulta.qml:editarComanda().
            visible: model.tipo !== "Mesa"
            implicitWidth: 32
            implicitHeight: 32
            padding: 0
            onClicked: pagina.editarComanda(model.arquivo)

            contentItem: Icone {
                nome: "fa6s.pen"
                cor: "#ffffff"
                tamanho: Estilo.fonte.padrao
                anchors.centerIn: parent
            }

            background: Rectangle {
                radius: 6
                color: parent.down ? Estilo.confirmar.pressionado : (parent.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
            }
        }

        Button {
            id: btnApagarItem

            implicitWidth: 32
            implicitHeight: 32
            padding: 0
            onClicked: popupExclusao.abrirPara(model.arquivo, pagina.tituloComanda(model))

            contentItem: Icone {
                nome: "fa6s.trash-can"
                cor: "#ffffff"
                tamanho: Estilo.fonte.padrao
                anchors.centerIn: parent
            }

            background: Rectangle {
                radius: 6
                color: parent.down ? Estilo.cancelar.pressionado : (parent.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
            }
        }
    }

    Column {
        id: colunaItem

        x: 10
        y: 10
        width: parent.width - 20 - (itemComanda.modoEdicao ? 84 : 0)
        spacing: 4

        Row {
            spacing: 8

            Rectangle {
                radius: 6
                width: textoBadgeItem.implicitWidth + 14
                height: textoBadgeItem.implicitHeight + 6
                color: model.tipo === "Entrega" ? "#0284c7" : (model.tipo === "Mesa" ? "#0d9488" : "#d97706")
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    id: textoBadgeItem

                    text: model.tipo
                    color: "#ffffff"
                    font.bold: true
                    font.pixelSize: 11
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
                font.pixelSize: 11
                font.family: "monospace"
                color: itemComanda.emConflito ? Estilo.cores.avisoTexto : Estilo.cores.textoSecundario
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }

            Icone {
                nome: "fa6s.triangle-exclamation"
                cor: Estilo.cores.avisoBorda
                tamanho: 12
                visible: itemComanda.emConflito
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            text: pagina.tituloComanda(model)
            font.pixelSize: 12
            font.bold: true
            color: Estilo.cores.texto
            elide: Text.ElideRight
            width: colunaItem.width
        }
    }
}
