import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../../components"

// Popup com as alterações de estilo disponíveis para um único campo da
// comanda (negrito, sublinhado, fundo preto, tamanho de fonte) — aberto ao
// clicar num item da lista em EstiloImpressora.qml (abrirPara()).
//
// Reaproveitado para os 14 campos (um popup só, não um por campo): por isso
// os controles (checkboxes e o campo de tamanho de fonte) NÃO usam "checked:
// expressão"/"text: expressão" — o próprio Qt Quick Controls atribui um
// valor literal a essas propriedades ao reagir ao clique/edição do usuário,
// o que quebra a ligação com a expressão original pra sempre (comportamento
// padrão do QML: atribuir a uma propriedade remove o binding dela). Depois
// disso o controle nunca mais refletiria o campo de outra linha aberta em
// seguida. Em vez disso, os valores são lidos e atribuídos explicitamente em
// abrirPara(), toda vez que o popup é aberto.
Popup {
    id: popup

    property var controlador
    property string campoChave: ""
    property string campoRotulo: ""
    // Nível do multiplicador ESC/POS atual (1x a 8x) — não um valor em
    // pixels: ver o bloco "Tamanho da fonte" mais abaixo pro motivo.
    property int nivelFonte: 1

    function abrirPara(chave, rotulo) {
        campoChave = chave;
        campoRotulo = rotulo;
        chkNegrito.checked = controlador.obterAtributo(chave, "negrito");
        chkSublinhado.checked = controlador.obterAtributo(chave, "sublinhado");
        chkFundoPreto.checked = controlador.obterAtributo(chave, "fundo_preto");
        nivelFonte = controlador.multiplicadorFonte(controlador.obterTamanhoFonte(chave));
        open();
    }

    function _definirNivelFonte(nivel) {
        nivelFonte = nivel;
        controlador.definirTamanhoFonteLocal(campoChave, nivel * controlador.tamanhoFontePadrao);
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: Estilo.global.padding.popup
    // Fixada explicitamente: sem isso, o Popup calcula sua largura a partir
    // do implicitWidth do contentItem, que os filhos (Row largura:
    // parent.width) não alimentam de volta a tempo — resultado observado:
    // o popup nascia bem mais estreito que os 320px pedidos no Column
    // abaixo, cortando o título do campo.
    width: Responsivo.larguraPopup(320) + leftPadding + rightPadding
    parent: Overlay.overlay
    anchors.centerIn: parent

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    contentItem: Column {
        spacing: Estilo.global.spacing.xxl
        width: Responsivo.larguraPopup(320)

        Row {
            spacing: Estilo.global.spacing.sm
            width: parent.width

            Icone { nome: "fa6s.pen"; cor: Estilo.screen.config.accent; tamanho: 17; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: popup.campoRotulo
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                elide: Text.ElideRight
                width: parent.width - 30
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle { width: parent.width; height: 1; color: Estilo.global.borderCard }

        // --- Atributos booleanos ---
        // Os três CheckBox fixam implicitWidth/implicitHeight no mesmo 22 do
        // indicador e zeram o padding porque o estilo Basic monta a largura
        // do controle a partir do contentItem (vazio aqui, já que o rótulo é
        // um Text à parte na Row) — só a ALTURA consulta o indicador. Sem
        // isso o controle nascia com 12px de largura (só o padding) por baixo
        // de um quadrado de 22px: o desenho aparecia inteiro, mas a metade
        // direita dele não respondia ao clique.
        Column {
            width: parent.width
            spacing: 14

            Row {
                spacing: Estilo.global.spacing.lg

                CheckBox {
                    id: chkNegrito

                    padding: 0
                    implicitWidth: 22
                    implicitHeight: 22
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: popup.controlador.definirAtributoLocal(popup.campoChave, "negrito", checked)

                    contentItem: Item {}
                    indicator: Rectangle {
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: Estilo.global.radius.xs
                        border.color: chkNegrito.checked ? Estilo.screen.config.accent : Estilo.global.borderStrong
                        border.width: Estilo.global.borderWidth.thick
                        color: chkNegrito.checked ? Estilo.screen.config.accent : "transparent"

                        Icone {
                            nome: "fa6s.check"
                            cor: Estilo.global.textOnAccent
                            tamanho: 13
                            anchors.centerIn: parent
                            visible: chkNegrito.checked
                        }
                    }
                }

                Text {
                    text: "Negrito"
                    font.pixelSize: Estilo.global.fontSize.lg
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                spacing: Estilo.global.spacing.lg

                CheckBox {
                    id: chkSublinhado

                    padding: 0
                    implicitWidth: 22
                    implicitHeight: 22
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: popup.controlador.definirAtributoLocal(popup.campoChave, "sublinhado", checked)

                    contentItem: Item {}
                    indicator: Rectangle {
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: Estilo.global.radius.xs
                        border.color: chkSublinhado.checked ? Estilo.screen.config.accent : Estilo.global.borderStrong
                        border.width: Estilo.global.borderWidth.thick
                        color: chkSublinhado.checked ? Estilo.screen.config.accent : "transparent"

                        Icone {
                            nome: "fa6s.check"
                            cor: Estilo.global.textOnAccent
                            tamanho: 13
                            anchors.centerIn: parent
                            visible: chkSublinhado.checked
                        }
                    }
                }

                Text {
                    text: "Sublinhado"
                    font.pixelSize: Estilo.global.fontSize.lg
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                spacing: Estilo.global.spacing.lg

                CheckBox {
                    id: chkFundoPreto

                    padding: 0
                    implicitWidth: 22
                    implicitHeight: 22
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: popup.controlador.definirAtributoLocal(popup.campoChave, "fundo_preto", checked)

                    contentItem: Item {}
                    indicator: Rectangle {
                        implicitWidth: 22
                        implicitHeight: 22
                        radius: Estilo.global.radius.xs
                        border.color: chkFundoPreto.checked ? Estilo.screen.config.accent : Estilo.global.borderStrong
                        border.width: Estilo.global.borderWidth.thick
                        color: chkFundoPreto.checked ? Estilo.screen.config.accent : "transparent"

                        Icone {
                            nome: "fa6s.check"
                            cor: Estilo.global.textOnAccent
                            tamanho: 13
                            anchors.centerIn: parent
                            visible: chkFundoPreto.checked
                        }
                    }
                }

                Text {
                    text: "Fundo preto"
                    font.pixelSize: Estilo.global.fontSize.lg
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Estilo.global.borderCard }

        // --- Tamanho da fonte ---
        // Um campo livre em pixels dava a falsa impressão de controle
        // contínuo: o ESC/POS só tem 8 multiplicadores inteiros do
        // tamanho normal (1x a 8x), então digitar "25" ou "30" imprimia
        // exatamente do mesmo tamanho (os dois viram 2x) — parecia bug
        // ("só muda pra valores específicos"). Aqui o controle já mostra
        // direto qual dos 8 níveis está selecionado.
        Item {
            width: parent.width
            height: 32

            Text {
                text: "Tamanho da fonte"
                font.pixelSize: Estilo.global.fontSize.lg
                color: Estilo.global.text
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            Row {
                anchors.right: parent.right
                spacing: Estilo.global.spacing.lg

                Button {
                    text: "-"
                    width: 32
                    height: 32
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: popup.nivelFonte > 1
                    onClicked: popup._definirNivelFonte(popup.nivelFonte - 1)

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                        border.color: Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                        opacity: parent.enabled ? 1 : Estilo.global.opacity.disabled
                    }
                }

                Text {
                    width: 60
                    text: popup.nivelFonte === 1 ? "Normal" : (popup.nivelFonte + "x")
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Estilo.global.fontSize.lg
                    font.bold: true
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    text: "+"
                    width: 32
                    height: 32
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: popup.nivelFonte < 8
                    onClicked: popup._definirNivelFonte(popup.nivelFonte + 1)

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.global.surfacePressed : Estilo.global.surface
                        border.color: Estilo.global.border
                        border.width: Estilo.global.borderWidth.hairline
                        opacity: parent.enabled ? 1 : Estilo.global.opacity.disabled
                    }
                }
            }
        }

        // --- Fechar ---
        Row {
            anchors.right: parent.right

            Button {
                id: btnFechar

                text: "Fechar"
                padding: Estilo.global.padding.md
                onClicked: popup.close()

                contentItem: Text {
                    text: btnFechar.text
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: parent.down ? Estilo.screen.config.pressed : (parent.hovered ? Estilo.screen.config.hover : Estilo.screen.config.base)
                }
            }
        }
    }
}
