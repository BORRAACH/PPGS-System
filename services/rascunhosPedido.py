"""Pedidos de Balcão/Entrega começados e ainda não finalizados — os rascunhos
que a faixa no topo dessas telas lista (ver qml/components/FaixaRascunhos.qml).

POR QUE EXISTE. Na pizzaria se tira vários pedidos ao mesmo tempo, e sair da
tela no meio de uma anotação perdia tudo: a barra lateral navega com
`stackView.replace(null, ...)` (ver qml/components/LateralBar.qml), que destrói
a página inteira, e nem Balcão nem Entrega tinham qualquer gancho de saída. O
atendente que atendia o telefone no meio de um pedido de balcão voltava para um
formulário em branco.

O Salão já resolvia isso para mesas (uma mesa aberta é um JSON em
pedidos/mesas/, ver controllers/salaoController.py). Aqui é o mesmo desenho —
um arquivo por rascunho em pedidos/rascunhos/ — de propósito, para quem já
conhece um reconhecer o outro.

MORA EM services/, E NÃO EM services/rede/. A diferença é a que mais importa
neste módulo: TUDO em services/rede/ é sincronizado entre as máquinas da malha,
e isto NÃO é. Um rascunho é o pedido que está sendo digitado NAQUELE terminal;
espalhá-lo pela malha abriria a porta para dois atendentes editarem o mesmo
pedido pela metade, um sobrescrevendo o outro sem que nenhum perceba. Se algum
dia isso mudar, vai precisar do arbitrador de conflito que as mesas têm
(idEvento + relogio.mais_novo) — não basta registrar um domínio novo.

Guardado em pedidos/rascunhos/<id>.json:
`{"id", "tipo", "dados", "copias", "arquivoOriginal", "manterBaixaAoSalvar",
  "criadoEm", "atualizadoEm"}` — onde "dados" é exatamente o que
`coletarDadosPedido()` das telas devolve, para retomar ser só devolver o que
saiu de lá."""

import json
import os
import uuid
from datetime import datetime, timedelta

_ROTULO = "rascunhosPedido"

# Rascunho velho é rascunho esquecido. Sem uma poda, a faixa vira um cemitério
# de pedidos que ninguém vai terminar, e o que interessa (o de agora há pouco)
# some no meio. Mesmo número de historicoEventos.RETENCAO_DIAS, pela mesma
# razão: é a janela em que ainda faz sentido olhar para trás.
RETENCAO_DIAS = 7


def _raiz_projeto():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def pasta():
    """`pedidos/rascunhos/`. Criada na hora do uso, não na importação: este
    módulo é importado por scripts e testes que nem sempre querem tocar o disco
    do projeto."""
    caminho = os.path.join(_raiz_projeto(), "pedidos", "rascunhos")
    os.makedirs(caminho, exist_ok=True)
    return caminho


def _normalizar_id(id_rascunho):
    """O id reduzido ao nome de arquivo, para um id vindo da QML nunca virar
    caminho relativo — mesmo cuidado de FechamentoController.reimprimirComanda.

    Normalizado em UM lugar e usado tanto para montar o caminho quanto para
    devolver a quem salvou: fazer só no caminho deixava salvar("../x") gravar
    em "x.json" e devolver "../x", um id que não abre mais nada."""
    return os.path.basename(str(id_rascunho or "")).strip()


def _caminho(id_rascunho):
    return os.path.join(pasta(), f"{_normalizar_id(id_rascunho)}.json")


def _ler(caminho):
    # Ausência não é falha, e por isso não vira log: salvar() lê o arquivo
    # anterior para preservar "criadoEm", e num rascunho NOVO ele ainda não
    # existe — um caso totalmente esperado. Mesma armadilha já documentada em
    # SalaoController.salvarMesa.
    if not os.path.isfile(caminho):
        return None

    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            dados = json.load(arquivo)
    except (OSError, json.JSONDecodeError) as erro:
        print(f"[{_ROTULO}] Falha ao ler {caminho}: {erro} — ignorando.")
        return None
    return dados if isinstance(dados, dict) else None


def listar():
    """Todos os rascunhos NA ORDEM EM QUE FORAM ABERTOS — o mais antigo
    primeiro —, já sem os que passaram da retenção (ver purgar_antigos, chamada
    daqui: a poda acontece na leitura porque é o único momento em que se sabe
    que alguém está olhando).

    Por "criadoEm", e não por "atualizadoEm": a faixa é uma fila de pedidos que
    o atendente está tocando ao mesmo tempo, e ele localiza cada um pela
    POSIÇÃO. Ordenar pela última alteração fazia o rascunho em que ele clicava
    saltar para a frente — o autosave grava a cada poucos segundos —, e a fila
    se remexia sozinha embaixo da mão dele.

    O id desempata: `os.listdir` devolve os arquivos em ordem arbitrária, e sem
    um critério final dois rascunhos abertos no mesmo instante podiam trocar de
    lugar entre uma leitura e outra — exatamente o que esta ordem existe para
    evitar."""
    purgar_antigos()

    registros = []
    for nome in os.listdir(pasta()):
        if not nome.endswith(".json"):
            continue
        registro = _ler(os.path.join(pasta(), nome))
        if registro:
            registros.append(registro)

    registros.sort(key=lambda r: (r.get("criadoEm", ""), r.get("id", "")))
    return registros


