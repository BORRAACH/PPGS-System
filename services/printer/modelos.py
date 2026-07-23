from dataclasses import dataclass, field
from typing import Any


@dataclass
class InfoImpressora:
    """Informações normalizadas de uma impressora instalada no sistema.

    `tipo_porta` é sempre um de: "usb", "serial", "rede", "desconhecido".
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
    bruto: dict[str, Any] = field(default_factory=dict)
