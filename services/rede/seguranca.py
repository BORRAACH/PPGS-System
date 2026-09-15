"""Criptografia da malha: a chave por instalação, o pareamento que a entrega a
uma máquina nova e a sessão cifrada entre máquinas pareadas.

QUEM ENTRA NA MALHA. Só máquina pareada. A primeira máquina cria a rede (uma
chave aleatória de 32 bytes, `gerar_chave`); cada máquina seguinte pede para
entrar pela tela Rede, e alguém numa máquina já pareada aprova depois de
conferir que o mesmo código de 6 dígitos aparece nas duas telas (ver
`SessaoPareamento`).

Antes disso a chave era a constante `CHAVE_PADRAO`, igual em toda instalação e
escrita no código-fonte: qualquer instância do app na rede da pizzaria entrava.
Deixou de poder ser assim quando o cadastro de clientes (nome, telefone,
endereço) passou a morar nas próprias máquinas e a viajar pela malha, sem o
servidor separado (ver services/rede/clientes.py). A chave por instalação já
existiu uma vez, com um código base32 transcrito à mão (commit 2b32c7b), e foi
desfeita pelo atrito (195f5bf). A diferença agora é que ninguém digita a chave:
ela viaja cifrada pelo pareamento, e a pessoa só compara seis dígitos.

ONDE A CHAVE FICA. Em `Config/chave_malha.json`, cifrada pelo cofre local
(services/cofreLocal.py), cuja chave o sistema operacional guarda (DPAPI no
Windows). Copiar o arquivo para outra máquina não entrega a chave.

O que a sessão entre máquinas pareadas garante:

1. **Quem não tem a chave não entra.** O handshake fecha num HMAC da chave
   sobre o transcrito; um peer sem ela é recusado antes de qualquer mensagem de
   protocolo.
2. **Quem escuta o fio não lê nada.** Depois do handshake tudo vai selado com
   ChaCha20-Poly1305.
3. **Quem grava o tráfego hoje não o lê amanhã, nem roubando a chave.** O
   segredo de sessão vem de um X25519 efêmero, jogado fora quando o socket
   fecha (forward secrecy).

O que NÃO está coberto: tirar uma máquina da rede. Uma máquina roubada continua
com a chave até a rede inteira trocar de chave, e essa troca ainda não existe.
"""

import base64
import hashlib
import hmac
import json
import os
import secrets
import struct

from services import cofreLocal
from services.rede import caminhos

# Sem `cryptography` não há malha. É uma postura deliberada: cair para um
# modo "sem criptografia" quando a biblioteca falta transformaria um problema
# de instalação numa brecha silenciosa, exatamente do jeito que ninguém
# perceberia. `Config/preConfig.py` instala o pacote automaticamente no
# primeiro boot, então na prática este caminho só acontece em máquina sem
# internet — e aí a tela Rede diz isso com todas as letras.
try:
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
    from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
    from cryptography.hazmat.primitives.kdf.hkdf import HKDF

    DISPONIVEL = True
    ERRO_IMPORT = ""
except ImportError as _erro:  # pragma: no cover - depende do ambiente
    DISPONIVEL = False
    ERRO_IMPORT = str(_erro)


# Sobe junto se o formato do handshake ou do enquadramento mudar de um jeito
# que versões diferentes não consigam conversar. Duas máquinas com versões
# diferentes se recusam explicitamente, em vez de travar num frame que uma
# delas não sabe ler. Foi a 2 com a chave por instalação: uma máquina ainda na
# versão da chave fixa precisa ouvir "atualize", e não "chave errada".
VERSAO_PROTOCOLO = 2


# Teto de um frame selado. A reconciliação (`reconciliar_dados`) pode mandar
# um domínio inteiro de uma vez — o cardápio, o histórico — então o limite
# precisa ser generoso; o que ele existe pra impedir é um peer não
# autenticado anunciar um tamanho absurdo e fazer esta máquina reservar a
# memória antes de ter provado qualquer coisa.
_TAMANHO_MAXIMO_FRAME = 64 * 1024 * 1024

