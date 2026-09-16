"""Sugestões de rua e bairro para os campos Endereço e Bairro da Entrega.qml,
sem passar pelo ppgs_server.

Três fontes, nesta ordem:

- o histórico dos endereços já usados em comandas
  (services/rede/historicoEnderecos.py) — conhece os nomes de bairro que a
  equipe escreve;
- o índice local com todas as ruas da cidade (services/rede/indiceRuas.py),
  montado em segundo plano a partir do Overpass e dos Correios — instantâneo,
  sem internet, com o bairro oficial;
- o Photon (https://photon.komoot.io), consultado SÓ quando o termo não casa
  com nada nas duas primeiras. As ruas que ele acha na cidade entram no
  índice, e a próxima busca delas já é local.

O índice é acompanhado do cadastro de endereços do IBGE (services/cnefe.py),
baixado por cada máquina assim que se sabe a cidade e a UF do índice — quem o
usa é a validação do endereço (controllers/validacaoEnderecoController.py).

Os dois arquivos são replicados pela malha, então a máquina que montou o
índice (a que definiu a localização) serve todas as outras.

Antes isto ia pelo ppgs_server, e a sugestão ficava refém dele: binário
desatualizado respondendo 404, rate limiter de 200ms compartilhado por todos
os balcões, máquina hospedeira desligada.

O bairro já digitado muda a ORDEM, não a consulta: ruas daquele bairro sobem
para o topo.

Falha é silenciosa por desenho: sem nada local e sem internet, lista vazia —
o campo segue sendo um campo de texto comum.

As requisições HTTP (Photon e ipinfo) não passam pelo QNetworkAccessManager:
no Windows ele travava sem nunca responder. Saem por services/requisicaoHttp.py,
só com o Python, numa thread do pool, e a resposta volta para a thread da
interface por sinal (ver _pedir_json)."""

import threading
import time
import traceback
from concurrent.futures import ThreadPoolExecutor

from PyQt6.QtCore import QObject, QTimer, pyqtProperty, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services import cnefe, montadorIndiceRuas, requisicaoHttp
from services.buscaCardapio import normalizar
from services.enderecoFormatado import bairros_equivalentes, escolher_bairro, formatar_endereco, normalizar_endereco
from services.rede import historicoEnderecos, indiceRuas, localizacaoServidor, rede, relogio

_URL_PHOTON = "https://photon.komoot.io/api/"
# Geolocalização pela conexão de internet, para quando nenhuma máquina da rede
# definiu a localização ainda. Precisão de cidade — é o que o índice precisa.
_URL_GEOLOCALIZACAO_IP = "https://ipinfo.io/json"
# Por espera de rede (conectar, cada leitura) — ver requisicaoHttp.obter_json.
_TIMEOUT_S = 6
# Threads das requisições. Duas bastam: uma busca por campo (Endereço e
# Bairro), e a resposta de uma busca já substituída é só descartada.
_THREADS_HTTP = 2

# Mesmo mínimo que o debounce da Entrega.qml aplica: com 1-2 letras quase
# tudo casa, e a lista não sugere nada — só rola.
_MINIMO_CARACTERES = 3
# Mais que isso não cabe no popup (ver ListaSugestoes.qml).
_LIMITE_SUGESTOES = 8
# Pede ao Photon mais do que se mostra: a ordenação por bairro precisa de
# candidatos para escolher.
_LIMITE_PHOTON = 15

# O cache absorve o vaivém da digitação (apagar e redigitar o mesmo prefixo).
_TTL_CACHE_S = 10 * 60
_MAXIMO_CACHE = 200

_EVENTO_ENDERECO_USADO = "endereco_usado"
_EVENTO_INDICE_RUAS = "indice_ruas_alterado"

# Idade a partir da qual o índice é baixado de novo: rua nova aparece no mapa,
# e um mês é o bastante para o índice acompanhar sem pesar em ninguém.
_IDADE_MAXIMA_INDICE_S = 30 * 24 * 3600
# Espaço entre duas consultas ao ViaCEP. O serviço é gratuito e bloqueia quem
# exagera; 1,5 s dá ~1 hora para 2.500 ruas, uma vez na vida da instalação.
_INTERVALO_VIACEP_S = 1.5
# Falhas seguidas até a consulta desistir por esta sessão (retoma na próxima).
_FALHAS_SEGUIDAS_VIACEP = 5
# Quanto uma máquina que não é a do servidor espera o índice chegar pela malha
# antes de montar o seu. Mais que um ciclo de reconciliação (2 min).
_ESPERA_INDICE_DA_HOSPEDEIRA_MS = 3 * 60 * 1000
# Atraso da gravação do índice em disco: uma gravação por rajada de mudanças
# (os 32 blocos de uma reconciliação, um lote dos Correios), não uma por
# mudança.
_ATRASO_GRAVACAO_INDICE_MS = 3000
# O que o ViaCEP responde é gravado e publicado em lote: gravar 300 KB de
# JSON a cada 1,5 s seria desgaste à toa na máquina fraca.
_INTERVALO_GRAVACAO_CORREIOS_MS = 15000


