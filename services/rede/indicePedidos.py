"""Dá a cada comanda um lugar na linha do tempo comum da malha (o id de
`services/rede/relogio.py`) e guarda os conflitos que a sincronização não
pode resolver sozinha.

Por que uma comanda precisa disso. Mesas e cardápio já carregam um
`idEvento` dentro do próprio arquivo, e é ele que decide quem ganha quando
duas máquinas divergem. Comandas não tinham nada disso: a versão comparada
na anti-entropy era o sha256 do conteúdo, o que só responde "é igual ou
diferente", nunca "qual veio antes". Sem uma resposta pra segunda pergunta
não dá pra dizer se uma exclusão vinda de outra máquina é mais nova que a
comanda que existe aqui, nem apresentar ao usuário qual das duas versões é
a recente. E não dá pra embutir esse id no arquivo da comanda: ele é o
cupom ESC/POS impresso, byte a byte — mexer nele muda o que sai no papel e
quebra os parsers de `services/comandaParserService.py`. Daí o sidecar,
mesmo padrão que `services/cardapioService.py` já usa pro cardápio.

Dois arquivos, ambos em `pedidos/.sync/` (ver services/rede/caminhos.py):

- `eventos.json` — `{nome_arquivo: {"idEvento", "maquina"}}`. Gravado por
  quem cria a comanda (com um id novo) e por quem a recebe da rede (com o
  id que veio junto, nunca um novo — é isso que faz as máquinas
  concordarem sobre a mesma comanda).
- `conflitos.json` — o que precisa de decisão humana. Nada aqui é resolvido
  automaticamente: comanda é dinheiro, e sobrescrever a versão de uma
  máquina pela da outra pode mudar o caixa do dia sem ninguém perceber.
  Guarda o conteúdo da versão divergente pra Consulta poder mostrá-la e o
  usuário escolher (ver ConsultaController.adotarVersaoRemota/manterVersaoLocal).

Comandas antigas (as que já estavam em disco antes deste módulo existir)
não têm entrada em `eventos.json`. Pra elas, `id_evento()` sintetiza um id
a partir do carimbo de data/hora que já está no nome do arquivo — o mesmo
truque de `tombstones._migrar_valor_antigo`. O cálculo é determinístico e
não depende do fuso da máquina, então as duas máquinas chegam ao MESMO id
sintético pra mesma comanda antiga e nenhuma delas vê conflito onde não
há."""

import os
import re
import threading
import time
from contextlib import contextmanager
from datetime import datetime, timezone

from services.rede import caminhos, relogio

# "pedido_20260729_124230_07fe75.txt" -> "20260729_124230". Os três
# prefixos (pedido_/entrega_/mesa_) são os de balcaoController,
# entregaController e salaoController.
_PADRAO_CARIMBO = re.compile(r"^(?:pedido|entrega|mesa)_(\d{8})_(\d{6})_")

_ROTULO = "indicePedidos"


def _caminho_eventos():
    return os.path.join(caminhos.pasta_sincronizacao(), "eventos.json")


def _caminho_conflitos():
    return os.path.join(caminhos.pasta_sincronizacao(), "conflitos.json")


# ---------- Índice de eventos ----------

# Retrato do índice válido só durante um varredura() — ver a docstring dele.
# Thread-local de propósito: a anti-entropy varre numa thread de fundo
# enquanto a Consulta varre na thread da interface, e um retrato compartilhado
# entre as duas serviria a uma o que a outra fixou.
_escopo = threading.local()


@contextmanager
def varredura():
    """Fixa UMA leitura de `eventos.json` para todo o bloco.

    As consultas por comanda (`id_evento`, `maquina`, `impressao`) releem o
    arquivo inteiro a cada chamada. Isso é barato numa chamada avulsa e
    quadrático dentro de um laço: com 346 comandas em disco,
    `ConsultaController.listarComandas` lia o mesmo arquivo de 67 KB 347
    vezes, e `_resumo_pedidos` — que roda a cada ciclo de anti-entropy, em
    segundo plano, o dia inteiro — 499 vezes. Quase todo o tempo dos dois era
    reinterpretar JSON que não mudou entre uma volta e outra: medido no
    Pentium E5300 da pizzaria, 164,9 ms -> 12,8 ms e 229,0 ms -> 2,9 ms.

    O escopo é curto de propósito (uma varredura, dezenas de ms) porque o
    retrato não acompanha o que outra thread grava no meio dele. Quem GRAVA
    nunca parte do retrato: `_carregar_para_gravar` sempre relê do disco, pra
    o read-modify-write continuar tão estreito quanto era antes deste cache e
    não sobrescrever com dados velhos o que a malha acabou de registrar.

    Reentrante: um varredura() dentro de outro respeita o retrato de fora, e
    só o bloco mais externo o descarta.

    A leitura é preguiçosa — um bloco que não consulte o índice não paga
    nada."""
    if getattr(_escopo, "ativo", False):
        yield
        return

    _escopo.ativo = True
    _escopo.indice = None
    try:
        yield
    finally:
        _escopo.ativo = False
        _escopo.indice = None


