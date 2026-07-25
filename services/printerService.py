"""Serviço de impressão da comanda na impressora térmica (Bematech MP-4200 TH).

O envio é feito pela fila de impressão já configurada no sistema operacional
(Windows: win32print em modo RAW; Linux: `lp -o raw` via CUPS), não por porta
física direta — então a impressora precisa estar instalada e com o driver
configurado em modo RAW/genérico antes de usar este serviço.
"""

import re

from services.printer import coletar_informacoes_impressoras, enviar_para_impressora

# ESC/POS "GS V 0" — corte total do papel. A Bematech MP-4200 TH entende
# esse comando quando configurada em modo de emulação ESC/POS (padrão em
# impressoras térmicas de cupom); testado manualmente e confirmado que
# corta o papel de verdade.
_COMANDO_CORTE = b"\x1d\x56\x00"


def _eh_bematech_mp4200th(impressora):
    """Reconhece a Bematech MP-4200 TH pelo nome/fabricante/modelo
    reportados pelo SO. No Linux, a fila costuma estar em modo raw
    genérico (sem PPD), então fabricante/modelo vêm vazios e só o nome da
    fila (ex: "Bematech4200TH") identifica o modelo — por isso os três
    campos são combinados numa busca só, ignorando maiúsculas/pontuação/
    espaços (assim "Bematech MP-4200 TH", "Bematech4200TH" e "MP-4200 TH
    Miniprinter" batem igual)."""
    texto = f"{impressora.nome} {impressora.fabricante} {impressora.modelo}".lower()
    texto_compacto = re.sub(r"[^a-z0-9]", "", texto)
    return "bematech" in texto_compacto and "4200" in texto_compacto


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

        if _eh_bematech_mp4200th(impressora):
            print(f"[PrinterService] '{impressora.nome}' identificada como Bematech MP-4200 TH — anexando corte automático do papel.")
            conteudo = conteudo + _COMANDO_CORTE

        enviar_para_impressora(impressora.nome, conteudo)
