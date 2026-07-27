"""Serviço de impressão da comanda na impressora térmica (Bematech MP-4200 TH).

O envio é feito pela fila de impressão já configurada no sistema operacional
(Windows: win32print em modo RAW; Linux: `lp -o raw` via CUPS), não por porta
física direta — então a impressora precisa estar instalada e com o driver
configurado em modo RAW/genérico antes de usar este serviço.
"""

from services import comandaEstiloService as estilo
from services.printer import coletar_informacoes_impressoras, enviar_para_impressora
from services.printer.modelos import eh_bematech_mp4200th

# ESC/POS "GS V 0" — corte total do papel. A Bematech MP-4200 TH entende
# esse comando quando configurada em modo de emulação ESC/POS (padrão em
# impressoras térmicas de cupom); testado manualmente e confirmado que
# corta o papel de verdade.
_COMANDO_CORTE = b"\x1d\x56\x00"

# ESC/POS "ESC t 2" — seleciona a tabela de caracteres PC850 (Multilingual)
# na própria impressora. O texto já é codificado em cp850 antes de chegar
# aqui (ver CODEPAGE_IMPRESSORA em balcaoController.py/entregaController.py),
# mas sem mandar a impressora usar essa MESMA tabela para interpretar os
# bytes 0x80-0xFF, ela usa a tabela padrão de fábrica (normalmente PC437 —
# EUA), que mapeia esses bytes para caracteres diferentes. Resultado sem
# este comando: "ç", "ã", "õ", "á" etc saem trocados/corrompidos no cupom,
# mesmo com o texto certo sendo enviado.
_COMANDO_CODEPAGE_CP850 = b"\x1b\x74\x02"

# A quantidade de linhas em branco inseridas antes do corte é configurável
# (tela Configurações, ver services/comandaEstiloService.py) — sem elas, o
# corte acontece rente à última linha impressa (ex: "Troco a dar"), antes do
# papel avançar de verdade para além da lâmina. Resultado observado: a
# comanda não é cortada de fato, o texto final fica preso sob o cabeçote, e
# só "aparece" (sem corte) quando a PRÓXIMA comanda empurra esse trecho pra
# fora — dando a impressão de que informações de uma comanda vazaram para a
# outra.


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
                    print(f"[PrinterService] Impressora configurada '{self.nome_impressora}' localizada (porta: {impressora.porta}, status: {impressora.status}).")
                    return impressora
            print(f"[PrinterService] Impressora configurada '{self.nome_impressora}' NÃO está entre as instaladas: {[i.nome for i in impressoras]}")
            return None

        for impressora in impressoras:
            if impressora.padrao:
                print(f"[PrinterService] Nenhuma impressora configurada — usando a padrão do sistema: '{impressora.nome}'.")
                return impressora

        if impressoras:
            print(f"[PrinterService] Nenhuma impressora configurada nem padrão — usando a primeira encontrada: '{impressoras[0].nome}'.")
            return impressoras[0]

        print("[PrinterService] Nenhuma impressora instalada foi encontrada no sistema.")
        return None

    def imprimir(self, conteudo: bytes) -> None:
        """Envia `conteudo` (bytes crus, já formatados em ESC/POS) para a
        impressora localizada por `localizar_impressora` (a configurada, ou a
        padrão do sistema). Se essa impressora for identificada como uma
        Bematech MP-4200 TH, anexa o comando ESC/POS de corte automático do
        papel ao final do conteúdo antes de enviar.

        Levanta `RuntimeError` se nenhuma impressora for encontrada, ou se o
        envio falhar (ver `services.printer.windows`/`.linux` para detalhes).
        """
        impressora = self.localizar_impressora()
        if impressora is None:
            if self.nome_impressora:
                raise RuntimeError(f"Impressora '{self.nome_impressora}' não encontrada.")
            raise RuntimeError("Nenhuma impressora instalada foi encontrada no sistema.")

        print(f"[PrinterService] Repassando pedido para '{impressora.nome}' (tipo de porta: {impressora.tipo_porta}, porta: {impressora.porta}).")

        conteudo = _COMANDO_CODEPAGE_CP850 + conteudo

        if eh_bematech_mp4200th(impressora):
            print(f"[PrinterService] '{impressora.nome}' identificada como Bematech MP-4200 TH — anexando espaçamento e corte automático do papel.")
            conteudo = conteudo + (b"\n" * estilo.linhas_espacamento_corte()) + _COMANDO_CORTE

        enviar_para_impressora(impressora.nome, conteudo)
