"""Configuração de como o "Lucro" da tela de Fechamento é calculado, a
partir de três termos: Contagem (Cartão+Dinheiro+Pix contados manualmente,
ver services/rede/contagemCaixa.py), Extras (pagamento de diária a
funcionários, ver services/rede/extrasCaixa.py) e Bruto (total de vendas do
dia, ver controllers/fechamentoController.py). Cada termo tem um sinal —
"somar", "subtrair" ou "nao_incluir" — e o lucro é a soma de cada termo já
com esse sinal aplicado (ver PopupFormulaLucro.qml, que edita isto).

Item único (não há "vários registros" aqui, ao contrário de
extrasCaixa/contagemCaixa) — mesmo desenho de services/comandaEstiloService.py
para o estilo de impressão: sincronizado entre as máquinas da malha com
idEvento (services/rede/relogio.py) resolvendo o conflito de duas máquinas
mudando a fórmula quase ao mesmo tempo."""

import json
import os

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido

TERMOS = ["contagem", "extras", "bruto"]
SINAIS_VALIDOS = ["somar", "subtrair", "nao_incluir"]


def _padrao():
    return {
        "contagem": "somar",
        "extras": "subtrair",
        "bruto": "subtrair",
        "idEvento": "",
    }


def _raiz_projeto():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _caminho_arquivo():
    return os.path.join(_raiz_projeto(), "Config", "formula_lucro.json")


def _carregar():
    caminho = _caminho_arquivo()
    config = _padrao()
    if not os.path.isfile(caminho):
        return config

    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            dados = json.load(arquivo)
    except (OSError, json.JSONDecodeError) as erro:
        print(f"[formulaLucroService] Falha ao ler {caminho}: {erro} — usando padrões.")
        return config

    for termo in TERMOS:
        if dados.get(termo) in SINAIS_VALIDOS:
            config[termo] = dados[termo]
    if isinstance(dados.get("idEvento"), str):
        config["idEvento"] = dados["idEvento"]

    return config


def _salvar():
    caminho = _caminho_arquivo()
    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
        with open(caminho, "w", encoding="utf-8") as arquivo:
            json.dump(_config, arquivo, indent=2, ensure_ascii=False)
    except OSError as erro:
        print(f"[formulaLucroService] Falha ao gravar {caminho}: {erro}")


# Estado em memória, igual a comandaEstiloService._config — carregado uma
# vez na primeira importação; FormulaLucroController muta este mesmo dict.
_config = _carregar()


def obter_configuracao():
    return _config


def _multiplicador(sinal):
    if sinal == "somar":
        return 1
    if sinal == "subtrair":
        return -1
    return 0


def calcular_lucro(bruto, contagem, extras):
    """Mesmo cálculo que Fechamento.qml faz (telaFechamento.lucro) — usado
    do lado Python pelo cupom impresso ao "Fechar Caixa" (ver
    FechamentoController._montar_recibo_fechamento), que não tem QML pra
    reaproveitar o binding."""
    valores = {"bruto": bruto, "contagem": contagem, "extras": extras}
    return sum(valores[termo] * _multiplicador(_config[termo]) for termo in TERMOS)


# ---------- Sincronização entre máquinas da malha (mesmo padrão de
# services/comandaEstiloService.py) ----------

_TIPO_EVENTO_FORMULA = "formula_lucro_alterada"
_CHAVE_DOMINIO_FORMULA = "formula_lucro"


def _payload_formula():
    return _config


def _resumo_formula():
    versao = _config.get("idEvento") or ""
    if not versao:
        # Nunca alterada nesta máquina — cai no conteúdo como versão só pra
        # detectar divergência; não decide quem é mais novo (mesmo
        # raciocínio de comandaEstiloService._resumo_estilo).
        versao = json.dumps(_config, sort_keys=True)
    return {"itens": {_CHAVE_DOMINIO_FORMULA: versao}}


def _obter_formula_reconciliacao(chave):
    if chave != _CHAVE_DOMINIO_FORMULA:
        return None
    return _payload_formula()


def _aplicar_formula_remota(payload):
    """Só sobrescreve se o idEvento recebido for mais novo que o local —
    mesma guarda de comandaEstiloService._aplicar_estilo_remoto. Devolve
    True só se aplicou de fato."""
    from services.rede import relogio

    global _config
    payload = payload or {}
    id_recebido = payload.get("idEvento", "")
    id_local = _config.get("idEvento", "")

    if id_recebido:
        relogio.observar(id_recebido)

    if id_local and (not id_recebido or not relogio.mais_novo(id_recebido, id_local)):
        return False

    novo = _padrao()
    for termo in TERMOS:
        if payload.get(termo) in SINAIS_VALIDOS:
            novo[termo] = payload[termo]
    novo["idEvento"] = id_recebido

    _config = novo
    _salvar()
    return True


class FormulaLucroController(QObject):
    """Ponte pra tela de Fechamento (PopupFormulaLucro.qml) ler/gravar a
    configuração acima."""

    formulaAlterada = pyqtSignal()

    def __init__(self):
        super().__init__()
        from services.rede import rede

        rede.registrarEvento(_TIPO_EVENTO_FORMULA, self._ao_receber_formula_remota)
        rede.registrarDominioSincronizado(
            _CHAVE_DOMINIO_FORMULA,
            _resumo_formula,
            _obter_formula_reconciliacao,
            self._aplicar_formula_reconciliacao,
        )

    def _ao_receber_formula_remota(self, payload):
        if _aplicar_formula_remota(payload):
            self.formulaAlterada.emit()

    def _aplicar_formula_reconciliacao(self, chave, payload):
        if chave != _CHAVE_DOMINIO_FORMULA:
            return
        if _aplicar_formula_remota(payload):
            self.formulaAlterada.emit()

    @pyqtSlot(result="QVariantMap")
    @protegido({})
    def obterConfiguracao(self):
        return _config

    @pyqtSlot(str, str, str, result="QVariantMap")
    @protegido({})
    def definirFormula(self, sinal_contagem, sinal_extras, sinal_bruto):
        """Grava a nova fórmula, propaga pra malha e devolve a configuração
        salva (com o idEvento novo) — quem chama usa o retorno pra
        atualizar a tela na hora, sem esperar o próprio sinal de volta."""
        global _config
        from services.rede import relogio, rede

        novo = _padrao()
        novo["contagem"] = sinal_contagem if sinal_contagem in SINAIS_VALIDOS else novo["contagem"]
        novo["extras"] = sinal_extras if sinal_extras in SINAIS_VALIDOS else novo["extras"]
        novo["bruto"] = sinal_bruto if sinal_bruto in SINAIS_VALIDOS else novo["bruto"]
        novo["idEvento"] = relogio.novo_id()

        _config = novo
        _salvar()
        rede.publicarEvento(_TIPO_EVENTO_FORMULA, _payload_formula())
        self.formulaAlterada.emit()
        return _config
