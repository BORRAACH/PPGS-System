"""Cadastro de clientes da Entrega — telefone, nome e endereço — guardado nas
próprias máquinas, replicado pela malha e cifrado em disco.

Substitui o ppgs_server, que guardava isto num banco numa das máquinas e era
alcançado pelas outras por dentro da malha: com a hospedeira desligada, nenhum
balcão tinha autofill. Aqui cada máquina pareada tem o cadastro inteiro.

A CHAVE DE CADA CLIENTE é o HMAC dos dígitos do telefone com a chave de índice
da malha (ver seguranca.chave_indice_clientes) — o mesmo "índice cego" que o
servidor usava. Toda máquina pareada chega à mesma chave para o mesmo telefone,
e o resumo da reconciliação (que lista as chaves) não mostra telefone nenhum.

EM DISCO, `pedidos/.sync/clientes.bin` é o JSON inteiro cifrado pelo cofre
local (services/cofreLocal.py), cuja chave o sistema operacional guarda. Um
arquivo que não abre (cofre de outra instalação) é tratado como cadastro vazio
— ele volta pela malha — e, na primeira gravação, fica de lado como
`clientes.bin.ilegivel-<instante>` em vez de ser sobrescrito.

Mesmo contrato de revisão de usuarios.py/historicoEnderecos.py: "idEventoRevisao"
diz qual versão do cliente é a mais recente, arbitrada por relogio.mais_novo.
Não há exclusão pela malha (nem tombstones): o que existe é sobrescrever o
endereço quando o cliente muda.

`{chave: {"telefone", "nome", "rua", "numero", "bairro", "observacao",
"atualizadoEm", "idEventoRevisao"}}`."""

import hashlib
import hmac
import json
import os
import time
from datetime import datetime

from services import cofreLocal
from services.rede import caminhos, relogio

_ROTULO = "clientes"

DOMINIO = "clientes"

# Tamanho máximo de cada campo — os mesmos limites que o ppgs_server validava
# (src/models.rs), para um registro vindo da malha não poder crescer sem teto.
_CAMPOS = {"nome": 120, "rua": 120, "numero": 20, "bairro": 80, "observacao": 200}
_MINIMO_DIGITOS_TELEFONE = 10
_MAXIMO_DIGITOS_TELEFONE = 20

_cache = None
# O arquivo existe mas não abriu nesta sessão: a próxima gravação o põe de
# lado em vez de apagar dados que talvez voltem a abrir (chaveiro trancado).
_arquivo_ilegivel = False


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "clientes.bin")


def digitos(telefone) -> str:
    return "".join(c for c in str(telefone or "") if c.isdigit())


def chave_de(telefone, chave_indice: bytes) -> str:
    """A chave do cliente deste telefone, ou "" quando não dá para calcular
    (telefone curto demais, ou esta máquina ainda sem rede)."""
    numero = digitos(telefone)
    if not chave_indice or not (_MINIMO_DIGITOS_TELEFONE <= len(numero) <= _MAXIMO_DIGITOS_TELEFONE):
        return ""
    return hmac.new(chave_indice, b"PPGS-cliente|" + numero.encode("ascii"), hashlib.sha256).hexdigest()


def _limpar(valor, tamanho: int) -> str:
    return " ".join(str(valor or "").split())[:tamanho]


def _normalizar(registro) -> dict | None:
    """O registro com os campos conhecidos, limpos e dentro do tamanho — ou
    None se ele não tem o mínimo (telefone válido e rua)."""
    if not isinstance(registro, dict):
        return None
    telefone = digitos(registro.get("telefone"))
    if not (_MINIMO_DIGITOS_TELEFONE <= len(telefone) <= _MAXIMO_DIGITOS_TELEFONE):
        return None
    normalizado = {campo: _limpar(registro.get(campo), tamanho) for campo, tamanho in _CAMPOS.items()}
    if not normalizado["rua"]:
        return None
    normalizado["telefone"] = telefone
    normalizado["atualizadoEm"] = _limpar(registro.get("atualizadoEm"), 32)
    normalizado["idEventoRevisao"] = _limpar(registro.get("idEventoRevisao"), 80)
    return normalizado


