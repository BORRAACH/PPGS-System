"""Onde ficam o código do sistema e onde ficam os dados dele.

São duas raízes porque têm vidas diferentes. O código (main.py, qml/,
services/...) é trocado inteiro a cada atualização; os dados (pedidos/, logs/,
data/cardapio/, as chaves e preferências de Config/) são da máquina e
precisam sobreviver a essa troca. Com tudo misturado numa pasta só, instalar
uma versão nova significaria apagar as comandas do dia.

Por padrão as duas são a MESMA pasta (a raiz do projeto): é o checkout de
desenvolvimento e o de produção por git de hoje, e nada muda para eles. Para
separar, defina PIZZARIA_DADOS com a pasta de dados — é o que o instalador do
Windows faz, apontando para %LOCALAPPDATA%.

Nenhum módulo deve montar caminho de dados a partir do próprio `__file__`:
um `dirname` a mais ou a menos já fez a replicação de comandas parar sem
nenhum erro no log (ver services/rede/caminhos.py)."""

import os
import shutil

RAIZ_CODIGO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# O que mora em data/ e é editado em tempo de execução (tela Cardápio) mas
# vem de série no código: copiado para a pasta de dados na primeira execução.
_SEMENTES = [os.path.join("data", "cardapio")]


def _resolver_raiz_dados() -> str:
    pasta = os.environ.get("PIZZARIA_DADOS", "").strip()
    return os.path.abspath(pasta) if pasta else RAIZ_CODIGO


RAIZ_DADOS = _resolver_raiz_dados()


def codigo(*partes: str) -> str:
    """Caminho dentro da pasta do código (somente leitura em produção)."""
    return os.path.join(RAIZ_CODIGO, *partes)


def dados(*partes: str) -> str:
    """Caminho dentro da pasta de dados da máquina (gravável)."""
    return os.path.join(RAIZ_DADOS, *partes)


def dados_separados() -> bool:
    return RAIZ_DADOS != RAIZ_CODIGO


def semear_dados() -> None:
    """Copia para a pasta de dados o que o código traz de série e ainda não
    existe lá. Nunca sobrescreve: o que já está na pasta de dados foi editado
    pelo usuário (ou sincronizado pela malha) e vale mais que a cópia de série.
    Não faz nada quando código e dados são a mesma pasta."""
    if not dados_separados():
        return

    for relativo in _SEMENTES:
        origem = codigo(relativo)
        if not os.path.isdir(origem):
            continue

        for pasta, _subpastas, arquivos in os.walk(origem):
            destino_pasta = dados(os.path.relpath(pasta, RAIZ_CODIGO))
            try:
                os.makedirs(destino_pasta, exist_ok=True)
                for nome in arquivos:
                    destino = os.path.join(destino_pasta, nome)
                    if not os.path.exists(destino):
                        shutil.copy2(os.path.join(pasta, nome), destino)
            except OSError as erro:
                print(f"[caminhos] Falha ao semear {destino_pasta}: {erro}")
