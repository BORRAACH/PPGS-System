"""Histórico dos endereços de entrega já usados em comandas, replicado pela
malha — a fonte de sugestão da Entrega.qml que funciona sem internet (ver
services/sugestoesEndereco.py).

Existe também porque o mapa não fala a língua do balcão: o OpenStreetMap põe
a Av. dos Bombeiros no "Areão", e a comanda diz "Jardim Garcês". O Photon
nunca vai sugerir o nome que a equipe escreve; o histórico aprende esse nome
na primeira comanda que o usar.

Uma entrada por par (rua, bairro), com a chave normalizada (sem acento,
minúscula — ver buscaCardapio.normalizar): a mesma rua em dois bairros vira
duas entradas, que é justamente o que a prioridade por bairro precisa, e
"Rua José" e "rua jose" viram uma só.

Mesmo contrato de revisão de usuarios.py/extrasCaixa.py: "idEventoRevisao"
diz qual versão da entrada é a mais recente, arbitrada por
relogio.mais_novo. Não há exclusão pela malha, e portanto nem tombstones: um
endereço usado uma vez continua sendo um endereço que existe.

Guardado em pedidos/.sync/enderecos_usados.json:
`{chave: {"rua", "bairro", "usos", "ultimoUso", "idEventoRevisao"}}`."""

import os
from datetime import datetime

from services.buscaCardapio import normalizar
from services.enderecoFormatado import normalizar_endereco, termos_de_busca
from services.rede import caminhos, relogio

_ROTULO = "historicoEnderecos"

DOMINIO = "enderecos_usados"

# Teto de entradas no arquivo. Uma pizzaria de bairro não chega perto disso em
# anos, mas o arquivo é lido a cada busca do autocomplete e reconciliado com
# a malha inteira a cada ciclo — sem teto, ele só cresceria.
LIMITE_ENTRADAS = 3000


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "enderecos_usados.json")


def _limpar(texto):
    """Espaços repetidos e das pontas fora — o que vai para a tela e para a
    chave precisa ser a mesma rua, digitada com um espaço a mais ou não."""
    return " ".join(str(texto or "").split())


def _inteiro(valor):
    try:
        return max(0, int(valor))
    except (TypeError, ValueError):
        return 0


def chave(rua, bairro):
    return f"{normalizar(rua)}|{normalizar(bairro)}"


# (marca de modificação do arquivo, dados, [(rua normalizada, bairro
# normalizado, registro)] do mais usado para o menos, [(bairro normalizado,
# nome)] do bairro com mais usos somados para o com menos). A busca roda a
# cada tecla na Entrega.qml: reler o JSON, normalizar e ordenar a cada tecla
# pesaria na máquina fraca, e com tudo pré-ordenado a busca para no limite. A
# marca do arquivo (e não só a invalidação em _salvar) é o que pega a
# gravação feita por outro processo — os scripts de docker/ gravam na mesma
# pasta.
_cache = None


def _lido():
    global _cache
    try:
        marca = os.stat(_caminho_arquivo()).st_mtime_ns
    except OSError:
        marca = None
    if _cache is None or _cache[0] != marca:
        dados = caminhos.carregar_json(_caminho_arquivo(), _ROTULO)
        dados = {k: v for k, v in dados.items() if isinstance(v, dict) and v.get("rua")}
        registros = sorted(
            dados.values(), key=lambda r: (_inteiro(r.get("usos")), r.get("ultimoUso", "")), reverse=True
        )
        # Forma de comparação (e não a chave): "RUA ANTONIO ROMERO" e "R. Antônio
        # Romero" casam com a mesma busca, e "ARCO IRIS" e "Arco-Iris" somam os
        # usos no mesmo bairro. Ver services/enderecoFormatado.py.
        normalizados = [(normalizar_endereco(r.get("rua", "")), normalizar_endereco(r.get("bairro", "")), r) for r in registros]

        totais = {}
        grafias = {}
        for _rua, nb, registro in normalizados:
            if nb:
                totais[nb] = totais.get(nb, 0) + _inteiro(registro.get("usos"))
                grafias.setdefault(nb, registro.get("bairro", ""))
        bairros = [(nb, grafias[nb]) for nb in sorted(totais, key=lambda nb: totais[nb], reverse=True)]

        _cache = (marca, dados, normalizados, bairros)
    return _cache


def carregar():
    return _lido()[1]


