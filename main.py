from Config import logConfig

# O mais cedo possível — antes até do preConfig, senão os prints dele
# escapam do log. Redireciona stdout/stderr para logs/app.log (além do
# console, quando existir um) sem precisar tocar nos vários print() já
# espalhados pelo código (ver Config/logConfig.py).
logConfig.configurar_logging()

from Config import preConfig

preConfig.garantir_dependencias()

from Config import atualizador, impressoraWindows

# Antes dos imports do resto do app (logo abaixo), e antes de qualquer coisa
# aparecer na tela: se o usuário aceitar atualizar, o `git merge --ff-only`
# deixa os arquivos novos no disco a tempo desses imports pegarem o código
# atualizado, e a atualização vale JÁ NESTA execução. Foi tentado adiar isto
# para depois da janela (a checagem é o que mais pesa na abertura: ~1,6s, até
# 15s com internet ruim), mas aí o app já está com o código antigo carregado
# em memória e a atualização só passaria a valer na abertura seguinte — o que
# não vale a espera economizada.
#
# Devolve a QApplication criada pra perguntar (se alguma foi criada) pra
# reaproveitar mais abaixo: só pode existir uma por processo.
_app_atualizador = atualizador.verificar_atualizacoes()

import sys
import os
import threading

try:
    from PyQt6.QtCore import QObject, pyqtSlot, QTimer, QVariant, QUrl
    from PyQt6.QtGui import QGuiApplication
    from PyQt6.QtQml import QQmlApplicationEngine

    from controllers.balcaoController import BalcaoController
    from controllers.entregaController import EntregaController
    from controllers.salaoController import SalaoController
    from controllers.consultaController import ConsultaController
    from controllers.fechamentoController import FechamentoController
    from services.rede import rede
    from services.iconProvider import IconProvider
    from services.comandaEstiloService import ComandaEstiloController
    from services.cardapioService import CardapioController
    from services.formulaLucroService import FormulaLucroController
    from services.statusInicializacaoService import status
    from Config import diagnosticar_impressora
except ImportError as erro:
    # preConfig.garantir_dependencias() já tentou instalar tudo sozinho —
    # se mesmo assim algo continua faltando (sem internet, sem permissão
    # etc.), termina aqui com uma mensagem clara em vez de um traceback cru.
    #
    # Pega ImportError e não só ModuleNotFoundError de propósito: no Linux é
    # comum o pacote estar instalado mas o .so não carregar por falta de uma
    # lib do sistema (libGL.so.1, libxcb-cursor.so.0...) — isso é ImportError
    # puro, e antes escapava daqui como traceback cru.
    #
    # erro.name é o módulo exato (ex: "PyQt6.QtQml"), não necessariamente o
    # nome do pacote pip — busca o pacote real em preConfig quando possível.
    modulo = erro.name or "<desconhecido>"
    pacote = modulo
    for nome_pacote, nomes_modulos, _plataforma in preConfig._DEPENDENCIAS_PIP:
        if any(modulo == m or modulo.startswith(m.split(".")[0] + ".") for m in nomes_modulos):
            pacote = nome_pacote
            break

    print(
        f"[main] Não foi possível carregar a dependência '{modulo}' mesmo "
        "depois do preConfig tentar instalá-la automaticamente."
    )
    # A mensagem original diz QUAL é o problema de verdade: "No module named
    # X" (não instalado) é bem diferente de "libGL.so.1: cannot open shared
    # object file" (instalado, faltando lib do sistema).
    print(f"[main] Erro original: {erro}")

    dica_distro = preConfig._dica_pacote_da_distro(pacote)
    if dica_distro:
        print(f"[main] No Linux, o caminho mais confiável é instalar pela distribuição: {dica_distro}")
    print(f"[main] Alternativa: pip install {pacote}")
    sys.exit(1)

# Só agora, com o PyQt6 garantidamente importado: manda os erros/avisos de
# QML (que o Qt escreve no stderr do sistema, fora do alcance do
# logConfig) também pro logs/app.log — sem isso, uma tela que não carrega
# ou um binding quebrado não deixa rastro nenhum no log.
logConfig.instalar_captura_de_mensagens_qt()

# codigo perigoso
os.environ["QML_XHR_ALLOW_FILE_READ"] = "1"


def _iniciar_rede():
    """Sobe a malha local. Roda na thread da interface (via QTimer), não numa
    thread de fundo: RedeService cria QTcpServer/QTimer, que pertencem à
    thread onde foram criados e não podem ser acionados de fora. O que era
    lento aqui — o registro mDNS, ~1,6s — passou a acontecer numa thread
    dentro da própria descoberta (ver services/rede/descoberta.py), então
    esta chamada volta na hora e o "Rede local no ar" chega depois, pelo
    sinal `iniciada`."""
    status.iniciando("rede", "Iniciando rede local...")
    rede.iniciar()


def _mostrar_resultado_da_atualizacao():
    """Conta na caixa de status o que a checagem de atualizações concluiu.

    Ela já aconteceu lá em cima, antes de existir qualquer janela — este é o
    primeiro momento em que dá para mostrar o resultado ao usuário (ver
    Config/atualizador.ultimo_resultado)."""
    texto, ok = atualizador.ultimo_resultado()
    if ok:
        status.concluida("atualizacao", texto)
    else:
        status.falhou("atualizacao", texto)


