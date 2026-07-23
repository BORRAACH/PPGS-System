"""Serviço de impressão da comanda na impressora térmica (Bematech MP-4200 TH).

O envio é feito pela fila de impressão já configurada no sistema operacional
(Windows: win32print em modo RAW; Linux: `lp -o raw` via CUPS), não por porta
física direta — então a impressora precisa estar instalada e com o driver
configurado em modo RAW/genérico antes de usar este serviço.
"""

from services.printer import coletar_informacoes_impressoras, enviar_para_impressora


class PrinterService:
    def __init__(self, nome_impressora: str | None = None):
        self.nome_impressora = nome_impressora

    def localizar_impressora(self):
        """Retorna a `InfoImpressora` configurada, ou None se não encontrada.

        Se `nome_impressora` não foi informado, usa a impressora padrão do
        sistema (`padrao=True`), se houver alguma instalada.
        """
        impressoras = coletar_informacoes_impressoras()

        if self.nome_impressora:
            for impressora in impressoras:
                if impressora.nome == self.nome_impressora:
                    return impressora
            return None

        for impressora in impressoras:
            if impressora.padrao:
                return impressora

        return impressoras[0] if impressoras else None

    def imprimir(self, conteudo: bytes) -> None:
        """Envia `conteudo` (bytes crus, já formatados em ESC/POS) para a
        impressora localizada por `localizar_impressora` (a configurada, ou a
        padrão do sistema).

        Levanta `RuntimeError` se nenhuma impressora for encontrada, ou se o
        envio falhar (ver `services.printer.windows`/`.linux` para detalhes).
        """
        impressora = self.localizar_impressora()
        if impressora is None:
            if self.nome_impressora:
                raise RuntimeError(f"Impressora '{self.nome_impressora}' não encontrada.")
            raise RuntimeError("Nenhuma impressora instalada foi encontrada no sistema.")

        enviar_para_impressora(impressora.nome, conteudo)
