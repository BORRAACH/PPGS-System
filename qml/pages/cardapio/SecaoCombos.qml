import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../components"

// Aba "Combos" da tela de cardápio: lista os combos promocionais e abre o
// formulário (PopupCombo.qml) para criar ou editar. Não grava nada — avisa
// Cardapio.qml por sinais e ele guarda a lista em memória até "Aplicar
// alterações", como faz com os itens das categorias.
//
// O que um combo é e como entra no pedido: services/combosService.py.
ColumnLayout {
    id: raiz

    // [{id, nome, valor, quantidade, tamanho, pizzas, ativo, agenda}, ...]
    property var combos: []
    // Um bool por combo, na mesma ordem: se vale hoje (ver
    // CardapioController.disponibilidadeCombosHoje).
    property var disponiveisHoje: []
    property color corDestaque: Estilo.global.text

    signal novo
    signal editar(int indice)
    signal remover(int indice)
    signal alternarAtivo(int indice)

    readonly property var nomesDias: ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]

    function paraBr(iso) {
        var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(iso || ""));
        return m ? m[3] + "/" + m[2] + "/" + m[1] : "";
    }

    // "Seg–Qui", "Sex, Sáb e Dom", "Todos os dias"... Dias seguidos viram
    // faixa; a semana começa na segunda, que é como a loja a lê.
    function resumoDias(dias) {
        if (!dias || dias.length === 0 || dias.length === 7)
            return "";

        var ordem = [1, 2, 3, 4, 5, 6, 0];
        var presentes = ordem.filter(function (d) {
            return dias.indexOf(d) >= 0;
        });
        var faixas = [];
        var inicio = 0;
        for (var i = 1; i <= presentes.length; i++) {
            if (i === presentes.length || ordem.indexOf(presentes[i]) !== ordem.indexOf(presentes[i - 1]) + 1) {
                var tamanho = i - inicio;
                var a = nomesDias[presentes[inicio]];
                var b = nomesDias[presentes[i - 1]];
                faixas.push(tamanho >= 3 ? a + "–" + b : presentes.slice(inicio, i).map(function (d) {
                    return nomesDias[d];
                }).join(", "));
                inicio = i;
            }
        }
        return faixas.join(", ");
    }

    function resumoAgenda(agenda) {
        agenda = agenda || {};
        var partes = [];
        var dias = resumoDias(agenda.dias);
        if (dias !== "")
            partes.push(dias);

        if (agenda.inicio && agenda.fim)
            partes.push("de " + paraBr(agenda.inicio) + " a " + paraBr(agenda.fim));
        else if (agenda.inicio)
            partes.push("a partir de " + paraBr(agenda.inicio));
        else if (agenda.fim)
            partes.push("até " + paraBr(agenda.fim));

        var datas = agenda.datas || [];
        if (datas.length > 0)
            partes.push(datas.length === 1 ? "+ 1 data avulsa (" + paraBr(datas[0]) + ")" : "+ " + datas.length + " datas avulsas");

        if (partes.length === 0 || (dias === "" && !agenda.inicio && !agenda.fim && datas.length === 0))
            return "Todos os dias";

        return partes.join(" · ");
    }

    function textoValor(valor) {
        return "R$ " + valor;
    }

    spacing: Estilo.global.spacing.lg

    RowLayout {
        Layout.fillWidth: true
        spacing: Estilo.global.spacing.lg

        Text {
            Layout.fillWidth: true
            text: "Quando o pedido tem pizzas suficientes de um combo, o desconto entra sozinho. As pizzas fora do combo ficam com o preço cheio."
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            wrapMode: Text.WordWrap
        }

        Button {
            id: btnNovo

            Layout.preferredHeight: 42
            padding: 14
            onClicked: raiz.novo()

            contentItem: Row {
                spacing: Estilo.global.spacing.sm

                Icone {
                    nome: "fa6s.plus"
                    cor: Estilo.global.textOnAccent
                    tamanho: Estilo.global.fontSize.lg
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Novo combo"
                    font.pixelSize: Estilo.global.fontSize.lg
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: btnNovo.down ? Qt.darker(raiz.corDestaque, 1.2) : (btnNovo.hovered ? Qt.lighter(raiz.corDestaque, 1.1) : raiz.corDestaque)
            }
        }
    }

    ListView {
        id: lista

        Layout.fillWidth: true
        Layout.fillHeight: true
        model: raiz.combos
        spacing: Estilo.global.spacing.sm
        clip: true

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        Text {
            anchors.centerIn: parent
            visible: raiz.combos.length === 0
            text: "Nenhum combo cadastrado. Toque em \"Novo combo\"."
            font.pixelSize: Estilo.global.fontSize.md
            font.italic: true
            color: Estilo.global.textMuted
        }

        delegate: Rectangle {
            id: cartao

            required property int index
            required property var modelData

            readonly property bool disponivel: raiz.disponiveisHoje[index] === true
            readonly property string estado: !modelData.ativo ? "Desativado" : (disponivel ? "Disponível hoje" : "Indisponível hoje")
            readonly property color corEstado: disponivel ? Estilo.action.confirm.base : Estilo.global.textMuted

            width: lista.width - (lista.ScrollBar.vertical.visible ? lista.ScrollBar.vertical.width : 0)
            height: 84
            radius: Estilo.global.radius.md
            color: areaCartao.containsMouse ? Estilo.global.surfaceHover : Estilo.global.surface
            border.color: Estilo.global.border
            border.width: Estilo.global.borderWidth.hairline
            // Combo que não vale agora fica esmaecido, mas continua legível e
            // editável: "indisponível" é um estado, não um erro.
            opacity: disponivel ? 1 : 0.7

            MouseArea {
                id: areaCartao

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: raiz.editar(cartao.index)
            }

            Row {
                id: acoes

                spacing: Estilo.global.spacing.sm
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter

                Switch {
                    checked: cartao.modelData.ativo
                    anchors.verticalCenter: parent.verticalCenter
                    onToggled: raiz.alternarAtivo(cartao.index)
                }

                Button {
                    id: btnEditar

                    width: 32
                    height: 32
                    padding: 0
                    onClicked: raiz.editar(cartao.index)

                    contentItem: Icone {
                        nome: "fa6s.pen"
                        cor: Estilo.global.textOnAccent
                        tamanho: 13
                        anchors.centerIn: parent
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnEditar.down ? Qt.darker(raiz.corDestaque, 1.2) : (btnEditar.hovered ? Qt.lighter(raiz.corDestaque, 1.1) : raiz.corDestaque)
                    }
                }

                Button {
                    id: btnRemover

                    width: 32
                    height: 32
                    padding: 0
                    onClicked: raiz.remover(cartao.index)

                    contentItem: Icone {
                        nome: "fa6s.trash-can"
                        cor: Estilo.global.textOnAccent
                        tamanho: 13
                        anchors.centerIn: parent
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: btnRemover.down ? Estilo.action.danger.pressed : (btnRemover.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base)
                    }
                }
            }

            Text {
                id: textoEstado

                anchors.right: acoes.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: cartao.estado
                font.pixelSize: Estilo.global.fontSize.sm
                font.bold: true
                color: cartao.corEstado
            }

            Column {
                spacing: 3
                anchors.left: parent.left
                anchors.leftMargin: 14
                anchors.right: textoEstado.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: cartao.modelData.nome
                    font.pixelSize: Estilo.global.fontSize.lg
                    font.bold: true
                    color: Estilo.global.text
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: cartao.modelData.quantidade + " pizzas " + cartao.modelData.tamanho + " por " + raiz.textoValor(cartao.modelData.valor) + "  ·  " + cartao.modelData.pizzas.length + (cartao.modelData.pizzas.length === 1 ? " sabor" : " sabores")
                    font.pixelSize: Estilo.global.fontSize.md
                    color: Estilo.action.confirm.base
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: raiz.resumoAgenda(cartao.modelData.agenda)
                    font.pixelSize: Estilo.global.fontSize.sm
                    color: Estilo.global.textSecondary
                    elide: Text.ElideRight
                }
            }
        }
    }
}
