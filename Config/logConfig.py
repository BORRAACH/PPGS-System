"""Redireciona toda a saída do app (stdout/stderr) — incluindo os
inúmeros `print()` de diagnóstico já espalhados pelos módulos de
impressão/rede — para um arquivo de log rotativo, além do console
(quando existir um).

Por quê: no Windows, quando o app roda "clicando duas vezes" no ícone
(sem console aberto), tudo que é escrito em print() simplesmente
desaparece — não tem pra onde ir. Isso torna impossível diagnosticar por
que uma impressão "não fez nada", porque os logs que já existem (ex:
services/printer/windows.py, services/rede/redeService.py) nunca chegam a
lugar nenhum. Depois de chamar configurar_logging(), os mesmos prints
continuam aparecendo no console quando há um (ex: rodando via terminal ou
dev_watch.py) E também ficam gravados em logs/app.log, disponíveis pra
inspeção mesmo depois do app ser fechado.

Chamado uma única vez, o mais cedo possível em main.py — antes de
qualquer outro import que já imprima algo (preConfig, atualizador etc.),
senão essas primeiras linhas escapam do log.
"""

import functools
import logging
import logging.handlers
import os
import sys
import threading
import traceback

_NOME_ARQUIVO = "app.log"
_TAMANHO_MAXIMO_BYTES = 2 * 1024 * 1024  # 2 MiB por arquivo
_QTD_BACKUPS = 3

_logger = logging.getLogger("pizzeria")
_ja_configurado = False


class _EscritaParaLog:
    """Arquivo-like que repassa cada write() tanto pro stream original
    (console, quando existir) quanto pro logger — assim substitui
    sys.stdout/sys.stderr sem precisar tocar em cada um dos vários pontos
    do código que já chamam print() diretamente. Guarda o texto em buffer
    até fechar uma linha, pra cada print() virar exatamente uma linha no
    log (em vez de fragmentos, já que print() faz duas chamadas a write()
    — uma pro texto, outra pro "\\n" final)."""

    def __init__(self, stream_original, nivel):
        self._stream_original = stream_original
        self._nivel = nivel
        self._buffer = ""

    def write(self, texto):
        if self._stream_original is not None:
            try:
                self._stream_original.write(texto)
            except Exception:
                pass  # Sem console de verdade (pythonw/exe sem terminal) — ignora.

        self._buffer += texto
        while "\n" in self._buffer:
            linha, self._buffer = self._buffer.split("\n", 1)
            if linha:
                _logger.log(self._nivel, linha)

    def flush(self):
        if self._stream_original is not None:
            try:
                self._stream_original.flush()
            except Exception:
                pass

    def isatty(self):
        return False


def _raiz_projeto():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def caminho_arquivo_log():
    return os.path.join(_raiz_projeto(), "logs", _NOME_ARQUIVO)


def configurar_logging():
    """Idempotente — chamar mais de uma vez (ex: main.py e um script de
    diagnóstico rodado dentro do mesmo processo de testes) não duplica
    handlers nem re-substitui stdout/stderr já substituídos."""
    global _ja_configurado
    if _ja_configurado:
        return
    _ja_configurado = True

    caminho = caminho_arquivo_log()
    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
    except OSError as erro:
        # Sem permissão de escrever a pasta de logs: segue só com o
        # console (se houver) em vez de derrubar o app inteiro por causa
        # de diagnóstico.
        print(f"[logConfig] Não foi possível criar a pasta de logs ({erro}) — seguindo sem gravar em arquivo.")
        return

    _logger.setLevel(logging.INFO)
    _logger.propagate = False

    handler = logging.handlers.RotatingFileHandler(
        caminho, maxBytes=_TAMANHO_MAXIMO_BYTES, backupCount=_QTD_BACKUPS, encoding="utf-8"
    )
    handler.setFormatter(logging.Formatter("%(asctime)s %(message)s", datefmt="%Y-%m-%d %H:%M:%S"))
    _logger.addHandler(handler)

    sys.stdout = _EscritaParaLog(sys.stdout, logging.INFO)
    sys.stderr = _EscritaParaLog(sys.stderr, logging.ERROR)

    _instalar_captura_de_excecoes()

    print(f"[logConfig] Log de diagnóstico sendo gravado em: {caminho}")


