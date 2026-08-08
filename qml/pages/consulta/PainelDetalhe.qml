import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0

// Coluna direita de Consulta.qml ("Área principal"): mostra o conteúdo
// completo da comanda selecionada na lista, ou uma mensagem de estado vazio.
Rectangle {
    id: painelDetalhe

    // Referência à página Consulta.qml (comandaSelecionada/tituloComanda).
    property var pagina
    property int totalComandas: 0

    radius: Estilo.rounding.medio
    color: "#ffffff"
    border.color: Estilo.cores.bordaCard

    Text {
        anchors.centerIn: parent
        // Durante o carregamento a lista ainda está se enchendo (ver
        // Consulta.qml _preencherModelo), então "nenhuma comanda encontrada"
        // seria uma conclusão tirada antes da hora — e das erradas.
        text: {
            if (painelDetalhe.pagina && painelDetalhe.pagina.carregando)
                return "Carregando comandas...";
            return painelDetalhe.totalComandas === 0
                ? "Nenhuma comanda encontrada em pedidos/"
                : "← Selecione uma comanda para ver os detalhes";
        }
        color: "#95a5a6"
        font.italic: true
        font.pixelSize: Estilo.fonte.padrao
        visible: painelDetalhe.pagina.comandaSelecionada === null
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12
        visible: painelDetalhe.pagina.comandaSelecionada !== null

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Column {
              spacing:5

                Rectangle {
                    radius: 6
                    width: textoBadgeDetalhe.implicitWidth + 16
                    height: textoBadgeDetalhe.implicitHeight + 8
                    color: {
                        var tipo = painelDetalhe.pagina.comandaSelecionada ? painelDetalhe.pagina.comandaSelecionada.tipo : "";
                        return tipo === "Entrega" ? "#0284c7" : (tipo === "Mesa" ? "#0d9488" : "#d97706");
                    }

                    Text {
                        id: textoBadgeDetalhe

                        text: painelDetalhe.pagina.comandaSelecionada ? painelDetalhe.pagina.comandaSelecionada.tipo : ""
                        color: "#ffffff"
                        font.bold: true
                        font.pixelSize: 12
                        anchors.centerIn: parent
                    }
                }

                Text {
                    text: painelDetalhe.pagina.comandaSelecionada ? painelDetalhe.pagina.tituloComanda(painelDetalhe.pagina.comandaSelecionada) : ""
                    font.pixelSize: 15
                    font.bold: true
                    color: Estilo.cores.texto
                }

                // Mesmo código impresso no papel + máquina onde a comanda
                // foi lançada, pra conferência entre as máquinas da rede.
                Text {
                    text: {
                        var c = painelDetalhe.pagina.comandaSelecionada;
                        if (!c || !c.codigo)
                            return "";
                        return c.maquinaOrigem ? c.codigo + " · " + c.maquinaOrigem : c.codigo;
                    }
                    visible: text !== ""
                    font.family: "monospace"
                    font.pixelSize: 12
                    color: Estilo.cores.textoSecundario
                }
            }
        }

        // --- FAIXA DE CONFLITO DE SINCRONIZAÇÃO ---
        // Aparece quando as máquinas da rede discordam sobre esta comanda.
        // Nada é resolvido automaticamente (ver
        // ConsultaController._comparar_pedido_reconciliacao): a decisão é
        // sempre de quem está no caixa.
        Rectangle {
            id: faixaConflito

            // Dados carregados sob demanda: só quando a comanda selecionada
            // muda, e só se ela estiver em conflito — o conteúdo da versão
            // remota é grande demais pra vir junto de toda a listagem.
            property var detalhe: null
            readonly property bool temVersaoRemota: detalhe !== null && detalhe.temVersaoRemota === true
            // Campo a campo, o que não bate entre as duas máquinas (ver
            // ConsultaController.detalheConflito). Conflitos gravados antes
            // desta comparação existir não têm a lista — nesses, e no caso
            // "apagada em outra máquina", a faixa cai no cupom inteiro.
            readonly property var diferencas: detalhe !== null && detalhe.diferencas ? detalhe.diferencas : []
            readonly property bool temDiferencas: diferencas.length > 0

            function recarregar() {
                var c = painelDetalhe.pagina ? painelDetalhe.pagina.comandaSelecionada : null;
                // A checagem do controller não é paranoia: durante o
                // encerramento do app as context properties são destruídas
                // antes das telas, e um binding que rode nesse intervalo
                // encontra null (é o que já acontecia com redeController em
                // Consulta.qml, deixando um TypeError no logs/app.log a cada
                // fechamento).
                if (!c || !c.emConflito || !consultaController) {
                    detalhe = null;
                    return;
                }
                detalhe = consultaController.detalheConflito(c.arquivo);
            }

            Layout.fillWidth: true
            implicitHeight: colunaConflito.implicitHeight + 24
            visible: detalhe !== null
            radius: Estilo.rounding.padrao
            color: Estilo.cores.avisoFundo
            border.color: Estilo.cores.avisoBorda
            border.width: 1

            Connections {
                target: painelDetalhe.pagina
                function onComandaSelecionadaChanged() {
                    faixaConflito.recarregar();
                }
            }

            Component.onCompleted: recarregar()

            Column {
                id: colunaConflito

                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: 13
                    font.bold: true
                    color: Estilo.cores.avisoTexto
                    text: {
                        if (faixaConflito.detalhe === null)
                            return "";
                        var maquina = faixaConflito.detalhe.maquinaRemota || "outra máquina";
                        if (faixaConflito.detalhe.motivo === "apagada_em_outra_maquina")
                            return "Esta comanda foi apagada em " + maquina + ", mas a versão daqui é mais recente.";

                        var quantos = faixaConflito.diferencas.length;
                        if (quantos === 0)
                            return "Esta comanda está diferente em " + maquina + ".";
                        return "Esta comanda é a mesma de " + maquina + ", mas "
                            + (quantos === 1 ? "1 campo não bate" : quantos + " campos não batem") + ".";
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    color: Estilo.cores.avisoTexto
                    text: {
                        if (faixaConflito.temDiferencas)
                            return "Confira o que mudou e escolha qual versão vale. Nada foi alterado automaticamente.";
                        return faixaConflito.temVersaoRemota
                            ? "Compare as duas versões abaixo e escolha qual vale. Nada foi alterado automaticamente."
                            : "Escolha se ela deve continuar existindo. Nada foi alterado automaticamente.";
                    }
                }

                // --- O que exatamente não bate ---
                // Só os campos divergentes, lado a lado. É o que responde a
                // pergunta que a faixa antes deixava no ar ("diferente em quê?")
                // sem obrigar o usuário a comparar dois cupons inteiros linha
                // a linha.
                Rectangle {
                    width: parent.width
                    height: colunaDiferencas.implicitHeight + 16
                    visible: faixaConflito.temDiferencas
                    radius: Estilo.rounding.padrao
                    color: "#ffffff"
                    border.color: Estilo.cores.avisoBorda

                    Column {
                        id: colunaDiferencas

                        x: 8
                        y: 8
                        width: parent.width - 16
                        spacing: 6

                        Row {
                            width: parent.width
                            spacing: 8

                            Text {
                                width: (parent.width - 16) * 0.3
                                text: "Campo"
                                font.pixelSize: 11
                                font.bold: true
                                color: Estilo.cores.textoSecundario
                            }
                            Text {
                                width: (parent.width - 16) * 0.35
                                text: "Esta máquina"
                                font.pixelSize: 11
                                font.bold: true
                                color: Estilo.cores.textoSecundario
                            }
                            Text {
                                width: (parent.width - 16) * 0.35
                                text: faixaConflito.detalhe && faixaConflito.detalhe.maquinaRemota
                                    ? faixaConflito.detalhe.maquinaRemota
                                    : "Outra máquina"
                                font.pixelSize: 11
                                font.bold: true
                                color: Estilo.cores.textoSecundario
                                elide: Text.ElideRight
                            }
                        }

                        Repeater {
                            model: faixaConflito.diferencas

                            delegate: Row {
                                id: linhaDiferenca

                                required property var modelData

                                width: colunaDiferencas.width
                                spacing: 8

                                Text {
                                    width: (linhaDiferenca.width - 16) * 0.3
                                    text: linhaDiferenca.modelData.rotulo
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: Estilo.cores.texto
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    width: (linhaDiferenca.width - 16) * 0.35
                                    // Campo ausente de um dos lados é uma
                                    // diferença tão real quanto um valor
                                    // trocado — o travessão evita que a
                                    // coluna vazia pareça um erro de tela.
                                    text: linhaDiferenca.modelData.local || "—"
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    color: Estilo.cores.texto
                                    wrapMode: Text.Wrap
                                }
                                Text {
                                    width: (linhaDiferenca.width - 16) * 0.35
                                    text: linhaDiferenca.modelData.remoto || "—"
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    color: Estilo.cores.avisoTexto
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }

                // Versão da outra máquina, no mesmo formato monoespaçado do
                // cupom, pra dar pra comparar linha a linha com o de baixo.
                Rectangle {
                    width: parent.width
                    height: Math.min(140, textoVersaoRemota.implicitHeight + 16)
                    // Com a tabela acima, o cupom inteiro só atrapalharia; ele
                    // fica para os conflitos sem lista de diferenças gravada.
                    visible: faixaConflito.temVersaoRemota && !faixaConflito.temDiferencas
                    radius: Estilo.rounding.padrao
                    color: "#ffffff"
                    border.color: Estilo.cores.avisoBorda

                    Flickable {
                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        contentWidth: Math.max(width, textoVersaoRemota.implicitWidth)
                        contentHeight: Math.max(height, textoVersaoRemota.implicitHeight)
                        boundsBehavior: Flickable.StopAtBounds

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        Text {
                            id: textoVersaoRemota

                            text: faixaConflito.detalhe ? (faixaConflito.detalhe.conteudoRemoto || "") : ""
                            font.family: "monospace"
                            font.pixelSize: 12
                            color: "#34495e"
                            wrapMode: Text.NoWrap
                        }
                    }
                }

                Row {
                    spacing: 8

                    Button {
                        text: "Manter esta versão"
                        padding: 8
                        onClicked: {
                            var c = painelDetalhe.pagina.comandaSelecionada;
                            if (c && consultaController.manterVersaoLocal(c.arquivo))
                                painelDetalhe.pagina.carregarComandas();
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: 6
                            color: parent.down ? Estilo.confirmar.pressionado : (parent.hovered ? Estilo.confirmar.hover : Estilo.confirmar.normal)
                        }
                    }

                    Button {
                        text: faixaConflito.temVersaoRemota ? "Adotar a da outra máquina" : "Apagar aqui também"
                        padding: 8
                        onClicked: {
                            var c = painelDetalhe.pagina.comandaSelecionada;
                            if (c && consultaController.adotarVersaoRemota(c.arquivo))
                                painelDetalhe.pagina.carregarComandas();
                        }

                        contentItem: Text {
                            text: parent.text
                            color: "#ffffff"
                            font.bold: true
                            font.pixelSize: 12
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        background: Rectangle {
                            radius: 6
                            color: parent.down ? Estilo.cancelar.pressionado : (parent.hovered ? Estilo.cancelar.hover : Estilo.cancelar.normal)
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#eeeeee"
        }

        // Área do conteúdo do cupom: fonte monoespaçada e sem quebra
        // de linha automática, para as colunas com "|" ficarem
        // alinhadas exatamente como saem na impressora. Rola nos
        // dois eixos quando o texto não cabe no painel.
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: Math.max(width, textoConteudo.implicitWidth)
            contentHeight: Math.max(height, textoConteudo.implicitHeight)
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            ScrollBar.horizontal: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            Text {
                id: textoConteudo

                text: painelDetalhe.pagina.comandaSelecionada ? painelDetalhe.pagina.comandaSelecionada.conteudo : ""
                font.family: "monospace"
                font.pixelSize: 13
                color: "#34495e"
                wrapMode: Text.NoWrap
            }
        }
    }
}
