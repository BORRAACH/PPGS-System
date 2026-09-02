"""Preparo do ppgs_server numa máquina Windows: ferramentas, repositório,
binário e banco.

Tudo aqui é síncrono e bloqueante de propósito — quem chama
(services/servidor/servidorLocal.py) roda numa thread de fundo em prioridade
ociosa. Nada neste arquivo toca objeto Qt, justamente pra poder rodar fora da
thread da interface.

O contrato de cada etapa é `(ok: bool, mensagem: str)`, nunca exceção: uma
máquina de pizzaria não tem quem leia traceback, e a tela Rede precisa de uma
frase curta dizendo em que passo parou e o que fazer.

Por que compilar, e não só baixar um binário: as máquinas do balcão não têm
toolchain nenhuma, e instalar rustup + VS Build Tools é caro (alguns GB, e o
instalador do VS costuma pedir UAC). Então a ordem é invertida em relação ao
óbvio: tenta primeiro o binário pronto do GitHub Releases (segundos, sem
admin) e só cai pra compilar do código quando não há release publicado — o
que mantém a promessa de "funciona a partir do código-fonte" sem cobrar
40 minutos de todo mundo no caso normal.
"""

import os
import platform
import threading
import shutil
import subprocess
import urllib.error
import urllib.request

from Config.atualizador import rodar_git

REPOSITORIO = "git@github.com:BORRAACH/PPGS-Server.git"
# `master` está atrás: o suporte a PIZZERIA_BIND e a rota /fechamentos só
# existem neste ramo. Clonar o default deixaria o servidor sem metade do que o
# sistema usa.
BRANCH = "acesso-rede-local"
_REPO_HTTPS_RELEASES = "https://api.github.com/repos/BORRAACH/PPGS-Server/releases/latest"

NOME_BINARIO = "pizzeria-server.exe" if os.name == "nt" else "pizzeria-server"
NOME_CHAVE_DEPLOY = "ppgs_deploy"

_TIMEOUT_GIT_LONGO = 300  # clone completo numa conexão ruim
_TIMEOUT_BUILD = 3600  # a primeira compilação do zero é lenta na máquina fraca
_TIMEOUT_FERRAMENTA = 1800


def eh_windows() -> bool:
    return os.name == "nt"


def pasta_base() -> str:
    """Onde o servidor mora. Fora da árvore do pizzeria_system de propósito:
    o Config/atualizador.py roda `git merge --ff-only` na raiz do projeto, e
    um segundo repositório ali dentro apareceria pra ele como diretório sujo
    a cada atualização."""
    if eh_windows():
        raiz = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
    else:
        raiz = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(raiz, "PPGS")


def pasta_repositorio() -> str:
    return os.path.join(pasta_base(), "ppgs_server")


def pasta_dados() -> str:
    """Onde o `pizzeria.db` vive. Separada do repositório porque o clone pode
    ser apagado e refeito (é o caminho de recuperação mais simples quando o
    checkout corrompe), e o banco não pode ir junto."""
    return os.path.join(pasta_base(), "dados")


def caminho_pid() -> str:
    """Onde fica gravado o PID do servidor que ESTA instalação subiu.

    Existe por um motivo concreto: o processo do servidor é filho do sistema,
    mas não morre junto com ele. Um fechamento que não passe pelo
    `aboutToQuit` — travamento, "encerrar tarefa" no Gerenciador de Tarefas,
    queda de energia com o processo sobrevivendo a uma sessão — deixa o
    servidor rodando e segurando a porta. Na abertura seguinte o servidor novo
    não consegue subir, e o sintoma que chega ao balcão é "os endereços
    sumiram", quando na verdade nada foi perdido: só não há quem responda."""
    return os.path.join(pasta_dados(), "servidor.pid")


def caminho_binario() -> str:
    return os.path.join(pasta_base(), NOME_BINARIO)


def caminho_chave_deploy() -> str:
    return os.path.join(os.path.expanduser("~"), ".ssh", NOME_CHAVE_DEPLOY)


# ---------- Execução de subprocessos em prioridade ociosa ----------


def _flags_de_prioridade() -> dict:
    """Faz cada subprocesso pesado (git, cargo, rustup) rodar sem disputar CPU
    com a interface. É o que sustenta o requisito de "consumindo pouco poder
    de processamento": no Windows, IDLE_PRIORITY_CLASS só recebe CPU quando
    ninguém mais quer, e CREATE_NO_WINDOW evita a janela preta piscando na
    cara do caixa."""
    if not eh_windows():
        return {}
    flags = 0
    for nome in ("IDLE_PRIORITY_CLASS", "CREATE_NO_WINDOW"):
        flags |= getattr(subprocess, nome, 0)
    return {"creationflags": flags} if flags else {}


