"""Inicializador da instalação empacotada do Windows.

Roda com o Python embutido (runtime\\pythonw.exe lib\\bootstrap.py), chamado
pelo SistemaDePedidos.exe (launcher/iniciar.py). Faz, nesta ordem:

  1. procura uma versão nova (manifesto assinado no GitHub Releases);
  2. se houver e o usuário aceitar: baixa, confere assinatura e hash, instala
     em versoes\\<tag>\\ e passa a ser a versão ativa;
  3. abre o main.py da versão ativa e fica esperando;
  4. se uma versão recém-instalada morrer logo ao abrir, volta para a anterior.

Estrutura da instalação (INSTALACAO = pasta acima de lib\\):
    SistemaDePedidos.exe   lib\\bootstrap.py   lib\\chave_publica.txt
    runtime\\   versoes\\<tag>\\   atual.json
Os dados do usuário (pedidos, cardápio, chaves, logs) NÃO ficam aí: vão para
PIZZARIA_DADOS (padrão %LOCALAPPDATA%\\PizzariaSistema), que sobrevive às trocas
de versão (ver Config/caminhos.py).

Regra de ouro: nada aqui impede o sistema de abrir. Sem internet, sem chave
pública, assinatura inválida, disco cheio — tudo vira log e "abre a versão
instalada". Só não há o que abrir se nenhuma versão chegou a ser instalada.

Usa só a biblioteca padrão, mais `cryptography` (que está no runtime) para
verificar a assinatura Ed25519.

Códigos de saída: 0 normal; 1 erro; 75 = "troquei o runtime, abra-me de novo"
(o launcher faz a troca de pastas, porque este processo roda dentro dele).
"""

import argparse
import base64
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import traceback
import urllib.request
import zipfile

TITULO = "Sistema de Pedidos"

# Versão do contrato launcher<->manifesto. O manifesto pode exigir um mínimo
# (campo "launcher_minimo") quando uma release depender de algo que só um
# instalador novo traz.
API_LAUNCHER = 1

COD_REINICIAR = 75

_URL_BASE_PADRAO = "https://github.com/BORRAACH/PPGS-System/releases/latest/download"
_TIMEOUT_MANIFESTO = 6
_TIMEOUT_DOWNLOAD = 60
# Quanto tempo uma versão recém-instalada precisa ficar de pé para ser dada
# como boa. Abaixo disso, e saindo com erro, é tratada como quebrada.
_SEGUNDOS_PARA_CONFIRMAR = 20
_TAMANHO_MAXIMO_PACOTE = 400 * 1024 * 1024

_TAG_VALIDA = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
_ARQUIVO_VALIDO = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
_SHA256_VALIDO = re.compile(r"^[0-9a-f]{64}$")

# Executa o main.py da versão como se fosse `python main.py`. Precisa disso em
# vez de passar o script direto: o Python embutido (modo ._pth) não coloca a
# pasta do script no sys.path, e o app importa Config, services, controllers.
_CODIGO_ENTRADA = (
    "import runpy, sys\n"
    "pasta = sys.argv[1]\n"
    "sys.path.insert(0, pasta)\n"
    "sys.argv = [pasta + '/main.py']\n"
    "runpy.run_path(sys.argv[0], run_name='__main__')\n"
)

LIB = os.path.dirname(os.path.abspath(__file__))
INSTALACAO = os.path.dirname(LIB)


# ---------------------------------------------------------------- utilidades


def pasta_dados():
    explicita = os.environ.get("PIZZARIA_DADOS", "").strip()
    if explicita:
        return os.path.abspath(explicita)
    base = os.environ.get("LOCALAPPDATA") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(base, "PizzariaSistema")


def log(texto):
    """Grava em <dados>\\logs\\launcher.log. O pythonw não tem console, então
    sem isto uma falha aqui não deixaria rastro nenhum."""
    linha = f"{time.strftime('%Y-%m-%d %H:%M:%S')} {texto}"
    try:
        pasta = os.path.join(pasta_dados(), "logs")
        os.makedirs(pasta, exist_ok=True)
        caminho = os.path.join(pasta, "launcher.log")
        if os.path.exists(caminho) and os.path.getsize(caminho) > 512 * 1024:
            os.replace(caminho, caminho + ".1")
        with open(caminho, "a", encoding="utf-8") as arquivo:
            arquivo.write(linha + "\n")
    except OSError:
        pass
    if sys.stdout is not None:
        try:
            print(linha)
        except OSError:
            pass


