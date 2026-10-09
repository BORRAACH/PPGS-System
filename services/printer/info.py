import copy
import platform
import threading
import time

from .modelos import InfoImpressora

__all__ = ["coletar_informacoes_impressoras", "invalidar_cache", "enviar_para_impressora"]

# Quanto tempo um resultado da varredura vale para quem não pediu uma nova.
# Varrer é caro (CUPS: 6 subprocessos e até ~6s; Windows: consulta ao spooler) e
# no startup duas threads pediam a mesma varredura ao mesmo tempo (o diagnóstico
# do main.py e a detecção do RedeService) — agora a segunda aproveita a da
# primeira. Menor que o intervalo do timer de detecção, então o ciclo periódico
# sempre varre de verdade.
_VALIDADE_PADRAO_S = 10.0

# Serializa as varreduras: quem chega durante uma em andamento espera por ela e
# usa o resultado dela, em vez de disparar uma segunda igual em paralelo.
_trava = threading.Lock()
_cache = None  # (instante monotônico, lista de InfoImpressora)


def invalidar_cache() -> None:
    """Descarta o resultado guardado — a próxima coleta varre de novo. Para
    quem acabou de mudar as impressoras do sistema (ex: criou a fila)."""
    global _cache
    with _trava:
        _cache = None


def coletar_informacoes_impressoras(max_idade: float = _VALIDADE_PADRAO_S) -> list[InfoImpressora]:
    """As impressoras instaladas, reaproveitando a última varredura se ela tem
    menos de `max_idade` segundos. `max_idade=0` força uma varredura nova (é o
    que o botão "Atualizar" da tela de Rede pede)."""
    global _cache
    with _trava:
        agora = time.monotonic()
        if max_idade > 0 and _cache is not None and agora - _cache[0] <= max_idade:
            return [copy.copy(i) for i in _cache[1]]
        impressoras = _coletar_sem_cache()
        _cache = (time.monotonic(), impressoras)
        return [copy.copy(i) for i in impressoras]


def _coletar_sem_cache() -> list[InfoImpressora]:
    """Coleta as impressoras instaladas no sistema operacional atual.

    Detecta automaticamente se está em Windows ou Linux e usa a estratégia
    adequada para cada um (win32print/Win32_Printer no Windows, CUPS/lpstat
    no Linux). Retorna uma lista de `InfoImpressora`.
    """
    sistema = platform.system()

    if sistema == "Windows":
        from . import windows

        return windows.coletar_impressoras()

    if sistema == "Linux":
        from . import linux

        return linux.coletar_impressoras()

    raise NotImplementedError(
        f"Coleta de informações de impressora não implementada para o sistema '{sistema}'."
    )


def enviar_para_impressora(nome_impressora: str, conteudo: bytes) -> None:
    """Envia `conteudo` (bytes crus, já formatados em ESC/POS) para a fila de
    impressão `nome_impressora`, detectando automaticamente Windows ou Linux.
    """
    sistema = platform.system()

    if sistema == "Windows":
        from . import windows

        return windows.imprimir(nome_impressora, conteudo)

    if sistema == "Linux":
        from . import linux

        return linux.imprimir(nome_impressora, conteudo)

    raise NotImplementedError(
        f"Envio para impressora não implementado para o sistema '{sistema}'."
    )
