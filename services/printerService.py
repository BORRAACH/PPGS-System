"""Serviço de impressão da comanda na impressora térmica (Bematech MP-4200 TH).

Ainda não implementado: falta confirmar qual conexão física vai ser usada em
produção (USB, serial ou compartilhamento de rede). Antes de implementar
`imprimir`, use `services.printer.coletar_informacoes_impressoras()` para
descobrir automaticamente nome, porta e tipo de porta das impressoras
instaladas no sistema (Windows ou Linux) e decidir a estratégia de envio.
"""

from services.printer import coletar_informacoes_impressoras


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
        """Envia `conteudo` (bytes crus, já formatados em ESC/POS) para a impressora.

        TODO: implementar o envio de fato depois que a conexão (USB, serial
        ou rede) usada em produção for confirmada:
        - USB/rede compartilhada no Windows: enviar via win32print (RAW) ou
          `copy /b` para a porta/compartilhamento.
        - Serial: abrir a porta (ex. pyserial) com baud rate compatível e
          escrever os bytes diretamente.
        - CUPS (Linux): `lp -d <impressora> -o raw <arquivo>` ou pycups.
        """
        raise NotImplementedError(
            "Envio para a impressora ainda não implementado — falta confirmar "
            "se a conexão em produção será USB, serial ou rede."
        )
