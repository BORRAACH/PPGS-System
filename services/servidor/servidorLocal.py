"""Sobe e mantém de pé o ppgs_server na máquina que a tela Rede designou.

O que este serviço faz, em ordem, e só quando ESTA máquina é a designada:
prepara ferramentas, traz o repositório, garante o binário, sobe o processo em
127.0.0.1 e o vigia. Tudo depois de a janela já estar na tela, numa thread de
fundo, com todo subprocesso em prioridade ociosa (ver services/servidor/
preparo.py) — o caixa não pode ver o sistema engasgar porque o servidor está
compilando.

As chaves que o servidor exige (token, chave de dados, chave de índice) são
derivadas da chave da malha aqui, na hora de subir o processo, e entregues por
variável de ambiente. Elas nunca são gravadas em disco: é isso que faz roubar
o `pizzeria.db` da máquina não bastar pra ler endereço de cliente nenhum.

Este módulo é também o único lugar que fala HTTP com o servidor. As outras
máquinas chegam nele pela malha, e o RedeService encaminha pra cá (ver
`registrar_encaminhador_local`) — o que mantém a porta invisível fora desta
máquina.
"""

import os
import signal
import subprocess
import threading
import time

from PyQt6.QtCore import QByteArray, QObject, QTimer, QUrl, pyqtProperty, pyqtSignal, pyqtSlot
from PyQt6.QtNetwork import QNetworkAccessManager, QNetworkRequest

from Config.logConfig import protegido
from services.rede import seguranca
from services.rede.redeService import rede
from services.statusInicializacaoService import status
from services.servidor import preparo

# Estados possíveis, expostos ao QML como string.
PARADO = "parado"
PREPARANDO = "preparando"
RODANDO = "rodando"
FALHA = "falha"
AGUARDANDO_CHAVE = "aguardando_chave"

_PORTA = 8080
_ENDERECO = f"127.0.0.1:{_PORTA}"
_BASE_URL = f"http://{_ENDERECO}"

# De quanto em quanto tempo se confere que o processo continua vivo.
_INTERVALO_VIGIA_MS = 15000
# Espera antes de tentar subir de novo depois de uma queda. Cresce até o teto
# pra que um servidor que morre no arranque (banco corrompido, porta ocupada
# por outra coisa) não vire um laço de reinício consumindo CPU a noite toda.
_ESPERA_REINICIO_S = 5
_ESPERA_REINICIO_MAXIMA_S = 300
_TIMEOUT_HTTP_MS = 10000