def _ler_do_disco():
    return caminhos.carregar_json(_caminho_eventos(), _ROTULO)


def _retrato():
    """O índice fixado pelo varredura() em curso, ou None fora de um."""
    if not getattr(_escopo, "ativo", False):
        return None
    if getattr(_escopo, "indice", None) is None:
        _escopo.indice = _ler_do_disco()
    return _escopo.indice


def carregar_indice():
    """Todo o índice — `{nome_arquivo: {"idEvento", "maquina"}}`. Exposto
    porque a Consulta precisa varrê-lo inteiro (ver
    ConsultaController._nomes_maquinas_conhecidas), não só consultar uma
    chave.

    Dentro de um varredura(), devolve o retrato já em memória — e o MESMO
    dicionário, não uma cópia. Quem for alterá-lo tem que passar por
    `_carregar_para_gravar`."""
    fixado = _retrato()
    return fixado if fixado is not None else _ler_do_disco()


def _carregar():
    return carregar_indice()


def _carregar_para_gravar():
    """Sempre do disco, mesmo dentro de um varredura().

    Toda gravação aqui é read-modify-write sem trava entre processos, e o
    retrato da varredura pode ter minutos de idade em relação ao que a thread
    da malha já escreveu. Partir dele para gravar apagaria essas entradas —
    justamente as comandas recém-chegadas da rede."""
    return _ler_do_disco()


def _salvar(dados):
    caminhos.salvar_json(_caminho_eventos(), dados, _ROTULO)
    # Mantém o retrato coerente com o disco até o fim da varredura: sem isto,
    # a impressão digital recém-calculada em impressao() seria recalculada de
    # novo na próxima comanda que caísse no mesmo arquivo.
    if getattr(_escopo, "ativo", False):
        _escopo.indice = dados


def _id_sintetico(nome_arquivo):
    """Id de linha do tempo deduzido do nome do arquivo, pras comandas
    anteriores a este módulo. UTC explícito (e não o fuso local) pra duas
    máquinas configuradas em fusos diferentes não deduzirem ids diferentes
    pra mesma comanda — o que apareceria pro usuário como um conflito
    inventado. Devolve "" se o nome não tiver o carimbo esperado; `relogio`
    trata "" como "mais antigo que qualquer id real"."""
    correspondencia = _PADRAO_CARIMBO.match(nome_arquivo)
    if correspondencia is None:
        return ""

    try:
        momento = datetime.strptime(
            f"{correspondencia.group(1)}{correspondencia.group(2)}", "%Y%m%d%H%M%S"
        ).replace(tzinfo=timezone.utc)
    except ValueError:
        return ""

    return relogio.id_para_instante(momento)


def id_evento(nome_arquivo):
    """Id de linha do tempo da comanda. Nunca grava nada — é chamado a cada
    ciclo de anti-entropy, pra toda comanda da janela."""
    entrada = _carregar().get(nome_arquivo)
    if isinstance(entrada, dict) and entrada.get("idEvento"):
        return entrada["idEvento"]
    return _id_sintetico(nome_arquivo)


def maquina(nome_arquivo):
    """Nome da máquina onde a comanda foi lançada, ou "" quando
    desconhecido (comanda anterior a este módulo)."""
    entrada = _carregar().get(nome_arquivo)
    if isinstance(entrada, dict):
        return entrada.get("maquina") or ""
    return ""


