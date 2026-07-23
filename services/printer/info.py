import platform

from .modelos import InfoImpressora

__all__ = ["coletar_informacoes_impressoras"]


def coletar_informacoes_impressoras() -> list[InfoImpressora]:
    """Coleta as impressoras instaladas no sistema operacional atual.

    Detecta automaticamente se está em Windows ou Linux e usa a estratégia
    adequada para cada um (PowerShell/Win32_Printer no Windows, CUPS/lpstat
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
