"""Atalho na pasta Inicializar do Windows, para o sistema (e com ele o
ppgs_server) subir sozinho quando a máquina liga.

Por que passa pelo APP e não sobe o servidor direto: o transporte das outras
máquinas até o servidor é a malha (ver RedeService.solicitar_servidor), e a
malha só existe com o app aberto. Um servidor no ar com o sistema fechado não
atenderia balcão nenhum além do próprio. Subir o app, portanto, é o que
realmente coloca o servidor central em serviço — e ele já sabe subir o servidor
sozinho quando esta é a máquina designada (services/servidor/servidorLocal.py).

O atalho aponta para o SistemaDePedidos.exe quando ele existe e, senão, para o
pythonw do projeto com o main.py como argumento — a mesma ordem de preferência
de launcher/iniciar.py, e pelo mesmo motivo: o "w" não abre a janela preta de
console junto do app.

Não guarda estado próprio em lugar nenhum: "está ligado?" é "o arquivo existe?".
Um flag em JSON poderia discordar da realidade (alguém apaga o atalho pelo
Explorador) e passaria a mentir na tela de Rede.
"""

import os

from services.rede import caminhos
from services.servidor import preparo

_NOME_ATALHO = "Sistema de Pedidos"


def disponivel() -> bool:
    """Só Windows tem "pasta Inicializar". No Linux o equivalente seria um
    .desktop em ~/.config/autostart, mas as máquinas do balcão são Windows e um
    caminho que ninguém usa é um caminho que ninguém testa."""
    return preparo.eh_windows()


def _pasta_inicializar() -> str:
    """A pasta Inicializar do usuário atual.

    Pergunta ao Windows em vez de montar o caminho na mão: em português ele é
    "Menu Iniciar\\Programas\\Inicializar", em inglês "Start Menu\\Programs\\
    Startup", e a máquina da pizzaria pode ser qualquer um dos dois. O caminho
    fixo em inglês fica só como último recurso."""
    try:
        import win32com.client

        pasta = win32com.client.Dispatch("WScript.Shell").SpecialFolders("Startup")
        if pasta:
            return str(pasta)
    except Exception:
        pass
    return os.path.join(
        os.environ.get("APPDATA", ""), "Microsoft", "Windows", "Start Menu", "Programs", "Startup"
    )


def _alvo():
    """(programa, argumentos) do que o atalho deve executar."""
    raiz = caminhos.raiz_projeto()

    executavel = os.path.join(raiz, "SistemaDePedidos.exe")
    if os.path.isfile(executavel):
        return executavel, ""

    for candidato in ("pythonw.exe", "python.exe"):
        python = os.path.join(raiz, ".venv", "Scripts", candidato)
        if os.path.isfile(python):
            return python, "main.py"

    # Sem venv: o pythonw do PATH ainda resolve, e se ele também não existir o
    # próprio atalho falha na cara do usuário com a mensagem do Windows — o que
    # é melhor que este módulo adivinhar um caminho que não existe.
    return "pythonw.exe", "main.py"


def _caminho_atalho() -> str:
    return os.path.join(_pasta_inicializar(), f"{_NOME_ATALHO}.lnk")


def _caminho_alternativo() -> str:
    """O .bat de reserva, para quando o COM do Windows não estiver disponível
    (instalação sem pywin32 funcional). Faz a mesma coisa, mais feio."""
    return os.path.join(_pasta_inicializar(), f"{_NOME_ATALHO}.bat")


def ativo() -> bool:
    if not disponivel():
        return False
    return os.path.isfile(_caminho_atalho()) or os.path.isfile(_caminho_alternativo())


def ativar():
    """Cria o atalho. Devolve (ok, mensagem) — nunca levanta: isto é uma
    conveniência, e falhar aqui não pode derrubar a tela de Rede."""
    if not disponivel():
        return False, "Iniciar com o sistema operacional só está disponível no Windows."

    programa, argumentos = _alvo()
    raiz = caminhos.raiz_projeto()

    try:
        import win32com.client

        atalho = win32com.client.Dispatch("WScript.Shell").CreateShortCut(_caminho_atalho())
        atalho.TargetPath = programa
        atalho.Arguments = argumentos
        # Não é detalhe: o .exe procura o main.py ao lado dele, e o main.py
        # monta caminhos a partir da raiz do projeto. Um atalho disparado com o
        # diretório de trabalho em System32 não acharia nem um nem outro.
        atalho.WorkingDirectory = raiz
        atalho.Description = "Sistema de Pedidos da pizzaria"
        atalho.save()
    except Exception as erro:
        print(f"[autostart] Não foi possível criar o atalho (.lnk): {erro} — usando um .bat.")
        return _ativar_com_bat(programa, argumentos, raiz)

    # Um .bat de uma tentativa anterior continuaria abrindo um segundo app
    # junto com o do atalho.
    _remover(_caminho_alternativo())
    return True, f"O sistema passa a abrir junto com o Windows ({_caminho_atalho()})."


def _ativar_com_bat(programa, argumentos, raiz):
    conteudo = f'@echo off\r\ncd /d "{raiz}"\r\nstart "" "{programa}" {argumentos}\r\n'
    try:
        with open(_caminho_alternativo(), "w", encoding="utf-8") as arquivo:
            arquivo.write(conteudo)
    except OSError as erro:
        return False, f"Não foi possível criar o atalho de inicialização: {erro}"
    return True, f"O sistema passa a abrir junto com o Windows ({_caminho_alternativo()})."


def desativar():
    """Remove o atalho (as duas formas dele). Devolve (ok, mensagem)."""
    if not disponivel():
        return True, "Nada a desfazer fora do Windows."

    erros = [erro for erro in (_remover(_caminho_atalho()), _remover(_caminho_alternativo())) if erro]
    if erros:
        return False, f"Não foi possível remover o atalho de inicialização: {erros[0]}"
    return True, "O sistema não abre mais junto com o Windows."


def _remover(caminho):
    """Apaga se existir. Devolve o erro (string) ou None."""
    try:
        os.remove(caminho)
    except FileNotFoundError:
        return None
    except OSError as erro:
        return str(erro)
    return None
