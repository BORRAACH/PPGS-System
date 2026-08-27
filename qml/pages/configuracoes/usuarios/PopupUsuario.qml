import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../../components"

// Ficha de um usuário: tudo que se sabe sobre a pessoa e tudo que dá para
// mexer nela (ver GerenciarUsuarios.qml e controllers/usuariosController.py).
//
// É a ÚNICA porta para esses dados. A lista lá fora mostra só o nome — o
// código de dois dígitos é o que libera apagar uma comanda, e exibi-lo em fila
// deixaria os códigos da casa inteira legíveis de longe para quem passasse
// pelo balcão com a tela aberta. Quem precisa dele clica na linha e chega
// aqui, o que também é o lugar certo para o resto (data de cadastro,
// estatísticas, remover).
//
// Três estágios no mesmo popup, trocados por booleanas — mesma técnica de
// PopupExtras.qml: são escolhas curtas, e empilhar modal sobre modal só
// acrescentaria uma camada para fechar.
//
// 1. NOVO      — idEdicao vazio: só os dois campos.
// 2. DETALHES  — idEdicao preenchido: campos + ficha + Remover.
// 3. EXCLUSÃO  — confirmação, por cima dos outros dois.
Popup {
    id: popupUsuario

    objectName: "popupUsuario"

    // "" = cadastrando alguém novo; preenchido = ficha de quem já existe.
    property string idEdicao: ""
    property bool confirmandoExclusao: false
    property string erro: ""

    // O que detalhesUsuario devolveu. {} enquanto for um cadastro novo — é o
    // que decide se a ficha aparece.
    property var detalhes: ({})

    readonly property bool editando: popupUsuario.idEdicao !== ""

    // Emitido depois de gravar/apagar, para a lista se recarregar.
    signal concluido

    function abrirParaNovo() {
        popupUsuario.idEdicao = "";
        popupUsuario.detalhes = ({});
        popupUsuario.confirmandoExclusao = false;
        popupUsuario.erro = "";
        inputNome.text = "";
        inputCodigo.text = "";
        open();
    }

    // Ponto de entrada do clique na lista. Recebe só o id e busca o resto no
    // controller, em vez de aceitar o registro que a lista já tem em mãos: a
    // lista foi carregada antes, e neste meio-tempo outra máquina da malha pode
    // ter corrigido o código ou a pessoa pode ter autorizado mais coisas.
    function abrirDetalhes(idUsuario) {
        var dados = usuariosController.detalhesUsuario(idUsuario);
        if (!dados || !dados.id) {
            popupUsuario.concluido();
            return false;
        }

        popupUsuario.idEdicao = dados.id;
        popupUsuario.detalhes = dados;
        popupUsuario.confirmandoExclusao = false;
        popupUsuario.erro = "";
        inputNome.text = dados.nome;
        inputCodigo.text = dados.codigo;
        open();
        return true;
    }

    function _recarregarDetalhes() {
        if (popupUsuario.editando)
            popupUsuario.detalhes = usuariosController.detalhesUsuario(popupUsuario.idEdicao) || ({});
    }

    // "1 ação" / "3 ações" / "nenhuma ação" — o plural feito aqui porque a
    // frase muda de forma, não só de número.
    function _contagem(quantas, singular, plural, nenhuma) {
        if (!quantas)
            return nenhuma;
        return quantas + " " + (quantas === 1 ? singular : plural);
    }

    // O instante vem do controller em segundos desde a época (ver
    // relogio.instante_do_id); 0 = nunca aconteceu.
    function _quando(segundos) {
        if (!segundos)
            return "";
        return Qt.formatDateTime(new Date(segundos * 1000), "dd/MM/yyyy HH:mm");
    }

    // Traduz o código de erro do controller para uma frase que diga o que
    // fazer. O controller devolve código, e não texto pronto, porque ele não
    // é quem decide como a tela fala.
    function _mensagemErro(resultado) {
        if (resultado.erro === "codigo_em_uso")
            return "O código " + inputCodigo.text + " já é de " + (resultado.nome || "outra pessoa") + ".";
        if (resultado.erro === "codigo_invalido")
            return "O código precisa ter dois dígitos.";
        if (resultado.erro === "nome_vazio")
            return "Escreva o nome da pessoa.";
        if (resultado.erro === "nao_encontrado")
            return "Esse usuário não existe mais — pode ter sido removido em outra máquina.";
        if (resultado.erro === "senha_incorreta")
            return "Senha do dono incorreta.";
        return "Não foi possível salvar.";
    }

    // As três gravações pedem a senha do dono, uma vez cada — o destrave da
    // porta abre a VISTA do cadastro, não o direito de gravar (ver
    // UsuariosController._autorizar_escrita). O callback devolve false só
    // quando a senha foi recusada: aí PopupSenhaDono se mantém aberto para
    // outra tentativa. Qualquer outro erro (código em uso, nome vazio) fecha o
    // popup da senha e aparece aqui na ficha, que é onde se conserta.
    function _confirmar() {
        var rotulo = popupUsuario.editando ? "Salvar as alterações" : "Cadastrar usuário";
        popupSenhaDono.solicitar(rotulo, function (senha) {
            var resultado = popupUsuario.editando
                ? usuariosController.editarUsuario(popupUsuario.idEdicao, inputNome.text, inputCodigo.text, senha)
                : usuariosController.cadastrarUsuario(inputNome.text, inputCodigo.text, senha);

            if (resultado && resultado.erro === "senha_incorreta")
                return false;

            if (!resultado || !resultado.id) {
                popupUsuario.erro = popupUsuario._mensagemErro(resultado || {});
                return true;
            }

            popupUsuario.concluido();
            popupUsuario.close();
            return true;
        });
    }

    function _excluir() {
        popupSenhaDono.solicitar("Remover do cadastro", function (senha) {
            var resultado = usuariosController.excluirUsuario(popupUsuario.idEdicao, senha);

            if (resultado && resultado.erro === "senha_incorreta")
                return false;

            if (!resultado || !resultado.ok) {
                popupUsuario.erro = "Não foi possível remover — pode já ter sido removido em outra máquina.";
                popupUsuario.confirmandoExclusao = false;
                return true;
            }

            popupUsuario.concluido();
            popupUsuario.close();
            return true;
        });
    }

    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    padding: Estilo.global.padding.popup
    parent: Overlay.overlay
    anchors.centerIn: parent
    onOpened: {
        if (!popupUsuario.confirmandoExclusao)
            inputNome.forceActiveFocus();
    }

    width: Math.min(420, parent ? parent.width * 0.9 : 420)

    // Guarda das três gravações desta ficha. Fica AQUI dentro, e não em
    // GerenciarUsuarios: é esta ficha que grava, e um guarda pendurado na tela
    // de fora precisaria de um caminho de volta para cada ação.
    PopupSenhaDono {
        id: popupSenhaDono
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
                nome: popupUsuario.confirmandoExclusao ? "fa6s.trash-can" : "fa6s.user-lock"
                cor: Estilo.global.text
                tamanho: Estilo.global.fontSize.title
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: {
                    if (popupUsuario.confirmandoExclusao)
                        return "Remover usuário?";
                    return popupUsuario.editando ? (popupUsuario.detalhes.nome || "Usuário") : "Novo usuário";
                }
                font.pixelSize: Estilo.global.fontSize.xl
                font.bold: true
                color: Estilo.global.text
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // --- FORMULÁRIO ---
        ColumnLayout {
            Layout.fillWidth: true
            visible: !popupUsuario.confirmandoExclusao
            spacing: Estilo.global.spacing.lg

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "Nome"
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                CampoTexto {
                    id: inputNome

                    Layout.fillWidth: true
                    corDestaque: Estilo.screen.config.accent
                    placeholderText: "NOME DA PESSOA"
                    KeyNavigation.tab: inputCodigo
                    Keys.onReturnPressed: inputCodigo.forceActiveFocus()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text {
                    text: "Código de dois dígitos"
                    font.pixelSize: Estilo.global.fontSize.sm
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                CampoTexto {
                    id: inputCodigo

                    Layout.fillWidth: true
                    corDestaque: Estilo.screen.config.accent
                    placeholderText: "00"
                    maximumLength: 2
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: RegularExpressionValidator { regularExpression: /^\d{0,2}$/ }
                    Keys.onReturnPressed: popupUsuario._confirmar()
                }

                Text {
                    Layout.fillWidth: true
                    visible: popupUsuario.detalhes.duplicado === true
                    text: "Outra pessoa usa este mesmo código. Enquanto durar, quem digitar "
                        + "estes dois dígitos escolhe de quem é."
                    font.pixelSize: Estilo.global.fontSize.xs
                    color: Estilo.status.error.content
                    wrapMode: Text.Wrap
                }
            }
        }

        // --- FICHA ---
        // Só na edição: num cadastro novo não há nada para contar ainda.
        Rectangle {
            Layout.fillWidth: true
            visible: popupUsuario.editando && !popupUsuario.confirmandoExclusao
            implicitHeight: colunaFicha.implicitHeight + Estilo.global.padding.lg * 2
            radius: Estilo.global.radius.md
            color: Estilo.global.surface
            border.color: Estilo.global.borderCard
            border.width: Estilo.global.borderWidth.hairline

            ColumnLayout {
                id: colunaFicha

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Estilo.global.padding.lg
                spacing: Estilo.global.spacing.sm

                Text {
                    text: "NO CADASTRO"
                    font.pixelSize: Estilo.global.fontSize.xs
                    font.bold: true
                    color: Estilo.global.textSecondary
                }

                Repeater {
                    model: [
                        {
                            "rotulo": "Cadastrado em",
                            "valor": popupUsuario.detalhes.dataHora || "—"
                        },
                        {
                            // A janela vem do controller (RETENCAO_DIAS do
                            // histórico) e é dita junto com o número: sem ela,
                            // "3 ações" pareceria o total de sempre.
                            "rotulo": "Autorizações (últimos " + (popupUsuario.detalhes.diasHistorico || 7) + " dias)",
                            "valor": popupUsuario._contagem(popupUsuario.detalhes.autorizacoes,
                                                            "ação", "ações", "nenhuma")
                                + (popupUsuario.detalhes.ultimaAutorizacao
                                   ? " — última em " + popupUsuario._quando(popupUsuario.detalhes.ultimaAutorizacao)
                                   : "")
                        },
                        {
                            // Sem janela: o domínio "edicoes" nunca é purgado.
                            "rotulo": "Alterações em comanda fechada",
                            "valor": popupUsuario._contagem(popupUsuario.detalhes.alteracoesCaixa,
                                                            "alteração", "alterações", "nenhuma")
                        }
                    ]

                    RowLayout {
                        required property var modelData

                        Layout.fillWidth: true
                        spacing: Estilo.global.spacing.md

                        Text {
                            text: modelData.rotulo
                            font.pixelSize: Estilo.global.fontSize.sm
                            color: Estilo.global.textSecondary
                            Layout.alignment: Qt.AlignTop
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.valor
                            font.pixelSize: Estilo.global.fontSize.sm
                            color: Estilo.global.text
                            horizontalAlignment: Text.AlignRight
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }
        }

        // --- CONFIRMAR EXCLUSÃO ---
        Text {
            Layout.fillWidth: true
            visible: popupUsuario.confirmandoExclusao
            text: inputNome.text + " (código " + inputCodigo.text + ") deixa de poder autorizar "
                + "edições e exclusões de comanda. O que essa pessoa já autorizou continua no histórico."
            font.pixelSize: Estilo.global.fontSize.md
            color: Estilo.global.textSecondary
            wrapMode: Text.Wrap
        }

        Text {
            Layout.fillWidth: true
            visible: popupUsuario.erro !== ""
            text: popupUsuario.erro
            font.pixelSize: Estilo.global.fontSize.sm
            color: Estilo.status.error.content
            wrapMode: Text.Wrap
        }

        // --- REMOVER ---
        // Fora da fileira de Cancelar/Confirmar de propósito: é a ação
        // destrutiva, e encostá-la no botão que se aperta no automático seria
        // convidar o clique errado.
        Button {
            id: btnRemoverUsuario

            Layout.fillWidth: true
            visible: popupUsuario.editando && !popupUsuario.confirmandoExclusao
            padding: Estilo.global.padding.md
            onClicked: {
                popupUsuario.erro = "";
                popupUsuario.confirmandoExclusao = true;
            }

            contentItem: Row {
                spacing: Estilo.global.spacing.xs
                anchors.centerIn: parent

                Icone {
                    nome: "fa6s.trash-can"
                    cor: Estilo.action.danger.base
                    tamanho: Estilo.global.fontSize.md
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: "Remover do cadastro"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.action.danger.base
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: btnRemoverUsuario.down ? Estilo.status.error.background : "transparent"
                border.color: Estilo.action.danger.base
                border.width: Estilo.global.borderWidth.hairline
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Estilo.global.spacing.lg

            Button {
                id: btnCancelarUsuario

                Layout.fillWidth: true
                padding: Estilo.global.padding.md
                onClicked: {
                    // Voltar da confirmação não fecha a ficha: quem desistiu de
                    // remover quase sempre quer continuar olhando a pessoa.
                    if (popupUsuario.confirmandoExclusao)
                        popupUsuario.confirmandoExclusao = false;
                    else
                        popupUsuario.close();
                }

                contentItem: Text {
                    text: popupUsuario.confirmandoExclusao ? "Voltar" : "Cancelar"
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: btnCancelarUsuario.down ? Estilo.action.neutral.pressed : (btnCancelarUsuario.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
                }
            }

            Button {
                id: btnConfirmarUsuario

                Layout.fillWidth: true
                padding: Estilo.global.padding.md
                enabled: popupUsuario.confirmandoExclusao
                    || (inputNome.text.trim() !== "" && inputCodigo.text.length === 2)
                onClicked: {
                    if (popupUsuario.confirmandoExclusao)
                        popupUsuario._excluir();
                    else
                        popupUsuario._confirmar();
                }

                contentItem: Text {
                    text: {
                        if (popupUsuario.confirmandoExclusao)
                            return "Remover";
                        return popupUsuario.editando ? "Salvar" : "Confirmar";
                    }
                    font.family: Estilo.global.fontFamily.title
                    color: Estilo.global.textOnAccent
                    horizontalAlignment: Text.AlignHCenter
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    opacity: btnConfirmarUsuario.enabled ? 1 : Estilo.global.opacity.disabled
                    color: {
                        if (popupUsuario.confirmandoExclusao)
                            return btnConfirmarUsuario.down ? Estilo.action.danger.pressed : (btnConfirmarUsuario.hovered ? Estilo.action.danger.hover : Estilo.action.danger.base);
                        return btnConfirmarUsuario.down ? Estilo.action.confirm.pressed : (btnConfirmarUsuario.hovered ? Estilo.action.confirm.hover : Estilo.action.confirm.base);
                    }
                }
            }
        }
    }
}
