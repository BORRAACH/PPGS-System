"""Estatísticas diárias (services/estatisticasService.py) para o "Fechar Caixa"
e para a página de Estatística (qml/pages/estatistica/Estatistica.qml).

Quando se grava:
- "Fechar Caixa" (Fechamento.qml) chama registrarFechamento: o dia é montado
  das comandas desta máquina, gravado, e as outras máquinas são avisadas pelo
  evento "estatisticas_fechamento" para gravarem o mesmo dia com as comandas
  delas — o mesmo desenho do "fechamento_atualizado", que manda só a data.
- Ao abrir a página, gerarHistorico grava numa thread os dias PASSADOS que têm
  comandas e ainda não têm arquivo. Hoje nunca é gravado como histórico
  (continua mudando): no período ele entra calculado na hora.

A leitura das comandas reaproveita o FechamentoController (_ler_comanda,
_itens_da_comanda, _somar_por_forma_pagamento), que só mexe com arquivos — por
isso roda também na thread do histórico."""

import os
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime

from PyQt6.QtCore import QObject, pyqtSignal, pyqtSlot

from Config.logConfig import protegido
from services import comandaParserService as parser
from services import comandaTextoService as texto
from services import estatisticasService
from services.rede import (alteracoesComandas, baixaComandas, contagemCaixa, despesasCaixa, edicoesCaixa,
                           extrasCaixa, rede, relogio)

# Fechar o caixa numa máquina avisa as outras (payload: data e o id do
# fechamento, para o aviso repetido não contar duas vezes).
_EVENTO_ESTATISTICAS_FECHAMENTO = "estatisticas_fechamento"


def _hoje_iso():
    return datetime.now().strftime("%Y-%m-%d")