def flags_de_processo_destacado() -> dict:
    """Como o ppgs_server é lançado: sem janela, mas SEM a prioridade ociosa e
    desligado do ciclo de vida do app.

    Duas diferenças de `_flags_de_prioridade`, e as duas importam:

    - Nada de IDLE_PRIORITY_CLASS. Aquilo é certo para git/cargo, que precisam
      sair da frente da interface; para o servidor seria errado — ele atende as
      requisições do balcão, e recebê-las em prioridade ociosa é justamente o
      contrário do que se quer.
    - DETACHED_PROCESS/start_new_session desligam o servidor do grupo de
      processos do app. Sem isso, fechar o sistema (ou um Ctrl+C no terminal
      durante o desenvolvimento) levaria o servidor junto, que é o
      comportamento de que este projeto acabou de sair."""
    if not eh_windows():
        # Sessão própria: o servidor não recebe o SIGINT/SIGHUP que chega ao
        # grupo do terminal onde o app foi aberto.
        return {"start_new_session": True}
    flags = 0
    for nome in ("DETACHED_PROCESS", "CREATE_NEW_PROCESS_GROUP", "CREATE_NO_WINDOW"):
        flags |= getattr(subprocess, nome, 0)
    return {"creationflags": flags} if flags else {}


# Subprocesso pesado em andamento (git, cargo, rustup, winget), pra que o
# botão "Cancelar" da tela Rede consiga interrompê-lo de verdade. É estado de
# módulo porque só existe um preparo por vez — `ServidorLocalService._preparando`
# garante isso — e porque quem cancela (a thread da interface) não é quem
# executa (a thread de fundo), então o handle precisa estar num lugar que as
# duas alcancem.
_lock_processo = threading.Lock()
_processo_atual = None


def _registrar_processo(processo):
    global _processo_atual
    with _lock_processo:
        _processo_atual = processo


def interromper_atual() -> bool:
    """Mata o subprocesso pesado que estiver rodando agora. Devolve se havia
    algum. Sem isto, cancelar durante um `cargo build` só teria efeito quando
    ele terminasse — até 40 minutos depois, o que não é cancelar."""
    with _lock_processo:
        processo = _processo_atual
    if processo is None or processo.poll() is not None:
        return False
    try:
        processo.kill()
    except OSError:
        return False
    return True


def rodar(comando, cwd=None, timeout=_TIMEOUT_FERRAMENTA, env=None, ao_sair_linha=None):
    """Roda um comando externo em prioridade baixa. Devolve (ok, saída).

    Com `ao_sair_linha`, a saída é entregue linha a linha ENQUANTO o comando
    roda, em vez de só no fim. É o que permite mostrar progresso real de um
    `cargo build` que leva 40 minutos — sem isso a tela ficaria congelada numa
    frase só durante todo esse tempo, indistinguível de um travamento."""
    if ao_sair_linha is not None:
        return _rodar_transmitindo(comando, cwd, timeout, env, ao_sair_linha)
    try:
        # Popen em vez de subprocess.run só para o processo ficar registrado e
        # poder ser interrompido por `interromper_atual`; o resto do
        # comportamento é idêntico.
        processo = subprocess.Popen(
            comando,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            # Mesmo motivo documentado em Config/atualizador.rodar_git: o
            # locale do Windows pt-BR é cp1252 e a saída dessas ferramentas é
            # UTF-8. Sem isto, um acento derruba a leitura do pipe.
            encoding="utf-8",
            errors="replace",
            env=env,
            **_flags_de_prioridade(),
        )
        _registrar_processo(processo)
        try:
            saida, erro_saida = processo.communicate(timeout=timeout)
        finally:
            _registrar_processo(None)
        resultado = subprocess.CompletedProcess(comando, processo.returncode, saida, erro_saida)
    except FileNotFoundError:
        # subprocess levanta o MESMO erro quando o programa não existe e
        # quando o `cwd` não existe. Confundir os dois manda quem lê o log
        # caçar uma ferramenta que está instalada o tempo todo.
        if cwd and not os.path.isdir(cwd):
            return False, f"A pasta '{cwd}' não existe."
        return False, f"'{comando[0]}' não encontrado."
    except subprocess.TimeoutExpired:
        return False, f"'{comando[0]}' passou de {timeout}s e foi interrompido."
    except OSError as erro:
        return False, f"Falha ao rodar '{comando[0]}': {erro}"

    saida = ((resultado.stdout or "") + (resultado.stderr or "")).strip()
    return resultado.returncode == 0, saida