def _gravar(nome_arquivo, id_evento, maquina_origem):
    dados = _carregar_para_gravar()
    entrada = {"idEvento": id_evento, "maquina": maquina_origem}
    # A impressão digital é recalculada na próxima leitura (ver impressao()):
    # gravar o índice é o único momento em que se sabe que o arquivo mudou.
    dados[nome_arquivo] = entrada
    _salvar(dados)
    return id_evento, maquina_origem


# ---------- Impressão digital do conteúdo ----------


def _calcular_impressao(nome_arquivo):
    """Resume a comanda pelos VALORES da venda, não pelos bytes do arquivo.

    Import local de propósito: services/rede/* é importado por redeService,
    que por sua vez é importado no meio da subida do pacote services.rede —
    trazer a cadeia do parser aqui no topo daria ciclo. É o mesmo cuidado que
    services/comandaEstiloService.py já toma com services.rede.

    Comparar os valores (e não sha256 dos bytes) faz duas máquinas com
    Config/estilo_impressao.json diferentes chegarem à MESMA impressão para a
    mesma venda — negrito num campo muda os bytes do cupom, não a venda. Com
    hash de bytes, cada máquina que tivesse mexido no estilo puxaria a comanda
    inteira do peer a cada ciclo, para no fim concluir que nada mudou."""
    import hashlib
    import json

    from services import comandaComparacaoService as comparacao

    caminho = os.path.join(caminhos.pasta_pedidos(), nome_arquivo)
    try:
        with open(caminho, "rb") as arquivo:
            conteudo = arquivo.read()
    except OSError:
        return ""

    campos = comparacao.campos_comparaveis(conteudo, nome_arquivo)
    serializado = json.dumps(campos, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(serializado.encode("utf-8")).hexdigest()[:16]


def impressao(nome_arquivo):
    """Impressão digital da comanda, calculada uma vez e guardada no índice.

    Validada pelo mtime do arquivo: sem isso, uma comanda alterada em disco
    (restauração de backup, edição manual) continuaria anunciando a impressão
    antiga à malha, e a divergência nunca seria detectada. Comandas que já
    estavam em disco antes deste campo existir simplesmente não têm a entrada
    e caem no cálculo na primeira leitura."""
    entrada = _carregar().get(nome_arquivo)
    entrada = entrada if isinstance(entrada, dict) else {}

    try:
        mtime = os.path.getmtime(os.path.join(caminhos.pasta_pedidos(), nome_arquivo))
    except OSError:
        return entrada.get("impressao", "")

    if entrada.get("impressao") and entrada.get("mtime") == mtime:
        return entrada["impressao"]

    # A partir daqui vai gravar, então relê do disco e recomeça da entrada de
    # lá — a que veio do retrato da varredura serve para decidir, não para
    # ser regravada por cima do que outra thread já escreveu.
    calculada = _calcular_impressao(nome_arquivo)
    dados = _carregar_para_gravar()
    entrada = dados.get(nome_arquivo)
    entrada = entrada if isinstance(entrada, dict) else {}
    entrada["impressao"] = calculada
    entrada["mtime"] = mtime
    dados[nome_arquivo] = entrada
    _salvar(dados)
    return calculada


def versao(nome_arquivo):
    """A versão anunciada de uma comanda na anti-entropy: id de linha do tempo
    + impressão digital do conteúdo.

    O id sozinho não bastava. Ele responde "qual veio antes", mas duas
    máquinas podem ter o MESMO id e conteúdos diferentes (o arquivo de uma
    delas foi alterado depois de replicado) — e nesse caso o resumo dizia
    "igual", a reconciliação não puxava nada e a divergência ficava invisível
    para sempre. Justamente o caso que a Consulta precisa destacar."""
    return f"{id_evento(nome_arquivo)}|{impressao(nome_arquivo)}"


def partes_da_versao(versao_anunciada):
    """(idEvento, impressao) de uma versão anunciada. Tolera o formato antigo
    (só o id, sem "|") de um peer ainda não atualizado — nesse caso a
    impressão vem vazia, e quem compara trata como "desconhecida"."""
    if not versao_anunciada or not isinstance(versao_anunciada, str):
        return "", ""
    id_parte, separador, impressao_parte = versao_anunciada.partition("|")
    return id_parte, impressao_parte if separador else ""


def registrar_local(nome_arquivo):
    """Anota uma comanda criada NESTA máquina: id novo do relógio local e a
    máquina local como origem. Só deve ser chamado por quem de fato acabou
    de criar a comanda (ver RedeService.transmitir_pedido)."""
    id_evento = relogio.novo_id()
    return _gravar(nome_arquivo, id_evento, relogio.maquina_do_id(id_evento) or "")


def registrar_recebido(nome_arquivo, id_recebido="", maquina_recebida=""):
    """Anota uma comanda que veio da rede, preservando a identidade de
    origem — é o que faz as máquinas concordarem sobre a mesma comanda.

    Quando o peer NÃO manda o id (versão antiga, sem este mecanismo, ou
    qualquer lacuna futura no protocolo), o certo é assumir que a origem é
    desconhecida: grava o id sintetizado do nome do arquivo, que as duas
    máquinas calculam igual, e deixa a máquina vazia — a Consulta então
    deduz a origem pela inicial do código impresso (ver
    ConsultaController._maquina_origem).

    Antes isto caía no mesmo caminho de `registrar_local` e a máquina que
    RECEBIA se declarava autora: uma comanda tirada no Windows aparecia na
    Consulta do Linux como se tivesse sido lançada no Linux. Pior que o
    rótulo errado, o id inventado localmente não bate com o que a outra
    máquina calcula pra mesma comanda — o que transformaria cada uma delas
    num conflito falso assim que as duas versões se encontrassem."""
    if id_recebido:
        relogio.observar(id_recebido)
        return _gravar(nome_arquivo, id_recebido, maquina_recebida or relogio.maquina_do_id(id_recebido) or "")

    return _gravar(nome_arquivo, _id_sintetico(nome_arquivo), maquina_recebida or "")


def remover(nome_arquivo):
    dados = _carregar_para_gravar()
    if dados.pop(nome_arquivo, None) is not None:
        _salvar(dados)


def purgar_ausentes(nomes_existentes):
    """Descarta entradas de comandas que não estão mais em disco — o índice
    não deve crescer para sempre. `nomes_existentes` é um conjunto/lista de
    nomes de arquivo. Chamado junto do ciclo de anti-entropy."""
    dados = _carregar_para_gravar()
    existentes = set(nomes_existentes)
    sobrando = [nome for nome in dados if nome not in existentes]
    if not sobrando:
        return
    for nome in sobrando:
        del dados[nome]
    _salvar(dados)


# ---------- Conflitos ----------


def carregar_conflitos():
    return caminhos.carregar_json(_caminho_conflitos(), _ROTULO)


def _salvar_conflitos(dados):
    caminhos.salvar_json(_caminho_conflitos(), dados, _ROTULO)


def registrar_conflito(
    nome_arquivo, motivo, id_local="", id_remoto="", maquina_remota="", conteudo_remoto_b64="", diferencas=None
):
    """Marca a comanda como divergente entre máquinas. Idempotente pelo par
    (motivo, idRemoto): a anti-entropy roda a cada 2 min e reencontraria o
    mesmo conflito indefinidamente — regravar a cada ciclo só gastaria
    disco e faria a data de detecção mentir.

    `diferencas` é a lista campo a campo de
    services/comandaComparacaoService.comparar, guardada junto para a Consulta
    mostrar o que exatamente não bate sem precisar reprocessar as duas versões
    a cada vez que o usuário abre o painel."""
    dados = carregar_conflitos()
    atual = dados.get(nome_arquivo)
    if isinstance(atual, dict) and atual.get("motivo") == motivo and atual.get("idRemoto") == id_remoto:
        return False

    dados[nome_arquivo] = {
        "motivo": motivo,
        "idLocal": id_local,
        "idRemoto": id_remoto,
        "maquinaRemota": maquina_remota,
        "conteudoRemoto_b64": conteudo_remoto_b64,
        "diferencas": diferencas or [],
        "detectadoEm": time.time(),
    }
    _salvar_conflitos(dados)
    print(f"[{_ROTULO}] Conflito em '{nome_arquivo}': {motivo} (máquina remota: {maquina_remota or 'desconhecida'}).")
    return True


def conflito(nome_arquivo):
    entrada = carregar_conflitos().get(nome_arquivo)
    return entrada if isinstance(entrada, dict) else None


def resolver_conflito(nome_arquivo):
    dados = carregar_conflitos()
    if dados.pop(nome_arquivo, None) is not None:
        _salvar_conflitos(dados)
