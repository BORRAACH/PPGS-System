"""Histórico do que aconteceu na malha: comandas lançadas e apagadas, mudanças
no cardápio, fechamento e caixa, configurações, e máquinas entrando e saindo.

Por que precisou existir. Até aqui os eventos da rede eram inteiramente
efêmeros: `BarramentoEventos` guardava os ids vistos por 10 minutos só para
descartar reentregas (services/rede/eventos.py) e esquecia tudo ao fechar o
app. Dava para ver o ESTADO atual de cada coisa, nunca o caminho até ele — e é
o caminho que responde perguntas como "esta comanda sumiu ou nunca chegou
aqui?" e "quem mudou este preço?".

Cada registro é guardado pelo id de `services/rede/relogio.py`, que já resolve
três coisas de uma vez: ordena os eventos numa linha do tempo comum, diz em que
máquina cada um nasceu (o sufixo do id) e quando (ver relogio.instante_do_id).
Por isso o histórico não precisa de campo de data nem de origem próprios — e
todas as máquinas mostram o mesmo horário para o mesmo evento, o da máquina
onde a mudança aconteceu, não o de quando cada uma soube dela.

O que NÃO é guardado: o payload do evento. Um `pedido_novo` carrega o cupom
inteiro em base64, e um mês desses viraria um JSON de dezenas de MB. Guarda-se
só um detalhe curto por tipo (o nome do arquivo, o item do cardápio, a data do
fechamento), extraído no momento do registro por `_DETALHE`.

Sincronizado como o domínio "historico" (ver RedeService.registrarDominioSincronizado
e ConsultaController._resumo_pedidos, mesmo contrato). Como evento é imutável —
nunca muda depois de acontecer —, a versão de cada um é o próprio id, e
reconciliar vira simplesmente a união dos dois lados: é assim que uma máquina
que entra na malha recebe o histórico acumulado por quem já estava lá."""

import os
from datetime import datetime, timedelta

from services.rede import caminhos, relogio

_ROTULO = "historicoEventos"

# Retenção dupla, por idade e por quantidade. A idade sozinha não segura um dia
# de movimento intenso (cada comanda replicada gera evento em toda máquina), e
# a quantidade sozinha apagaria o histórico de uma semana calma.
# Público: a tela de Usuários precisa dizer de quantos dias é a janela ao
# mostrar quantas ações uma pessoa autorizou (ver contar_autorizacoes e
# UsuariosController.detalhesUsuario) — um número sem a janela ao lado mentiria
# por omissão, parecendo o total de sempre.
RETENCAO_DIAS = 7
_MAXIMO_REGISTROS = 1000

# Categorias exibidas na tela de Rede — o filtro de lá é montado a partir
# daqui, então acrescentar uma categoria nova não exige mexer no QML.
COMANDAS = "comandas"
CARDAPIO = "cardapio"
CAIXA = "caixa"
CONFIGURACOES = "configuracoes"
MAQUINAS = "maquinas"
USUARIOS = "usuarios"

ROTULOS_CATEGORIAS = {
    COMANDAS: "Comandas",
    CARDAPIO: "Cardápio",
    CAIXA: "Fechamento e caixa",
    CONFIGURACOES: "Configurações",
    MAQUINAS: "Máquinas",
    USUARIOS: "Usuários e autorizações",
}

# Ícone por categoria, nos mesmos nomes do qtawesome já usados no app (ver
# qml/components/Icone.qml). Fica aqui, e não no QML, para um tipo de evento
# novo aparecer na tela sem precisar de duas edições.
_ICONES = {
    COMANDAS: "fa6s.receipt",
    CARDAPIO: "fa6s.book-open",
    CAIXA: "fa6s.cash-register",
    CONFIGURACOES: "fa6s.gear",
    MAQUINAS: "fa6s.desktop",
    USUARIOS: "fa6s.user-lock",
}

