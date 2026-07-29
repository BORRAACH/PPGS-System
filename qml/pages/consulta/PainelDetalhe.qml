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
        text: painelDetalhe.totalComandas === 0 ? "Nenhuma comanda encontrada em pedidos/" : "← Selecione uma comanda para ver os detalhes"
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
                        return "Esta comanda está diferente em " + maquina + ".";
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    color: Estilo.cores.avisoTexto
                    text: faixaConflito.temVersaoRemota
                        ? "Compare as duas versões abaixo e escolha qual vale. Nada foi alterado automaticamente."
                        : "Escolha se ela deve continuar existindo. Nada foi alterado automaticamente."
                }

                // Versão da outra máquina, no mesmo formato monoespaçado do
                // cupom, pra dar pra comparar linha a linha com o de baixo.
                Rectangle {
                    width: parent.width
                    height: Math.min(140, textoVersaoRemota.implicitHeight + 16)
                    visible: faixaConflito.temVersaoRemota
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
