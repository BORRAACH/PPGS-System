import QtQuick
import QtQuick.Layouts
import estilo 1.0
import "../../components"

// Uma linha do histórico da malha (ver services/rede/historicoEventos.py e o
// cartão "Histórico da rede" em Rede.qml): o que aconteceu, em qual máquina e
// há quanto tempo.
//
// O ícone e o rótulo da categoria vêm PRONTOS do Python, não de um mapa aqui:
// acrescentar um tipo de evento novo (services/rede/historicoEventos._EVENTOS)
// deve bastar para ele aparecer nesta tela, sem uma segunda edição no QML que
// alguém fatalmente esqueceria.
Rectangle {
    id: itemHistorico

    // {id, tipo, categoria, rotuloCategoria, icone, rotulo, detalhe, maquina, quando}
    required property var evento
    // Instante atual em segundos, vindo de fora (o timer de 1s de Rede.qml já
    // existe para as durações dos peers) — assim "há 5 min" avança sozinho sem
    // cada linha manter o próprio timer.
    required property real agoraSegundos
    // A formatação ("3600" -> "1h 0min") chega como função em vez de ser
    // reescrita aqui: id de outro arquivo QML não é visível de dentro deste,
    // e uma segunda cópia da mesma regra sairia do lugar na primeira vez que
    // alguém ajustasse a de Rede.qml.
    required property var formatarDuracao

    implicitHeight: linha.implicitHeight + 16
    radius: Estilo.global.radius.sm
    color: Estilo.global.surface
    border.color: Estilo.global.borderCard
    border.width: Estilo.global.borderWidth.hairline

    RowLayout {
        id: linha

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: Estilo.global.spacing.md

        Icone {
            nome: itemHistorico.evento.icone
            cor: Estilo.global.textSecondary
            tamanho: Estilo.global.fontSize.lg
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 2
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: itemHistorico.evento.rotulo
                font.pixelSize: Estilo.global.fontSize.md
                font.bold: true
                color: Estilo.global.text
                elide: Text.ElideRight
            }

            // Só ocupa espaço quando o evento tem alvo (o nome do arquivo da
            // comanda, a categoria do cardápio...) — "Contagem de caixa
            // atualizada" não tem, e uma linha vazia embaixo pareceria falha.
            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: itemHistorico.evento.detalhe
                font.pixelSize: Estilo.global.fontSize.xs
                font.family: "monospace"
                color: Estilo.global.textSecondary
                elide: Text.ElideMiddle
            }

            Text {
                Layout.fillWidth: true
                text: itemHistorico.evento.maquina
                    ? itemHistorico.evento.rotuloCategoria + " · " + itemHistorico.evento.maquina
                    : itemHistorico.evento.rotuloCategoria
                font.pixelSize: Estilo.global.fontSize.xs
                color: Estilo.global.textSecondary
                elide: Text.ElideRight
            }
        }

        Text {
            Layout.alignment: Qt.AlignTop
            // O instante vem do id do evento, ou seja, do relógio da máquina
            // onde a mudança aconteceu (ver relogio.instante_do_id) — todas as
            // máquinas mostram o mesmo horário para o mesmo evento.
            text: itemHistorico.evento.quando > 0
                ? "há " + itemHistorico.formatarDuracao(itemHistorico.agoraSegundos - itemHistorico.evento.quando)
                : ""
            font.pixelSize: Estilo.global.fontSize.xs
            color: Estilo.global.textSecondary
        }
    }
}