# Eventos que a malha publica hoje (ver RedeService.publicarEvento e quem
# chama). Um tipo desconhecido não é descartado: entra com a própria string
# como rótulo, para uma máquina com versão mais nova do app não ficar invisível
# no histórico de uma mais antiga.
_EVENTOS = {
    "pedido_novo": (COMANDAS, "Comanda lançada"),
    "pedido_apagado": (COMANDAS, "Comanda apagada"),
    "mesa_atualizada": (COMANDAS, "Mesa atualizada"),
    "mesa_fechada": (COMANDAS, "Mesa fechada"),
    "cardapio_alterado": (CARDAPIO, "Cardápio alterado"),
    "fechamento_atualizado": (CAIXA, "Fechamento do dia atualizado"),
    "comanda_baixada": (CAIXA, "Comanda baixada"),
    # Correção/exclusão de uma comanda que já tinha baixa (ver
    # services/rede/edicoesCaixa.py). Aparece aqui e no cupom de fechamento
    # do dia atingido — a tela de Rede responde "o que andou acontecendo",
    # o cupom é a trilha que acompanha o papel guardado.
    "edicao_caixa": (CAIXA, "Comanda fechada alterada"),
    "extra_lancado": (CAIXA, "Extra lançado"),
    "extra_apagado": (CAIXA, "Extra apagado"),
    "contagem_caixa_atualizada": (CAIXA, "Contagem de caixa atualizada"),
    "estilo_impressao_alterado": (CONFIGURACOES, "Estilo da comanda alterado"),
    "impressora_fixada": (CONFIGURACOES, "Impressora principal alterada"),
    # Publicados por este módulo, não pelo barramento (ver registrar_local).
    "maquina_conectada": (MAQUINAS, "Máquina entrou na rede"),
    "maquina_desconectada": (MAQUINAS, "Máquina saiu da rede"),
    "maquina_recusada": (MAQUINAS, "Máquina recusada na rede"),
    "servidor_designado": (MAQUINAS, "Servidor central mudou de máquina"),
    # Anotados só na máquina hospedeira, no instante em que ela avisa a malha
    # (ver RedeService._ao_mudar_servidor_local).
    "servidor_no_ar": (MAQUINAS, "Servidor central entrou no ar"),
    "servidor_fora_do_ar": (MAQUINAS, "Servidor central saiu do ar"),
    "conflito_detectado": (COMANDAS, "Divergência detectada entre máquinas"),
    "conflito_resolvido": (COMANDAS, "Divergência resolvida"),
    # Cadastro de quem pode autorizar as ações destrutivas (ver
    # services/rede/usuarios.py). Estes dois passam pelo barramento.
    "usuario_alterado": (USUARIOS, "Usuário cadastrado ou alterado"),
    "usuario_apagado": (USUARIOS, "Usuário removido"),
    # Uso do código no balcão. Publicados por registrar_local, NÃO pelo
    # barramento: é uma linha por ação protegida, e em malha isso seria
    # tráfego constante dizendo o que a reconciliação do domínio "historico"
    # já entrega sozinha alguns segundos depois.
    "autorizacao_concedida": (USUARIOS, "Ação autorizada"),
    "autorizacao_negada": (USUARIOS, "Código recusado"),
    "autorizacao_sem_cadastro": (USUARIOS, "Ação liberada sem usuário cadastrado"),
    # A senha do dono, que tranca o CADASTRO (ver services/rede/senhaDono.py).
    # "senha_dono_alterada" passa pelo barramento (é o evento de sincronização);
    # os três de baixo vêm de registrar_local, mesmo raciocínio dos de
    # autorização — é uma linha por tentativa, e pôr isso em gossip seria
    # tráfego constante na malha.
    "senha_dono_alterada": (USUARIOS, "Senha do dono definida ou trocada"),
    "usuarios_destrancado": (USUARIOS, "Cadastro de usuários destrancado"),
    "usuarios_senha_recusada": (USUARIOS, "Senha do dono recusada"),
    # Gravação no cadastro liberada porque ainda não há senha do dono definida
    # (ver UsuariosController._autorizar_escrita). O buraco do bootstrap
    # existe, mas nunca em silêncio — mesmo espírito de
    # "autorizacao_sem_cadastro".
    "usuarios_sem_senha": (USUARIOS, "Cadastro alterado sem senha definida"),
    "usuarios_bloqueado": (USUARIOS, "Cadastro recusado por estar trancado"),
}

