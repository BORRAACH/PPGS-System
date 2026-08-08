"""Lançador do sistema para Windows — é isto que vira o .exe de duplo clique.

Não é o app: é um atalho executável que acha o Python certo e roda o main.py do
projeto. O sistema continua sendo os arquivos .py/.qml no disco, e isso é
proposital — o auto-atualizador (Config/atualizador.py) faz `git merge` e conta
que os imports seguintes leiam os arquivos novos. Empacotar o app inteiro num
.exe congelaria o código dentro do binário e a atualização automática pararia de
valer, além de levar junto data/cardapio/*.json, que a tela Cardápio edita e a
malha sincroniza em tempo de execução.

Só usa a biblioteca padrão, de propósito: ele precisa conseguir avisar que o
Python/PyQt6 está faltando, e não daria para fazer isso dependendo justamente
do que pode estar faltando.

Para gerar o .exe, ver launcher/gerar_exe.bat (roda no Windows).
"""

import os
import subprocess
import sys

_TITULO = "Sistema de Pedidos"


def _raiz_do_projeto():
    """Pasta onde está o main.py.

    Procura ao lado do executável e nos diretórios acima — cobre tanto o .exe
    na raiz do projeto quanto dentro de launcher/. Rodando como script (não
    empacotado), parte do próprio arquivo.

    Devolve None se não achar, que é o caso de alguém ter COPIADO o .exe para
    a Área de Trabalho em vez de criar um atalho."""
    if getattr(sys, "frozen", False):
        inicio = os.path.dirname(os.path.abspath(sys.executable))
    else:
        inicio = os.path.dirname(os.path.abspath(__file__))

    atual = inicio
    for _ in range(4):
        if os.path.isfile(os.path.join(atual, "main.py")):
            return atual
        pai = os.path.dirname(atual)
        if pai == atual:
            break
        atual = pai
    return None


def _pythons_candidatos(raiz):
    """Interpretadores a tentar, do mais específico para o mais genérico.

    O venv do projeto vem primeiro: é onde as dependências foram instaladas.
    "pythonw" antes de "python" em cada par porque ele não abre a janela preta
    de console junto do app — o console só apareceria para assustar o usuário,
    já que todo log do sistema vai para logs/app.log (ver Config/logConfig.py).
    """
    candidatos = [
        os.path.join(raiz, ".venv", "Scripts", "pythonw.exe"),
        os.path.join(raiz, ".venv", "Scripts", "python.exe"),
        # Linux/macOS: serve para testar este lançador fora do Windows.
        os.path.join(raiz, ".venv", "bin", "python"),
    ]

    # O py.exe (Python Launcher for Windows) é o jeito mais confiável de achar
    # uma instalação do sistema: ele existe mesmo quando o python.exe não está
    # no PATH, que é o padrão de quem instalou sem marcar "Add to PATH".
    candidatos += ["pythonw.exe", "python.exe", "pyw.exe", "py.exe", "python3", "python"]
    return candidatos


def _resolver_python(raiz):
    import shutil

    for candidato in _pythons_candidatos(raiz):
        if os.path.isabs(candidato):
            if os.path.isfile(candidato):
                return candidato
            continue
        caminho = shutil.which(candidato)
        if caminho:
            return caminho
    return None


def _avisar(mensagem):
    """Mostra o erro numa caixa do Windows; no resto, imprime.

    Sem isto, um .exe --noconsole que falha simplesmente não faz nada ao ser
    clicado, e não há onde ler o motivo."""
    print(f"[{_TITULO}] {mensagem}")
    if sys.platform != "win32":
        return

    try:
        import ctypes

        # 0x10 = MB_ICONERROR
        ctypes.windll.user32.MessageBoxW(None, mensagem, _TITULO, 0x10)
    except Exception:
        pass


def main():
    raiz = _raiz_do_projeto()
    if raiz is None:
        _avisar(
            "Não encontrei o arquivo main.py do sistema.\n\n"
            "Este atalho precisa ficar na pasta do projeto. Se você copiou o "
            "executável para a Área de Trabalho, apague a cópia e crie um "
            "ATALHO para ele no lugar (botão direito no .exe > Enviar para > "
            "Área de trabalho)."
        )
        return 1

    python = _resolver_python(raiz)
    if python is None:
        _avisar(
            "O Python não foi encontrado nesta máquina.\n\n"
            "Instale o Python 3.14 ou mais novo de python.org e marque a opção "
            '"Add Python to PATH" durante a instalação. Depois é só abrir este '
            "atalho de novo — o sistema instala o resto sozinho."
        )
        return 1

    main_py = os.path.join(raiz, "main.py")
    try:
        # cwd na raiz porque o app monta caminhos a partir dela (pedidos/,
        # data/cardapio/, logs/). Sem isso, abrir pelo atalho gravaria comanda
        # em qualquer pasta de onde o Windows resolvesse iniciar o processo.
        processo = subprocess.Popen([python, main_py], cwd=raiz)
    except OSError as erro:
        _avisar(f"Não foi possível iniciar o sistema:\n\n{erro}")
        return 1

    # Espera o app terminar em vez de sair na hora: assim o .exe representa o
    # sistema na barra de tarefas e no Gerenciador de Tarefas enquanto ele
    # roda, e fechar o lançador não deixa um processo órfão.
    return processo.wait()


if __name__ == "__main__":
    sys.exit(main())