def mensagem(texto, erro=False):
    """Caixa do Windows (só informa). Fora do Windows, só o log."""
    log(f"[aviso] {texto}")
    if sys.platform != "win32":
        return
    try:
        import ctypes

        ctypes.windll.user32.MessageBoxW(None, texto, TITULO, 0x10 if erro else 0x40)
    except Exception:
        pass


def perguntar_sim_nao(texto):
    """Caixa Sim/Não. Fora do Windows (testes), PIZZARIA_RESPOSTA_ATUALIZAR."""
    if sys.platform != "win32":
        return os.environ.get("PIZZARIA_RESPOSTA_ATUALIZAR", "").lower() == "sim"
    try:
        import ctypes

        # 0x24 = MB_YESNO | MB_ICONQUESTION; 6 = IDYES
        return ctypes.windll.user32.MessageBoxW(None, texto, TITULO, 0x24) == 6
    except Exception:
        return False


def ler_json(caminho, padrao=None):
    try:
        with open(caminho, encoding="utf-8") as arquivo:
            dados = json.load(arquivo)
        return dados if isinstance(dados, dict) else padrao
    except (OSError, ValueError):
        return padrao


def gravar_json_atomico(caminho, dados):
    temporario = f"{caminho}.{os.getpid()}.tmp"
    with open(temporario, "w", encoding="utf-8") as arquivo:
        json.dump(dados, arquivo, indent=2)
    os.replace(temporario, caminho)


def caminho_atual():
    return os.path.join(INSTALACAO, "atual.json")


def ler_atual():
    return ler_json(caminho_atual(), {}) or {}


def pasta_versao(tag):
    return os.path.join(INSTALACAO, "versoes", tag)


def configuracao():
    return ler_json(os.path.join(LIB, "config.json"), {}) or {}


def hash_runtime_instalado():
    try:
        with open(os.path.join(INSTALACAO, "runtime", "runtime.hash"), encoding="utf-8") as arquivo:
            return arquivo.read().strip()
    except OSError:
        return ""


def python_do_app():
    """Interpretador que roda o app. pythonw: sem a janela preta de console."""
    explicito = os.environ.get("PIZZARIA_PYTHON")
    if explicito:
        return explicito
    for nome in ("pythonw.exe", "python.exe"):
        candidato = os.path.join(INSTALACAO, "runtime", nome)
        if os.path.isfile(candidato):
            return candidato
    return sys.executable


# ------------------------------------------------------ manifesto e assinatura


def carregar_chave_publica():
    try:
        with open(os.path.join(LIB, "chave_publica.txt"), encoding="ascii") as arquivo:
            return base64.b64decode(arquivo.read().strip(), validate=True)
    except (OSError, ValueError):
        return None


def assinatura_valida(conteudo, assinatura_b64, chave_publica):
    """Ed25519 sobre os bytes EXATOS do manifesto (não sobre o JSON reler/reserializado)."""
    try:
        from cryptography.exceptions import InvalidSignature
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

        Ed25519PublicKey.from_public_bytes(chave_publica).verify(
            base64.b64decode(assinatura_b64.strip(), validate=True), conteudo
        )
        return True
    except (InvalidSignature, ValueError, ImportError):
        return False


def _abrir(url, timeout):
    pedido = urllib.request.Request(url, headers={"User-Agent": "SistemaDePedidos-launcher"})
    return urllib.request.urlopen(pedido, timeout=timeout)


def buscar_manifesto(url_base, chave_publica):
    """Devolve o manifesto (dict) já com a assinatura conferida, ou None."""
    try:
        with _abrir(f"{url_base}/manifesto.json", _TIMEOUT_MANIFESTO) as resposta:
            conteudo = resposta.read(1024 * 1024)
        with _abrir(f"{url_base}/manifesto.sig", _TIMEOUT_MANIFESTO) as resposta:
            assinatura = resposta.read(4096).decode("ascii")
    except (OSError, ValueError) as erro:
        log(f"Sem manifesto ({erro}) — seguindo com a versão instalada.")
        return None

    if not assinatura_valida(conteudo, assinatura, chave_publica):
        log("ASSINATURA INVÁLIDA no manifesto — ignorado.")
        return None

    try:
        manifesto = json.loads(conteudo)
        validar_manifesto(manifesto)
    except (ValueError, KeyError, TypeError) as erro:
        log(f"Manifesto malformado ({erro}) — ignorado.")
        return None
    return manifesto


