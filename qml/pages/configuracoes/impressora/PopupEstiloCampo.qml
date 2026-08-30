import QtQuick
import QtQuick.Controls
import estilo 1.0
import "../../../components"

// Popup com as alterações de estilo disponíveis para os campos SELECIONADOS
// da comanda (negrito, sublinhado, fundo preto, tamanho de fonte) — aberto por
// EstiloImpressora.abrirEstiloDaSelecao().
//
// Trabalha sobre uma LISTA de campos, não um só: estilizar quinze campos um a
// um era o trabalho que a tela dava, e com Ctrl/Shift+clique dá para pegar
// vários e ligar o negrito de todos numa tacada. Um campo só é o caso de uma
// lista de tamanho um — não há dois caminhos aqui.
//
// Quando os campos escolhidos DISCORDAM num atributo (uns em negrito, outros
// não), o controle mostra "misto" em vez de fingir um valor comum. Clicar nele
// resolve a divergência: todos passam a valer o que foi clicado.
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
    // Os campos que este popup está editando. Sempre uma lista, mesmo com um
    // campo só.
    property var campoChaves: []
    property string campoRotulo: ""
    // Atributos em que os campos escolhidos discordam entre si — {atributo:
    // true}. O que está aqui aparece como "misto" na tela.
    property var mistos: ({})
    // Nível do multiplicador ESC/POS atual (1x a 8x) e o tamanho em pixels.
    // Qual dos dois o popup mostra depende de quem vai desenhar a comanda —
    // ver o bloco "Tamanho da fonte" mais abaixo.
    property int nivelFonte: 1
    property int tamanhoPx: 24
    // Quando há uma fonte escolhida, quem desenha a comanda somos nós, e o
    // tamanho deixa de estar preso aos 8 multiplicadores do ESC/POS.
    readonly property bool tamanhoEmPixels: !!popup.controlador && popup.controlador.fonteImpressao !== ""

    // `chaves` aceita uma lista ou uma string solta — o segundo caso existe
    // para quem chama com um campo só não precisar embrulhá-lo.
    function abrirPara(chaves, rotulo) {
        popup.campoChaves = (typeof chaves === "string") ? [chaves] : (chaves || []);
        if (popup.campoChaves.length === 0)
            return;

        popup.campoRotulo = rotulo;

        var divergentes = {};
        chkNegrito.checked = popup._valorComum("negrito", divergentes);
        chkSublinhado.checked = popup._valorComum("sublinhado", divergentes);
        chkFundoPreto.checked = popup._valorComum("fundo_preto", divergentes);

        var nivel = popup._nivelComum(divergentes);
        popup.nivelFonte = nivel;
        popup.tamanhoPx = popup.controlador.obterTamanhoFonte(popup.campoChaves[0]);
        campoTamanhoPx.text = popup.tamanhoPx;
        popup.mistos = divergentes;
        open();
    }

    // O valor do atributo quando todos os campos concordam. Discordando,
    // devolve o do PRIMEIRO e marca o atributo como misto — o primeiro porque
    // é o campo em que a pessoa clicou primeiro, o que torna o estado inicial
    // previsível em vez de arbitrário.
    function _valorComum(atributo, divergentes) {
        var primeiro = !!popup.controlador.obterAtributo(popup.campoChaves[0], atributo);
        for (var i = 1; i < popup.campoChaves.length; i++) {
            if (!!popup.controlador.obterAtributo(popup.campoChaves[i], atributo) !== primeiro) {
                divergentes[atributo] = true;
                return primeiro;
            }
        }
        return primeiro;
    }

    function _nivelComum(divergentes) {
        var primeiro = popup.controlador.multiplicadorFonte(
            popup.controlador.obterTamanhoFonte(popup.campoChaves[0]));
        for (var i = 1; i < popup.campoChaves.length; i++) {
            var nivel = popup.controlador.multiplicadorFonte(
                popup.controlador.obterTamanhoFonte(popup.campoChaves[i]));
            if (nivel !== primeiro) {
                divergentes["tamanho_fonte"] = true;
                return primeiro;
            }
        }
        return primeiro;
    }

    // Aplicar resolve a divergência: o atributo deixa de ser misto porque
    // todos passam a valer o mesmo.
    function _definirAtributo(atributo, valor) {
        for (var i = 0; i < popup.campoChaves.length; i++)
            popup.controlador.definirAtributoLocal(popup.campoChaves[i], atributo, valor);
        popup._limparMisto(atributo);
    }

    function _definirNivelFonte(nivel) {
        popup.nivelFonte = nivel;
        popup.tamanhoPx = nivel * popup.controlador.tamanhoFontePadrao;
        campoTamanhoPx.text = popup.tamanhoPx;
        for (var i = 0; i < popup.campoChaves.length; i++)
            popup.controlador.definirTamanhoFonteLocal(popup.campoChaves[i], popup.tamanhoPx);

        popup._limparMisto("tamanho_fonte");
    }

    function _definirTamanhoPx(px) {
        // Vazio ou não numérico (o campo aceita ser apagado enquanto se
        // digita) volta pro tamanho que já valia, em vez de virar o mínimo.
        var alvo = isNaN(px) ? popup.tamanhoPx : px;
        var limitado = Math.max(popup.controlador.tamanhoFonteMin,
                                Math.min(popup.controlador.tamanhoFonteMax, Math.round(alvo)));

        popup.tamanhoPx = limitado;
        // Reescrito mesmo quando o valor não mudou: é o que devolve o campo
        // ao normal depois de alguém digitar "999" ou deixá-lo vazio.
        campoTamanhoPx.text = limitado;
        for (var i = 0; i < popup.campoChaves.length; i++)
            popup.controlador.definirTamanhoFonteLocal(popup.campoChaves[i], limitado);

        popup.nivelFonte = popup.controlador.multiplicadorFonte(limitado);
        popup._limparMisto("tamanho_fonte");
    }

    function _limparMisto(atributo) {
        if (!popup.mistos[atributo])
            return;

        // Cópia, não mutação: `mistos` é um objeto JS comum, e mutar não
        // emite sinal nenhum — os rótulos "misto" ficariam na tela depois de
        // a divergência ter sido resolvida.
        var restantes = {};
        for (var chave in popup.mistos) {
            if (chave !== atributo)
                restantes[chave] = true;
        }
        popup.mistos = restantes;
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
                    onClicked: popup._definirAtributo("negrito", checked)

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

                // Os campos escolhidos discordam neste atributo. Clicar
                // resolve: todos passam a valer o que foi clicado.
                Text {
                    visible: popup.mistos["negrito"] === true
                    text: "misto"
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.italic: true
                    color: Estilo.global.textSecondary
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
                    onClicked: popup._definirAtributo("sublinhado", checked)

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

                // Os campos escolhidos discordam neste atributo. Clicar
                // resolve: todos passam a valer o que foi clicado.
                Text {
                    visible: popup.mistos["sublinhado"] === true
                    text: "misto"
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.italic: true
                    color: Estilo.global.textSecondary
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
                    onClicked: popup._definirAtributo("fundo_preto", checked)

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

                // Os campos escolhidos discordam neste atributo. Clicar
                // resolve: todos passam a valer o que foi clicado.
                Text {
                    visible: popup.mistos["fundo_preto"] === true
                    text: "misto"
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.italic: true
                    color: Estilo.global.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Estilo.global.borderCard }

        // --- Tamanho da fonte ---
        // DOIS controles, e qual aparece depende de quem vai desenhar a
        // comanda.
        //
        // Quando é a impressora (nenhuma fonte escolhida), são os 8 níveis.
        // Um campo livre em pixels aqui dava a falsa impressão de controle
        // contínuo: o ESC/POS só tem multiplicadores inteiros do tamanho
        // normal (1x a 8x), então digitar "25" ou "30" imprimia exatamente do
        // mesmo tamanho (os dois viram 2x) — parecia bug ("só muda pra
        // valores específicos"). O controle de nível mostra direto o que vai
        // sair.
        //
        // Quando somos nós que desenhamos (uma fonte escolhida, ver
        // services/comandaImagemService.py), esse teto não existe: o tamanho
        // vai em pixels até o papel, e aí o campo livre passa a dizer a
        // verdade — 30 imprime 30. É a mesma razão de antes, aplicada ao
        // caso novo, e não uma volta atrás.
        Item {
            width: parent.width
            height: 32

            Row {
                spacing: Estilo.global.spacing.sm
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: "Tamanho da fonte"
                    font.pixelSize: Estilo.global.fontSize.lg
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    visible: popup.mistos["tamanho_fonte"] === true
                    text: "misto"
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.italic: true
                    color: Estilo.global.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // --- Em pixels: só quando somos nós que desenhamos ---
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Estilo.global.spacing.md
                visible: popup.tamanhoEmPixels

                TextField {
                    id: campoTamanhoPx

                    width: 80
                    height: 32
                    horizontalAlignment: TextInput.AlignHCenter
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator {
                        bottom: 1
                        top: 999
                    }
                    font.pixelSize: Estilo.global.fontSize.lg
                    font.bold: true
                    color: Estilo.global.textInput
                    anchors.verticalCenter: parent.verticalCenter
                    // Só ao confirmar/sair do campo, nunca a cada tecla: com
                    // onTextChanged, apagar "48" pra digitar "30" passaria por
                    // "4" e o campo já teria sido limitado ao mínimo antes de
                    // a pessoa terminar de digitar.
                    onEditingFinished: popup._definirTamanhoPx(parseInt(text, 10))

                    background: Rectangle {
                        radius: Estilo.global.radius.md
                        color: Estilo.global.inputBackground
                        border.color: campoTamanhoPx.activeFocus ? Estilo.screen.config.accent : Estilo.global.border
                        border.width: campoTamanhoPx.activeFocus ? 2 : 1
                    }
                }

                Text {
                    text: "px"
                    font.pixelSize: Estilo.global.fontSize.md
                    color: Estilo.global.textSecondary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // --- Em níveis: quando quem desenha é a impressora ---
            Row {
                anchors.right: parent.right
                spacing: Estilo.global.spacing.lg
                visible: !popup.tamanhoEmPixels

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
