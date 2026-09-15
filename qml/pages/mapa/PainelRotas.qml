import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtPositioning
import "../../components"

// PainelRotas.qml — barra lateral "Verificar rota" da página Mapa (Maps.qml),
// no estilo do Google Maps: origem, destino e paradas, rotas de carro,
// bicicleta e a pé pelo OSRM e a lista de rotas
// alternativas. Traçados e marcadores ficam na CamadaRotas.qml, que o Maps.qml
// põe dentro do mapa; os dois conversam pelas propriedades deste painel.
//
// O que difere do pedido original, e por quê:
// - Sem QtLocation (Map, MapPolyline, MapQuickItem): o PyQt6 do pip não traz
//   esse módulo. O mapa é o components/MapaBlocos.qml (blocos do OSM em QML
//   puro), o traçado é um Shape e os marcadores são Items posicionados por ele.
// - Carro vem do router.project-osrm.org; bicicleta e a pé, dos servidores
//   OSRM da FOSSGIS (routing.openstreetmap.de), porque o primeiro só tem o
//   perfil de carro. Os dois são servidores públicos de demonstração: servem
//   para uso leve e não garantem disponibilidade.
// - O OSRM não conhece trânsito. O horário de saída não muda a rota; ele só
//   calcula o horário de chegada.
// - Alternativas só existem com dois pontos: com parada no meio, o OSRM
//   devolve uma rota só.
//
// Cada ponto é um DeliveryAddressValidator, o mesmo campo de endereço da
// Entrega: sugestões do histórico, do índice de ruas e do Photon na cidade do
// estabelecimento, número, CEP e a verificação de que o endereço existe
// (Photon → Nominatim → ViaCEP, em controllers/validacaoEnderecoController.py).
// Aqui num campo só, no estilo do Google Maps ("Rua São Vicente de Paula, 311,
// Centro, 12020-000"), sem complemento e sem zona de entrega. Um ponto só entra na rota
// verificado, ou com "Usar mesmo assim" quando o endereço tem posição no mapa
// mas não foi confirmado. A origem começa na pizzaria e já vale antes de a
// verificação terminar: a coordenada dela é conhecida.
//
// Abaixo dos pontos ficam as entregas em aberto do dia (comandas de Entrega
// sem baixa, ver FechamentoController.listarEntregasAbertas): clicar numa põe
// o endereço dela no destino, que é verificado como um endereço digitado.
//
// Os pedidos de rota saem por XMLHttpRequest, com o User-Agent que o main.py põe em
// todo pedido do QML (services/redeQml.py). No Windows, HTTPS pelo Qt já travou
// sem resposta (ver services/requisicaoHttp.py): o tempo limite abaixo garante
// que a tela não fica "calculando" para sempre.
Rectangle {
    id: raiz

    // O mapa onde as rotas são enquadradas (o MapaBlocos do Maps.qml).
    required property MapaBlocos mapa
    // Origem, paradas e destino, para a CamadaRotas desenhar os marcadores.
    property alias pontos: modeloPontos

    // O X do título: quem usa o painel decide como escondê-lo.
    signal fecharSolicitado()

    // =========================================================================
    // PERSONALIZAÇÃO
    // =========================================================================

    // ----- Cores -----
    property color corPainel: "#ffffff"
    property color corFundoCampo: "#f3f5f8"
    property color corBorda: "#dde2ea"
    property color corTexto: "#1f2933"
    property color corTextoSecundario: "#5f6b7a"
    property color corDestaque: "#0066cc"
    property color corSelecao: "#e8f0fe"
    property color corRotaSelecionada: "#0066cc"
    property color corRotaAlternativa: "#5588ff"
    property color corOrigem: "#d93025"
    property color corDestino: "#1e8e3e"
    property color corParada: "#5f6b7a"
    property color corTempoCurto: "#1e8e3e" // menos de 10 min
    property color corTempoMedio: "#b7791f" // 10 a 30 min (âmbar: amarelo puro some no branco)
    property color corTempoLongo: "#d93025" // mais de 30 min
    property color corErro: "#d93025"

    // ----- Medidas -----
    property int larguraPainel: 400
    property int espaco: 12
    property int raio: 8
    property int alturaCampo: 38
    property int fonte: 13
    property int fontePequena: 12
    property int fonteDestaque: 16
    property int espessuraRota: 6

    // ----- Serviços -----
    property var servidoresRota: ({
        "carro": "https://router.project-osrm.org/route/v1/driving/",
        "bicicleta": "https://routing.openstreetmap.de/routed-bike/route/v1/driving/",
        "pe": "https://routing.openstreetmap.de/routed-foot/route/v1/driving/"
    })
    property int tempoLimiteRotaMs: 15000
    property int maximoPontos: 6
    // Ponto mais longe que isto da rua mais próxima é erro, não rota (ver
    // pontoLongeDaRua).
    property int distanciaMaximaDaRuaM: 500

    // ----- Mapa e ponto de partida -----
    // Localização do estabelecimento definida na tela Rede, ou null. Sem ela
    // (página aberta fora do app, ou localização ainda não definida) valem as
    // coordenadas abaixo.
    readonly property var localizacaoEstabelecimento: {
        const localizacao = typeof redeController !== "undefined" ? redeController.localizacaoServidor : null;
        return localizacao && localizacao.lat !== undefined ? localizacao : null;
    }
    property var coordenadaInicial: localizacaoEstabelecimento
                                    ? QtPositioning.coordinate(localizacaoEstabelecimento.lat, localizacaoEstabelecimento.lon)
                                    : QtPositioning.coordinate(-23.0016226, -45.5642446)
    property string nomeOrigemPadrao: localizacaoEstabelecimento && localizacaoEstabelecimento.descricao
                                      ? "Pizzaria — " + localizacaoEstabelecimento.descricao
                                      : "Pizzaria — Av. dos Bombeiros, 375"

    // =========================================================================
    // ESTADO
    // =========================================================================

    readonly property var modos: [
        { id: "carro", rotulo: "Carro", icone: "fa6s.car" },
        { id: "bicicleta", rotulo: "Bicicleta", icone: "fa6s.bicycle" },
        { id: "pe", rotulo: "A pé", icone: "fa6s.person-walking" }
    ]
    property string modoTransporte: "carro"

    // Por modo: lista de rotas lidas do OSRM, mensagem de erro, carregando.
    // Sempre reatribuídos por inteiro (ver atualizarPorModo): mudar uma chave
    // dentro do objeto não avisaria os bindings.
    property var rotasPorModo: ({ "carro": [], "bicicleta": [], "pe": [] })
    property var errosPorModo: ({})
    property var carregandoPorModo: ({})
    property int rotaSelecionada: 0

    readonly property var rotasAtuais: rotasPorModo[modoTransporte] || []
    readonly property string erroAtual: errosPorModo[modoTransporte] || ""
    readonly property bool calculandoAtual: carregandoPorModo[modoTransporte] === true

    // ListModel não avisa bindings que leem por get(): quem muda os pontos
    // incrementa isto (ver pontosMudaram).
    property int versaoPontos: 0

    // Comandas de Entrega de hoje ainda sem baixa, para usar como destino.
    property var entregasAbertas: []
    property bool entregasExpandidas: true
    // Arquivo da comanda cujo endereço está no destino ("" quando o destino
    // foi digitado): destaca o cartão dela na lista.
    property string entregaNoDestino: ""
    property int alturaMaximaEntregas: 220

    property bool sairAgora: true
    property string horarioSaida: ""
    property real agoraMs: Date.now()

    // Traçados em pixels de um zoom fixo (ver montarTracado).
    readonly property real escalaTracado: 256 * Math.pow(2, 14)

    property int _geracaoRotas: 0
    property var _pedidosRota: []
    property var _pendentes: []

    // Tom dos campos de endereço (DeliveryAddressValidator): o azul do painel.
    readonly property QtObject tomCampos: QtObject {
        property color accent: raiz.corDestaque
        property color base: raiz.corDestaque
        property color hover: Qt.darker(raiz.corDestaque, 1.1)
        property color pressed: Qt.darker(raiz.corDestaque, 1.25)
    }

    color: corPainel

    // =========================================================================
    // FUNÇÕES — pedidos HTTP
    // =========================================================================

    // GET com JSON e tempo limite. `aoTerminar(dados, erro, status)`: erro é ""
    // ou "sem-conexao", "http", "json", "tempo", "falha"; nos erros HTTP os
    // dados ainda vêm, quando a resposta era JSON (o OSRM explica o erro
    // nela). Devolve o pedido, para cancelarPedido.
    function pedirJson(url, tempoLimiteMs, aoTerminar) {
        const xhr = new XMLHttpRequest();
        const pedido = { xhr: xhr, prazo: Date.now() + tempoLimiteMs, encerrado: false, aoTerminar: aoTerminar };
        _pendentes.push(pedido);
        relogioPedidos.start();

        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE || pedido.encerrado)
                return;
            pedido.encerrado = true;
            raiz.removerPendente(pedido);
            if (xhr.status === 0) {
                aoTerminar(null, "sem-conexao", 0);
                return;
            }
            let dados = null;
            try {
                dados = JSON.parse(xhr.responseText);
            } catch (erro) {
                dados = null;
            }
            if (xhr.status < 200 || xhr.status >= 300)
                aoTerminar(dados, "http", xhr.status);
            else if (dados === null)
                aoTerminar(null, "json", xhr.status);
            else
                aoTerminar(dados, "", xhr.status);
        };

        try {
            xhr.open("GET", url);
            xhr.setRequestHeader("Accept", "application/json");
            xhr.send();
        } catch (erro) {
            pedido.encerrado = true;
            removerPendente(pedido);
            aoTerminar(null, "falha", 0);
        }
        return pedido;
    }

    // Cancela sem chamar aoTerminar: quem cancela já não quer a resposta.
    function cancelarPedido(pedido) {
        if (!pedido || pedido.encerrado)
            return;
        pedido.encerrado = true;
        removerPendente(pedido);
        pedido.xhr.abort();
    }

    function removerPendente(pedido) {
        const posicao = _pendentes.indexOf(pedido);
        if (posicao >= 0)
            _pendentes.splice(posicao, 1);
    }

    // =========================================================================
    // FUNÇÕES — pontos (origem, paradas, destino)
    // =========================================================================

    function pontosMudaram() {
        ++versaoPontos;
    }

    function pontoDefinido(indice) {
        return indice >= 0 && indice < modeloPontos.count && modeloPontos.get(indice).definido;
    }

    function todosDefinidos() {
        if (modeloPontos.count < 2)
            return false;
        for (let i = 0; i < modeloPontos.count; ++i) {
            if (!modeloPontos.get(i).definido)
                return false;
        }
        return true;
    }

    // Com o artigo: "a origem", "o destino", "a parada 2".
    function rotuloDoPonto(indice) {
        if (indice === 0)
            return "a origem";
        if (indice === modeloPontos.count - 1)
            return "o destino";
        return "a parada " + indice;
    }

    // O campo de endereço de um ponto mudou de estado (ver pontoValido no
    // delegate): entra na rota com a posição verificada, ou sai dela.
    function atualizarPonto(indice, definido, latitude, longitude, texto) {
        if (indice < 0 || indice >= modeloPontos.count)
            return;
        const antes = modeloPontos.get(indice);
        if (!definido && !antes.definido)
            return;
        if (definido && antes.definido && antes.latitude === latitude && antes.longitude === longitude)
            return;
        modeloPontos.set(indice, {
            texto: texto,
            latitude: definido ? latitude : antes.latitude,
            longitude: definido ? longitude : antes.longitude,
            definido: definido,
            padrao: antes.padrao
        });
        pontosMudaram();
        limparRotas();
        if (todosDefinidos())
            timerCalculo.restart();
        else if (definido)
            mapa.centralizar(latitude, longitude, Math.max(mapa.zoom, 15));
    }

    // =========================================================================
    // FUNÇÕES — entregas em aberto
    // =========================================================================

    function hojeIso() {
        return Qt.formatDate(new Date(), "yyyy-MM-dd");
    }

    // Relida ao abrir o painel, quando uma comanda chega ou muda e quando
    // alguém dá baixa (ver as Connections junto do Component.onCompleted).
    function recarregarEntregas() {
        if (typeof fechamentoController === "undefined") {
            entregasAbertas = [];
            return;
        }
        entregasAbertas = fechamentoController.listarEntregasAbertas(hojeIso());
    }

    // "15/09/2026 19:02:11" → "19:02".
    function horaDaComanda(dataHora) {
        const hora = /(\d{2}:\d{2})/.exec(dataHora || "");
        return hora ? hora[1] : "";
    }

    // O endereço da comanda vai para o campo do destino, por cima do que
    // estiver lá, e a verificação roda como num endereço digitado.
    function usarEntregaComoDestino(entrega) {
        const indice = modeloPontos.count - 1;
        const linha = repetidorPontos.itemAt(indice);
        if (!linha || !entrega)
            return;
        // O destino pode ser a pizzaria depois de inverter: deixa de ser.
        marcarEditado(indice);
        linha.validador.preencher({
            endereco: entrega.rua,
            numero: entrega.numero,
            bairro: entrega.bairro
        });
        entregaNoDestino = entrega.arquivo;
    }

    // Alguém digitou no campo da origem: ela deixa de ser a pizzaria.
    function marcarEditado(indice) {
        if (indice >= 0 && indice < modeloPontos.count && modeloPontos.get(indice).padrao)
            modeloPontos.setProperty(indice, "padrao", false);
    }

    // A origem começa na pizzaria: o endereço digitado na tela Rede, com a
    // coordenada dela. A verificação roda em segundo plano, e a origem já vale
    // enquanto isso (ver pontoValido no delegate).
    function preencherPontoPadrao(validador) {
        const localizacao = localizacaoEstabelecimento;
        const texto = localizacao ? (localizacao.endereco || localizacao.descricao || "") : "Avenida dos Bombeiros, 375";
        const info = texto ? validacaoEnderecoController.interpretar(texto) : {};
        validador.preencher({
            endereco: info.rua || texto,
            numero: info.numero || "",
            bairro: info.bairro || "",
            latitude: coordenadaInicial.latitude,
            longitude: coordenadaInicial.longitude
        });
    }

    // X do campo: origem e destino (com só dois pontos) são limpos; paradas e
    // pontos a mais são removidos.
    function limparOuRemover(indice) {
        if (indice === modeloPontos.count - 1)
            entregaNoDestino = "";
        if (modeloPontos.count > 2 && indice > 0)
            modeloPontos.remove(indice);
        else
            modeloPontos.set(indice, { texto: "", latitude: 0.0, longitude: 0.0, definido: false, padrao: false });
        pontosMudaram();
        limparRotas();
        if (todosDefinidos())
            timerCalculo.restart();
    }

    // Novo destino no fim: o destino de antes vira parada.
    function adicionarDestino() {
        if (modeloPontos.count >= maximoPontos)
            return;
        // O destino de antes vira parada: a comanda dele deixa de ser o destino.
        entregaNoDestino = "";
        modeloPontos.append({ texto: "", latitude: 0.0, longitude: 0.0, definido: false, padrao: false });
        pontosMudaram();
        limparRotas();
        Qt.callLater(function () {
            const linha = repetidorPontos.itemAt(modeloPontos.count - 1);
            if (linha)
                linha.focar();
        });
    }

    // Botão das setas: inverte a ordem (origem vira destino).
    function inverterPontos() {
        const quantidade = modeloPontos.count;
        if (quantidade < 2)
            return;
        entregaNoDestino = "";
        // move() em vez de recriar: os campos continuam os mesmos, sem perder
        // o que está digitado.
        for (let i = 0; i < quantidade - 1; ++i)
            modeloPontos.move(quantidade - 1, i, 1);
        pontosMudaram();
        limparRotas();
        if (todosDefinidos())
            timerCalculo.restart();
    }

    function enquadrarPontos() {
        let minX = 1, minY = 1, maxX = 0, maxY = 0;
        for (let i = 0; i < modeloPontos.count; ++i) {
            const ponto = modeloPontos.get(i);
            if (!ponto.definido)
                continue;
            const p = mapa.paraMundo(ponto.latitude, ponto.longitude);
            minX = Math.min(minX, p.x);
            minY = Math.min(minY, p.y);
            maxX = Math.max(maxX, p.x);
            maxY = Math.max(maxY, p.y);
        }
        mapa.enquadrar(minX, minY, maxX, maxY, 70);
    }

    // =========================================================================
    // FUNÇÕES — rotas (OSRM)
    // =========================================================================

    function atualizarPorModo(nomePropriedade, modo, valor) {
        const copia = Object.assign({}, raiz[nomePropriedade]);
        copia[modo] = valor;
        raiz[nomePropriedade] = copia;
    }

    function limparRotas() {
        ++_geracaoRotas;
        timerCalculo.stop();
        for (let i = 0; i < _pedidosRota.length; ++i)
            cancelarPedido(_pedidosRota[i]);
        _pedidosRota = [];
        rotasPorModo = ({ "carro": [], "bicicleta": [], "pe": [] });
        errosPorModo = ({});
        carregandoPorModo = ({});
        rotaSelecionada = 0;
    }

    function mensagemRota(dados, erro, status) {
        const codigo = dados && dados.code;
        if (erro === "tempo")
            return "O serviço de rotas demorou demais. Tente de novo.";
        if (erro === "sem-conexao")
            return "Sem conexão com o serviço de rotas.";
        if (codigo === "NoRoute")
            return "Não há rota entre esses pontos neste modo de transporte.";
        if (codigo === "NoSegment")
            return "Um dos pontos está longe demais de qualquer rua.";
        if (codigo === "TooBig")
            return "Pontos demais para o serviço de rotas.";
        if (status === 429)
            return "Muitas consultas seguidas. Aguarde um instante.";
        if (erro === "json")
            return "Resposta inválida do serviço de rotas.";
        return "O serviço de rotas falhou" + (status ? " (erro " + status + ")" : "") + ".";
    }

    // Calcula os três modos de uma vez: os botões de modo mostram o melhor
    // tempo de cada um, como no Google Maps.
    function calcularRotas() {
        limparRotas();
        if (!todosDefinidos())
            return;

        const geracao = _geracaoRotas;
        const coordenadas = [];
        for (let i = 0; i < modeloPontos.count; ++i) {
            const ponto = modeloPontos.get(i);
            coordenadas.push(ponto.longitude.toFixed(6) + "," + ponto.latitude.toFixed(6));
        }
        // Com parada no meio o OSRM não calcula alternativas.
        const alternativas = modeloPontos.count === 2 ? "3" : "false";
        const pedidos = [];
        let carregando = {};

        for (let m = 0; m < modos.length; ++m) {
            const modo = modos[m].id;
            carregando[modo] = true;
            const url = servidoresRota[modo] + coordenadas.join(";")
                + "?alternatives=" + alternativas + "&overview=full&geometries=geojson&steps=false";

            pedidos.push(pedirJson(url, tempoLimiteRotaMs, function (dados, erro, status) {
                if (geracao !== raiz._geracaoRotas)
                    return; // os pontos mudaram enquanto isto chegava
                raiz.atualizarPorModo("carregandoPorModo", modo, false);
                if (erro || !dados || dados.code !== "Ok") {
                    raiz.atualizarPorModo("errosPorModo", modo, raiz.mensagemRota(dados, erro, status));
                    return;
                }
                const longe = raiz.pontoLongeDaRua(dados.waypoints);
                if (longe >= 0) {
                    raiz.atualizarPorModo("errosPorModo", modo, raiz.mensagemPontoLonge(longe, dados.waypoints[longe].distance));
                    return;
                }
                raiz.atualizarPorModo("rotasPorModo", modo, raiz.lerRotas(dados, modo));
                if (modo === raiz.modoTransporte) {
                    raiz.rotaSelecionada = 0;
                    raiz.enquadrarRota();
                }
            }));
        }
        _pedidosRota = pedidos;
        carregandoPorModo = carregando;
    }

    // Rotas do OSRM no formato da lista, com "mais rápida" e "mais curta"
    // calculadas entre as rotas do mesmo modo.
    function lerRotas(dados, modo) {
        const rotas = [];
        const brutas = Array.isArray(dados.routes) ? dados.routes : [];
        for (let i = 0; i < brutas.length; ++i) {
            const bruta = brutas[i];
            const coordenadas = bruta.geometry && Array.isArray(bruta.geometry.coordinates) ? bruta.geometry.coordinates : [];
            const nomesVia = (bruta.legs || []).map(function (trecho) { return trecho.summary; }).filter(Boolean);
            rotas.push({
                modo: modo,
                distancia: Number(bruta.distance) || 0,
                duracao: Number(bruta.duration) || 0,
                via: nomesVia.join(" → "),
                tracado: montarTracado(coordenadas),
                maisRapida: false,
                maisCurta: false
            });
        }
        if (rotas.length > 1) {
            let rapida = 0, curta = 0;
            for (let i = 1; i < rotas.length; ++i) {
                if (rotas[i].duracao < rotas[rapida].duracao)
                    rapida = i;
                if (rotas[i].distancia < rotas[curta].distancia)
                    curta = i;
            }
            rotas[rapida].maisRapida = true;
            rotas[curta].maisCurta = true;
        }
        return rotas;
    }

    // Coordenadas [[lon, lat], ...] em pontos para o Shape: cada ponto é o
    // deslocamento até o primeiro, em pixels do zoom fixo escalaTracado. No pan
    // e no zoom a camada só é movida e escalada, sem recalcular pontos.
    function montarTracado(coordenadas) {
        if (!coordenadas || coordenadas.length < 2)
            return null;
        const origem = mapa.paraMundo(coordenadas[0][1], coordenadas[0][0]);
        const pontos = [];
        let minX = origem.x, minY = origem.y, maxX = origem.x, maxY = origem.y;
        for (let i = 0; i < coordenadas.length; ++i) {
            const p = mapa.paraMundo(coordenadas[i][1], coordenadas[i][0]);
            pontos.push(Qt.point((p.x - origem.x) * escalaTracado, (p.y - origem.y) * escalaTracado));
            minX = Math.min(minX, p.x);
            minY = Math.min(minY, p.y);
            maxX = Math.max(maxX, p.x);
            maxY = Math.max(maxY, p.y);
        }
        return { x: origem.x, y: origem.y, pontos: pontos, minX: minX, minY: minY, maxX: maxX, maxY: maxY };
    }

    // O OSRM encaixa cada ponto na rua mais próxima, por mais longe que ela
    // esteja: um ponto no mar virava uma rota de horas até a costa. Devolve o
    // índice do primeiro ponto longe demais (waypoints vêm na ordem dos
    // pontos), ou -1.
    function pontoLongeDaRua(waypoints) {
        if (!Array.isArray(waypoints))
            return -1;
        for (let i = 0; i < waypoints.length; ++i) {
            if (Number(waypoints[i].distance) > distanciaMaximaDaRuaM)
                return i;
        }
        return -1;
    }

    function mensagemPontoLonge(indice, metros) {
        const rotulo = rotuloDoPonto(indice);
        const distancia = metros >= 1000 ? formatarDistancia(metros) : Math.round(metros) + " m";
        return rotulo.charAt(0).toUpperCase() + rotulo.slice(1) + " fica a " + distancia
            + " da rua mais próxima. Escolha um endereço perto de uma rua.";
    }

    function selecionarRota(indice) {
        rotaSelecionada = indice;
        enquadrarRota();
    }

    function selecionarModo(modo) {
        modoTransporte = modo;
        rotaSelecionada = 0;
        enquadrarRota();
    }

    function enquadrarRota() {
        const rota = rotasAtuais[rotaSelecionada];
        if (rota && rota.tracado)
            mapa.enquadrar(rota.tracado.minX, rota.tracado.minY, rota.tracado.maxX, rota.tracado.maxY, 60);
    }

    // =========================================================================
    // FUNÇÕES — formatação
    // =========================================================================

    function formatarDuracao(segundos) {
        const minutos = Math.max(1, Math.round(segundos / 60));
        if (minutos < 60)
            return minutos + " min";
        const resto = minutos % 60;
        return Math.floor(minutos / 60) + " h" + (resto ? " " + resto + " min" : "");
    }

    function formatarDistancia(metros) {
        return (metros / 1000).toFixed(1).replace(".", ",") + " km";
    }

    function corDoTempo(segundos) {
        if (segundos < 10 * 60)
            return corTempoCurto;
        if (segundos <= 30 * 60)
            return corTempoMedio;
        return corTempoLongo;
    }

    function instanteSaida() {
        if (sairAgora)
            return agoraMs;
        const partes = /^(\d{1,2}):(\d{2})$/.exec(horarioSaida);
        if (!partes)
            return agoraMs;
        const saida = new Date(agoraMs);
        saida.setHours(Number(partes[1]), Number(partes[2]), 0, 0);
        // Horário que já passou hoje é o de amanhã.
        if (saida.getTime() < agoraMs - 60000)
            saida.setDate(saida.getDate() + 1);
        return saida.getTime();
    }

    function horarioChegada(segundos) {
        return Qt.formatTime(new Date(instanteSaida() + segundos * 1000), "HH:mm");
    }

    function melhorTempoDoModo(modo) {
        if (carregandoPorModo[modo] === true)
            return "…";
        const rotas = rotasPorModo[modo] || [];
        if (rotas.length === 0)
            return errosPorModo[modo] ? "—" : "";
        let menor = rotas[0].duracao;
        for (let i = 1; i < rotas.length; ++i)
            menor = Math.min(menor, rotas[i].duracao);
        return formatarDuracao(menor);
    }

    // =========================================================================
    // MODELOS E TIMERS
    // =========================================================================

    // Cada linha: texto, latitude, longitude, definido (entra na rota) e padrao
    // (a origem na pizzaria, até alguém digitar nela). Índice 0 é a origem, o
    // último é o destino, os do meio são paradas. Todas as linhas levam todos
    // os campos: o ListModel fixa os papéis na primeira.
    ListModel { id: modeloPontos }

    // Agrupa mudanças seguidas (inverter logo depois de escolher) num cálculo só.
    Timer {
        id: timerCalculo
        interval: 150
        onTriggered: raiz.calcularRotas()
    }

    // Um relógio só para todos os pedidos: aborta os que passaram do prazo.
    Timer {
        id: relogioPedidos
        interval: 500
        repeat: true
        onTriggered: {
            const agora = Date.now();
            const pendentes = raiz._pendentes.slice();
            for (let i = 0; i < pendentes.length; ++i) {
                const pedido = pendentes[i];
                if (pedido.encerrado || agora <= pedido.prazo)
                    continue;
                pedido.encerrado = true;
                raiz.removerPendente(pedido);
                pedido.xhr.abort();
                pedido.aoTerminar(null, "tempo", 0);
            }
            if (raiz._pendentes.length === 0)
                stop();
        }
    }

    // O horário de chegada de "Sair agora" anda com o relógio.
    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: raiz.agoraMs = Date.now()
    }

    Component.onCompleted: {
        modeloPontos.append({
            texto: nomeOrigemPadrao,
            latitude: coordenadaInicial.latitude,
            longitude: coordenadaInicial.longitude,
            definido: true,
            padrao: true
        });
        modeloPontos.append({ texto: "", latitude: 0.0, longitude: 0.0, definido: false, padrao: false });
        pontosMudaram();
        recarregarEntregas();
    }

    // O Maps.qml cria o painel escondido: a lista é relida quando ele aparece.
    onVisibleChanged: {
        if (visible)
            recarregarEntregas();
    }

    // Comanda nova, editada ou apagada (aqui ou recebida de outra máquina).
    Connections {
        target: typeof consultaController !== "undefined" ? consultaController : null
        ignoreUnknownSignals: true

        function onComandasAtualizadas() {
            raiz.recarregarEntregas();
        }
    }

    // Baixa dada: a entrega sai da lista de abertas.
    Connections {
        target: typeof fechamentoController !== "undefined" ? fechamentoController : null
        ignoreUnknownSignals: true

        function onBaixasAtualizadas() {
            raiz.recarregarEntregas();
        }
    }

    // =========================================================================
    // LAYOUT
    // =========================================================================

    // Linha divisória com o mapa.
    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: raiz.corBorda
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: raiz.espaco
        spacing: raiz.espaco

        // ----- Título e fechar -----
        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: "Verificar rota"
                color: raiz.corTexto
                font.pixelSize: raiz.fonteDestaque + 4
                font.weight: Font.DemiBold
            }

            Rectangle {
                implicitWidth: 32
                implicitHeight: 32
                radius: 16
                color: areaFecharPainel.containsMouse ? raiz.corFundoCampo : "transparent"

                Icone {
                    anchors.centerIn: parent
                    nome: "fa6s.xmark"
                    cor: raiz.corTextoSecundario
                    tamanho: 16
                }

                MouseArea {
                    id: areaFecharPainel
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: raiz.fecharSolicitado()
                }

                ToolTip.visible: areaFecharPainel.containsMouse
                ToolTip.delay: 500
                ToolTip.text: "Fechar"
            }
        }

        // ----- Modos de transporte, com o melhor tempo de cada -----
        RowLayout {
            Layout.fillWidth: true
            spacing: raiz.espaco / 2

            Repeater {
                model: raiz.modos

                delegate: Rectangle {
                    id: botaoModo

                    required property var modelData
                    readonly property bool ativo: raiz.modoTransporte === modelData.id
                    readonly property string tempo: raiz.melhorTempoDoModo(modelData.id)

                    Layout.fillWidth: true
                    implicitHeight: raiz.alturaCampo + 6
                    radius: height / 2
                    color: ativo ? raiz.corSelecao : "transparent"
                    border.color: ativo ? raiz.corDestaque : raiz.corBorda

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        Icone {
                            anchors.verticalCenter: parent.verticalCenter
                            nome: botaoModo.modelData.icone
                            cor: botaoModo.ativo ? raiz.corDestaque : raiz.corTextoSecundario
                            tamanho: 16
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: botaoModo.tempo !== "" ? botaoModo.tempo : botaoModo.modelData.rotulo
                            color: botaoModo.ativo ? raiz.corDestaque : raiz.corTexto
                            font.pixelSize: raiz.fonte
                            font.weight: botaoModo.ativo ? Font.DemiBold : Font.Normal
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: raiz.selecionarModo(botaoModo.modelData.id)
                    }

                    ToolTip.visible: areaDica.containsMouse
                    ToolTip.delay: 500
                    ToolTip.text: modelData.rotulo

                    MouseArea {
                        id: areaDica
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }
            }
        }

        // ----- Origem, paradas e destino + botão de inverter -----
        RowLayout {
            Layout.fillWidth: true
            spacing: raiz.espaco / 2

            // Os pontos rolam quando passam de meia tela: com seis, os campos
            // empurrariam a lista de rotas para fora do painel.
            Flickable {
                id: rolagemPontos

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(colunaPontos.implicitHeight, Math.max(raiz.alturaCampo * 4, raiz.height * 0.5))
                contentWidth: width
                contentHeight: colunaPontos.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                    id: colunaPontos

                    width: rolagemPontos.width
                    spacing: raiz.espaco

                    Repeater {
                        id: repetidorPontos
                        model: modeloPontos

                        delegate: Item {
                            id: linhaPonto

                            required property int index
                            required property bool padrao

                            readonly property bool ehOrigem: index === 0
                            readonly property bool ehDestino: index === modeloPontos.count - 1
                            property alias validador: validadorPonto

                            // Entra na rota: com posição no mapa e verificado,
                            // com "Usar mesmo assim", ou a pizzaria antes de
                            // alguém mexer nela.
                            readonly property bool pontoValido: validadorPonto.latitude !== null && validadorPonto.longitude !== null
                                                                && (padrao || validadorPonto.verificado || validadorPonto.usarMesmoAssim)
                            readonly property string chavePonto: pontoValido ? validadorPonto.latitude.toFixed(6) + "," + validadorPonto.longitude.toFixed(6) : ""

                            // A linha curta embaixo do campo: onde fica o
                            // endereço verificado, ou o que falta.
                            readonly property string textoStatus: {
                                const v = validadorPonto;
                                if (v.status === "")
                                    return "";
                                if (v.status === "validando")
                                    return "Verificando o endereço…";
                                const pendencias = [];
                                const informacoes = [];
                                for (let i = 0; i < v.mensagens.length; ++i)
                                    (v.mensagens[i].nivel === "info" ? informacoes : pendencias).push(v.mensagens[i].texto);
                                // Bairro e CEP já estão no próprio campo.
                                const cidadeUf = [v.cidade, v.uf].filter(Boolean).join(" - ");
                                if (v.verificado)
                                    return ["Endereço verificado" + (cidadeUf ? " · " + cidadeUf : "")].concat(informacoes).join("\n");
                                if (padrao)
                                    return "Saída da pizzaria";
                                if (v.usarMesmoAssim)
                                    return "Usado sem verificação" + (pendencias.length ? ": " + pendencias[0] : ".");
                                return pendencias.length ? pendencias[0] : "Endereço não verificado.";
                            }
                            readonly property bool statusNeutro: padrao && !validadorPonto.verificado && validadorPonto.status !== "validando"

                            function focar() {
                                validadorPonto.focar();
                            }

                            onChavePontoChanged: raiz.atualizarPonto(index, pontoValido, validadorPonto.latitude, validadorPonto.longitude, validadorPonto.resumoEndereco)

                            Component.onCompleted: {
                                if (padrao)
                                    raiz.preencherPontoPadrao(validadorPonto);
                            }

                            width: colunaPontos.width
                            height: validadorPonto.height + (linhaStatus.visible ? linhaStatus.height + 4 : 0)

                            // Selo: vermelho na origem, verde no destino,
                            // cinza com número nas paradas.
                            Rectangle {
                                id: seloPonto
                                anchors.left: parent.left
                                y: Math.round((validadorPonto.primeiroCampo.height - height) / 2)
                                width: 14
                                height: 14
                                radius: 7
                                color: linhaPonto.ehOrigem ? raiz.corOrigem
                                     : linhaPonto.ehDestino ? raiz.corDestino : raiz.corParada

                                Text {
                                    anchors.centerIn: parent
                                    visible: !linhaPonto.ehOrigem && !linhaPonto.ehDestino
                                    text: linhaPonto.index
                                    color: "white"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                }
                            }

                            DeliveryAddressValidator {
                                id: validadorPonto

                                anchors.left: seloPonto.right
                                anchors.leftMargin: raiz.espaco / 2
                                anchors.right: botaoLimparPonto.left
                                anchors.rightMargin: 4
                                rotulo: ""
                                placeholder: linhaPonto.ehOrigem ? "Escolha a origem"
                                           : linhaPonto.ehDestino ? "Escolha o destino"
                                           : "Adicione uma parada"
                                mostrarComplemento: false
                                verificarZona: false
                                campoUnico: true
                                tom: raiz.tomCampos
                                onEnderecoEditado: {
                                    raiz.marcarEditado(linhaPonto.index);
                                    if (linhaPonto.ehDestino)
                                        raiz.entregaNoDestino = "";
                                }
                            }

                            Row {
                                id: linhaStatus

                                anchors.top: validadorPonto.bottom
                                anchors.topMargin: 4
                                anchors.left: validadorPonto.left
                                anchors.right: validadorPonto.right
                                spacing: 6
                                visible: linhaPonto.textoStatus !== ""

                                Icone {
                                    id: iconeStatusPonto
                                    nome: linhaPonto.statusNeutro ? "fa6s.location-dot" : validadorPonto.iconeStatus
                                    cor: textoStatusPonto.color
                                    tamanho: raiz.fontePequena
                                }

                                Text {
                                    id: textoStatusPonto
                                    width: linhaStatus.width - iconeStatusPonto.width - linhaStatus.spacing
                                           - (linkUsarMesmoAssim.visible ? linkUsarMesmoAssim.implicitWidth + linhaStatus.spacing : 0)
                                    text: linhaPonto.textoStatus
                                    wrapMode: Text.Wrap
                                    color: linhaPonto.statusNeutro ? raiz.corTextoSecundario : validadorPonto.tomStatus.content
                                    font.pixelSize: raiz.fontePequena
                                }

                                // Endereço com posição no mapa mas não
                                // confirmado (rua nova, serviço fora do ar):
                                // o atendente decide seguir com ele.
                                Text {
                                    id: linkUsarMesmoAssim
                                    visible: !validadorPonto.verificado && !validadorPonto.usarMesmoAssim && !linhaPonto.padrao
                                             && validadorPonto.status !== "" && validadorPonto.status !== "validando"
                                             && validadorPonto.latitude !== null
                                    text: "Usar mesmo assim"
                                    color: raiz.corDestaque
                                    font.pixelSize: raiz.fontePequena
                                    font.underline: true

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: validadorPonto.usarAssimMesmo()
                                    }
                                }
                            }

                            // X: limpa (origem/destino) ou remove (parada).
                            Rectangle {
                                id: botaoLimparPonto

                                anchors.right: parent.right
                                y: Math.round((validadorPonto.primeiroCampo.height - height) / 2)
                                width: 26
                                height: 26
                                radius: 13
                                visible: validadorPonto.textoEndereco.length > 0 || modeloPontos.count > 2
                                color: areaLimparPonto.containsMouse ? raiz.corBorda : "transparent"

                                Icone {
                                    anchors.centerIn: parent
                                    nome: "fa6s.xmark"
                                    cor: raiz.corTextoSecundario
                                    tamanho: 13
                                }

                                MouseArea {
                                    id: areaLimparPonto
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        // Removida, a linha some com o campo; limpa, o campo esvazia.
                                        if (!(modeloPontos.count > 2 && linhaPonto.index > 0))
                                            validadorPonto.limpar();
                                        raiz.limparOuRemover(linhaPonto.index);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Setas: troca origem e destino.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 36
                implicitHeight: 36
                radius: 18
                color: areaInverter.containsMouse ? raiz.corFundoCampo : "transparent"
                opacity: modeloPontos.count >= 2 ? 1 : 0.4

                Icone {
                    anchors.centerIn: parent
                    nome: "fa6s.arrows-up-down"
                    cor: raiz.corTextoSecundario
                    tamanho: 16
                }

                MouseArea {
                    id: areaInverter
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: raiz.inverterPontos()
                }

                ToolTip.visible: areaInverter.containsMouse
                ToolTip.delay: 500
                ToolTip.text: "Inverter origem e destino"
            }
        }

        // ----- Adicionar destino -----
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: raiz.alturaCampo
            radius: raiz.raio
            visible: modeloPontos.count < raiz.maximoPontos
            color: areaAdicionar.containsMouse ? raiz.corFundoCampo : "transparent"

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: raiz.espaco / 2

                Icone {
                    anchors.verticalCenter: parent.verticalCenter
                    nome: "fa6s.plus"
                    cor: raiz.corDestaque
                    tamanho: 14
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Adicionar destino"
                    color: raiz.corDestaque
                    font.pixelSize: raiz.fonte
                    font.weight: Font.Medium
                }
            }

            MouseArea {
                id: areaAdicionar
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: raiz.adicionarDestino()
            }
        }

        // ----- Entregas em aberto hoje -----
        ColumnLayout {
            Layout.fillWidth: true
            spacing: raiz.espaco / 2

            // Cabeçalho: abre e fecha a lista.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: raiz.alturaCampo - 6
                radius: raiz.raio
                color: areaCabecalhoEntregas.containsMouse ? raiz.corFundoCampo : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 2
                    anchors.rightMargin: 6
                    spacing: raiz.espaco / 2

                    Icone {
                        Layout.preferredWidth: tamanho
                        Layout.preferredHeight: tamanho
                        nome: "fa6s.motorcycle"
                        cor: raiz.corDestaque
                        tamanho: 14
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Entregas em aberto hoje (" + raiz.entregasAbertas.length + ")"
                        color: raiz.corTexto
                        font.pixelSize: raiz.fonte
                        font.weight: Font.Medium
                    }
                    Icone {
                        Layout.preferredWidth: tamanho
                        Layout.preferredHeight: tamanho
                        nome: raiz.entregasExpandidas ? "fa6s.chevron-up" : "fa6s.chevron-down"
                        cor: raiz.corTextoSecundario
                        tamanho: 12
                    }
                }

                MouseArea {
                    id: areaCabecalhoEntregas
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: raiz.entregasExpandidas = !raiz.entregasExpandidas
                }
            }

            Text {
                Layout.fillWidth: true
                visible: raiz.entregasExpandidas && raiz.entregasAbertas.length === 0
                text: "Nenhuma entrega em aberto hoje."
                color: raiz.corTextoSecundario
                font.pixelSize: raiz.fontePequena
            }

            ListView {
                id: listaEntregas

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, raiz.alturaMaximaEntregas)
                visible: raiz.entregasExpandidas && count > 0
                clip: true
                spacing: 4
                model: raiz.entregasAbertas
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    id: cartaoEntrega

                    required property var modelData
                    readonly property bool noDestino: raiz.entregaNoDestino !== "" && raiz.entregaNoDestino === modelData.arquivo

                    width: ListView.view.width
                    height: colunaEntrega.implicitHeight + 12
                    radius: raiz.raio
                    color: noDestino ? raiz.corSelecao : areaEntrega.containsMouse ? raiz.corFundoCampo : raiz.corPainel
                    border.color: noDestino ? raiz.corDestaque : raiz.corBorda
                    border.width: noDestino ? 2 : 1

                    ColumnLayout {
                        id: colunaEntrega

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                visible: text !== ""
                                text: cartaoEntrega.modelData.codigo || ""
                                color: raiz.corDestaque
                                font.pixelSize: raiz.fontePequena
                                font.weight: Font.DemiBold
                            }
                            Text {
                                Layout.fillWidth: true
                                text: cartaoEntrega.modelData.cliente || "Cliente sem nome"
                                elide: Text.ElideRight
                                color: raiz.corTexto
                                font.pixelSize: raiz.fonte
                                font.weight: Font.Medium
                            }
                            Text {
                                text: raiz.horaDaComanda(cartaoEntrega.modelData.dataHora)
                                color: raiz.corTextoSecundario
                                font.pixelSize: raiz.fontePequena
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: cartaoEntrega.modelData.enderecoTexto
                            elide: Text.ElideRight
                            color: raiz.corTextoSecundario
                            font.pixelSize: raiz.fontePequena
                        }
                    }

                    MouseArea {
                        id: areaEntrega
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: raiz.usarEntregaComoDestino(cartaoEntrega.modelData)
                    }

                    ToolTip.visible: areaEntrega.containsMouse
                    ToolTip.delay: 600
                    ToolTip.text: "Usar como destino"
                }
            }
        }

        // ----- Horário de saída -----
        RowLayout {
            Layout.fillWidth: true
            spacing: raiz.espaco / 2

            Icone {
                // Dentro de Layout, width/height do Icone não valem: sem
                // isto o ícone sai no tamanho da imagem supersampleada.
                Layout.preferredWidth: tamanho
                Layout.preferredHeight: tamanho
                nome: "fa6s.clock"
                cor: raiz.corTextoSecundario
                tamanho: 14
            }

            ComboBox {
                id: seletorSaida
                Layout.preferredWidth: 160
                model: ["Sair agora", "Sair às…"]
                currentIndex: raiz.sairAgora ? 0 : 1
                font.pixelSize: raiz.fonte
                onActivated: (indice) => {
                    raiz.sairAgora = indice === 0;
                    raiz.agoraMs = Date.now();
                    if (!raiz.sairAgora && raiz.horarioSaida === "") {
                        // Começa em 15 minutos, arredondado.
                        const sugestao = new Date(Date.now() + 15 * 60000);
                        sugestao.setMinutes(Math.ceil(sugestao.getMinutes() / 5) * 5, 0, 0);
                        raiz.horarioSaida = Qt.formatTime(sugestao, "HH:mm");
                    }
                }
            }

            TextField {
                id: campoHorario
                Layout.preferredWidth: 80
                visible: !raiz.sairAgora
                text: raiz.horarioSaida
                inputMask: "99:99"
                font.pixelSize: raiz.fonte
                color: acceptableInput ? raiz.corTexto : raiz.corErro
                validator: RegularExpressionValidator { regularExpression: /^([01]\d|2[0-3]):[0-5]\d$/ }
                onTextEdited: {
                    if (acceptableInput)
                        raiz.horarioSaida = text;
                }
            }

            Item { Layout.fillWidth: true }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: raiz.corBorda
        }

        // ----- Andamento, validação e erros -----
        RowLayout {
            Layout.fillWidth: true
            spacing: raiz.espaco / 2

            readonly property string dica: {
                raiz.versaoPontos; // reavalia quando os pontos mudam
                for (let i = 0; i < modeloPontos.count; ++i) {
                    if (!raiz.pontoDefinido(i))
                        return "Informe " + raiz.rotuloDoPonto(i) + " com o número e aguarde a verificação do endereço.";
                }
                return "";
            }
            readonly property string conteudo: raiz.calculandoAtual ? "Calculando rotas…"
                                             : raiz.erroAtual !== "" ? raiz.erroAtual
                                             : dica

            visible: conteudo !== ""

            BusyIndicator {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                running: raiz.calculandoAtual
                visible: running
            }
            Text {
                Layout.fillWidth: true
                text: parent.conteudo
                wrapMode: Text.Wrap
                color: raiz.erroAtual !== "" && !raiz.calculandoAtual ? raiz.corErro : raiz.corTextoSecundario
                font.pixelSize: raiz.fonte
            }
        }

        // ----- Rotas -----
        ListView {
            id: listaRotas

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: raiz.espaco / 2
            model: raiz.rotasAtuais
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
                id: cartaoRota

                required property int index
                required property var modelData
                readonly property bool selecionada: index === raiz.rotaSelecionada

                width: ListView.view.width
                height: conteudoCartao.implicitHeight + 2 * raiz.espaco
                radius: raiz.raio
                color: selecionada ? raiz.corSelecao : areaCartao.containsMouse ? raiz.corFundoCampo : raiz.corPainel
                border.color: selecionada ? raiz.corDestaque : raiz.corBorda
                border.width: selecionada ? 2 : 1

                RowLayout {
                    id: conteudoCartao

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: raiz.espaco
                    spacing: raiz.espaco

                    Icone {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: tamanho
                        Layout.preferredHeight: tamanho
                        nome: raiz.modos.find(function (m) { return m.id === cartaoRota.modelData.modo; }).icone
                        cor: cartaoRota.selecionada ? raiz.corDestaque : raiz.corTextoSecundario
                        tamanho: 22
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        RowLayout {
                            spacing: raiz.espaco / 2

                            Text {
                                text: raiz.formatarDuracao(cartaoRota.modelData.duracao)
                                color: raiz.corDoTempo(cartaoRota.modelData.duracao)
                                font.pixelSize: raiz.fonteDestaque
                                font.weight: Font.Bold
                            }
                            Text {
                                text: raiz.formatarDistancia(cartaoRota.modelData.distancia)
                                color: raiz.corTexto
                                font.pixelSize: raiz.fonteDestaque
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "Chegada às " + raiz.horarioChegada(cartaoRota.modelData.duracao)
                                  + (cartaoRota.modelData.via ? " · via " + cartaoRota.modelData.via : "")
                            elide: Text.ElideRight
                            color: raiz.corTextoSecundario
                            font.pixelSize: raiz.fontePequena
                        }

                        Row {
                            spacing: raiz.espaco / 2
                            visible: cartaoRota.modelData.maisRapida || cartaoRota.modelData.maisCurta

                            Repeater {
                                model: [
                                    { ativo: cartaoRota.modelData.maisRapida, rotulo: "Mais rápida", cor: raiz.corTempoCurto },
                                    { ativo: cartaoRota.modelData.maisCurta, rotulo: "Mais curta", cor: raiz.corDestaque }
                                ]

                                delegate: Rectangle {
                                    required property var modelData

                                    visible: modelData.ativo
                                    width: textoSelo.implicitWidth + 12
                                    height: textoSelo.implicitHeight + 4
                                    radius: height / 2
                                    color: Qt.alpha(modelData.cor, 0.12)

                                    Text {
                                        id: textoSelo
                                        anchors.centerIn: parent
                                        text: parent.modelData.rotulo
                                        color: parent.modelData.cor
                                        font.pixelSize: raiz.fontePequena
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    id: areaCartao
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: raiz.selecionarRota(cartaoRota.index)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "Rotas: OSRM (carro) e FOSSGIS (bicicleta e a pé), dados © OpenStreetMap. Tempos sem trânsito."
            color: raiz.corTextoSecundario
            font.pixelSize: raiz.fontePequena - 1
        }
    }
}