class ServidorLocalService(QObject):
    estadoMudou = pyqtSignal()

    def __init__(self):
        super().__init__()
        self._estado = PARADO
        self._etapa = ""
        self._detalhe = ""
        self._chave_publica = ""
        self._processo = None
        self._log_servidor = None
        self._preparando = False
        self._falhas_seguidas = 0
        # Marcado quando o preparo é cancelado ou o servidor é parado pelo
        # usuário. Sem ele o vigia (e a troca de designação) ressuscitariam o
        # servidor segundos depois, e o botão "Parar" pareceria não funcionar.
        self._parado_pelo_usuario = False
        self._cancelar = threading.Event()
        self._gerenciador = QNetworkAccessManager(self)

        self._timer_vigia = QTimer(self)
        self._timer_vigia.timeout.connect(self._vigiar)

        # O RedeService encaminha pra cá as requisições que chegam dos outros
        # terminais pela malha.
        rede.registrar_encaminhador_local(self.encaminhar)
        rede.servidorDesignadoMudou.connect(self._ao_mudar_designacao)

    # ---------- Superfície QML ----------

    @pyqtProperty(str, notify=estadoMudou)
    def estado(self) -> str:
        return self._estado

    @pyqtProperty(str, notify=estadoMudou)
    def etapa(self) -> str:
        return self._etapa

    @pyqtProperty(str, notify=estadoMudou)
    def detalhe(self) -> str:
        return self._detalhe

    @pyqtProperty(str, notify=estadoMudou)
    def chavePublicaDeploy(self) -> str:
        """A chave que alguém precisa cadastrar como deploy key no GitHub.
        Só fica preenchida quando o clone falhou por falta dela — é o único
        passo deste preparo que uma pessoa tem mesmo que fazer à mão."""
        return self._chave_publica

    @pyqtProperty(bool, notify=estadoMudou)
    def hospedandoAqui(self) -> bool:
        return rede.servidorAqui

    @pyqtSlot()
    @protegido(None)
    def cancelarPreparo(self):
        """Interrompe o preparo em andamento. O trabalho já feito (repositório
        baixado, dependências compiladas) fica no disco: cancelar é desistir de
        continuar agora, não desfazer o que já custou tempo — retomar depois
        recomeça do ponto em que parou."""
        if not self._preparando:
            return
        print("[servidorLocal] Preparo cancelado pelo usuário.")
        self._parado_pelo_usuario = True
        self._cancelar.set()
        # Mata o git/cargo/winget que estiver rodando agora; sem isto o
        # cancelamento só teria efeito quando o comando terminasse sozinho.
        preparo.interromper_atual()
        status.falhou("servidor", "Preparo do servidor cancelado")
        self._definir(PARADO, "Cancelado", "Preparo cancelado. O que já foi baixado continua salvo.")

    @pyqtSlot()
    @protegido(None)
    def pararServidor(self):
        """Para o servidor que roda nesta máquina. A designação continua sendo
        desta máquina — é ela que segue sendo a escolhida — mas nada sobe de
        novo até alguém mandar."""
        self._parado_pelo_usuario = True
        self._cancelar.set()
        preparo.interromper_atual()
        self._parar_processo()
        status.falhou("servidor", "Servidor central parado")
        self._definir(PARADO, "Parado", "O servidor foi parado nesta máquina.")

    @pyqtSlot()
    @protegido(None)
    def refazerPreparo(self):
        """Botão "Tentar de novo" da tela Rede — usado depois de cadastrar a
        deploy key, ou quando algo falhou e foi corrigido à mão."""
        self._falhas_seguidas = 0
        self._parado_pelo_usuario = False
        self._cancelar.clear()
        self.iniciar()

    @pyqtSlot()
    @protegido(None)
    def iniciar(self):
        """Ponto de entrada, chamado depois que a janela já está de pé e
        sempre que a designação muda. Não faz nada se esta máquina não é a
        escolhida — é o que garante que só uma máquina roda o servidor."""
        if not rede.servidorAqui:
            self._parar_processo()
            self._definir(PARADO, "", "O servidor roda em outra máquina." if rede.maquinaServidor else "Nenhuma máquina escolhida ainda.")
            return
        if self._preparando or self._processo is not None:
            return
        if self._parado_pelo_usuario:
            # Parado de propósito: só volta quando alguém pedir explicitamente
            # (botão "Iniciar"/"Tentar de novo", ou uma nova designação).
            return
        self._cancelar.clear()
        self._preparando = True
        threading.Thread(target=self._preparar_em_thread, daemon=True).start()

    # ---------- Preparo (thread de fundo) ----------

    def _definir(self, estado: str, etapa: str, detalhe: str = ""):
        """Seguro de chamar de qualquer thread: só mexe em str/bool e emite um
        sinal Qt, que o Qt entrega na thread principal (o mesmo vale para
        `status`, ver services/statusInicializacaoService.py)."""
        self._estado, self._etapa, self._detalhe = estado, etapa, detalhe
        if etapa or detalhe:
            print(f"[servidorLocal] {etapa}: {detalhe}" if detalhe else f"[servidorLocal] {etapa}")
        # A notificação do canto da tela é atualizada a cada mudança, e não
        # só no começo e no fim: este preparo pode levar de segundos (tudo já
        # instalado) a quase uma hora (primeira vez, compilando do zero), e
        # uma frase única e imóvel durante todo esse tempo é indistinguível
        # de um travamento.
        if estado == PREPARANDO:
            status.iniciando("servidor", self._texto_de_status())
        # As outras máquinas são avisadas na hora em que o servidor entra (ou
        # sai) do ar, em vez de descobrirem sozinhas no próximo tique de 30s
        # da verificação de conexão — ver RedeService.anunciar_servidor_no_ar.
        # Chamado a cada mudança de estado porque "no ar" é justamente o que
        # este método sabe; o RedeService ignora a repetição quando nada
        # cruzou a fronteira entre RODANDO e o resto.
        rede.anunciar_servidor_no_ar(estado == RODANDO)
        self.estadoMudou.emit()

    def _texto_de_status(self) -> str:
        if self._detalhe:
            return f"Servidor: {self._detalhe}"
        if self._etapa:
            return f"Servidor: {self._etapa.lower()}..."
        return "Preparando o servidor central..."

    def _avisar(self, texto: str):
        """Progresso fino, vindo de dentro de uma etapa longa (ver o parâmetro
        `avisar` em services/servidor/preparo.py). Mantém a etapa atual e só
        troca o detalhe — é o que faz a notificação andar durante um clone ou
        uma compilação, em vez de congelar no nome da etapa."""
        self._detalhe = texto
        status.iniciando("servidor", f"Servidor: {texto}")
        self.estadoMudou.emit()

    def _preparar_em_thread(self):
        try:
            self._rebaixar_prioridade_da_thread()
            self._definir(PREPARANDO, "Preparando o servidor central", "")

            etapas = [
                ("Verificando ferramentas", self._etapa_ferramentas),
                ("Baixando o código", self._etapa_repositorio),
                ("Preparando o programa", self._etapa_binario),
            ]
            precisa_recompilar = False
            for nome, funcao in etapas:
                if self._cancelar.is_set():
                    return
                self._definir(PREPARANDO, nome, "")
                ok, mensagem, extra = funcao(precisa_recompilar)
                if self._cancelar.is_set():
                    # A falha que vier de um comando morto pelo cancelamento
                    # não é uma falha de verdade — não vale reportar como erro.
                    return
                if not ok:
                    status.falhou("servidor", mensagem)
                    self._definir(AGUARDANDO_CHAVE if self._chave_publica else FALHA, nome, mensagem)
                    return
                precisa_recompilar = precisa_recompilar or bool(extra)
                self._definir(PREPARANDO, nome, mensagem)

            if self._cancelar.is_set():
                return
            self._definir(PREPARANDO, "Iniciando o servidor", "")
            ok, mensagem = self._subir_processo()
            if not ok:
                status.falhou("servidor", mensagem)
                self._definir(FALHA, "Iniciando o servidor", mensagem)
                return

            self._falhas_seguidas = 0
            status.concluida("servidor", "Servidor central no ar nesta máquina")
            self._definir(RODANDO, "No ar", f"Servidor rodando nesta máquina ({_ENDERECO}).")
            # start() precisa acontecer na thread dona do QTimer.
            QTimer.singleShot(0, lambda: self._timer_vigia.start(_INTERVALO_VIGIA_MS))
        except Exception as erro:  # nunca deixa a thread morrer calada
            import traceback

            print(f"[servidorLocal] Falha inesperada no preparo: {erro}\n{traceback.format_exc()}")
            self._definir(FALHA, "Preparo", str(erro))
        finally:
            self._preparando = False

    def _rebaixar_prioridade_da_thread(self):
        """Além dos subprocessos (que já nascem ociosos, ver preparo.rodar),
        a própria thread precisa sair da frente: ela copia arquivos e espera
        I/O ao lado da thread que desenha a tela."""
        try:
            if preparo.eh_windows():
                import win32api
                import win32process

                win32process.SetThreadPriority(
                    win32api.GetCurrentThread(), win32process.THREAD_PRIORITY_LOWEST
                )
            else:
                os.nice(19)
        except Exception as erro:
            print(f"[servidorLocal] Não foi possível baixar a prioridade da thread: {erro}")

    def _etapa_ferramentas(self, _):
        pronta, publica, erro = preparo.garantir_chave_deploy(self._avisar)
        if not pronta:
            return False, erro, False
        self._chave_publica = ""
        ok, mensagem = preparo.garantir_git(self._avisar)
        return ok, mensagem, False

    def _etapa_repositorio(self, _):
        ok, mensagem, mudou = preparo.clonar_ou_atualizar(self._avisar)
        if not ok:
            if os.path.isfile(preparo.caminho_binario()):
                # Não alcançar o GitHub não pode tirar a pizzaria do ar: se já
                # existe um servidor compilado aqui de uma vez anterior, ele
                # sobe com o que tem. Perder o autofill de endereço por causa
                # de uma deploy key revogada ou de uma queda de internet seria
                # uma falha muito pior que ficar uma noite sem atualizar.
                print(f"[servidorLocal] {mensagem} Seguindo com o binário já instalado.")
                return True, "sem acesso ao repositório — usando o servidor já instalado.", False
            # Primeira instalação e o clone falhou: a causa esmagadoramente
            # mais provável é a deploy key ainda não cadastrada. Mostrar a
            # chave junto do erro transforma "deu erro" em "faça isto".
            _, publica, _erro = preparo.garantir_chave_deploy(self._avisar)
            self._chave_publica = publica
            return False, mensagem, False
        return True, mensagem, mudou

    def _etapa_binario(self, precisa_recompilar):
        ok, mensagem = preparo.garantir_binario(precisa_recompilar, self._avisar)
        return ok, mensagem, False

    # ---------- Processo ----------

    def _ambiente_do_servidor(self):
        """As três chaves saem da chave da malha, aqui, em memória. Nenhuma
        delas encosta no disco — é isso que faz levar o `pizzeria.db` embora
        não bastar pra ler endereço de cliente nenhum.

        A chave da malha hoje é uma constante do código (ver
        seguranca.CHAVE_PADRAO), então isto nunca falha por falta dela e o
        servidor sobe sem ninguém configurar nada. O que se perde junto está
        escrito lá: quem tiver o código-fonte chega às mesmas três chaves."""
        chave = seguranca.carregar_chave()
        return {
            **os.environ,
            "PIZZERIA_BIND": _ENDERECO,
            "PIZZERIA_TOKEN": seguranca.token_servidor(chave),
            "PIZZERIA_CHAVE_DADOS": seguranca.chave_dados(chave),
            "PIZZERIA_CHAVE_INDICE": seguranca.chave_indice(chave),
        }

    def _subir_processo(self):
        binario = preparo.caminho_binario()
        if not os.path.isfile(binario):
            return False, "O binário do servidor não está onde deveria."

        dados = preparo.pasta_dados()
        os.makedirs(dados, exist_ok=True)

        # Antes de tentar a porta: se um servidor desta mesma instalação ficou
        # para trás de uma sessão anterior, ele ainda a está segurando, e o
        # processo novo morreria com "Address already in use".
        self._encerrar_orfao()

        try:
            ambiente = self._ambiente_do_servidor()
        except seguranca.ErroSeguranca as erro:
            return False, str(erro)

        try:
            # A saída do servidor precisa ir pra algum lugar. Mandá-la pro
            # DEVNULL (como estava) significa que "o servidor não subiu" chega
            # sem motivo nenhum junto — e os motivos reais (porta ocupada,
            # chave errada, banco corrompido) são exatamente os que só o
            # próprio servidor sabe explicar.
            self._log_servidor = open(os.path.join(dados, "servidor.log"), "a", encoding="utf-8")
            self._log_servidor.write(f"\n===== iniciando em {time.strftime('%Y-%m-%d %H:%M:%S')} =====\n")
            self._log_servidor.flush()
            self._processo = subprocess.Popen(
                [binario],
                # cwd define qual banco o servidor usa (o DB_PATH dele é
                # relativo), então isto não é detalhe: é o que fixa o
                # pizzeria.db em pasta_dados() e não onde o app foi aberto.
                cwd=dados,
                env=ambiente,
                stdout=self._log_servidor,
                stderr=subprocess.STDOUT,
                **preparo._flags_de_prioridade(),
            )
        except OSError as erro:
            return False, f"Não foi possível iniciar o servidor: {erro}"

        # O servidor faz migration antes de escutar; num banco grande isso
        # leva alguns segundos. Confirmar que ele respondeu evita anunciar
        # "no ar" pra um processo que morreu no arranque.
        self._avisar("atualizando o banco de dados")
        for _ in range(40):
            time.sleep(0.25)
            if self._processo.poll() is not None:
                return False, f"O servidor encerrou logo após iniciar: {self._ultimo_erro_do_servidor()}"
            sonda = self._sondar()
            if sonda == self.NO_AR:
                self._registrar_pid()
                return True, "Servidor no ar."
            if sonda == self.VERSAO_ANTIGA:
                # Falhar já, com o motivo certo, em vez de esperar o timeout e
                # relatar "não respondeu a tempo".
                self._parar_processo()
                return False, (
                    "O servidor instalado é de uma versão antiga (sem autenticação nem "
                    "cifragem dos dados). Atualize o repositório PPGS-Server e refaça o preparo."
                )
        # Subiu mas não respondeu: deixar o processo vivo aqui seria um
        # vazamento — ele continuaria segurando a porta e o banco, e o próximo
        # arranque falharia por "porta ocupada" sem ninguém entender por quê.
        self._parar_processo()
        return False, "O servidor subiu mas não respondeu a tempo."

    def _registrar_pid(self):
        try:
            with open(preparo.caminho_pid(), "w", encoding="utf-8") as arquivo:
                arquivo.write(str(self._processo.pid))
        except (OSError, AttributeError) as erro:
            # Não é fatal: só significa que um eventual órfão desta sessão terá
            # de ser resolvido à mão.
            print(f"[servidorLocal] Não foi possível gravar o PID do servidor: {erro}")

    def _apagar_pid(self):
        try:
            os.remove(preparo.caminho_pid())
        except OSError:
            pass

    def _encerrar_orfao(self):
        """Derruba um servidor sobrevivente de uma sessão anterior.

        Só mata o PID que ESTE sistema gravou, e só depois de confirmar que
        quem está na porta responde o /saude do nosso próprio servidor — as
        duas checagens juntas evitam o pesadelo de matar um processo alheio
        que por acaso herdou o mesmo número de PID."""
        try:
            with open(preparo.caminho_pid(), "r", encoding="utf-8") as arquivo:
                pid = int((arquivo.read() or "").strip())
        except (OSError, ValueError):
            return
        if pid <= 0 or not self._responde():
            self._apagar_pid()
            return

        print(f"[servidorLocal] Encontrado um servidor de uma sessão anterior (PID {pid}) — encerrando para liberar a porta.")
        self._avisar("encerrando o servidor da sessão anterior")
        try:
            if preparo.eh_windows():
                preparo.rodar(["taskkill", "/PID", str(pid), "/T", "/F"], timeout=30)
            else:
                os.kill(pid, signal.SIGTERM)
        except (OSError, ProcessLookupError) as erro:
            print(f"[servidorLocal] Não foi possível encerrar o PID {pid}: {erro}")

        # Espera a porta sair do ar de verdade: o servidor termina as
        # requisições em andamento antes de fechar, então ele não some no
        # mesmo instante em que recebe o sinal.
        for _ in range(40):
            if not self._responde():
                break
            time.sleep(0.25)
        else:
            print("[servidorLocal] O servidor anterior não liberou a porta a tempo.")
        self._apagar_pid()

    def _ultimo_erro_do_servidor(self) -> str:
        """A última linha útil do log do servidor, pra mensagem de erro da tela
        dizer o motivo em vez de mandar procurar num arquivo."""
        try:
            with open(os.path.join(preparo.pasta_dados(), "servidor.log"), "r", encoding="utf-8", errors="replace") as arquivo:
                linhas = [l.strip() for l in arquivo.readlines()[-15:] if l.strip() and not l.startswith("=====")]
        except OSError:
            return "motivo desconhecido"
        return linhas[-1] if linhas else "motivo desconhecido"

    # Resultados de _sondar().
    NO_AR = "no_ar"
    VERSAO_ANTIGA = "versao_antiga"
    SEM_RESPOSTA = "sem_resposta"

    def _sondar(self) -> str:
        """Checagem síncrona, só usada durante o arranque (fora da thread da
        interface). O /saude é público de propósito — ver src/routes.rs.

        Distingue três casos, e não dois, porque "não respondeu" englobava
        silenciosamente um quarto muito comum: um binário de uma versão antiga
        do servidor, que sobe bem mas não conhece a rota /saude. Ele respondia
        404, a sonda dizia apenas "não", e o resultado era esperar 10s e
        acusar um timeout — sem nenhuma pista de que o problema era a versão
        do servidor instalado."""
        import urllib.error
        import urllib.request

        try:
            with urllib.request.urlopen(f"{_BASE_URL}/saude", timeout=2) as resposta:
                return self.NO_AR if resposta.status == 200 else self.VERSAO_ANTIGA
        except urllib.error.HTTPError:
            # Respondeu HTTP, só não conhece a rota: está no ar, mas é de uma
            # versão anterior à autenticação/cifragem que este sistema exige.
            return self.VERSAO_ANTIGA
        except (urllib.error.URLError, OSError, TimeoutError):
            return self.SEM_RESPOSTA

    def _responde(self) -> bool:
        return self._sondar() != self.SEM_RESPOSTA

    def _parar_processo(self):
        self._timer_vigia.stop()
        processo = self._processo
        self._processo = None
        if processo is None or processo.poll() is not None:
            return
        # Mesmo padrão de dev_watch.py: pede pra sair, dá um tempo, e só
        # então mata. O servidor termina as requisições em andamento no
        # SIGTERM (ver src/shutdown.rs) — matar direto poderia cortar uma
        # gravação de caixa pela metade.
        try:
            processo.terminate()
            processo.wait(timeout=5)
        except subprocess.TimeoutExpired:
            processo.kill()
        except OSError:
            pass
        finally:
            self._apagar_pid()
            if self._log_servidor is not None:
                try:
                    self._log_servidor.close()
                except OSError:
                    pass
                self._log_servidor = None

    def _vigiar(self):
        if self._parado_pelo_usuario:
            return
        if not rede.servidorAqui:
            self._parar_processo()
            self._definir(PARADO, "", "O servidor passou a rodar em outra máquina.")
            return
        processo = self._processo
        if processo is not None and processo.poll() is None:
            return

        self._processo = None
        self._timer_vigia.stop()
        self._falhas_seguidas += 1
        espera = min(_ESPERA_REINICIO_S * (2 ** (self._falhas_seguidas - 1)), _ESPERA_REINICIO_MAXIMA_S)
        self._definir(FALHA, "Caiu", f"O servidor parou. Nova tentativa em {espera}s.")
        QTimer.singleShot(int(espera * 1000), self.iniciar)

    def _ao_mudar_designacao(self):
        if rede.servidorAqui:
            # Escolher a máquina de novo é um pedido explícito pra rodar aqui,
            # então desfaz uma parada manual anterior.
            self._parado_pelo_usuario = False
            self._cancelar.clear()
            self.iniciar()
        else:
            self._parar_processo()
            self._definir(PARADO, "", f"O servidor roda em '{rede.maquinaServidor}'." if rede.maquinaServidor else "")

    def encerrar(self):
        """Ligado ao aboutToQuit — sem isto o servidor sobreviveria ao
        fechamento do sistema e a porta continuaria ocupada na próxima
        abertura."""
        self._parar_processo()

    # ---------- Encaminhamento HTTP (chamado pelo RedeService) ----------

    def encaminhar(self, metodo: str, caminho: str, corpo: bytes, responder):
        """Fala com o ppgs_server desta máquina e chama
        `responder(status, bytes)` quando a resposta chegar.

        É aqui que o token entra. Note que ele NÃO vem do peer: cada máquina
        deriva o seu da própria chave da malha, então um peer que passasse no
        handshake mas mandasse um token forjado não mudaria nada — o token
        usado é sempre o desta máquina."""
        if self._processo is None or self._processo.poll() is not None:
            responder(503, b"")
            return

        token = seguranca.token_servidor()

        requisicao = QNetworkRequest(QUrl(f"{_BASE_URL}{caminho}"))
        requisicao.setRawHeader(b"Authorization", f"Bearer {token}".encode("ascii"))
        requisicao.setHeader(QNetworkRequest.KnownHeaders.ContentTypeHeader, "application/json")
        requisicao.setTransferTimeout(_TIMEOUT_HTTP_MS)

        metodo = (metodo or "GET").upper()
        if metodo == "POST":
            resposta = self._gerenciador.post(requisicao, corpo or b"")
        else:
            resposta = self._gerenciador.get(requisicao)

        def concluir():
            resposta.deleteLater()
            status = resposta.attribute(QNetworkRequest.Attribute.HttpStatusCodeAttribute)
            responder(int(status or 0), bytes(resposta.readAll()))

        resposta.finished.connect(concluir)


# Singleton de módulo — mesmo padrão dos demais services do projeto.
servidor_local = ServidorLocalService()
