"""Comparação de rotas de entrega da tela Mapa (qml/pages/mapa/Maps.qml): com a
pizzaria e duas entregas, compensa levar as duas numa viagem só ou fazer duas
viagens?

O trabalho pesado vai para uma thread: ler o grafo do cache ou, na primeira
vez, baixar a malha viária (~10 MB) e montá-lo; depois, cada comparação são
seis buscas A*. A resposta volta à thread da interface por sinal. Pronto, o
grafo fica em memória até o sistema fechar. Os algoritmos estão em
services/grafoRuas.py."""

import threading

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot

from services import grafoRuas


class RotasController(QObject):
    estadoMudou = pyqtSignal()
    comparacaoPronta = pyqtSignal("QVariantMap")
    comparacaoFalhou = pyqtSignal(str)

    # Das threads para a thread da interface. O controller vive nela, então a
    # conexão é enfileirada.
    _progresso = pyqtSignal(str)
    _grafoCarregado = pyqtSignal(object, str)
    _comparacaoCalculada = pyqtSignal(int, object, str)

    def __init__(self):
        super().__init__()
        self._grafo = None
        self._carregando = False
        self._estado = "vazio"  # vazio | carregando | pronto | erro
        self._mensagem = ""
        # Comparação pedida antes de o grafo ficar pronto: roda quando ele chegar.
        self._pendente = None
        # Só vale a resposta da comparação mais recente.
        self._geracao = 0
        self._cancelado = threading.Event()
        self._progresso.connect(self._ao_progresso)
        self._grafoCarregado.connect(self._ao_grafo_carregado)
        self._comparacaoCalculada.connect(self._ao_comparacao_calculada)

    @pyqtProperty(str, notify=estadoMudou)
    def estado(self):
        return self._estado

    @pyqtProperty(str, notify=estadoMudou)
    def mensagem(self):
        return self._mensagem

    def _definir_estado(self, estado, mensagem=""):
        if (estado, mensagem) != (self._estado, self._mensagem):
            self._estado, self._mensagem = estado, mensagem
            self.estadoMudou.emit()

    # ---------- Grafo ----------

    @pyqtSlot(float, float)
    def prepararGrafo(self, lat, lon):
        """Garante o grafo em memória, do cache ou baixado. Não faz nada se ele
        já está pronto ou sendo carregado."""
        if self._grafo is not None or self._carregando:
            return
        self._carregando = True
        self._definir_estado("carregando", "Carregando o mapa de ruas…")
        threading.Thread(target=self._carregar, args=(lat, lon), name="grafo-ruas", daemon=True).start()

    def _carregar(self, lat, lon):
        try:
            grafo = grafoRuas.ler_cache(lat, lon)
            if grafo is None:
                self._progresso.emit("Baixando o mapa de ruas da região (só na primeira vez; pode levar um minuto)…")
                elementos = grafoRuas.baixar_elementos(lat, lon, self._cancelado)
                self._progresso.emit("Montando o grafo das ruas…")
                dados = grafoRuas.montar_grafo(elementos, (lat, lon))
                try:
                    grafoRuas.salvar_cache(dados)
                except Exception as erro:  # sem cache, só baixa de novo na próxima abertura
                    print(f"[RotasController] não foi possível gravar o cache do grafo: {erro!r}")
                grafo = grafoRuas.Grafo(dados)
            self._grafoCarregado.emit(grafo, "")
        except grafoRuas.ErroRota as erro:
            self._grafoCarregado.emit(None, str(erro))
        except Exception as erro:  # a thread não pode morrer calada: a tela ficaria "carregando"
            print(f"[RotasController] falha ao montar o grafo: {erro!r}")
            self._grafoCarregado.emit(None, f"Não foi possível montar o mapa de ruas ({erro}).")

    def _ao_progresso(self, mensagem):
        if self._carregando:
            self._definir_estado("carregando", mensagem)

    def _ao_grafo_carregado(self, grafo, erro):
        self._carregando = False
        pendente, self._pendente = self._pendente, None
        if grafo is None:
            self._definir_estado("erro", erro)
            if pendente is not None and pendente[0] == self._geracao:
                self.comparacaoFalhou.emit(erro)
            return
        self._grafo = grafo
        self._definir_estado("pronto")
        if pendente is not None and pendente[0] == self._geracao:
            self._calcular(*pendente)

    # ---------- Comparação ----------

    @pyqtSlot(float, float, float, float, float, float)
    def comparar(self, lat_p, lon_p, lat_a, lon_a, lat_b, lon_b):
        """Responde por comparacaoPronta (o dict de grafoRuas.comparar_entregas)
        ou comparacaoFalhou (a mensagem)."""
        self._geracao += 1
        pedido = (self._geracao, (lat_p, lon_p), (lat_a, lon_a), (lat_b, lon_b))
        if self._grafo is None:
            self._pendente = pedido
            self.prepararGrafo(lat_p, lon_p)
            return
        self._calcular(*pedido)

    def _calcular(self, geracao, pizzaria, entrega_a, entrega_b):
        grafo = self._grafo
        self._definir_estado("pronto", "Calculando as rotas…")

        def trabalho():
            try:
                resultado = grafoRuas.comparar_entregas(grafo, pizzaria, entrega_a, entrega_b)
                self._comparacaoCalculada.emit(geracao, resultado, "")
            except grafoRuas.ErroRota as erro:
                self._comparacaoCalculada.emit(geracao, None, str(erro))
            except Exception as erro:
                print(f"[RotasController] falha ao comparar rotas: {erro!r}")
                self._comparacaoCalculada.emit(geracao, None, f"Não foi possível calcular as rotas ({erro}).")

        threading.Thread(target=trabalho, name="comparar-rotas", daemon=True).start()

    def _ao_comparacao_calculada(self, geracao, resultado, erro):
        if geracao != self._geracao:
            return
        self._definir_estado("pronto")
        if resultado is None:
            self.comparacaoFalhou.emit(erro)
        else:
            self.comparacaoPronta.emit(resultado)

    @pyqtSlot()
    def encerrar(self):
        """Fechamento do sistema: um download em andamento não tenta o próximo
        servidor."""
        self._cancelado.set()
