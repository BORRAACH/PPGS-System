"""Taxa de entrega de cada bairro, replicada pela malha.

Quando o atendente digita a taxa de um bairro na Entrega, ela fica guardada
aqui e vai para as outras máquinas; ao preencher o mesmo bairro em qualquer
uma delas, a taxa aparece sozinha (ver controllers/taxasBairroController.py).

A CHAVE é o bairro normalizado (services/enderecoFormatado.normalizar_endereco):
"Centro", "centro" e "CENTRO" são o mesmo registro, então duas máquinas que
definem o mesmo bairro disputam a mesma entrada em vez de duplicá-la.

Mesmo contrato de revisão de clientes.py: "idEventoRevisao" diz qual versão é a
mais recente, arbitrada por relogio.mais_novo (o último a escrever vence). Não
há exclusão pela malha: o que existe é sobrescrever a taxa.

`{chave: {"bairro", "taxa", "atualizadoEm", "idEventoRevisao"}}`."""

import os
import re
from datetime import datetime

from services.enderecoFormatado import normalizar_endereco
from services.rede import caminhos, relogio

_ROTULO = "taxasBairro"

DOMINIO = "taxasBairro"

_TAMANHO_BAIRRO = 80
# O texto que o campo da Entrega produz (Moeda.formatar): "R$ 8,00".
_TAXA_VALIDA = re.compile(r"^(R\$ )?\d{1,6}([.,]\d{1,2})?$")

_cache = None


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "taxasBairro.json")


def chave_de(bairro) -> str:
    return normalizar_endereco(bairro)


def _limpar(valor, tamanho: int) -> str:
    return " ".join(str(valor or "").split())[:tamanho]


def _normalizar(registro) -> dict | None:
    """O registro limpo, ou None se faltar bairro ou a taxa não for dinheiro."""
    if not isinstance(registro, dict):
        return None
    bairro = _limpar(registro.get("bairro"), _TAMANHO_BAIRRO)
    taxa = _limpar(registro.get("taxa"), 20)
    if not chave_de(bairro) or not _TAXA_VALIDA.match(taxa):
        return None
    return {
        "bairro": bairro,
        "taxa": taxa,
        "atualizadoEm": _limpar(registro.get("atualizadoEm"), 32),
        "idEventoRevisao": _limpar(registro.get("idEventoRevisao"), 80),
    }


def carregar() -> dict:
    global _cache
    if _cache is not None:
        return _cache
    brutos = caminhos.carregar_json(_caminho_arquivo(), _ROTULO)
    _cache = {}
    for chave, registro in brutos.items():
        normalizado = _normalizar(registro)
        if normalizado and chave == chave_de(normalizado["bairro"]):
            _cache[chave] = normalizado
    return _cache


def _salvar(dados: dict) -> bool:
    global _cache
    caminhos.salvar_json(_caminho_arquivo(), dados, _ROTULO)
    _cache = dados
    return True


def taxa_do_bairro(bairro) -> str:
    """A taxa guardada para este bairro, ou "" quando não há."""
    registro = carregar().get(chave_de(bairro))
    return registro["taxa"] if registro else ""


def definir(bairro, taxa):
    """Guarda a taxa do bairro. Devolve (chave, registro) para quem vai
    publicar na malha, ou None quando os dados não servem ou a taxa já é essa
    (nada a replicar)."""
    registro = _normalizar({
        "bairro": bairro,
        "taxa": taxa,
        "atualizadoEm": datetime.now().isoformat(timespec="seconds"),
        "idEventoRevisao": relogio.novo_id(),
    })
    if registro is None:
        return None
    chave = chave_de(registro["bairro"])
    atual = carregar().get(chave)
    if atual is not None and atual["taxa"] == registro["taxa"]:
        return None

    novos = dict(carregar())
    novos[chave] = registro
    if not _salvar(novos):
        return None
    return chave, dict(registro)


def aplicar_remoto(chave: str, payload) -> bool:
    """Grava uma taxa aprendida de outra máquina (gossip ou reconciliação).
    Devolve True se algo mudou aqui."""
    registro = _normalizar(payload)
    if registro is None or not isinstance(chave, str) or chave != chave_de(registro["bairro"]):
        return False

    relogio.observar(registro["idEventoRevisao"])
    local = carregar().get(chave)
    if local is not None and not relogio.mais_novo(registro["idEventoRevisao"], local.get("idEventoRevisao", "")):
        return False

    novos = dict(carregar())
    novos[chave] = registro
    return _salvar(novos)


# ---------- Anti-entropy (ver RedeService.registrarDominioSincronizado) ----------

def resumo():
    return {"itens": {chave: registro.get("idEventoRevisao", "") for chave, registro in carregar().items()}}


def obter(chave):
    registro = carregar().get(chave)
    return dict(registro) if registro else None
