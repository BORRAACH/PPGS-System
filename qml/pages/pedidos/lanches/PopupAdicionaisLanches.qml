import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../../components"

// Popup de atribuição de adicional a um lanche já selecionado em
// Lanches.qml (selecionados) — máquina de estados navegada só por clique:
//
//   itens -> lanches -> atribui e fecha
//
// Mais simples que o equivalente de Pizzas.qml (PopupAdicionaisBordas.qml):
// lanche não tem borda nem se divide em sabores, então não existem as
// etapas "categoria" nem "sabores" — só "escolha o adicional" e "em qual
// lanche?" (ver comandaTextoService._extras_adicionais, que casa o
// adicional pelo nome BASE do lanche, sem o sufixo do pão).
Popup {
    id: popupAdicionaisLanches

    // Lista de lanches já selecionados (Lanches.qml.selecionados) — só
    // leitura aqui, a atribuição de fato acontece via onAtribuirAdicional,
    // que quem abriu o popup implementa.
    property var lanchesSelecionados: []
    // function(indiceLanche, {nome, valorNum})
    property var onAtribuirAdicional: null

    property string etapa: "itens"
    property var itemSelecionado: null
    property bool adicionaisCarregados: false

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    // A lista de adicionais cresce com o cardápio: presa à altura da janela,
    // a sobra vira rolagem do conteúdo em vez de empurrar os botões de
    // confirmar/cancelar para fora da tela — num popup modal, isso deixaria
    // o atendente sem saída a não ser pelo Esc.
    height: Math.min(implicitHeight, Responsivo.alturaPopup(implicitHeight))
    onOpened: {
        etapa = "itens";
        itemSelecionado = null;
        carregarAdicionais();
    }

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    ListModel {
        id: modeloAdicionaisLanche
    }

    // Síncrono de propósito (3º argumento "false"): arquivo local pequeno,
    // mesmo padrão de PopupAdicionaisBordas.qml.carregarAdicionais — evita
    // ter que encadear callback assíncrono só pra abrir um popup.
    function carregarAdicionais() {
        if (adicionaisCarregados)
            return;

        var xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl(raizProjeto + "data/cardapio/adicionaisLanches.json"), false);
        xhr.send();
        if (xhr.status !== 200 && xhr.status !== 0)
            return;

        try {
            var dados = JSON.parse(xhr.responseText);
            for (var i = 0; i < dados.length; i++) {
                modeloAdicionaisLanche.append(dados[i]);
            }
            adicionaisCarregados = true;
        } catch (e) {
            console.error("Erro ao interpretar adicionaisLanches.json:", e);
        }
    }

    function parseValor(strValor) {
        return parseFloat((strValor || "0").replace(",", "."));
    }

    function descricaoLanche(lanche) {
        return lanche.paoTipo && lanche.paoTipo !== "Pão de Hambúrguer" ? (lanche.nome + " (" + lanche.paoTipo + ")") : lanche.nome;
    }

    function selecionarItem(nome, valorTexto) {
        itemSelecionado = {
            "nome": nome,
            "valorNum": parseValor(valorTexto)
        };
        etapa = "lanches";
    }

    function selecionarLanche(indice) {
        if (typeof onAtribuirAdicional === "function")
            onAtribuirAdicional(indice, itemSelecionado);
        popupAdicionaisLanches.close();
    }

    function voltar() {
        if (etapa === "lanches")
            etapa = "itens";
    }

    function tituloEtapa() {
        return etapa === "itens" ? "Escolha o Adicional" : "Em qual lanche?";
    }

    contentItem: Flickable {
        contentWidth: width
        contentHeight: colunaPopup.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        implicitWidth: colunaPopup.implicitWidth
        implicitHeight: colunaPopup.implicitHeight

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Column {
            id: colunaPopup

            width: Responsivo.larguraPopup(380)
            spacing: 16

            Text {
                text: popupAdicionaisLanches.tituloEtapa()
                font.pixelSize: Estilo.global.fontSize.title
                font.family: Estilo.global.fontFamily.title
                color: Estilo.global.text
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // ---------- ETAPA 1: lista de adicionais ----------
            ListView {
                visible: popupAdicionaisLanches.etapa === "itens"
                width: parent.width
                height: Math.min(300, count * 54)
                clip: true
                spacing: Estilo.global.spacing.xs
                model: modeloAdicionaisLanche

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                delegate: Button {
                    width: ListView.view.width
                    height: 48
                    padding: Estilo.global.padding.md
                    onClicked: popupAdicionaisLanches.selecionarItem(model.nome, model.valor)

                    contentItem: Row {
                        spacing: Estilo.global.spacing.md

                        Text {
                            text: model.nome
                            font.pixelSize: Estilo.global.fontSize.lg
                            font.bold: true
                            color: Estilo.global.text
                            width: parent.width - 90
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "R$ " + model.valor
                            font.pixelSize: Estilo.global.fontSize.lg
                            color: Estilo.action.confirm.base
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.md
                        color: parent.down ? Estilo.global.surfacePressed : (parent.hovered ? Estilo.global.surfaceHover : Estilo.global.surface)
                        border.color: Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }
            }

            // ---------- ETAPA 2: lista de lanches já selecionados ----------
            ListView {
                visible: popupAdicionaisLanches.etapa === "lanches"
                width: parent.width
                height: Math.min(300, count * 54)
                clip: true
                spacing: Estilo.global.spacing.xs
                model: popupAdicionaisLanches.lanchesSelecionados

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                delegate: Button {
                    width: ListView.view.width
                    height: 48
                    padding: Estilo.global.padding.md
                    onClicked: popupAdicionaisLanches.selecionarLanche(index)

                    contentItem: Text {
                        text: popupAdicionaisLanches.descricaoLanche(modelData)
                        font.pixelSize: Estilo.global.fontSize.lg
                        font.bold: true
                        color: Estilo.global.text
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.md
                        color: parent.down ? Estilo.global.surfacePressed : (parent.hovered ? Estilo.global.surfaceHover : Estilo.global.surface)
                        border.color: Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }
            }

            // ---------- Rodapé: Voltar/Cancelar ----------
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Estilo.global.spacing.lg

                Button {
                    text: "Voltar"
                    visible: popupAdicionaisLanches.etapa !== "itens"
                    padding: Estilo.global.padding.md
                    width: 150
                    onClicked: popupAdicionaisLanches.voltar()

                    contentItem: Text {
                        text: "Voltar"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.action.back.pressed : (parent.hovered ? Estilo.action.back.hover : Estilo.action.danger.base)
                    }
                }

                Button {
                    text: "Cancelar"
                    padding: Estilo.global.padding.md
                    width: 150
                    onClicked: popupAdicionaisLanches.close()

                    contentItem: Text {
                        text: "Cancelar"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Qt.darker(Estilo.global.textSecondary, 1.2) : (parent.hovered ? Qt.lighter(Estilo.global.textSecondary, 1.1) : Estilo.global.textSecondary)
                    }
                }
            }
        }

    }
}
