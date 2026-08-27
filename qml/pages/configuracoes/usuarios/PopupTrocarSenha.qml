import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../../components"

// Troca a senha do dono (ver services/rede/senhaDono.py). Só alcançável com o
// cadastro já destrancado — mas ainda assim EXIGE a senha atual, e não é
// redundância: o destrave dura cinco minutos (ver
// _DURACAO_DESTRAVE_SEGUNDOS), então sem esta segunda checagem bastaria passar
// pela máquina no minuto errado para tomar o cadastro do dono trocando a senha
// por outra. Quem confere isso de verdade é o controller; aqui só se pede o
// campo.
//
// Popup, e não painel como PainelTranca.qml: aqui a tela por baixo está
// destrancada e continua fazendo sentido — é uma ação pontual sobre ela, o
// mesmo papel de PopupUsuario.qml.
Popup {
    id: popupTrocarSenha

    property string erro: ""

    signal trocada

    function abrir() {
        popupTrocarSenha.erro = "";
        inputAtual.text = "";
        inputNova.text = "";
        inputRepetir.text = "";
        open();
    }

    function _confirmar() {
        if (inputNova.text !== inputRepetir.text) {
            popupTrocarSenha.erro = "As duas senhas novas não são iguais.";
            inputRepetir.text = "";
            inputRepetir.forceActiveFocus();
            return;
        }

        var resultado = usuariosController.definirSenhaDono(inputAtual.text, inputNova.text);
        if (resultado && resultado.ok) {
            popupTrocarSenha.trocada();
            popupTrocarSenha.close();
            return;
        }

        if (resultado && resultado.erro === "senha_atual_incorreta") {
            popupTrocarSenha.erro = "A senha atual está errada.";
            inputAtual.text = "";
            inputAtual.forceActiveFocus();
            return;
        }

        if (resultado && resultado.erro === "senha_curta") {
            popupTrocarSenha.erro = "A senha nova precisa ter pelo menos " + (resultado.tamanhoMinimo || 6) + " caracteres.";
            return;
        }

        popupTrocarSenha.erro = "Não foi possível trocar a senha.";
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    onOpened: inputAtual.forceActiveFocus()

    width: Math.min(400, parent ? parent.width * 0.9 : 400)

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
                nome: "fa6s.key"
                cor: Estilo.global.text
                tamanho: Estilo.global.fontSize.title
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Trocar senha do dono"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            Layout.fillWidth: true
            text: "A senha nova passa a valer em todas as máquinas da malha, e tranca "
                + "as que estiverem destrancadas agora com a senha antiga.";
            font.pixelSize: Estilo.global.fontSize.sm
            color: Estilo.global.textSecondary
            wrapMode: Text.Wrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: "Senha atual"
                font.pixelSize: Estilo.global.fontSize.sm
                font.bold: true
                color: Estilo.global.textSecondary
            }

            CampoTexto {
                id: inputAtual

                Layout.fillWidth: true
                corDestaque: Estilo.screen.config.accent
                echoMode: TextInput.Password
                passwordCharacter: "•"
                KeyNavigation.tab: inputNova
                Keys.onReturnPressed: inputNova.forceActiveFocus()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: "Senha nova"
                font.pixelSize: Estilo.global.fontSize.sm
                font.bold: true
                color: Estilo.global.textSecondary
            }

            CampoTexto {
                id: inputNova

                Layout.fillWidth: true
                corDestaque: Estilo.screen.config.accent
                echoMode: TextInput.Password
                passwordCharacter: "•"
                KeyNavigation.tab: inputRepetir
                Keys.onReturnPressed: inputRepetir.forceActiveFocus()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                text: "Repita a senha nova"
                font.pixelSize: Estilo.global.fontSize.sm
                font.bold: true
                color: Estilo.global.textSecondary
            }

            CampoTexto {
                id: inputRepetir

                Layout.fillWidth: true
                corDestaque: Estilo.screen.config.accent
                echoMode: TextInput.Password
                passwordCharacter: "•"
                Keys.onReturnPressed: popupTrocarSenha._confirmar()
            }
        }

        Text {
            Layout.fillWidth: true
            visible: popupTrocarSenha.erro !== ""
            text: popupTrocarSenha.erro
            font.pixelSize: Estilo.global.fontSize.sm
            color: Estilo.status.error.content
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Estilo.global.spacing.lg

            Button {
                id: btnCancelarTroca

                Layout.fillWidth: true
                padding: Estilo.global.padding.md
                onClicked: popupTrocarSenha.close()

                contentItem: Text {
                    text: "Cancelar"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnCancelarTroca.down ? Estilo.action.neutral.pressed : (btnCancelarTroca.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                }
            }

            Button {
                id: btnConfirmarTroca

                Layout.fillWidth: true
                padding: Estilo.global.padding.md
                onClicked: popupTrocarSenha._confirmar()

                contentItem: Text {
                    text: "Trocar"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnConfirmarTroca.down ? Estilo.screen.config.pressed : (btnConfirmarTroca.hovered ? Estilo.screen.config.hover : Estilo.screen.config.accent)
                }
            }
        }
    }
}
