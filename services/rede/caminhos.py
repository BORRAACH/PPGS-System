"""Caminhos e leitura/escrita de JSON compartilhados pelos módulos de
sincronização (services/rede/*).

Existe por causa de um bug real: cada módulo daqui calculava a raiz do
projeto por conta própria contando `os.path.dirname` a partir do próprio
`__file__`, e `RedeService._pasta_pedidos()` ficou com um `dirname` a menos
quando `redeService.py` foi movido de `services/` para `services/rede/`
(commit d8503d0). Ele passou a apontar para `<raiz>/services/pedidos`, que
não existe — e como `_listar_arquivos_locais()` devolve `[]` quando a pasta
não existe, a falha foi silenciosa: o catch-up de handshake
(meus_arquivos/pedir_arquivo) parou de replicar qualquer comanda, sem um
único erro no log. Com o cálculo num lugar só, mover um arquivo de pasta
não pode mais quebrar isso.

`salvar_json` grava por arquivo temporário + os.replace: o processo pode ser
fechado no meio de uma escrita (a pizzaria desliga a máquina no fim do
expediente), e um índice de sincronização truncado é pior que um
desatualizado — ele some com a informação de quais comandas já foram
replicadas."""

import json
import os


def raiz_projeto() -> str:
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def pasta_pedidos() -> str:
    """Pasta com as comandas (.txt) — a mesma que ConsultaController,
    FechamentoController e SalaoController usam."""
    return os.path.join(raiz_projeto(), "pedidos")


def pasta_sincronizacao() -> str:
    """`pedidos/.sync/`: metadados de sincronização (tombstones, índice de
    eventos, conflitos). Fica dentro da árvore de pedidos/ (já fora do git),
    mas fora dos padrões "*.txt" e "mesas/*.json" que os scans existentes
    varrem, então não aparece em nenhum deles."""
    return os.path.join(pasta_pedidos(), ".sync")


def carregar_json(caminho: str, rotulo: str) -> dict:
    """Devolve o dict gravado em `caminho`, ou {} se ele não existir ou
    estiver ilegível/corrompido — nunca levanta. `rotulo` só identifica o
    módulo na mensagem de log."""
    if not os.path.isfile(caminho):
        return {}

    try:
        with open(caminho, "r", encoding="utf-8") as arquivo:
            dados = json.load(arquivo)
    except (OSError, json.JSONDecodeError) as erro:
        print(f"[{rotulo}] Falha ao ler {caminho}: {erro} — assumindo vazio.")
        return {}

    return dados if isinstance(dados, dict) else {}


def salvar_json(caminho: str, dados: dict, rotulo: str) -> None:
    """Grava `dados` de forma atômica (temporário + os.replace)."""
    temporario = caminho + ".tmp"
    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
        with open(temporario, "w", encoding="utf-8") as arquivo:
            json.dump(dados, arquivo, indent=2, ensure_ascii=False)
        os.replace(temporario, caminho)
    except OSError as erro:
        print(f"[{rotulo}] Falha ao gravar {caminho}: {erro}")
        try:
            os.remove(temporario)
        except OSError:
            pass