def _instalar_captura_de_excecoes():
    """Faz toda exceção não tratada virar linha no log — e, no caso das que
    vêm de dentro do Qt, impede que ela derrube o app.

    O motivo é específico do PyQt6: quando um slot Python chamado a partir
    do QML (um onClicked, um binding...) deixa escapar uma exceção, o PyQt
    chama qFatal(), que aborta o processo com SIGABRT na hora — a janela
    simplesmente some, sem diálogo e sem nada no console. Pior: nesse
    caminho o traceback é escrito por dentro do C, sem passar pelos
    sys.stdout/sys.stderr trocados acima, então logs/app.log fica com um
    silêncio total exatamente no momento em que o app morreu.

    O PyQt só aborta quando sys.excepthook ainda é o padrão do Python.
    Trocando o hook (como aqui), ele apenas o chama e a aplicação continua
    de pé — o pedido em andamento não é perdido por causa de um erro numa
    tela. Registra o traceback inteiro no log pra dar pra diagnosticar
    depois."""

    def _ao_escapar_excecao(tipo, valor, tb):
        texto = "".join(traceback.format_exception(tipo, valor, tb)).rstrip()
        print(f"[erro] Exceção não tratada (o app continua rodando):\n{texto}", file=sys.stderr)

    def _ao_escapar_excecao_em_thread(args):
        if args.exc_type is SystemExit:
            return
        _ao_escapar_excecao(args.exc_type, args.exc_value, args.exc_traceback)

    sys.excepthook = _ao_escapar_excecao
    threading.excepthook = _ao_escapar_excecao_em_thread


def protegido(valor_padrao=None):
    """Decorador para os métodos expostos à QML (os @pyqtSlot dos
    controllers): captura qualquer exceção que escape do corpo, registra o
    traceback no log e devolve `valor_padrao` em vez de deixar o erro voltar
    pro Qt.

    Fica ABAIXO dos @pyqtSlot (aplicado primeiro, colado na função), pra que
    a assinatura registrada no Qt continue sendo exatamente a declarada — e
    pra funcionar igual nos slots com sobrecarga (dois @pyqtSlot empilhados
    na mesma função, como enviarPedido).

    Por que o sys.excepthook instalado acima não basta: ele impede o PyQt6 de
    abortar o processo, mas o slot ainda devolve pra QML um valor não
    inicializado — e, num slot declarado com `result=bool`, o que a QML
    observa é `true`. Sem este decorador, um enviarPedido() que estoura no
    meio faz a tela mostrar "Pedido salvo com sucesso!", limpar o formulário
    e (quando a comanda foi aberta pela Consulta para edição) apagar o
    arquivo original: o pedido some e o atendente nem fica sabendo. Com o
    valor_padrao combinado (False/{}/[]), a QML cai no caminho de erro que
    ela já tem pronto e avisa o atendente."""

    def decorar(funcao):
        @functools.wraps(funcao)
        def envolvido(*args, **kwargs):
            try:
                return funcao(*args, **kwargs)
            except Exception:
                texto = traceback.format_exc().rstrip()
                print(f"[erro] {funcao.__qualname__} falhou (o app continua rodando):\n{texto}", file=sys.stderr)
                return valor_padrao

        return envolvido

    return decorar


def instalar_captura_de_mensagens_qt():
    """Encaminha para o log as mensagens que o Qt escreve direto no stderr
    do sistema operacional — erros e avisos de QML (`Unable to assign...`,
    `is not a function`, arquivo .qml que não carrega) e os console.log()
    das telas.

    Sem isto, esse tipo de mensagem só aparece pra quem estiver com o
    terminal aberto: ela não passa pelo sys.stderr do Python, então nunca
    chegava em logs/app.log — que é justamente o que se tem em mãos quando
    o problema acontece na máquina da pizzaria.

    Fica separado de configurar_logging() de propósito: precisa do PyQt6
    importado, e configurar_logging() roda em main.py ANTES do preConfig
    garantir que as dependências estão instaladas."""
    try:
        from PyQt6.QtCore import QtMsgType, qInstallMessageHandler
    except ImportError as erro:
        print(f"[logConfig] PyQt6 indisponível — mensagens do Qt não serão logadas ({erro}).")
        return

    niveis = {
        QtMsgType.QtDebugMsg: "debug",
        QtMsgType.QtInfoMsg: "info",
        QtMsgType.QtWarningMsg: "aviso",
        QtMsgType.QtCriticalMsg: "crítico",
        QtMsgType.QtFatalMsg: "fatal",
    }

    def _ao_receber_mensagem(tipo, contexto, mensagem):
        nivel = niveis.get(tipo, "info")
        destino = sys.stderr if tipo in (QtMsgType.QtWarningMsg, QtMsgType.QtCriticalMsg, QtMsgType.QtFatalMsg) else sys.stdout
        print(f"[qt/{nivel}] {mensagem}", file=destino)

    qInstallMessageHandler(_ao_receber_mensagem)


if __name__ == "__main__":
    configurar_logging()
    print("[logConfig] Teste: esta linha deveria aparecer no console e em logs/app.log.")
