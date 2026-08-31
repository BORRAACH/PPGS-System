import QtQuick
import estilo 1.0

// Um "campo" de texto da prévia da comanda (ver EstiloImpressora.qml),
// estilizado de acordo com a configuração atual do campo indicado —
// negrito/sublinhado refletidos via font, fundo preto via cor de fundo +
// texto branco (o modo reverso real da impressora), e tamanho de fonte na
// mesma escala que realmente sai impressa.
//
// Essa escala depende de quem desenha a comanda: sendo a impressora, é o
// multiplicador ESC/POS (1x-8x) e não o valor em pixels puro, pra prévia não
// prometer uma granularidade que a impressora não tem; havendo uma fonte
// escolhida (ver services/comandaImagemService.py), quem desenha somos nós e
// o tamanho em pixels vale como está — a prévia então mostra 30px como 30px,
// e não arredondado pra 2x.
Rectangle {
    id: raizCampo

    property var controlador
    property string campo: ""
    property string texto: ""
    property int tamanhoBase: 12

    // Estado do estilo deste campo, relido quando o controlador avisa que ESTE
    // campo mudou (campoEstiloAlterado), em vez de por binding.
    //
    // Antes as quatro eram bindings que liam controlador.versaoConfig, um
    // contador incrementado a cada edição — e como configAtual é um objeto JS
    // comum, que não emite sinal ao ser mutado, era preciso passar versaoConfig
    // como argumento de funções que nem o usavam (obterAtributoReativo), só
    // para criar a dependência. Some esse parâmetro-fantasma, e mudar um campo
    // deixa de reavaliar as ~80 bindings dos ~20 campos da comanda.
    //
    // Não espere ganho de desempenho por isto: medido, sai igual. O que pesa
    // numa alteração é o relayout (mudar o tamanho do texto reposiciona a
    // coluna inteira do papel e mexe no contentHeight do Flickable) — ~3ms,
    // contra ~0,3ms de uma alteração que não mexe no tamanho, como o negrito.
    //
    // versaoConfig continua servindo de "invalidar tudo", para quando a
    // configuração inteira é trocada (carregarConfiguracao/restaurar padrões).
    property bool _negrito: false
    property bool _sublinhado: false
    property bool _fundoPreto: false
    // Quantas vezes o tamanho base — fracionário quando o tamanho vai em
    // pixels livres, inteiro quando é multiplicador de impressora.
    property real _escala: 1

    function recarregarEstilo() {
        if (!controlador)
            return;

        _negrito = !!controlador.obterAtributo(campo, "negrito");
        _sublinhado = !!controlador.obterAtributo(campo, "sublinhado");
        _fundoPreto = !!controlador.obterAtributo(campo, "fundo_preto");
        // O tamanho DESENHADO, não o configurado: o modelo em colunas limita o
        // conteúdo da tabela de itens ao tamanho normal (ver
        // EstiloImpressora.tamanhoFonteDesenhado), e a prévia tem que mostrar
        // a letra que vai sair no papel.
        var tamanhoPx = controlador.tamanhoFonteDesenhado(campo);
        _escala = controlador.fonteImpressao === "" ? controlador.multiplicadorFonte(tamanhoPx) : tamanhoPx / controlador.tamanhoFontePadrao;
    }

    Component.onCompleted: recarregarEstilo()
    onCampoChanged: recarregarEstilo()

    Connections {
        target: raizCampo.controlador

        function onCampoEstiloAlterado(chave) {
            if (chave === raizCampo.campo)
                raizCampo.recarregarEstilo();
        }

        function onVersaoConfigChanged() {
            raizCampo.recarregarEstilo();
        }
    }

    implicitWidth: rotulo.implicitWidth + (_fundoPreto ? 8 : 0)
    implicitHeight: rotulo.implicitHeight + (_fundoPreto ? 2 : 0)
    color: _fundoPreto ? Estilo.printer.reverseBackground : "transparent"

    Text {
        id: rotulo

        anchors.centerIn: parent
        text: raizCampo.texto
        font.family: "monospace"
        font.bold: raizCampo._negrito
        font.underline: raizCampo._sublinhado
        font.pixelSize: Math.max(1, Math.round(raizCampo.tamanhoBase * raizCampo._escala))
        color: raizCampo._fundoPreto ? Estilo.printer.reverseText : Estilo.printer.ink
    }
}