def _validar_pacote(pacote):
    if not _ARQUIVO_VALIDO.match(pacote["arquivo"]):
        raise ValueError(f"nome de arquivo inválido: {pacote['arquivo']!r}")
    if not _SHA256_VALIDO.match(pacote["sha256"]):
        raise ValueError("sha256 inválido")
    if not 0 < int(pacote["tamanho"]) <= _TAMANHO_MAXIMO_PACOTE:
        raise ValueError("tamanho inválido")


def validar_manifesto(manifesto):
    """Mesmo assinado, o manifesto é conferido: ele vira nome de pasta e URL."""
    if not _TAG_VALIDA.match(str(manifesto["versao"])):
        raise ValueError(f"versão inválida: {manifesto['versao']!r}")
    int(manifesto["serie"])
    _validar_pacote(manifesto["app"])
    if manifesto.get("runtime"):
        if not re.match(r"^[0-9a-f]{6,64}$", str(manifesto["runtime"]["hash"])):
            raise ValueError("hash de runtime inválido")
        _validar_pacote(manifesto["runtime"])


# ------------------------------------------------------------ download/instalação


def baixar_verificado(url, destino, sha256, tamanho):
    resumo = hashlib.sha256()
    total = 0
    with _abrir(url, _TIMEOUT_DOWNLOAD) as resposta, open(destino, "wb") as arquivo:
        for bloco in iter(lambda: resposta.read(1 << 20), b""):
            total += len(bloco)
            if total > tamanho:
                raise ValueError("pacote maior que o declarado no manifesto")
            resumo.update(bloco)
            arquivo.write(bloco)
    if total != tamanho or resumo.hexdigest() != sha256:
        raise ValueError("pacote não confere com o hash do manifesto")


def extrair_seguro(caminho_zip, destino):
    """Extrai recusando entradas que escapem de `destino` (zip slip)."""
    raiz = os.path.realpath(destino)
    with zipfile.ZipFile(caminho_zip) as zipado:
        for entrada in zipado.infolist():
            alvo = os.path.realpath(os.path.join(raiz, entrada.filename))
            if alvo != raiz and not alvo.startswith(raiz + os.sep):
                raise ValueError(f"entrada fora da pasta no pacote: {entrada.filename!r}")
        zipado.extractall(raiz)


def _limpar(caminho):
    shutil.rmtree(caminho, ignore_errors=True)


def instalar_runtime(url_base, runtime, temporaria):
    """Deixa o runtime novo em runtime.novo\\ — a troca de pastas é do launcher
    (este processo roda de dentro de runtime\\ e o Windows trava os arquivos)."""
    zip_runtime = os.path.join(temporaria, runtime["arquivo"])
    baixar_verificado(f"{url_base}/{runtime['arquivo']}", zip_runtime, runtime["sha256"], int(runtime["tamanho"]))
    novo = os.path.join(INSTALACAO, "runtime.novo")
    _limpar(novo)
    extrair_seguro(zip_runtime, novo)
    with open(os.path.join(novo, "runtime.hash"), "w", encoding="ascii") as arquivo:
        arquivo.write(runtime["hash"] + "\n")