class EstatisticasController(QObject):
    # Um dia foi gravado (fechamento aqui ou em outra máquina, histórico).
    estatisticasAtualizadas = pyqtSignal()
    # (dias já gerados, total) enquanto o histórico é gerado.
    progressoHistorico = pyqtSignal(int, int)
    # Quantos dias o histórico gravou.
    historicoGerado = pyqtSignal(int)

    # Da thread do histórico para a thread da interface.
    _progressoCalculado = pyqtSignal(int, int)
    _historicoConcluido = pyqtSignal(int)

    def __init__(self, fechamento_controller):
        super().__init__()
        self._fechamento = fechamento_controller
        self._pool = ThreadPoolExecutor(max_workers=1, thread_name_prefix="estatisticas")
        self._gerando_historico = False
        self._cancelado = threading.Event()
        # A thread do histórico e a da interface podem gravar o mesmo dia.
        self._trava_gravacao = threading.Lock()
        self._progressoCalculado.connect(self.progressoHistorico)
        self._historicoConcluido.connect(self._ao_concluir_historico)
        rede.registrarEvento(_EVENTO_ESTATISTICAS_FECHAMENTO, self._ao_receber_fechamento_remoto)

    # ---------- Montar um dia ----------

    def _comandas_do_dia(self, data_iso):
        """As comandas de `data_iso` já interpretadas para montar_dia, e a soma
        das vendas por forma de pagamento."""
        fechamento = self._fechamento
        baixas = baixaComandas.carregar()
        comandas = []
        fechadas_por_tipo = {}

        for nome_arquivo in fechamento._listar_arquivos_do_dia(data_iso):
            dados = fechamento._ler_comanda(nome_arquivo)
            if dados is None:
                continue
            conteudo = dados.get("conteudo", "")
            tipo = dados["tipo"]
            fechada = nome_arquivo in baixas
            comandas.append({
                "arquivo": nome_arquivo,
                "tipo": tipo,
                "codigo": dados.get("codigo", ""),
                "cliente": dados.get("cliente", ""),
                "usuario": dados.get("usuario", ""),
                "valor": dados.get("valor", 0.0),
                "dataHora": dados.get("dataHora", ""),
                "fechada": fechada,
                "itens": [
                    {"pedido": item.get("pedido", ""), "valor": texto.valor_para_float(item.get("valor"))}
                    for item in fechamento._itens_da_comanda(conteudo)
                ],
                "taxaEntrega": texto.valor_para_float(parser.extrair_campo(parser.PADRAO_TAXA_ENTREGA, conteudo)) if tipo == "Entrega" else 0.0,
                "bairro": parser.extrair_campo(parser.PADRAO_BAIRRO, conteudo) if tipo == "Entrega" else "",
            })
            if fechada:
                fechadas_por_tipo.setdefault(tipo, []).append(
                    {"arquivo": nome_arquivo, "formaPagamento": dados.get("formaPagamento", ""), "valor": dados.get("valor", 0.0)}
                )

        formas = {"dinheiro": 0.0, "pix": 0.0, "cartao": 0.0}
        for tipo, lista in fechadas_por_tipo.items():
            for chave, valor in fechamento._somar_por_forma_pagamento(tipo, lista).items():
                formas[chave] = formas.get(chave, 0.0) + valor
        return comandas, formas

    @staticmethod
    def _alteracoes_do_dia(data_iso):
        """As alterações do dia. As correções de caixa gravadas antes de
        alteracoesComandas existir (só em edicoesCaixa) entram também, sem
        repetir as que já estão nos dois."""
        alteracoes = alteracoesComandas.listar_do_dia(data_iso)
        ja_registradas = {(a.get("acao"), a.get("arquivo")) for a in alteracoes}
        for antiga in edicoesCaixa.listar_do_dia(data_iso):
            if (antiga.get("acao"), antiga.get("arquivo")) in ja_registradas:
                continue
            alteracoes.append(dict(antiga, tipo=parser.tipo_comanda(antiga.get("arquivo") or ""), fechada=True))
        return alteracoes

    def _montar_dia(self, data_iso, origem, id_fechamento=""):
        comandas, formas = self._comandas_do_dia(data_iso)
        return estatisticasService.montar_dia(
            data_iso,
            comandas,
            self._alteracoes_do_dia(data_iso),
            extrasCaixa.listar_do_dia(data_iso),
            despesasCaixa.listar_do_dia(data_iso),
            contagemCaixa.obter_dia(data_iso),
            formas,
            origem,
            anterior=estatisticasService.carregar(data_iso),
            id_fechamento=id_fechamento,
        )

    def gerar_dia(self, data_iso, origem, id_fechamento=""):
        """Monta e grava `data_iso`. Devolve as estatísticas gravadas."""
        with self._trava_gravacao:
            dados = self._montar_dia(data_iso, origem, id_fechamento)
            estatisticasService.salvar(data_iso, dados)
        return dados

    # ---------- Fechamento ----------

    @pyqtSlot(str, result=bool)
    @protegido(False)
    def registrarFechamento(self, data_iso):
        """Chamado pelo "Fechar Caixa": grava o dia e avisa as outras máquinas."""
        if not estatisticasService.data_valida(data_iso):
            return False
        id_fechamento = relogio.novo_id()
        self.gerar_dia(data_iso, "fechamento", id_fechamento)
        rede.publicarEvento(_EVENTO_ESTATISTICAS_FECHAMENTO, {"data": data_iso, "idFechamento": id_fechamento})
        self.estatisticasAtualizadas.emit()
        return True

    def _ao_receber_fechamento_remoto(self, payload, _socket=None):
        """Outra máquina fechou o caixa: grava o mesmo dia com as comandas
        daqui. Não republica — senão as máquinas ficariam se avisando de volta."""
        payload = payload or {}
        data_iso = payload.get("data", "")
        if not estatisticasService.data_valida(data_iso):
            return
        try:
            relogio.observar(payload.get("idFechamento") or "")
            self.gerar_dia(data_iso, "fechamento", payload.get("idFechamento", ""))
        except Exception as erro:  # um aviso da rede não pode derrubar o app
            print(f"[Estatisticas] falha ao gravar o fechamento recebido de {data_iso}: {erro!r}")
            return
        self.estatisticasAtualizadas.emit()

    # ---------- Página ----------

    @pyqtSlot(str, str, result="QVariantMap")
    @protegido({})
    def obterPeriodo(self, inicio, fim):
        """A soma do período para a página. Hoje entra calculado na hora (sem
        gravar); os outros dias, do arquivo."""
        hoje = _hoje_iso()
        por_dia = {}
        for data_iso in estatisticasService.datas_do_periodo(inicio, fim):
            if data_iso == hoje:
                por_dia[data_iso] = self._montar_dia(data_iso, "ao_vivo")
            elif data_iso < hoje:
                dados = estatisticasService.carregar(data_iso)
                if dados:
                    por_dia[data_iso] = dados
        return estatisticasService.agregar(por_dia, inicio, fim)

    def _dias_para_gerar(self):
        """Dias passados que têm comandas (ou alterações) e ainda não têm
        arquivo — só o nome dos arquivos é lido, nenhuma comanda é aberta."""
        hoje = _hoje_iso()
        dias = set(alteracoesComandas.dias_com_alteracoes())
        pasta = self._fechamento.pasta_pedidos
        if os.path.isdir(pasta):
            for nome_arquivo in os.listdir(pasta):
                if not nome_arquivo.endswith(".txt"):
                    continue
                aaaammdd = parser.data_arquivo_aaaammdd(nome_arquivo)
                if aaaammdd:
                    dias.add(f"{aaaammdd[:4]}-{aaaammdd[4:6]}-{aaaammdd[6:]}")
        existentes = set(estatisticasService.listar_dias())
        return sorted(d for d in dias if estatisticasService.data_valida(d) and d < hoje and d not in existentes)

    @pyqtSlot(result=int)
    @protegido(0)
    def gerarHistorico(self):
        """Grava numa thread os dias passados ainda sem arquivo. Devolve quantos
        vão ser gerados (0: nada a fazer ou já está gerando). Responde por
        progressoHistorico e historicoGerado."""
        if self._gerando_historico:
            return 0
        dias = self._dias_para_gerar()
        if not dias:
            return 0
        self._gerando_historico = True

        def trabalho():
            gerados = 0
            try:
                for indice, data_iso in enumerate(dias, start=1):
                    if self._cancelado.is_set():
                        break
                    # Um fechamento feito enquanto isto rodava já gravou o dia.
                    if estatisticasService.carregar(data_iso) is None:
                        try:
                            self.gerar_dia(data_iso, "historico")
                            gerados += 1
                        except Exception as erro:
                            print(f"[Estatisticas] falha ao gerar {data_iso}: {erro!r}")
                    self._emitir(self._progressoCalculado, indice, len(dias))
            finally:
                self._emitir(self._historicoConcluido, gerados)

        try:
            self._pool.submit(trabalho)
        except RuntimeError:
            self._gerando_historico = False
            return 0
        return len(dias)

    def _ao_concluir_historico(self, gerados):
        self._gerando_historico = False
        self.historicoGerado.emit(gerados)
        if gerados:
            self.estatisticasAtualizadas.emit()

    @staticmethod
    def _emitir(sinal, *argumentos):
        try:
            sinal.emit(*argumentos)
        except RuntimeError:
            pass  # sistema fechando: o controller já foi destruído

    @pyqtSlot()
    def encerrar(self):
        self._cancelado.set()
        self._pool.shutdown(wait=False, cancel_futures=True)
