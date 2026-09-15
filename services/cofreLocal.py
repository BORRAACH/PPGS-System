"""Chave local de armazenamento: cifra, em disco, o que só esta máquina deve
conseguir ler — a chave da malha (services/rede/seguranca.py) e o cadastro de
clientes (services/rede/clientes.py).

POR QUE UMA CHAVE SEPARADA, E NÃO A DA MALHA. A chave da malha é igual em todas
as máquinas pareadas e precisa, ela mesma, ser guardada em disco; cifrar o disco
com ela seria trancar o cofre deixando a chave colada na porta. Esta aqui é
aleatória, de cada máquina, e quem a guarda é o sistema operacional:

- Windows: DPAPI (CryptProtectData), amarrada à conta do Windows. O arquivo
  `Config/chave_local.bin` só abre nesta máquina e nesta conta — copiado para
  um pendrive ou outro computador, não serve para nada.
- Linux: o chaveiro da sessão (libsecret, pelo `secret-tool`).
- Sem nenhum dos dois (docker, Linux sem chaveiro): um arquivo com permissão
  0600 fora da pasta do projeto. Protege contra outro usuário da máquina e
  contra quem copiar só a pasta do sistema, não contra quem levar o disco
  inteiro — e a tela Rede diz isso (ver `protecao`).

O QUE NÃO PROTEGE: um programa malicioso rodando na mesma conta. Ele pede a
chave ao sistema do mesmo jeito que este app pede.

PERDER A CHAVE (Windows reinstalado, conta trocada) torna ilegível o que ela
cifrou. É recuperável por desenho: o cadastro de clientes volta pela malha e a
chave da malha volta pareando de novo. O que NUNCA se faz aqui é gerar uma chave
nova por cima de uma que existe e não abriu — isso destruiria dados que podem
estar só momentaneamente inacessíveis (um chaveiro trancado, por exemplo)."""

import base64
import os
import secrets
import shutil
import subprocess
import threading

from services.rede import caminhos

try:
    from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

    DISPONIVEL = True
except ImportError:  # pragma: no cover - depende do ambiente
    DISPONIVEL = False

_TAMANHO_CHAVE = 32
_TAMANHO_NONCE = 12
# Marca no começo de todo blob cifrado: distingue "não é deste cofre" (arquivo
# de outra versão, lixo) de "é deste cofre mas a chave não abre".
_CABECALHO = b"PPGSC1"
_DADOS_ASSOCIADOS = b"PPGS-cofre-local-v1"

# Como a chave aparece no chaveiro do Linux (`secret-tool lookup` com estes
# pares) — é por eles que ela é achada de novo na abertura seguinte.
_ATRIBUTOS_CHAVEIRO = ["aplicacao", "ppgs-pizzaria", "uso", "chave-local"]
# O secret-tool pode esperar o chaveiro destrancar, e isto roda na abertura do
# app: melhor desistir e cair para o arquivo do que segurar a janela.
_TIMEOUT_CHAVEIRO_S = 8
_CRYPTPROTECT_UI_FORBIDDEN = 0x1

PROTECAO_WINDOWS = "windows"
PROTECAO_CHAVEIRO = "chaveiro"
PROTECAO_ARQUIVO = "arquivo"
PROTECAO_INDISPONIVEL = "indisponivel"


class ErroCofre(Exception):
    """A chave local não pôde ser obtida, ou um blob não abriu com ela."""


_trava = threading.Lock()
_chave = None
_protecao = ""


def _pasta_dados_usuario() -> str:
    raiz = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(raiz, "PPGS")


def _caminho_windows() -> str:
    return os.environ.get("PIZZARIA_COFRE_ARQUIVO") or os.path.join(caminhos.raiz_projeto(), "Config", "chave_local.bin")


def _caminho_arquivo() -> str:
    return os.environ.get("PIZZARIA_COFRE_ARQUIVO") or os.path.join(_pasta_dados_usuario(), "chave_local")


def _caminho_marca() -> str:
    """Onde se anota qual mecanismo guardou a chave no Linux. Sem esta marca,
    um chaveiro que num dia não responde (trancado) faria o app criar uma chave
    nova no arquivo — e tudo o que a chave do chaveiro cifrou ficaria órfão."""
    return os.path.join(_pasta_dados_usuario(), "chave_local.origem")


def _gravar_atomico(caminho: str, conteudo: bytes) -> None:
    os.makedirs(os.path.dirname(caminho), exist_ok=True)
    temporario = f"{caminho}.{os.getpid()}.tmp"
    descritor = os.open(temporario, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descritor, "wb") as arquivo:
        arquivo.write(conteudo)
    os.replace(temporario, caminho)


# ---------- Windows ----------

def _chave_windows() -> bytes:
    import win32crypt

    caminho = _caminho_windows()
    if os.path.isfile(caminho):
        with open(caminho, "rb") as arquivo:
            blob = arquivo.read()
        try:
            _descricao, chave = win32crypt.CryptUnprotectData(blob, None, None, None, _CRYPTPROTECT_UI_FORBIDDEN)
        except Exception as erro:
            raise ErroCofre(
                f"o Windows não abriu {caminho} ({erro}) — ela foi criada em outra conta ou em outra instalação"
            ) from erro
        chave = bytes(chave)
        if len(chave) != _TAMANHO_CHAVE:
            raise ErroCofre(f"{caminho} guarda uma chave com tamanho inválido")
        return chave

    chave = secrets.token_bytes(_TAMANHO_CHAVE)
    blob = win32crypt.CryptProtectData(chave, "PPGS chave local", None, None, None, _CRYPTPROTECT_UI_FORBIDDEN)
    _gravar_atomico(caminho, bytes(blob))
    print("[cofreLocal] Chave local criada e protegida pelo Windows (DPAPI).")
    return chave