def _podar(dados):
    """Fica com as LIMITE_ENTRADAS mais usadas (e, no empate, as usadas por
    último) — o endereço do cliente de toda sexta nunca é o que sai."""
    if len(dados) <= LIMITE_ENTRADAS:
        return dados
    ordenadas = sorted(
        dados.items(),
        key=lambda item: (_inteiro(item[1].get("usos")), item[1].get("ultimoUso", "")),
        reverse=True,
    )
    return dict(ordenadas[:LIMITE_ENTRADAS])


def _salvar(dados):
    global _cache
    caminhos.salvar_json(_caminho_arquivo(), _podar(dados), _ROTULO)
    # Sem esperar a marca do arquivo mudar: em sistema de arquivos de
    # resolução grossa, duas gravações seguidas podem ter a mesma marca.
    _cache = None


def registrar(rua, bairro):
    """Conta mais um uso de (rua, bairro) e devolve (chave, registro) para
    quem vai publicar na malha — ou None quando não há rua (comanda sem
    endereço não ensina nada)."""
    rua = _limpar(rua)
    bairro = _limpar(bairro)
    if not rua:
        return None

    dados = carregar()
    k = chave(rua, bairro)
    registro = dados.get(k) or {}
    registro = {
        # A grafia mais recente vence: se alguém corrigir o acento de uma
        # rua, é a correção que passa a ser sugerida.
        "rua": rua,
        "bairro": bairro,
        "usos": _inteiro(registro.get("usos")) + 1,
        "ultimoUso": datetime.now().isoformat(timespec="seconds"),
        "idEventoRevisao": relogio.novo_id(),
    }
    dados[k] = registro
    _salvar(dados)
    return k, dict(registro)


def aplicar_remoto(_chave, payload):
    """Grava uma entrada aprendida de outra máquina (gossip ou reconciliação).
    Devolve True se algo mudou aqui.

    A chave é recalculada a partir do conteúdo em vez de confiar na recebida:
    uma chave que não bate com o próprio registro faria a reconciliação pedir,
    a cada ciclo, uma entrada que nunca passaria a existir com aquele nome.

    `usos` fica com o MAIOR dos dois lados: duas máquinas lançando a mesma rua
    quase juntas geram duas revisões, e a que perde a arbitragem não pode
    levar a contagem dela embora."""
    if not isinstance(payload, dict):
        return False
    rua = _limpar(payload.get("rua"))
    if not rua:
        return False
    bairro = _limpar(payload.get("bairro"))
    id_revisao = payload.get("idEventoRevisao") or ""
    relogio.observar(id_revisao)

    dados = carregar()
    k = chave(rua, bairro)
    local = dados.get(k)
    if local is not None and not relogio.mais_novo(id_revisao, local.get("idEventoRevisao", "")):
        return False

    dados[k] = {
        "rua": rua,
        "bairro": bairro,
        "usos": max(_inteiro(payload.get("usos")), _inteiro((local or {}).get("usos"))),
        "ultimoUso": str(payload.get("ultimoUso") or ""),
        "idEventoRevisao": id_revisao,
    }
    _salvar(dados)
    return True


# ---------- Anti-entropy (ver RedeService.registrarDominioSincronizado) ----------

def resumo():
    return {"itens": {k: v.get("idEventoRevisao", "") for k, v in carregar().items()}}


def obter(k):
    registro = carregar().get(k)
    return dict(registro) if registro else None


# ---------- Busca ----------

def _casa(texto_normalizado, termo_normalizado):
    """Começo de qualquer palavra: "jo" acha "Rua José Dantas", e "jose da"
    também — o atendente raramente começa pelo "Rua"."""
    return f" {termo_normalizado}" in f" {texto_normalizado}"


def buscar_ruas(termo, limite=40):
    """Registros cuja rua casa com `termo`, dos mais usados para os menos —
    no máximo `limite` (a lista na tela mostra 8)."""
    termos = termos_de_busca(termo)
    if not termos:
        return []
    registros = []
    for rua, _bairro, registro in _lido()[2]:
        if any(_casa(rua, t) for t in termos):
            registros.append(dict(registro))
            if len(registros) >= limite:
                break
    return registros


def buscar_bairros(termo):
    """Nomes de bairro que casam com `termo`, somando os usos de todas as
    ruas de cada bairro — o bairro onde a pizzaria mais entrega vem primeiro."""
    termos = termos_de_busca(termo)
    if not termos:
        return []
    return [nome for nb, nome in _lido()[3] if any(_casa(nb, t) for t in termos)][:20]
