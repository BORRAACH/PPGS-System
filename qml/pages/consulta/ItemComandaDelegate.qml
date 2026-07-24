import QtQuick
import QtQuick.Controls
import estilo 1.0

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
    property bool selecionado: pagina ? index === pagina.indiceSelecionado : false

    // Emitido no clique com o botão direito — ColunaEsquerda.qml conecta a
    // este sinal para alternar o modo de edição, mesma ação do botão
    // "✏️ Editar" ao lado da barra de pesquisa.
    signal alternarModoEdicao

    width: ListView.view.width - (ListView.view.ScrollBar.vertical.visible ? ListView.view.ScrollBar.vertical.width : 0)
    height: colunaItem.implicitHeight + 20
    radius: Estilo.rounding.grande
    color: selecionado ? "#ede9fe" : (mouseAreaItem.containsMouse ? "#f5f5f5" : "#ffffff")
    border.color: selecionado ? "#7c3aed" : Estilo.cores.bordaCard
    border.width: selecionado ? 2 : 1

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
            pagina.indiceSelecionado = index;
            pagina.comandaSelecionada = {
                "tipo": model.tipo,
                "arquivo": model.arquivo,
                "conteudo": model.conteudo,
                "cliente": model.cliente,
                "dataHora": model.dataHora
            };
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

            implicitWidth: 32
            implicitHeight: 32
            padding: 0
            onClicked: pagina.editarComanda(model.arquivo)

            contentItem: Text {
                text: "✏️"
                font.pixelSize: Estilo.fonte.padrao
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
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

            contentItem: Text {
                text: "🗑️"
                font.pixelSize: Estilo.fonte.padrao
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
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
                color: model.tipo === "Entrega" ? "#0284c7" : "#d97706"
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

            Text {
                text: pagina.tituloComanda(model)
                font.pixelSize: 12
                font.bold: true
                color: Estilo.cores.texto
                elide: Text.ElideRight
                width: colunaItem.width - 70
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
