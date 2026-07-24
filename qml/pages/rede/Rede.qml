import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0

// Mostra as máquinas atualmente conectadas na malha local (ver
// services/redeService.py) — quem está compartilhando pedidos com esta
// instância agora, desde quando, e o endereço de cada uma.
Page {
    id: telaRede

    objectName: "telaRede"

    property var _todosPeers: []

    function carregarPeers() {
        telaRede._todosPeers = redeController.listarPeers();
        modeloPeers.clear();
        for (var i = 0; i < telaRede._todosPeers.length; i++) {
            modeloPeers.append(telaRede._todosPeers[i]);
        }
    }

    // "3600" -> "1h 0min"; usado tanto na lista quanto atualizado a cada
    // tique do timer abaixo, sem precisar reconsultar a rede.
    function formatarDuracao(segundos) {
        segundos = Math.max(0, Math.floor(segundos));
        if (segundos < 60)
            return segundos + "s";
        var minutos = Math.floor(segundos / 60);
        if (minutos < 60)
            return minutos + "min";
        var horas = Math.floor(minutos / 60);
        return horas + "h " + (minutos % 60) + "min";
    }

    Component.onCompleted: {
        carregarPeers();
        redeController.peersMudaram.connect(carregarPeers);
    }
    StackView.onActivated: carregarPeers()

    // Só para as durações ("conectado há...") avançarem sozinhas na tela,
    // sem precisar reconsultar a rede a cada segundo.
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: relogio.agora = Date.now()
    }
    QtObject {
        id: relogio
        property real agora: Date.now()
    }

    background: Rectangle {
        color: Estilo.cores.fundoPagina
        radius: Estilo.rounding.popup
    }

    ListModel {
        id: modeloPeers
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 15

        // --- CABEÇALHO ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 15

            Text {
                text: "🌐 REDE LOCAL"
                font.pixelSize: Estilo.fonte.titulo
                font.bold: true
                color: "#0ea5e9"
            }

            Item {
                Layout.fillWidth: true
            }

            Button {
                id: btnAtualizarRede

                text: "🔄 Atualizar"
                padding: 8
                onClicked: telaRede.carregarPeers()

                contentItem: Text {
                    text: btnAtualizarRede.text
                    font.bold: true
                    color: "#ffffff"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.rounding.padrao
                    color: parent.down ? "#0369a1" : (parent.hovered ? "#0ea5e9" : "#0284c7")
                }
            }
        }

        // --- ESTA MÁQUINA ---
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: linhaEstaMaquina.implicitHeight + 20
            radius: Estilo.rounding.grande
            color: "#f0f9ff"
            border.color: "#bae6fd"
            border.width: 1

            RowLayout {
                id: linhaEstaMaquina
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10

                Text {
                    text: "🖥️"
                    font.pixelSize: Estilo.fonte.titulo
                }

                ColumnLayout {
                    spacing: 2

                    Text {
                        text: "Esta máquina: " + redeController.nomeLocal
                        font.bold: true
                        font.pixelSize: Estilo.fonte.padrao
                        color: Estilo.cores.texto
                    }

                    Text {
                        text: "Compartilhando pedidos com " + redeController.quantidadeConectados + " máquina(s) na rede local"
                        font.pixelSize: 11
                        color: Estilo.cores.textoSecundario
                    }
                }
            }
        }

        Text {
            text: "Máquinas conectadas (" + modeloPeers.count + ")"
            font.pixelSize: Estilo.fonte.padrao
            font.bold: true
            color: Estilo.cores.textoSecundario
        }

        // --- LISTA DE PEERS ---
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 8
            model: modeloPeers

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            // Estado vazio: nenhuma outra instância do app foi encontrada
            // ainda na rede local (pode levar alguns segundos após abrir).
            Text {
                anchors.centerIn: parent
                visible: modeloPeers.count === 0
                text: "Nenhuma outra máquina conectada ainda.\nAbra o sistema nas outras máquinas da rede local para elas aparecerem aqui."
                horizontalAlignment: Text.AlignHCenter
                color: Estilo.cores.textoSecundario
                font.pixelSize: Estilo.fonte.padrao
            }

            delegate: Rectangle {
                width: ListView.view.width - (ListView.view.ScrollBar.vertical.visible ? ListView.view.ScrollBar.vertical.width : 0)
                height: colunaPeer.implicitHeight + 20
                radius: Estilo.rounding.grande
                color: "#ffffff"
                border.color: Estilo.cores.bordaCard
                border.width: 1

                RowLayout {
                    id: colunaPeer
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 10
                    spacing: 10

                    Text {
                        text: "🖥️"
                        font.pixelSize: Estilo.fonte.titulo
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: model.nome
                            font.bold: true
                            font.pixelSize: Estilo.fonte.padrao
                            color: Estilo.cores.texto
                        }

                        Text {
                            text: model.endereco
                            font.pixelSize: 11
                            color: Estilo.cores.textoSecundario
                        }
                    }

                    Text {
                        text: "conectado há " + telaRede.formatarDuracao(relogio.agora / 1000 - model.conectadoEm)
                        font.pixelSize: 11
                        color: Estilo.cores.textoSecundario
                    }
                }
            }
        }
    }
}
