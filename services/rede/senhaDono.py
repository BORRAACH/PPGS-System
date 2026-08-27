"""Senha do dono — o que tranca o cadastro de usuários (ver
controllers/usuariosController.py e qml/pages/configuracoes/usuarios/).

POR QUE NÃO O CÓDIGO DE DOIS DÍGITOS. O código de services/rede/usuarios.py é
digitado no balcão, na frente da equipe, várias vezes por turno — ele existe
para dizer QUEM fez uma correção, e por isso não pode ser segredo de ninguém.
Se ele também trancasse o cadastro, bastaria alguém decorar os dois dígitos do
dono (que ele digita na frente de todos) para se cadastrar sozinho e assinar o
que quisesse. Daí um segredo separado, que só é pedido nesta tela e nunca no
balcão.

AQUI HASHEAR VALE A PENA, e isso inverte o que está escrito no topo de
usuarios.py: lá, hashear dois dígitos seria teatro (cem pré-imagens, quebradas
num piscar). Uma senha de verdade tem espaço de busca grande o bastante para o
hash significar alguma coisa — então ela nunca é gravada em claro, e quem
abrir este JSON não consegue lê-la de volta para digitá-la na tela.

PBKDF2-HMAC-SHA256 com salt por senha, da stdlib (`hashlib.pbkdf2_hmac`): não
depende de `cryptography`, que já é dependência da malha mas cuja ausência não
pode trancar o dono fora do cadastro (ver o topo de seguranca.py). O custo de
iteração é regulado por `_ITERACOES` e viaja gravado no registro, para uma
senha antiga continuar conferindo depois de o número subir.

ACENTOS. A senha aceita o Unicode inteiro — maiúsculas, minúsculas, símbolos e
acentos. Isso traz um problema que só aparece com acento: "á" pode ser gravado
como um caractere (U+00E1) ou como dois (a + acento combinante), iguais na
tela e diferentes em bytes. Sem normalizar, a MESMA senha digitada em dois
teclados falharia num deles, sem nada explicando por quê. Por isso tudo passa
por `unicodedata.normalize("NFC", ...)` antes de virar bytes — na definição e
na conferência, pelo mesmo caminho (`_bytes_da_senha`), que é o que garante
que os dois lados concordem.

SINCRONIZADA NA MALHA, um registro só, arbitrado por idEvento/relogio.mais_novo
— mesmo desenho de contagemCaixa.py e cardapioService.py. Define-se numa
máquina e vale em todas, inclusive nas que entrarem depois: máquina nova que
chegasse sem senha seria uma porta aberta até alguém lembrar de fechá-la.

O QUE ISTO NÃO É. A senha tranca a TELA. Ela não impede quem edita
`pedidos/.sync/usuarios.json` na mão, nem quem roda outra instância do app na
LAN e publica um `usuario_alterado` pelo gossip — a malha não autentica
ninguém (ver `CHAVE_PADRAO` em seguranca.py e a seção "Fora do escopo" de
architecture/EXPLAIN.md). É um obstáculo contra quem usa o app, no mesmo
espírito do código de dois dígitos, não um segredo contra alguém decidido.

ESQUECEU A SENHA. Não há porta dos fundos, e isso é de propósito: uma que
funcionasse a partir de uma máquina só seria exatamente o atalho que a equipe
usaria para contornar a senha. A saída é manual e proposital — fechar o app em
TODAS as máquinas, apagar `pedidos/.sync/senha_dono.json` em cada uma e abrir
de novo; a próxima abertura da tela pede para definir uma senha nova. Apagar em
uma só não adianta: a reconciliação a reaprende do vizinho no ciclo seguinte.
Trocar a senha sabendo a atual é o caminho normal, pela própria tela.

Guardado em pedidos/.sync/senha_dono.json (ver services/rede/caminhos.py):
`{"algoritmo", "iteracoes", "salt", "hash", "definidaEm", "idEvento"}`."""

import base64
import hashlib
import hmac
import os
import secrets
import unicodedata

from services.rede import caminhos, relogio

_ROTULO = "senhaDono"

# Mesmo nome do domínio de reconciliação — ver UsuariosController, que o
# registra com esta constante.
DOMINIO = "senha_dono"

# A chave única do registro dentro do domínio sincronizado. O domínio guarda
# UM registro, não uma coleção, mas o contrato de
# RedeService.registrarDominioSincronizado é {chave: versao} — então o
# registro tem uma chave fixa, e é ela que viaja.
CHAVE = "senha"

# Piso de tamanho, não meta: a senha do dono deve ser longa, mas quem escolhe
# o quanto é ele. Não há regra de composição (exigir símbolo/maiúscula/dígito)
# de propósito — regra de composição empurra para senha decorável e anotada no
# monitor, e aqui o inimigo é a equipe que trabalha ao lado do monitor.
TAMANHO_MINIMO = 6

_ALGORITMO = "pbkdf2_sha256"
_ITERACOES = 240_000
_TAMANHO_SALT = 16


def _caminho_arquivo():
    return os.path.join(caminhos.pasta_sincronizacao(), "senha_dono.json")


def carregar():
    """O registro da senha, ou {} enquanto ninguém definiu uma."""
    return caminhos.carregar_json(_caminho_arquivo(), _ROTULO)


def _salvar(dados):
    caminhos.salvar_json(_caminho_arquivo(), dados, _ROTULO)


def definida():
    """Se já existe senha. False numa instalação nova E numa máquina que
    ainda não recebeu o registro da malha — nos dois casos a tela pede para
    DEFINIR uma, que é o que fecha a porta na primeira abertura."""
    return bool(carregar().get("hash"))