# Eventos de escrituração que NÃO entram no histórico. A tela de Rede existe
# pra responder "o que aconteceu na malha", e a retenção é limitada
# (_MAXIMO_REGISTROS / RETENCAO_DIAS): um evento que dispara uma vez por
# comanda, sem dizer nada que o usuário queira saber, encurtaria pela metade a
# janela de dias realmente visível em troca de ruído.
#
# "comanda_numerada" (ver RedeService.reservar_numero_comanda) é exatamente
# isso: a reserva do número que vai sair impresso. O "pedido_novo" da MESMA
# comanda, esse sim no histórico, já conta a história inteira — inclusive o
# código, que está dentro do cupom.
_SEM_HISTORICO = {"comanda_numerada"}

# Como extrair, do payload de cada tipo, a linha curta que identifica o alvo do
# evento. Sem isto o histórico diria só "Comanda lançada", sem dizer qual.
_DETALHE = {
    "pedido_novo": lambda p: p.get("arquivo", ""),
    "pedido_apagado": lambda p: p.get("arquivo", ""),
    "mesa_atualizada": lambda p: f"Mesa {p.get('mesa', '')}".strip(),
    "mesa_fechada": lambda p: "",
    "cardapio_alterado": lambda p: p.get("categoria", ""),
    "fechamento_atualizado": lambda p: p.get("data", ""),
    "comanda_baixada": lambda p: p.get("arquivo", ""),
    "edicao_caixa": lambda p: f"{p.get('usuario', '')} — {p.get('codigo', '')} ({p.get('dataIso', '')})".strip(" —"),
    "extra_lancado": lambda p: p.get("descricao", ""),
    "extra_apagado": lambda p: "",
    "contagem_caixa_atualizada": lambda p: p.get("data", ""),
    "impressora_fixada": lambda p: p.get("nomeMaquina", "") or "automática",
    "maquina_conectada": lambda p: p.get("nome", ""),
    "maquina_desconectada": lambda p: p.get("nome", ""),
    # O endereço, e não um nome: uma máquina recusada nunca chegou a
    # dizer como se chama — o handshake morre antes do "identificar".
    "maquina_recusada": lambda p: f"{p.get('endereco', '?')} — {p.get('motivo', '')}".strip(" —"),
    "servidor_designado": lambda p: p.get("nome", ""),
    "servidor_no_ar": lambda p: p.get("nome", ""),
    "servidor_fora_do_ar": lambda p: p.get("nome", ""),
    "conflito_detectado": lambda p: p.get("arquivo", ""),
    "conflito_resolvido": lambda p: p.get("arquivo", ""),
    # Só o nome, nunca o código: o código não é segredo (ver o topo de
    # services/rede/usuarios.py), mas carimbá-lo para sempre no histórico de
    # todas as máquinas não ajuda ninguém a responder "quem fez isto?".
    "usuario_alterado": lambda p: p.get("nome", ""),
    "usuario_apagado": lambda p: p.get("nome", ""),
    "autorizacao_concedida": lambda p: f"{p.get('usuario', '')} — {p.get('acao', '')}: {p.get('alvo', '')}".strip(" —:"),
    # Aqui o código digitado ENTRA: numa recusa ele é a evidência útil (alguém
    # tentando adivinhar deixa uma trilha de códigos errados).
    "autorizacao_negada": lambda p: f"código {p.get('codigo', '')} — {p.get('acao', '')}: {p.get('alvo', '')}".strip(" —:"),
    "autorizacao_sem_cadastro": lambda p: f"{p.get('acao', '')}: {p.get('alvo', '')}".strip(" :"),
    # Quando ela passou a valer — nunca o hash, o salt ou qualquer parte do
    # registro: eles não dizem nada a quem lê a tela de Rede, e espalhá-los por
    # um arquivo a mais em toda máquina não ajuda ninguém.
    "senha_dono_alterada": lambda p: p.get("definidaEm", ""),
    "usuarios_bloqueado": lambda p: p.get("acao", ""),
    "usuarios_sem_senha": lambda p: p.get("acao", ""),
    "usuarios_senha_recusada": lambda p: p.get("acao", ""),
}


