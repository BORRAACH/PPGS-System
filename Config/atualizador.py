"""Confere se há atualizações no repositório Git do projeto antes de abrir
main.py e, se houver, pergunta ao usuário (janela) se quer atualizar agora
ou continuar com a versão atual.

Precisa rodar DEPOIS de preConfig.garantir_dependencias() (usa PyQt6 pra
mostrar a pergunta) e ANTES do resto do app ser importado (controllers,
services) — assim, se o usuário aceitar atualizar, o `git merge --ff-only`
já deixa os arquivos novos no disco a tempo dos imports seguintes pegarem o
código atualizado, sem precisar reiniciar o processo.

Essa posição custa caro na abertura: o `git fetch` daqui é o passo mais lento
do arranque (~1,6s medido, e até _TIMEOUT_GIT=15s com internet ruim), todo ele
antes de qualquer coisa aparecer na tela. Já foi tentado adiá-lo para depois
da janela, junto das outras tarefas de arranque (ver main.py), e foi
revertido: com o app já carregado em memória, a atualização aceita só passaria
a valer na abertura seguinte. É uma troca deliberada de tempo de abertura por
atualização que vale na hora. O resultado da checagem fica em
ultimo_resultado() para a interface poder contá-lo assim que existir uma.

Só faz sentido rodar num checkout que seja de fato um repositório git com
upstream configurado; qualquer outra coisa (sem `.git`, sem internet, sem
`git` instalado, branch "solta"/detached) faz verificar_atualizacoes()
desistir silenciosamente (só um log no console) e o app abre normalmente
com a versão atual — nunca trava a abertura por causa disso.

Roda em QUALQUER checkout, incluindo o de desenvolvimento — não existe
mais distinção entre "máquina de deploy" e "máquina de dev": se o checkout
está atrás do upstream, pergunta se quer atualizar, seja lá onde estiver
rodando. Antes disso era gateado por um arquivo Config/.versao criado à
mão em cada máquina da pizzaria, mas isso exigia um passo manual fácil de
esquecer; agora Config/.versao é só informativo (guarda a versão do commit
atual, tipo `git describe`), reescrito sozinho a cada execução — não é
usado pra decidir nada, só pra você conferir a versão instalada olhando o
arquivo. Continua fora do git (.gitignore) porque o valor é específico de
cada máquina/commit.
"""

import os
import subprocess
import sys
import traceback

from Config import mesclarCardapio

_TIMEOUT_GIT = 15


