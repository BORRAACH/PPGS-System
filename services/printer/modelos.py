import re
from dataclasses import dataclass, field
from typing import Any


@dataclass
class InfoImpressora:
    """Informações normalizadas de uma impressora instalada no sistema.

    `tipo_porta` é sempre um de: "usb", "serial", "rede", "desconhecido".

    `disponivel` distingue "instalada com uma porta usb/serial" de "de
    fato conectada, habilitada e ligada agora" — uma impressora usb
    instalada uma vez fica registrada no SO com esse tipo de porta pra
    sempre, mesmo desconectada/desligada (ver
    services/printer/windows.py:WorkOffline/Pausada e
    services/printer/linux.py:_dispositivos_conectados_agora/habilitada
    — no Linux, "habilitada" também serve de proxy pra "ligada", já que o
    CUPS desabilita a fila sozinho quando um job de verdade não consegue
    falar com o hardware). Só conta pra eleição de quem imprime na malha
    quando True — ver o comentário em RedeService._detectar_impressora_em_thread.

    `bruto` guarda os dados originais coletados da plataforma (Windows ou
    Linux), para depuração ou casos em que os campos normalizados não bastem.
    """

    nome: str
    modelo: str = ""
    fabricante: str = ""
    driver: str = ""
    porta: str = ""
    tipo_porta: str = "desconhecido"
    status: str = ""
    padrao: bool = False
    disponivel: bool = True
    bruto: dict[str, Any] = field(default_factory=dict)


def eh_bematech_mp4200th(impressora: InfoImpressora) -> bool:
    """Reconhece a Bematech MP-4200 TH pelo nome/fabricante/modelo
    reportados pelo SO. No Linux, a fila costuma estar em modo raw
    genérico (sem PPD), então fabricante/modelo vêm vazios e só o nome da
    fila (ex: "Bematech4200TH") identifica o modelo — por isso os três
    campos são combinados numa busca só, ignorando maiúsculas/pontuação/
    espaços (assim "Bematech MP-4200 TH", "Bematech4200TH" e "MP-4200 TH
    Miniprinter" batem igual).

    Vive aqui (não em printerService.py, que é quem originalmente definia
    isso) porque services/printer/windows.py também precisa: antes de
    mandar uma consulta de status ESC/POS (DLE EOT) pra uma impressora,
    precisa confirmar que é uma impressora ESC/POS de verdade — mandar
    esses bytes crus pra uma impressora genérica (laser, PDF virtual etc.)
    tem efeito indefinido, incluindo o risco de sair algo impresso, que é
    exatamente o que essa consulta existe pra evitar."""
    texto = f"{impressora.nome} {impressora.fabricante} {impressora.modelo}".lower()
    texto_compacto = re.sub(r"[^a-z0-9]", "", texto)
    if "bematech" in texto_compacto and "4200" in texto_compacto:
        return True
    # Instalada pelo instalador oficial da Bematech (não pelo script de
    # autoconfiguração deste app, o único que nomeia a fila como "Bematech
    # MP-4200 TH"): o nome amigável que o Windows mostra é só o nome do
    # produto, "MP-4200 TH", sem a marca "Bematech" em lugar nenhum —
    # confirmado em campo (título "MP-4200 TH", porta "Bematech_COM3": a
    # marca só aparece no nome da porta, que nem é olhado aqui). "mp4200th"
    # sozinho já é específico o bastante pra não precisar da marca junto.
    return "mp4200th" in texto_compacto