def _tarefas_de_fundo():
    """Chamado numa thread à parte depois que a janela já carregou (ver
    __main__ abaixo). Só faz configuração/diagnóstico de impressora — nada
    aqui é necessário para a interface aparecer, e ambos já eram melhor
    esforço (nunca levantam exceção, só logam avisos)."""
    status.iniciando("impressora", "Procurando impressora...")
    # Só faz algo no Windows (ver Config/impressoraWindows.py) — acha a
    # Bematech MP-4200 TH nas portas USB e garante que existe uma fila de
    # impressão apontando pra ela, já que o Windows não cria essa fila
    # sozinho mesmo reconhecendo o hardware. Melhor esforço: se não achar
    # impressora nenhuma, ou a configuração falhar por qualquer motivo, só
    # loga um aviso e o app continua normalmente sem impressora configurada.
    impressoraWindows.garantir_impressora_bematech()

    # Loga nome/porta/tipo_porta de cada impressora instalada (ver
    # Config/diagnosticar_impressora.py) — mesma info que services/printer/
    # windows.py/redeService.py já usam pra decidir a máquina que imprime na
    # rede, só que aqui aparece sempre, de forma explícita, no console/
    # logs/app.log, sem precisar rodar o diagnóstico à parte pra descobrir por
    # que uma porta caiu como "desconhecido" (ver
    # redeService._detectar_impressora_em_thread).
    impressoras = diagnosticar_impressora.listar_impressoras()

    # listar_impressoras() já loga o detalhe; aqui só interessa se achou
    # alguma, para a tela poder dizer algo útil em vez de "pronto".
    if impressoras:
        status.concluida("impressora", f"{len(impressoras)} impressora(s) encontrada(s)")
    else:
        status.falhou("impressora", "Nenhuma impressora encontrada")


if __name__ == "__main__":
    app = _app_atualizador or QGuiApplication(sys.argv)
    # Nome/organização estáveis — necessário para QStandardPaths resolver
    # sempre o mesmo diretório de cache entre execuções (ver
    # services/rede/fechamentoCache.py); sem isso, o Qt cai num caminho
    # baseado no nome do executável (variável conforme como o app foi
    # iniciado), o que espalharia o cache de fechamento por pastas
    # diferentes a cada vez.
    app.setApplicationName("PizzeriaSystem")
    app.setOrganizationName("PizzeriaSystem")
    engine = QQmlApplicationEngine()

    # Diretório onde o script está sendo executado
    base_dir = os.path.dirname(os.path.abspath(__file__))
    qml_dir = os.path.join(base_dir, "qml")
    main_qml = os.path.join(qml_dir, "main.qml")
    # Exposto ao QML para montar caminhos absolutos (ex: data/cardapio/*.json)
    # a partir da raiz do projeto, em vez de caminhos relativos "../../../.."
    # que quebram se um arquivo .qml mudar de pasta.
    engine.rootContext().setContextProperty("raizProjeto", QUrl.fromLocalFile(base_dir + os.sep))

    # Ícones (qml/components/Icone.qml) via "image://qtaicon/<nome>" — ver
    # services/iconProvider.py.
    engine.addImageProvider("qtaicon", IconProvider())

    controller = BalcaoController()
    engine.rootContext().setContextProperty("balcaoController", controller)
    entregaController = EntregaController()
    engine.rootContext().setContextProperty("entregaController", entregaController)
    salaoController = SalaoController()
    engine.rootContext().setContextProperty("salaoController", salaoController)
    consultaController = ConsultaController()
    engine.rootContext().setContextProperty("consultaController", consultaController)
    fechamentoController = FechamentoController()
    engine.rootContext().setContextProperty("fechamentoController", fechamentoController)
    comandaEstiloController = ComandaEstiloController()
    engine.rootContext().setContextProperty("comandaEstiloController", comandaEstiloController)
    # Edição de data/cardapio/*.json pela tela Cardápio — as telas de pedido
    # continuam lendo esses arquivos direto por XMLHttpRequest; o controller
    # só existe porque o QML não grava arquivo.
    cardapioController = CardapioController()
    engine.rootContext().setContextProperty("cardapioController", cardapioController)
    formulaLucroController = FormulaLucroController()
    engine.rootContext().setContextProperty("formulaLucroController", formulaLucroController)

    # Compartilha pedidos com outras instâncias deste app na mesma rede
    # local (ver architecture/EXPLAIN.md). Os sinais entram pelo
    # consultaController, que é quem sabe gravar/apagar os .txt e avisar a
    # tela de Consulta. A malha só sobe depois da janela (ver abaixo).
    rede.pedidoRecebido.connect(consultaController.aplicarPedidoRemoto)
    rede.pedidoRemovidoRemoto.connect(consultaController.removerPedidoRemoto)
    engine.rootContext().setContextProperty("redeController", rede)
    engine.rootContext().setContextProperty("statusController", status)

    engine.addImportPath(qml_dir)

    engine.load(main_qml)

    if not engine.rootObjects():
        sys.exit(-1)

    # --- Daqui pra baixo, a janela JÁ está de pé ---
    #
    # A atualização é a única coisa que roda antes da interface (ver o topo do
    # arquivo). O que sobrou aqui não é necessário para desenhar a tela e só
    # custa tempo de rede: subir a malha local levava ~1,7s antes do primeiro
    # frame. Agora roda com o usuário já vendo a tela, anunciando o progresso
    # no canto (services/statusInicializacaoService.py).
    #
    # QTimer.singleShot(0, ...) em vez de chamar direto: devolve o controle ao
    # loop de eventos primeiro, para o primeiro frame ser desenhado antes de
    # qualquer uma dessas tarefas começar.
    QTimer.singleShot(0, _mostrar_resultado_da_atualizacao)
    QTimer.singleShot(0, _iniciar_rede)

    # Em thread porque é I/O bloqueante puro (PowerShell/CUPS) e não toca
    # objeto Qt nenhum.
    threading.Thread(target=_tarefas_de_fundo, daemon=True).start()

    sys.exit(app.exec())
