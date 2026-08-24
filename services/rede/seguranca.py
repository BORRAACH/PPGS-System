"""Criptografia da malha, e as chaves derivadas que o ppgs_server usa.

Entrar na malha é automático: qualquer instância deste app na mesma rede local
entra sozinha, sem senha nem configuração. É a decisão original do projeto
(`architecture/EXPLAIN.md`, seção "Fora do escopo": *"Sem autenticação/senha
para entrar na rede — qualquer instância deste app na mesma LAN entra
automaticamente"*), e ela vale de novo depois de uma temporada exigindo uma
chave transcrita entre as máquinas.

O QUE ISTO CUSTA, dito com todas as letras: o ppgs_server escuta só em
127.0.0.1 e é alcançado POR DENTRO da malha (ver `solicitar_servidor` em
redeService.py), então "estar na malha" é o que separa alguém do banco de
endereços e telefones dos clientes. Sem autenticação, qualquer máquina que
alcance a rede local e rode este app chega lá. A aposta é a de sempre: a rede
da pizzaria é um lugar fechado, e o custo de administrar segredo em máquinas
que ninguém administra é maior que o risco. Ver `CHAVE_PADRAO` abaixo, que é
onde essa aposta está escrita, e o caminho de volta caso ela deixe de valer.

O que este módulo garante, então:

1. **Quem escuta o fio não lê nada.** Depois do handshake tudo vai selado com
   ChaCha20-Poly1305 — inclusive as comandas, que antes trafegavam em base64
   legível. Contra escuta passiva no wi-fi da pizzaria isso continua valendo
   inteiro.
2. **Quem grava o tráfego hoje não o lê amanhã.** O segredo de sessão vem de
   um X25519 efêmero, jogado fora quando o socket fecha (forward secrecy).
3. **Quem não roda este app não conversa.** O handshake fecha num HMAC sobre o
   transcrito, então um programa qualquer que abra o socket é recusado antes
   de qualquer mensagem de protocolo. É uma barreira contra acidente e
   varredura, não contra alguém decidido: a chave que assina esse HMAC está no
   código-fonte.

O que NÃO está garantido é um atacante ativo: ele não precisa mais interceptar
nada, porque pode entrar pela porta da frente. Antes, o HMAC sobre as duas
chaves públicas impedia um intermediário de trocar uma delas; ele continua
impedindo, mas o intermediário deixou de precisar disso.

A mesma chave deriva, por HKDF com `info` diferentes, o token HTTP e as chaves
de dados e de índice do ppgs_server (ver `token_servidor`, `chave_dados` e
`chave_indice`). Continuam sendo derivações separadas — nenhuma delas dá as
outras — e continuam nunca sendo gravadas em disco: o servidor as recebe por
variável de ambiente, que é o que faz levar o `pizzeria.db` embora ainda não
bastar para lê-lo.
"""

import base64
import hashlib
import hmac
import json
import secrets
import struct

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
# delas não sabe ler.
VERSAO_PROTOCOLO = 1


# Teto de um frame selado. A reconciliação (`reconciliar_dados`) pode mandar
# um domínio inteiro de uma vez — o cardápio, o histórico — então o limite
# precisa ser generoso; o que ele existe pra impedir é um peer não
# autenticado anunciar um tamanho absurdo e fazer esta máquina reservar a
# memória antes de ter provado qualquer coisa.
_TAMANHO_MAXIMO_FRAME = 64 * 1024 * 1024

_INFO_SESSAO = b"PPGS-malha-sessao-v1"
_INFO_TOKEN_SERVIDOR = b"PPGS-servidor-token-v1"
_INFO_CHAVE_DADOS = b"PPGS-servidor-dados-v1"
_INFO_INDICE_DADOS = b"PPGS-servidor-indice-v1"

_ROTULO_CONFIRMACAO = b"PPGS-confirmar-v1"


class ErroSeguranca(Exception):
    """Falha de handshake ou de abertura de frame. Quem trata fecha o socket
    — nunca há recuperação parcial: um frame que não abre significa chave
    errada, versão incompatível ou adulteração, e nos três casos a única
    resposta correta é desistir daquela conexão."""