def _rodar_transmitindo(comando, cwd, timeout, env, ao_sair_linha):
    """Igual a `rodar`, mas emitindo cada linha assim que ela sai."""
    import time

    try:
        processo = subprocess.Popen(
            comando,
            cwd=cwd,
            stdout=subprocess.PIPE,
            # O cargo escreve o progresso no stderr; juntar os dois é o que
            # faz "Compiling ..." chegar aqui.
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            **_flags_de_prioridade(),
        )
    except FileNotFoundError:
        if cwd and not os.path.isdir(cwd):
            return False, f"A pasta '{cwd}' não existe."
        return False, f"'{comando[0]}' não encontrado."
    except OSError as erro:
        return False, f"Falha ao rodar '{comando[0]}': {erro}"

    _registrar_processo(processo)
    limite = time.monotonic() + timeout
    linhas = []
    try:
        for linha in processo.stdout:
            linha = linha.rstrip()
            if linha:
                linhas.append(linha)
                ao_sair_linha(linha)
            # Um processo que trava produzindo saída sem parar não pode
            # prender esta thread pra sempre.
            if time.monotonic() > limite:
                processo.kill()
                return False, f"'{comando[0]}' passou de {timeout}s e foi interrompido."
        processo.wait(timeout=max(1, int(limite - time.monotonic())))
    except subprocess.TimeoutExpired:
        processo.kill()
        return False, f"'{comando[0]}' passou de {timeout}s e foi interrompido."
    finally:
        _registrar_processo(None)
        if processo.stdout:
            processo.stdout.close()

    # Só o fim da saída interessa quando dá errado: é onde o erro real está.
    return processo.returncode == 0, "\n".join(linhas[-40:])


def _nada(_texto: str) -> None:
    """Callback padrão de progresso: não faz nada. Existe pra que cada função
    daqui possa avisar sem precisar checar se alguém está ouvindo."""


def _tem(programa: str) -> bool:
    return shutil.which(programa) is not None


# ---------- Etapa: chave de deploy ----------


def garantir_chave_deploy(avisar=_nada):
    """Gera o par de chaves desta máquina, se ainda não existir.

    Devolve (pronta, chave_publica, mensagem). `pronta` é False enquanto a
    chave pública não tiver sido cadastrada no GitHub — o que ninguém aqui
    consegue detectar sem tentar clonar, então quem decide é
    `clonar_ou_atualizar`, e esta função só garante que o par existe."""
    caminho = caminho_chave_deploy()
    publica = caminho + ".pub"

    if not os.path.isfile(publica):
        avisar("gerando a chave de acesso desta máquina")
        os.makedirs(os.path.dirname(caminho), exist_ok=True)

        if os.path.isfile(caminho):
            # Privada sem pública: acontece quando um ssh-keygen anterior foi
            # interrompido no meio, ou quando dois processos correm pra criar
            # a chave ao mesmo tempo. Chamar ssh-keygen de novo aqui NÃO
            # resolve — ele recusa com "already exists" e o preparo trava pra
            # sempre num passo que ninguém sabe destravar. A pública é
            # derivável da privada, então é isso que se faz.
            ok, saida = rodar(["ssh-keygen", "-y", "-f", caminho])
            if not ok:
                return False, "", (
                    f"Existe uma chave em {caminho} que não pôde ser lida ({saida}). "
                    "Apague os arquivos ppgs_deploy* de ~/.ssh e tente de novo."
                )
            try:
                with open(publica, "w", encoding="utf-8") as arquivo:
                    arquivo.write(saida.strip() + "\n")
            except OSError as erro:
                return False, "", f"Não foi possível gravar a chave pública: {erro}"
        else:
            ok, saida = rodar([
                "ssh-keygen", "-t", "ed25519", "-N", "", "-q",
                "-C", f"ppgs-server@{platform.node()}",
                "-f", caminho,
            ])
            if not ok:
                return False, "", f"Não foi possível gerar a chave SSH: {saida}"

    try:
        with open(publica, "r", encoding="utf-8") as arquivo:
            return True, arquivo.read().strip(), ""
    except OSError as erro:
        return False, "", f"Chave gerada mas ilegível: {erro}"