def _caminho():
    return os.path.join(caminhos.pasta_sincronizacao(), "historico.json")


def _carregar():
    return caminhos.carregar_json(_caminho(), _ROTULO)


def _salvar(dados):
    caminhos.salvar_json(_caminho(), dados, _ROTULO)


def _detalhe_de(tipo_evento, payload):
    extrair = _DETALHE.get(tipo_evento)
    if extrair is None:
        return ""
    try:
        return str(extrair(payload or {}) or "")[:120]
    except (AttributeError, TypeError):
        # Payload de uma versão do app com outro formato — o evento continua
        # valendo no histórico, só sem o detalhe.
        return ""


def registrar(id_evento, tipo_evento, payload=None, maquina=""):
    """Anota um evento no histórico. Idempotente pelo id: o mesmo evento chega
    por gossip e pode reaparecer na reconciliação, e regravar mudaria nada além
    de gastar disco.

    `maquina` só precisa ser passada quando não dá pra deduzir do id (que
    carrega o nome de quem o gerou)."""
    if not id_evento or not tipo_evento:
        return False

    if tipo_evento in _SEM_HISTORICO:
        return False

    dados = _carregar()
    if id_evento in dados:
        return False

    dados[id_evento] = {
        "tipo": tipo_evento,
        "maquina": maquina or relogio.maquina_do_id(id_evento),
        "detalhe": _detalhe_de(tipo_evento, payload),
    }
    _salvar(_purgados(dados))
    return True


def registrar_local(tipo_evento, payload=None):
    """Anota um evento que nasce nesta máquina e NÃO passa pelo barramento —
    entrada/saída de peers e conflitos de comanda. Os que passam pelo
    barramento já são capturados por lá (ver BarramentoEventos.publicar)."""
    id_evento = relogio.novo_id()
    registrar(id_evento, tipo_evento, payload)
    return id_evento


def _purgados(dados):
    """Descarta o que passou da retenção. Roda a cada gravação, que é barato
    (o arquivo já está em memória) e evita depender de alguém lembrar de
    chamar uma limpeza periódica."""
    if len(dados) <= _MAXIMO_REGISTROS:
        # Comparar id com id como string é comparar cronologicamente (ver
        # relogio) — o limiar fictício de id_para_instante existe pra isso, e
        # é o mesmo truque de tombstones.purgar_antigos.
        limite = relogio.id_para_instante(datetime.now() - timedelta(days=RETENCAO_DIAS))
        antigos = [id_evento for id_evento in dados if id_evento < limite]
        if not antigos:
            return dados
        return {id_evento: v for id_evento, v in dados.items() if id_evento not in antigos}

    # Passou do teto: descarta primeiro o ruído de conectividade. Uma malha
    # instável religa sozinha a cada poucos segundos, e numa rodada de teste
    # isso já produziu 61 eventos de máquina para 5 de comanda — sem esta
    # prioridade, um dia de rede ruim empurraria todo o histórico de vendas
    # para fora da retenção, que é justamente o que ninguém pode perder.
    # Dentro de cada grupo continua valendo o mais recente (ordenar id é
    # ordenar cronologicamente, ver relogio).
    def _prioridade(id_evento):
        entrada = dados[id_evento]
        tipo_evento = entrada.get("tipo", "") if isinstance(entrada, dict) else ""
        categoria, _rotulo = _EVENTOS.get(tipo_evento, (MAQUINAS, tipo_evento))
        return (0 if categoria == MAQUINAS else 1, id_evento)

    mantidos = sorted(dados, key=_prioridade, reverse=True)[:_MAXIMO_REGISTROS]
    return {id_evento: dados[id_evento] for id_evento in mantidos}


