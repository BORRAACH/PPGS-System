"""Avisa a interface do andamento das tarefas que o app faz sozinho ao abrir
(subir a malha local, checar atualizações).

Por que existe. Essas tarefas rodavam ANTES da janela aparecer e somavam ~3,3s
de espera numa tela preta: `git fetch` do atualizador (~1,6s, e até 15s com
internet ruim — ver Config/atualizador._TIMEOUT_GIT) e o registro do serviço
mDNS da descoberta (~1,6s, ver services/rede/descoberta.py). Nenhuma das duas
é necessária para desenhar a interface, então agora elas começam DEPOIS que a
janela está de pé (ver main.py). Como passaram a acontecer com o usuário já
olhando para a tela, precisam se anunciar — senão a malha simplesmente "fica
pronta" em algum momento, sem ninguém saber quando.

Cada etapa é anunciada duas vezes: ao começar ("Iniciando rede...") e ao
terminar ("Rede iniciada"), pelo mesmo `id`, para a tela substituir a linha em
vez de empilhar duas.

Thread-safety: os métodos daqui são chamados das threads de fundo de main.py,
mas emitir um sinal Qt de outra thread é seguro — o Qt enfileira a entrega na
thread onde este objeto vive (a principal), que é de onde o QML lê."""

from PyQt6.QtCore import QObject, pyqtSignal

# Estados de uma etapa, como chegam ao QML (ver qml/components/StatusInicio.qml).
ANDAMENTO = "andamento"
CONCLUIDO = "concluido"
FALHA = "falha"


class StatusInicializacaoService(QObject):
    """Exposto ao QML como `statusController`."""

    # (id, texto, estado) — `id` identifica a etapa para a tela atualizar a
    # linha existente em vez de criar outra.
    etapaAtualizada = pyqtSignal(str, str, str)

    def iniciando(self, id_etapa, texto):
        self.etapaAtualizada.emit(id_etapa, texto, ANDAMENTO)

    def concluida(self, id_etapa, texto):
        self.etapaAtualizada.emit(id_etapa, texto, CONCLUIDO)

    def falhou(self, id_etapa, texto):
        self.etapaAtualizada.emit(id_etapa, texto, FALHA)


# Instância única, importada por quem precisa avisar algo (main.py e as
# tarefas de fundo). Mesmo padrão de services/rede/rede.
status = StatusInicializacaoService()
