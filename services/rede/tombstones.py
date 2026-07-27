"""Registro persistido de exclusões ("tombstones") para os domínios de
sincronização que têm operação de apagar — hoje só pedidos e mesas (ver
services/rede/redeService.py:registrarDominioSincronizado). Sem isto, uma
máquina que reconecta depois de perder o evento de exclusão (gossip
"pedido_apagado"/"mesa_fechada") não tem como distinguir "nunca vi este
item" de "vi e ele foi apagado" — e tanto o catch-up de handshake
(meus_arquivos/pedir_arquivo) quanto a camada de anti-entropy periódica
(ver RedeService._disparar_reconciliacao) acabariam empurrando o item
apagado de volta pra quem apagou.

Guardado em pedidos/.sync/tombstones.json — dentro da própria árvore de
pedidos/ (já fora do git), mas fora dos padrões "*.txt" e "mesas/*.json"
que os scans existentes usam (ConsultaController.listarComandas,
SalaoController._listar_mesas_locais, RedeService._listar_arquivos_locais),
então não aparece em nenhum deles."""

import json
import os
from datetime import datetime, timedelta

_RETENCAO_PADRAO_DIAS = 180


def _raiz_projeto():
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _caminho_arquivo():
    return os.path.join(_raiz_projeto(), "pedidos", ".sync", "tombstones.json")


def _carregar_tudo():
    caminho = _caminho_arquivo()
    if not os.path.isfile(caminho):
        return {}

    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            dados = json.load(arquivo)
    except (OSError, json.JSONDecodeError) as erro:
        print(f"[tombstones] Falha ao ler {caminho}: {erro} — assumindo vazio.")
        return {}

    return dados if isinstance(dados, dict) else {}


def _salvar_tudo(dados):
    caminho = _caminho_arquivo()
    temporario = caminho + ".tmp"
    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
        with open(temporario, "w", encoding="utf-8") as arquivo:
            json.dump(dados, arquivo, indent=2, ensure_ascii=False)
        os.replace(temporario, caminho)
    except OSError as erro:
        print(f"[tombstones] Falha ao gravar {caminho}: {erro}")
        try:
            os.remove(temporario)
        except OSError:
            pass


def carregar(dominio):
    """{"chave": "isoApagadoEm", ...} de tudo que já foi apagado neste
    domínio, do ponto de vista desta máquina (inclui tanto o que ela mesma
    apagou quanto o que aprendeu de outras máquinas — ver registrar())."""
    return _carregar_tudo().get(dominio, {})


def registrar(dominio, chave, quando=None):
    """Grava um tombstone pra `chave` em `dominio` — chamado tanto por quem
    apaga de fato (ex: ConsultaController.apagarComanda,
    SalaoController.apagarMesa/fecharMesa) quanto por quem só recebe a
    notícia da exclusão de outra máquina (ex: removerPedidoRemoto,
    _ao_receber_mesa_fechada_remota, ou ao processar "apagados" recebido
    numa reconciliação). Todo nó que aprende de uma exclusão precisa
    lembrar dela — senão um terceiro nó ainda desatualizado pode
    reintroduzi-la mais tarde através DELE, mesmo que o originador e este
    nó já estejam corretos."""
    quando = quando or datetime.now().isoformat()
    dados = _carregar_tudo()
    dados.setdefault(dominio, {})[chave] = quando
    _salvar_tudo(dados)
    return quando


def mesclar(dominio, recebidos):
    """Aplica tombstones recebidos de um peer (ver campo "apagados" de
    reconciliar_resumo em redeService.py) e devolve só as chaves que eram
    novidade aqui — quem chama usa isso pra saber quais precisam de fato
    disparar a exclusão local (arquivo/mesa), não só atualizar o
    registro."""
    if not recebidos:
        return []

    atuais = carregar(dominio)
    novas = [chave for chave in recebidos if chave not in atuais]
    if not novas:
        return []

    dados = _carregar_tudo()
    secao = dados.setdefault(dominio, {})
    for chave in novas:
        secao[chave] = recebidos[chave]
    _salvar_tudo(dados)
    return novas


def purgar_antigos(retencao_dias=_RETENCAO_PADRAO_DIAS):
    """Remove tombstones mais velhos que `retencao_dias` — evita que o
    arquivo cresça pra sempre. Chamado uma vez por ciclo de reconciliação
    (ver RedeService._disparar_reconciliacao). Uma máquina que fique
    offline por mais tempo que isso volta a correr o risco de reintroduzir
    algo já apagado há muito tempo — aceitável: o padrão já é bem generoso
    (meses) pra esse cenário improvável."""
    limite = (datetime.now() - timedelta(days=retencao_dias)).isoformat()
    dados = _carregar_tudo()
    mudou = False
    for secao in dados.values():
        for chave, quando in list(secao.items()):
            if quando < limite:
                del secao[chave]
                mudou = True
    if mudou:
        _salvar_tudo(dados)