def carregar() -> dict:
    global _cache, _arquivo_ilegivel
    if _cache is not None:
        return _cache

    caminho = _caminho_arquivo()
    if not os.path.isfile(caminho):
        _cache = {}
        return _cache

    try:
        with open(caminho, "rb") as arquivo:
            dados = json.loads(cofreLocal.decifrar(arquivo.read()).decode("utf-8"))
    except (OSError, ValueError, UnicodeDecodeError, cofreLocal.ErroCofre) as erro:
        print(f"[{_ROTULO}] O cadastro de clientes desta máquina não abriu ({erro}) — "
              "começando vazio; os clientes voltam pela malha.")
        _arquivo_ilegivel = True
        _cache = {}
        return _cache

    brutos = dados.get("clientes") if isinstance(dados, dict) else None
    _cache = {}
    for chave, registro in (brutos or {}).items():
        normalizado = _normalizar(registro)
        if normalizado and isinstance(chave, str) and len(chave) == 64:
            _cache[chave] = normalizado
    return _cache


def _salvar(dados: dict) -> bool:
    global _cache, _arquivo_ilegivel
    caminho = _caminho_arquivo()
    if _arquivo_ilegivel and os.path.isfile(caminho):
        destino = f"{caminho}.ilegivel-{int(time.time())}"
        try:
            os.replace(caminho, destino)
            print(f"[{_ROTULO}] Cadastro ilegível guardado de lado em {destino}.")
        except OSError as erro:
            print(f"[{_ROTULO}] Não foi possível pôr de lado o cadastro ilegível ({erro}) — gravação cancelada.")
            return False
    try:
        blob = cofreLocal.cifrar(json.dumps({"clientes": dados}, ensure_ascii=False, separators=(",", ":")).encode("utf-8"))
    except cofreLocal.ErroCofre as erro:
        print(f"[{_ROTULO}] Não foi possível cifrar o cadastro de clientes: {erro}")
        return False
    if not caminhos.salvar_bytes(caminho, blob, _ROTULO):
        return False
    _arquivo_ilegivel = False
    _cache = dados
    return True


def buscar(telefone, chave_indice: bytes) -> dict | None:
    chave = chave_de(telefone, chave_indice)
    if not chave:
        return None
    registro = carregar().get(chave)
    return dict(registro) if registro else None


def salvar(dados: dict, chave_indice: bytes):
    """Cria ou sobrescreve o cliente deste telefone. Devolve (chave, registro)
    para quem vai publicar na malha, ou None quando não há o mínimo para
    guardar (telefone válido e rua) ou a gravação falhou."""
    chave = chave_de((dados or {}).get("telefone"), chave_indice)
    if not chave:
        return None
    registro = _normalizar(dict(
        dados,
        atualizadoEm=datetime.now().isoformat(timespec="seconds"),
        idEventoRevisao=relogio.novo_id(),
    ))
    if registro is None:
        return None

    novos = dict(carregar())
    novos[chave] = registro
    if not _salvar(novos):
        return None
    return chave, dict(registro)


def aplicar_remoto(chave: str, payload, chave_indice: bytes | None = None) -> bool:
    """Grava um cliente aprendido de outra máquina (gossip ou reconciliação).
    Devolve True se algo mudou aqui.

    Com `chave_indice`, confere que a chave recebida é mesmo a do telefone do
    registro: uma chave que não bata faria a reconciliação pedir, a cada ciclo,
    uma entrada que nunca passaria a existir com aquele nome."""
    registro = _normalizar(payload)
    if registro is None or not isinstance(chave, str) or len(chave) != 64:
        return False
    if chave_indice and chave_de(registro["telefone"], chave_indice) != chave:
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
