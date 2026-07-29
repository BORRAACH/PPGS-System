"""Relógio lógico híbrido (HLC) — dá a cada mudança de estado (comanda nova,
comanda apagada, mesa atualizada, cardápio alterado, e qualquer outro evento
futuro que se enquadre como "isto é uma mudança de estado que a malha
precisa saber") um id ordenável, gerado pela máquina onde a mudança
aconteceu, combinando data/hora com a identidade da máquina.

Comparar dois ids como string (`mais_novo`) equivale a comparar por ordem
cronológica/causal — é isso que dá à malha inteira uma "linha do tempo
comum": quando uma máquina que ficou offline reconecta e aprende (via
gossip ou via anti-entropy, ver services/rede/redeService.py) mudanças que
aconteceram enquanto ela estava fora, esses ids dizem, sem ambiguidade, qual
versão de cada coisa é a mais recente.

Por que não bastava um timestamp local puro (datetime.now().isoformat() +
nome da máquina, sem mais nada): no exato cenário que motivou este módulo —
uma máquina reconecta, aprende eventos "do futuro" do ponto de vista do
próprio relógio dela, e must voltar a gerar eventos novos localmente logo
em seguida — nada garante que o relógio de parede dela esteja adiantado o
suficiente (a malha não depende de NTP). Um HLC resolve isso com uma regra
barata: toda vez que esta máquina OBSERVA um id vindo de fora (`observar`),
o relógio lógico local avança para nunca ficar atrás do que já se sabe que
aconteceu — garantindo que o próximo id gerado localmente (`novo_id`) seja
sempre maior que qualquer coisa já vista, mesmo que o relógio de parede
desta máquina esteja um pouco atrasado."""

import threading
import time
from datetime import datetime

# Tamanho fixo dos dois primeiros campos do id — é o que permite comparar o
# id inteiro como string e obter a mesma ordem que comparar a tupla
# (fisico, logico, maquina): microssegundos desde epoch cabem em 16 dígitos
# até o ano ~5138, e o contador lógico não passa de milhares de eventos no
# mesmo microssegundo em nenhum cenário real deste app.
_LARGURA_FISICO = 16
_LARGURA_LOGICO = 4

_lock = threading.Lock()
_fisico = 0
_logico = 0


def _microssegundos_agora() -> int:
    return int(time.time() * 1_000_000)


def _formatar(fisico: int, logico: int, maquina: str) -> str:
    return f"{fisico:0{_LARGURA_FISICO}d}-{logico:0{_LARGURA_LOGICO}d}-{maquina}"


def _maquina_local() -> str:
    # Import local (não no topo do módulo) só para evitar qualquer risco de
    # import circular com services/rede/redeService.py, que importa este
    # módulo — platform.node() em si não depende de nada daqui.
    import platform

    return platform.node() or "maquina-desconhecida"


def novo_id() -> str:
    """Gera o próximo id desta máquina, sempre estritamente maior que
    qualquer id gerado ou observado (ver `observar`) por ela antes —
    regra padrão de HLC: se o relógio de parede já passou do último
    instante conhecido, usa o relógio de parede e zera o desempate lógico;
    senão (relógio de parede igual ou atrás, incluindo o caso do próprio
    relógio do SO andar pra trás) fica no mesmo instante e incrementa o
    desempate lógico."""
    global _fisico, _logico
    with _lock:
        agora = _microssegundos_agora()
        if agora > _fisico:
            _fisico = agora
            _logico = 0
        else:
            _logico += 1
        return _formatar(_fisico, _logico, _maquina_local())


def observar(id_remoto: str) -> None:
    """Aprende um id vindo de outra máquina (um evento de gossip recebido,
    ou um valor trazido por uma reconciliação de anti-entropy) — avança o
    relógio lógico local para nunca ficar atrás dele, garantindo que o
    próximo `novo_id()` desta máquina seja maior que tudo que ela já sabe
    que aconteceu. Tolerante a id malformado/vazio (registro migrado sem
    id de verdade, ou payload de uma máquina ainda não atualizada) — nesse
    caso não faz nada."""
    partes = _analisar(id_remoto)
    if partes is None:
        return
    fisico_remoto, logico_remoto, _maquina_remota = partes

    global _fisico, _logico
    with _lock:
        agora = _microssegundos_agora()
        maior_conhecido = max(_fisico, fisico_remoto, agora)
        if maior_conhecido == _fisico == fisico_remoto:
            _logico = max(_logico, logico_remoto) + 1
        elif maior_conhecido == _fisico:
            _logico += 1
        elif maior_conhecido == fisico_remoto:
            _logico = logico_remoto + 1
        else:
            _logico = 0
        _fisico = maior_conhecido


def _analisar(id_evento):
    """(fisico, logico, maquina) a partir da string de id, ou None se
    `id_evento` não tiver o formato esperado (vazio, None, ou registro
    antigo/migrado incorretamente)."""
    if not id_evento or not isinstance(id_evento, str):
        return None
    partes = id_evento.split("-", 2)
    if len(partes) != 3:
        return None
    fisico_str, logico_str, maquina = partes
    try:
        return int(fisico_str), int(logico_str), maquina
    except ValueError:
        return None


def maquina_do_id(id_evento) -> str:
    """Nome da máquina que gerou `id_evento`, ou "" se o id for vazio/
    malformado (ou for um limiar fictício de `id_para_instante`, que não
    tem máquina). Evita que quem só quer essa informação — a Consulta, pra
    mostrar de onde veio cada comanda — precise conhecer o formato do id."""
    partes = _analisar(id_evento)
    return partes[2] if partes is not None else ""


def mais_novo(id_a, id_b) -> bool:
    """True se `id_a` é estritamente mais recente que `id_b`. Único ponto
    de comparação do projeto — quem usa este módulo nunca deveria comparar
    ids diretamente com `>=`/`>`, pra o formato do id continuar sendo um
    detalhe interno só deste módulo. `None`/""/formato inválido conta como
    "mais antigo que qualquer id real" (cobre registros migrados/antigos
    sem o campo, ou payload de uma máquina ainda não atualizada)."""
    partes_a = _analisar(id_a)
    partes_b = _analisar(id_b)
    if partes_a is None:
        return False
    if partes_b is None:
        return True
    return partes_a > partes_b


def id_para_instante(momento: datetime) -> str:
    """Monta um id "fictício" (desempate lógico zero, sem máquina) a partir
    de um `datetime` arbitrário — usado só para montar limiares de
    comparação na mesma régua dos ids reais (ex: "180 dias atrás", ver
    services/rede/tombstones.py:purgar_antigos), nunca para representar um
    evento de verdade. Máquina vazia ordena antes de qualquer máquina real
    com o mesmo (fisico, logico), o que é o comportamento certo para um
    limiar (nunca precisa vencer um empate de verdade)."""
    fisico = int(momento.timestamp() * 1_000_000)
    return _formatar(fisico, 0, "")