def _raiz_projeto():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def rodar_git(*args, cwd=None, timeout=None, env_extra=None):
    """Roda um comando git e devolve a saída, ou None se ele falhou.

    Público (e com `cwd`/`env_extra`) porque
    services/servidor/servidorLocal.py clona e atualiza o repositório do
    ppgs_server com exatamente os mesmos cuidados desta função — os três
    detalhes abaixo (BatchMode, encoding explícito e timeout) já custaram
    incidentes reais em produção, e reimplementá-los noutro arquivo seria
    convidar os mesmos incidentes de volta. `env_extra` existe pro
    servidorLocal poder apontar o GIT_SSH_COMMAND pra deploy key dele sem
    mexer no ambiente do processo inteiro."""
    # Sem isso, um "git fetch" contra um remoto SSH sem a chave já
    # destravada no agente trava esperando a senha da chave (via askpass) —
    # e como main.py roda essa checagem toda vez que abre (inclusive a cada
    # reinício automático do dev_watch.py durante o desenvolvimento), isso
    # interromperia a abertura do app com um prompt de senha o tempo todo.
    # BatchMode=yes faz o ssh falhar rápido em vez de perguntar; o
    # resultado (retorno != 0) já cai no mesmo fallback usado para "sem
    # internet".
    env = {
        **os.environ,
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_SSH_COMMAND": os.environ.get("GIT_SSH_COMMAND", "ssh") + " -o BatchMode=yes -o ConnectTimeout=10",
        **(env_extra or {}),
    }

    try:
        resultado = subprocess.run(
            ["git", *args],
            cwd=cwd or _raiz_projeto(),
            capture_output=True,
            text=True,
            # Sem isto, text=True decodifica com o encoding do LOCALE — no
            # Windows pt-BR, cp1252 — e "git show HEAD:data/cardapio/*.json"
            # (ver _atualizar) despeja um arquivo UTF-8 cheio de acentos. O
            # byte 0x81 (segundo byte de "Á" em UTF-8) é indefinido em
            # cp1252, e o UnicodeDecodeError estourava DENTRO da thread que
            # o subprocess usa pra ler o pipe no Windows: a thread morria,
            # resultado.stdout voltava None e o .strip() aqui embaixo virava
            # AttributeError — a atualização abortava antes do merge, e a
            # máquina ficava presa na versão antiga a cada abertura.
            #
            # git fala UTF-8: tanto as mensagens dele quanto (aqui, o que
            # importa) o conteúdo cru dos arquivos que "git show" imprime.
            # errors="replace" é rede de segurança — decodificar a saída do
            # git nunca mais pode derrubar a atualização, mesmo que algum
            # arquivo do repositório deixe de ser UTF-8 válido um dia.
            encoding="utf-8",
            errors="replace",
            timeout=timeout or _TIMEOUT_GIT,
            env=env,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as erro:
        print(f"[atualizador] Falha ao rodar 'git {' '.join(args)}': {erro}")
        return None

    if resultado.returncode != 0:
        print(f"[atualizador] 'git {' '.join(args)}' falhou: {(resultado.stderr or '').strip()}")
        return None

    # stdout/stderr podem vir None se a leitura do pipe falhar por um motivo
    # que não seja decodificação (o caso acima já não acontece mais). Tratar
    # como saída vazia mantém o contrato de "None só quando o comando
    # falhou" — um AttributeError aqui abortaria a atualização inteira.
    return (resultado.stdout or "").strip()


# Nome interno original, mantido pras chamadas já existentes neste arquivo.
_rodar_git = rodar_git


def _eh_repositorio_git():
    return os.path.isdir(os.path.join(_raiz_projeto(), ".git"))


def _versao_atual():
    """Deriva um identificador de versão a partir do commit atual (`git
    describe`) — hash curto, ou a tag mais próxima + distância se o
    repositório tiver tags no futuro. None se não for possível (ex: git não
    instalado)."""
    return _rodar_git("describe", "--tags", "--always", "--dirty")


def _gravar_arquivo_versao(versao):
    """Reescreve Config/.versao com `versao` — só informativo (não gateia
    nada em verificar_atualizacoes()), pra quem olhar a pasta conseguir
    conferir qual commit está instalado nessa máquina sem rodar git."""
    caminho = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".versao")
    try:
        with open(caminho, "w", encoding="utf-8") as arquivo:
            arquivo.write(versao + "\n")
    except OSError as erro:
        print(f"[atualizador] Falha ao gravar Config/.versao: {erro}")


def _branch_atual():
    """Devolve o nome da branch local, ou None se for HEAD solto (detached
    — ex: checkout de uma tag/commit específico), onde não faz sentido
    comparar/atualizar nada."""
    branch = _rodar_git("rev-parse", "--abbrev-ref", "HEAD")
    if not branch or branch == "HEAD":
        return None
    return branch


def _upstream_de(branch):
    """Ex: "master" -> "origin/master", ou None se a branch não tiver
    upstream configurado."""
    return _rodar_git("rev-parse", "--abbrev-ref", "--symbolic-full-name", branch + "@{upstream}") or None


def _commits_atras(branch, upstream):
    saida = _rodar_git("rev-list", "--count", f"{branch}..{upstream}")
    if saida is None or not saida.isdigit():
        return 0
    return int(saida)


def _resumo_commits_novos(branch, upstream, limite=8):
    return _rodar_git("log", "--oneline", f"{branch}..{upstream}", f"-{limite}") or ""


def _qapplication_existente():
    """A QApplication já criada neste processo, se houver — usada só pelo
    fallback de erro abaixo, pra main.py continuar recebendo a instância
    mesmo quando a atualização falhou depois de tê-la criado."""
    try:
        from PyQt6.QtWidgets import QApplication
    except ImportError:
        return None
    return QApplication.instance()


