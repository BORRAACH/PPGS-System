import QtQuick
import QtPositioning

// MapaBlocos.qml — mapa de blocos do OpenStreetMap em QML puro, com arrastar,
// roda do mouse, pinça e toque duplo. Usado pela página Mapa
// (qml/pages/mapa/Maps.qml), inclusive pela barra lateral de rotas dela.
//
// Por que não o Map do QtLocation: o PyQt6 do pip não traz o módulo QtLocation
// (ver o topo de qml/pages/mapa/Maps.qml). Cada bloco
// 256x256 é um Image posicionado pela projeção Web Mercator. Os blocos do
// tile.openstreetmap.org só chegam com User-Agent, que o main.py coloca em
// todo pedido de rede do QML (services/redeQml.py).
//
// POSIÇÕES. O centro fica "normalizado" (mundoX, mundoY de 0 a 1 cobrindo o
// mundo). Para pôr algo sobre o mapa, declare-o dentro do MapaBlocos: os
// filhos vão para uma camada acima dos blocos, e telaX/telaY convertem uma
// posição normalizada (de paraMundo) em pixels desta área.
Item {
    id: mapa

    // ----- Personalização -----
    property real zoomMinimo: 2
    property real zoomMaximo: 19 // último nível servido pelo tile.openstreetmap.org
    property int duracaoAnimacao: 600
    property string modeloUrlBlocos: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    property string atribuicao: "© OpenStreetMap contributors"
    // Desligue quando quem usa o componente já mostra a atribuição em outro lugar.
    property bool mostrarAtribuicao: true
    property color corFundo: "#eae4d8" // aparece enquanto os blocos carregam

    // ----- Estado -----
    property real mundoX: 0.5
    property real mundoY: 0.5
    property real zoom: 13

    // Largura do mundo inteiro em pixels no zoom atual.
    readonly property real tamanhoMundo: 256 * Math.pow(2, zoom)
    // Nível de blocos baixado: o inteiro mais próximo do zoom.
    readonly property int nivelBlocos: Math.round(limitar(zoom, zoomMinimo, zoomMaximo))
    readonly property var centro: paraCoordenada(mundoX, mundoY)

    // Os filhos declarados por quem usa o componente (marcadores, traçados).
    default property alias conteudo: camadaConteudo.data

    // Toque simples no mapa (fora de marcador), em pixels desta área.
    signal tocado(real x, real y)
    // Um bloco falhou ao carregar (sem internet, servidor fora).
    signal blocoFalhou()
    // O usuário começou a arrastar o mapa.
    signal arrastoIniciado()

    clip: true

    // =========================================================================
    // Projeção
    // =========================================================================

    function limitar(valor, minimo, maximo) {
        return Math.max(minimo, Math.min(maximo, valor));
    }

    function paraMundo(latitude, longitude) {
        // ±85.0511° é onde a projeção vira um quadrado; além disso vai ao infinito.
        const seno = Math.sin(limitar(latitude, -85.0511287798, 85.0511287798) * Math.PI / 180);
        return {
            x: (longitude + 180) / 360,
            y: 0.5 - Math.log((1 + seno) / (1 - seno)) / (4 * Math.PI)
        };
    }

    function paraCoordenada(x, y) {
        const latitude = Math.atan(Math.sinh(Math.PI * (1 - 2 * y))) * 180 / Math.PI;
        return QtPositioning.coordinate(latitude, x * 360 - 180);
    }

    // Pixel desta área onde fica a posição normalizada. Usado em bindings: a
    // posição acompanha pan e zoom sozinha.
    function telaX(x) {
        return (x - mundoX) * tamanhoMundo + width / 2;
    }

    function telaY(y) {
        return (y - mundoY) * tamanhoMundo + height / 2;
    }

    function pontoParaMundo(px, py) {
        return {
            x: mundoX + (px - width / 2) / tamanhoMundo,
            y: mundoY + (py - height / 2) / tamanhoMundo
        };
    }

    function urlBloco(nivel, coluna, linha) {
        const quantidade = Math.pow(2, nivel);
        // Coluna fora do mundo (zoom baixo em tela larga) repete o mapa.
        const colunaNoMundo = ((coluna % quantidade) + quantidade) % quantidade;
        return modeloUrlBlocos
            .replace("{z}", nivel)
            .replace("{x}", colunaNoMundo)
            .replace("{y}", linha);
    }

    // =========================================================================
    // Navegação
    // =========================================================================

    // Sem animação: para a posição inicial.
    function definirCentro(latitude, longitude, novoZoom) {
        animacao.stop();
        const ponto = paraMundo(latitude, longitude);
        mundoX = ponto.x;
        mundoY = ponto.y;
        if (novoZoom !== undefined)
            zoom = limitar(novoZoom, zoomMinimo, zoomMaximo);
    }

    // Voa até o ponto normalizado (x, y) ajustando o zoom junto.
    function animarPara(x, y, novoZoom) {
        animacao.stop();
        animacao.destinoX = limitar(x, 0, 1);
        animacao.destinoY = limitar(y, 0, 1);
        animacao.zoomDestino = limitar(novoZoom, zoomMinimo, zoomMaximo);
        animacao.start();
    }

    function centralizar(latitude, longitude, novoZoom) {
        const ponto = paraMundo(latitude, longitude);
        animarPara(ponto.x, ponto.y, novoZoom === undefined ? zoom : novoZoom);
    }

    function aproximar(passo) {
        animarPara(mundoX, mundoY, zoom + passo);
    }

    // Aproxima ou afasta até o retângulo normalizado caber na área, com
    // `margem` pixels de folga. Um ponto só (retângulo sem tamanho) não
    // passa de `zoomMaximoEnquadrar`.
    function enquadrar(minX, minY, maxX, maxY, margem, zoomMaximoEnquadrar) {
        if (maxX < minX || maxY < minY)
            return;
        const folga = margem === undefined ? 60 : margem;
        const teto = zoomMaximoEnquadrar === undefined ? 17 : zoomMaximoEnquadrar;
        const largura = Math.max(1, width - 2 * folga);
        const altura = Math.max(1, height - 2 * folga);
        const encaixe = Math.log2(Math.min(largura / Math.max((maxX - minX) * 256, 1e-9),
                                           altura / Math.max((maxY - minY) * 256, 1e-9)));
        animarPara((minX + maxX) / 2, (minY + maxY) / 2, Math.min(encaixe, teto));
    }

    // Arrastar o conteúdo dx pixels para a direita move o centro para a esquerda.
    function pan(dx, dy) {
        mundoX = limitar(mundoX - dx / tamanhoMundo, 0, 1);
        mundoY = limitar(mundoY - dy / tamanhoMundo, 0, 1);
    }

    // Muda o zoom mantendo parado o ponto de tela (px, py).
    function zoomEmTorno(novoZoom, px, py) {
        const fixo = pontoParaMundo(px, py);
        zoom = limitar(novoZoom, zoomMinimo, zoomMaximo);
        const tamanho = 256 * Math.pow(2, zoom);
        mundoX = limitar(fixo.x - (px - width / 2) / tamanho, 0, 1);
        mundoY = limitar(fixo.y - (py - height / 2) / tamanho, 0, 1);
    }

    // =========================================================================
    // Blocos
    // =========================================================================

    // Sincroniza modeloBlocos com a área visível. Blocos de outro nível ficam
    // por baixo como prévia até descartarOutrosNiveis: trocar de nível não
    // pisca a tela em branco enquanto os novos chegam.
    function atualizarBlocos(descartarOutrosNiveis) {
        if (width <= 0 || height <= 0)
            return;

        const nivel = nivelBlocos;
        const quantidade = Math.pow(2, nivel);
        const lado = tamanhoMundo / quantidade;
        const margemBlocos = 1;

        const esquerda = Math.floor(mundoX * quantidade - width / 2 / lado) - margemBlocos;
        const direita = Math.floor(mundoX * quantidade + width / 2 / lado) + margemBlocos;
        const topo = Math.max(0, Math.floor(mundoY * quantidade - height / 2 / lado) - margemBlocos);
        const base = Math.min(quantidade - 1, Math.floor(mundoY * quantidade + height / 2 / lado) + margemBlocos);

        const faltando = {};
        for (let bx = esquerda; bx <= direita; ++bx)
            for (let by = topo; by <= base; ++by)
                faltando[nivel + "/" + bx + "/" + by] = true;

        for (let i = modeloBlocos.count - 1; i >= 0; --i) {
            const bloco = modeloBlocos.get(i);
            const chave = bloco.nivel + "/" + bloco.bx + "/" + bloco.by;
            if (faltando[chave])
                delete faltando[chave];
            else if (bloco.nivel === nivel || descartarOutrosNiveis)
                modeloBlocos.remove(i);
        }

        for (const chave in faltando) {
            const partes = chave.split("/");
            modeloBlocos.append({ nivel: Number(partes[0]), bx: Number(partes[1]), by: Number(partes[2]) });
        }
    }

    onMundoXChanged: Qt.callLater(atualizarBlocos)
    onMundoYChanged: Qt.callLater(atualizarBlocos)
    onZoomChanged: Qt.callLater(atualizarBlocos)
    onWidthChanged: Qt.callLater(atualizarBlocos)
    onHeightChanged: Qt.callLater(atualizarBlocos)
    onNivelBlocosChanged: timerDescartarNiveis.restart()
    Component.onCompleted: Qt.callLater(atualizarBlocos)

    ListModel { id: modeloBlocos }

    Timer {
        id: timerDescartarNiveis
        interval: 1200
        onTriggered: mapa.atualizarBlocos(true)
    }

    Rectangle {
        anchors.fill: parent
        color: mapa.corFundo
    }

    Item {
        id: camadaBlocos
        anchors.fill: parent

        Repeater {
            model: modeloBlocos

            delegate: Image {
                id: bloco

                required property int nivel
                required property int bx
                required property int by
                property int tentativas: 0

                readonly property real lado: mapa.tamanhoMundo / Math.pow(2, nivel)

                // floor na posição + 1 px a mais de lado: sem frestas entre
                // blocos vizinhos quando o zoom é fracionário.
                x: Math.floor(bx * lado - mapa.mundoX * mapa.tamanhoMundo + mapa.width / 2)
                y: Math.floor(by * lado - mapa.mundoY * mapa.tamanhoMundo + mapa.height / 2)
                width: Math.ceil(lado) + 1
                height: Math.ceil(lado) + 1
                z: nivel === mapa.nivelBlocos ? 1 : 0

                source: mapa.urlBloco(nivel, bx, by)
                asynchronous: true
                cache: true
                smooth: true
                opacity: status === Image.Ready ? 1 : 0

                Behavior on opacity { NumberAnimation { duration: 150 } }

                onStatusChanged: {
                    if (status !== Image.Error)
                        return;
                    mapa.blocoFalhou();
                    if (tentativas < 3) {
                        ++tentativas;
                        novaTentativa.restart();
                    }
                }

                Timer {
                    id: novaTentativa
                    interval: 3000 * bloco.tentativas
                    onTriggered: {
                        bloco.source = "";
                        bloco.source = mapa.urlBloco(bloco.nivel, bloco.bx, bloco.by);
                    }
                }
            }
        }
    }

    // Camada de quem usa o componente, por cima dos blocos.
    Item {
        id: camadaConteudo
        anchors.fill: parent
    }

    // ----- Pan: arrastar com mouse ou um dedo -----
    DragHandler {
        target: null
        onActiveChanged: {
            if (active) {
                animacao.stop();
                mapa.arrastoIniciado();
            }
        }
        onTranslationChanged: (delta) => mapa.pan(delta.x, delta.y)
    }

    // ----- Zoom: pinça com dois dedos -----
    PinchHandler {
        id: pinca
        target: null
        grabPermissions: PointerHandler.TakeOverForbidden
        onActiveChanged: {
            if (active)
                animacao.stop();
        }
        onScaleChanged: (delta) => mapa.zoomEmTorno(mapa.zoom + Math.log2(delta), pinca.centroid.position.x, pinca.centroid.position.y)
    }

    // ----- Zoom: roda do mouse, centrado no ponteiro -----
    WheelHandler {
        id: roda
        // No macOS e no Wayland o touchpad também manda eventos de roda.
        acceptedDevices: Qt.platform.pluginName === "cocoa" || Qt.platform.pluginName === "wayland"
                         ? PointerDevice.Mouse | PointerDevice.TouchPad
                         : PointerDevice.Mouse
        onWheel: (evento) => {
            animacao.stop();
            mapa.zoomEmTorno(mapa.zoom + evento.angleDelta.y / 120, roda.point.position.x, roda.point.position.y);
        }
    }

    // ----- Toque simples avisa; toque duplo aproxima no ponto -----
    TapHandler {
        onTapped: (ponto) => mapa.tocado(ponto.position.x, ponto.position.y)
        onDoubleTapped: (ponto) => {
            const alvo = mapa.pontoParaMundo(ponto.position.x, ponto.position.y);
            mapa.animarPara(alvo.x + (mapa.mundoX - alvo.x) / 2, alvo.y + (mapa.mundoY - alvo.y) / 2, mapa.zoom + 1);
        }
    }

    ParallelAnimation {
        id: animacao
        property real destinoX: 0.5
        property real destinoY: 0.5
        property real zoomDestino: 13

        NumberAnimation {
            target: mapa
            property: "mundoX"
            to: animacao.destinoX
            duration: mapa.duracaoAnimacao
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: mapa
            property: "mundoY"
            to: animacao.destinoY
            duration: mapa.duracaoAnimacao
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: mapa
            property: "zoom"
            to: animacao.zoomDestino
            duration: mapa.duracaoAnimacao
            easing.type: Easing.InOutQuad
        }
    }

    // Atribuição exigida pela política de uso dos blocos do OSM.
    Rectangle {
        visible: mapa.mostrarAtribuicao
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: textoAtribuicao.implicitWidth + 8
        height: textoAtribuicao.implicitHeight + 4
        color: Qt.rgba(1, 1, 1, 0.8)

        Text {
            id: textoAtribuicao
            anchors.centerIn: parent
            text: mapa.atribuicao
            color: "#333333"
            font.pixelSize: 11
        }
    }
}