def _ambiente_git() -> dict:
    """Aponta o git pra deploy key desta máquina. `IdentitiesOnly=yes` importa:
    sem ele, o ssh oferece primeiro as chaves já carregadas no agente, o
    GitHub aceita a primeira que reconhecer e o clone pode acabar usando a
    identidade pessoal de quem instalou — que funciona hoje e some quando essa
    pessoa sai."""
    chave = caminho_chave_deploy()
    return {
        "GIT_SSH_COMMAND": (
            f'ssh -i "{chave}" -o IdentitiesOnly=yes -o BatchMode=yes '
            "-o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new"
        )
    }


# ---------- Etapa: ferramentas ----------


def garantir_git(avisar=_nada):
    if _tem("git"):
        return True, "git já instalado"
    avisar("instalando o Git (pode demorar alguns minutos)")
    if not eh_windows():
        return False, "git não encontrado — instale-o pelo gerenciador de pacotes da distribuição."
    if not _tem("winget"):
        return False, "git não encontrado e o winget não está disponível — instale o Git manualmente."
    ok, saida = rodar([
        "winget", "install", "--id", "Git.Git", "-e",
        "--silent", "--accept-package-agreements", "--accept-source-agreements",
    ])
    if not ok:
        return False, f"Falha ao instalar o git: {saida[:200]}"
    # O winget mexe no PATH da sessão nova, não nesta: sem isto, o `git`
    # recém-instalado continua invisível até o app ser reaberto.
    _acrescentar_ao_path(os.path.join(os.environ.get("ProgramFiles", r"C:\Program Files"), "Git", "cmd"))
    return _tem("git"), "git instalado" if _tem("git") else "git instalado, mas será visível só na próxima abertura do sistema."


def _acrescentar_ao_path(pasta: str):
    if pasta and os.path.isdir(pasta) and pasta not in os.environ.get("PATH", ""):
        os.environ["PATH"] = pasta + os.pathsep + os.environ.get("PATH", "")


def garantir_toolchain_rust(avisar=_nada):
    """rustup + compilador C. Só chamado quando não há binário pronto."""
    _acrescentar_ao_path(os.path.join(os.path.expanduser("~"), ".cargo", "bin"))
    if _tem("cargo"):
        return True, "toolchain Rust já instalada"

    if not eh_windows():
        return False, "cargo não encontrado — instale a toolchain Rust (rustup) nesta máquina."

    avisar("baixando o instalador do Rust")
    destino = os.path.join(pasta_base(), "rustup-init.exe")
    ok, msg = _baixar("https://win.rustup.rs/x86_64", destino)
    if not ok:
        return False, f"Falha ao baixar o instalador do Rust: {msg}"

    # -y: sem perguntas. O host padrão já é o MSVC, que é o que queremos: o
    # binário resultante não depende de nenhuma DLL de runtime extra.
    avisar("instalando o Rust (alguns minutos)")
    ok, saida = rodar([destino, "-y", "--no-modify-path", "--profile", "minimal"], timeout=_TIMEOUT_BUILD)
    if not ok:
        return False, f"Falha ao instalar o Rust: {saida[:200]}"

    _acrescentar_ao_path(os.path.join(os.path.expanduser("~"), ".cargo", "bin"))
    return _tem("cargo"), "toolchain Rust instalada" if _tem("cargo") else "Rust instalado, mas o cargo não apareceu no PATH."


def garantir_compilador_c(avisar=_nada):
    """O `rusqlite` compila o SQLite em C (feature "bundled"), então um
    compilador é obrigatório mesmo com todo o resto sendo Rust puro.

    Isto é MUITO mais barato do que era: o `rustls` que estava no Cargo.toml
    sem nenhuma linha de código usando arrastava aws-lc-sys, que exige
    cmake e NASM além do compilador. Ele foi removido — hoje basta o MSVC."""
    if not eh_windows():
        return _tem("cc") or _tem("gcc"), "compilador C do sistema"
    if _tem("cl"):
        return True, "compilador MSVC já instalado"
    if not _tem("winget"):
        return False, "Falta o compilador C (VS Build Tools) e o winget não está disponível."

    # O passo mais demorado e mais chato de todo o preparo: alguns GB, e o
    # instalador do Visual Studio costuma pedir confirmação de administrador.
    # Dizer isso na tela evita que alguém conclua que travou.
    avisar("instalando o compilador do Windows (vários GB, pode pedir permissão de administrador)")
    ok, saida = rodar([
        "winget", "install", "--id", "Microsoft.VisualStudio.2022.BuildTools", "-e",
        "--silent", "--accept-package-agreements", "--accept-source-agreements",
        "--override",
        "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools "
        "--add Microsoft.VisualStudio.Component.Windows11SDK.22621",
    ], timeout=_TIMEOUT_BUILD)
    if not ok:
        return False, f"Falha ao instalar o VS Build Tools (pode ter pedido permissão de administrador): {saida[:200]}"
    return True, "VS Build Tools instalado"


