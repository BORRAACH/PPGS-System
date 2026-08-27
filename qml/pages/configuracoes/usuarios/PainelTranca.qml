import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../../components"

// A tranca do cadastro de usuários: a senha do dono (ver
// services/rede/senhaDono.py e controllers/usuariosController.py).
//
// PAINEL, e não popup como PopupAutorizacao. O guarda de dois dígitos
// interrompe uma ação que já estava em curso — apagar uma comanda —, então
// ele é um modal que aparece e some. Aqui é o contrário: a tela inteira está
// trancada, e enquanto estiver não há nada por baixo para olhar. Um popup
// sobre uma lista de códigos visível seria pior que inútil — bastaria fechá-lo
// para ler o que ele deveria estar escondendo.
//
// Dois modos no mesmo painel, decididos por `definindo`:
//
// - DEFINIR (não há senha ainda) — primeira abertura numa instalação nova, ou
//   numa máquina que ainda não recebeu o registro da malha. Enquanto não
//   houver senha, o cadastro não aparece: a tela fica NESTE painel até a
//   senha ser escolhida (ver UsuariosController.cadastroDestrancado), em vez
//   de abrir o cadastro e deixar a porta encostada.
// - DESTRANCAR (já há senha) — o caso de sempre.
ColumnLayout {
    id: painelTranca

    // Emitido quando a senha é aceita (ou acabou de ser definida). A seção
    // reage mostrando o cadastro.
    signal destrancado

    property bool definindo: false
    property string erro: ""

    property int _tentativas: 0
    property bool _travado: false

    readonly property int _tentativasAteTravar: 3
    readonly property color corDestaque: Estilo.screen.config.accent

    // Chamado pela seção toda vez que ela volta à vista: uma máquina pode ter
    // aprendido a senha da malha desde a última abertura, e o painel precisa
    // trocar de modo sem depender de o app ser reiniciado.
    function recomecar() {
        painelTranca.definindo = !usuariosController.senhaDonoDefinida();
        painelTranca.erro = "";
        painelTranca._tentativas = 0;
        painelTranca._travado = false;
        inputSenha.text = "";
        inputConfirmar.text = "";
    }

    function _confirmar() {
        if (painelTranca._travado)
            return;

        if (painelTranca.definindo) {
            painelTranca._definir();
            return;
        }

        var resultado = usuariosController.destrancarCadastro(inputSenha.text);
        if (resultado && resultado.destrancado) {
            inputSenha.text = "";
            painelTranca.erro = "";
            painelTranca.destrancado();
            return;
        }

        // Uma senha só é conferida por PBKDF2 (ver senhaDono.py), o que já
        // custa uma fração de segundo por tentativa. O freio aqui é pela mesma
        // razão do de PopupAutorizacao: torna insistir lento e visível para
        // quem está ao lado, não impossível.
        painelTranca._tentativas += 1;
        painelTranca.erro = "Senha incorreta.";
        inputSenha.text = "";
        inputSenha.forceActiveFocus();

        if (painelTranca._tentativas >= painelTranca._tentativasAteTravar) {
            painelTranca._travado = true;
            painelTranca.erro = "Senha incorreta. Aguarde alguns segundos.";
            destravar.restart();
        }
    }

    function _definir() {
        if (inputSenha.text !== inputConfirmar.text) {
            painelTranca.erro = "As duas senhas não são iguais.";
            inputConfirmar.text = "";
            inputConfirmar.forceActiveFocus();
            return;
        }

        // Sem senha atual: este modo só existe quando ainda não há senha
        // nenhuma. Trocar uma senha existente é outro caminho, e exige a
        // atual (ver PopupTrocarSenha.qml).
        var resultado = usuariosController.definirSenhaDono("", inputSenha.text);
        if (resultado && resultado.ok) {
            inputSenha.text = "";
            inputConfirmar.text = "";
            painelTranca.erro = "";
            painelTranca.definindo = false;
            painelTranca.destrancado();
            return;
        }

        if (resultado && resultado.erro === "senha_curta") {
            painelTranca.erro = "A senha precisa ter pelo menos " + (resultado.tamanhoMinimo || 6) + " caracteres.";
            return;
        }

        // A senha chegou da malha entre a abertura desta tela e o clique: o
        // controller recusa porque trocar uma senha existente exige a atual
        // (ver definirSenhaDono), e "não foi possível" não diria o que houve.
        // Trocar de modo aqui é o que impede a pessoa de insistir num
        // formulário que já não é o certo.
        if (resultado && resultado.erro === "senha_atual_incorreta") {
            painelTranca.recomecar();
            painelTranca.erro = "Outra máquina da malha já tem senha definida — digite a senha do dono.";
            inputSenha.forceActiveFocus();
            return;
        }

        painelTranca.erro = "Não foi possível definir a senha.";
    }

    spacing: Estilo.global.spacing.lg

    Timer {
        id: destravar

        interval: 5000
        onTriggered: {
            painelTranca._travado = false;
            painelTranca._tentativas = 0;
            painelTranca.erro = "";
            inputSenha.forceActiveFocus();
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: conteudoTranca.implicitHeight + Estilo.global.padding.xl * 2
        radius: Estilo.global.radius.md
        color: Estilo.global.surface
        border.color: Estilo.global.borderCard
        border.width: Estilo.global.borderWidth.hairline

        ColumnLayout {
            id: conteudoTranca

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Estilo.global.padding.xl
            spacing: Estilo.global.spacing.lg

            Row {
                spacing: Estilo.global.spacing.sm

                Icone {
                    nome: painelTranca.definindo ? "fa6s.key" : "fa6s.lock"
                    cor: painelTranca.corDestaque
                    tamanho: Estilo.global.fontSize.title
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: painelTranca.definindo ? "Defina a senha do dono" : "Cadastro trancado"
                    font.pixelSize: Estilo.global.fontSize.xl
                    font.bold: true
                    color: Estilo.global.text
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                Layout.fillWidth: true
                text: painelTranca.definindo
                    ? "Esta máquina ainda não tem senha do dono: o cadastro só abre depois "
                      + "que ela existir, e até lá o app não pede o código de dois dígitos para "
                      + "imprimir, lançar ou apagar comanda. A senha vale em todas as máquinas "
                      + "da malha e não é a mesma coisa que o código — ela nunca é digitada no "
                      + "balcão. Se outra máquina já tiver senha, ela chega pela malha e esta "
                      + "tela troca sozinha para pedi-la."
                    : "Cadastrar, editar ou remover usuários exige a senha do dono. "
                      + "Ela não é o código de dois dígitos.";
                font.pixelSize: Estilo.global.fontSize.sm
                color: Estilo.global.textSecondary
                wrapMode: Text.Wrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: painelTranca.definindo ? "Nova senha" : "Senha do dono"
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                CampoTexto {
                    id: inputSenha

                    Layout.fillWidth: true
                    Layout.maximumWidth: 360
                    enabled: !painelTranca._travado
                    corDestaque: painelTranca.corDestaque
                    // Sem placeholder com exemplo de senha, e sem
                    // inputMethodHints de dígitos: aqui vale o Unicode inteiro
                    // — maiúsculas, minúsculas, símbolos e acentos (ver o topo
                    // de services/rede/senhaDono.py).
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    KeyNavigation.tab: painelTranca.definindo ? inputConfirmar : null
                    Keys.onReturnPressed: painelTranca.definindo
                        ? inputConfirmar.forceActiveFocus()
                        : painelTranca._confirmar()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: painelTranca.definindo
                spacing: 4

                Text {
                    text: "Repita a senha"
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                CampoTexto {
                    id: inputConfirmar

                    Layout.fillWidth: true
                    Layout.maximumWidth: 360
                    corDestaque: painelTranca.corDestaque
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    Keys.onReturnPressed: painelTranca._confirmar()
                }
            }

            // Dito na hora de escolher a senha, e não escondido num manual: a
            // recuperação é manual e trabalhosa de propósito (ver
            // services/rede/senhaDono.py), e quem só descobre isso no dia em
            // que esqueceu a senha descobre tarde demais.
            Text {
                Layout.fillWidth: true
                visible: painelTranca.definindo
                text: "Anote a senha em lugar seguro. Não há como recuperá-la pelo app: "
                    + "esquecê-la exige apagar o arquivo da senha em todas as máquinas.";
                font.pixelSize: Estilo.global.fontSize.xs
                color: Estilo.status.warning.content
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                visible: painelTranca.erro !== ""
                text: painelTranca.erro
                font.pixelSize: Estilo.global.fontSize.sm
                color: Estilo.status.error.content
                wrapMode: Text.Wrap
            }

            Button {
                id: btnDestrancar

                Layout.maximumWidth: 360
                Layout.fillWidth: true
                padding: Estilo.global.padding.md
                enabled: !painelTranca._travado
                onClicked: painelTranca._confirmar()

                contentItem: Row {
                    spacing: Estilo.global.spacing.xs
                    anchors.centerIn: parent

                    Icone {
                        nome: painelTranca.definindo ? "fa6s.key" : "fa6s.lock-open"
                        cor: Estilo.global.textOnAccent
                        tamanho: Estilo.global.fontSize.md
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: painelTranca.definindo ? "Definir senha" : "Destrancar"
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: !btnDestrancar.enabled
                        ? Estilo.global.inputDisabled
                        : (btnDestrancar.down ? Estilo.screen.config.pressed
                                              : (btnDestrancar.hovered ? Estilo.screen.config.hover : painelTranca.corDestaque))
                }
            }
        }
    }
}
