// ===== CAMADA 0: A MEDIDA DA JANELA =====
// Único lugar do app que sabe QUANTO espaço existe. Import: "import estilo 1.0"
// (o diretório qml/ já está no import path, configurado em main.py).
//
// Antes disto, cada tela trazia larguras cravadas em pixel — o formulário de
// pedidos era um Row de 690, o resumo ao lado tinha 300, o campo de nome 420 —
// somando pouco mais de 1050px rígidos dentro de um Flickable que só rolava na
// vertical. Numa janela mais estreita que isso o conteúdo simplesmente saía
// pela direita, sem rolagem horizontal e sem jeito de alcançar os botões.
//
// A responsividade aqui tem DUAS alavancas, e elas resolvem problemas
// diferentes:
//
//   1. ESCALA (escalaTexto/escalaEspaco/escalaRaio) — encolhe fonte, respiro e
//      raio proporcionalmente. Entra sozinha, por baixo, nas escalas de
//      Estilo.qml: nenhuma tela precisa saber que ela existe. Resolve o
//      "aperto" leve, mas tem piso: abaixo de certo tamanho o texto deixa de
//      ser legível e encolher mais só piora.
//
//   2. REFLOW (compacto/empilhar/colunas()) — quando encolher não basta, o
//      layout se reorganiza: o que estava lado a lado passa a ficar um sobre o
//      outro, e as grades perdem colunas. Isto cada tela declara
//      explicitamente, porque só ela sabe o que pode descer para baixo.
//
// REGRA DE OURO: as decisões de reflow olham a largura de QUEM decide (a
// própria página, o próprio painel), não a da janela — uma página dividida em
// dois painéis precisa saber quanto sobrou para ELA, não quanto a janela tem.
// Por isso as funções recebem uma largura como argumento; as propriedades
// globais (compacto, empilhar) existem só para o que é filho direto da janela:
// a barra lateral e os popups, que flutuam fora da árvore das páginas.

import QtQuick
pragma Singleton

