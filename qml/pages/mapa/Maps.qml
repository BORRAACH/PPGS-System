import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtPositioning
import "../../components"

// Maps.qml — mapa em tela cheia (blocos do OpenStreetMap) com busca de
// endereços pelo Photon, marcadores, controles de zoom e localização,
// comparação de duas entregas (controllers/rotasController.py) e o botão
// "Verificar rota", que abre a barra lateral de cálculo de rotas pelo OSRM
// (PainelRotas.qml, com o traçado desenhado pela CamadaRotas.qml).
//
// Por que não usa o Map do QtLocation: o PyQt6 instalado pelo pip não traz o
// módulo QtLocation (nem no Linux, nem no Windows), e a página falhava logo
// no import. O mapa é o components/MapaBlocos.qml, em QML puro: cada bloco
// 256x256 do OSM é um Image posicionado pela projeção Web Mercator. Só o
// QtPositioning é usado (GPS e o tipo coordinate), e ele vem no PyQt6.
//
// A barra lateral, aberta, empurra o mapa para a direita: tudo o que fica
// sobre o mapa (busca, painéis, botões) mora dentro de areaMapa e acompanha a
// área que sobra.
Rectangle {
    id: raiz

    // Nome que o LateralBar compara para não recarregar a tela já aberta.
    objectName: "telaMapa"

    // =========================================================================
    // PERSONALIZAÇÃO
    // Tudo que muda a cara ou o comportamento da página fica aqui em cima.
    // Quem usa a página pode sobrescrever: Maps { corPrimaria: "#1976d2" }
    // =========================================================================

    // ----- Cores -----
    property color corPrimaria: "#e2661a"
    property color corPrimariaPressionada: "#bb3e00"
    property color corSuperficie: "#fffdf7"
    property color corSuperficieHover: "#f6e8d0"
    property color corSuperficiePressionada: "#eadaba"
    property color corBorda: "#cbb595"
    property color corTexto: "#33291f"
    property color corTextoSecundario: "#7a6549"
    property color corTextoSobrePrimaria: "#ffffff"
    property color corErro: "#cc0000"
    property color corMarcadorBusca: corPrimaria
    property color corMarcadorLocalizacao: "#2b7bb9"
    property color corMira: "#33291f"
    property color corFundoMapa: "#eae4d8" // aparece enquanto os blocos carregam
    property color corPizzaria: "#96320a"
    property color corEntregaA: "#1d7a8c"
    property color corEntregaB: "#7b3fa0"
    property color corRotaJuntas: "#e2661a"
    property color corSucesso: "#4b7029"
    property color corAviso: "#9a6212"

    // ----- Espaçamento e medidas -----
    // Abaixo de 640 px de largura a página entra no modo compacto (celular):
    // busca ocupa a largura toda e os alvos de toque crescem.
    readonly property bool compacto: areaMapa.width < 640
    property int espaco: compacto ? 8 : 12
    property int raioBorda: 8
    property int alturaControle: compacto ? 44 : 38
    property int larguraMaximaBusca: 520
    property int tamanhoFonte: compacto ? 15 : 14
    property int tamanhoFontePequena: 12

    // ----- Mapa -----
    // Pizzaria: Avenida dos Bombeiros, 375, Jardim Garcez, Taubaté-SP. O OSM
    // não tem o número 375 cadastrado; o ponto é o trecho da avenida no
    // Jardim Garcez (Nominatim).
    property var coordenadaPizzaria: QtPositioning.coordinate(-23.0016226, -45.5642446)
    property var coordenadaInicial: coordenadaPizzaria
    property real zoomInicial: 13
    property real zoomAoSelecionar: 17
    property real zoomMinimo: 2
    property real zoomMaximo: 19 // último nível servido pelo tile.openstreetmap.org
    property int duracaoAnimacao: 600
    property bool mostrarMira: true
    // Endereço dos blocos: {z} nível, {x} coluna, {y} linha.
    property string modeloUrlBlocos: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    property string atribuicao: "© OpenStreetMap contributors"

    // ----- Photon -----
    property string urlPhoton: "https://photon.komoot.io/api/"
    property int limiteSugestoes: 6
    property int minimoCaracteres: 3
    property int atrasoDigitacaoMs: 350
    property int tempoLimiteBuscaMs: 8000

    // ----- Rotas -----
    property int espessuraRota: 5
    // Folga, em pixels, entre as rotas e a borda da tela ao enquadrá-las.
    property int margemEnquadramento: 60

    // ----- Localização -----
    // Usada quando não há serviço de posição (desktop sem GPS, permissão
    // negada ou tempo esgotado). No computador do balcão, "onde estou" é a
    // própria pizzaria.
    property var localizacaoSimulada: coordenadaPizzaria
    property int tempoLimiteGpsMs: 6000

    // =========================================================================
    // ESTADO
    // =========================================================================

    property bool buscando: false
    property string avisoBusca: ""
    property bool avisoBuscaEhErro: false
    property var localizacaoAtual: QtPositioning.coordinate() // inválida até pedir
    property bool localizacaoEhSimulada: false

    // Barra lateral "Verificar rota" (PainelRotas) aberta.
    property bool modoVerificarRota: false
    // O MapaBlocos, com outro nome: dentro do PainelRotas e da CamadaRotas a
    // propriedade se chama "mapa", e "mapa: mapa" seria ambíguo.
    property alias mapaPrincipal: mapa

    // ----- Comparação de rotas -----
    // O serviço vem do Python (main.py). Com a página aberta sem ele, o painel
    // avisa em vez de quebrar.
    readonly property var rotas: typeof rotasController !== "undefined" ? rotasController : null
    property bool modoRotas: false
    property var entregaA: null // { latitude, longitude, titulo }
    property var entregaB: null
    property var comparacao: null // resultado de rotasController.comparar
    property bool comparando: false
    property string erroRotas: ""
    property string rotasVisiveis: "juntas" // "juntas" | "separadas"
    // Muda a cada troca de entrega: a resposta de um pedido anterior é ignorada.
    property int _geracaoRotas: 0
    property int _geracaoComparada: -1

    // Traçados prontos para desenhar (ver montarTracado).
    readonly property real escalaTracado: 256 * Math.pow(2, 14)
    readonly property var tracadoJuntas: comparacao ? montarTracado(comparacao.juntas.rota) : null
    readonly property var tracadoSeparadaA: comparacao ? montarTracado(comparacao.separadas.rotaA) : null
    readonly property var tracadoSeparadaB: comparacao ? montarTracado(comparacao.separadas.rotaB) : null

    readonly property var pontosRotas: {
        const pontos = [{ letra: "P", latitude: coordenadaPizzaria.latitude, longitude: coordenadaPizzaria.longitude, cor: corPizzaria }];
        if (entregaA)
            pontos.push({ letra: "A", latitude: entregaA.latitude, longitude: entregaA.longitude, cor: corEntregaA });
        if (entregaB)
            pontos.push({ letra: "B", latitude: entregaB.latitude, longitude: entregaB.longitude, cor: corEntregaB });
        return pontos;
    }

    // Requisição em andamento e um contador de gerações: a resposta de uma
    // busca que já foi substituída por outra mais nova é descartada.
    property var _requisicaoAtual: null
    property int _geracaoBusca: 0
    property bool _aguardandoGps: false

    color: corFundoMapa

    // =========================================================================
    // FUNÇÕES — projeção (Web Mercator)
    // As posições no mapa são guardadas "normalizadas": x e y de 0 a 1 cobrindo
    // o mundo inteiro. Em pixels, basta multiplicar por mapa.tamanhoMundo.
    // =========================================================================

    function limitar(valor, minimo, maximo) {
        return Math.max(minimo, Math.min(maximo, valor));
    }

    // A projeção é a do MapaBlocos.
    function paraMundo(latitude, longitude) {
        return mapa.paraMundo(latitude, longitude);
    }

    // =========================================================================
    // FUNÇÕES — navegação no mapa
    // =========================================================================

    // Voa até o ponto normalizado (x, y) ajustando o zoom junto.
    function animarPara(x, y, zoom) {
        mapa.animarPara(x, y, zoom);
    }

    // Move o mapa até a coordenada com animação; sem zoom, mantém o atual.
    function centralizar(coordenada, zoom) {
        if (!coordenada || !coordenada.isValid)
            return;
        const ponto = paraMundo(coordenada.latitude, coordenada.longitude);
        animarPara(ponto.x, ponto.y, zoom === undefined ? mapa.zoom : zoom);
    }

    function aproximar(passo) {
        animarPara(mapa.mundoX, mapa.mundoY, mapa.zoom + passo);
    }

    function formatarCoordenada(coordenada) {
        return coordenada.latitude.toFixed(5) + ", " + coordenada.longitude.toFixed(5);
    }

    // =========================================================================
    // FUNÇÕES — marcadores
    // =========================================================================

    function adicionarMarcador(coordenada, titulo, subtitulo) {
        modeloMarcadores.append({
            latitude: coordenada.latitude,
            longitude: coordenada.longitude,
            titulo: titulo || "",
            subtitulo: subtitulo || ""
        });
    }

    function limparMarcadores() {
        modeloMarcadores.clear();
        entregaA = null;
        entregaB = null;
        comparacao = null;
        comparando = false;
        erroRotas = "";
        ++_geracaoRotas;
        localizacaoAtual = QtPositioning.coordinate();
        localizacaoEhSimulada = false;
        campoBusca.clear();
        fecharSugestoes();
    }

    // =========================================================================
    // FUNÇÕES — busca no Photon
    // =========================================================================

    // Chamada a cada tecla: só dispara a requisição quando a digitação para.
    function agendarBusca(texto) {
        if (texto.trim().length < minimoCaracteres) {
            cancelarBusca();
            modeloSugestoes.clear();
            avisoBusca = "";
            return;
        }
        timerDigitacao.restart();
    }

    function cancelarBusca() {
        timerDigitacao.stop();
        timerTempoLimiteBusca.stop();
        if (_requisicaoAtual) {
            const requisicao = _requisicaoAtual;
            _requisicaoAtual = null; // antes do abort: o DONE dele será ignorado
            requisicao.abort();
        }
        buscando = false;
    }

    function buscarPhoton(termo) {
        cancelarBusca();
        if (termo.length === 0)
            return;

        const geracao = ++_geracaoBusca;
        // lat/lon do centro do mapa dão preferência a resultados próximos.
        const url = urlPhoton
            + "?q=" + encodeURIComponent(termo)
            + "&limit=" + limiteSugestoes
            + "&lat=" + mapa.centro.latitude.toFixed(5)
            + "&lon=" + mapa.centro.longitude.toFixed(5);

        const requisicao = new XMLHttpRequest();
        _requisicaoAtual = requisicao;
        buscando = true;
        avisoBusca = "";

        requisicao.onreadystatechange = function () {
            if (requisicao.readyState !== XMLHttpRequest.DONE)
                return;
            // Abortada, expirada ou substituída por uma busca mais nova.
            if (geracao !== raiz._geracaoBusca || requisicao !== raiz._requisicaoAtual)
                return;

            raiz._requisicaoAtual = null;
            timerTempoLimiteBusca.stop();
            raiz.buscando = false;

            if (requisicao.status === 0) {
                raiz.mostrarErroBusca("Sem conexão com o serviço de endereços.");
                return;
            }
            if (requisicao.status === 429) {
                raiz.mostrarErroBusca("Muitas buscas seguidas. Aguarde um instante.");
                return;
            }
            if (requisicao.status < 200 || requisicao.status >= 300) {
                raiz.mostrarErroBusca("O serviço de endereços respondeu com erro " + requisicao.status + ".");
                return;
            }

            let dados;
            try {
                dados = JSON.parse(requisicao.responseText);
            } catch (erro) {
                raiz.mostrarErroBusca("Resposta inválida do serviço de endereços.");
                return;
            }
            raiz.preencherSugestoes(dados && Array.isArray(dados.features) ? dados.features : []);
        };

        try {
            requisicao.open("GET", url);
            requisicao.setRequestHeader("Accept", "application/json");
            requisicao.send();
            timerTempoLimiteBusca.restart();
        } catch (erro) {
            _requisicaoAtual = null;
            buscando = false;
            mostrarErroBusca("Não foi possível iniciar a busca: " + erro);
        }
    }

    function mostrarErroBusca(mensagem) {
        modeloSugestoes.clear();
        avisoBusca = mensagem;
        avisoBuscaEhErro = true;
    }

    // Converte as features GeoJSON do Photon em linhas do modelo de sugestões.
    function preencherSugestoes(features) {
        modeloSugestoes.clear();
        for (let i = 0; i < features.length; ++i) {
            const geometria = features[i].geometry;
            const p = features[i].properties || {};
            // GeoJSON guarda [longitude, latitude], nessa ordem.
            if (!geometria || !Array.isArray(geometria.coordinates) || geometria.coordinates.length < 2)
                continue;
            const titulo = tituloDoLugar(p);
            modeloSugestoes.append({
                titulo: titulo,
                subtitulo: subtituloDoLugar(p, titulo),
                latitude: Number(geometria.coordinates[1]),
                longitude: Number(geometria.coordinates[0])
            });
        }
        if (modeloSugestoes.count === 0) {
            avisoBusca = "Nenhum endereço encontrado.";
            avisoBuscaEhErro = false;
        } else {
            avisoBusca = "";
            listaSugestoes.currentIndex = 0;
        }
    }

    function ruaDoLugar(p) {
        if (!p.street)
            return "";
        return p.housenumber ? p.street + ", " + p.housenumber : p.street;
    }

    // Nome do estabelecimento/lugar; senão a rua; senão a cidade.
    function tituloDoLugar(p) {
        return p.name || ruaDoLugar(p) || p.city || p.state || p.country || "Local sem nome";
    }

    // Complemento sem repetir o que já está no título: "Rua • Bairro • Cidade • UF".
    function subtituloDoLugar(p, titulo) {
        const partes = [ruaDoLugar(p), p.district || p.locality, p.city, p.state, p.country];
        const vistas = {};
        vistas[titulo] = true;
        return partes.filter(function (parte) {
            if (!parte || vistas[parte])
                return false;
            vistas[parte] = true;
            return true;
        }).join(" • ");
    }

    function selecionarSugestao(indice) {
        if (indice < 0 || indice >= modeloSugestoes.count)
            return;
        const s = modeloSugestoes.get(indice);
        const coordenada = QtPositioning.coordinate(s.latitude, s.longitude);
        // Com o painel de rotas aberto, o endereço vira a entrega A ou B.
        if (modoRotas) {
            definirEntrega(s.latitude, s.longitude, s.titulo);
            centralizar(coordenada, Math.max(mapa.zoom, 14));
        } else {
            adicionarMarcador(coordenada, s.titulo, s.subtitulo);
            centralizar(coordenada, zoomAoSelecionar);
        }
        campoBusca.text = s.titulo; // atribuição não emite textEdited: não rebusca
        fecharSugestoes();
    }

    // Enter: escolhe a sugestão destacada ou, se ainda não há lista, busca já.
    function confirmarBusca() {
        if (modeloSugestoes.count > 0) {
            selecionarSugestao(Math.max(listaSugestoes.currentIndex, 0));
            return;
        }
        buscarPhoton(campoBusca.text.trim());
    }

    function fecharSugestoes() {
        cancelarBusca();
        modeloSugestoes.clear();
        avisoBusca = "";
        campoBusca.focus = false;
    }

    // =========================================================================
    // FUNÇÕES — localização atual
    // =========================================================================

    function irParaLocalizacaoAtual() {
        if (!gps.valid) {
            usarLocalizacaoSimulada("Serviço de localização indisponível. Usando posição simulada.");
            return;
        }
        _aguardandoGps = true;
        timerTempoLimiteGps.restart();
        mostrarAviso("Obtendo localização…", false);
        gps.update();
    }

    function aplicarLocalizacao(coordenada, simulada) {
        _aguardandoGps = false;
        timerTempoLimiteGps.stop();
        localizacaoAtual = coordenada;
        localizacaoEhSimulada = simulada;
        centralizar(coordenada, Math.max(mapa.zoom, 16));
        if (!simulada)
            aviso.opacity = 0;
    }

    function usarLocalizacaoSimulada(motivo) {
        aplicarLocalizacao(localizacaoSimulada, true);
        mostrarAviso(motivo, false);
    }

    function descreverErroGps(erro) {
        switch (erro) {
        case PositionSource.AccessError:
            return "permissão negada";
        case PositionSource.ClosedError:
            return "serviço desligado";
        case PositionSource.UpdateTimeoutError:
            return "tempo esgotado";
        default:
            return "erro desconhecido";
        }
    }

    // =========================================================================
    // FUNÇÕES — comparação de rotas
    // =========================================================================

    function abrirRotas() {
        modoRotas = true;
        // Começa a carregar o grafo já: na primeira vez ele é baixado.
        if (rotas)
            rotas.prepararGrafo(coordenadaPizzaria.latitude, coordenadaPizzaria.longitude);
    }

    function fecharRotas() {
        modoRotas = false;
    }

    // Endereço escolhido na busca com o painel aberto: preenche a A, depois a
    // B; com as duas já escolhidas, troca a B.
    function definirEntrega(latitude, longitude, titulo) {
        const entrega = { latitude: latitude, longitude: longitude, titulo: titulo };
        if (entregaA === null)
            entregaA = entrega;
        else
            entregaB = entrega;
        descartarComparacao();
    }

    function removerEntrega(letra) {
        if (letra === "A") {
            entregaA = entregaB;
            entregaB = null;
        } else {
            entregaB = null;
        }
        descartarComparacao();
    }

    function descartarComparacao() {
        comparacao = null;
        comparando = false;
        erroRotas = "";
        ++_geracaoRotas;
    }

    function compararRotas() {
        if (!rotas || entregaA === null || entregaB === null)
            return;
        comparacao = null;
        erroRotas = "";
        comparando = true;
        _geracaoComparada = _geracaoRotas;
        rotas.comparar(coordenadaPizzaria.latitude, coordenadaPizzaria.longitude,
                       entregaA.latitude, entregaA.longitude,
                       entregaB.latitude, entregaB.longitude);
    }

    // Frase do veredito. "Fora do caminho" não quer dizer que separadas seja
    // melhor: com um motoboy só, juntar nunca demora mais no total (os
    // caminhos mínimos obedecem à desigualdade triangular). O que passa do
    // limite é a espera extra de quem fica por último.
    function textoVeredito(c) {
        if (!c)
            return "";
        const d = c.desvio;
        const atraso = d.segundos < 60 ? "menos de 1 min" : formatarTempo(d.segundos);
        if (c.aCaminho)
            return "A caminho: " + d.segunda + " atrasa " + atraso + " passando antes em " + d.primeira;
        return "Fora do caminho: " + d.segunda + " atrasa " + atraso + " passando antes em " + d.primeira
               + (c.economiaSegundos >= 60 ? ", mas juntas economiza " + formatarTempo(c.economiaSegundos) : "");
    }

    function formatarTempo(segundos) {
        const minutos = Math.round(segundos / 60);
        if (minutos < 60)
            return minutos + " min";
        return Math.floor(minutos / 60) + " h " + (minutos % 60) + " min";
    }

    function formatarDistancia(metros) {
        if (metros < 1000)
            return Math.round(metros) + " m";
        return (metros / 1000).toFixed(1).replace(".", ",") + " km";
    }

    // Traçado [lat, lon, lat, lon, ...] em pontos para o Shape. Cada ponto é o
    // deslocamento até o primeiro, em pixels de um zoom fixo (escalaTracado):
    // no pan e no zoom a camada só é movida e escalada, sem recalcular pontos.
    function montarTracado(plano) {
        if (!plano || plano.length < 4)
            return null;
        const origem = paraMundo(plano[0], plano[1]);
        const pontos = [];
        let minX = origem.x, minY = origem.y, maxX = origem.x, maxY = origem.y;
        for (let i = 0; i + 1 < plano.length; i += 2) {
            const p = paraMundo(plano[i], plano[i + 1]);
            pontos.push(Qt.point((p.x - origem.x) * escalaTracado, (p.y - origem.y) * escalaTracado));
            minX = Math.min(minX, p.x);
            minY = Math.min(minY, p.y);
            maxX = Math.max(maxX, p.x);
            maxY = Math.max(maxY, p.y);
        }
        return { x: origem.x, y: origem.y, pontos: pontos, minX: minX, minY: minY, maxX: maxX, maxY: maxY };
    }

    // Aproxima ou afasta até os traçados caberem na parte da tela que o
    // painel de rotas não cobre.
    function enquadrar(tracados) {
        let minX = 1, minY = 1, maxX = 0, maxY = 0;
        for (let i = 0; i < tracados.length; ++i) {
            const t = tracados[i];
            if (!t)
                continue;
            minX = Math.min(minX, t.minX);
            minY = Math.min(minY, t.minY);
            maxX = Math.max(maxX, t.maxX);
            maxY = Math.max(maxY, t.maxY);
        }
        if (maxX < minX || maxY < minY)
            return;
        // No desktop o painel cobre a esquerda; no celular, o alto da tela.
        const lateral = compacto ? 0 : painelRotas.width + espaco;
        const topo = compacto ? painelRotas.y + painelRotas.height : 0;
        const largura = Math.max(1, mapa.width - lateral - 2 * margemEnquadramento);
        const altura = Math.max(1, mapa.height - topo - 2 * margemEnquadramento);
        const zoom = limitar(Math.log2(Math.min(largura / Math.max((maxX - minX) * 256, 1e-9),
                                                altura / Math.max((maxY - minY) * 256, 1e-9))),
                             zoomMinimo, zoomMaximo);
        // O centro anda meio painel para o lado livre: as rotas ficam no meio
        // da área que sobra, não atrás do painel.
        const tamanho = 256 * Math.pow(2, zoom);
        animarPara((minX + maxX) / 2 - lateral / 2 / tamanho, (minY + maxY) / 2 - topo / 2 / tamanho, zoom);
    }

    // =========================================================================
    // FUNÇÕES — avisos
    // =========================================================================

    function mostrarAviso(texto, ehErro) {
        aviso.texto = texto;
        aviso.ehErro = !!ehErro;
        aviso.opacity = 1;
        timerAviso.restart();
    }

    // Um bloco que falha avisa uma vez; os seguintes ficam quietos por 30 s
    // para não piscar um aviso por bloco quando a internet cai.
    function registrarFalhaBloco() {
        if (timerSilencioFalhaBloco.running)
            return;
        mostrarAviso("Não foi possível carregar partes do mapa. Verifique a conexão.", true);
        timerSilencioFalhaBloco.start();
    }

    // =========================================================================
    // MODELOS, TIMERS E FONTES DE DADOS
    // =========================================================================

    // Cada linha: titulo, subtitulo, latitude, longitude.
    ListModel { id: modeloSugestoes }
    ListModel { id: modeloMarcadores }

    // O Column do painel só recalcula a altura no quadro seguinte; enquadrar
    // antes disso usaria a altura do painel ainda sem o resultado.
    Timer {
        id: timerEnquadrarRotas
        interval: 100
        onTriggered: raiz.enquadrar([raiz.tracadoJuntas, raiz.tracadoSeparadaA, raiz.tracadoSeparadaB])
    }

    Connections {
        target: raiz.rotas

        function onComparacaoPronta(resultado) {
            if (raiz._geracaoComparada !== raiz._geracaoRotas)
                return; // as entregas mudaram durante o cálculo
            raiz.comparando = false;
            raiz.comparacao = resultado;
            timerEnquadrarRotas.restart();
        }

        function onComparacaoFalhou(mensagem) {
            if (raiz._geracaoComparada !== raiz._geracaoRotas)
                return;
            raiz.comparando = false;
            raiz.erroRotas = mensagem;
        }
    }

    Timer {
        id: timerDigitacao
        interval: raiz.atrasoDigitacaoMs
        onTriggered: raiz.buscarPhoton(campoBusca.text.trim())
    }

    // O XMLHttpRequest do QML não tem timeout próprio confiável: quem aborta é
    // este Timer, e assim nenhuma busca fica "carregando" para sempre.
    Timer {
        id: timerTempoLimiteBusca
        interval: raiz.tempoLimiteBuscaMs
        onTriggered: {
            if (!raiz._requisicaoAtual)
                return;
            raiz.cancelarBusca();
            raiz.mostrarErroBusca("A busca demorou demais. Verifique a conexão e tente de novo.");
        }
    }

    Timer {
        id: timerTempoLimiteGps
        interval: raiz.tempoLimiteGpsMs
        onTriggered: {
            if (raiz._aguardandoGps)
                raiz.usarLocalizacaoSimulada("A localização não respondeu a tempo. Usando posição simulada.");
        }
    }

    Timer {
        id: timerSilencioFalhaBloco
        interval: 30000
    }

    PositionSource {
        id: gps
        active: false // só uma leitura quando o botão é tocado (gps.update())
        preferredPositioningMethods: PositionSource.AllPositioningMethods

        onPositionChanged: {
            if (raiz._aguardandoGps && position.latitudeValid && position.longitudeValid)
                raiz.aplicarLocalizacao(position.coordinate, false);
        }
        onSourceErrorChanged: {
            if (raiz._aguardandoGps && sourceError !== PositionSource.NoError)
                raiz.usarLocalizacaoSimulada("Sem localização (" + raiz.descreverErroGps(sourceError) + "). Usando posição simulada.");
        }
    }

    // =========================================================================
    // BARRA LATERAL "VERIFICAR ROTA" E MAPA
    // =========================================================================

    PainelRotas {
        id: painelVerificarRota

        visible: raiz.modoVerificarRota
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        // Numa tela estreita a barra ocupa tudo; o X dela devolve o mapa.
        width: visible ? Math.min(400, raiz.width < 720 ? raiz.width : raiz.width * 0.5) : 0
        mapa: raiz.mapaPrincipal
        onFecharSolicitado: raiz.modoVerificarRota = false
    }

    Item {
        id: areaMapa

        anchors.left: painelVerificarRota.visible ? painelVerificarRota.right : parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        clip: true

        MapaBlocos {
            id: mapa

            anchors.fill: parent
            zoomMinimo: raiz.zoomMinimo
            zoomMaximo: raiz.zoomMaximo
            duracaoAnimacao: raiz.duracaoAnimacao
            modeloUrlBlocos: raiz.modeloUrlBlocos
            atribuicao: raiz.atribuicao
            corFundo: raiz.corFundoMapa
            // A atribuição já está no painel de informações.
            mostrarAtribuicao: false

            Component.onCompleted: definirCentro(raiz.coordenadaInicial.latitude, raiz.coordenadaInicial.longitude, raiz.zoomInicial)

            // Toque no mapa fecha a lista de sugestões; arrastar tira o foco da busca.
            onTocado: {
                if (modeloSugestoes.count > 0 || raiz.avisoBusca !== "")
                    raiz.fecharSugestoes();
                else
                    campoBusca.focus = false;
            }
            onArrastoIniciado: campoBusca.focus = false
            onBlocoFalhou: raiz.registrarFalhaBloco()

            // ----- Rotas da comparação (entre os blocos e os marcadores) -----
            Item {
                id: camadaRotas
                anchors.fill: parent
                z: 3
                visible: raiz.modoRotas && raiz.comparacao !== null

                Repeater {
                    model: raiz.rotasVisiveis === "juntas"
                           ? [{ tracado: raiz.tracadoJuntas, cor: raiz.corRotaJuntas }]
                           : [{ tracado: raiz.tracadoSeparadaA, cor: raiz.corEntregaA },
                              { tracado: raiz.tracadoSeparadaB, cor: raiz.corEntregaB }]

                    delegate: Item {
                        id: desenhoRota

                        required property var modelData
                        readonly property var tracado: modelData.tracado
                        // Pixels de tela por unidade do traçado.
                        readonly property real escala: mapa.tamanhoMundo / raiz.escalaTracado

                        visible: tracado !== null
                        x: tracado ? (tracado.x - mapa.mundoX) * mapa.tamanhoMundo + mapa.width / 2 : 0
                        y: tracado ? (tracado.y - mapa.mundoY) * mapa.tamanhoMundo + mapa.height / 2 : 0
                        scale: escala
                        transformOrigin: Item.TopLeft

                        Shape {
                            // Contorno branco por baixo: a rota não some sobre uma
                            // avenida da mesma cor.
                            ShapePath {
                                strokeColor: "white"
                                strokeWidth: (raiz.espessuraRota + 3) / desenhoRota.escala
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                joinStyle: ShapePath.RoundJoin
                                PathPolyline { path: desenhoRota.tracado ? desenhoRota.tracado.pontos : [] }
                            }
                            ShapePath {
                                strokeColor: desenhoRota.modelData.cor
                                strokeWidth: raiz.espessuraRota / desenhoRota.escala
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                joinStyle: ShapePath.RoundJoin
                                PathPolyline { path: desenhoRota.tracado ? desenhoRota.tracado.pontos : [] }
                            }
                        }
                    }
                }
            }

            // ----- Pizzaria e entregas A e B (com o painel de rotas aberto) -----
            Repeater {
                model: raiz.modoRotas ? raiz.pontosRotas : []

                delegate: Item {
                    id: pontoRota

                    required property var modelData
                    readonly property var ponto: raiz.paraMundo(modelData.latitude, modelData.longitude)

                    z: 12
                    width: 28
                    height: 28
                    x: Math.round((ponto.x - mapa.mundoX) * mapa.tamanhoMundo + mapa.width / 2 - width / 2)
                    y: Math.round((ponto.y - mapa.mundoY) * mapa.tamanhoMundo + mapa.height / 2 - height / 2)

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: pontoRota.modelData.cor
                        border.color: "white"
                        border.width: 2

                        Text {
                            anchors.centerIn: parent
                            text: pontoRota.modelData.letra
                            color: "white"
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                    }
                }
            }

            // ----- Marcador da localização atual (ponto azul pulsante) -----
            Item {
                id: marcadorLocalizacao

                readonly property var ponto: raiz.localizacaoAtual.isValid
                                             ? raiz.paraMundo(raiz.localizacaoAtual.latitude, raiz.localizacaoAtual.longitude)
                                             : ({ x: 0, y: 0 })

                visible: raiz.localizacaoAtual.isValid
                z: 5
                width: 44
                height: 44
                // O centro do ponto fica sobre a coordenada.
                x: Math.round((ponto.x - mapa.mundoX) * mapa.tamanhoMundo + mapa.width / 2 - width / 2)
                y: Math.round((ponto.y - mapa.mundoY) * mapa.tamanhoMundo + mapa.height / 2 - height / 2)

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: raiz.corMarcadorLocalizacao
                    opacity: 0.2

                    SequentialAnimation on scale {
                        running: marcadorLocalizacao.visible
                        loops: Animation.Infinite
                        NumberAnimation { from: 0.4; to: 1; duration: 1200; easing.type: Easing.OutQuad }
                        PauseAnimation { duration: 300 }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    radius: 9
                    // Posição simulada aparece num tom mais claro.
                    color: raiz.localizacaoEhSimulada ? Qt.lighter(raiz.corMarcadorLocalizacao, 1.5) : raiz.corMarcadorLocalizacao
                    border.color: "white"
                    border.width: 3
                }
            }

            // ----- Marcadores das buscas -----
            Repeater {
                model: modeloMarcadores

                delegate: Item {
                    id: marcador

                    required property int index
                    required property real latitude
                    required property real longitude
                    required property string titulo
                    required property string subtitulo

                    readonly property var ponto: raiz.paraMundo(latitude, longitude)
                    // Só o marcador mais recente abre com o nome; tocar alterna.
                    property bool rotuloVisivel: index === modeloMarcadores.count - 1

                    z: 10
                    width: 30
                    height: 32
                    // A ponta da gota fica exatamente sobre a coordenada.
                    x: Math.round((ponto.x - mapa.mundoX) * mapa.tamanhoMundo + mapa.width / 2 - width / 2)
                    y: Math.round((ponto.y - mapa.mundoY) * mapa.tamanhoMundo + mapa.height / 2 - height)

                    // Gota: quadrado com três cantos redondos girado 45°, o canto
                    // reto aponta para baixo.
                    Rectangle {
                        x: 2
                        y: 0
                        width: 26
                        height: 26
                        radius: 13
                        bottomRightRadius: 0
                        rotation: 45
                        antialiasing: true
                        color: raiz.corMarcadorBusca
                        border.color: "white"
                        border.width: 2
                    }
                    Rectangle {
                        x: 10
                        y: 8
                        width: 10
                        height: 10
                        radius: 5
                        color: "white"
                    }

                    // Balão com o nome do lugar, acima da gota.
                    Rectangle {
                        visible: marcador.rotuloVisivel && marcador.titulo !== ""
                        anchors.bottom: parent.top
                        anchors.bottomMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(textoRotulo.implicitWidth + 16, 240)
                        height: textoRotulo.implicitHeight + 8
                        radius: 4
                        color: raiz.corSuperficie
                        border.color: raiz.corBorda

                        Text {
                            id: textoRotulo
                            anchors.centerIn: parent
                            width: parent.width - 16
                            text: marcador.titulo
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            color: raiz.corTexto
                            font.pixelSize: raiz.tamanhoFontePequena
                            font.weight: Font.DemiBold
                        }
                    }

                    TapHandler {
                        onTapped: marcador.rotuloVisivel = !marcador.rotuloVisivel
                    }
                }
            }

            // ----- Rotas da barra "Verificar rota" -----
            CamadaRotas {
                z: 4
                visible: raiz.modoVerificarRota
                painel: painelVerificarRota
                mapa: raiz.mapaPrincipal
            }
        }

        // Mira no centro: é a este ponto que as coordenadas exibidas se referem.
        Item {
            visible: raiz.mostrarMira
            anchors.centerIn: parent
            width: 22
            height: 22
            opacity: 0.55

            Rectangle { anchors.centerIn: parent; width: parent.width; height: 2; color: raiz.corMira }
            Rectangle { anchors.centerIn: parent; width: 2; height: parent.height; color: raiz.corMira }
        }

        // =========================================================================
        // BUSCA (topo)
        // =========================================================================

        Column {
            id: barraBusca
            z: 20
            anchors.top: parent.top
            anchors.topMargin: raiz.espaco
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(raiz.larguraMaximaBusca, areaMapa.width - 2 * raiz.espaco)
            spacing: 4

            // ----- Caixa do campo -----
            Rectangle {
                width: parent.width
                height: raiz.alturaControle + 4
                radius: raiz.raioBorda
                color: raiz.corSuperficie
                border.color: campoBusca.activeFocus ? raiz.corPrimaria : raiz.corBorda
                border.width: campoBusca.activeFocus ? 2 : 1

                // Lupa desenhada (não depende de fonte de ícones).
                Item {
                    id: lupa
                    anchors.left: parent.left
                    anchors.leftMargin: raiz.espaco
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18

                    Rectangle {
                        width: 13
                        height: 13
                        radius: 6.5
                        color: "transparent"
                        border.color: raiz.corTextoSecundario
                        border.width: 2
                    }
                    Rectangle {
                        x: 11
                        y: 10
                        width: 2.5
                        height: 7
                        radius: 1
                        rotation: -45
                        antialiasing: true
                        color: raiz.corTextoSecundario
                    }
                }

                TextField {
                    id: campoBusca
                    anchors.left: lupa.right
                    anchors.leftMargin: raiz.espaco / 2
                    anchors.right: acoesCampo.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: raiz.alturaControle

                    placeholderText: "Buscar endereço…"
                    placeholderTextColor: raiz.corTextoSecundario
                    color: raiz.corTexto
                    selectByMouse: true
                    font.pixelSize: raiz.tamanhoFonte
                    inputMethodHints: Qt.ImhNoPredictiveText
                    background: null

                    // textEdited só vem da digitação, não de "text = ..." no código.
                    onTextEdited: raiz.agendarBusca(text)

                    Keys.onDownPressed: {
                        if (listaSugestoes.count > 0) {
                            listaSugestoes.currentIndex = Math.min(listaSugestoes.currentIndex + 1, listaSugestoes.count - 1);
                            listaSugestoes.positionViewAtIndex(listaSugestoes.currentIndex, ListView.Contain);
                        }
                    }
                    Keys.onUpPressed: {
                        if (listaSugestoes.count > 0) {
                            listaSugestoes.currentIndex = Math.max(listaSugestoes.currentIndex - 1, 0);
                            listaSugestoes.positionViewAtIndex(listaSugestoes.currentIndex, ListView.Contain);
                        }
                    }
                    Keys.onReturnPressed: raiz.confirmarBusca()
                    Keys.onEnterPressed: raiz.confirmarBusca()
                    Keys.onEscapePressed: raiz.fecharSugestoes()
                }

                Row {
                    id: acoesCampo
                    anchors.right: parent.right
                    anchors.rightMargin: raiz.espaco / 2
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    BusyIndicator {
                        anchors.verticalCenter: parent.verticalCenter
                        width: raiz.alturaControle * 0.7
                        height: width
                        running: raiz.buscando
                        visible: running
                    }

                    // Apaga o texto digitado (os marcadores ficam).
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: campoBusca.text.length > 0
                        width: raiz.alturaControle * 0.8
                        height: width
                        radius: width / 2
                        color: areaApagar.pressed ? raiz.corSuperficiePressionada
                             : areaApagar.containsMouse ? raiz.corSuperficieHover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: raiz.corTextoSecundario
                            font.pixelSize: raiz.tamanhoFonte
                        }
                        MouseArea {
                            id: areaApagar
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                campoBusca.clear();
                                raiz.fecharSugestoes();
                                campoBusca.forceActiveFocus();
                            }
                        }
                    }
                }
            }

            // ----- Painel de sugestões / aviso da busca -----
            Rectangle {
                width: parent.width
                height: visible ? conteudoSugestoes.height : 0
                visible: modeloSugestoes.count > 0 || raiz.avisoBusca !== ""
                radius: raiz.raioBorda
                color: raiz.corSuperficie
                border.color: raiz.corBorda
                clip: true

                Column {
                    id: conteudoSugestoes
                    width: parent.width

                    Text {
                        visible: raiz.avisoBusca !== ""
                        width: parent.width
                        padding: raiz.espaco
                        text: raiz.avisoBusca
                        wrapMode: Text.Wrap
                        color: raiz.avisoBuscaEhErro ? raiz.corErro : raiz.corTextoSecundario
                        font.pixelSize: raiz.tamanhoFontePequena + 1
                    }

                    ListView {
                        id: listaSugestoes
                        width: parent.width
                        height: Math.min(contentHeight, areaMapa.height * (raiz.compacto ? 0.45 : 0.5))
                        visible: count > 0
                        model: modeloSugestoes
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            id: itemSugestao

                            required property int index
                            required property string titulo
                            required property string subtitulo

                            width: ListView.view.width
                            height: Math.max(raiz.alturaControle, textosSugestao.implicitHeight + raiz.espaco)
                            color: toqueSugestao.pressed ? raiz.corSuperficiePressionada
                                 : itemSugestao.ListView.isCurrentItem || cursorSugestao.hovered ? raiz.corSuperficieHover
                                 : "transparent"

                            Column {
                                id: textosSugestao
                                anchors.verticalCenter: parent.verticalCenter
                                x: raiz.espaco
                                width: parent.width - 2 * raiz.espaco
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: itemSugestao.titulo
                                    elide: Text.ElideRight
                                    color: raiz.corTexto
                                    font.pixelSize: raiz.tamanhoFonte
                                    font.weight: Font.Medium
                                }
                                Text {
                                    width: parent.width
                                    visible: text !== ""
                                    text: itemSugestao.subtitulo
                                    elide: Text.ElideRight
                                    color: raiz.corTextoSecundario
                                    font.pixelSize: raiz.tamanhoFontePequena
                                }
                            }

                            // Separador entre itens.
                            Rectangle {
                                visible: itemSugestao.index < modeloSugestoes.count - 1
                                anchors.bottom: parent.bottom
                                x: raiz.espaco
                                width: parent.width - 2 * raiz.espaco
                                height: 1
                                color: raiz.corSuperficiePressionada
                            }

                            HoverHandler {
                                id: cursorSugestao
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                id: toqueSugestao
                                onTapped: raiz.selecionarSugestao(itemSugestao.index)
                            }
                        }
                    }
                }
            }
        }

        // Aviso flutuante (localização, falha de rede), logo abaixo da busca.
        Rectangle {
            id: aviso
            z: 25

            property alias texto: textoAviso.text
            property bool ehErro: false

            anchors.top: barraBusca.bottom
            anchors.topMargin: raiz.espaco
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(textoAviso.implicitWidth, areaMapa.width - 4 * raiz.espaco)
            height: textoAviso.implicitHeight
            radius: raiz.raioBorda
            color: ehErro ? raiz.corErro : raiz.corTexto
            opacity: 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: 200 } }

            Text {
                id: textoAviso
                width: parent.width
                padding: raiz.espaco
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                color: raiz.corTextoSobrePrimaria
                font.pixelSize: raiz.tamanhoFontePequena + 1
            }

            Timer {
                id: timerAviso
                interval: 3500
                onTriggered: aviso.opacity = 0
            }
        }

        // =========================================================================
        // COMPARAR ROTAS (painel à esquerda, logo abaixo do campo de busca)
        // =========================================================================

        Rectangle {
            id: painelRotas

            visible: raiz.modoRotas
            z: 10
            x: raiz.espaco
            y: barraBusca.y + raiz.alturaControle + 4 + raiz.espaco
            width: raiz.compacto ? areaMapa.width - 2 * raiz.espaco : 330
            height: Math.max(0, Math.min(conteudoRotas.implicitHeight + 2 * raiz.espaco,
                                         areaMapa.height - y - painelInfo.height - 3 * raiz.espaco))
            radius: raiz.raioBorda
            color: raiz.corSuperficie
            border.color: raiz.corBorda

            // Segura cliques e arrastos: sem isto eles atravessariam o painel e
            // moveriam o mapa por baixo.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                onWheel: (evento) => evento.accepted = true
            }

            Flickable {
                anchors.fill: parent
                anchors.margins: raiz.espaco
                contentHeight: conteudoRotas.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: conteudoRotas
                    width: parent.width
                    spacing: raiz.espaco * 0.75

                    Item {
                        width: parent.width
                        height: tituloRotas.implicitHeight

                        Text {
                            id: tituloRotas
                            text: "Comparar entregas"
                            color: raiz.corTexto
                            font.pixelSize: raiz.tamanhoFonte + 1
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "✕"
                            color: raiz.corTextoSecundario
                            font.pixelSize: raiz.tamanhoFonte

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                cursorShape: Qt.PointingHandCursor
                                onClicked: raiz.fecharRotas()
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: raiz.entregaA === null || raiz.entregaB === null
                        wrapMode: Text.Wrap
                        text: raiz.entregaA === null
                              ? "Busque no campo acima o endereço da primeira entrega."
                              : "Agora busque o endereço da segunda entrega."
                        color: raiz.corTextoSecundario
                        font.pixelSize: raiz.tamanhoFontePequena + 1
                    }

                    // ----- Entregas A e B -----
                    Repeater {
                        model: [
                            { letra: "A", entrega: raiz.entregaA, cor: raiz.corEntregaA },
                            { letra: "B", entrega: raiz.entregaB, cor: raiz.corEntregaB }
                        ]

                        delegate: Rectangle {
                            id: linhaEntrega

                            required property var modelData

                            width: conteudoRotas.width
                            height: raiz.alturaControle
                            radius: raiz.raioBorda
                            color: modelData.entrega ? raiz.corSuperficieHover : "transparent"
                            border.color: raiz.corBorda

                            Rectangle {
                                id: seloEntrega
                                anchors.left: parent.left
                                anchors.leftMargin: raiz.espaco / 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                height: 24
                                radius: 12
                                color: linhaEntrega.modelData.cor

                                Text {
                                    anchors.centerIn: parent
                                    text: linhaEntrega.modelData.letra
                                    color: "white"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                            }

                            Text {
                                anchors.left: seloEntrega.right
                                anchors.leftMargin: raiz.espaco / 2
                                anchors.right: botaoRemoverEntrega.left
                                anchors.rightMargin: raiz.espaco / 2
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: linhaEntrega.modelData.entrega
                                      ? linhaEntrega.modelData.entrega.titulo
                                      : "Entrega " + linhaEntrega.modelData.letra + " ainda não escolhida"
                                color: linhaEntrega.modelData.entrega ? raiz.corTexto : raiz.corTextoSecundario
                                font.pixelSize: raiz.tamanhoFontePequena + 1
                            }

                            Text {
                                id: botaoRemoverEntrega
                                anchors.right: parent.right
                                anchors.rightMargin: raiz.espaco
                                anchors.verticalCenter: parent.verticalCenter
                                visible: linhaEntrega.modelData.entrega !== null
                                text: "✕"
                                color: raiz.corTextoSecundario
                                font.pixelSize: raiz.tamanhoFontePequena + 1

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: raiz.removerEntrega(linhaEntrega.modelData.letra)
                                }
                            }
                        }
                    }

                    Button {
                        id: botaoComparar
                        width: parent.width
                        height: raiz.alturaControle
                        enabled: raiz.rotas !== null && raiz.entregaA !== null && raiz.entregaB !== null && !raiz.comparando
                        text: raiz.comparando ? "Calculando…" : "Comparar rotas"
                        focusPolicy: Qt.NoFocus
                        onClicked: raiz.compararRotas()

                        background: Rectangle {
                            radius: raiz.raioBorda
                            color: !botaoComparar.enabled ? raiz.corSuperficiePressionada
                                 : botaoComparar.down ? raiz.corPrimariaPressionada : raiz.corPrimaria
                        }
                        contentItem: Text {
                            text: botaoComparar.text
                            color: botaoComparar.enabled ? raiz.corTextoSobrePrimaria : raiz.corTextoSecundario
                            font.pixelSize: raiz.tamanhoFonte
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    // ----- Andamento e erros -----
                    Text {
                        readonly property bool ehErro: raiz.rotas === null || raiz.erroRotas !== ""
                                                       || (raiz.rotas.estado === "erro" && !raiz.comparando)
                        readonly property string conteudo: raiz.rotas === null
                            ? "Comparação de rotas indisponível: o serviço de rotas não foi carregado."
                            : raiz.erroRotas !== "" ? raiz.erroRotas
                            : raiz.rotas.estado === "erro" ? raiz.rotas.mensagem
                            : (raiz.comparando || raiz.rotas.estado === "carregando") ? raiz.rotas.mensagem
                            : ""

                        width: parent.width
                        visible: conteudo !== ""
                        wrapMode: Text.Wrap
                        text: conteudo
                        color: ehErro ? raiz.corErro : raiz.corTextoSecundario
                        font.pixelSize: raiz.tamanhoFontePequena + 1
                    }

                    // ----- Resultado -----
                    Column {
                        id: resultadoRotas

                        readonly property var c: raiz.comparacao

                        width: parent.width
                        spacing: raiz.espaco * 0.5
                        visible: c !== null

                        Rectangle {
                            width: parent.width
                            height: textoVeredito.implicitHeight + raiz.espaco
                            radius: raiz.raioBorda
                            color: resultadoRotas.c && resultadoRotas.c.aCaminho ? raiz.corSucesso : raiz.corAviso

                            Text {
                                id: textoVeredito
                                anchors.centerIn: parent
                                width: parent.width - 2 * raiz.espaco
                                wrapMode: Text.Wrap
                                horizontalAlignment: Text.AlignHCenter
                                color: "white"
                                font.pixelSize: raiz.tamanhoFonte
                                font.weight: Font.DemiBold
                                text: raiz.textoVeredito(resultadoRotas.c)
                            }
                        }

                        Repeater {
                            model: {
                                const c = resultadoRotas.c;
                                if (!c)
                                    return [];
                                const ordem = c.juntas.ordem;
                                return [
                                    ["Separadas (P→A→P e P→B→P)", raiz.formatarTempo(c.separadas.segundos) + " · " + raiz.formatarDistancia(c.separadas.metros)],
                                    ["Juntas (P→" + ordem[0] + "→" + ordem[1] + "→P)", raiz.formatarTempo(c.juntas.segundos) + " · " + raiz.formatarDistancia(c.juntas.metros)],
                                    ["Economia juntando", raiz.formatarTempo(c.economiaSegundos)],
                                    ["Atraso de " + c.desvio.segunda + " por passar antes em " + c.desvio.primeira,
                                     "+" + raiz.formatarTempo(c.desvio.segundos) + " (limite " + raiz.formatarTempo(c.desvio.limite) + ")"]
                                ];
                            }

                            delegate: Item {
                                required property var modelData

                                width: resultadoRotas.width
                                height: Math.max(rotuloResultado.implicitHeight, valorResultado.implicitHeight)

                                Text {
                                    id: rotuloResultado
                                    width: parent.width * 0.55
                                    wrapMode: Text.Wrap
                                    text: parent.modelData[0]
                                    color: raiz.corTextoSecundario
                                    font.pixelSize: raiz.tamanhoFontePequena + 1
                                }
                                Text {
                                    id: valorResultado
                                    anchors.right: parent.right
                                    width: parent.width * 0.45
                                    wrapMode: Text.Wrap
                                    horizontalAlignment: Text.AlignRight
                                    text: parent.modelData[1]
                                    color: raiz.corTexto
                                    font.pixelSize: raiz.tamanhoFontePequena + 1
                                    font.weight: Font.Medium
                                    font.features: { "tnum": 1 }
                                }
                            }
                        }

                        // Qual rota aparece no mapa.
                        Row {
                            spacing: raiz.espaco / 2

                            Repeater {
                                model: [
                                    { valor: "juntas", rotulo: "Rota juntas" },
                                    { valor: "separadas", rotulo: "Rotas separadas" }
                                ]

                                delegate: Rectangle {
                                    id: chipRota

                                    required property var modelData
                                    readonly property bool ativo: raiz.rotasVisiveis === modelData.valor

                                    width: textoChipRota.implicitWidth + 2 * raiz.espaco
                                    height: Math.round(raiz.alturaControle * 0.8)
                                    radius: height / 2
                                    color: ativo ? raiz.corTexto : "transparent"
                                    border.color: ativo ? raiz.corTexto : raiz.corBorda

                                    Text {
                                        id: textoChipRota
                                        anchors.centerIn: parent
                                        text: chipRota.modelData.rotulo
                                        color: chipRota.ativo ? raiz.corSuperficie : raiz.corTexto
                                        font.pixelSize: raiz.tamanhoFontePequena + 1
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: raiz.rotasVisiveis = chipRota.modelData.valor
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: "Tempos estimados pelo tipo de via e pelo limite de velocidade do OpenStreetMap, sem contar trânsito."
                            color: raiz.corTextoSecundario
                            font.pixelSize: raiz.tamanhoFontePequena
                        }
                    }
                }
            }
        }

        // =========================================================================
        // INFORMAÇÕES (canto inferior esquerdo): centro, zoom e atribuição
        // =========================================================================

        Rectangle {
            id: painelInfo
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: raiz.espaco
            width: colunaInfo.implicitWidth + 2 * raiz.espaco
            height: colunaInfo.implicitHeight + raiz.espaco
            radius: raiz.raioBorda
            color: Qt.alpha(raiz.corSuperficie, 0.92)
            border.color: raiz.corBorda

            Column {
                id: colunaInfo
                anchors.centerIn: parent
                spacing: 2

                Text {
                    text: "Centro  " + raiz.formatarCoordenada(mapa.centro)
                    color: raiz.corTexto
                    font.pixelSize: raiz.tamanhoFontePequena + 1
                    font.features: { "tnum": 1 } // algarismos de largura fixa: não "dança" no pan
                }
                Text {
                    text: "Zoom  " + mapa.zoom.toFixed(1)
                    color: raiz.corTexto
                    font.pixelSize: raiz.tamanhoFontePequena + 1
                    font.features: { "tnum": 1 }
                }
                Text {
                    text: raiz.atribuicao
                    color: raiz.corTextoSecundario
                    font.pixelSize: raiz.tamanhoFontePequena - 1
                }
            }
        }

        // =========================================================================
        // CONTROLES (canto inferior direito)
        // =========================================================================

        Column {
            id: controles
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: raiz.espaco
            spacing: raiz.espaco / 2

            Repeater {
                model: [
                    { acao: "aproximar", rotulo: "+", dica: "Aproximar" },
                    { acao: "afastar", rotulo: "−", dica: "Afastar" },
                    { acao: "localizacao", rotulo: "", dica: "Centralizar na minha localização" },
                    { acao: "rotas", rotulo: "A·B", dica: "Comparar rotas de duas entregas" },
                    { acao: "limpar", rotulo: "✕", dica: "Limpar marcadores" }
                ]

                delegate: Button {
                    id: botao

                    required property var modelData

                    width: raiz.alturaControle
                    height: raiz.alturaControle
                    enabled: modelData.acao !== "limpar"
                             || modeloMarcadores.count > 0 || raiz.localizacaoAtual.isValid || campoBusca.text !== ""
                             || raiz.entregaA !== null
                    opacity: enabled ? 1 : 0.5
                    focusPolicy: Qt.NoFocus // não rouba o foco do campo de busca

                    ToolTip.visible: hovered && !raiz.compacto
                    ToolTip.delay: 500
                    ToolTip.text: modelData.dica

                    onClicked: {
                        switch (modelData.acao) {
                        case "aproximar":
                            raiz.aproximar(1);
                            break;
                        case "afastar":
                            raiz.aproximar(-1);
                            break;
                        case "localizacao":
                            raiz.irParaLocalizacaoAtual();
                            break;
                        case "rotas":
                            if (raiz.modoRotas)
                                raiz.fecharRotas();
                            else
                                raiz.abrirRotas();
                            break;
                        case "limpar":
                            raiz.limparMarcadores();
                            break;
                        }
                    }

                    background: Rectangle {
                        radius: raiz.raioBorda
                        // O botão de rotas fica aceso enquanto o painel está aberto.
                        color: botao.modelData.acao === "rotas" && raiz.modoRotas ? raiz.corPrimaria
                             : botao.down ? raiz.corSuperficiePressionada
                             : botao.hovered ? raiz.corSuperficieHover : raiz.corSuperficie
                        border.color: botao.modelData.acao === "rotas" && raiz.modoRotas ? raiz.corPrimaria : raiz.corBorda
                    }

                    contentItem: Item {
                        Text {
                            anchors.centerIn: parent
                            visible: botao.modelData.rotulo !== ""
                            text: botao.modelData.rotulo
                            color: botao.modelData.acao === "limpar" ? raiz.corErro
                                 : botao.modelData.acao === "rotas" && raiz.modoRotas ? raiz.corTextoSobrePrimaria
                                 : raiz.corTexto
                            font.pixelSize: botao.modelData.acao === "limpar" ? raiz.tamanhoFonte
                                          : botao.modelData.acao === "rotas" ? raiz.tamanhoFontePequena + 1
                                          : raiz.tamanhoFonte + 8
                            font.weight: Font.DemiBold
                        }

                        // Ícone "minha localização": anel com ponto central.
                        Rectangle {
                            anchors.centerIn: parent
                            visible: botao.modelData.acao === "localizacao"
                            width: 18
                            height: 18
                            radius: 9
                            color: "transparent"
                            border.width: 2
                            border.color: raiz._aguardandoGps ? raiz.corPrimaria : raiz.corMarcadorLocalizacao

                            Rectangle {
                                anchors.centerIn: parent
                                width: 6
                                height: 6
                                radius: 3
                                color: parent.border.color
                            }
                        }
                    }
                }
            }
        }

        // Abre a barra lateral de cálculo de rotas (PainelRotas).
        Button {
            id: botaoVerificarRota

            z: 15
            visible: !raiz.modoVerificarRota
            anchors.right: parent.right
            anchors.rightMargin: raiz.espaco
            // No celular a busca ocupa a largura toda: o botão desce para baixo dela.
            anchors.top: raiz.compacto ? barraBusca.bottom : parent.top
            anchors.topMargin: raiz.espaco
            height: raiz.alturaControle + 4
            leftPadding: 16
            rightPadding: 16
            focusPolicy: Qt.NoFocus
            text: "Verificar rota"
            onClicked: raiz.modoVerificarRota = true

            background: Rectangle {
                radius: height / 2
                color: botaoVerificarRota.down ? raiz.corPrimariaPressionada : raiz.corPrimaria
            }
            contentItem: Row {
                spacing: 8

                Icone {
                    anchors.verticalCenter: parent.verticalCenter
                    nome: "fa6s.route"
                    cor: raiz.corTextoSobrePrimaria
                    tamanho: 16
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: botaoVerificarRota.text
                    color: raiz.corTextoSobrePrimaria
                    font.pixelSize: raiz.tamanhoFonte
                    font.weight: Font.DemiBold
                }
            }
        }

    }
}