def obter(id_rascunho):
    """O rascunho inteiro, ou None se ele não existe mais (apagado noutra aba
    da mesma máquina, ou podado por idade enquanto a tela estava aberta)."""
    if not id_rascunho:
        return None
    return _ler(_caminho(id_rascunho))


def salvar(registro):
    """Grava (criando ou sobrescrevendo) e devolve o id.

    Id vazio cria um rascunho novo, id preenchido atualiza — mesma convenção de
    SalaoController.salvarMesa. "criadoEm" é preservado do arquivo anterior:
    ele é a hora em que o pedido COMEÇOU a ser tirado, e regravá-lo a cada
    autosave apagaria justamente a informação de há quanto tempo aquele pedido
    está pendurado."""
    if not isinstance(registro, dict):
        return ""

    id_rascunho = _normalizar_id(registro.get("id")) or uuid.uuid4().hex
    anterior = _ler(_caminho(id_rascunho)) or {}
    agora = datetime.now().isoformat(timespec="seconds")
    # Microssegundos só na criação, que é o que ordena a faixa: dois rascunhos
    # abertos no mesmo segundo ficam na ordem certa em vez de caírem no
    # desempate por id. "atualizadoEm" fica em segundos porque quem o lê é a
    # poda por idade, e ali o segundo já é fino demais.
    agora_preciso = datetime.now().isoformat()

    completo = {
        "id": id_rascunho,
        "tipo": registro.get("tipo", ""),
        "dados": registro.get("dados") or {},
        "copias": registro.get("copias", 1),
        # Um rascunho pode ser a EDIÇÃO de uma comanda já salva (ver
        # components/EdicaoComanda.js): sem estes dois, retomá-lo gravaria uma
        # comanda nova e deixaria a antiga para trás, duplicando a venda.
        "arquivoOriginal": registro.get("arquivoOriginal", ""),
        "manterBaixaAoSalvar": bool(registro.get("manterBaixaAoSalvar", False)),
        "criadoEm": anterior.get("criadoEm", agora_preciso),
        "atualizadoEm": agora,
    }

    caminho = _caminho(id_rascunho)
    try:
        # Arquivo temporário + replace, como caminhos.salvar_json: a máquina é
        # desligada no fim do expediente, e um rascunho truncado no meio de uma
        # gravação seria pior que rascunho nenhum — ele apareceria na faixa e
        # falharia ao ser aberto.
        temporario = caminho + ".tmp"
        with open(temporario, "w", encoding="utf-8") as arquivo:
            json.dump(completo, arquivo, indent=2, ensure_ascii=False)
        os.replace(temporario, caminho)
    except OSError as erro:
        print(f"[{_ROTULO}] Falha ao gravar {caminho}: {erro}")
        return ""

    return id_rascunho


def apagar(id_rascunho):
    """Remove o rascunho. True mesmo se ele já não existia — o efeito desejado
    (não está mais lá) é o mesmo, e quem chama não tem o que fazer de diferente
    nos dois casos."""
    if not id_rascunho:
        return False

    caminho = _caminho(id_rascunho)
    try:
        os.remove(caminho)
    except FileNotFoundError:
        return True
    except OSError as erro:
        print(f"[{_ROTULO}] Falha ao apagar {caminho}: {erro}")
        return False
    return True


def purgar_antigos(dias=RETENCAO_DIAS):
    """Descarta rascunhos parados há mais de `dias`. Devolve quantos saíram.

    Pela data de ATUALIZAÇÃO, não a de criação: um pedido mexido ontem continua
    vivo mesmo tendo começado semana passada."""
    limite = (datetime.now() - timedelta(days=dias)).isoformat(timespec="seconds")

    removidos = 0
    for nome in os.listdir(pasta()):
        if not nome.endswith(".json"):
            continue

        caminho = os.path.join(pasta(), nome)
        registro = _ler(caminho)
        # Arquivo ilegível também sai: ele não tem como ser retomado, e deixá-lo
        # ali só faz o log repetir a falha de leitura a cada abertura da tela.
        if registro is None or registro.get("atualizadoEm", "") < limite:
            try:
                os.remove(caminho)
                removidos += 1
            except OSError:
                pass

    return removidos