QtObject {
    id: root

    // ===== O que a janela mede agora =====
    // Escrito por qml/main.qml (um Binding para root.width/height da
    // ApplicationWindow). Não é readonly de propósito: é a única entrada de
    // dados deste singleton. Os valores iniciais são só o palpite que vale
    // durante o carregamento, antes do primeiro Binding chegar.
    property real largura: 1280
    property real altura: 800

    // ===== Tamanho de referência do projeto =====
    // As telas foram desenhadas em ~1280x800: nesse tamanho, fator = 1 e
    // NADA escala — o app fica pixel a pixel como sempre foi.
    readonly property int larguraBase: 1280
    readonly property int alturaBase: 800

    // ===== Pontos de virada =====
    // Medidos na largura DISPONÍVEL para o conteúdo, não na da janela.
    // bpEstreito é onde duas colunas deixam de caber: o formulário de pedidos
    // (~690) mais o resumo da comanda (~300) mais o respiro entre eles pedem
    // por volta de 1000px. Abaixo disso, empilhar é melhor que espremer.
    // bpCompacto é o território do tablet em pé: uma coluna só, tudo rolando.
    readonly property int bpCompacto: 640
    readonly property int bpEstreito: 1000

    // ===== Estado da JANELA (só para quem é filho direto dela) =====
    readonly property bool compacto: largura < bpCompacto
    readonly property bool empilhar: largura < bpEstreito
    // Telas 16:9 de notebook (768px de altura) e janelas restauradas: onde a
    // conta que aperta é a vertical, não a horizontal.
    readonly property bool baixa: altura < 700

    // ===== Fatores de escala =====
    // Vale o MENOR dos dois: numa janela larga e baixa, quem manda é a altura;
    // numa alta e estreita, a largura. Escalar por um só produzia o absurdo de
    // aumentar a fonte numa janela de 1920x400.
    readonly property real fator: Math.min(largura / larguraBase, altura / alturaBase)
    // O texto tem o piso mais alto das três escalas (0.85): é o que decide se
    // o atendente consegue LER o pedido, e um sistema ilegível não fica
    // utilizável só porque coube na tela. O teto (1.15) evita que um monitor
    // 4K vire uma interface de fonte gigante.
    readonly property real escalaTexto: limitar(fator, 0.85, 1.15)
    // Espaço em branco é o primeiro a ceder — some sem prejuízo funcional, e
    // é dele que sai a maior parte do ganho em tela pequena.
    readonly property real escalaEspaco: limitar(fator, 0.6, 1.2)
    // O raio quase não muda: é identidade visual, não medida de layout.
    readonly property real escalaRaio: limitar(fator, 0.85, 1.1)

    // ===== Alvo mínimo de toque =====
    // Em tablet o dedo substitui o mouse e precisa de mais área que um clique
    // — sem isto, os botões encolhem junto com o resto e ficam difíceis de
    // acertar exatamente onde o ponteiro é menos preciso.
    readonly property int alvoToque: compacto ? 44 : 38

    // Prende um valor entre um piso e um teto (o "clamp" do CSS).
    function limitar(valor, minimo, maximo) {
        return Math.max(minimo, Math.min(maximo, valor));
    }

    // A largura que um bloco DEVERIA ter, cortada pelo que de fato sobrou.
    // Substitui os "width: 690" cravados: em tela grande devolve os mesmos 690
    // de sempre; em tela pequena devolve o espaço existente, e o conteúdo
    // encolhe em vez de vazar para fora.
    function larguraUtil(disponivel, ideal) {
        return Math.max(0, Math.min(ideal, disponivel));
    }

    // Quantas colunas de larguraItem cabem em disponivel. Nunca menos de uma:
    // uma grade sem coluna nenhuma não desenha nada.
    function colunas(disponivel, larguraItem, espaco) {
        var passo = larguraItem + (espaco || 0);
        if (passo <= 0)
            return 1;

        return Math.max(1, Math.floor((disponivel + (espaco || 0)) / passo));
    }

    // Largura/altura que um popup pode de fato ocupar: a que ele pediu, ou o
    // que a janela comporta, o que for menor. Popups não são filhos das
    // páginas — moram no Overlay, sobre a janela inteira —, então são os
    // únicos elementos que legitimamente consultam o tamanho da JANELA em vez
    // do espaço do próprio pai. As margens deixam a moldura da janela
    // aparecendo dos dois lados, que é o que faz um popup ler como popup e
    // não como tela cheia.
    function larguraPopup(ideal) {
        return Math.min(ideal, largura - 48);
    }

    function alturaPopup(ideal) {
        return Math.min(ideal, altura - 48);
    }

    // Divide a largura de uma linha de item de pedido entre as três colunas
    // (pedido / observação / valor). Mora aqui, e não em cada tela, porque
    // Balcão, Entrega e Salão precisam CHEGAR NO MESMO NÚMERO: o cabeçalho de
    // colunas é desenhado pela página e os campos pelo delegate
    // (components/LinhaPedido.qml), e qualquer divergência entre os dois
    // aparece na hora como rótulo fora de cima do seu campo.
    //
    // As proporções (41/37/22) são as das larguras originais — 200, 180 e 110
    // — agora relativas em vez de cravadas. O desconto de 100px é o par de
    // botões +/- no fim da linha; errar essa estimativa por alguns pixels só
    // sobra ou falta respiro na ponta direita, nunca desalinha as colunas.
    function gradePedido(larguraLinha) {
        var campos = Math.max(270, larguraLinha - 100);
        var pedido = Math.max(110, Math.round(campos * 0.41));
        var observacao = Math.max(90, Math.round(campos * 0.37));
        return {
            "pedido": pedido,
            "observacao": observacao,
            "valor": Math.max(70, campos - pedido - observacao)
        };
    }

    // Verdadeiro quando o espaço recebido não comporta duas colunas — o teste
    // que cada tela faz para decidir entre Row e Column.
    function ehEstreito(disponivel) {
        return disponivel < bpEstreito;
    }

    // Verdadeiro no território de uma coluna só (tablet em pé).
    function ehCompacto(disponivel) {
        return disponivel < bpCompacto;
    }

}
