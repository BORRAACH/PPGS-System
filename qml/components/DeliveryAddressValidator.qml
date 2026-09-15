import QtQuick
import QtQuick.Controls
import estilo 1.0
import "Texto.js" as Texto

// Endereço de entrega validado — substitui os antigos campos Endereço, Número
// e Bairro da Entrega (pages/entrega/Entrega.qml).
//
// O fluxo: digitar → escolher uma sugestão (ou Enter no texto livre) →
// validar → completar número e complemento → confirmar. Quem valida é o
// Python (controllers/validacaoEnderecoController.py e
// services/validacaoEndereco.py): Photon para o ponto, Nominatim reverse e
// ViaCEP para o CEP, e o grafo de ruas para a zona de entrega. Nenhum HTTP sai
// daqui: no Windows o HTTPS pelo Qt travava (ver services/requisicaoHttp.py).
// As respostas voltam por sinal com um número de geração, e a de um pedido já
// substituído por outro é descartada.
//
// Aqui moram só os campos e o estado. O resultado (selo, endereço oficial,
// mensagens e ações) é desenhado por ResultadoValidacaoEndereco.qml, que a
// tela põe onde quiser — na Entrega, acima do Resumo da comanda.
//
// Ponto de referência não tem campo próprio: vai na Observação da Entrega,
// que já sai na comanda.
//
// Validar NÃO bloqueia o pedido. Uma rua nova que o mapa ainda não conhece, ou
// a internet fora do ar, não pode impedir a entrega: "Usar mesmo assim" segue
// com o que foi digitado, e a Entrega só pergunta antes de imprimir um
// endereço que não ficou pronto (ver revisaoPendente).
Column {
    id: validador

    // Tom da tela dona do validador: foco dos campos e o botão "Tentar outro".
    property var tom: Estilo.screen.entrega
    readonly property color corDestaque: tom.accent
    // Vizinhos na ordem do Tab, fora deste componente.
    property Item campoAnterior: null
    property Item proximoCampo: null
    // Para quem está fora apontar o Tab para dentro daqui.
    property alias primeiroCampo: campoEndereco
    property alias ultimoCampo: campoCep

    // Adaptação a outras telas — o painel de rotas do Mapa
    // (pages/mapa/PainelRotas.qml) usa sem rótulo, sem complemento e sem zona
    // de entrega. Os padrões são os da Entrega.
    property string rotulo: "Endereço de entrega"
    property string placeholder: "DIGITE O ENDEREÇO (EX: RUA GOIÁS, 196)"
    // Complemento é para quem entrega; numa rota não serve.
    property bool mostrarComplemento: true
    // Zona de entrega (tempo de carro desde a pizzaria): uma rota vai a
    // qualquer lugar, e "fora da zona" não é problema dela.
    property bool verificarZona: true
    // Um campo só, no estilo do Google Maps: "Rua São Vicente de Paula, 311,
    // Centro, 12020-000". Número e CEP saem do texto (ver
    // validacaoEndereco.interpretar), e a validação reescreve o campo com o
    // endereço oficial. Os campos Número e CEP continuam existindo, escondidos:
    // são o estado do que foi lido do texto, e a validação segue igual.
    property bool campoUnico: false

    // ===== Endereço estruturado (o que a validação devolveu) =====
    property string rua: ""
    property string bairro: ""
    property string cidade: ""
    property string uf: ""
    property var latitude: null
    property var longitude: null
    property string validadoEm: ""
    // "" (nada validado ainda) | validando | incompleto | atencao | validado | erro
    property string status: ""
    // [{nivel: erro|incompleto|atencao|info, texto}]
    property var mensagens: []
    property var tempoRotaMin: null
    property string zona: ""
    property int limiteEntregaMin: 25
    property bool complementoObrigatorio: false
    property bool numeroConfirmadoNoMapa: false
    // O atendente escolheu seguir com o endereço sem validação ("Usar mesmo
    // assim"): a Entrega não pergunta de novo ao imprimir.
    property bool usarMesmoAssim: false
    // "Confirmar" apertado com o endereço pronto. Qualquer edição desfaz.
    property bool enderecoConfirmado: false

    // ===== O que está digitado =====
    readonly property string textoEndereco: campoEndereco.text.trim()
    readonly property string numero: campoNumero.text.trim()
    readonly property string complemento: campoComplemento.text.trim()
    readonly property string cep: campoCep.text.trim()

    // Mesmas regras de services/validacaoEndereco.py (numero_valido).
    readonly property bool numeroOk: /^\d{1,5}[A-Z]?$/.test(numero) || numero === "S/N"
    readonly property bool cepOk: /^\d{5}-\d{3}$/.test(cep)
    readonly property bool complementoOk: !mostrarComplemento || !complementoObrigatorio || complemento !== ""
    readonly property bool temEndereco: textoEndereco !== "" || numero !== "" || complemento !== ""
    // Validado e com tudo o que a validação pediu preenchido.
    readonly property bool pronto: status === "validado" && numeroOk && complementoOk && cepOk
    // O endereço existe e dá para achar o lugar: validado, com número e CEP.
    // Não olha complemento nem zona — é o que o painel de rotas precisa.
    readonly property bool verificado: status === "validado" && numeroOk && cepOk
    // Há endereço, ele não ficou pronto e ninguém decidiu seguir assim mesmo.
    readonly property bool revisaoPendente: temEndereco && !pronto && !usarMesmoAssim
    // Pendências só aparecem em vermelho depois da primeira validação: um
    // formulário que acabou de abrir não começa cheio de campos acusando erro.
    readonly property bool _mostrarPendencias: status !== "" && status !== "validando"

    readonly property var tomStatus: {
        if (usarMesmoAssim && status !== "validado")
            return Estilo.status.warning;
        switch (status) {
        case "validado":
            // Validado mas faltando o complemento do condomínio: ainda não é verde.
            return pronto ? Estilo.status.success : Estilo.status.warning;
        case "atencao":
            return Estilo.status.warning;
        case "erro":
        case "incompleto":
            return Estilo.status.error;
        }
        return Estilo.status.info;
    }

    readonly property string iconeStatus: {
        if (usarMesmoAssim && status !== "validado")
            return "fa6s.triangle-exclamation";
        switch (status) {
        case "validando":
            return "fa6s.hourglass-half";
        case "validado":
            return pronto ? "fa6s.circle-check" : "fa6s.triangle-exclamation";
        case "atencao":
            return "fa6s.triangle-exclamation";
        }
        return "fa6s.circle-xmark";
    }

    readonly property string rotuloStatus: {
        if (usarMesmoAssim && status !== "validado" && status !== "validando")
            return "Usado sem validação";
        switch (status) {
        case "validando":
            return "Validando";
        case "incompleto":
            return "Incompleto";
        case "erro":
            return "Erro";
        case "atencao":
            return "Atenção";
        case "validado":
            return enderecoConfirmado ? "Confirmado" : (pronto ? "Validado" : "Falta completar");
        }
        return "";
    }

    // No campo único, antes de validar, o texto digitado já é o resumo: o
    // Número escondido ainda pode ser o da validação anterior.
    readonly property string resumoEndereco: campoUnico && rua === "" ? textoEndereco
                                             : (rua || textoEndereco) + (numero ? ", " + numero : "")
                                               + (complemento ? " — " + complemento : "")

    readonly property string resumoLocal: {
        var partes = [];
        if (bairro)
            partes.push(bairro);
        var local = [cidade, uf].filter(function (parte) { return parte; }).join(" - ");
        if (local)
            partes.push(local);
        var texto = partes.join(" — ");
        if (cepOk)
            texto += (texto ? " · " : "") + "CEP " + cep;
        return texto;
    }

    // Emitido pelo "Confirmar" (botão ou Enter no fim), com o mesmo mapa de dados().
    signal confirmado(var dados)
    // O atendente voltou a digitar a rua. Não sai das escritas do próprio
    // componente (sugestão, validação, preencher) nem de limpar().
    signal enderecoEditado()

    // A sugestão escolhida (ou o texto livre interpretado) que a validação
    // usa. Vazia enquanto o atendente digita: é o que diz que o texto do campo
    // ainda não virou endereço.
    property var _escolha: ({})
    property int _geracaoSugestoes: 0
    property int _geracaoValidacao: 0
    // Número e CEP da última validação: mudou um deles, valida de novo.
    property string _numeroValidado: ""
    property string _cepValidado: ""
    // CEP escrito pela sugestão ou pela validação, e não pelo atendente: esse
    // some quando a rua muda; o digitado fica.
    property string _cepAutomatico: ""
    // Ligado enquanto o próprio componente escreve nos campos: a escrita
    // dispara onTextChanged, e sem isto ela contaria como edição do atendente.
    property bool _aplicando: false
    property string avisoBusca: ""

    spacing: Estilo.global.spacing.md

    // ---------- API ----------

    // O endereço para a comanda, o rascunho e o cadastro de clientes. As
    // chaves endereco/numero/bairro são as de sempre da Entrega.
    function dados() {
        var ruaFinal = validador.rua;
        var numeroFinal = validador.numero;
        var bairroFinal = validador.bairro;
        var cepFinal = validador.cepOk ? validador.cep : "";
        // Texto livre que ainda não virou endereço (Imprimir antes da resposta,
        // rascunho gravado no meio da digitação): rua e número separados do
        // mesmo jeito que a validação separaria.
        if (ruaFinal === "" && validador.textoEndereco !== "") {
            var info = validacaoEnderecoController.interpretar(validador.textoEndereco);
            ruaFinal = info.rua || validador.textoEndereco;
            // No campo único o texto é a fonte: o Número e o CEP escondidos
            // podem ser da validação anterior.
            numeroFinal = validador.campoUnico ? (info.numero || "") : (numeroFinal || info.numero || "");
            bairroFinal = bairroFinal || info.bairro || "";
            if (validador.campoUnico)
                cepFinal = info.cep || "";
        }
        return {
            "endereco": ruaFinal,
            "numero": numeroFinal,
            "bairro": bairroFinal,
            "complemento": validador.complemento,
            "cep": cepFinal,
            "cidade": validador.cidade,
            "uf": validador.uf,
            "latitude": validador.latitude,
            "longitude": validador.longitude,
            "validadoEm": validador.status === "validado" ? validador.validadoEm : "",
            "enderecoStatus": (validador.usarMesmoAssim && validador.status !== "validado") ? "usado_sem_validacao" : validador.status
        };
    }

    // Repõe um endereço salvo: cadastro do cliente (autofill por telefone),
    // rascunho ou comanda reaberta pela Consulta. Aceita "endereco" (comanda,
    // rascunho) ou "rua" (cadastro de clientes).
    //
    // Endereço que já veio validado, com CEP, volta validado sem consultar
    // nada. O resto é validado agora, em segundo plano.
    function preencher(d) {
        d = d || {};
        validador._pararConsultas();

        var ruaSalva = d.endereco || d.rua || "";
        validador._aplicando = true;
        campoEndereco.text = validador.campoUnico ? validador._textoCompleto(ruaSalva, d.numero || "", d.bairro || "", d.cep || "") : ruaSalva;
        campoEndereco.cursorPosition = 0;
        campoNumero.text = d.numero || "";
        campoComplemento.text = d.complemento || "";
        campoCep.text = d.cep || "";
        validador._aplicando = false;

        validador._zerarResultado();
        validador._cepAutomatico = validador.cep;
        validador.rua = ruaSalva;
        validador.bairro = d.bairro || "";
        validador.cidade = d.cidade || "";
        validador.uf = d.uf || "";
        validador.latitude = validador._numeroOuNulo(d.latitude);
        validador.longitude = validador._numeroOuNulo(d.longitude);
        validador._escolha = ruaSalva === "" ? ({}) : {
            "rua": ruaSalva,
            "bairro": validador.bairro,
            "latitude": validador.latitude,
            "longitude": validador.longitude
        };
        if (ruaSalva === "")
            return;

        if ((d.validadoEm || "") !== "" && validador.cepOk) {
            validador.validadoEm = d.validadoEm;
            validador.status = "validado";
            validador._numeroValidado = validador.numero;
            validador._cepValidado = validador.cep;
            return;
        }

        validador.validar();
        // Depois de validar(), que zera a escolha: quem decidiu seguir sem
        // validação continua decidido ao retomar o rascunho.
        validador.usarMesmoAssim = d.enderecoStatus === "usado_sem_validacao";
    }

    function limpar() {
        validador._pararConsultas();
        validador._escolha = ({});
        validador.avisoBusca = "";
        validador._aplicando = true;
        campoEndereco.text = "";
        campoNumero.text = "";
        campoComplemento.text = "";
        campoCep.text = "";
        validador._aplicando = false;
        validador._zerarResultado();
    }

    function focar() {
        campoEndereco.forceActiveFocus();
    }

    // Leva o foco ao que falta — o "Revisar" do aviso de endereço não
    // validado na Entrega.
    function focarPendencia() {
        if (validador.campoUnico) {
            campoEndereco.forceActiveFocus();
            return;
        }
        if (validador.textoEndereco === "" || validador.status === "" || validador.status === "erro" && validador.numeroOk)
            campoEndereco.forceActiveFocus();
        else if (!validador.numeroOk)
            campoNumero.forceActiveFocus();
        else if (!validador.complementoOk)
            campoComplemento.forceActiveFocus();
        else if (!validador.cepOk)
            campoCep.forceActiveFocus();
        else
            campoEndereco.forceActiveFocus();
    }

    // A frase da pendência principal, para o aviso da Entrega.
    function resumoPendencia() {
        if (validador.status === "validando")
            return "O endereço ainda está sendo validado.";
        if (validador.status === "")
            return "O endereço não foi validado.";
        if (!validador.numeroOk)
            return "Falta o número da residência.";
        if (!validador.complementoOk)
            return "Parece condomínio e falta o apartamento ou o bloco.";
        for (var i = 0; i < validador.mensagens.length; i++) {
            var mensagem = validador.mensagens[i];
            if (mensagem.nivel !== "info")
                return mensagem.texto;
        }
        if (!validador.cepOk)
            return "Falta o CEP do endereço.";
        return "Endereço não validado oficialmente.";
    }

    function confirmar() {
        if (!validador.pronto)
            return false;
        validador.enderecoConfirmado = true;
        validador.confirmado(validador.dados());
        return true;
    }

    // Enter no último campo, ou o botão "Confirmar": confirma se estiver
    // pronto e segue para o próximo campo da tela de qualquer jeito —
    // confirmar é opcional.
    function concluir() {
        validador.confirmar();
        if (validador.proximoCampo)
            validador.proximoCampo.forceActiveFocus();
    }

    // "Usar mesmo assim": segue com o endereço como está.
    function usarAssimMesmo() {
        validador.usarMesmoAssim = true;
        if (validador.proximoCampo)
            validador.proximoCampo.forceActiveFocus();
    }

    // "Tentar outro": recomeça do campo de endereço.
    function tentarOutro() {
        validador.limpar();
        validador.focar();
    }

    // ---------- Busca e validação ----------

    // "Rua Goiás, 196, Jardim dos Estados, 12062-130": o texto do campo único.
    function _textoCompleto(rua, numero, bairro, cep) {
        return [rua, numero, bairro, cep].filter(function (parte) { return parte; }).join(", ");
    }

    // Depois de a rua virar endereço: nos campos separados o foco segue para
    // o Número (ou o que vier depois dele); no campo único fica onde está.
    function _focarDepoisDaRua() {
        if (validador.campoUnico)
            campoEndereco.cursorPosition = campoEndereco.text.length;
        else
            (validador.numeroOk ? validador._depoisDoNumero() : campoNumero).forceActiveFocus();
    }

    // A cada tecla no campo: o que está salvo nesta máquina (histórico e
    // índice de ruas) aparece na hora; o Photon entra depois do debounce.
    function _sugerir() {
        debounceBusca.stop();
        var termo = validador.textoEndereco;
        if (termo === "") {
            listaSugestoes.close();
            validador.avisoBusca = "";
            return;
        }
        listaSugestoes.mostrar(validacaoEnderecoController.sugerirLocais(termo));
        if (termo.length >= 3)
            debounceBusca.restart();
    }

    // Aceita uma sugestão da lista: a rua vai para o campo, o número (quando a
    // sugestão trouxe) para o Número, e a validação começa.
    function escolher(sugestao) {
        if (!sugestao)
            return;
        validador._pararConsultas();
        validador._aplicando = true;
        campoEndereco.text = validador.campoUnico
            ? validador._textoCompleto(sugestao.rua || sugestao.nome || "", sugestao.numero || "", sugestao.bairroNome || "", sugestao.cep || "")
            : (sugestao.rua || sugestao.nome || "");
        campoEndereco.cursorPosition = campoEndereco.text.length;
        // No campo único a sugestão sem número zera o Número: o texto não tem.
        if (sugestao.numero || validador.campoUnico)
            campoNumero.text = sugestao.numero || "";
        // O CEP de outra rua não vale para esta.
        if (validador.cep === validador._cepAutomatico)
            campoCep.text = sugestao.cep || "";
        validador._aplicando = false;

        validador._zerarResultado();
        validador._cepAutomatico = sugestao.cep || "";
        validador.bairro = sugestao.bairroNome || "";
        validador._escolha = sugestao;
        validador.validar();
        validador._focarDepoisDaRua();
    }

    // Enter (ou saída do campo) sem sugestão escolhida: valida o texto livre,
    // "rua goias 196" separado em rua e número pelo Python.
    function validarTexto() {
        var termo = validador.textoEndereco;
        if (termo === "")
            return;
        var info = validacaoEnderecoController.interpretar(termo);
        if (!info || !info.rua)
            return;

        validador._pararConsultas();
        validador._aplicando = true;
        if (validador.campoUnico) {
            // O texto fica como foi escrito até a validação devolver o
            // oficial; número e CEP saem dele.
            campoNumero.text = info.numero || "";
            campoCep.text = info.cep || "";
        } else {
            campoEndereco.text = info.rua;
            if (info.numero && validador.numero === "")
                campoNumero.text = info.numero;
        }
        validador._aplicando = false;

        validador._zerarResultado();
        validador.bairro = info.bairro || "";
        validador._escolha = {
            "rua": info.rua,
            "bairro": info.bairro || "",
            "pistaCondominio": info.pistaCondominio === true
        };
        validador.validar();
    }

    // Valida a escolha atual com o número e, quando digitado pelo atendente, o
    // CEP. O CEP que veio da sugestão ou de uma validação anterior não vai: a
    // validação o descobre de novo — o número pode ter mudado de faixa.
    function validar() {
        // Cópia: o semZona não pode grudar na escolha guardada.
        var escolha = Object.assign({}, validador._escolha || {});
        if (!escolha.rua)
            return;
        if (!validador.verificarZona)
            escolha.semZona = true;
        revalidacao.stop();
        validador.status = "validando";
        validador.mensagens = [];
        validador.enderecoConfirmado = false;
        validador.usarMesmoAssim = false;
        validador._numeroValidado = validador.numero;
        validador._cepValidado = validador.cep;
        var cepDigitado = validador.cepOk && validador.cep !== validador._cepAutomatico;
        validador._geracaoValidacao = cepDigitado
            ? validacaoEnderecoController.validarComCep(escolha, validador.numero, validador.cep)
            : validacaoEnderecoController.validar(escolha, validador.numero);
        // Geração 0: o controller falhou antes de começar (ver @protegido).
        if (validador._geracaoValidacao === 0) {
            validador.status = "atencao";
            validador.mensagens = [{ "nivel": "atencao", "texto": "Não foi possível validar agora. Revise os dados." }];
        }
    }

    function _aplicarResultado(r) {
        validador._aplicando = true;
        if (r.rua && !validador.campoUnico)
            campoEndereco.text = r.rua;
        // O CEP achado entra quando o campo está vazio ou ainda tem o CEP
        // automático — decidido pelo CONTEÚDO, e não pelo foco: sem complemento
        // (painel de rotas) o foco cai no CEP logo depois da sugestão, e o CEP
        // nunca era escrito. Se o atendente começou a digitar, o texto é outro
        // e fica. CEP corrigido pela validação (era de outra rua ou de outra
        // faixa de números) substitui até o digitado: ficar com ele mandaria o
        // CEP errado para a comanda e o cadastro.
        if (r.cep && (r.cepCorrigidoDe || validador.cep === "" || validador.cep === validador._cepAutomatico))
            campoCep.text = r.cep;
        // A validação descartou o CEP da sugestão (era de outra rua): ele sai
        // do campo. O digitado pelo atendente fica.
        else if (!r.cep && validador.cep !== "" && validador.cep === validador._cepAutomatico)
            campoCep.text = "";
        // Campo único: o endereço oficial inteiro volta para o campo. Sem foco,
        // o cursor vai para o começo, para a rua ficar à vista.
        if (validador.campoUnico) {
            if (r.numero)
                campoNumero.text = r.numero;
            campoEndereco.text = validador._textoCompleto(r.rua || validador.textoEndereco, validador.numero, r.bairro || "",
                                                          validador.cepOk ? validador.cep : "");
            campoEndereco.cursorPosition = campoEndereco.activeFocus ? campoEndereco.text.length : 0;
        }
        validador._aplicando = false;

        if (r.cep && validador.cep === r.cep)
            validador._cepAutomatico = r.cep;
        validador.rua = r.rua || "";
        validador.bairro = r.bairro || "";
        validador.cidade = r.cidade || "";
        validador.uf = r.uf || "";
        validador.latitude = validador._numeroOuNulo(r.latitude);
        validador.longitude = validador._numeroOuNulo(r.longitude);
        validador.validadoEm = r.validadoEm || "";
        validador.mensagens = r.mensagens || [];
        validador.tempoRotaMin = validador._numeroOuNulo(r.tempoRotaMin);
        validador.zona = r.zona || "";
        validador.limiteEntregaMin = r.limiteEntregaMin || 25;
        validador.complementoObrigatorio = r.complementoObrigatorio === true;
        validador.numeroConfirmadoNoMapa = r.numeroConfirmadoNoMapa === true;
        validador._cepValidado = validador.cep;
        // A próxima validação (número trocado) parte do que esta achou: rua
        // oficial, ponto e condomínio.
        validador._escolha = {
            "rua": validador.rua,
            "bairro": validador.bairro,
            "latitude": validador.latitude,
            "longitude": validador.longitude,
            "pistaCondominio": validador.complementoObrigatorio
        };
        validador.status = r.status || "atencao";
    }

    // O atendente voltou a digitar a rua: o que foi validado não vale mais.
    function _invalidar() {
        revalidacao.stop();
        validador._geracaoValidacao = 0;
        validador._escolha = ({});
        if (validador.cep !== "" && validador.cep === validador._cepAutomatico) {
            validador._aplicando = true;
            campoCep.text = "";
            validador._aplicando = false;
        }
        validador._zerarResultado();
        validador.enderecoEditado();
    }

    function _pararConsultas() {
        listaSugestoes.close();
        debounceBusca.stop();
        revalidacao.stop();
        validador._geracaoSugestoes = 0;
        validador._geracaoValidacao = 0;
    }

    function _zerarResultado() {
        validador.rua = "";
        validador.bairro = "";
        validador.cidade = "";
        validador.uf = "";
        validador.latitude = null;
        validador.longitude = null;
        validador.validadoEm = "";
        validador.status = "";
        validador.mensagens = [];
        validador.tempoRotaMin = null;
        validador.zona = "";
        validador.complementoObrigatorio = false;
        validador.numeroConfirmadoNoMapa = false;
        validador.usarMesmoAssim = false;
        validador.enderecoConfirmado = false;
        validador._numeroValidado = "";
        validador._cepValidado = "";
    }

    function _numeroOuNulo(valor) {
        if (valor === null || valor === undefined || valor === "")
            return null;
        var numero = Number(valor);
        return isNaN(numero) ? null : numero;
    }

    function _enterNoEndereco() {
        if (listaSugestoes.opened && listaSugestoes.confirmar())
            return; // escolher() já levou o foco adiante
        if (!validador._escolha.rua)
            validador.validarTexto();
        validador._focarDepoisDaRua();
    }

    // O campo que vem depois do Número: o Complemento, ou o CEP quando não há
    // complemento.
    function _depoisDoNumero() {
        return validador.mostrarComplemento ? campoComplemento : campoCep;
    }

    // Enter no Complemento: falta o CEP, vai até ele; senão conclui.
    function _enterNoComplemento() {
        if (validador._mostrarPendencias && !validador.cepOk)
            campoCep.forceActiveFocus();
        else
            validador.concluir();
    }

    Component.onCompleted: {
        if (validador.verificarZona)
            validacaoEnderecoController.prepararZona();
    }

    // Debounce do Photon: a consulta sai ~350ms depois da ÚLTIMA tecla, e não
    // a cada uma (o Photon público pede moderação).
    Timer {
        id: debounceBusca

        interval: 350
        onTriggered: {
            if (!campoEndereco.activeFocus || validador.textoEndereco.length < 3)
                return;
            validador._geracaoSugestoes = validacaoEnderecoController.sugerir(validador.textoEndereco);
        }
    }

    // Número trocado depois de validar: valida de novo quando o atendente
    // para de digitar (o número decide se a casa aparece no mapa).
    Timer {
        id: revalidacao

        interval: 700
        onTriggered: {
            if (validador._escolha.rua && validador.numero !== validador._numeroValidado)
                validador.validar();
        }
    }

    Connections {
        target: validacaoEnderecoController

        function onSugestoesProntas(geracao, sugestoes, aviso) {
            // Resposta de uma busca já substituída, ou o atendente já saiu do campo.
            if (geracao !== validador._geracaoSugestoes || !campoEndereco.activeFocus)
                return;
            validador.avisoBusca = aviso;
            listaSugestoes.mostrar(sugestoes);
        }

        function onValidacaoPronta(geracao, resultado) {
            if (geracao !== validador._geracaoValidacao)
                return;
            validador._aplicarResultado(resultado);
        }
    }

    // ---------- Campos ----------

    Column {
        spacing: 4

        Text {
            visible: validador.rotulo !== ""
            text: validador.rotulo
            font.pixelSize: Estilo.global.fontSize.sm
            font.bold: true
            color: Estilo.global.textSecondary
        }

        TextField {
            id: campoEndereco

            width: validador.width
            color: Estilo.global.textInput
            placeholderTextColor: Estilo.global.textPlaceholder
            placeholderText: validador.placeholder
            topPadding: 10
            bottomPadding: 10
            leftPadding: 10
            rightPadding: 10
            KeyNavigation.tab: validador.campoUnico ? validador.proximoCampo : campoNumero
            KeyNavigation.backtab: validador.campoAnterior
            // Setas navegam as sugestões sem tirar o foco do campo (ver
            // ListaSugestoes.qml).
            Keys.onDownPressed: listaSugestoes.mover(1)
            Keys.onUpPressed: listaSugestoes.mover(-1)
            Keys.onReturnPressed: validador._enterNoEndereco()
            Keys.onEnterPressed: validador._enterNoEndereco()
            // Só consumido com a lista aberta; fechada, o Esc segue para quem
            // mais o trate.
            Keys.onEscapePressed: function (evento) {
                evento.accepted = listaSugestoes.opened;
                listaSugestoes.close();
            }
            // Mesma capitalização do nome do cliente. O gate de activeFocus
            // deixa de fora as escritas programáticas (autofill, rascunho).
            onTextChanged: {
                Texto.capitalizarCampo(campoEndereco);
                if (activeFocus && !validador._aplicando) {
                    validador._invalidar();
                    validador._sugerir();
                }
            }
            onActiveFocusChanged: {
                if (!activeFocus)
                    listaSugestoes.close();
            }
            // Saiu do campo com um texto que ainda não virou endereço (Tab sem
            // escolher sugestão): valida o que foi digitado.
            onEditingFinished: {
                if (!validador._escolha.rua && validador.textoEndereco !== "")
                    validador.validarTexto();
            }

            background: Rectangle {
                radius: Estilo.global.radius.pill
                color: Estilo.global.inputBackground
                border.color: campoEndereco.activeFocus ? validador.corDestaque
                            : (validador._mostrarPendencias && (validador.campoUnico ? (validador.status === "erro" || validador.status === "incompleto")
                                                                                   : (validador.status === "erro" && validador.numeroOk))
                               ? Estilo.status.error.content : Estilo.global.border)
                border.width: Estilo.global.borderWidth.hairline
            }
        }

        ListaSugestoes {
            id: listaSugestoes

            campo: campoEndereco

            // O popup só dá texto e detalhe; a sugestão inteira (rua, número,
            // CEP, ponto) ainda está no índice destacado.
            onEscolhida: validador.escolher(listaSugestoes.sugestoes[listaSugestoes.indiceSelecionado])
        }

        // Photon fora do ar: as sugestões ficam só nas locais, e o atendente
        // sabe por quê.
        Text {
            width: validador.width
            visible: validador.avisoBusca !== "" && campoEndereco.activeFocus
            text: validador.avisoBusca
            font.pixelSize: Estilo.global.fontSize.xs
            color: Estilo.status.warning.content
            wrapMode: Text.WordWrap
        }
    }

    // Número, Complemento e CEP numa linha só, na ordem do Tab.
    Row {
        id: linhaDetalhes

        // No campo único, número e CEP estão no próprio texto.
        visible: !validador.campoUnico
        // O que as três colunas repartem, sem os dois espaços entre elas.
        readonly property real larguraLivre: validador.width - spacing * (validador.mostrarComplemento ? 2 : 1)

        spacing: Estilo.global.spacing.md

        Column {
            spacing: 4

            Text {
                text: "Número"
                font.pixelSize: Estilo.global.fontSize.sm
                font.bold: true
                color: validador._mostrarPendencias && !validador.numeroOk ? Estilo.status.error.content : Estilo.global.textSecondary
            }

            TextField {
                id: campoNumero

                width: Math.round(linhaDetalhes.larguraLivre * (validador.mostrarComplemento ? 0.22 : 0.45))
                color: Estilo.global.textInput
                placeholderTextColor: Estilo.global.textPlaceholder
                placeholderText: "NÚMERO"
                topPadding: 10
                bottomPadding: 10
                leftPadding: 10
                rightPadding: 10
                KeyNavigation.tab: validador.mostrarComplemento ? campoComplemento : campoCep
                KeyNavigation.backtab: campoEndereco
                Keys.onReturnPressed: validador._depoisDoNumero().forceActiveFocus()
                Keys.onEnterPressed: validador._depoisDoNumero().forceActiveFocus()
                // Algarismos com uma letra opcional (196, 196A) ou S/N.
                validator: RegularExpressionValidator {
                    regularExpression: /^(\d{0,5}[A-Za-z]?|[Ss](\/[Nn]?)?)$/
                }
                onTextChanged: {
                    var maiusculo = text.toUpperCase();
                    if (maiusculo !== text) {
                        text = maiusculo;
                        return;
                    }
                    if (validador._aplicando)
                        return;
                    validador.enderecoConfirmado = false;
                    if (validador._escolha.rua)
                        revalidacao.restart();
                }
                // Saiu do campo: não espera o debounce.
                onEditingFinished: {
                    if (revalidacao.running) {
                        revalidacao.stop();
                        revalidacao.triggered();
                    }
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: Estilo.global.inputBackground
                    border.color: campoNumero.activeFocus ? validador.corDestaque
                                : (validador._mostrarPendencias && !validador.numeroOk ? Estilo.status.error.content : Estilo.global.border)
                    border.width: validador._mostrarPendencias && !validador.numeroOk ? 2 : Estilo.global.borderWidth.hairline
                }
            }
        }

        Column {
            visible: validador.mostrarComplemento
            spacing: 4

            Text {
                text: validador.complementoObrigatorio ? "Complemento (obrigatório)" : "Complemento"
                font.pixelSize: Estilo.global.fontSize.sm
                font.bold: true
                color: validador._mostrarPendencias && !validador.complementoOk ? Estilo.status.error.content : Estilo.global.textSecondary
            }

            TextField {
                id: campoComplemento

                width: linhaDetalhes.larguraLivre - campoNumero.width - campoCep.width
                color: Estilo.global.textInput
                placeholderTextColor: Estilo.global.textPlaceholder
                placeholderText: "EX: APTO 501, BLOCO A"
                topPadding: 10
                bottomPadding: 10
                leftPadding: 10
                rightPadding: 10
                maximumLength: 80
                KeyNavigation.tab: campoCep
                KeyNavigation.backtab: campoNumero
                Keys.onReturnPressed: validador._enterNoComplemento()
                Keys.onEnterPressed: validador._enterNoComplemento()
                onTextChanged: {
                    Texto.capitalizarCampoFrase(campoComplemento);
                    if (!validador._aplicando)
                        validador.enderecoConfirmado = false;
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: Estilo.global.inputBackground
                    border.color: campoComplemento.activeFocus ? validador.corDestaque
                                : (validador._mostrarPendencias && !validador.complementoOk ? Estilo.status.error.content : Estilo.global.border)
                    border.width: validador._mostrarPendencias && !validador.complementoOk ? 2 : Estilo.global.borderWidth.hairline
                }
            }
        }

        Column {
            spacing: 4

            Text {
                text: "CEP"
                font.pixelSize: Estilo.global.fontSize.sm
                font.bold: true
                color: validador._mostrarPendencias && !validador.cepOk ? Estilo.status.error.content : Estilo.global.textSecondary
            }

            TextField {
                id: campoCep

                // Evita recursão: reformatar o texto dispara onTextChanged de
                // novo (mesmo caso do telefone da Entrega).
                property bool reformatando: false

                width: validador.mostrarComplemento ? Math.round(linhaDetalhes.larguraLivre * 0.28) : linhaDetalhes.larguraLivre - campoNumero.width
                color: Estilo.global.textInput
                placeholderTextColor: Estilo.global.textPlaceholder
                placeholderText: "CEP"
                topPadding: 10
                bottomPadding: 10
                leftPadding: 10
                rightPadding: 10
                inputMethodHints: Qt.ImhDigitsOnly
                KeyNavigation.tab: validador.proximoCampo
                KeyNavigation.backtab: validador.mostrarComplemento ? campoComplemento : campoNumero
                Keys.onReturnPressed: validador.concluir()
                Keys.onEnterPressed: validador.concluir()
                onTextChanged: {
                    if (reformatando)
                        return;
                    reformatando = true;
                    // "12062130" vira "12062-130" enquanto se digita.
                    var digitos = text.replace(/\D/g, "").slice(0, 8);
                    text = digitos.length > 5 ? digitos.slice(0, 5) + "-" + digitos.slice(5) : digitos;
                    reformatando = false;
                    if (!validador._aplicando)
                        validador.enderecoConfirmado = false;
                }
                // CEP digitado ou corrigido: valida de novo a partir dele (o
                // ViaCEP devolve rua e bairro oficiais).
                onEditingFinished: {
                    if (validador.cepOk && validador.cep !== validador._cepValidado && validador._escolha.rua)
                        validador.validar();
                }

                background: Rectangle {
                    radius: Estilo.global.radius.pill
                    color: Estilo.global.inputBackground
                    border.color: campoCep.activeFocus ? validador.corDestaque
                                : (validador._mostrarPendencias && !validador.cepOk ? Estilo.status.error.content : Estilo.global.border)
                    border.width: validador._mostrarPendencias && !validador.cepOk ? 2 : Estilo.global.borderWidth.hairline
                }
            }
        }
    }
}
