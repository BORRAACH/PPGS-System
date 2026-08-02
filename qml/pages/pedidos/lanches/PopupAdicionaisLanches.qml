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
    padding: 25
    parent: Overlay.overlay
    anchors.centerIn: parent
    onOpened: {
        etapa = "itens";
        itemSelecionado = null;
        carregarAdicionais();
    }

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        radius: Estilo.rounding.popup
        color: Estilo.cores.fundoPagina
        border.color: Estilo.cores.bordaCard
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

    contentItem: Column {
        id: colunaPopup

        width: 380
        spacing: 16

        Text {
            text: popupAdicionaisLanches.tituloEtapa()
            font.pixelSize: Estilo.fonte.titulo
            font.bold: true
            color: Estilo.cores.texto
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // ---------- ETAPA 1: lista de adicionais ----------
        ListView {
            visible: popupAdicionaisLanches.etapa === "itens"
            width: parent.width
            height: Math.min(300, count * 54)
            clip: true
            spacing: 6
            model: modeloAdicionaisLanche

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Button {
                width: ListView.view.width
                height: 48
                padding: 10
                onClicked: popupAdicionaisLanches.selecionarItem(model.nome, model.valor)

                contentItem: Row {
                    spacing: 10

                    Text {
                        text: model.nome
                        font.pixelSize: Estilo.fonte.padrao
                        font.bold: true
                        color: Estilo.cores.texto
                        width: parent.width - 90
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "R$ " + model.valor
                        font.pixelSize: Estilo.fonte.padrao
                        color: Estilo.confirmar.normal
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.grande
                    color: parent.down ? Estilo.cores.bordaCard : (parent.hovered ? "#f1f1f1" : "#ffffff")
                    border.color: Estilo.cores.borda
                    border.width: 1
                }
            }
        }

        // ---------- ETAPA 2: lista de lanches já selecionados ----------
        ListView {
            visible: popupAdicionaisLanches.etapa === "lanches"
            width: parent.width
            height: Math.min(300, count * 54)
            clip: true
            spacing: 6
            model: popupAdicionaisLanches.lanchesSelecionados

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Button {
                width: ListView.view.width
                height: 48
                padding: 10
                onClicked: popupAdicionaisLanches.selecionarLanche(index)

                contentItem: Text {
                    text: popupAdicionaisLanches.descricaoLanche(modelData)
                    font.pixelSize: Estilo.fonte.padrao
                    font.bold: true
                    color: Estilo.cores.texto
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.grande
                    color: parent.down ? Estilo.cores.bordaCard : (parent.hovered ? "#f1f1f1" : "#ffffff")
                    border.color: Estilo.cores.borda
                    border.width: 1
                }
            }
        }

        // ---------- Rodapé: Voltar/Cancelar ----------
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Button {
                text: "Voltar"
                visible: popupAdicionaisLanches.etapa !== "itens"
                padding: 10
                width: 150
                onClicked: popupAdicionaisLanches.voltar()

                contentItem: Text {
                    text: "Voltar"
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Estilo.voltar.pressionado : (parent.hovered ? Estilo.voltar.hover : Estilo.cancelar.normal)
                }
            }

            Button {
                text: "Cancelar"
                padding: 10
                width: 150
                onClicked: popupAdicionaisLanches.close()

                contentItem: Text {
                    text: "Cancelar"
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? Qt.darker(Estilo.cores.textoSecundario, 1.2) : (parent.hovered ? Qt.lighter(Estilo.cores.textoSecundario, 1.1) : Estilo.cores.textoSecundario)
                }
            }
        }
    }
}