_TAMANHO_CHAVE = 32
_ARQUIVO_CHAVE = "chave_malha.json"
# Formato do arquivo da chave. O 1 (sem este campo) era o código base32 em
# claro da temporada de 2b32c7b; ele é ignorado, nunca lido.
_FORMATO_ARQUIVO_CHAVE = 2

_INFO_SESSAO = b"PPGS-malha-sessao-v1"
_INFO_PAREAMENTO = b"PPGS-pareamento-v1"
_INFO_INDICE_CLIENTES = b"PPGS-clientes-indice-v1"

_ROTULO_CONFIRMACAO = b"PPGS-confirmar-v1"
_DADOS_ASSOCIADOS_CHAVE = b"PPGS-pareamento-chave-v1"

# Tipos das mensagens do pareamento, todas JSON em claro enquadrado — só a
# última (`chave_pareamento`) carrega algo sigiloso, e ela vai cifrada.
TIPO_PEDIDO = "pedido_pareamento"
TIPO_RESPOSTA = "resposta_pareamento"
TIPO_REVELACAO = "revelacao_pareamento"
TIPO_CHAVE = "chave_pareamento"
TIPO_RECUSA = "pareamento_recusado"


class ErroSeguranca(Exception):
    """Falha de handshake ou de abertura de frame. Quem trata fecha o socket
    — nunca há recuperação parcial: um frame que não abre significa chave
    errada, versão incompatível ou adulteração, e nos três casos a única
    resposta correta é desistir daquela conexão."""


# ---------- Chave da malha (por instalação, cifrada pelo cofre local) ----------


def _caminho_chave() -> str:
    # A variável de ambiente existe só para os testes rodarem várias
    # "máquinas" no mesmo computador, cada uma com a sua chave.
    return os.environ.get("PIZZARIA_CHAVE_MALHA_ARQUIVO") or os.path.join(caminhos.raiz_projeto(), "Config", _ARQUIVO_CHAVE)


def carregar_chave() -> bytes | None:
    """A chave desta máquina, ou None enquanto ela não entrou em nenhuma rede.

    Um arquivo que não abre (formato antigo, cofre local de outra instalação)
    também devolve None, com o motivo no log: a saída é parear de novo, e o
    arquivo ilegível é substituído na próxima gravação."""
    dados = caminhos.carregar_json(_caminho_chave(), "chave da malha")
    if not dados:
        return None
    if dados.get("formato") != _FORMATO_ARQUIVO_CHAVE:
        print(f"[seguranca] Config/{_ARQUIVO_CHAVE} é de uma versão antiga (chave em claro) — ignorado. "
              "Esta máquina precisa entrar na rede pela tela Rede.")
        return None
    try:
        chave = cofreLocal.decifrar(base64.b64decode(dados.get("chave") or ""))
    except (cofreLocal.ErroCofre, ValueError) as erro:
        print(f"[seguranca] A chave da malha gravada nesta máquina não abriu ({erro}) — "
              "é preciso entrar na rede de novo pela tela Rede.")
        return None
    if len(chave) != _TAMANHO_CHAVE:
        print("[seguranca] A chave da malha gravada tem tamanho inválido — tratando como sem chave.")
        return None
    return chave


def salvar_chave(chave: bytes) -> None:
    if len(chave) != _TAMANHO_CHAVE:
        raise ErroSeguranca(f"Chave precisa ter {_TAMANHO_CHAVE} bytes.")
    try:
        blob = cofreLocal.cifrar(chave)
    except cofreLocal.ErroCofre as erro:
        raise ErroSeguranca(f"Não foi possível proteger a chave da malha: {erro}") from erro
    caminhos.salvar_json(
        _caminho_chave(),
        {"formato": _FORMATO_ARQUIVO_CHAVE, "chave": base64.b64encode(blob).decode("ascii")},
        "chave da malha",
    )


