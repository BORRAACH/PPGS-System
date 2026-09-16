"""Validação do endereço de entrega (qml/components/DeliveryAddressValidator.qml).

As sugestões locais saem na hora (sugerirLocais, sem internet), nesta ordem:

1. a casa já entregue: rua e número que a equipe já lançou, com o bairro e o
   CEP daquela comanda (services/rede/historicoEnderecos.aprendido) — uma
   correção de bairro feita pelo atendente vale dali em diante;
2. a casa do cadastro do IBGE (services/cnefe.py): o bairro, o CEP e o ponto
   do número digitado;
3. o histórico e o índice de ruas, como antes; sem número, os bairros do
   cadastro do IBGE entram no lugar dos palpites do OpenStreetMap.

Uma rua resolvida pelo número (1 ou 2) não aparece de novo com outro bairro.

O resto vai para uma thread: Photon para as sugestões, e a cadeia cadastro do
IBGE → Photon → Nominatim → ViaCEP → zona de entrega para validar. A resposta volta à
thread da interface por sinal, com um número de geração: a resposta de um
pedido já substituído por outro é descartada.

O grafo de ruas da zona de entrega é o mesmo do cálculo de rotas
(services/grafoRuas.py): lido do cache ou baixado em segundo plano. Enquanto
não fica pronto, a validação sai com "zona ainda não verificada" em vez de
esperar. Os algoritmos estão em services/validacaoEndereco.py."""

import threading
from concurrent.futures import ThreadPoolExecutor

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services import cnefe, grafoRuas, validacaoEndereco
from services.rede import historicoEnderecos, indiceRuas, rede
from services.enderecoFormatado import formatar_endereco, normalizar_endereco
from services.sugestoesEndereco import sugestoes_endereco

# Bairros do cadastro do IBGE por rua, quando o número ainda não foi digitado.
_BAIRROS_CNEFE_POR_RUA = 3
# Ruas do cadastro do IBGE consultadas por busca.
_RUAS_CNEFE = 5