def verificar_atualizacoes():
    """Ponto de entrada chamado por main.py. Devolve a instância de
    QApplication criada pra mostrar a pergunta, se alguma foi criada (pra
    main.py reaproveitar em vez de tentar criar uma segunda — só é possível
    existir uma por processo), ou None se não precisou perguntar nada.

    Nunca levanta exceção. Isto não é zelo genérico: o atualizador é o
    único componente do app que, quando quebra, não consegue entregar a
    própria correção — uma exceção aqui aborta o update, a máquina fica
    presa na versão antiga e passa a falhar exatamente igual em TODA
    abertura seguinte, sem chance de se recuperar sozinha por mais commits
    que sejam publicados. Foi o que aconteceu de verdade com o
    UnicodeDecodeError de _rodar_git (ver o comentário lá): as máquinas só
    voltaram a atualizar com um `git pull` feito na mão em cada uma.

    Falhar aqui vira "abre com a versão atual" + traceback no log
    (logs/app.log, ver Config/logConfig.py), que é sempre recuperável: o
    app abre normal e a atualização é tentada de novo na próxima abertura,
    já com o código novo se ele tiver entrado."""
    try:
        quantidade, branch, upstream, resumo = checar_atualizacoes()
        if not quantidade:
            return _qapplication_existente()

        # A pergunta precisa de uma QApplication, e ela pode não existir
        # ainda: isto roda antes do main.py criar a dele. Quem for criada
        # aqui volta para o main.py reaproveitar — só pode haver uma por
        # processo.
        try:
            from PyQt6.QtWidgets import QApplication
        except ImportError:
            # preConfig já deveria ter garantido o PyQt6; se não garantiu,
            # main.py tem seu próprio try/except de import logo em seguida,
            # com mensagem melhor. Aqui só desiste da pergunta e segue.
            return None

        app = QApplication.instance() or QApplication(sys.argv)
        perguntar_e_atualizar(quantidade, branch, upstream, resumo)
        return app
    except Exception:
        print(
            "[atualizador] Falha inesperada ao checar/aplicar a atualização — abrindo com a "
            f"versão atual. Detalhes:\n{traceback.format_exc().rstrip()}",
            file=sys.stderr,
        )
        return _qapplication_existente()


# O que a checagem concluiu, para a interface contar ao usuário depois. Fica
# guardado porque o atualizador roda ANTES de existir qualquer janela: quando
# a caixa de status aparece (ver services/statusInicializacaoService.py), isto
# já aconteceu — sem registrar, não haveria como dizer o que foi feito.
_ultimo_resultado = ("Atualizações não verificadas", False)


def ultimo_resultado():
    """(texto, deu_certo) da última checagem deste processo."""
    return _ultimo_resultado


def _registrar(texto, ok=True):
    global _ultimo_resultado
    _ultimo_resultado = (texto, ok)


def checar_atualizacoes():
    """A parte LENTA e sem interface do atualizador: descobre se há commits
    novos no remoto. Devolve (quantidade, branch, upstream, resumo), com
    quantidade 0 quando não há nada a fazer.

    Existe separada de verificar_atualizacoes() para poder rodar numa thread
    depois que a janela já abriu: o `git fetch` daqui é o que mais pesa na
    abertura do app (~1,6s medido, e até _TIMEOUT_GIT=15s com internet ruim),
    e nada dele precisa acontecer antes de desenhar a tela. A pergunta ao
    usuário e o merge continuam do outro lado, na thread da interface — abrir
    um QMessageBox de uma thread de fundo não é permitido pelo Qt.

    Nunca levanta: erro aqui vira "nenhuma atualização" e a tentativa se
    repete na próxima abertura (ver o docstring de verificar_atualizacoes)."""
    try:
        if not _eh_repositorio_git():
            _registrar("Sem controle de versão — atualização não checada", False)
            return 0, "", "", ""

        branch = _branch_atual()
        if not branch:
            print("[atualizador] HEAD solto (sem branch) — nada para checar.")
            _registrar("Atualização não checada (sem branch)", False)
            return 0, "", "", ""

        versao = _versao_atual()
        if versao:
            _gravar_arquivo_versao(versao)
            print(f"[atualizador] Versão instalada: {versao}. Checando atualizações no repositório...")

        if _rodar_git("fetch", "--quiet") is None:
            print("[atualizador] Não foi possível checar o remoto (sem internet/git?) — seguindo com a versão atual.")
            _registrar("Sem conexão para checar atualizações", False)
            return 0, "", "", ""

        upstream = _upstream_de(branch)
        if not upstream:
            print(f"[atualizador] Branch '{branch}' não tem upstream configurado — nada para checar.")
            _registrar("Atualização não checada (sem upstream)", False)
            return 0, "", "", ""

        quantidade = _commits_atras(branch, upstream)
        if not quantidade:
            print("[atualizador] Já está na versão mais recente.")
            _registrar("Sistema já está atualizado")
            return 0, branch, upstream, ""

        print(f"[atualizador] {quantidade} atualização(ões) disponível(is) em '{upstream}'.")
        return quantidade, branch, upstream, _resumo_commits_novos(branch, upstream)
    except Exception:
        print(
            "[atualizador] Falha inesperada ao checar a atualização — seguindo com a versão "
            f"atual. Detalhes:\n{traceback.format_exc().rstrip()}",
            file=sys.stderr,
        )
        return 0, "", "", ""


