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
    readonly property color corDestaque: categoria ? categoria.cor : Estilo.cores.texto

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
    padding: 25
    parent: Overlay.overlay
    anchors.centerIn: parent

    Overlay.modal: Rectangle {
        color: "#99000000"
    }

    background: Rectangle {
        radius: Estilo.rounding.popup
        color: Estilo.cores.fundoPagina
        border.color: Estilo.cores.bordaCard
    }

    ListModel {
        id: modeloCampos
    }

    contentItem: Column {
        spacing: 18

        Row {
            spacing: 8

            Icone {
                nome: raiz.categoria ? raiz.categoria.icone : "fa6s.pen"
                cor: raiz.corDestaque
                tamanho: 17
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: raiz.indiceEditando < 0 ? (raiz.categoria ? raiz.categoria.novoRotulo : "Novo item") : "Editar item do cardápio"
                font.pixelSize: 17
                font.bold: true
                color: Estilo.cores.texto
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Column {
            spacing: 12
            width: 460

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
                        font.pixelSize: 12
                        font.bold: true
                        color: Estilo.cores.textoSecundario
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
                        font.pixelSize: Estilo.fonte.padrao
                        color: Estilo.cores.textoInput
                        leftPadding: 12
                        rightPadding: 12
                        selectByMouse: true
                        placeholderTextColor: Estilo.cores.placeholderInput
                        placeholderText: model.tipo === "preco" ? "0,00" : ""
                        onTextChanged: raiz.valores[blocoCampo.chave] = text
                        onAccepted: raiz.confirmar()
                        Component.onCompleted: {
                            if (index === 0)
                                campoLinha.forceActiveFocus();
                        }

                        background: Rectangle {
                            radius: Estilo.rounding.grande
                            color: "#ffffff"
                            border.color: campoLinha.activeFocus ? raiz.corDestaque : Estilo.cores.borda
                            border.width: campoLinha.activeFocus ? 2 : 1
                        }
                    }

                    // Várias linhas: a lista de ingredientes, que costuma ser
                    // longa demais para caber numa linha só.
                    Rectangle {
                        visible: blocoCampo.longo
                        width: parent.width
                        height: 78
                        radius: Estilo.rounding.grande
                        color: "#ffffff"
                        border.color: campoTexto.activeFocus ? raiz.corDestaque : Estilo.cores.borda
                        border.width: campoTexto.activeFocus ? 2 : 1

                        TextArea {
                            id: campoTexto

                            placeholderTextColor: Estilo.cores.placeholderInput
                            anchors.fill: parent
                            anchors.margins: 4
                            text: model.valor
                            font.pixelSize: Estilo.fonte.padrao
                            color: Estilo.cores.textoInput
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
            spacing: 8
            visible: raiz.erro !== ""
            width: 460

            Icone {
                nome: "fa6s.triangle-exclamation"
                cor: Estilo.cancelar.normal
                tamanho: 13
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: raiz.erro
                font.pixelSize: 12
                color: Estilo.cancelar.normal
                width: parent.width - 21
                wrapMode: Text.WordWrap
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Row {
            spacing: 12
            anchors.right: parent.right

            Button {
                id: btnCancelar

                text: "Cancelar"
                padding: 10
                onClicked: raiz.close()

                contentItem: Text {
                    text: btnCancelar.text
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: btnCancelar.down ? Estilo.cores.textoSecundario : (btnCancelar.hovered ? "#95a5a6" : Estilo.cores.textoSecundario)
                }
            }

            Button {
                id: btnSalvar

                padding: 10
                onClicked: raiz.confirmar()

                contentItem: Row {
                    spacing: 6
                    anchors.centerIn: parent

                    Icone {
                        nome: "fa6s.floppy-disk"
                        cor: "#ffffff"
                        tamanho: Estilo.fonte.padrao
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Salvar"
                        font.bold: true
                        color: "#ffffff"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: btnSalvar.down ? Estilo.confirmar.pressionado : (btnSalvar.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                    border.color: Estilo.confirmar.pressionado
                    border.width: 1
                }
            }
        }
    }
}
