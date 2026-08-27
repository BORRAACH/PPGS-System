import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0
import "../../../components"

// Cadastro de quem pode autorizar as ações destrutivas do app — editar uma
// comanda já fechada, apagar uma comanda (ver components/PopupAutorizacao.qml
// e controllers/usuariosController.py). Cada pessoa tem um código de dois
// dígitos, e cadastrar aqui cadastra em todas as máquinas da malha.
//
// A seção inteira é trancada pela SENHA DO DONO (ver PainelTranca.qml e
// services/rede/senhaDono.py) — outro segredo, com papel oposto ao do código:
// o código de dois dígitos existe para ser digitado na frente de todos (é
// assinatura), e a senha existe para não ser. Enquanto a tranca não abre, esta
// seção não mostra nem a lista: os códigos aparecem nela em claro.
//
// Diferente de EstiloImpressora (a outra seção desta tela), aqui NÃO existe
// "alterações pendentes": cada Confirmar grava e publica na hora. Quem vier
// atrás procurando o gancho de alteracoesPendentes/salvarNoBackend não vai
// encontrar — é de propósito. Um cadastro pela metade esperando alguém
// lembrar de clicar em "Aplicar" seria um funcionário que acha que existe e
// não existe.
ColumnLayout {
    id: gerenciarUsuarios

    property var usuarios: []

    // Se a senha do dono já foi conferida nesta sessão (ver PainelTranca.qml e
    // UsuariosController.destrancarCadastro). Enquanto for falsa, a seção
    // mostra só o painel da tranca — nem a lista, porque os códigos de dois
    // dígitos aparecem nela em claro, e deixá-los à mostra entregaria de graça
    // exatamente o que a senha protege.
    //
    // Falsa também na máquina que ainda NÃO tem senha nenhuma: ali o painel
    // aparece no modo "definir", e o cadastro só surge depois que a senha for
    // escolhida (definirSenhaDono destrava a sessão em seguida). É o caso da
    // segunda máquina da casa, que antes abria o cadastro sozinha e nunca
    // chegava a pedir a senha.
    //
    // Espelho do estado do controller, nunca a fonte dele: quem decide é
    // cadastroDestrancado(), e este bool só existe para as bindings de
    // `visible` terem o que observar.
    property bool destrancado: false

    readonly property color corDestaque: Estilo.screen.config.accent

    function recarregar() {
        gerenciarUsuarios.usuarios = usuariosController.listarUsuarios();
    }

    // Relê a tranca do controller e recarrega a lista quando ela abre. Sempre
    // pelo controller, e não confiando no bool daqui: o destrave EXPIRA
    // sozinho (cinco minutos), e uma cópia local ficaria dizendo "aberto"
    // depois de o prazo ter passado.
    function sincronizarTranca() {
        gerenciarUsuarios.destrancado = usuariosController.cadastroDestrancado();
        if (gerenciarUsuarios.destrancado)
            gerenciarUsuarios.recarregar();
        else
            painelTranca.recomecar();
    }

    spacing: Estilo.global.spacing.lg

    Component.onCompleted: gerenciarUsuarios.sincronizarTranca()

    // Sair da seção tranca na hora, sem esperar os cinco minutos: trocar de
    // seção (ou fechar Configurações) é o sinal mais claro de que o dono
    // terminou, e esperar o prazo deixaria a próxima pessoa que abrisse a
    // tela entrar sem senha.
    onVisibleChanged: {
        if (visible) {
            gerenciarUsuarios.sincronizarTranca();
            return;
        }
        usuariosController.trancarCadastro();
        gerenciarUsuarios.destrancado = false;
    }

    // Configurações fechada de vez (a página saiu da pilha) — onVisibleChanged
    // não cobre este caso em toda troca de tela, e deixar a sessão destravada
    // para trás é justamente o que a tranca existe para evitar.
    // Guardado contra o controller já ter sido derrubado: na destruição da
    // tela a ordem de teardown não é garantida, e um erro no console ao fechar
    // o app assusta sem informar nada.
    Component.onDestruction: {
        if (typeof usuariosController !== "undefined" && usuariosController)
            usuariosController.trancarCadastro();
    }

    // Cadastro alterado em OUTRA máquina da malha. Conexão declarativa presa
    // ao ciclo de vida desta seção, e não um .connect() solto: o controller é
    // global e vive pra sempre (mesmo motivo documentado em Fechamento.qml).
    Connections {
        target: usuariosController

        function onUsuariosAtualizados() {
            gerenciarUsuarios.recarregar();
        }

        // Senha definida ou trocada em outra máquina. O controller já trancou
        // esta sessão (a senha que a destravou não vale mais); aqui a tela só
        // acompanha, em vez de continuar mostrando o cadastro aberto.
        function onSenhaDonoAtualizada() {
            gerenciarUsuarios.sincronizarTranca();
        }
    }

    PainelTranca {
        id: painelTranca

        Layout.fillWidth: true
        visible: !gerenciarUsuarios.destrancado

        onDestrancado: gerenciarUsuarios.sincronizarTranca()
    }

    // --- CABEÇALHO DA SEÇÃO ---
    Row {
        spacing: Estilo.global.spacing.sm

        Icone {
            nome: "fa6s.user-lock"
            cor: gerenciarUsuarios.corDestaque
            tamanho: Estilo.global.fontSize.lg
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: "Usuários"
            font.pixelSize: Estilo.global.fontSize.lg
            font.bold: true
            color: gerenciarUsuarios.corDestaque
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Text {
        Layout.fillWidth: true
        visible: gerenciarUsuarios.destrancado
        text: "Quem pode editar uma comanda já fechada ou apagar uma comanda. "
            + "O código de dois dígitos é pedido na hora da ação, e quem autorizou "
            + "fica registrado no histórico da Rede. Mexer neste cadastro exige a "
            + "senha do dono, que não é o código."
        font.pixelSize: Estilo.global.fontSize.sm
        color: Estilo.global.textSecondary
        wrapMode: Text.Wrap
    }

    // --- AVISO DE CADASTRO VAZIO ---
    // Em destaque, e não uma linha discreta: enquanto não houver ninguém, o
    // guarda libera tudo (ver PopupAutorizacao.solicitar) — e um aviso
    // tímido faria essa porta aberta parecer o estado normal do app.
    Rectangle {
        Layout.fillWidth: true
        visible: gerenciarUsuarios.destrancado && gerenciarUsuarios.usuarios.length === 0
        implicitHeight: textoVazio.implicitHeight + Estilo.global.padding.lg * 2
        radius: Estilo.global.radius.md
        color: Estilo.status.warning.background
        border.color: Estilo.status.warning.border
        border.width: Estilo.global.borderWidth.hairline

        Text {
            id: textoVazio

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Estilo.global.padding.lg
            text: "Ninguém cadastrado ainda — enquanto isso, qualquer pessoa pode "
                + "editar e apagar comandas sem pedir autorização."
            font.pixelSize: Estilo.global.fontSize.sm
            color: Estilo.status.warning.content
            wrapMode: Text.Wrap
        }
    }

    // --- LISTA ---
    // Cada linha mostra SÓ o nome. O código, a data de cadastro, as
    // estatísticas e as ferramentas de edição ficam atrás de um clique, no
    // popup de detalhes (ver PopupUsuario.abrirDetalhes).
    //
    // O código saiu da lista de propósito: ele é o que libera apagar uma
    // comanda, e uma tela que o exibe em fila deixa os cinco códigos da casa
    // legíveis de longe para qualquer um que passe pelo balcão enquanto a tela
    // está aberta. Quem precisa dele continua a um clique de distância.
    Repeater {
        model: gerenciarUsuarios.destrancado ? gerenciarUsuarios.usuarios : []

        Rectangle {
            id: linhaUsuarioCartao

            required property var modelData

            Layout.fillWidth: true
            implicitHeight: linhaUsuario.implicitHeight + Estilo.global.padding.md * 2
            radius: Estilo.global.radius.md
            color: areaLinhaUsuario.containsMouse ? Estilo.global.surfaceHover : Estilo.global.surface
            border.color: modelData.duplicado ? Estilo.status.error.border : Estilo.global.borderCard
            border.width: Estilo.global.borderWidth.hairline

            RowLayout {
                id: linhaUsuario

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Estilo.global.padding.md
                spacing: Estilo.global.spacing.md

                Icone {
                    nome: "fa6s.user"
                    cor: gerenciarUsuarios.corDestaque
                    tamanho: Estilo.global.fontSize.lg
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: linhaUsuarioCartao.modelData.nome
                        font.pixelSize: Estilo.global.fontSize.md
                        color: Estilo.global.text
                        elide: Text.ElideRight
                    }

                    // O conflito que só existe em sistema distribuído: duas
                    // máquinas sem se enxergar cadastraram o mesmo número. Os
                    // dois cadastros são válidos e nenhum é descartado — ver
                    // services/rede/usuarios.py. Enquanto durar, quem digitar
                    // esse código escolhe de quem é.
                    //
                    // Este aviso fica na LISTA, e não só no popup, mesmo com o
                    // código escondido: é um problema que precisa ser visto sem
                    // que ninguém vá procurar, e ele não revela qual é o código.
                    Text {
                        Layout.fillWidth: true
                        visible: linhaUsuarioCartao.modelData.duplicado
                        text: "Código repetido — outra pessoa usa o mesmo. Troque um dos dois."
                        font.pixelSize: Estilo.global.fontSize.xs
                        color: Estilo.status.error.content
                        wrapMode: Text.Wrap
                    }
                }

                // Afordância do clique: sem ela a linha parece um rótulo, e
                // ninguém descobre que o cadastro inteiro está atrás dela.
                Icone {
                    nome: "fa6s.chevron-right"
                    cor: Estilo.global.textSecondary
                    tamanho: Estilo.global.fontSize.md
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            MouseArea {
                id: areaLinhaUsuario

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: popupUsuario.abrirDetalhes(linhaUsuarioCartao.modelData.id)
            }
        }
    }

    Button {
        id: btnAdicionarUsuario

        Layout.fillWidth: true
        visible: gerenciarUsuarios.destrancado
        padding: Estilo.global.padding.md
        onClicked: popupUsuario.abrirParaNovo()

        contentItem: Row {
            spacing: Estilo.global.spacing.xs
            anchors.centerIn: parent

            Icone {
                nome: "fa6s.plus"
                cor: Estilo.global.textOnAccent
                tamanho: Estilo.global.fontSize.md
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Adicionar usuário"
                font.family: Estilo.global.fontFamily.title
                color: Estilo.global.textOnAccent
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        background: Rectangle {
            radius: Estilo.global.radius.pill
            color: btnAdicionarUsuario.down ? Estilo.screen.config.pressed : (btnAdicionarUsuario.hovered ? Estilo.screen.config.hover : gerenciarUsuarios.corDestaque)
        }
    }

    // Trocar a senha fica ao lado do cadastro, e não numa seção própria: é
    // aqui que ela é usada, e uma pessoa que acabou de destrancar a tela é
    // exatamente quem tem como (e motivo para) trocá-la.
    Button {
        id: btnTrocarSenha

        Layout.fillWidth: true
        visible: gerenciarUsuarios.destrancado
        padding: Estilo.global.padding.md
        onClicked: popupTrocarSenha.abrir()

        contentItem: Row {
            spacing: Estilo.global.spacing.xs
            anchors.centerIn: parent

            Icone {
                nome: "fa6s.key"
                cor: Estilo.global.textOnAccent
                tamanho: Estilo.global.fontSize.md
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Trocar senha do dono"
                font.family: Estilo.global.fontFamily.title
                color: Estilo.global.textOnAccent
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        background: Rectangle {
            radius: Estilo.global.radius.pill
            color: btnTrocarSenha.down ? Estilo.action.neutral.pressed : (btnTrocarSenha.hovered ? Estilo.action.neutral.hover : Estilo.action.neutral.base)
        }
    }

    PopupUsuario {
        id: popupUsuario

        onConcluido: gerenciarUsuarios.recarregar()
    }

    PopupTrocarSenha {
        id: popupTrocarSenha

        // Trocar a senha destrava a sessão de novo no controller (quem acabou
        // de provar que sabe a senha nova não precisa digitá-la outra vez) —
        // sincronizar mantém a tela contando a mesma história.
        onTrocada: gerenciarUsuarios.sincronizarTranca()
    }
}