def perguntar_e_atualizar(quantidade, branch, upstream, resumo):
    """A parte com interface: pergunta e, se o usuário aceitar, aplica. Tem
    que rodar na thread da interface. Devolve True se atualizou."""
    try:
        if not quantidade or not branch or not upstream:
            return False

        if not _perguntar_atualizar(quantidade, resumo):
            _registrar("Atualização adiada pelo usuário", False)
            return False

        _atualizar(branch, upstream)
        _registrar(f"{quantidade} atualização(ões) aplicada(s)")
        return True
    except Exception:
        print(
            "[atualizador] Falha inesperada ao aplicar a atualização — seguindo com a versão "
            f"atual. Detalhes:\n{traceback.format_exc().rstrip()}",
            file=sys.stderr,
        )
        return False


def _perguntar_atualizar(quantidade, resumo):
    from PyQt6.QtWidgets import QMessageBox

    texto = f"Há {quantidade} atualização(ões) disponível(is) para o sistema."
    if resumo:
        texto += f"\n\nNovidades:\n{resumo}"
    texto += "\n\nAtualizar agora?"

    caixa = QMessageBox()
    caixa.setWindowTitle("Atualização disponível")
    caixa.setIcon(QMessageBox.Icon.Question)
    caixa.setText(texto)
    botao_atualizar = caixa.addButton("Atualizar agora", QMessageBox.ButtonRole.AcceptRole)
    caixa.addButton("Continuar com a versão atual", QMessageBox.ButtonRole.RejectRole)
    caixa.setDefaultButton(botao_atualizar)
    caixa.exec()

    return caixa.clickedButton() is botao_atualizar


def _ha_mudancas_locais_em(caminho):
    """True se `caminho` (relativo à raiz do projeto) tem alguma mudança
    não commitada — modificada, staged ou não rastreada."""
    saida = _rodar_git("status", "--porcelain", "--", caminho)
    return bool(saida)


def _caminho_relativo_cardapio(nome_arquivo):
    # Sempre com "/" (não os.path.join): isto também alimenta "git show
    # HEAD:<caminho>" abaixo, e o git usa "/" no seu modelo de objetos
    # mesmo rodando no Windows — um separador errado ali simplesmente não
    # acha o blob. os.path.join com o resultado ainda funciona certo pra
    # abrir o arquivo de verdade (Windows aceita "/" também).
    return f"data/cardapio/{nome_arquivo}"


def _arquivos_cardapio_modificados_localmente():
    """Nomes dos data/cardapio/*.json (ex: "pizzas.json", sem o caminho)
    reconhecidos por Config/mesclarCardapio.py com mudança não commitada
    nesta máquina agora."""
    saida = _rodar_git("status", "--porcelain", "--", "data/cardapio")
    if not saida:
        return []

    encontrados = []
    for linha in saida.splitlines():
        nome_arquivo = os.path.basename(linha[3:].strip())
        if nome_arquivo in mesclarCardapio.CAMPOS_PRECO_POR_ARQUIVO and nome_arquivo not in encontrados:
            encontrados.append(nome_arquivo)
    return encontrados


def _ler_arquivo_projeto(caminho_relativo):
    caminho_absoluto = os.path.join(_raiz_projeto(), caminho_relativo)
    try:
        with open(caminho_absoluto, "r", encoding="utf-8") as arquivo:
            return arquivo.read()
    except OSError as erro:
        print(f"[atualizador] Falha ao ler {caminho_relativo}: {erro}")
        return None


def _escrever_arquivo_projeto(caminho_relativo, conteudo):
    caminho_absoluto = os.path.join(_raiz_projeto(), caminho_relativo)
    try:
        # newline="\n" pelo mesmo motivo de services/cardapioService.py:
        # salvar() — sem isso o Python no Windows reintroduziria "\r\n" e
        # o problema que este módulo existe pra evitar voltaria no
        # próximo update.
        with open(caminho_absoluto, "w", encoding="utf-8", newline="\n") as arquivo:
            arquivo.write(conteudo)
        return True
    except OSError as erro:
        print(f"[atualizador] Falha ao gravar {caminho_relativo} mesclado: {erro}")
        return False


