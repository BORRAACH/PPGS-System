"""Diagnóstico das impressoras instaladas no sistema. Rode com:

    python -m services.printer
"""

from services.printer import InfoImpressora, coletar_informacoes_impressoras


def _imprimir_relatorio(impressoras: list[InfoImpressora]):
    if not impressoras:
        print("Nenhuma impressora encontrada.")
        return

    for impressora in impressoras:
        print("-" * 40)
        print(f"Nome: {impressora.nome}")
        print(f"Modelo/driver: {impressora.modelo or '(desconhecido)'}")
        print(f"Fabricante: {impressora.fabricante or '(desconhecido)'}")
        print(f"Porta: {impressora.porta or '(desconhecida)'}")
        print(f"Tipo de porta: {impressora.tipo_porta}")
        print(f"Status: {impressora.status or '(desconhecido)'}")
        print(f"Impressora padrão do sistema: {'sim' if impressora.padrao else 'não'}")


if __name__ == "__main__":
    _imprimir_relatorio(coletar_informacoes_impressoras())