def _baixar(url: str, destino: str, cabecalhos: dict | None = None):
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    try:
        requisicao = urllib.request.Request(url, headers=cabecalhos or {"User-Agent": "ppgs-system"})
        with urllib.request.urlopen(requisicao, timeout=120) as resposta, open(destino, "wb") as arquivo:
            shutil.copyfileobj(resposta, arquivo)
    except (urllib.error.URLError, OSError, TimeoutError) as erro:
        return False, str(erro)
    return True, destino


# ---------- Etapa: repositório ----------


def clonar_ou_atualizar(avisar=_nada):
    """Clona o repositório do servidor, ou traz o que houver de novo.

    Devolve (ok, mensagem, mudou) — `mudou` diz se vale recompilar."""
    destino = pasta_repositorio()
    env = _ambiente_git()

    if not os.path.isdir(os.path.join(destino, ".git")):
        os.makedirs(os.path.dirname(destino), exist_ok=True)
        # Diretório meio-clonado de uma tentativa anterior: apagar é seguro,
        # nada de dados vive aqui (o banco está em pasta_dados()).
        if os.path.isdir(destino):
            shutil.rmtree(destino, ignore_errors=True)
        avisar("baixando o código do servidor")
        saida = rodar_git(
            "clone", "--branch", BRANCH, "--single-branch", REPOSITORIO, destino,
            cwd=pasta_base(), timeout=_TIMEOUT_GIT_LONGO, env_extra=env,
        )
        if saida is None:
            return False, (
                "Não foi possível clonar o repositório do servidor. Se a chave de deploy "
                "desta máquina ainda não foi cadastrada no GitHub, é isso."
            ), False
        return True, "código do servidor baixado.", True

    avisar("procurando atualizações do servidor")
    if rodar_git("fetch", "--quiet", "origin", BRANCH, cwd=destino, timeout=_TIMEOUT_GIT_LONGO, env_extra=env) is None:
        # Sem rede ou chave revogada: seguir com o que já está em disco é o
        # comportamento certo — o servidor continua rodando a versão anterior
        # em vez de a pizzaria ficar sem servidor por causa de um fetch.
        return True, "sem acesso ao repositório — usando a versão já baixada.", False

    atras = rodar_git("rev-list", "--count", f"HEAD..origin/{BRANCH}", cwd=destino, env_extra=env)
    if not atras or not atras.isdigit() or int(atras) == 0:
        return True, "já está na versão mais recente.", False

    avisar(f"aplicando {atras} atualização(ões) do servidor")
    if rodar_git("merge", "--ff-only", f"origin/{BRANCH}", cwd=destino, env_extra=env) is None:
        return False, "Há atualização do servidor, mas o merge falhou (checkout modificado à mão?).", False
    return True, f"Servidor atualizado ({atras} commit(s) novo(s)).", True


def commit_atual() -> str:
    return rodar_git("rev-parse", "--short", "HEAD", cwd=pasta_repositorio(), env_extra=_ambiente_git()) or ""


# ---------- Etapa: binário ----------


def binario_atualizado() -> bool:
    """True quando o binário em disco é mais novo que o último commit — o que
    torna todo o passo de build um no-op nas aberturas seguintes, que é o que
    mantém o custo do arranque perto de zero."""
    binario = caminho_binario()
    if not os.path.isfile(binario):
        return False
    cabeca = os.path.join(pasta_repositorio(), ".git", "HEAD")
    try:
        marca_do_codigo = os.path.getmtime(cabeca)
    except OSError:
        # Binário instalado, mas sem repositório clonado (clone falhou, ou
        # alguém copiou o executável à mão). Não há com o que comparar e
        # também não há como recompilar — o binário em disco é o melhor que
        # existe, e tratá-lo como desatualizado só levaria a uma tentativa de
        # build fadada a falhar.
        return True
    return os.path.getmtime(binario) >= marca_do_codigo


