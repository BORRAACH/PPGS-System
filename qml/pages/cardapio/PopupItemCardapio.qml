import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../components"
import "../../components/Texto.js" as Texto

// Formulário de um item do cardápio (novo ou já existente), usado por
// Cardapio.qml. Os campos não são escritos à mão aqui: vêm da descrição da
// categoria (services/cardapioService.py), então a mesma tela serve para
// pizza (nome + ingredientes + 3 preços), lanche (3 preços por tipo de pão),
// bebida e "outros" (um preço só).
//
// O popup valida antes de fechar (campo obrigatório em branco, preço fora do
// formato, nome repetido) para o erro aparecer com o formulário ainda aberto
// e preenchido. O Python revalida na hora de gravar — é ele que decide o que
// entra no arquivo.
Popup {
    id: raiz

    // -1 = item novo; >= 0 = índice do item sendo editado em Cardapio.qml
    property int indiceEditando: -1
    property var categoria: null
    // Nomes dos outros itens da categoria, para barrar duplicata
    property var nomesExistentes: []
    // Valores digitados, por chave de campo (ex: valores["valor.pao_baby"])
    property var valores: ({})
    property string erro: ""
    // Vem da tela do cardápio, que resolve a cor pela chave da categoria — o
    // "cor" que o cardapioController devolve junto é ignorado de propósito.
    property color corDestaque: Estilo.global.text

    signal confirmado(int indice, var item)

    // Mesmo formato aceito por normalizar_preco() em services/cardapioService.py
    // ("24,90", "24.90", "24", "R$ 24,9") — a validação aqui só existe para o
    // usuário ver o erro sem perder o que digitou.
    readonly property var formatoPreco: /^(?:R\$\s*)?\d{1,5}([.,]\d{1,2})?$/

    function abrirPara(indice, item, categoriaDoItem, nomes) {
        if (!categoriaDoItem)
            return;

        raiz.indiceEditando = indice;
        raiz.categoria = categoriaDoItem;
        raiz.nomesExistentes = nomes;
        raiz.erro = "";
        raiz.valores = {};

        // Recria a lista de campos a cada abertura (mesmo quando a categoria
        // é a mesma da vez anterior): é isso que faz o Repeater recriar os
        // delegates e os campos aparecerem com o valor do item atual, em vez
        // de manterem o texto da edição anterior.
        modeloCampos.clear();
        var campos = categoriaDoItem.campos;
        for (var i = 0; i < campos.length; i++) {
            var valor = item ? (item[campos[i].chave] || "") : "";
            raiz.valores[campos[i].chave] = valor;
            modeloCampos.append({
                "chave": campos[i].chave,
                "rotulo": campos[i].rotulo,
                "tipo": campos[i].tipo,
                "obrigatorio": campos[i].obrigatorio,
                "valor": valor
            });
        }
        raiz.open();
    }

    function confirmar() {
        var item = {};
        var nomeInformado = "";

        for (var i = 0; i < modeloCampos.count; i++) {
            var campo = modeloCampos.get(i);
            var valor = String(raiz.valores[campo.chave] || "").trim();

            if (campo.obrigatorio && valor === "") {
                raiz.erro = "Preencha o campo \"" + campo.rotulo + "\".";
                return;
            }
            // "preco" espelha o tipo PRECO de services/cardapioService.py
            if (campo.tipo === "preco" && valor !== "" && !raiz.formatoPreco.test(valor)) {
                raiz.erro = "\"" + campo.rotulo + "\" precisa ser um preço como 24,90.";
                return;
            }
            if (campo.chave === "nome")
                nomeInformado = valor;

            item[campo.chave] = valor;
        }

        // Dois itens com o mesmo nome ficariam indistinguíveis na busca das
        // telas de pedido — compara sem acento e sem diferenciar maiúsculas,
        // igual à busca (ver components/Texto.js).
        var nomeNormalizado = Texto.normalizar(nomeInformado);
        for (var j = 0; j < raiz.nomesExistentes.length; j++) {
            if (Texto.normalizar(raiz.nomesExistentes[j]) === nomeNormalizado) {
                raiz.erro = "Já existe um item chamado \"" + nomeInformado + "\" nesta categoria.";
                return;
            }
        }

        raiz.confirmado(raiz.indiceEditando, item);
        raiz.close();
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    // Um item com muitos campos (uma pizza tem nome, ingredientes e três
    // preços) faz este popup passar da altura da janela num tablet. Preso ao
    // que a janela comporta, o excedente vira rolagem do conteúdo em vez de
    // sumir para fora da tela junto com os botões de Salvar/Cancelar.
    height: Math.min(implicitHeight, Responsivo.alturaPopup(implicitHeight))

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    ListModel {
        id: modeloCampos
    }

    contentItem: Flickable {
        contentWidth: width
        contentHeight: colunaItem.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        implicitWidth: colunaItem.implicitWidth
        implicitHeight: colunaItem.implicitHeight

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Column {
            id: colunaItem

            spacing: 18

            Row {
                spacing: Estilo.global.spacing.sm

                Icone {
                    nome: raiz.categoria ? raiz.categoria.icone : "fa6s.pen"
                    cor: raiz.corDestaque
                    tamanho: 17
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: raiz.indiceEditando < 0 ? (raiz.categoria ? raiz.categoria.novoRotulo : "Novo item") : "Editar item do cardápio"
                    font.pixelSize: Estilo.global.fontSize.xl
                    font.bold: true
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Column {
                spacing: Estilo.global.spacing.lg
                width: Responsivo.larguraPopup(460)

                Repeater {
                    model: modeloCampos

                    delegate: Column {
                        id: blocoCampo

                        // Capturados do modelo porque os handlers e o background
                        // dos campos abaixo estão em outro escopo.
                        readonly property string chave: model.chave
                        readonly property bool longo: model.tipo === "texto_longo"

                        width: parent.width
                        spacing: 5

                        Text {
                            text: model.rotulo + (model.obrigatorio ? "" : " (opcional)")
                            font.pixelSize: Estilo.global.fontSize.sm
                            font.bold: true
                            color: Estilo.global.textSecondary
                        }

                        // Uma linha: nome e preços. Enter confirma o formulário
                        // inteiro, para dar conta do caso mais comum (bebida ou
                        // "outros": nome + preço e pronto).
                        TextField {
                            id: campoLinha

                            visible: !blocoCampo.longo
                            width: parent.width
                            height: 40
                            text: model.valor
                            font.pixelSize: Estilo.global.fontSize.lg
                            color: Estilo.global.textInput
                            leftPadding: 12
                            rightPadding: 12
                            selectByMouse: true
                            placeholderTextColor: Estilo.global.textPlaceholder
                            placeholderText: model.tipo === "preco" ? "0,00" : ""
                            onTextChanged: raiz.valores[blocoCampo.chave] = text
                            onAccepted: raiz.confirmar()
                            Component.onCompleted: {
                                if (index === 0)
                                    campoLinha.forceActiveFocus();
                            }

                            background: Rectangle {
                                radius: Estilo.global.radius.pill
                                color: Estilo.global.inputBackground
                                border.color: campoLinha.activeFocus ? raiz.corDestaque : Estilo.global.border
                                border.width: campoLinha.activeFocus ? 2 : 1
                            }
                        }

                        // Várias linhas: a lista de ingredientes, que costuma ser
                        // longa demais para caber numa linha só.
                        Rectangle {
                            visible: blocoCampo.longo
                            width: parent.width
                            height: 78
                            radius: Estilo.global.radius.md
                            color: Estilo.global.inputBackground
                            border.color: campoTexto.activeFocus ? raiz.corDestaque : Estilo.global.border
                            border.width: campoTexto.activeFocus ? 2 : 1

                            TextArea {
                                id: campoTexto

                                placeholderTextColor: Estilo.global.textPlaceholder
                                anchors.fill: parent
                                anchors.margins: 4
                                text: model.valor
                                font.pixelSize: Estilo.global.fontSize.lg
                                color: Estilo.global.textInput
                                wrapMode: TextArea.Wrap
                                selectByMouse: true
                                background: null
                                onTextChanged: raiz.valores[blocoCampo.chave] = text
                            }
                        }
                    }
                }
            }

            Row {
                spacing: Estilo.global.spacing.sm
                visible: raiz.erro !== ""
                width: Responsivo.larguraPopup(460)

                Icone {
                    nome: "fa6s.triangle-exclamation"
                    cor: Estilo.action.danger.base
                    tamanho: 13
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: raiz.erro
                    font.pixelSize: Estilo.global.fontSize.sm
                    color: Estilo.action.danger.base
                    width: parent.width - 21
                    wrapMode: Text.WordWrap
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                spacing: Estilo.global.spacing.lg
                anchors.right: parent.right

                Button {
                    id: btnCancelar

                    text: "Cancelar"
                    padding: Estilo.global.padding.md
                    onClicked: raiz.close()

                    contentItem: Text {
                        text: btnCancelar.text
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnCancelar.down ? Estilo.action.neutral.pressed : (btnCancelar.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                    }
                }

                Button {
                    id: btnSalvar

                    padding: Estilo.global.padding.md
                    onClicked: raiz.confirmar()

                    contentItem: Row {
                        spacing: Estilo.global.spacing.xs
                        anchors.centerIn: parent

                        Icone {
                            nome: "fa6s.floppy-disk"
                            cor: Estilo.global.textOnAccent
                            tamanho: Estilo.global.fontSize.lg
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "Salvar"
                            font.family: Estilo.global.fontFamily.title
                            color: Estilo.global.textOnAccent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnSalvar.down ? Estilo.action.confirm.pressed : (btnSalvar.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                        border.color: Estilo.action.confirm.pressed
                        border.width: Estilo.global.borderWidth.hairline
                    }
                }
            }
        }

    }
}
