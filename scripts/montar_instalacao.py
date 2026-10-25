"""Monta a árvore que o instalador (launcher/instalador.iss) empacota:

    dist-instalacao/
      SistemaDePedidos.exe
      lib/bootstrap.py  lib/chave_publica.txt
      runtime/          (o zip do montar_runtime.py, extraído)
      versoes/<tag>/    (o app-<tag>.zip da release, extraído)
      atual.json        (aponta para <tag>)

Uso:
    python scripts/montar_instalacao.py --exe SistemaDePedidos.exe \
        --runtime dist-runtime --release dist-release
"""

import argparse
import json
import os
import shutil
import zipfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--exe", required=True)
    parser.add_argument("--runtime", default=os.path.join(RAIZ, "dist-runtime"))
    parser.add_argument("--release", default=os.path.join(RAIZ, "dist-release"))
    parser.add_argument("--saida", default=os.path.join(RAIZ, "dist-instalacao"))
    args = parser.parse_args()

    chave = os.path.join(RAIZ, "launcher", "chave_publica.txt")
    if not os.path.isfile(chave):
        raise SystemExit("Falta launcher/chave_publica.txt (rode: python scripts/assinar_release.py gerar-chaves).")

    shutil.rmtree(args.saida, ignore_errors=True)
    os.makedirs(os.path.join(args.saida, "lib"))
    shutil.copy2(args.exe, os.path.join(args.saida, "SistemaDePedidos.exe"))
    shutil.copy2(os.path.join(RAIZ, "launcher", "bootstrap.py"), os.path.join(args.saida, "lib"))
    shutil.copy2(chave, os.path.join(args.saida, "lib"))

    info = json.load(open(os.path.join(args.runtime, "runtime.json"), encoding="utf-8"))
    with zipfile.ZipFile(os.path.join(args.runtime, info["arquivo"])) as zipado:
        zipado.extractall(os.path.join(args.saida, "runtime"))

    manifesto = json.load(open(os.path.join(args.release, "manifesto.json"), encoding="utf-8"))
    if manifesto.get("runtime", {}).get("hash") != info["runtime_hash"]:
        raise SystemExit("O runtime da release não é o mesmo de --runtime; gere a release com --runtime.")

    tag = manifesto["versao"]
    with zipfile.ZipFile(os.path.join(args.release, manifesto["app"]["arquivo"])) as zipado:
        zipado.extractall(os.path.join(args.saida, "versoes", tag))

    with open(os.path.join(args.saida, "atual.json"), "w", encoding="utf-8") as arquivo:
        json.dump({"ativa": tag, "serie": manifesto["serie"], "anterior": None, "pendente": False, "rejeitadas": []}, arquivo, indent=2)

    print(f"Instalação montada em {args.saida} (versão {tag}).")


if __name__ == "__main__":
    main()