# ---------- Linux ----------

def _secret_tool(*argumentos, entrada=None):
    ferramenta = shutil.which("secret-tool")
    if not ferramenta:
        return None
    try:
        return subprocess.run(
            [ferramenta, *argumentos],
            input=entrada,
            capture_output=True,
            text=True,
            timeout=_TIMEOUT_CHAVEIRO_S,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def _decodificar(texto: str) -> bytes:
    try:
        chave = base64.b64decode(texto.strip())
    except ValueError as erro:
        raise ErroCofre(f"chave local ilegível ({erro})") from erro
    if len(chave) != _TAMANHO_CHAVE:
        raise ErroCofre("chave local com tamanho inválido")
    return chave


def _ler_marca() -> str:
    try:
        with open(_caminho_marca(), "r", encoding="utf-8") as arquivo:
            return arquivo.read().strip()
    except OSError:
        return ""


def _gravar_marca(origem: str) -> None:
    try:
        _gravar_atomico(_caminho_marca(), origem.encode("utf-8"))
    except OSError as erro:
        print(f"[cofreLocal] Não foi possível anotar a origem da chave local: {erro}")


def _chave_linux():
    arquivo_forcado = bool(os.environ.get("PIZZARIA_COFRE_ARQUIVO"))
    marca = "" if arquivo_forcado else _ler_marca()

    if not arquivo_forcado and marca != PROTECAO_ARQUIVO:
        consulta = _secret_tool("lookup", *_ATRIBUTOS_CHAVEIRO)
        if consulta is not None and consulta.returncode == 0 and consulta.stdout.strip():
            return _decodificar(consulta.stdout), PROTECAO_CHAVEIRO
        if marca == PROTECAO_CHAVEIRO:
            raise ErroCofre("a chave local está no chaveiro da sessão, mas ele não a entregou (trancado?)")

        chave = secrets.token_bytes(_TAMANHO_CHAVE)
        gravacao = _secret_tool(
            "store", "--label=PPGS - chave local", *_ATRIBUTOS_CHAVEIRO,
            entrada=base64.b64encode(chave).decode("ascii"),
        )
        if gravacao is not None and gravacao.returncode == 0:
            # Confere lendo de volta: um `store` que "deu certo" num chaveiro sem
            # sessão pode não ter guardado nada, e descobrir isso na próxima
            # abertura seria perder o que foi cifrado nesta.
            conferencia = _secret_tool("lookup", *_ATRIBUTOS_CHAVEIRO)
            if conferencia is not None and conferencia.returncode == 0:
                try:
                    if _decodificar(conferencia.stdout) == chave:
                        _gravar_marca(PROTECAO_CHAVEIRO)
                        print("[cofreLocal] Chave local criada e guardada no chaveiro da sessão.")
                        return chave, PROTECAO_CHAVEIRO
                except ErroCofre:
                    pass

    caminho = _caminho_arquivo()
    if os.path.isfile(caminho):
        with open(caminho, "r", encoding="utf-8") as arquivo:
            return _decodificar(arquivo.read()), PROTECAO_ARQUIVO

    chave = secrets.token_bytes(_TAMANHO_CHAVE)
    _gravar_atomico(caminho, base64.b64encode(chave))
    try:
        os.chmod(caminho, 0o600)
    except OSError:
        pass
    if not arquivo_forcado:
        _gravar_marca(PROTECAO_ARQUIVO)
    print(
        f"[cofreLocal] AVISO: sem chaveiro do sistema — chave local guardada em {caminho} (permissão 0600). "
        "Protege contra outros usuários desta máquina, não contra quem levar o disco."
    )
    return chave, PROTECAO_ARQUIVO


# ---------- API ----------

def _obter() -> bytes:
    global _chave, _protecao
    with _trava:
        if _chave is None:
            if os.name == "nt":
                _chave, _protecao = _chave_windows(), PROTECAO_WINDOWS
            else:
                _chave, _protecao = _chave_linux()
        return _chave


def cifrar(dados: bytes) -> bytes:
    if not DISPONIVEL:
        raise ErroCofre("biblioteca 'cryptography' indisponível")
    nonce = secrets.token_bytes(_TAMANHO_NONCE)
    return _CABECALHO + nonce + ChaCha20Poly1305(_obter()).encrypt(nonce, bytes(dados), _DADOS_ASSOCIADOS)


def decifrar(blob: bytes) -> bytes:
    if not DISPONIVEL:
        raise ErroCofre("biblioteca 'cryptography' indisponível")
    blob = bytes(blob or b"")
    if not blob.startswith(_CABECALHO) or len(blob) <= len(_CABECALHO) + _TAMANHO_NONCE:
        raise ErroCofre("conteúdo não foi cifrado por este cofre")
    inicio = len(_CABECALHO)
    nonce = blob[inicio:inicio + _TAMANHO_NONCE]
    try:
        return ChaCha20Poly1305(_obter()).decrypt(nonce, blob[inicio + _TAMANHO_NONCE:], _DADOS_ASSOCIADOS)
    except ErroCofre:
        raise
    except Exception as erro:
        raise ErroCofre("não abriu com a chave local desta máquina (outra instalação, ou dado adulterado)") from erro


def protecao() -> str:
    """Qual mecanismo guarda a chave local: "windows", "chaveiro", "arquivo" ou
    "indisponivel" — para a tela Rede avisar quando a proteção é reduzida."""
    try:
        _obter()
    except ErroCofre as erro:
        print(f"[cofreLocal] Chave local indisponível: {erro}")
        return PROTECAO_INDISPONIVEL
    return _protecao