def baixar_binario_do_release(avisar=_nada):
    """Plano A: binário já compilado, publicado como GitHub Release.

    Vale a tentativa mesmo o repositório sendo privado — se ela falhar por
    404/401, cai pro build normalmente. O que se ganha quando dá certo são
    ~40 minutos e alguns GB de instalação por máquina."""
    if not eh_windows():
        return False, "Fora do Windows, compilar localmente é o caminho normal."
    alvo = "pizzeria-server-x86_64-pc-windows-msvc.exe"
    avisar("procurando um servidor já compilado")
    try:
        requisicao = urllib.request.Request(_REPO_HTTPS_RELEASES, headers={"User-Agent": "ppgs-system"})
        with urllib.request.urlopen(requisicao, timeout=30) as resposta:
            import json

            dados = json.load(resposta)
    except Exception as erro:
        return False, f"Sem release publicado ({erro})."

    for arquivo in dados.get("assets") or []:
        if arquivo.get("name") == alvo:
            avisar("baixando o servidor já compilado")
            ok, msg = _baixar(arquivo.get("browser_download_url", ""), caminho_binario())
            return ok, ("programa pronto baixado do GitHub Releases." if ok else f"Falha ao baixar o binário: {msg}")
    return False, "Nenhum release com binário para Windows."


def _total_de_pacotes() -> int:
    """Número de pacotes no Cargo.lock — o denominador do progresso do build."""
    try:
        with open(os.path.join(pasta_repositorio(), "Cargo.lock"), "r", encoding="utf-8") as arquivo:
            return arquivo.read().count("[[package]]")
    except OSError:
        return 0


def compilar(avisar=_nada):
    """Plano B: compilar do código, como pedido. Lento na primeira vez."""
    if not os.path.isdir(os.path.join(pasta_repositorio(), ".git")):
        return False, (
            "O código do servidor ainda não foi baixado nesta máquina — "
            "cadastre a chave de deploy no GitHub e tente de novo."
        )
    ok, msg = garantir_toolchain_rust(avisar)
    if not ok:
        return False, msg
    ok, msg = garantir_compilador_c(avisar)
    if not ok:
        return False, msg

    # Quantas dependências o cargo vai compilar, pra transformar "compilando"
    # numa fração que anda. Sai do Cargo.lock, que é a lista exata do que
    # será construído — se ele não puder ser lido, mostra só a contagem.
    total = _total_de_pacotes()
    progresso = {"n": 0}

    def ao_sair_linha(linha: str):
        # O cargo imprime uma linha "Compiling <crate> v<versão>" por
        # dependência. É o único sinal de progresso que ele dá sem
        # --message-format=json, e é suficiente.
        texto = linha.strip()
        if not texto.startswith("Compiling "):
            return
        progresso["n"] += 1
        nome = texto.split()[1] if len(texto.split()) > 1 else ""
        posicao = f"{progresso['n']}/{total}" if total else str(progresso["n"])
        avisar(f"compilando ({posicao}): {nome}")

    # -j 1 e prioridade ociosa: o objetivo aqui não é compilar rápido, é
    # compilar sem que o caixa perceba. Com todos os núcleos, o cargo deixa a
    # interface travada por minutos numa máquina de balcão.
    avisar("compilando o programa — a primeira vez leva bastante tempo")
    ok, saida = rodar(
        ["cargo", "build", "--release", "-j", "1"],
        cwd=pasta_repositorio(),
        timeout=_TIMEOUT_BUILD,
        ao_sair_linha=ao_sair_linha,
    )
    if not ok:
        return False, f"Falha ao compilar o servidor: {saida[-300:]}"

    origem = os.path.join(pasta_repositorio(), "target", "release", NOME_BINARIO)
    if not os.path.isfile(origem):
        return False, "Compilação terminou sem gerar o binário."
    try:
        shutil.copy2(origem, caminho_binario())
    except OSError as erro:
        return False, f"Binário compilado mas não foi possível copiá-lo: {erro}"
    return True, "compilado a partir do código."


def garantir_binario(precisa_recompilar: bool, avisar=_nada):
    if binario_atualizado() and not precisa_recompilar:
        return True, "programa já está pronto."
    ok, msg = baixar_binario_do_release(avisar)
    if ok:
        return True, msg
    print(f"[servidorLocal] {msg} Compilando do código.")
    return compilar(avisar)
