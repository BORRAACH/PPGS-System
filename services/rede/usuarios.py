"""Cadastro de usuários replicado pela malha — quem pode autorizar as ações
destrutivas do app (ver controllers/usuariosController.py e
qml/components/PopupAutorizacao.qml).

Cada usuário tem um código de DOIS DÍGITOS, que é o que se digita no balcão
para liberar uma edição de comanda fechada ou uma exclusão. Cadastrar numa
máquina cadastra em todas: mesmo desenho de extrasCaixa.py, do qual este
módulo é um decalque.

O QUE ESTE CADASTRO É, E O QUE NÃO É. Dois dígitos são cem combinações —
quem quiser acerta por tentativa em poucos minutos, e o guarda ainda por
cima freia mas não impede isso. Some a isso que a malha não autentica
ninguém (services/rede/seguranca.py:CHAVE_PADRAO está no código-fonte, e
architecture/EXPLAIN.md registra a decisão): qualquer instância do app na
mesma LAN lê este arquivo e pode publicar um cadastro forjado. Então isto
aqui é ATRIBUIÇÃO — responder "quem editou esta comanda?" — e um obstáculo
contra a própria equipe, não um segredo. É por isso que o código fica em
claro: hashear dois dígitos seria teatro (cem pré-imagens) e ainda
atrapalharia a checagem de código repetido.

O CÓDIGO NÃO É A CHAVE. A chave é o idEvento do relógio lógico
(services/rede/relogio.py), como em extrasCaixa.py, e o código é só um
campo. O motivo é o caso que só existe em sistema distribuído: duas
máquinas sem se enxergar podem cadastrar o código "07" para pessoas
diferentes, e as duas estão certas. Com o código como chave, uma delas
sumiria em silêncio na primeira reconciliação — some uma PESSOA do cadastro,
que é exatamente o tipo de perda que ninguém percebe até precisar. Com
idEvento como chave, a fusão é união: os dois usuários sobrevivem, o código
repetido fica visível na tela de cadastro, e `por_codigo` devolve os dois
para quem digitar 07 escolher qual é.

Os dois ids de cada registro, mesmo contrato de extrasCaixa.py:

- a chave do dict ("idEvento") — identidade do usuário na malha, atribuída
  na criação e IMUTÁVEL (trocar o nome ou o código continua sendo a mesma
  pessoa).
- "idEventoRevisao" — qual versão do conteúdo (nome/código) é a mais
  recente. Nasce igual ao idEvento; toda edição gera um novo, e
  relogio.mais_novo arbitra duas máquinas editando o mesmo usuário quase ao
  mesmo tempo.

Guardado em pedidos/.sync/usuarios.json (ver services/rede/caminhos.py):
`{idEvento: {"codigo", "nome", "dataHora", "idEventoRevisao"}}`."""

import os

from services.rede import caminhos, relogio, tombstones

_ROTULO = "usuarios"

# O domínio de tombstones e o de reconciliação têm o mesmo nome de propósito
# (ver UsuariosController) — é uma coisa só vista de dois ângulos, e nomes
# diferentes só dariam chance de errar um deles.
DOMINIO = "usuarios"

# Dois dígitos, sempre — "7" e "07" precisam ser o MESMO código, senão duas
# pessoas digitam a mesma coisa e o app entende diferente. Toda entrada passa
# por normalizar_codigo antes de ser gravada ou comparada.
TAMANHO_CODIGO = 2


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "usuarios.json")


def normalizar_codigo(codigo):
    """"7" -> "07", " 07 " -> "07", "abc"/"" -> "". Ponto único por onde todo
    código passa: o campo da tela, a gravação e a busca usam este mesmo
    formato, então não existe "código que existe mas não é encontrado"."""
    texto = str(codigo or "").strip()
    if not texto.isdigit() or len(texto) > TAMANHO_CODIGO:
        return ""
    return texto.zfill(TAMANHO_CODIGO)


def carregar():
    """`{idEvento: {codigo, nome, dataHora, idEventoRevisao}}` de todos os
    usuários conhecidos por esta máquina (os que ela mesma cadastrou e os
    que aprendeu de outras)."""
    return caminhos.carregar_json(_caminho_arquivo(), _ROTULO)


def _salvar(dados):
    caminhos.salvar_json(_caminho_arquivo(), dados, _ROTULO)


def listar():
    """Todos os usuários, com o id embutido, ordenados por nome — é uma
    lista para gente ler (a tela de cadastro), não para a malha comparar."""
    itens = [dict(registro, id=id_evento) for id_evento, registro in carregar().items()]
    itens.sort(key=lambda item: (str(item.get("nome", "")).lower(), item.get("codigo", "")))
    return itens


