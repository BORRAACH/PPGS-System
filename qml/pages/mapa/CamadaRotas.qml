import QtQuick
import QtQuick.Shapes
import "../../components"

// CamadaRotas.qml — o que a barra "Verificar rota" (PainelRotas.qml) desenha no
// mapa: as rotas alternativas em azul claro, a selecionada por cima em azul
// escuro, a origem vermelha, o destino verde e as paradas numeradas. Declarada
// dentro do MapaBlocos, fica acima dos blocos; os dados vêm todos do painel.
//
// Traçado: cada rota é um Shape com os pontos em pixels de um zoom fixo
// (PainelRotas.escalaTracado). No pan e no zoom a camada só é movida e
// escalada, sem recalcular pontos.
Item {
    id: camada

    required property PainelRotas painel
    required property MapaBlocos mapa

    anchors.fill: parent

    // ----- Traçados: alternativas em azul claro, a selecionada por cima -----
    Repeater {
        model: camada.painel.rotasAtuais

        delegate: Item {
            id: desenhoRota

            required property int index
            required property var modelData
            readonly property var tracado: modelData.tracado
            readonly property bool selecionada: index === camada.painel.rotaSelecionada
            // Pixels de tela por unidade do traçado.
            readonly property real escala: camada.mapa.tamanhoMundo / camada.painel.escalaTracado

            z: selecionada ? 2 : 1
            visible: tracado !== null
            x: tracado ? camada.mapa.telaX(tracado.x) : 0
            y: tracado ? camada.mapa.telaY(tracado.y) : 0
            scale: escala
            transformOrigin: Item.TopLeft

            Shape {
                // Contorno branco: a rota não some sobre uma avenida.
                ShapePath {
                    strokeColor: "white"
                    strokeWidth: (camada.painel.espessuraRota + 3) / desenhoRota.escala
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: desenhoRota.tracado ? desenhoRota.tracado.pontos : [] }
                }
                ShapePath {
                    strokeColor: desenhoRota.selecionada ? camada.painel.corRotaSelecionada : camada.painel.corRotaAlternativa
                    strokeWidth: (desenhoRota.selecionada ? camada.painel.espessuraRota : camada.painel.espessuraRota - 2) / desenhoRota.escala
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathPolyline { path: desenhoRota.tracado ? desenhoRota.tracado.pontos : [] }
                }
            }
        }
    }

    // ----- Marcadores: origem vermelha, destino verde, paradas numeradas -----
    Repeater {
        model: camada.painel.pontos

        delegate: Item {
            id: marcadorPonto

            required property int index
            required property real latitude
            required property real longitude
            required property bool definido

            readonly property var ponto: camada.mapa.paraMundo(latitude, longitude)
            readonly property bool ehOrigem: index === 0
            readonly property bool ehDestino: index === camada.painel.pontos.count - 1
            readonly property color cor: ehOrigem ? camada.painel.corOrigem : ehDestino ? camada.painel.corDestino : camada.painel.corParada

            visible: definido
            z: 10
            width: 30
            height: 32
            // A ponta da gota fica sobre a coordenada.
            x: Math.round(camada.mapa.telaX(ponto.x) - width / 2)
            y: Math.round(camada.mapa.telaY(ponto.y) - height)

            // Gota: quadrado com três cantos redondos girado 45°.
            Rectangle {
                x: 2
                y: 0
                width: 26
                height: 26
                radius: 13
                bottomRightRadius: 0
                rotation: 45
                antialiasing: true
                color: marcadorPonto.cor
                border.color: "white"
                border.width: 2
            }
            Rectangle {
                x: 9
                y: 7
                width: 12
                height: 12
                radius: 6
                color: "white"

                Text {
                    anchors.centerIn: parent
                    visible: !marcadorPonto.ehOrigem && !marcadorPonto.ehDestino
                    text: marcadorPonto.index
                    color: marcadorPonto.cor
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }
            }
        }
    }
}