def gerar_chave() -> bytes:
    """Cria e grava a chave de uma rede nova. Só a PRIMEIRA máquina faz isto;
    as outras recebem a mesma chave pelo pareamento."""
    chave = secrets.token_bytes(_TAMANHO_CHAVE)
    salvar_chave(chave)
    print("[seguranca] Rede criada: chave da malha gerada nesta máquina.")
    return chave


def _derivar(chave: bytes, info: bytes, tamanho: int = 32) -> bytes:
    if not DISPONIVEL:
        raise ErroSeguranca(f"Biblioteca 'cryptography' indisponível: {ERRO_IMPORT}")
    return HKDF(algorithm=hashes.SHA256(), length=tamanho, salt=None, info=info).derive(chave)


def chave_indice_clientes(chave: bytes) -> bytes:
    """Chave do índice cego do cadastro de clientes (ver
    services/rede/clientes.py). Igual em toda máquina pareada — é o que faz o
    mesmo telefone cair na mesma entrada em todas — e desconhecida fora da
    rede. Derivada com `info` próprio: vazá-la não entrega a chave da malha."""
    return _derivar(chave, _INFO_INDICE_CLIENTES)


# ---------- Enquadramento ----------


def enquadrar(payload: bytes) -> bytes:
    """Prefixo de 4 bytes com o tamanho. Substitui o `json + b"\\n"` de antes:
    um frame selado é binário e pode conter 0x0A em qualquer posição, então
    delimitar por newline deixou de ser possível."""
    return struct.pack(">I", len(payload)) + payload


def desenquadrar(buffer: bytearray):
    """Extrai os frames completos do buffer, consumindo-os. Devolve a lista do
    que deu pra ler; o resto fica no buffer esperando mais bytes chegarem."""
    frames = []
    while len(buffer) >= 4:
        (tamanho,) = struct.unpack(">I", bytes(buffer[:4]))
        if tamanho > _TAMANHO_MAXIMO_FRAME:
            raise ErroSeguranca(f"Frame anunciado com {tamanho} bytes, acima do teto de {_TAMANHO_MAXIMO_FRAME}.")
        if len(buffer) < 4 + tamanho:
            break
        frames.append(bytes(buffer[4 : 4 + tamanho]))
        del buffer[: 4 + tamanho]
    return frames


