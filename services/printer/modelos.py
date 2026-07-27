from dataclasses import dataclass, field
from typing import Any


@dataclass
class InfoImpressora:
    """Informações normalizadas de uma impressora instalada no sistema.

    `tipo_porta` é sempre um de: "usb", "serial", "rede", "desconhecido".

    `disponivel` distingue "instalada com uma porta usb/serial" de
    "fisicamente conectada e respondendo agora" — uma impressora usb
    instalada uma vez fica registrada no SO com esse tipo de porta pra
    sempre, mesmo desconectada (ver services/printer/windows.py:WorkOffline
    e services/printer/linux.py:_dispositivos_conectados_agora). Só conta
    pra eleição de quem imprime na malha quando True — ver o comentário em
    RedeService._detectar_impressora_em_thread.

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
