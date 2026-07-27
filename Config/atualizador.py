"""Confere se há atualizações no repositório Git do projeto antes de abrir
main.py e, se houver, pergunta ao usuário (janela) se quer atualizar agora
ou continuar com a versão atual.

Precisa rodar DEPOIS de preConfig.garantir_dependencias() (usa PyQt6 pra
mostrar a pergunta) e ANTES do resto do app ser importado (controllers,
services) — assim, se o usuário aceitar atualizar, o `git merge --ff-only`
já deixa os arquivos novos no disco a tempo dos imports seguintes pegarem o
código atualizado, sem precisar reiniciar o processo.

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

_TIMEOUT_GIT = 15


def _raiz_projeto():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _rodar_git(*args):
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
    }

    try:
        resultado = subprocess.run(
            ["git", *args],
            cwd=_raiz_projeto(),
            capture_output=True,
            text=True,
            timeout=_TIMEOUT_GIT,
            env=env,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as erro:
        print(f"[atualizador] Falha ao rodar 'git {' '.join(args)}': {erro}")
        return None

    if resultado.returncode != 0:
        print(f"[atualizador] 'git {' '.join(args)}' falhou: {resultado.stderr.strip()}")
        return None

    return resultado.stdout.strip()


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


def verificar_atualizacoes():
    """Ponto de entrada chamado por main.py. Devolve a instância de
    QApplication criada pra mostrar a pergunta, se alguma foi criada (pra
    main.py reaproveitar em vez de tentar criar uma segunda — só é possível
    existir uma por processo), ou None se não precisou perguntar nada."""
    if not _eh_repositorio_git():
        return None

    branch = _branch_atual()
    if not branch:
        print("[atualizador] HEAD solto (sem branch) — nada para checar.")
        return None

    versao = _versao_atual()
    if versao:
        _gravar_arquivo_versao(versao)
        print(f"[atualizador] Versão instalada: {versao}. Checando atualizações no repositório...")
    else:
        print("[atualizador] Checando atualizações no repositório...")

    if _rodar_git("fetch", "--quiet") is None:
        print("[atualizador] Não foi possível checar o remoto (sem internet/git?) — seguindo com a versão atual.")
        return None

    upstream = _upstream_de(branch)
    if not upstream:
        print(f"[atualizador] Branch '{branch}' não tem upstream configurado — nada para checar.")
        return None

    quantidade = _commits_atras(branch, upstream)
    if quantidade == 0:
        print("[atualizador] Já está na versão mais recente.")
        return None

    print(f"[atualizador] {quantidade} atualização(ões) disponível(is) em '{upstream}'.")

    try:
        from PyQt6.QtWidgets import QApplication
    except ImportError:
        # PyQt6 deveria estar instalado a essa altura (preConfig já rodou),
        # mas se por algum motivo não estiver, main.py tem seu próprio
        # try/except de import logo em seguida com uma mensagem melhor —
        # aqui só desiste da pergunta e segue.
        return None

    app = QApplication.instance() or QApplication(sys.argv)
    quer_atualizar = _perguntar_atualizar(quantidade, _resumo_commits_novos(branch, upstream))

    if quer_atualizar:
        _atualizar(branch, upstream)

    return app


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


def _guardar_cardapio_local():
    """Poe de lado (git stash) qualquer mudança não commitada em
    data/cardapio/*.json antes do merge — ver comentário em _atualizar()
    sobre por que esses arquivos ficam localmente modificados sozinhos.
    Devolve True se guardou algo (e portanto precisa tentar devolver
    depois), False se não havia nada pra guardar."""
    if not _ha_mudancas_locais_em("data/cardapio"):
        return False

    print("[atualizador] data/cardapio/*.json tem mudanças locais (provavelmente só a tela "
          "Cardápio salvando com \\r\\n no Windows, ver services/cardapioService.py) — guardando "
          "num stash antes de atualizar, pra não travar o merge.")
    _rodar_git("stash", "push", "--include-untracked", "--message", "atualizador: cardápio local antes de atualizar", "--", "data/cardapio")
    return True


def _desfazer_guarda_cardapio_local():
    """Só chamado quando o merge NÃO rolou — a árvore de trabalho
    continua exatamente onde estava quando _guardar_cardapio_local()
    guardou o stash, então reaplicar aqui é sempre seguro (não tem como
    dar conflito contra a mesma árvore de onde saiu)."""
    _rodar_git("stash", "pop")


def _atualizar(branch, upstream):
    from PyQt6.QtWidgets import QMessageBox

    print(f"[atualizador] Atualizando '{branch}' a partir de '{upstream}'...")

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
        # De propósito NÃO tenta "git stash pop" aqui: a árvore de trabalho
        # já avançou pro commit novo, então reaplicar o cardápio guardado
        # vira um merge de verdade — se o commit puxado tiver mexido nos
        # mesmos itens, o "pop" grava marcadores de conflito ("<<<<<<<")
        # direto no JSON, que nenhuma tela (Cardápio, Balcão, Entrega...)
        # consegue mais ler. Fica guardado em "git stash list" — recuperável
        # à mão depois — e o cardápio que acabou de vir da atualização vale
        # a partir daqui, sem risco de corromper o arquivo sozinho.
        print("[atualizador] Cardápio local guardado em 'git stash list' (não reaplicado "
              "automaticamente, pra não arriscar gravar conflito no JSON) — recupere com "
              "'git stash pop' na pasta do projeto se precisar daquela edição.")

    print("[atualizador] Atualizado com sucesso — usando o código novo a partir daqui.")

    versao_nova = _versao_atual()
    if versao_nova:
        _gravar_arquivo_versao(versao_nova)


if __name__ == "__main__":
    verificar_atualizacoes()
