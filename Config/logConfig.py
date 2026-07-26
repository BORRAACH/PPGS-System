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

import logging
import logging.handlers
import os
import sys

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

    print(f"[logConfig] Log de diagnóstico sendo gravado em: {caminho}")


if __name__ == "__main__":
    configurar_logging()
    print("[logConfig] Teste: esta linha deveria aparecer no console e em logs/app.log.")
