import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../../components"

// Pede a senha do dono para UMA gravação no cadastro de usuários — cada
// cadastro, cada edição e cada remoção passa por aqui (ver
// UsuariosController._autorizar_escrita).
//
// É o irmão de components/PopupAutorizacao.qml, com a mesma forma (a ação vai
// num callback em vez de num sinal, pelo motivo documentado lá) e um segredo
// diferente: aquele pede o código de dois dígitos, que é assinatura e é
// digitado no balcão à vista de todos; este pede a senha do dono, que nunca é.
//
// NÃO é ele quem libera nada. A senha digitada é repassada ao callback, que a
// entrega ao controller — quem confere de verdade é o Python, e este popup só
// reage ao que ele responder. Um popup que conferisse por conta própria e
// chamasse um slot desprotegido seria teatro: bastaria chamar o slot direto.
Popup {
    id: popupSenhaDono

    objectName: "popupSenhaDono"

    // Rótulo legível do que está prestes a acontecer ("Cadastrar usuário").
    property string acao: ""
    property string erro: ""

    // Continuação, guardada só enquanto o popup está aberto (ver onClosed).
    // Recebe a senha digitada e devolve true quando a gravação passou; false
    // diz "senha recusada", e aí o popup fica aberto para outra tentativa.
    property var _aoConfirmar: null

    property int _tentativas: 0
    property bool _travado: false

    readonly property int _tentativasAteTravar: 3

    function solicitar(acao, aoConfirmar) {
        popupSenhaDono.acao = acao || "";

        // Bootstrap: sem senha definida o app não pode se trancar fora do
        // próprio cadastro — a primeira pessoa a abrir a tela não teria como
        // cadastrar ninguém. Passa direto, e o controller registra
        // "usuarios_sem_senha" no histórico (ver _autorizar_escrita).
        if (!usuariosController.senhaDonoDefinida()) {
            if (aoConfirmar)
                aoConfirmar("");
            return;
        }

        popupSenhaDono._aoConfirmar = aoConfirmar || null;
        popupSenhaDono.erro = "";
        popupSenhaDono._tentativas = 0;
        popupSenhaDono._travado = false;
        campoSenha.text = "";
        open();
    }

    function _confirmar() {
        if (popupSenhaDono._travado || !popupSenhaDono._aoConfirmar)
            return;

        if (popupSenhaDono._aoConfirmar(campoSenha.text) !== false) {
            // Gravou (ou falhou por outro motivo, que quem chamou mostra na
            // ficha) — de todo jeito a senha estava certa e o gate cumpriu.
            popupSenhaDono.close();
            return;
        }

        // A senha já custa um PBKDF2 no Python (ver senhaDono.conferir), o que
        // por si só torna a tentativa lenta. O freio aqui é pela mesma razão do
        // de PopupAutorizacao: torna insistir visível para quem está ao lado.
        popupSenhaDono._tentativas += 1;
        popupSenhaDono.erro = "Senha incorreta.";
        campoSenha.text = "";
        campoSenha.forceActiveFocus();

        if (popupSenhaDono._tentativas >= popupSenhaDono._tentativasAteTravar) {
            popupSenhaDono._travado = true;
            popupSenhaDono.erro = "Senha incorreta. Aguarde alguns segundos.";
            destravar.restart();
        }
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    onOpened: campoSenha.forceActiveFocus()
    onClosed: {
        // A continuação não sobrevive ao fechamento: sem isto, um Esc seguido
        // de outra ação reaproveitaria o callback da anterior.
        popupSenhaDono._aoConfirmar = null;
        campoSenha.text = "";
        destravar.stop();
    }

    width: Math.min(380, parent ? parent.width * 0.9 : 380)

    Timer {
        id: destravar

        interval: 5000
        onTriggered: {
            popupSenhaDono._travado = false;
            popupSenhaDono._tentativas = 0;
            popupSenhaDono.erro = "";
            campoSenha.forceActiveFocus();
        }
    }

    Overlay.modal: Rectangle {
        color: Estilo.global.overlay
    }

    background: Rectangle {
        radius: Estilo.global.radius.xl
        color: Estilo.global.background
        border.color: Estilo.global.borderCard
    }

    contentItem: ColumnLayout {
        spacing: Estilo.global.spacing.xl

        Row {
            spacing: Estilo.global.spacing.sm

            Icone {
                nome: "fa6s.lock"
                cor: Estilo.global.text
                tamanho: Estilo.global.fontSize.title
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Senha do dono"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            Layout.fillWidth: true
            text: popupSenhaDono.acao !== ""
                ? popupSenhaDono.acao + " exige a senha do dono."
                : "Esta alteração exige a senha do dono."
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            wrapMode: Text.Wrap
        }

        CampoTexto {
            id: campoSenha

            objectName: "campoSenhaDono"

            Layout.fillWidth: true
            enabled: !popupSenhaDono._travado
            corDestaque: Estilo.screen.config.accent
            echoMode: TextInput.Password
            passwordCharacter: "•"
            Keys.onReturnPressed: popupSenhaDono._confirmar()
        }

        Text {
            Layout.fillWidth: true
            visible: popupSenhaDono.erro !== ""
            text: popupSenhaDono.erro
            font.pixelSize: Estilo.global.fontSize.sm
            color: Estilo.status.error.content
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Estilo.global.spacing.lg

            Button {
                id: btnCancelarSenha

                Layout.fillWidth: true
                padding: Estilo.global.padding.md
                onClicked: popupSenhaDono.close()

                contentItem: Text {
                    text: "Cancelar"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnCancelarSenha.down ? Estilo.action.neutral.pressed : (btnCancelarSenha.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                }
            }

            Button {
                id: btnConfirmarSenha

                Layout.fillWidth: true
                padding: Estilo.global.padding.md
                enabled: !popupSenhaDono._travado && campoSenha.text !== ""
                onClicked: popupSenhaDono._confirmar()

                contentItem: Text {
                    text: "Confirmar"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    opacity: btnConfirmarSenha.enabled ? 1 : Estilo.global.opacity.disabled
                    color: btnConfirmarSenha.down ? Estilo.screen.config.pressed : (btnConfirmarSenha.hovered ? Estilo.screen.config.hover : Estilo.screen.config.accent)
                }
            }
        }
    }
}