def por_codigo(codigo):
    """Usuários que usam `codigo`. Devolve LISTA, e não um único registro,
    porque zero, um e vários são todos resultados possíveis e legítimos —
    ver o comentário sobre colisão no topo do módulo. Quem chama decide o
    que fazer com cada caso; esconder a ambiguidade aqui devolvendo "o
    primeiro" faria o app atribuir a ação à pessoa errada, calado."""
    procurado = normalizar_codigo(codigo)
    if not procurado:
        return []

    itens = [
        dict(registro, id=id_evento)
        for id_evento, registro in carregar().items()
        if normalizar_codigo(registro.get("codigo")) == procurado
    ]
    # Por id: o cadastro mais antigo primeiro, então a ordem da lista de
    # desempate não muda de máquina para máquina nem de abertura para
    # abertura do popup.
    itens.sort(key=lambda item: item["id"])
    return itens


def existe_algum():
    """True se esta máquina conhece pelo menos um usuário. É o que decide o
    caminho de bootstrap do guarda (ver PopupAutorizacao.solicitar): com o
    cadastro vazio a ação passa direto, senão uma instalação nova se trancaria
    para fora das próprias funções."""
    return bool(carregar())


def codigo_em_uso(codigo, ignorando=""):
    """True se `codigo` já pertence a outro usuário. `ignorando` é o id do
    próprio usuário sendo editado — sem isso, salvar um cadastro sem trocar
    o código acusaria conflito consigo mesmo."""
    return any(item["id"] != ignorando for item in por_codigo(codigo))


def registrar(codigo, nome, data_hora, quando=None):
    """Cadastra um usuário e devolve o id dele.

    `quando` vem preenchido quando o cadastro foi aprendido de outra máquina
    (gossip ou reconciliação): preservar o id de origem é o que faz todas as
    máquinas concordarem sobre a MESMA pessoa. Gerar um id local aqui faria
    cada máquina achar que conhece um usuário diferente, e o mesmo
    funcionário apareceria repetido na lista.

    Idempotente: um id que já existe não é regravado, senão uma reentrega de
    gossip sobrescreveria uma edição mais nova com o conteúdo original."""
    dados = carregar()
    id_evento = quando or relogio.novo_id()
    if id_evento in dados:
        return id_evento

    dados[id_evento] = {
        "codigo": normalizar_codigo(codigo),
        "nome": nome,
        "dataHora": data_hora,
        "idEventoRevisao": id_evento,
    }
    _salvar(dados)
    return id_evento


def editar(id_evento, codigo, nome, quando=None):
    """Corrige nome/código de um usuário — mantém o mesmo id (a identidade
    da pessoa) e a mesma dataHora do cadastro original. `quando` só vem
    preenchido quando a edição é aprendida de outra máquina (ver
    aplicar_edicao_remota). Devolve o id da revisão, ou None se o usuário
    não existe mais aqui (foi demitido enquanto a tela estava aberta)."""
    dados = carregar()
    registro = dados.get(id_evento)
    if registro is None:
        return None

    id_revisao = quando or relogio.novo_id()
    registro["codigo"] = normalizar_codigo(codigo)
    registro["nome"] = nome
    registro["idEventoRevisao"] = id_revisao
    _salvar(dados)
    return id_revisao


def apagar(id_evento, quando=None):
    """Remove um usuário — tombstone genérico de services/rede/tombstones.py,
    mesmo padrão de extrasCaixa.apagar. `quando` só vem preenchido quando a
    exclusão é aprendida de outra máquina.

    Sempre registra o tombstone, mesmo se o id já não existir mais aqui. Aqui
    isso pesa mais que nos outros domínios: sem o tombstone, a máquina que
    estava desligada quando o gerente tirou o funcionário do sistema volta e
    empurra o cadastro de volta para todo mundo na primeira reconciliação —
    a demissão não pega, e ninguém fica sabendo. Devolve o id do
    tombstone."""
    quando = tombstones.registrar(DOMINIO, id_evento, quando)
    dados = carregar()
    if id_evento in dados:
        del dados[id_evento]
        _salvar(dados)
    return quando


def aplicar_edicao_remota(id_evento, codigo, nome, id_revisao):
    """Aplica uma edição vinda de outra máquina só se `id_revisao` for
    estritamente mais nova que a revisão conhecida aqui — mesmo cuidado de
    extrasCaixa.aplicar_edicao_remota. Devolve True só se aplicou de fato."""
    dados = carregar()
    registro = dados.get(id_evento)
    if registro is None:
        return False

    # Antes da decisão, e não depois: observar um id vindo de fora avança o
    # relógio lógico local mesmo quando a mudança é descartada (ver
    # services/rede/relogio.py). É o invariante do HLC.
    if id_revisao:
        relogio.observar(id_revisao)

    versao_local = registro.get("idEventoRevisao", id_evento)
    if not id_revisao or not relogio.mais_novo(id_revisao, versao_local):
        return False

    registro["codigo"] = normalizar_codigo(codigo)
    registro["nome"] = nome
    registro["idEventoRevisao"] = id_revisao
    _salvar(dados)
    return True