def instalar_versao(url_base, manifesto):
    """Baixa, confere e instala a versão do manifesto. Devolve True se o
    runtime também foi trocado (precisa reiniciar pelo launcher)."""
    tag = manifesto["versao"]
    os.makedirs(os.path.join(INSTALACAO, "versoes"), exist_ok=True)
    precisa_runtime = bool(manifesto.get("runtime")) and manifesto["runtime"]["hash"] != hash_runtime_instalado()

    with tempfile.TemporaryDirectory(dir=INSTALACAO, prefix="tmp-") as temporaria:
        zip_app = os.path.join(temporaria, manifesto["app"]["arquivo"])
        baixar_verificado(
            f"{url_base}/{manifesto['app']['arquivo']}", zip_app, manifesto["app"]["sha256"], int(manifesto["app"]["tamanho"])
        )
        if precisa_runtime:
            instalar_runtime(url_base, manifesto["runtime"], temporaria)

        parcial = pasta_versao(tag) + ".parcial"
        _limpar(parcial)
        extrair_seguro(zip_app, parcial)
        if not os.path.isfile(os.path.join(parcial, "main.py")):
            _limpar(parcial)
            raise ValueError("pacote sem main.py")
        _limpar(pasta_versao(tag))
        os.replace(parcial, pasta_versao(tag))

    atual = ler_atual()
    gravar_json_atomico(
        caminho_atual(),
        {
            "ativa": tag,
            "serie": int(manifesto["serie"]),
            "anterior": atual.get("ativa"),
            "anterior_serie": atual.get("serie"),
            "pendente": True,
            "rejeitadas": atual.get("rejeitadas", []),
        },
    )
    log(f"Versão {tag} instalada (runtime novo: {precisa_runtime}).")
    return precisa_runtime


def limpar_versoes_antigas():
    atual = ler_atual()
    manter = {atual.get("ativa"), atual.get("anterior")}
    pasta = os.path.join(INSTALACAO, "versoes")
    if not os.path.isdir(pasta):
        return
    for nome in os.listdir(pasta):
        if nome not in manter:
            _limpar(os.path.join(pasta, nome))


def procurar_e_instalar():
    """Passo 1-2. Devolve True se é preciso reiniciar pelo launcher (runtime novo)."""
    atual = ler_atual()
    primeira_vez = not atual.get("ativa") or not os.path.isdir(pasta_versao(atual["ativa"]))

    chave = carregar_chave_publica()
    if chave is None:
        log("Sem lib\\chave_publica.txt — atualizações desligadas.")
        return False

    url_base = (configuracao().get("url_base") or _URL_BASE_PADRAO).rstrip("/")
    manifesto = buscar_manifesto(url_base, chave)
    if manifesto is None:
        if primeira_vez:
            mensagem(
                "Não consegui baixar o sistema. Confira a conexão com a internet e abra o programa de novo.",
                erro=True,
            )
        return False

    if int(manifesto.get("launcher_minimo", 1)) > API_LAUNCHER:
        mensagem(
            "Há uma versão nova do sistema, mas ela precisa de um instalador mais recente. "
            "Peça o instalador atualizado."
        )
        return False

    # Série só cresce: um manifesto antigo (e legitimamente assinado) servido
    # de novo por alguém no caminho não pode fazer a máquina voltar atrás.
    if not primeira_vez:
        if int(manifesto["serie"]) <= int(atual.get("serie") or 0):
            return False
        if int(manifesto["serie"]) in (atual.get("rejeitadas") or []):
            log(f"Versão {manifesto['versao']} já falhou nesta máquina — não oferecida de novo.")
            return False
        notas = str(manifesto.get("notas", "")).strip()[:600]
        texto = f"Há uma versão nova do sistema ({manifesto['versao']}).\n\n"
        if notas:
            texto += notas + "\n\n"
        texto += "Atualizar agora?"
        if not perguntar_sim_nao(texto):
            log("Atualização recusada pelo usuário.")
            return False

    try:
        reiniciar = instalar_versao(url_base, manifesto)
    except Exception as erro:
        log(f"Falha ao instalar {manifesto['versao']}: {erro}\n{traceback.format_exc()}")
        if primeira_vez:
            mensagem("Não consegui instalar o sistema. Tente de novo mais tarde.", erro=True)
        else:
            mensagem("Não consegui instalar a atualização. O sistema abrirá na versão atual.")
        return False

    limpar_versoes_antigas()
    return reiniciar


# --------------------------------------------------------------------- execução


def _marcar_confirmada():
    atual = ler_atual()
    if atual.get("pendente"):
        atual["pendente"] = False
        gravar_json_atomico(caminho_atual(), atual)
        log(f"Versão {atual.get('ativa')} confirmada.")


