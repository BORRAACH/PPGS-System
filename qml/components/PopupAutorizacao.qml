import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0

// Guarda das ações destrutivas: pede o código de dois dígitos de um usuário
// cadastrado (ver services/rede/usuarios.py) e só então deixa a ação
// acontecer. Quem autorizou fica registrado no histórico da malha — é
// UsuariosController.validarCodigo que confere e anota, na mesma chamada,
// justamente para não existir caminho que libere sem registrar.
//
// Fica em components/ (e não em pages/consulta ou pages/fechamento) porque
// as duas telas usam — mesmo critério de EdicaoComanda.js.
//
// COMO SE USA. Envolve-se a ação numa função, em vez de chamá-la direto:
//
//     popupAutorizacao.solicitar("Apagar comanda", arquivo, function () {
//         consultaController.apagarComanda(arquivo);
//     });
//
// A continuação vai num callback (property var) em vez de um sinal porque o
// mesmo guarda serve chamadores com continuações diferentes: com sinal, cada
// tela precisaria de um handler e de um switch na string da ação para saber o
// que retomar — e um call site que esquecesse de filtrar executaria a ação de
// outro. O padrão de função guardada em property var já existe aqui, em
// components/CargaDiferida.qml ("tarefa").
//
// O QUE ELE NÃO É. Dois dígitos são cem combinações, e a malha não autentica
// ninguém (ver o topo de services/rede/usuarios.py). Isto identifica quem
// mexeu e obriga um ato deliberado antes de uma edição destrutiva; não
// segura quem estiver decidido a insistir. O freio de tentativas abaixo é
// pelo mesmo motivo: torna insistir lento e visível para os colegas ao lado,
// não impossível.
Popup {
    id: popupAutorizacao

    // Nomeado por padrão (as instâncias não precisam repetir): deixa o guarda
    // alcançável de fora para inspeção e teste, como já vale para o campo do
    // código lá embaixo.
    objectName: "popupAutorizacao"

    // Rótulo legível da ação ("Apagar comanda") e o que ela atinge (o nome do
    // arquivo da comanda) — os dois vão para a linha do histórico.
    property string acao: ""
    property string alvo: ""

    // Continuação, guardada só enquanto o popup está aberto (ver onClosed).
    property var _aoAutorizar: null
    // Preenchido quando duas pessoas usam o mesmo código: em vez de escolher
    // por conta própria (e carimbar a ação no nome errado, que é justamente o
    // dano que este guarda existe para evitar), o popup pergunta qual é.
    property var _candidatos: []
    property string _erro: ""
    property int _tentativas: 0
    property bool _travado: false

    readonly property int _tentativasAteTravar: 3

    // Chamado no lugar da ação protegida. `aoAutorizar` recebe o usuário que
    // liberou ({nome, codigo, id}) e só roda se a autorização passar.
    function solicitar(acao, alvo, aoAutorizar) {
        popupAutorizacao.acao = acao || "";
        popupAutorizacao.alvo = alvo || "";

        // Bootstrap: enquanto a tranca não estiver ligada nesta máquina, o app
        // não pode se trancar para fora das próprias funções. São dois casos, e
        // quem decide é o controller (ver UsuariosController.guardaAtivo):
        // ninguém cadastrado ainda, ou nenhuma senha do dono definida.
        //
        // O segundo é o que derrubava a segunda máquina da casa: ela aprendia
        // o CADASTRO pela malha e passava a exigir um código de dois dígitos
        // que ninguém daquele balcão tinha — sem imprimir, sem lançar comanda,
        // e com o conserto (cadastrar alguém dali) do outro lado da mesma
        // tranca. A ação passa direto, e validarCodigo registra a liberação no
        // histórico: o buraco existe, mas nunca em silêncio.
        if (!usuariosController.guardaAtivo()) {
            usuariosController.validarCodigo("", popupAutorizacao.acao, popupAutorizacao.alvo);
            if (aoAutorizar)
                aoAutorizar({ "nome": "", "semCadastro": true });
            return;
        }

        popupAutorizacao._aoAutorizar = aoAutorizar || null;
        popupAutorizacao._candidatos = [];
        popupAutorizacao._erro = "";
        popupAutorizacao._tentativas = 0;
        popupAutorizacao._travado = false;
        campoCodigo.text = "";
        open();
    }

    function _confirmar() {
        if (popupAutorizacao._travado)
            return;

        var resultado = usuariosController.validarCodigo(campoCodigo.text, popupAutorizacao.acao, popupAutorizacao.alvo);

        if (resultado && resultado.autorizado) {
            popupAutorizacao._concluir(resultado);
            return;
        }

        if (resultado && resultado.erro === "codigo_ambiguo") {
            // Não conta como tentativa errada: o código está certo, quem
            // cadastrou é que repetiu o número em duas máquinas separadas.
            popupAutorizacao._candidatos = resultado.candidatos || [];
            popupAutorizacao._erro = "";
            return;
        }

        popupAutorizacao._tentativas += 1;
        popupAutorizacao._erro = "Código não encontrado.";
        campoCodigo.text = "";
        campoCodigo.forceActiveFocus();

        if (popupAutorizacao._tentativas >= popupAutorizacao._tentativasAteTravar) {
            popupAutorizacao._travado = true;
            popupAutorizacao._erro = "Código não encontrado. Aguarde alguns segundos.";
            destravar.restart();
        }
    }

    // Volta do desempate: a pessoa escolheu qual dos dois homônimos de código
    // é ela.
    function _autorizarComo(idUsuario) {
        var resultado = usuariosController.autorizarComo(idUsuario, popupAutorizacao.acao, popupAutorizacao.alvo);
        if (resultado && resultado.autorizado)
            popupAutorizacao._concluir(resultado);
        else
            popupAutorizacao._erro = "Esse usuário não existe mais.";
    }

    function _concluir(usuario) {
        // A continuação é capturada ANTES do close(): onClosed zera
        // _aoAutorizar, e ler a propriedade depois traria null. Fechar
        // primeiro é o que impede o popup de reaparecer por cima do
        // formulário que a edição empurra na pilha — mesmo cuidado
        // documentado em PopupFechamentoRapido._abrirEdicao.
        var seguir = popupAutorizacao._aoAutorizar;
        popupAutorizacao.close();
        if (seguir)
            seguir(usuario);
    }

    modal: true
    focus: true
    // Sem CloseOnPressOutside: é formulário, e o dialeto da casa para
    // formulário é só Esc (ver PopupExtras.qml).
    closePolicy: Popup.CloseOnEscape
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    onOpened: campoCodigo.forceActiveFocus()

    // Não deixa closure nem código digitado pendurados depois de fechar —
    // inclusive quando se sai pelo Esc, que não passa por _concluir.
    onClosed: {
        popupAutorizacao._aoAutorizar = null;
        popupAutorizacao._candidatos = [];
        popupAutorizacao._erro = "";
        popupAutorizacao._tentativas = 0;
        popupAutorizacao._travado = false;
        campoCodigo.text = "";
        destravar.stop();
    }

    width: Math.min(380, parent ? parent.width * 0.9 : 380)

    Timer {
        id: destravar

        interval: 5000
        onTriggered: {
            popupAutorizacao._travado = false;
            popupAutorizacao._tentativas = 0;
            popupAutorizacao._erro = "";
            campoCodigo.forceActiveFocus();
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
                nome: "fa6s.user-lock"
                cor: Estilo.global.text
                tamanho: Estilo.global.fontSize.title
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "Autorizar"
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            Layout.fillWidth: true
            text: popupAutorizacao.acao
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            wrapMode: Text.Wrap
        }

        // --- CÓDIGO ---
        ColumnLayout {
            Layout.fillWidth: true
            visible: popupAutorizacao._candidatos.length === 0
            spacing: Estilo.global.spacing.sm

            Text {
                text: "Código do usuário"
                font.pixelSize: Estilo.global.fontSize.sm
                font.bold: true
                color: Estilo.global.textSecondary
            }

            CampoTexto {
                id: campoCodigo

                // Nomeado como os popups já são (ver objectName em
                // Fechamento.qml) — deixa este campo alcançável de fora para
                // inspeção e teste sem expor nada do funcionamento.
                objectName: "campoCodigo"
                Layout.fillWidth: true
                enabled: !popupAutorizacao._travado
                placeholderText: "00"
                horizontalAlignment: TextInput.AlignHCenter
                maximumLength: 2
                // Esconder o que se digita aqui não é sigilo (o código não é
                // segredo — ver o topo deste arquivo): é só não deixar o
                // colega do lado ler o código alheio pela tela.
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhDigitsOnly
                validator: RegularExpressionValidator { regularExpression: /^\d{0,2}$/ }
                Keys.onReturnPressed: popupAutorizacao._confirmar()
            }

            Text {
                Layout.fillWidth: true
                visible: popupAutorizacao._erro !== ""
                text: popupAutorizacao._erro
                font.pixelSize: Estilo.global.fontSize.sm
                color: Estilo.status.error.content
                wrapMode: Text.Wrap
            }
        }

        // --- DESEMPATE (dois usuários com o mesmo código) ---
        ColumnLayout {
            Layout.fillWidth: true
            visible: popupAutorizacao._candidatos.length > 0
            spacing: Estilo.global.spacing.sm

            Text {
                Layout.fillWidth: true
                text: "Duas pessoas usam esse código. Quem está autorizando?"
                font.pixelSize: Estilo.global.fontSize.sm
                font.bold: true
                color: Estilo.global.textSecondary
                wrapMode: Text.Wrap
            }

            Repeater {
                model: popupAutorizacao._candidatos

                Button {
                    required property var modelData

                    Layout.fillWidth: true
                    padding: Estilo.global.padding.md
                    onClicked: popupAutorizacao._autorizarComo(modelData.id)

                    contentItem: Text {
                        text: modelData.nome
                        font.family: Estilo.global.fontFamily.title
                        color: Estilo.global.textOnAccent
                        horizontalAlignment: Text.AlignHCenter
                    }

                    background: Rectangle {
                        radius: Estilo.global.radius.pill
                        color: parent.down ? Estilo.action.confirm.pressed : (parent.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Corrija o código repetido em Configurações › Usuários."
                font.pixelSize: Estilo.global.fontSize.xs
                color: Estilo.global.textSecondary
                wrapMode: Text.Wrap
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Estilo.global.spacing.lg

            Button {
                id: btnCancelarAutorizacao

                Layout.fillWidth: true
                padding: Estilo.global.padding.md
                onClicked: popupAutorizacao.close()

                contentItem: Text {
                    text: "Cancelar"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnCancelarAutorizacao.down ? Estilo.action.neutral.pressed : (btnCancelarAutorizacao.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                }
            }

            Button {
                id: btnConfirmarAutorizacao

                Layout.fillWidth: true
                visible: popupAutorizacao._candidatos.length === 0
                padding: Estilo.global.padding.md
                // Um dígito basta para os códigos que começam com zero: quem
                // é "07" digita 7, e o Python completa (ver
                // usuarios.normalizar_codigo, por onde passam tanto a
                // gravação quanto a busca). Exigir os dois aqui era a tela
                // cobrando um zero que ela mesma sabia pôr — e no balcão, com
                // a fila andando, esse zero é digitado errado ou esquecido.
                //
                // O campo vazio continua desabilitando: um Enter apressado em
                // nada queimaria uma tentativa do freio à toa.
                enabled: campoCodigo.text.length > 0 && !popupAutorizacao._travado
                onClicked: popupAutorizacao._confirmar()

                contentItem: Text {
                    text: "Autorizar"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    // Desabilitado é opacidade, não uma cor própria — mesmo
                    // idioma de components/Botao.qml.
                    opacity: btnConfirmarAutorizacao.enabled ? 1 : Estilo.global.opacity.disabled
                    color: btnConfirmarAutorizacao.down ? Estilo.action.confirm.pressed : (btnConfirmarAutorizacao.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base)
                }
            }
        }
    }
}