class ValidacaoEnderecoController(QObject):
    # (geração, sugestões no formato do ListaSugestoes, aviso)
    sugestoesProntas = pyqtSignal(int, "QVariantList", str)
    # (geração, resultado de validacaoEndereco.validar)
    validacaoPronta = pyqtSignal(int, "QVariantMap")

    # Das threads para a thread da interface.
    _sugestoesCalculadas = pyqtSignal(int, object, str)
    _validacaoCalculada = pyqtSignal(int, object)

    def __init__(self):
        super().__init__()
        self._pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix="validacao-endereco")
        self._geracao_sugestoes = 0
        self._geracao_validacao = 0
        self._grafo = None
        self._carregando_grafo = False
        self._trava_grafo = threading.Lock()
        self._cancelado = threading.Event()
        self._sugestoesCalculadas.connect(self._ao_sugestoes_calculadas)
        self._validacaoCalculada.connect(self._ao_validacao_calculada)

    def _localizacao(self):
        """A localização do estabelecimento (tela Rede), com a UF do índice de
        ruas quando ele já está em memória."""
        localizacao = dict(rede.localizacaoServidor or {})
        if indiceRuas.carregado() and not localizacao.get("uf"):
            localizacao["uf"] = str(indiceRuas.base().get("uf") or "")
        return localizacao

    @staticmethod
    def _cnefe_ativo():
        """O cadastro do IBGE desta máquina é da cidade do índice de ruas. Com
        a pizzaria mudando de cidade, o banco antigo fica de fora até o novo
        ficar pronto."""
        if not indiceRuas.carregado():
            return False
        base = indiceRuas.base()
        return cnefe.disponivel_para(base.get("cidade"), base.get("uf"))

    @classmethod
    def _locais(cls, info):
        """As sugestões desta máquina para a rua digitada (ver o topo), com a
        grafia do índice. Aqui, na thread da interface: o índice e o histórico
        só são lidos nela (ver enderecoFormatado.formatar_endereco), e a thread
        da busca recebe a lista pronta.

        Cada item: {"nome", "bairro", "fonte"} e, quando se sabe, "cep",
        "latitude", "longitude", "numeroNoMapa" e "condominio"."""
        if not info["rua"]:
            return []
        numero = info["numero"] if info["numero"] != "S/N" else ""
        usar_cnefe = cls._cnefe_ativo()
        locais = sugestoes_endereco._enderecos_locais(info["rua"], info["bairro"])
        ruas_cnefe = cnefe.buscar_ruas(info["rua"], _RUAS_CNEFE) if usar_cnefe else []

        # As ruas candidatas, na ordem em que aparecem: histórico e índice
        # primeiro, depois as que só o cadastro do IBGE conhece.
        ruas = []
        vistas = set()
        for nome in [l["nome"] for l in locais] + [r["nome"] for r in ruas_cnefe]:
            rua_formatada, _ = formatar_endereco(nome, "")
            chave = normalizar_endereco(rua_formatada)
            if chave and chave not in vistas:
                vistas.add(chave)
                ruas.append(rua_formatada)

        resolvidas = []
        chaves_resolvidas = set()
        if numero:
            for rua in ruas:
                achado = cls._casa_conhecida(rua, numero, usar_cnefe)
                if achado:
                    resolvidas.append(achado)
                    chaves_resolvidas.add(normalizar_endereco(rua))
            # A casa já entregue antes da do cadastro.
            resolvidas.sort(key=lambda s: s["fonte"] != "aprendido")

        conhecidas_cnefe = {normalizar_endereco(formatar_endereco(r["nome"], "")[0]) for r in ruas_cnefe}
        demais = []
        for local in locais:
            rua, bairro = formatar_endereco(local.get("nome"), local.get("bairro"))
            chave = normalizar_endereco(rua)
            if chave in chaves_resolvidas:
                continue
            # O bairro que o OSM supôs para a rua perde para os do cadastro.
            if local.get("fonte") in ("indice", "photon") and chave in conhecidas_cnefe:
                continue
            demais.append({"nome": rua, "bairro": bairro, "fonte": local.get("fonte") or "local"})
        do_cnefe = []
        for rua_cnefe in ruas_cnefe:
            rua, _ = formatar_endereco(rua_cnefe["nome"], "")
            if normalizar_endereco(rua) in chaves_resolvidas:
                continue
            for trecho in cnefe.bairros_da_rua(rua_cnefe["id"])[:_BAIRROS_CNEFE_POR_RUA]:
                _, bairro = formatar_endereco(rua, trecho["bairro"])
                do_cnefe.append({"nome": rua, "bairro": bairro, "fonte": "cnefe"})
        # O histórico fala a língua da equipe; o cadastro vem antes do índice.
        historico = [d for d in demais if d["fonte"] == "historico"]
        indice = [d for d in demais if d["fonte"] != "historico"]
        return resolvidas + historico + do_cnefe + indice

    @staticmethod
    def _casa_conhecida(rua, numero, usar_cnefe):
        """A sugestão da casa `numero` da `rua`: a da última comanda para ela,
        senão a do cadastro do IBGE (o número exato ou um vizinho); None se
        nenhuma das duas conhece."""
        aprendido = historicoEnderecos.aprendido(rua, numero)
        casa = cnefe.endereco(rua, numero) if usar_cnefe else None
        if not aprendido and not casa:
            return None
        sugestao = {"nome": rua, "fonte": "cnefe"}
        if casa:
            # O ponto vem do cadastro mesmo quando o bairro é o aprendido.
            sugestao.update({
                "bairro": formatar_endereco(rua, casa["bairro"])[1],
                "cep": casa["cep"],
                "latitude": casa["latitude"],
                "longitude": casa["longitude"],
                "numeroNoMapa": casa["exato"],
                "condominio": casa["condominio"],
            })
        if aprendido:
            rua_formatada, bairro = formatar_endereco(aprendido["rua"] or rua, aprendido["bairro"])
            sugestao.update({"nome": rua_formatada, "bairro": bairro, "fonte": "aprendido"})
            if aprendido["cep"]:
                sugestao["cep"] = aprendido["cep"]
        return sugestao

    def _enviar(self, trabalho):
        try:
            self._pool.submit(trabalho)
        except RuntimeError:
            pass  # sistema fechando

    @staticmethod
    def _emitir(sinal, *argumentos):
        try:
            sinal.emit(*argumentos)
        except RuntimeError:
            pass  # sistema fechando: o controller já foi destruído

    # ---------- Sugestões ----------

    @pyqtSlot(str, result="QVariantMap")
    @protegido({})
    def interpretar(self, texto):
        """{rua, numero, bairro, pistaCondominio} do texto livre: o Enter sem
        escolher sugestão valida o que foi digitado."""
        return validacaoEndereco.interpretar(texto)

    @pyqtSlot(str, result="QVariantList")
    @protegido([])
    def sugerirLocais(self, texto):
        """Síncrono, a cada tecla: histórico e índice de ruas desta máquina."""
        locais = self._locais(validacaoEndereco.interpretar(texto))
        return validacaoEndereco.sugestoes_locais(texto, self._localizacao(), locais) if locais else []

    @pyqtSlot(str, result=int)
    @protegido(0)
    def sugerir(self, texto):
        """Locais + Photon, numa thread. Responde por sugestoesProntas."""
        self._geracao_sugestoes += 1
        geracao = self._geracao_sugestoes
        locais = self._locais(validacaoEndereco.interpretar(texto))
        localizacao = self._localizacao()

        def trabalho():
            try:
                lista, aviso = validacaoEndereco.sugestoes(texto, localizacao, locais)
            except Exception as erro:  # a thread não pode morrer calada
                print(f"[ValidacaoEndereco] falha nas sugestões: {erro!r}")
                lista, aviso = validacaoEndereco.sugestoes_locais(texto, localizacao, locais), "Busca de endereços indisponível."
            self._emitir(self._sugestoesCalculadas, geracao, lista, aviso)

        self._enviar(trabalho)
        return geracao

    def _ao_sugestoes_calculadas(self, geracao, lista, aviso):
        self.sugestoesProntas.emit(geracao, lista, aviso)

    # ---------- Validação ----------

    @pyqtSlot("QVariantMap", str, result=int)
    @protegido(0)
    def validar(self, escolha, numero):
        """Valida a sugestão escolhida com o número do campo. Responde por
        validacaoPronta com a geração devolvida aqui."""
        return self._validar(dict(escolha or {}), numero, "")

    @pyqtSlot("QVariantMap", str, str, result=int)
    @protegido(0)
    def validarComCep(self, escolha, numero, cep):
        """Mesma validação, partindo do CEP digitado pelo atendente."""
        return self._validar(dict(escolha or {}), numero, cep)

    def _validar(self, escolha, numero, cep):
        self._geracao_validacao += 1
        geracao = self._geracao_validacao
        if cep:
            # Digitado pelo atendente: corrigido, ganha aviso (ver
            # validacaoEndereco.validar).
            escolha["cep"] = cep
            escolha["cepDigitado"] = True
        localizacao = self._localizacao()
        escolha["usarCnefe"] = self._cnefe_ativo()
        # A última comanda para esta casa decide o bairro e o CEP — menos
        # quando o atendente acabou de escrever o bairro à mão.
        aprendido = historicoEnderecos.aprendido(escolha.get("rua"), numero)
        if aprendido and not escolha.get("bairroManual"):
            _, bairro = formatar_endereco(escolha.get("rua"), aprendido["bairro"])
            escolha["bairroAprendido"] = bairro
            if aprendido["cep"] and not cep:
                escolha["cep"] = aprendido["cep"]
                escolha["cepAprendido"] = True
        # Sem zona (painel de rotas), o grafo de ruas nem é carregado.
        if not escolha.get("semZona"):
            self.prepararZona()

        def trabalho():
            try:
                resultado = validacaoEndereco.validar(escolha, numero, localizacao, lambda: self._grafo)
            except Exception as erro:
                print(f"[ValidacaoEndereco] falha na validação: {erro!r}")
                resultado = validacaoEndereco.resultado_de_falha(escolha, numero, erro)
            self._emitir(self._validacaoCalculada, geracao, resultado)

        self._enviar(trabalho)
        return geracao

    # As duas repassam TODA resposta: quem descarta a velha é cada campo, pela
    # geração que guardou (DeliveryAddressValidator). Filtrar aqui pela última
    # geração derrubava a resposta de um campo quando outro validava junto — no
    # painel de rotas, a origem ficava "verificando" para sempre.
    def _ao_validacao_calculada(self, geracao, resultado):
        self.validacaoPronta.emit(geracao, resultado)

    # ---------- Zona de entrega ----------

    @pyqtSlot()
    @protegido(None)
    def prepararZona(self):
        """Carrega o grafo de ruas em segundo plano (cache ou download), uma
        vez só."""
        localizacao = self._localizacao()
        if self._grafo is not None or localizacao.get("lat") is None:
            return
        with self._trava_grafo:
            if self._carregando_grafo:
                return
            self._carregando_grafo = True

        lat, lon = float(localizacao["lat"]), float(localizacao["lon"])

        def carregar():
            try:
                grafo = grafoRuas.ler_cache(lat, lon)
                if grafo is None and not self._cancelado.is_set():
                    dados = grafoRuas.montar_grafo(grafoRuas.baixar_elementos(lat, lon, self._cancelado), (lat, lon))
                    try:
                        grafoRuas.salvar_cache(dados)
                    except Exception as erro:
                        print(f"[ValidacaoEndereco] não foi possível gravar o cache do grafo: {erro!r}")
                    grafo = grafoRuas.Grafo(dados)
                self._grafo = grafo
            except Exception as erro:
                print(f"[ValidacaoEndereco] mapa de ruas indisponível para a zona de entrega: {erro!r}")
            finally:
                with self._trava_grafo:
                    self._carregando_grafo = False

        threading.Thread(target=carregar, name="zona-entrega", daemon=True).start()

    @pyqtSlot()
    def encerrar(self):
        self._cancelado.set()
        self._pool.shutdown(wait=False, cancel_futures=True)