def ler_json(frame: bytes) -> dict:
    """Frame em claro (abertura do handshake ou pareamento) como dict."""
    try:
        mensagem = json.loads(frame.decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as erro:
        raise ErroSeguranca(f"Frame ilegível: {erro}") from erro
    if not isinstance(mensagem, dict):
        raise ErroSeguranca("Frame sem objeto JSON.")
    return mensagem


# ---------- Sessão ----------


class SessaoSegura:
    """Handshake e cifragem de UM socket entre máquinas pareadas.

    Simétrica: os dois lados rodam exatamente o mesmo código, sem papel de
    cliente/servidor. Quem chama só precisa de quatro coisas —
    `frame_inicial()` pra mandar assim que o socket abre, `receber()` pra cada
    frame que chegar, `pronta` pra saber se já dá pra falar protocolo, e
    `selar()`/`abrir()` depois disso.

    O par de chaves é direcional (uma por sentido) pra que um frame gravado
    não possa ser devolvido ao próprio remetente como se fosse resposta. Qual
    lado usa qual é decidido comparando os bytes dos dois frames `ola`: não
    dá empate (os nonces são aleatórios) e os dois lados chegam à mesma
    conclusão sem trocar mais nada.
    """

    def __init__(self, chave_malha: bytes, id_local: str):
        if not DISPONIVEL:
            raise ErroSeguranca(f"Biblioteca 'cryptography' indisponível: {ERRO_IMPORT}")
        if not chave_malha:
            raise ErroSeguranca("Sem chave da malha configurada.")

        self._psk = chave_malha
        self._id_local = id_local
        self._privada = X25519PrivateKey.generate()
        self._nonce_local = secrets.token_bytes(32)

        self._ola_local = json.dumps(
            {
                "tipo": "ola",
                "versao": VERSAO_PROTOCOLO,
                "id": id_local,
                "nonce": base64.b64encode(self._nonce_local).decode("ascii"),
                "pub": base64.b64encode(
                    self._privada.public_key().public_bytes_raw()
                ).decode("ascii"),
            },
            sort_keys=True,
        ).encode("utf-8")

        self._ola_remoto = None
        self._cifra_envio = None
        self._cifra_recepcao = None
        self._contador_envio = 0
        self._contador_recepcao = 0
        self._confirmacao_enviada = False
        self._confirmacao_recebida = False
        self.id_remoto = ""

    # -- estado --

    @property
    def pronta(self) -> bool:
        """True só depois que ESTA máquina verificou o HMAC do outro lado.
        Nenhuma mensagem de protocolo pode ser aceita antes disso."""
        return self._confirmacao_recebida

    def frame_inicial(self) -> bytes:
        return enquadrar(self._ola_local)

    # -- handshake --

    def receber(self, frame: bytes):
        """Consome um frame. Durante o handshake devolve a lista de frames a
        mandar de volta (pode ser vazia). Depois dele, devolve None — a partir
        daí quem chama usa `abrir()`."""
        if self.pronta:
            return None
        if self._ola_remoto is None:
            return self._receber_ola(frame)
        return self._receber_confirmacao(frame)

    def _receber_ola(self, frame: bytes):
        mensagem = ler_json(frame)

        if mensagem.get("tipo") != "ola":
            raise ErroSeguranca(f"Esperava 'ola', veio {mensagem.get('tipo')!r}.")
        versao = mensagem.get("versao")
        if versao != VERSAO_PROTOCOLO:
            raise ErroSeguranca(
                f"Versão de protocolo {versao!r} incompatível com a {VERSAO_PROTOCOLO} desta máquina — "
                "atualize o sistema na outra máquina."
            )

        self.id_remoto = mensagem.get("id") or ""
        if not self.id_remoto:
            raise ErroSeguranca("Frame de abertura sem id.")

        try:
            nonce_remoto = base64.b64decode(mensagem["nonce"])
            pub_remota = X25519PublicKey.from_public_bytes(base64.b64decode(mensagem["pub"]))
        except Exception as erro:
            raise ErroSeguranca(f"Frame de abertura malformado: {erro}") from erro

        self._ola_remoto = frame
        self._derivar_chaves(pub_remota, nonce_remoto)

        # Só agora dá pra provar quem somos: a prova cobre as duas chaves
        # públicas, então ela não existe antes de conhecer a do outro lado.
        self._confirmacao_enviada = True
        return [enquadrar(self._confirmacao(self._sou_menor))]

    def _derivar_chaves(self, pub_remota, nonce_remoto: bytes):
        segredo = self._privada.exchange(pub_remota)

        # "Menor" e "maior" são só rótulos estáveis para os dois lados
        # combinarem quem cifra com qual chave, sem uma rodada extra de
        # mensagens. Os nonces são aleatórios de 32 bytes, então empate é
        # impossível na prática.
        self._sou_menor = self._ola_local < self._ola_remoto
        primeiro, segundo = (
            (self._ola_local, self._ola_remoto) if self._sou_menor else (self._ola_remoto, self._ola_local)
        )
        self._transcrito = primeiro + segundo
        nonce_a, nonce_b = (
            (self._nonce_local, nonce_remoto) if self._sou_menor else (nonce_remoto, self._nonce_local)
        )

        # A chave da malha entra no material do HKDF junto com o segredo
        # X25519 — assim nem quem quebra o X25519 nem quem tem só a chave
        # consegue a chave de sessão sozinho.
        material = HKDF(
            algorithm=hashes.SHA256(),
            length=64,
            salt=nonce_a + nonce_b,
            info=_INFO_SESSAO,
        ).derive(segredo + self._psk)

        chave_menor, chave_maior = material[:32], material[32:]
        if self._sou_menor:
            self._cifra_envio = ChaCha20Poly1305(chave_menor)
            self._cifra_recepcao = ChaCha20Poly1305(chave_maior)
        else:
            self._cifra_envio = ChaCha20Poly1305(chave_maior)
            self._cifra_recepcao = ChaCha20Poly1305(chave_menor)

    def _confirmacao(self, do_lado_menor: bool) -> bytes:
        """HMAC da chave da malha sobre o transcrito inteiro. O rótulo do lado
        entra no cálculo pra que as duas provas sejam diferentes — senão
        bastaria devolver a que acabou de chegar pra "provar" que se tem a
        chave."""
        rotulo = b"menor" if do_lado_menor else b"maior"
        return hmac.new(self._psk, _ROTULO_CONFIRMACAO + rotulo + self._transcrito, hashlib.sha256).digest()

    def _receber_confirmacao(self, frame: bytes):
        esperado = self._confirmacao(not self._sou_menor)
        # compare_digest e não "==": a comparação byte a byte de um HMAC
        # vaza, pelo tempo que leva, quantos bytes iniciais o atacante
        # acertou — o que transforma adivinhar 32 bytes num trabalho viável.
        if not hmac.compare_digest(frame, esperado):
            raise ErroSeguranca("Chave da malha não confere — esta máquina é de outra rede.")
        self._confirmacao_recebida = True
        return []

    # -- tráfego --

    def _proximo_nonce(self, contador: int) -> bytes:
        # 12 bytes: 4 zerados + contador de 64 bits. Cada sentido tem o seu,
        # e as chaves são diferentes por sentido, então o par (chave, nonce)
        # nunca se repete — que é a única regra que ChaCha20-Poly1305 exige
        # e a única cujo descumprimento quebra tudo de uma vez.
        return b"\x00\x00\x00\x00" + struct.pack(">Q", contador)

    def selar(self, dados: bytes) -> bytes:
        if not self._cifra_envio:
            raise ErroSeguranca("Sessão ainda não estabelecida.")
        selado = self._cifra_envio.encrypt(self._proximo_nonce(self._contador_envio), dados, None)
        self._contador_envio += 1
        return enquadrar(selado)

    def abrir(self, frame: bytes) -> bytes:
        if not self._cifra_recepcao:
            raise ErroSeguranca("Sessão ainda não estabelecida.")
        try:
            dados = self._cifra_recepcao.decrypt(self._proximo_nonce(self._contador_recepcao), frame, None)
        except Exception as erro:
            # Aqui não se distingue "adulterado" de "fora de ordem": TCP já
            # garante a ordem, então qualquer falha significa que este fio
            # não é mais confiável.
            raise ErroSeguranca(f"Frame não autenticou: {erro}") from erro
        self._contador_recepcao += 1
        return dados


# ---------- Pareamento ----------


class SessaoPareamento:
    """Entrega a chave da malha a uma máquina nova, com uma pessoa conferindo
    um código de 6 dígitos nas duas telas.

    Dois papéis: PEDE (a máquina sem chave) e APROVA (uma máquina já pareada).
    Quatro mensagens, na ordem:

      1. PEDE -> APROVA   pedido     {id, nome, compromisso = sha256(pub ‖ nonce)}
      2. APROVA -> PEDE   resposta   {id, nome, pub, nonce}
      3. PEDE -> APROVA   revelação  {pub, nonce}  (confere com o compromisso)
      4. APROVA -> PEDE   chave      a chave da malha, cifrada — só depois que
                                     alguém na máquina APROVA clicou Aceitar

    Depois da 3 os dois lados têm o mesmo segredo X25519, e dele sai o código
    de 6 dígitos que cada tela mostra. Um intermediário faz um X25519 com cada
    lado, e o código de cada lado sai diferente — a pessoa vê a diferença.

    POR QUE O COMPROMISSO. Sem ele o intermediário, que vê as duas chaves
    públicas antes de escolher as suas, poderia gerar chaves até os dois
    códigos coincidirem: um milhão de tentativas, alguns segundos. Com o
    compromisso, o lado que PEDE fixa a própria chave antes de ver a do outro,
    e o que APROVA mostra a sua antes de ver a do primeiro — não sobra uma
    ordem em que o intermediário escolha a dele conhecendo as duas.
    """

    PEDE = "pede"
    APROVA = "aprova"

    def __init__(self, papel: str, id_local: str, nome_local: str):
        if not DISPONIVEL:
            raise ErroSeguranca(f"Biblioteca 'cryptography' indisponível: {ERRO_IMPORT}")
        if papel not in (self.PEDE, self.APROVA):
            raise ValueError(f"papel inválido: {papel!r}")
        self.papel = papel
        self._id_local = id_local
        self._nome_local = nome_local
        self._privada = X25519PrivateKey.generate()
        self._pub = self._privada.public_key().public_bytes_raw()
        self._nonce = secrets.token_bytes(32)

        self.id_remoto = ""
        self.nome_remoto = ""
        self._compromisso_remoto = b""
        self._pub_remota = b""
        self._nonce_remoto = b""
        self.codigo = ""
        self._chave_embrulho = None

    @property
    def pronta(self) -> bool:
        """Os dois lados já chegaram ao código (depois da revelação)."""
        return bool(self.codigo)

    # -- utilidades --

    def _frame(self, tipo: str, **campos) -> bytes:
        dados = {"tipo": tipo, "versao": VERSAO_PROTOCOLO, "id": self._id_local, "nome": self._nome_local}
        dados.update(campos)
        return enquadrar(json.dumps(dados, sort_keys=True).encode("utf-8"))

    @staticmethod
    def _b64(dados: bytes) -> str:
        return base64.b64encode(dados).decode("ascii")

    @staticmethod
    def _conferir_versao(mensagem: dict):
        if mensagem.get("versao") != VERSAO_PROTOCOLO:
            raise ErroSeguranca(
                f"Versão de protocolo {mensagem.get('versao')!r} incompatível com a {VERSAO_PROTOCOLO} — "
                "atualize o sistema nas duas máquinas."
            )

    def _identificar_remoto(self, mensagem: dict):
        self.id_remoto = str(mensagem.get("id") or "")
        self.nome_remoto = " ".join(str(mensagem.get("nome") or "").split())[:60] or "Máquina sem nome"
        if not self.id_remoto:
            raise ErroSeguranca("Mensagem de pareamento sem id.")

    def _ler_pub_nonce(self, mensagem: dict):
        try:
            pub = base64.b64decode(mensagem["pub"])
            nonce = base64.b64decode(mensagem["nonce"])
            X25519PublicKey.from_public_bytes(pub)
        except Exception as erro:
            raise ErroSeguranca(f"Mensagem de pareamento malformada: {erro}") from erro
        if len(nonce) != 32:
            raise ErroSeguranca("Nonce de pareamento com tamanho inválido.")
        return pub, nonce

    def _derivar(self):
        if self.papel == self.PEDE:
            pub_pede, nonce_pede, pub_aprova, nonce_aprova = self._pub, self._nonce, self._pub_remota, self._nonce_remoto
        else:
            pub_pede, nonce_pede, pub_aprova, nonce_aprova = self._pub_remota, self._nonce_remoto, self._pub, self._nonce

        segredo = self._privada.exchange(X25519PublicKey.from_public_bytes(self._pub_remota))
        transcrito = hashlib.sha256(nonce_pede + nonce_aprova + pub_pede + pub_aprova).digest()
        material = HKDF(algorithm=hashes.SHA256(), length=64, salt=transcrito, info=_INFO_PAREAMENTO).derive(segredo)

        self.codigo = f"{int.from_bytes(material[:8], 'big') % 1_000_000:06d}"
        self._chave_embrulho = material[32:]

    # -- lado que PEDE --

    def frame_pedido(self) -> bytes:
        if self.papel != self.PEDE:
            raise ErroSeguranca("Só quem pede abre o pareamento.")
        compromisso = hashlib.sha256(self._pub + self._nonce).hexdigest()
        return self._frame(TIPO_PEDIDO, compromisso=compromisso)

    def receber_resposta(self, mensagem: dict) -> bytes:
        """Consome a resposta e devolve o frame de revelação a mandar."""
        if self.papel != self.PEDE or mensagem.get("tipo") != TIPO_RESPOSTA or self._pub_remota:
            raise ErroSeguranca("Resposta de pareamento fora de ordem.")
        self._conferir_versao(mensagem)
        self._identificar_remoto(mensagem)
        self._pub_remota, self._nonce_remoto = self._ler_pub_nonce(mensagem)
        self._derivar()
        return self._frame(TIPO_REVELACAO, pub=self._b64(self._pub), nonce=self._b64(self._nonce))

    def abrir_chave(self, mensagem: dict) -> bytes:
        if self.papel != self.PEDE or not self.pronta or mensagem.get("tipo") != TIPO_CHAVE:
            raise ErroSeguranca("Chave de pareamento fora de ordem.")
        try:
            blob = base64.b64decode(mensagem.get("dados") or "")
            nonce, cifrado = blob[:12], blob[12:]
            chave = ChaCha20Poly1305(self._chave_embrulho).decrypt(nonce, cifrado, _DADOS_ASSOCIADOS_CHAVE)
        except Exception as erro:
            raise ErroSeguranca("A chave recebida no pareamento não abriu — alguém interferiu na conexão.") from erro
        if len(chave) != _TAMANHO_CHAVE:
            raise ErroSeguranca("A chave recebida no pareamento tem tamanho inválido.")
        return chave

    # -- lado que APROVA --

    def receber_pedido(self, mensagem: dict) -> bytes:
        """Consome o pedido e devolve o frame de resposta a mandar."""
        if self.papel != self.APROVA or mensagem.get("tipo") != TIPO_PEDIDO or self._compromisso_remoto:
            raise ErroSeguranca("Pedido de pareamento fora de ordem.")
        self._conferir_versao(mensagem)
        self._identificar_remoto(mensagem)
        try:
            self._compromisso_remoto = bytes.fromhex(str(mensagem.get("compromisso") or ""))
        except ValueError as erro:
            raise ErroSeguranca("Compromisso de pareamento malformado.") from erro
        if len(self._compromisso_remoto) != 32:
            raise ErroSeguranca("Compromisso de pareamento com tamanho inválido.")
        return self._frame(TIPO_RESPOSTA, pub=self._b64(self._pub), nonce=self._b64(self._nonce))

    def receber_revelacao(self, mensagem: dict) -> None:
        if self.papel != self.APROVA or mensagem.get("tipo") != TIPO_REVELACAO or not self._compromisso_remoto or self.pronta:
            raise ErroSeguranca("Revelação de pareamento fora de ordem.")
        pub, nonce = self._ler_pub_nonce(mensagem)
        if not hmac.compare_digest(hashlib.sha256(pub + nonce).digest(), self._compromisso_remoto):
            raise ErroSeguranca("A máquina que pediu para entrar mudou a própria chave no meio do pareamento.")
        self._pub_remota, self._nonce_remoto = pub, nonce
        self._derivar()

    def frame_chave(self, chave_malha: bytes) -> bytes:
        if self.papel != self.APROVA or not self.pronta:
            raise ErroSeguranca("Só dá para entregar a chave depois de os dois lados terem o código.")
        nonce = secrets.token_bytes(12)
        cifrado = ChaCha20Poly1305(self._chave_embrulho).encrypt(nonce, chave_malha, _DADOS_ASSOCIADOS_CHAVE)
        return self._frame(TIPO_CHAVE, dados=self._b64(nonce + cifrado))

    def frame_recusa(self, motivo: str) -> bytes:
        return self._frame(TIPO_RECUSA, motivo=str(motivo or "")[:200])