def _guardar_cardapio_local():
    """Poe de lado (git stash) qualquer mudança não commitada em
    data/cardapio/*.json antes do merge — ver comentário em _atualizar()
    sobre por que esses arquivos costumam ficar localmente modificados
    sozinhos. Devolve True se guardou algo (e portanto precisa tentar
    devolver/mesclar depois), False se não havia nada pra guardar."""
    if not _ha_mudancas_locais_em("data/cardapio"):
        return False

    print("[atualizador] data/cardapio/*.json tem mudanças locais nesta máquina — guardando "
          "num stash antes de atualizar, pra não travar o merge (ver Config/mesclarCardapio.py "
          "pra como isso é reaplicado por cima da atualização).")
    _rodar_git("stash", "push", "--include-untracked", "--message", "atualizador: cardápio local antes de atualizar", "--", "data/cardapio")
    return True


def _desfazer_guarda_cardapio_local():
    """Só chamado quando o merge NÃO rolou — a árvore de trabalho
    continua exatamente onde estava quando _guardar_cardapio_local()
    guardou o stash, então reaplicar aqui é sempre seguro (não tem como
    dar conflito contra a mesma árvore de onde saiu)."""
    _rodar_git("stash", "pop")


def _mesclar_cardapios_locais(arquivos, conteudo_base, conteudo_local):
    """Chamado depois de um merge bem-sucedido, com o stash de
    _guardar_cardapio_local() ainda guardado: pra cada arquivo que tinha
    edição local, mescla com o que acabou de vir da atualização (preço
    editado localmente prevalece, resto — inclusive itens novos/removidos
    — vem da atualização; ver Config/mesclarCardapio.py) e grava por cima
    da versão "só remota" que o merge deixou no disco.

    Sempre descarta o stash no final: seu conteúdo relevante já foi
    incorporado (ou, na pior hipótese — JSON local inválido, por exemplo
    — mesclarCardapio.mesclar() decidiu de propósito manter só a versão
    da atualização, e não há nada a mais pra recuperar dali)."""
    for nome_arquivo in arquivos:
        caminho_relativo = _caminho_relativo_cardapio(nome_arquivo)
        texto_atualizado = _ler_arquivo_projeto(caminho_relativo)
        if texto_atualizado is None:
            continue

        texto_mesclado = mesclarCardapio.mesclar(
            nome_arquivo,
            conteudo_base.get(nome_arquivo) or "",
            conteudo_local.get(nome_arquivo) or "",
            texto_atualizado,
        )
        if texto_mesclado != texto_atualizado and _escrever_arquivo_projeto(caminho_relativo, texto_mesclado):
            print(f"[atualizador] {caminho_relativo}: mesclado com a edição local desta máquina "
                  "(preços editados aqui foram preservados).")

    _rodar_git("stash", "drop")


def _atualizar(branch, upstream):
    from PyQt6.QtWidgets import QMessageBox

    print(f"[atualizador] Atualizando '{branch}' a partir de '{upstream}'...")

    # Precisa ler a base (versão no commit atual) e o local (o que está no
    # disco agora, não commitado) ANTES de guardar/mesclar qualquer coisa —
    # depois do "git stash push" o arquivo no disco já não é mais "o
    # local", é a versão da base de volta.
    arquivos_cardapio_locais = _arquivos_cardapio_modificados_localmente()
    conteudo_base = {}
    conteudo_local = {}
    for nome_arquivo in arquivos_cardapio_locais:
        caminho_relativo = _caminho_relativo_cardapio(nome_arquivo)
        conteudo_base[nome_arquivo] = _rodar_git("show", f"HEAD:{caminho_relativo}") or ""
        conteudo_local[nome_arquivo] = _ler_arquivo_projeto(caminho_relativo) or ""

    guardou_cardapio = _guardar_cardapio_local()
    resultado_merge = _rodar_git("merge", "--ff-only", upstream)

    if resultado_merge is None:
        if guardou_cardapio:
            # O merge falhou por outro motivo (não pelo cardápio, que já
            # tiramos do caminho) — devolve como estava antes de desistir.
            _desfazer_guarda_cardapio_local()
        QMessageBox.warning(
            None,
            "Falha ao atualizar",
            "Não foi possível atualizar automaticamente (pode haver mudanças locais no "
            "repositório que impedem a atualização direta). Abrindo com a versão atual — "
            "para atualizar manualmente, rode 'git pull' na pasta do projeto.",
        )
        return

    if guardou_cardapio:
        _mesclar_cardapios_locais(arquivos_cardapio_locais, conteudo_base, conteudo_local)

    print("[atualizador] Atualizado com sucesso — usando o código novo a partir daqui.")

    versao_nova = _versao_atual()
    if versao_nova:
        _gravar_arquivo_versao(versao_nova)


if __name__ == "__main__":
    verificar_atualizacoes()