# ---------- Funções puras (ordenação e leitura do Photon) ----------

def _unicos(grupos, chave=normalizar_endereco, limite=_LIMITE_SUGESTOES):
    """Concatena os grupos na ordem dada, sem repetir item (pela `chave`,
    que compara sem acento, caixa, pontuação e abreviação) e parando no
    limite."""
    vistos = set()
    saida = []
    for grupo in grupos:
        for item in grupo:
            k = chave(item)
            if not k or k in vistos:
                continue
            vistos.add(k)
            saida.append(item)
            if len(saida) >= limite:
                return saida
    return saida


def ordenar_enderecos(bairro, historico, ruas_indice, ruas_photon):
    """Lista final de ruas sugeridas, como [{"nome", "bairro", "fonte"}] — o
    bairro aparece embaixo do nome na lista e preenche o campo Bairro quando a
    rua é escolhida (ver Entrega.qml). "" quando a fonte não sabe o bairro.
    "fonte" diz de onde veio: "historico", "correios" (bairro oficial do
    índice), "indice" (bairro do OSM no índice) ou "photon".

    - `historico`: registros de historicoEnderecos.buscar_ruas.
    - `ruas_indice`: [{"nome", "bairros", "oficiais"}] de indiceRuas.buscar_ruas.
    - `ruas_photon`: [{"nome", "bairros"}] na ordem de relevância do Photon.

    Ordem: as três fontes com o bairro digitado, depois as três inteiras. O
    bairro casa por começo ("Barr" já prioriza "Barranco"), para valer
    enquanto ainda está sendo digitado.

    Rua com bairro dos Correios vira uma sugestão por bairro oficial — uma
    avenida longa tem um CEP por trecho, cada um no seu bairro. Sem bairro
    oficial, uma sugestão só, com o bairro mais provável.

    O endereço salvo sai com a grafia do índice (ou do Photon) quando é a mesma
    rua: "RUA ANTONIO ROMERO / ARCO IRIS" do histórico vira "Rua Antônio Romero
    / Parque Arco Íris", e aí se junta à sugestão do índice em vez de aparecer
    duas vezes. A repetição é cortada por rua E bairro, já formatados e
    comparados por enderecoFormatado.normalizar_endereco."""
    bairro_digitado = normalizar_endereco(bairro)

    def do_bairro(nome_bairro):
        if not bairro_digitado or not nome_bairro:
            return False
        return normalizar_endereco(nome_bairro).startswith(bairro_digitado) or bairros_equivalentes(bairro, nome_bairro)

    # Grafia formatada de cada rua, pelo nome comparável: o índice primeiro
    # (é ele que tem os bairros oficiais), depois o Photon.
    referencias = {}
    for r in ruas_indice:
        referencias.setdefault(normalizar_endereco(r["nome"]), (r["nome"], r.get("oficiais") or [], r.get("bairros") or []))
    for p in ruas_photon:
        referencias.setdefault(normalizar_endereco(p["nome"]), (p["nome"], [], p.get("bairros") or []))

    def formatada(nome, nome_bairro):
        referencia = referencias.get(normalizar_endereco(nome))
        if referencia is None:
            return {"nome": nome, "bairro": nome_bairro, "fonte": "historico"}
        nome_formatado, oficiais, conhecidos = referencia
        return {"nome": nome_formatado, "bairro": escolher_bairro(nome_bairro, oficiais, conhecidos), "fonte": "historico"}

    def uma(nome, bairros, fonte):
        bairros = [b for b in bairros if b]
        # Mostra o bairro que casou com o digitado; senão o mais provável.
        casados = [b for b in bairros if do_bairro(b)]
        return [{"nome": nome, "bairro": (casados or bairros or [""])[0], "fonte": fonte}]

    def cada(nome, bairros, fonte):
        return [{"nome": nome, "bairro": b, "fonte": fonte} for b in bairros] or [{"nome": nome, "bairro": "", "fonte": fonte}]

    do_historico = [formatada(r["rua"], r.get("bairro", "")) for r in historico]
    do_indice = [
        s for r in ruas_indice
        for s in (cada(r["nome"], r["oficiais"], "correios") if r.get("oficiais") else uma(r["nome"], r["bairros"], "indice"))
    ]
    do_photon = [s for p in ruas_photon for s in uma(p["nome"], p["bairros"], "photon")]

    fontes = (do_historico, do_indice, do_photon)
    return _unicos(
        [[s for s in fonte if do_bairro(s["bairro"])] for fonte in fontes] + list(fontes),
        chave=lambda s: f"{normalizar_endereco(s['nome'])}|{normalizar_endereco(s['bairro'])}",
    )