def _bytes_da_senha(senha):
    """A senha em bytes, normalizada em NFC. Ponto único por onde toda senha
    passa — definir e conferir usam este mesmo caminho, então não existe
    "senha certa que não confere" por causa de acento composto de dois jeitos
    diferentes (ver o topo do módulo)."""
    return unicodedata.normalize("NFC", str(senha or "")).encode("utf-8")


def _derivar(senha, salt, iteracoes):
    return hashlib.pbkdf2_hmac("sha256", _bytes_da_senha(senha), salt, iteracoes)


def validar(senha):
    """"" quando a senha serve, ou o motivo de não servir:
    "senha_curta". Só o tamanho é checado — ver TAMANHO_MINIMO.

    O tamanho é medido em CARACTERES depois da normalização, não em bytes:
    uma senha de sete letras acentuadas tem catorze bytes em UTF-8, e recusá-la
    por "curta" seria incompreensível para quem a digitou."""
    texto = unicodedata.normalize("NFC", str(senha or ""))
    if len(texto) < TAMANHO_MINIMO:
        return "senha_curta"
    return ""


def definir(senha, data_hora, quando=None):
    """Grava a senha (sobrescrevendo a anterior) e devolve o id da gravação,
    ou None se ela não passar em `validar`.

    `quando` só vem preenchido quando o registro é aprendido de outra máquina
    (ver aplicar_remoto): preservar o id de origem é o que faz as duas
    concordarem sobre a MESMA gravação, mesmo cuidado de
    contagemCaixa.registrar."""
    if validar(senha):
        return None

    salt = secrets.token_bytes(_TAMANHO_SALT)
    id_evento = quando or relogio.novo_id()
    _salvar({
        # Algoritmo e iterações viajam gravados, e não são lidos de uma
        # constante na hora de conferir: subir _ITERACOES depois não pode
        # invalidar a senha que já está em uso, e uma máquina com o app mais
        # antigo precisa conseguir conferir o que uma mais nova gravou.
        "algoritmo": _ALGORITMO,
        "iteracoes": _ITERACOES,
        "salt": base64.b64encode(salt).decode("ascii"),
        "hash": base64.b64encode(_derivar(senha, salt, _ITERACOES)).decode("ascii"),
        "definidaEm": data_hora,
        "idEvento": id_evento,
    })
    return id_evento


def conferir(senha):
    """True se `senha` bate com a gravada. False quando não bate, quando
    ainda não há senha nenhuma, ou quando o registro veio de uma versão do
    app com um algoritmo que esta não conhece — nos três casos a resposta
    segura é a mesma: não libera.

    A comparação é em tempo constante (`hmac.compare_digest`). Contra alguém
    digitando na tela isso não muda nada; está aqui porque a alternativa (`==`)
    é o tipo de detalhe que passa a importar no dia em que esta função for
    chamada de outro lugar, e ninguém volta para revisá-la."""
    registro = carregar()
    esperado = registro.get("hash")
    salt = registro.get("salt")
    if not esperado or not salt:
        return False

    if registro.get("algoritmo") != _ALGORITMO:
        print(f"[{_ROTULO}] Algoritmo desconhecido: {registro.get('algoritmo')!r} — recusando.")
        return False

    try:
        salt_bytes = base64.b64decode(salt)
        esperado_bytes = base64.b64decode(esperado)
    except (ValueError, TypeError) as erro:
        print(f"[{_ROTULO}] Registro ilegível ({erro}) — recusando.")
        return False

    iteracoes = registro.get("iteracoes")
    if not isinstance(iteracoes, int) or iteracoes < 1:
        return False

    return hmac.compare_digest(_derivar(senha, salt_bytes, iteracoes), esperado_bytes)


# ---------- Sincronização entre máquinas ----------
# Um registro só, arbitrado por idEvento (relogio.mais_novo) — mesmo desenho
# de contagemCaixa.py. Sem "apagados": não existe operação de apagar a senha
# pela malha, justamente para que apagar o arquivo numa máquina não destranque
# as outras (ver "ESQUECEU A SENHA" no topo do módulo).


def resumo():
    registro = carregar()
    if not registro.get("hash"):
        return {"itens": {}}
    return {"itens": {CHAVE: registro.get("idEvento", "")}}


def obter(chave):
    """O registro pronto para viajar. Vai o HASH, nunca a senha — ela não
    existe em lugar nenhum depois de definida, nem aqui nem em disco."""
    if chave != CHAVE:
        return None
    registro = carregar()
    return dict(registro) if registro.get("hash") else None


def aplicar_remoto(payload):
    """Grava a senha aprendida de outra máquina, só se o id recebido for
    estritamente mais novo que o já conhecido aqui — mesmo cuidado de
    contagemCaixa.aplicar_remoto, para duas máquinas trocando a senha quase ao
    mesmo tempo não desfazerem uma a da outra. Devolve True só se aplicou.

    O payload é copiado como veio (hash, salt, iterações e algoritmo juntos):
    reprocessar qualquer um deles aqui produziria um registro que não confere
    mais com a senha que o dono digitou lá."""
    if not isinstance(payload, dict):
        return False

    id_recebido = payload.get("idEvento", "")
    if not payload.get("hash") or not id_recebido:
        return False

    relogio.observar(id_recebido)
    atual = carregar().get("idEvento", "")
    if atual and not relogio.mais_novo(id_recebido, atual):
        return False

    _salvar({
        "algoritmo": payload.get("algoritmo", ""),
        "iteracoes": payload.get("iteracoes", 0),
        "salt": payload.get("salt", ""),
        "hash": payload.get("hash", ""),
        "definidaEm": payload.get("definidaEm", ""),
        "idEvento": id_recebido,
    })
    return True