def contar_autorizacoes(nome):
    """(quantas, id_do_mais_recente) das ações que `nome` autorizou dentro da
    janela de retenção deste histórico. (0, "") quando não há nenhuma.

    DUAS LIMITAÇÕES, ditas aqui para não serem descobertas na tela: a janela é
    a da retenção (ver RETENCAO_DIAS/_MAXIMO_REGISTROS), então isto conta os
    últimos dias e não a vida inteira da pessoa; e o casamento é pelo NOME,
    porque o id do usuário não é guardado no registro — só o `detalhe` é (ver
    o topo do módulo). Dois homônimos no cadastro somam juntos.

    O nome vem no começo do detalhe, na forma "Nome — Ação: alvo" (ver
    _DETALHE), e vira só "Nome" quando ação e alvo estão vazios — daí a
    comparação aceitar as duas formas."""
    nome = (nome or "").strip()
    if not nome:
        return 0, ""

    prefixo = f"{nome} \u2014"
    quantas = 0
    ultimo = ""
    for id_evento, entrada in _carregar().items():
        if not isinstance(entrada, dict) or entrada.get("tipo") != "autorizacao_concedida":
            continue
        detalhe = entrada.get("detalhe", "")
        if detalhe != nome and not detalhe.startswith(prefixo):
            continue
        quantas += 1
        # Comparar id com id como string é comparar cronologicamente (ver
        # relogio) — mesmo truque de _purgados.
        if id_evento > ultimo:
            ultimo = id_evento
    return quantas, ultimo


def listar(limite=200, categorias=None):
    """Os eventos mais recentes primeiro, já prontos para a tela: rótulo em
    português, categoria, ícone, máquina de origem e o instante em que
    aconteceu.

    `categorias` filtra por uma lista de categorias (None = todas)."""
    dados = _carregar()
    registros = []
    for id_evento in sorted(dados, reverse=True):
        entrada = dados[id_evento]
        if not isinstance(entrada, dict):
            continue

        tipo_evento = entrada.get("tipo", "")
        categoria, rotulo = _EVENTOS.get(tipo_evento, (MAQUINAS, tipo_evento))
        if categorias and categoria not in categorias:
            continue

        registros.append({
            "id": id_evento,
            "tipo": tipo_evento,
            "categoria": categoria,
            "rotuloCategoria": ROTULOS_CATEGORIAS.get(categoria, categoria),
            "icone": _ICONES.get(categoria, "fa6s.circle-info"),
            "rotulo": rotulo,
            "detalhe": entrada.get("detalhe", ""),
            "maquina": entrada.get("maquina", ""),
            "quando": relogio.instante_do_id(id_evento),
        })
        if len(registros) >= limite:
            break

    return registros


# ---------- Sincronização entre máquinas ----------
# Evento é imutável: a versão de cada um é o próprio id, e reconciliar é a
# união dos dois lados. Nada é apagado pela malha (não há `apagar`) — a
# retenção é decisão local de cada máquina.


def resumo():
    dados = _carregar()
    return {"itens": {id_evento: id_evento for id_evento in dados}, "apagados": {}}


def obter(id_evento):
    entrada = _carregar().get(id_evento)
    return entrada if isinstance(entrada, dict) else None


def aplicar(id_evento, payload):
    """Grava um evento aprendido de outra máquina, preservando o registro dela
    (inclusive a máquina de origem, que não pode ser reinterpretada aqui)."""
    if not isinstance(payload, dict):
        return

    relogio.observar(id_evento)
    dados = _carregar()
    if id_evento in dados:
        return

    dados[id_evento] = {
        "tipo": payload.get("tipo", ""),
        "maquina": payload.get("maquina", "") or relogio.maquina_do_id(id_evento),
        "detalhe": payload.get("detalhe", ""),
    }
    _salvar(_purgados(dados))