def ordenar_bairros(*grupos):
    return _unicos(grupos)


def _ruas_do_photon(features):
    ruas = []
    for props, _coordenadas in features:
        nome = props.get("name") or props.get("street")
        if nome:
            bairros = [str(b) for b in (props.get("district"), props.get("locality")) if b]
            ruas.append({"nome": str(nome), "bairros": bairros, "cidade": str(props.get("city") or "")})
    return ruas


def _bairros_do_photon(features):
    return [str(props["name"]) for props, _coordenadas in features if props.get("name")]


def _features_de(dados):
    """[(properties, coordinates)] do GeoJSON do Photon, ou None se a
    resposta não prestou (sem rede, timeout, erro HTTP, JSON inválido — que
    chegam aqui como dados None)."""
    if not isinstance(dados, dict) or not isinstance(dados.get("features"), list):
        return None
    features = []
    for feature in dados["features"]:
        if not isinstance(feature, dict):
            continue
        props = feature.get("properties")
        coordenadas = (feature.get("geometry") or {}).get("coordinates") or []
        if isinstance(props, dict):
            features.append((props, coordenadas))
    return features


class SugestoesEnderecoService(QObject):
    # (termo consultado, sugestões) — o termo volta junto porque a consulta é
    # assíncrona, e a QML descarta a resposta que chegar depois de o atendente
    # já ter digitado outra coisa. Ruas vêm como [{"nome", "bairro"}] (ver
    # ordenar_enderecos); bairros, como nomes.
    enderecosSugeridos = pyqtSignal(str, "QVariantList")
    bairrosSugeridos = pyqtSignal(str, "QVariantList")
    # Resposta do "Definir" da Localização da pizzaria em Rede.qml: (deu certo,
    # descrição do lugar encontrado ou motivo da falha).
    localizacaoDefinida = pyqtSignal(bool, str)
    statusIndiceMudou = pyqtSignal()

    # Pontes da thread de montagem do índice para a thread da interface. Um
    # sinal emitido de outra thread chega aqui enfileirado no loop de eventos:
    # é o que garante que o índice só é gravado por esta thread.
    _indiceBaixado = pyqtSignal(object, object)
    _correiosConsultado = pyqtSignal(str, object)
    _montagemTerminou = pyqtSignal(str)
    _indiceLido = pyqtSignal(object)
    # Fim da montagem do cadastro do IBGE: "" ou o motivo da falha.
    _cnefeTerminou = pyqtSignal(str)
    # A resposta de uma requisição HTTP feita numa thread do pool (ver
    # _pedir_json): (quem espera, JSON decodificado ou None, erro ou None).
    _respostaHttp = pyqtSignal(object, object, object)

    def __init__(self):
        super().__init__()
        self._http = ThreadPoolExecutor(max_workers=_THREADS_HTTP, thread_name_prefix="sugestoes-http")
        # (camadas, termo normalizado, bbox) -> (instante, resultado extraído)
        self._cache = {}
        # campo ("endereco"/"bairro") -> número da busca mais recente. Uma
        # requisição em thread não tem como ser abortada: a resposta de uma
        # busca que já foi substituída por outra é descartada quando chega.
        self._geracao = {}
        self._detectando_localizacao = False
        # Só para o log não repetir "Photon indisponível" a cada tecla.
        self._photon_respondendo = True

        self._montando = False
        self._cancelar_montagem = threading.Event()
        self._cancelar_cnefe = threading.Event()
        self._trabalho_cnefe = ""
        # (cidade, UF) cuja montagem falhou nesta sessão: não tenta de novo a
        # cada bloco do índice que chega pela malha, só na próxima abertura.
        self._cnefe_falhou_para = None
        self._cnefe_para = None
        self._trabalho_indice = ""
        self._status_indice = ""
        # Respostas do ViaCEP esperando a próxima gravação em lote.
        self._correios_a_gravar = {}
        self._timer_gravar_correios = QTimer(self)
        self._timer_gravar_correios.setSingleShot(True)
        self._timer_gravar_correios.setInterval(_INTERVALO_GRAVACAO_CORREIOS_MS)
        self._timer_gravar_correios.timeout.connect(self._gravar_correios)
        # Espera pelo índice da máquina responsável por ele (ver _garantir_indice).
        self._espera_hospedeira = QTimer(self)
        self._espera_hospedeira.setSingleShot(True)
        self._espera_hospedeira.setInterval(_ESPERA_INDICE_DA_HOSPEDEIRA_MS)
        self._espera_hospedeira.timeout.connect(lambda: self._garantir_indice(sem_hospedeira=True))
        self._indiceBaixado.connect(self._ao_indice_baixado)
        self._correiosConsultado.connect(self._ao_correios_consultado)
        self._montagemTerminou.connect(self._ao_montagem_terminar)
        self._indiceLido.connect(self._ao_indice_lido)
        self._cnefeTerminou.connect(self._ao_cnefe_terminar)
        self._respostaHttp.connect(self._ao_responder_http)
        self._timer_gravar_indice = QTimer(self)
        self._timer_gravar_indice.setSingleShot(True)
        self._timer_gravar_indice.setInterval(_ATRASO_GRAVACAO_INDICE_MS)
        self._timer_gravar_indice.timeout.connect(indiceRuas.gravar_pendente)

        rede.registrarEvento(_EVENTO_ENDERECO_USADO, self._ao_receber_endereco_usado)
        rede.registrarDominioSincronizado(
            historicoEnderecos.DOMINIO,
            historicoEnderecos.resumo,
            historicoEnderecos.obter,
            historicoEnderecos.aplicar_remoto,
        )
        rede.registrarEvento(_EVENTO_INDICE_RUAS, self._ao_receber_indice_remoto)
        rede.registrarDominioSincronizado(
            indiceRuas.DOMINIO,
            indiceRuas.resumo,
            indiceRuas.obter,
            lambda _bloco, payload: self._ao_receber_indice_remoto(payload),
        )
        # Uma localização nova pede um índice novo — e decide quem o monta
        # (ver _responsavel_pelo_indice).
        rede.localizacaoServidorMudou.connect(self.garantirIndice)

    # ---------- Busca (Entrega.qml) ----------

    @pyqtSlot(str, str, result="QVariantList")
    @protegido([])
    def sugerirEnderecosLocais(self, termo, bairro):
        """Ruas salvas nesta máquina (histórico e índice) que casam com
        `termo` — síncrono, chamado pela Entrega.qml a cada tecla, desde a
        primeira letra. Custa frações de milissegundo: a busca no índice é
        binária e o histórico fica em memória. Só quando isto volta vazio a
        tela espera a pausa na digitação para ir ao Photon (buscarEnderecos)."""
        return self._enderecos_locais((termo or "").strip(), bairro)

    @pyqtSlot(str, result="QVariantList")
    @protegido([])
    def sugerirBairrosLocais(self, termo):
        """Mesmo papel de sugerirEnderecosLocais, para o campo Bairro."""
        return self._bairros_locais((termo or "").strip())

    def _enderecos_locais(self, termo, bairro):
        if not termo:
            return []
        historico = historicoEnderecos.buscar_ruas(termo)
        # Com o índice ainda sendo lido na thread da abertura, fica só o
        # histórico: carregar ~550 KB aqui travaria justamente uma tecla.
        indice = indiceRuas.buscar_ruas(termo) if indiceRuas.carregado() else []
        return ordenar_enderecos(bairro, historico, indice, [])

    def _bairros_locais(self, termo):
        if not termo:
            return []
        indice = indiceRuas.buscar_bairros(termo) if indiceRuas.carregado() else []
        return ordenar_bairros(historicoEnderecos.buscar_bairros(termo), indice)

    @pyqtSlot(str, str)
    @protegido(None)
    def buscarEnderecos(self, termo, bairro):
        """Caminho com espera (debounce da Entrega.qml) para o que não está
        salvo: confere o local de novo — o texto pode ter mudado desde a
        última tecla — e só então consulta o Photon."""
        termo = (termo or "").strip()
        if len(termo) < _MINIMO_CARACTERES:
            self.enderecosSugeridos.emit(termo, [])
            return

        locais = self._enderecos_locais(termo, bairro)
        if locais:
            # Achou no que está guardado: o Photon nem é consultado.
            self.enderecosSugeridos.emit(termo, locais)
            return

        def responder(ruas_photon):
            self._aprender_do_photon(ruas_photon)
            self.enderecosSugeridos.emit(termo, ordenar_enderecos(bairro, [], [], ruas_photon))

        self._consultar_photon("endereco", termo, ("street",), _ruas_do_photon, responder)

    @pyqtSlot(str)
    @protegido(None)
    def buscarBairros(self, termo):
        """Do Photon (só sem nada local) vêm as camadas district e locality
        juntas: em Taubaté a primeira volta vazia e é a segunda que conhece os
        "Jardim ..."."""
        termo = (termo or "").strip()
        if len(termo) < _MINIMO_CARACTERES:
            self.bairrosSugeridos.emit(termo, [])
            return

        locais = self._bairros_locais(termo)
        if locais:
            self.bairrosSugeridos.emit(termo, locais)
            return

        def responder(bairros_photon):
            self.bairrosSugeridos.emit(termo, ordenar_bairros(bairros_photon))

        self._consultar_photon("bairro", termo, ("district", "locality"), _bairros_do_photon, responder)

    @protegido(None)
    def registrarUso(self, endereco, bairro, numero="", cep=""):
        """Conta o endereço de uma comanda lançada/impressa no histórico e
        avisa a malha. Chamado pelo EntregaController depois de a comanda ser
        salva. O número e o CEP ensinam o bairro daquela casa (ver
        historicoEnderecos.aprendido)."""
        # Grava a grafia do índice quando é a mesma rua: "RUA SAO VICENTE DE
        # PAULA" entra como "Rua São Vicente de Paula" (ver enderecoFormatado).
        endereco, bairro = formatar_endereco(endereco, bairro)
        resultado = historicoEnderecos.registrar(endereco, bairro, numero, cep)
        if resultado is None:
            return
        chave, registro = resultado
        rede.publicarEvento(_EVENTO_ENDERECO_USADO, dict(registro, chave=chave))

    def _ao_receber_endereco_usado(self, payload, _socket=None):
        payload = payload or {}
        historicoEnderecos.aplicar_remoto(payload.get("chave", ""), payload)

    def _aprender_do_photon(self, ruas_photon):
        """Ruas que o Photon achou dentro da cidade do índice e que faltavam
        nele — entram no índice (e na malha), e a próxima busca delas já não
        sai da máquina."""
        cidade = normalizar(indiceRuas.base().get("cidade"))
        if not cidade:
            return
        novas = {
            p["nome"]: {
                "nome": p["nome"],
                "correios": False,
                "bairros": [{"nome": b, "origem": indiceRuas.ORIGEM_PHOTON, "distancia": 0} for b in p["bairros"]],
            }
            for p in ruas_photon
            if normalizar(p.get("cidade")) == cidade
        }
        self._publicar_ruas(indiceRuas.adicionar(novas))

    def _consultar_photon(self, campo, termo, camadas, extrair, responder):
        localizacao = rede.localizacaoServidor
        bbox = localizacaoServidor.bbox(localizacao)
        chave_cache = (camadas, normalizar(termo), bbox)

        guardado = self._do_cache(chave_cache)
        if guardado is not None:
            responder(guardado)
            return

        geracao = self._geracao.get(campo, 0) + 1
        self._geracao[campo] = geracao

        # Lista de pares, e não dict: "layer" se repete.
        parametros = [("q", termo)] + [("layer", camada) for camada in camadas]
        if bbox:
            parametros += [
                ("bbox", bbox),
                ("lat", f"{localizacao['lat']:.6f}"),
                ("lon", f"{localizacao['lon']:.6f}"),
            ]
        parametros.append(("limit", str(_LIMITE_PHOTON)))
        # "default" devolve o nome local ("Rua ..."), não "... Street".
        parametros.append(("lang", "default"))

        def concluir(dados, erro):
            if self._geracao.get(campo) != geracao:
                # Já há uma busca mais nova para este campo.
                return

            features = _features_de(dados)
            if features is None:
                if self._photon_respondendo:
                    print(f"[sugestoesEndereco] Photon indisponível ({erro or 'resposta inválida'}).")
                self._photon_respondendo = False
                responder([])
                return

            if not self._photon_respondendo:
                print("[sugestoesEndereco] Photon voltou a responder.")
            self._photon_respondendo = True
            resultado = extrair(features)
            self._guardar(chave_cache, resultado)
            responder(resultado)

        self._pedir_json(_URL_PHOTON, parametros, concluir)

    def _pedir_json(self, url, parametros, ao_terminar):
        """Faz a requisição numa thread do pool e entrega `ao_terminar(dados,
        erro)` na thread da interface: `dados` é o JSON já decodificado, ou None
        com `erro` dizendo o motivo. `ao_terminar` sempre é chamado — é o que
        garante que ninguém fica esperando para sempre (o "Buscando..." da
        tela Rede)."""
        def trabalho():
            try:
                dados, erro = requisicaoHttp.obter_json(url, parametros, timeout=_TIMEOUT_S), None
            except Exception as falha:  # qualquer falha vira resposta vazia, nunca thread morta calada
                dados, erro = None, falha
            try:
                self._respostaHttp.emit(ao_terminar, dados, erro)
            except RuntimeError:
                pass  # sistema fechando: o serviço já foi destruído

        try:
            self._http.submit(trabalho)
        except RuntimeError:
            # Pool já encerrado (fechamento do sistema): responde vazio na hora.
            ao_terminar(None, requisicaoHttp.ErroRequisicao("sistema fechando"))

    @protegido(None)
    def _ao_responder_http(self, ao_terminar, dados, erro):
        ao_terminar(dados, erro)

    def _do_cache(self, chave):
        entrada = self._cache.get(chave)
        if entrada is None:
            return None
        instante, valor = entrada
        if time.monotonic() - instante > _TTL_CACHE_S:
            del self._cache[chave]
            return None
        return valor

    def _guardar(self, chave, valor):
        self._cache[chave] = (time.monotonic(), valor)
        if len(self._cache) > _MAXIMO_CACHE:
            # dict preserva a ordem de inserção: o primeiro é o mais antigo.
            del self._cache[next(iter(self._cache))]

    # ---------- Índice de ruas (montagem em segundo plano) ----------

    @pyqtSlot()
    @protegido(None)
    def aquecerIndice(self):
        """Lê o índice do disco numa thread na abertura do sistema: ~550 KB
        de JSON mais a lista ordenada da busca pesariam na primeira tecla
        digitada na Entrega. A leitura pronta volta por _indiceLido."""
        threading.Thread(target=self._ler_indice, name="indice-ruas-leitura", daemon=True).start()

    def _ler_indice(self):
        try:
            self._indiceLido.emit(indiceRuas.ler_arquivo())
        except Exception as erro:  # sem leitura prévia, a primeira busca lê na hora
            print(f"[sugestoesEndereco] Falha lendo o índice de ruas: {erro}")
            self._indiceLido.emit(None)

    def _ao_indice_lido(self, leitura):
        if leitura is not None:
            indiceRuas.instalar_leitura(leitura)
        self._atualizar_status()
        self.garantirIndice()

    def _agendar_gravacao_indice(self):
        if not self._timer_gravar_indice.isActive():
            self._timer_gravar_indice.start()

    @pyqtProperty(str, notify=statusIndiceMudou)
    def statusIndice(self):
        """Uma linha para a tela Rede: quantas ruas há e o que está em curso."""
        return self._status_indice

    def _atualizar_status(self):
        base = indiceRuas.base()
        if not base.get("cidade"):
            texto = self._trabalho_indice or "Índice de ruas ainda não montado — as sugestões vêm do Photon."
        else:
            total, oficiais, consultadas = indiceRuas.contagens()
            texto = f"{total} ruas de {base['cidade']} guardadas, {oficiais} com o bairro dos Correios"
            texto += f" ({consultadas} de {total} consultadas)." if consultadas < total else "."
            if self._trabalho_indice:
                texto += f" {self._trabalho_indice}"
            texto += " " + self._status_cnefe()
        if texto != self._status_indice:
            self._status_indice = texto
            self.statusIndiceMudou.emit()

    def _status_cnefe(self):
        if self._trabalho_cnefe:
            return self._trabalho_cnefe
        dados = cnefe.meta()
        if dados:
            total = f"{int(dados.get('enderecos') or 0):,}".replace(",", ".")
            return f"Cadastro do IBGE: {total} endereços de {dados.get('cidade')}."
        return "Cadastro do IBGE ainda não baixado."

    def _garantir_cnefe(self):
        """Baixa o cadastro do IBGE da cidade do índice, se esta máquina ainda
        não tem o dela. Cada máquina baixa o seu (ver services/cnefe.py)."""
        base = indiceRuas.base() if indiceRuas.carregado() else {}
        cidade, uf = base.get("cidade") or "", str(base.get("uf") or "").upper()
        if not cidade or not uf or self._cnefe_falhou_para == (cidade, uf):
            return

        def terminar(erro):
            try:
                self._cnefeTerminou.emit(erro)
            except RuntimeError:
                pass  # sistema fechando: o serviço já foi destruído

        if cnefe.garantir(cidade, uf, self._cancelar_cnefe, terminar):
            self._cnefe_para = (cidade, uf)
            self._trabalho_cnefe = "Baixando o cadastro de endereços do IBGE..."
            self._atualizar_status()

    def _ao_cnefe_terminar(self, erro):
        if erro:
            self._cnefe_falhou_para = self._cnefe_para
        self._trabalho_cnefe = f"Cadastro do IBGE não baixado: {erro}." if erro else ""
        self._atualizar_status()

    @pyqtSlot()
    @protegido(None)
    def garantirIndice(self):
        """Monta (ou completa) o índice de ruas numa thread, quando esta
        máquina é quem define a localização: baixa as ruas se não há índice,
        se ele é de outra localização ou passou de 30 dias; senão só retoma a
        consulta dos bairros nos Correios de onde parou. As outras máquinas
        recebem tudo pela malha."""
        self._garantir_indice(sem_hospedeira=False)
        self._garantir_cnefe()

    def _garantir_indice(self, sem_hospedeira):
        if self._montando or not indiceRuas.carregado():
            # Sem índice em memória, a leitura ainda está na thread (ver
            # aquecerIndice) — e ela chama isto de novo quando terminar.
            return
        localizacao = rede.localizacaoServidor
        if not localizacao:
            return
        if not sem_hospedeira and not self._responsavel_pelo_indice(localizacao):
            # Quem monta é a máquina que definiu a localização. Mas se ela
            # estiver desligada, ninguém montaria nunca: continuando sem índice
            # depois da espera, esta máquina monta o seu — e a fusão por união
            # junta os dois quando ela aparecer.
            if not indiceRuas.base().get("cidade") and not self._espera_hospedeira.isActive():
                self._espera_hospedeira.start()
            return
        if sem_hospedeira and indiceRuas.base().get("cidade"):
            # Chegou pela malha durante a espera.
            return

        base = indiceRuas.base()
        idade = time.time() - relogio.instante_do_id(base.get("idEvento", ""))
        baixar = (
            not base.get("cidade")
            or base.get("localizacaoId") != localizacao["idEvento"]
            or idade > _IDADE_MAXIMA_INDICE_S
        )
        pendentes = [] if baixar else indiceRuas.pendentes_correios()
        if not baixar and (not pendentes or not base.get("uf")):
            return

        # Tudo o que a thread precisa sai daqui, pronto: ela não lê o índice
        # (que a malha pode estar reescrevendo) nem gera id no relógio lógico.
        montagem = {
            "lat": localizacao["lat"],
            "lon": localizacao["lon"],
            "baixar": baixar,
            "base": dict(base, idEvento=relogio.novo_id(), localizacaoId=localizacao["idEvento"]) if baixar else base,
            "pendentes": pendentes,
            "jaConsultadas": indiceRuas.chaves_consultadas(),
        }
        self._montando = True
        self._cancelar_montagem.clear()
        self._trabalho_indice = "Baixando as ruas da cidade..." if baixar else "Consultando bairros nos Correios em segundo plano..."
        self._atualizar_status()
        threading.Thread(target=self._montar, args=(montagem,), name="indice-ruas", daemon=True).start()

    def _montar(self, montagem):
        """Corpo da thread. Só faz HTTP e emite sinais — nunca grava nada."""
        try:
            base, pendentes = montagem["base"], montagem["pendentes"]
            if montagem["baixar"]:
                cidade, ruas = montadorIndiceRuas.baixar_cidade(montagem["lat"], montagem["lon"], self._cancelar_montagem)
                base = dict(base, **cidade)
                self._indiceBaixado.emit(base, ruas)
                pendentes = sorted((k, r["nome"]) for k, r in ruas.items() if k not in montagem["jaConsultadas"])
            if base.get("uf") and pendentes:
                self._consultar_correios(base["uf"], base["cidade"], pendentes)
            self._montagemTerminou.emit("")
        except montadorIndiceRuas.ErroMontagem as erro:
            self._montagemTerminou.emit("" if str(erro) == "cancelado" else str(erro))
        except Exception as erro:  # nunca deixa a thread morrer calada
            print(f"[sugestoesEndereco] Falha inesperada montando o índice: {erro}\n{traceback.format_exc()}")
            self._montagemTerminou.emit(str(erro))

    def _consultar_correios(self, uf, cidade, pendentes):
        falhas = 0
        for chave, nome in pendentes:
            if self._cancelar_montagem.wait(_INTERVALO_VIACEP_S):
                return
            try:
                bairros = montadorIndiceRuas.consultar_correios(uf, cidade, nome)
            except montadorIndiceRuas.ErroMontagem as erro:
                falhas += 1
                if falhas >= _FALHAS_SEGUIDAS_VIACEP:
                    raise montadorIndiceRuas.ErroMontagem(
                        f"Correios fora do ar ({erro}); a consulta continua na próxima abertura do sistema"
                    ) from erro
                # Espera crescente: 1, 2, 4, 8 minutos.
                if self._cancelar_montagem.wait(30 * 2 ** falhas):
                    return
                continue
            falhas = 0
            self._correiosConsultado.emit(chave, bairros)

    def _ao_indice_baixado(self, base, ruas):
        total = indiceRuas.aplicar_montagem(base, ruas, preparadas=True)
        self._agendar_gravacao_indice()
        print(f"[sugestoesEndereco] Índice de ruas montado: {total} ruas de {base['cidade']}/{base['uf']}.")
        self._trabalho_indice = "Consultando bairros nos Correios em segundo plano..." if base.get("uf") else ""
        self._atualizar_status()
        self._garantir_cnefe()

    def _ao_correios_consultado(self, chave, bairros):
        self._correios_a_gravar[chave] = bairros
        if not self._timer_gravar_correios.isActive():
            self._timer_gravar_correios.start()

    def _gravar_correios(self):
        if not self._correios_a_gravar:
            return
        lote, self._correios_a_gravar = self._correios_a_gravar, {}
        self._publicar_ruas(indiceRuas.marcar_correios(lote))
        self._atualizar_status()

    def _publicar_ruas(self, mudadas):
        """Publica na malha as ruas que mudaram aqui — o caminho rápido; a
        reconciliação por blocos cobre quem estava desconectado."""
        if not mudadas:
            return
        rede.publicarEvento(_EVENTO_INDICE_RUAS, {"base": indiceRuas.base(), "ruas": mudadas})
        self._agendar_gravacao_indice()
        self._atualizar_status()

    def _ao_montagem_terminar(self, erro):
        self._gravar_correios()
        self._montando = False
        self._trabalho_indice = f"Última tentativa falhou: {erro}." if erro else ""
        if erro:
            print(f"[sugestoesEndereco] Montagem do índice de ruas interrompida: {erro}")
        self._atualizar_status()

    def _ao_receber_indice_remoto(self, payload, _socket=None):
        if indiceRuas.aplicar_remoto(payload):
            self._agendar_gravacao_indice()
            self._atualizar_status()
            self._garantir_cnefe()

    @pyqtSlot()
    def encerrar(self):
        """Fechamento do sistema: para a thread e grava o que o ViaCEP já
        respondeu, para a próxima abertura não repetir essas consultas."""
        self._cancelar_montagem.set()
        self._cancelar_cnefe.set()
        self._http.shutdown(wait=False, cancel_futures=True)
        self._gravar_correios()
        indiceRuas.gravar_pendente()

    # ---------- Localização da pizzaria (Rede.qml) ----------

    @staticmethod
    def _responsavel_pelo_indice(localizacao):
        """A máquina que definiu a localização monta o índice das ruas dela: o
        idEvento da localização carrega o nome de quem a gravou (ver
        services/rede/relogio.py). Uma máquina só, para o Overpass e o ViaCEP
        não serem consultados por todas ao mesmo tempo."""
        return relogio.maquina_do_id(localizacao.get("idEvento", "")) == rede.nomeLocal

    @pyqtSlot()
    @protegido(None)
    def garantirLocalizacao(self):
        """Detecta a localização pela conexão de internet quando ainda não há
        nenhuma conhecida. Nunca sobrescreve uma existente — nem a digitada na
        tela Rede, nem a aprendida de um peer."""
        if rede.localizacaoServidor or self._detectando_localizacao:
            return

        self._detectando_localizacao = True

        def concluir(dados, erro):
            self._detectando_localizacao = False
            dados = dados if isinstance(dados, dict) else {}
            try:
                lat, lon = (float(parte) for parte in str(dados.get("loc", "")).split(","))
            except ValueError:
                print(f"[sugestoesEndereco] Não foi possível detectar a localização pela internet ({erro or 'resposta sem coordenadas'}).")
                return
            # Alguém pode ter definido enquanto a detecção estava no ar.
            if rede.localizacaoServidor:
                return
            cidade = str(dados.get("city") or "")
            descricao = ", ".join(p for p in (cidade, str(dados.get("region") or "")) if p)
            if rede.definir_localizacao_servidor({
                "descricao": descricao,
                "cidade": cidade,
                "lat": lat,
                "lon": lon,
                "origem": "ip",
            }):
                print(f"[sugestoesEndereco] Localização detectada pela internet: {descricao} ({lat}, {lon}).")

        self._pedir_json(_URL_GEOLOCALIZACAO_IP, None, concluir)

    @pyqtSlot(str)
    @protegido(None)
    def definirLocalizacaoPorEndereco(self, texto):
        """Geocodifica o endereço digitado na tela Rede e o adota como
        localização da pizzaria, na malha inteira. Responde por
        localizacaoDefinida."""
        texto = (texto or "").strip()
        if not texto:
            self.localizacaoDefinida.emit(False, "Digite o endereço da pizzaria.")
            return

        def concluir(dados, erro):
            features = _features_de(dados)
            if features is None:
                print(f"[sugestoesEndereco] Photon indisponível ao definir a localização ({erro or 'resposta inválida'}).")
                self.localizacaoDefinida.emit(False, "Sem resposta do serviço de mapas — confira a internet e tente de novo.")
                return
            if not features:
                self.localizacaoDefinida.emit(False, "Endereço não encontrado — tente incluir a cidade e o estado.")
                return

            props, coordenadas = features[0]
            try:
                lon, lat = float(coordenadas[0]), float(coordenadas[1])
            except (IndexError, TypeError, ValueError):
                self.localizacaoDefinida.emit(False, "O serviço de mapas devolveu um lugar sem coordenadas.")
                return

            rua = str(props.get("street") or props.get("name") or "")
            if rua and props.get("housenumber"):
                rua = f"{rua}, {props['housenumber']}"
            partes = (rua, props.get("district"), props.get("city"), props.get("state"))
            descricao = ", ".join(str(p) for p in partes if p)

            ok = rede.definir_localizacao_servidor({
                "endereco": texto,
                "descricao": descricao,
                "cidade": str(props.get("city") or ""),
                "lat": lat,
                "lon": lon,
                "origem": "manual",
            })
            self.localizacaoDefinida.emit(ok, descricao if ok else "O lugar encontrado tem coordenadas inválidas.")

        self._pedir_json(_URL_PHOTON, [("q", texto), ("limit", "1"), ("lang", "default")], concluir)


# Singleton de módulo — mesmo padrão dos demais services do projeto.
sugestoes_endereco = SugestoesEnderecoService()
