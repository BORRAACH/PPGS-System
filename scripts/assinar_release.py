"""Empacota e assina uma release do sistema (usado pelo workflow de release,
mas roda igual na sua máquina).

    python scripts/assinar_release.py gerar-chaves
        Gera o par Ed25519. Imprime a CHAVE PRIVADA (base64) uma única vez —
        guarde no secret PIZZARIA_CHAVE_ASSINATURA do GitHub e em lugar seguro
        — e grava a pública em launcher/chave_publica.txt (essa vai no
        repositório e no instalador).

    python scripts/assinar_release.py empacotar --versao v1.2.0 \
        [--runtime dist-runtime] [--notas "texto"] [--saida dist-release]
        Gera app-<versao>.zip, manifesto.json e manifesto.sig. A chave privada
        vem de PIZZARIA_CHAVE_ASSINATURA (base64).

A chave privada NUNCA entra no repositório: quem a tem decide o que as
máquinas da pizzaria aceitam executar."""

import argparse
import base64
import hashlib
import json
import os
import subprocess
import sys
import time
import zipfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# O que não faz parte do app em produção. `launcher/` fica de fora: é o
# instalador que o leva, e uma versão do app não deve poder trocá-lo.
_EXCLUIR = (
    ".github/", "graphify-out/", "docker/", "design/", "cloned_repositories",
    "launcher/", "scripts/", "dev_watch.py", "CONTEXTO_CLAUDE_WEB.md", "CLAUDE.md",
    ".gitignore",
)


def _sha256(caminho):
    resumo = hashlib.sha256()
    with open(caminho, "rb") as arquivo:
        for bloco in iter(lambda: arquivo.read(1 << 20), b""):
            resumo.update(bloco)
    return resumo.hexdigest()


def gerar_chaves():
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    privada = Ed25519PrivateKey.generate()
    bruto = serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption()
    privada_b64 = base64.b64encode(privada.private_bytes(*bruto)).decode()
    publica_b64 = base64.b64encode(
        privada.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    ).decode()

    destino = os.path.join(RAIZ, "launcher", "chave_publica.txt")
    if os.path.exists(destino):
        sys.exit(f"{destino} já existe — apagar uma chave em uso deixa as máquinas sem atualizar. Remova à mão se for isso mesmo.")
    with open(destino, "w", encoding="ascii") as arquivo:
        arquivo.write(publica_b64 + "\n")

    print(f"Chave pública gravada em {destino}")
    print("\nCHAVE PRIVADA (mostrada só agora — guarde no secret PIZZARIA_CHAVE_ASSINATURA):\n")
    print(privada_b64)


def _arquivos_do_app():
    saida = subprocess.run(["git", "ls-files", "-z"], cwd=RAIZ, capture_output=True, check=True).stdout
    for caminho in saida.decode("utf-8").split("\0"):
        if caminho and not caminho.startswith(_EXCLUIR) and caminho not in _EXCLUIR:
            yield caminho


def empacotar(args):
    from cryptography.hazmat.primitives import serialization  # noqa: F401
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    chave_b64 = os.environ.get("PIZZARIA_CHAVE_ASSINATURA", "").strip()
    if not chave_b64:
        sys.exit("Defina PIZZARIA_CHAVE_ASSINATURA (chave privada em base64; ver gerar-chaves).")
    privada = Ed25519PrivateKey.from_private_bytes(base64.b64decode(chave_b64))

    os.makedirs(args.saida, exist_ok=True)
    zip_app = os.path.join(args.saida, f"app-{args.versao}.zip")
    with zipfile.ZipFile(zip_app, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zipado:
        for caminho in _arquivos_do_app():
            zipado.write(os.path.join(RAIZ, caminho), caminho)

    manifesto = {
        "versao": args.versao,
        "serie": args.serie,
        "notas": args.notas,
        "app": {"arquivo": os.path.basename(zip_app), "sha256": _sha256(zip_app), "tamanho": os.path.getsize(zip_app)},
    }

    if args.runtime:
        info = json.load(open(os.path.join(args.runtime, "runtime.json"), encoding="utf-8"))
        origem = os.path.join(args.runtime, info["arquivo"])
        destino = os.path.join(args.saida, info["arquivo"])
        if os.path.abspath(origem) != os.path.abspath(destino):
            with open(origem, "rb") as de, open(destino, "wb") as para:
                para.write(de.read())
        manifesto["runtime"] = {
            "hash": info["runtime_hash"], "arquivo": info["arquivo"],
            "sha256": info["sha256"], "tamanho": info["tamanho"],
        }

    # Os bytes gravados em disco são os assinados: o launcher verifica a
    # assinatura sobre o arquivo como baixou, sem reserializar.
    conteudo = json.dumps(manifesto, indent=2, ensure_ascii=False).encode("utf-8")
    with open(os.path.join(args.saida, "manifesto.json"), "wb") as arquivo:
        arquivo.write(conteudo)
    with open(os.path.join(args.saida, "manifesto.sig"), "w", encoding="ascii") as arquivo:
        arquivo.write(base64.b64encode(privada.sign(conteudo)).decode() + "\n")

    print(f"Release {args.versao} (série {args.serie}) em {args.saida}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="comando", required=True)
    sub.add_parser("gerar-chaves")
    emp = sub.add_parser("empacotar")
    emp.add_argument("--versao", required=True)
    emp.add_argument("--serie", type=int, default=int(time.time()), help="número que só cresce (padrão: agora)")
    emp.add_argument("--notas", default="")
    emp.add_argument("--runtime", help="pasta com runtime.json e o zip (saída do montar_runtime.py)")
    emp.add_argument("--saida", default=os.path.join(RAIZ, "dist-release"))
    args = parser.parse_args()
    gerar_chaves() if args.comando == "gerar-chaves" else empacotar(args)


if __name__ == "__main__":
    main()
