"""Serviço de impressão da comanda na impressora térmica (Bematech MP-4200 TH).

O envio é feito pela fila de impressão já configurada no sistema operacional
(Windows: win32print em modo RAW; Linux: `lp -o raw` via CUPS), não por porta
física direta — então a impressora precisa estar instalada e com o driver
configurado em modo RAW/genérico antes de usar este serviço.
"""

import re

from services import comandaEstiloService as estilo
from services import comandaImagemService
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

# O marcador de tamanho em pixels, do lado de cá já em bytes — é assim que ele
# chega, e converter o conteúdo inteiro pra texto só pra limpá-lo seria trocar
# uma substituição por duas conversões de codepage.
_PADRAO_MARCA_TAMANHO = re.compile(
    re.escape(estilo.MARCA_TAMANHO_PX.encode("ascii")) + rb"\d{3}"
)

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

    def _preparar_conteudo(self, conteudo: bytes) -> bytes:
        """O conteúdo pronto pra ir ao papel: a comanda desenhada como imagem,
        quando há uma fonte configurada, ou o texto ESC/POS de sempre.

        POR QUE A CONVERSÃO É AQUI, e não em quem monta a comanda: o que os
        controllers produzem é o mesmo objeto de bytes que vai pro arquivo
        pedidos/*.txt e pra malha. Esse arquivo é o REGISTRO da comanda — a
        Consulta reabre e edita, o Fechamento tira dele o caixa do dia, a
        comparação entre máquinas confere campo a campo, e a reimpressão
        reenvia o arquivo byte a byte. Todos leem texto cp850. Rasterizar mais
        cedo trocaria o registro por uma imagem e derrubaria os quatro de uma
        vez; aqui, no último instante, o arquivo já foi gravado e replicado, e
        só o que segue pro cabeçote muda.

        O comando de codepage não acompanha a imagem: ele diz à impressora como
        interpretar bytes de TEXTO, e num raster não há nenhum."""
        familia = estilo.fonte_impressao()
        if not familia:
            return _COMANDO_CODEPAGE_CP850 + self._sem_marcadores(conteudo)

        raster = comandaImagemService.para_raster(conteudo, familia)
        if raster is None:
            # Melhor esforço, no espírito de Config/fontes.py: a máquina que
            # imprime pode não ter a fonte que o dono escolheu em outra (o
            # estilo é sincronizado pela malha, as fontes instaladas não).
            # Cupom na fonte errada é contratempo; cupom que não sai é pedido
            # perdido.
            print(f"[PrinterService] Não foi possível desenhar a comanda em '{familia}' — imprimindo em texto.")
            return _COMANDO_CODEPAGE_CP850 + self._sem_marcadores(conteudo)

        print(f"[PrinterService] Comanda desenhada em '{familia}': {len(conteudo)} bytes de texto viraram {len(raster)} bytes de imagem.")
        return raster

    @staticmethod
    def _sem_marcadores(conteudo: bytes) -> bytes:
        """O conteúdo sem os marcadores de tamanho exato (ver
        comandaEstiloService.MARCA_TAMANHO_PX), pro caminho de texto.

        Eles são recado nosso pra quem desenha a comanda, não comando de
        impressora — indo pro papel, sairiam como caracteres soltos no meio do
        cupom ("~048" grudado no nome do cliente). Uma comanda ganha esses
        marcadores quando há fonte escolhida, e ainda assim pode acabar aqui:
        basta a máquina que imprime não ter a fonte, ou o arquivo ser
        reimpresso depois de a fonte ter sido desligada.

        O tamanho não se perde nessa limpeza — o "GS !" com o multiplicador
        continua no texto, ao lado, e é ele que a impressora entende."""
        return _PADRAO_MARCA_TAMANHO.sub(b"", conteudo)

    def imprimir(self, conteudo: bytes) -> None:
        """Envia `conteudo` (bytes crus, já formatados em ESC/POS) para a
        impressora localizada por `localizar_impressora` (a configurada, ou a
        padrão do sistema). Se essa impressora for identificada como uma
        Bematech MP-4200 TH, anexa o comando ESC/POS de corte automático do
        papel ao final do conteúdo antes de enviar.

        Havendo uma fonte configurada, o texto vira imagem antes do envio (ver
        _preparar_conteudo). O espaçamento e o corte valem igual nos dois
        casos: são avanço de papel e lâmina, indiferentes a o que foi impresso
        acima.

        Levanta `RuntimeError` se nenhuma impressora for encontrada, ou se o
        envio falhar (ver `services.printer.windows`/`.linux` para detalhes).
        """
        impressora = self.localizar_impressora()
        if impressora is None:
            if self.nome_impressora:
                raise RuntimeError(f"Impressora '{self.nome_impressora}' não encontrada.")
            raise RuntimeError("Nenhuma impressora instalada foi encontrada no sistema.")

        print(f"[PrinterService] Repassando pedido para '{impressora.nome}' (tipo de porta: {impressora.tipo_porta}, porta: {impressora.porta}).")

        conteudo = self._preparar_conteudo(conteudo)

        if eh_bematech_mp4200th(impressora):
            print(f"[PrinterService] '{impressora.nome}' identificada como Bematech MP-4200 TH — anexando espaçamento e corte automático do papel.")
            conteudo = conteudo + (b"\n" * estilo.linhas_espacamento_corte()) + _COMANDO_CORTE

        enviar_para_impressora(impressora.nome, conteudo)
