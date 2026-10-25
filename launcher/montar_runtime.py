"""Monta o runtime do Windows: um Python embutido com as dependências do
sistema já instaladas, empacotado em `runtime-<hash>.zip`.

É o que permite abrir o sistema numa máquina sem Python. O launcher
(launcher/iniciar.py) usa `runtime\\python.exe` em vez de procurar um Python do
sistema, e o preConfig deixa de instalar coisas via pip na hora.

Roda no Windows ou no Linux (CI): as dependências são baixadas já compiladas
para Windows (`pip --platform win_amd64 --only-binary`), então nada aqui
executa o Python embutido. Precisa de internet e do pip do Python que roda o
script.

O hash no nome do arquivo identifica a COMPOSIÇÃO do runtime (versão do Python
+ dependências do pyproject.toml): enquanto ele não muda, as máquinas não
precisam baixar o runtime de novo, mesmo que o código do sistema mude a cada
release. Ver `runtime.json`, que acompanha o zip.

Uso:
    python launcher/montar_runtime.py [--python 3.14.9] [--saida dist-runtime]
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
import urllib.request
import zipfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Incrementar quando mudar ALGO NESTE SCRIPT que altere o conteúdo do runtime
# (ex.: passar a podar arquivos). Entra no hash para forçar o rebuild.
_VERSAO_DO_SCRIPT = 1

_PYTHON_PADRAO = "3.14.9"
_URL_EMBED = "https://www.python.org/ftp/python/{v}/python-{v}-embed-amd64.zip"

# Ambiente de destino para avaliar os marcadores do pyproject
# ("pywin32; sys_platform == 'win32'"): o alvo é Windows, não a máquina que
# monta o runtime.
_AMBIENTE_ALVO = {
    "sys_platform": "win32",
    "platform_system": "Windows",
    "os_name": "nt",
    "platform_machine": "AMD64",
    "implementation_name": "cpython",
}


def _dependencias_do_projeto(versao_python):
    with open(os.path.join(RAIZ, "pyproject.toml"), "rb") as arquivo:
        projeto = tomllib.load(arquivo)["project"]

    from packaging.requirements import Requirement

    ambiente = {
        **_AMBIENTE_ALVO,
        "python_version": ".".join(versao_python.split(".")[:2]),
        "python_full_version": versao_python,
    }
    aplicaveis = []
    for texto in projeto.get("dependencies", []):
        requisito = Requirement(texto)
        if requisito.marker is None or requisito.marker.evaluate(ambiente):
            # Sem o marcador: o pip avaliaria contra a máquina de build
            # (Linux), descartaria o pywin32 e ele ficaria de fora.
            requisito.marker = None
            aplicaveis.append(str(requisito))
    return sorted(aplicaveis)


def _hash_da_composicao(versao_python, dependencias):
    base = json.dumps(
        {"python": versao_python, "deps": dependencias, "script": _VERSAO_DO_SCRIPT},
        sort_keys=True,
    )
    return hashlib.sha256(base.encode()).hexdigest()[:12]


def _baixar(url, destino):
    print(f"Baixando {url}")
    with urllib.request.urlopen(url, timeout=120) as resposta, open(destino, "wb") as arquivo:
        shutil.copyfileobj(resposta, arquivo)


_ENTRADAS_PTH = [
    "Lib\\site-packages",
    "Lib\\site-packages\\win32",
    "Lib\\site-packages\\win32\\lib",
    "Lib\\site-packages\\pythonwin",
]

# O pywin32 acha as DLLs dele (pywin32_system32) pelo pywin32_bootstrap, que o
# pywin32.pth importaria. Sem o .pth, quem faz isso é este sitecustomize.
_SITECUSTOMIZE = (
    "try:\n"
    "    import pywin32_bootstrap  # noqa: F401\n"
    "except ImportError:\n"
    "    pass\n"
)


def _habilitar_site_packages(pasta_runtime):
    """O Python embutido ignora o site-packages por padrão: o `python3NN._pth`
    manda em tudo e traz `import site` comentado. Liga as duas coisas."""
    arquivos = [n for n in os.listdir(pasta_runtime) if n.endswith("._pth")]
    if len(arquivos) != 1:
        raise RuntimeError(f"Esperava um único ._pth em {pasta_runtime}, achei {arquivos}")

    caminho = os.path.join(pasta_runtime, arquivos[0])
    with open(caminho, encoding="utf-8") as arquivo:
        linhas = [linha.rstrip("\n") for linha in arquivo]

    saida = []
    for linha in linhas:
        if linha.strip() == "#import site":
            linha = "import site"
        saida.append(linha)
    # Os .pth de dentro do site-packages (o do pywin32 é o que importa) não
    # são garantidos no modo embutido, então as pastas que o pywin32.pth
    # listaria entram aqui à mão. Antes do "import site", que precisa ser a
    # última linha.
    posicao = saida.index("import site") if "import site" in saida else len(saida)
    for entrada in reversed(_ENTRADAS_PTH):
        if entrada not in saida:
            saida.insert(posicao, entrada)

    with open(caminho, "w", encoding="utf-8", newline="\r\n") as arquivo:
        arquivo.write("\n".join(saida) + "\n")

    with open(os.path.join(pasta_runtime, "sitecustomize.py"), "w", encoding="utf-8") as arquivo:
        arquivo.write(_SITECUSTOMIZE)


def _instalar_dependencias(pasta_runtime, dependencias, versao_python):
    destino = os.path.join(pasta_runtime, "Lib", "site-packages")
    os.makedirs(destino, exist_ok=True)
    subprocess.run(
        [
            sys.executable, "-m", "pip", "install",
            "--target", destino,
            "--platform", "win_amd64",
            "--python-version", ".".join(versao_python.split(".")[:2]),
            "--implementation", "cp",
            "--only-binary=:all:",
            "--no-compile",
            "--disable-pip-version-check",
            *dependencias,
        ],
        check=True,
    )


def _podar(pasta_runtime):
    """Tira o que o sistema não usa e pesa: caches e as `tests` dos pacotes."""
    for pasta, subpastas, _arquivos in os.walk(pasta_runtime):
        for nome in list(subpastas):
            if nome == "__pycache__":
                shutil.rmtree(os.path.join(pasta, nome), ignore_errors=True)
                subpastas.remove(nome)


def _zipar(pasta_runtime, destino_zip):
    with zipfile.ZipFile(destino_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zipado:
        for pasta, _subpastas, arquivos in os.walk(pasta_runtime):
            for nome in sorted(arquivos):
                completo = os.path.join(pasta, nome)
                zipado.write(completo, os.path.relpath(completo, pasta_runtime))


def _sha256(caminho):
    resumo = hashlib.sha256()
    with open(caminho, "rb") as arquivo:
        for bloco in iter(lambda: arquivo.read(1 << 20), b""):
            resumo.update(bloco)
    return resumo.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--python", default=_PYTHON_PADRAO, help="versão do Python embutido (padrão: %(default)s)")
    parser.add_argument("--saida", default=os.path.join(RAIZ, "dist-runtime"), help="pasta onde o zip é gravado")
    args = parser.parse_args()

    dependencias = _dependencias_do_projeto(args.python)
    hash_runtime = _hash_da_composicao(args.python, dependencias)
    print(f"Python {args.python}; dependências: {', '.join(dependencias)}")
    print(f"Hash do runtime: {hash_runtime}")

    os.makedirs(args.saida, exist_ok=True)
    zip_final = os.path.join(args.saida, f"runtime-{hash_runtime}.zip")

    with tempfile.TemporaryDirectory() as temporaria:
        zip_python = os.path.join(temporaria, "python-embed.zip")
        _baixar(_URL_EMBED.format(v=args.python), zip_python)

        pasta_runtime = os.path.join(temporaria, "runtime")
        with zipfile.ZipFile(zip_python) as zipado:
            zipado.extractall(pasta_runtime)

        _habilitar_site_packages(pasta_runtime)
        _instalar_dependencias(pasta_runtime, dependencias, args.python)
        _podar(pasta_runtime)
        # O bootstrap compara este arquivo com o hash do manifesto para saber
        # se o runtime instalado ainda serve (ver launcher/bootstrap.py).
        with open(os.path.join(pasta_runtime, "runtime.hash"), "w", encoding="ascii") as arquivo:
            arquivo.write(hash_runtime + "\n")
        _zipar(pasta_runtime, zip_final)

    manifesto = {
        "runtime_hash": hash_runtime,
        "python": args.python,
        "dependencias": dependencias,
        "arquivo": os.path.basename(zip_final),
        "sha256": _sha256(zip_final),
        "tamanho": os.path.getsize(zip_final),
    }
    with open(os.path.join(args.saida, "runtime.json"), "w", encoding="utf-8") as arquivo:
        json.dump(manifesto, arquivo, indent=2)

    print(f"Pronto: {zip_final} ({manifesto['tamanho'] / 1e6:.0f} MB)")


if __name__ == "__main__":
    main()