def _reverter():
    """Volta para a versão anterior. Devolve True se conseguiu."""
    atual = ler_atual()
    anterior = atual.get("anterior")
    if not anterior or not os.path.isfile(os.path.join(pasta_versao(anterior), "main.py")):
        return False
    rejeitadas = list(atual.get("rejeitadas") or [])
    if atual.get("serie") is not None:
        rejeitadas.append(int(atual["serie"]))
    gravar_json_atomico(
        caminho_atual(),
        {
            "ativa": anterior,
            "serie": atual.get("anterior_serie") or 0,
            "anterior": None,
            "pendente": False,
            "rejeitadas": rejeitadas[-10:],
        },
    )
    log(f"Versão {atual.get('ativa')} quebrou ao abrir — voltando para {anterior}.")
    return True


def executar_app():
    """Passo 3-4. Devolve o código de saída do app."""
    atual = ler_atual()
    tag = atual.get("ativa")
    if not tag or not os.path.isfile(os.path.join(pasta_versao(tag), "main.py")):
        mensagem("Nenhuma versão do sistema está instalada. Reinstale o programa.", erro=True)
        return 1

    pasta = pasta_versao(tag)
    ambiente = {
        **os.environ,
        "PIZZARIA_DADOS": pasta_dados(),
        "PIZZARIA_EMPACOTADO": "1",
        "PIZZARIA_VERSAO": tag,
    }
    log(f"Abrindo a versão {tag}.")
    inicio = time.monotonic()
    processo = subprocess.Popen([python_do_app(), "-c", _CODIGO_ENTRADA, pasta], cwd=pasta, env=ambiente)

    try:
        codigo = processo.wait(timeout=_SEGUNDOS_PARA_CONFIRMAR)
    except subprocess.TimeoutExpired:
        _marcar_confirmada()
        return processo.wait()

    duracao = time.monotonic() - inicio
    if atual.get("pendente"):
        if codigo != 0:
            log(f"Versão nova saiu com código {codigo} após {duracao:.1f}s.")
            if _reverter():
                mensagem("A versão nova do sistema não abriu. Voltei para a anterior.")
                return executar_app()
            return codigo
        _marcar_confirmada()
    return codigo


# --------------------------------------------------------------------- migração

_MIGRAR_PASTAS = ["pedidos", os.path.join("data", "cardapio")]
_MIGRAR_ARQUIVOS = [
    "chave_malha.json",
    "chave_local.bin",
    "estilo_impressao.json",
    "impressora_fixada.json",
    "localizacao_servidor.json",
]


def migrar_de(antiga):
    """Copia os dados de um checkout/instalação antiga para a pasta de dados.
    Não sobrescreve nada que já exista no destino."""
    destino = pasta_dados()
    if not os.path.isfile(os.path.join(antiga, "main.py")):
        mensagem(f"A pasta {antiga} não parece ser a do sistema antigo (sem main.py). Nada foi copiado.", erro=True)
        return 1

    copiados = 0
    for relativa in _MIGRAR_PASTAS:
        origem = os.path.join(antiga, relativa)
        if os.path.isdir(origem):
            shutil.copytree(origem, os.path.join(destino, relativa), dirs_exist_ok=True,
                            copy_function=lambda o, d: None if os.path.exists(d) else shutil.copy2(o, d))
            copiados += 1
    os.makedirs(os.path.join(destino, "Config"), exist_ok=True)
    for nome in _MIGRAR_ARQUIVOS:
        origem = os.path.join(antiga, "Config", nome)
        alvo = os.path.join(destino, "Config", nome)
        if os.path.isfile(origem) and not os.path.exists(alvo):
            shutil.copy2(origem, alvo)
            copiados += 1
    log(f"Migração de {antiga}: {copiados} itens copiados.")
    return 0


# ------------------------------------------------------------------------- main


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--migrar-de", metavar="PASTA")
    parser.add_argument("--so-atualizar", action="store_true", help="instala o que houver e sai, sem abrir o app")
    args = parser.parse_args(argv)

    try:
        if args.migrar_de:
            return migrar_de(args.migrar_de)

        if procurar_e_instalar():
            return COD_REINICIAR
        if args.so_atualizar:
            return 0
        return executar_app()
    except Exception:
        log(f"Falha inesperada no bootstrap:\n{traceback.format_exc()}")
        # Última tentativa: abrir o que estiver instalado.
        try:
            if not args.so_atualizar:
                return executar_app()
        except Exception:
            log(traceback.format_exc())
        mensagem("O sistema não conseguiu iniciar. Veja logs\\launcher.log.", erro=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
