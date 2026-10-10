// ===== FACHADA DOS TOKENS SEMÂNTICOS =====
// Import: "import estilo 1.0". Todo o app lê estilo por aqui (Estilo.global.*,
// Estilo.action.* etc.), mas os valores moram nos temas em temas/:
//   TemaForno.qml       o tema padrão (estável)
//   TemaSecundario.qml  o tema de experimentação
// `nomeTema` escolhe qual está valendo; a troca é imediata, sem reiniciar,
// porque todo token abaixo é um binding para o tema atual.
//
// A escolha é por máquina (não vai pela malha) e fica guardada pelo
// TemaController (controllers/temaController.py), exposto como `temaController`.

import "temas"
import QtQuick
pragma Singleton

QtObject {
    id: root

    // Temas disponíveis para a tela Aparência: chave, nome e descrição.
    readonly property var temas: [
        { "chave": "forno", "nome": "Forno", "descricao": "O visual atual do sistema." },
        { "chave": "secundario", "nome": "Secundário", "descricao": "Tema experimental, em desenvolvimento." }
    ]

    property string nomeTema: "forno"

    // Muda o tema agora e guarda a escolha. Chave desconhecida é ignorada.
    function definirTema(chave) {
        if (chave !== "forno" && chave !== "secundario")
            return;

        root.nomeTema = chave;
        if (typeof temaController !== "undefined")
            temaController.definir(chave);
    }

    Component.onCompleted: {
        if (typeof temaController !== "undefined" && (temaController.nome === "forno" || temaController.nome === "secundario"))
            root.nomeTema = temaController.nome;
    }

    readonly property TemaForno _forno: TemaForno {
    }
    readonly property TemaSecundario _secundario: TemaSecundario {
    }
    readonly property QtObject _atual: root.nomeTema === "secundario" ? root._secundario : root._forno

    readonly property QtObject global: root._atual.global
    readonly property QtObject action: root._atual.action
    readonly property QtObject status: root._atual.status
    readonly property QtObject finance: root._atual.finance
    readonly property QtObject screen: root._atual.screen
    readonly property QtObject orderType: root._atual.orderType
    readonly property QtObject category: root._atual.category
    readonly property QtObject bread: root._atual.bread
    readonly property QtObject illustration: root._atual.illustration
    readonly property QtObject printer: root._atual.printer
}