# ---------- Chave da malha (fixa, e de propósito não é segredo) ----------
#
# Entrar na malha voltou a ser automático: qualquer instância deste app na
# mesma rede local entra sozinha, sem ninguém configurar nada. Foi assim até a
# chave ser introduzida, e é assim de novo — a transcrição de um código entre
# máquinas era fricção real numa pizzaria onde ninguém administra computador.
#
# A chave em si NÃO foi removida, porque ela sustenta três coisas que nada tem
# a ver com barrar quem entra: o HMAC que fecha o handshake, o material do
# HKDF que produz as chaves de sessão, e as chaves derivadas que o
# ppgs_server exige (token, dados, índice). O que mudou é que ela deixou de
# ser um segredo por instalação e passou a ser esta constante, igual em toda
# máquina que rodar este código.
#
# SEJA HONESTO SOBRE O QUE ISTO VALE. Como o valor sai daqui, do código-fonte
# aberto, ele não autentica ninguém: quem puser este app numa máquina na rede
# da pizzaria entra na malha, e por dentro dela alcança o ppgs_server e o banco
# de endereços e telefones dos clientes. O HMAC do handshake continua rodando,
# mas prova apenas "este peer roda esta versão deste app", nunca "este peer é
# autorizado".
#
# O que continua valendo, e não é pouco:
#
# - **Quem escuta o fio não lê nada.** O segredo de sessão vem de um X25519
#   efêmero, então o tráfego segue cifrado com ChaCha20-Poly1305 e ninguém
#   capturando o wi-fi lê comanda, endereço ou telefone. Contra escuta passiva
#   a proteção é a mesma de antes; o que se perdeu foi a defesa contra um
#   atacante ATIVO, que agora pode simplesmente entrar na malha pela porta da
#   frente em vez de ter que interceptar alguma coisa.
# - **Forward secrecy.** As chaves efêmeras são jogadas fora quando o socket
#   fecha, então gravar o tráfego de hoje não ajuda ninguém amanhã.
# - **O banco continua cifrado em repouso.** O ppgs_server segue cifrando
#   endereços e nomes com uma chave que não fica ao lado do arquivo, então
#   levar o `pizzeria.db` embora ainda não basta para lê-lo — só que a chave
#   agora é derivável por quem tiver o código.
#
# Um dia em que a rede da pizzaria deixar de ser confiável, o caminho de volta
# é reintroduzir a chave por instalação: só esta seção precisa mudar, porque
# tudo abaixo dela já trabalha com "uma chave qualquer de 32 bytes".

# Derivada de uma frase fixa em vez de ser um blob aleatório colado aqui: um
# monte de hex neste arquivo pareceria um segredo que alguém esqueceu de tirar,
# e mais cedo ou mais tarde seria tratado como tal. Assim fica evidente na
# primeira leitura que não há segredo nenhum a proteger aqui.
CHAVE_PADRAO = hashlib.sha256(b"PPGS-malha-aberta-v1").digest()


def carregar_chave() -> bytes:
    """A chave desta máquina — sempre a mesma, em toda máquina.

    Continua sendo uma função (e não a constante usada direto) porque é o
    ponto único por onde tudo passa: reintroduzir chave por instalação é
    mexer só aqui. Um `Config/chave_malha.json` que tenha sobrado de antes é
    ignorado de propósito — se ele ainda fosse lido, a máquina que o tem
    ficaria isolada das que não têm, e o sintoma seria "a rede parou de
    funcionar sozinha" depois de uma atualização.
    """
    return CHAVE_PADRAO



# ---------- Segredos derivados (nunca distribuídos, sempre recalculados) ----------


def _derivar(chave: bytes, info: bytes, tamanho: int = 32) -> bytes:
    if not DISPONIVEL:
        raise ErroSeguranca(f"Biblioteca 'cryptography' indisponível: {ERRO_IMPORT}")
    return HKDF(algorithm=hashes.SHA256(), length=tamanho, salt=None, info=info).derive(chave)


def token_servidor(chave: bytes | None = None) -> str:
    """O `Authorization: Bearer` que o ppgs_server exige. Toda máquina da
    malha chega ao mesmo valor sozinha, então ele nunca precisa trafegar nem
    ser guardado em lugar nenhum."""
    chave = chave if chave is not None else carregar_chave()
    if not chave:
        raise ErroSeguranca("Sem chave da malha — não há token de servidor.")
    return _derivar(chave, _INFO_TOKEN_SERVIDOR).hex()


def chave_dados(chave: bytes | None = None) -> str:
    """Chave com que o ppgs_server cifra endereços e nomes no SQLite. Vai pro
    processo dele por variável de ambiente e nunca é gravada ao lado do banco
    — é isso que faz roubar o `pizzeria.db` não bastar."""
    chave = chave if chave is not None else carregar_chave()
    if not chave:
        raise ErroSeguranca("Sem chave da malha — não há chave de dados.")
    return _derivar(chave, _INFO_CHAVE_DADOS).hex()


def chave_indice(chave: bytes | None = None) -> str:
    """Chave do índice cego de telefone (HMAC). Separada da de cifragem de
    propósito: quem obtiver uma não consegue a outra, e o índice é o único
    valor que fica em claro no banco (em forma de HMAC), porque é por ele que
    a busca por telefone acontece."""
    chave = chave if chave is not None else carregar_chave()
    if not chave:
        raise ErroSeguranca("Sem chave da malha — não há chave de índice.")
    return _derivar(chave, _INFO_INDICE_DADOS).hex()


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


# ---------- Sessão ----------


class SessaoSegura:
    """Handshake e cifragem de UM socket.

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
        try:
            mensagem = json.loads(frame.decode("utf-8"))
        except (ValueError, UnicodeDecodeError) as erro:
            raise ErroSeguranca(f"Frame de abertura ilegível: {erro}") from erro

        if mensagem.get("tipo") != "ola":
            raise ErroSeguranca(f"Esperava 'ola', veio {mensagem.get('tipo')!r}.")
        versao = mensagem.get("versao")
        if versao != VERSAO_PROTOCOLO:
            raise ErroSeguranca(f"Versão de protocolo {versao!r} incompatível com a {VERSAO_PROTOCOLO} desta máquina.")

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
            raise ErroSeguranca("Chave da malha não confere.")
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
