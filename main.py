from Config import logConfig

# O mais cedo possível — antes até do preConfig, senão os prints dele
# escapam do log. Redireciona stdout/stderr para logs/app.log (além do
# console, quando existir um) sem precisar tocar nos vários print() já
# espalhados pelo código (ver Config/logConfig.py).
logConfig.configurar_logging()

from Config import preConfig

preConfig.garantir_dependencias()

from Config import atualizador, impressoraWindows

# Roda antes dos imports do resto do app (logo abaixo): se o usuário aceitar
# atualizar, o `git merge --ff-only` já deixa os arquivos novos no disco a
# tempo desses imports pegarem o código atualizado, sem precisar reiniciar
# o processo. Devolve a QApplication criada pra perguntar (se alguma foi
# criada) pra reaproveitar mais abaixo — só é possível existir uma por
# processo.
_app_atualizador = atualizador.verificar_atualizacoes()

# Só faz algo no Windows (ver Config/impressoraWindows.py) — acha a
# Bematech MP-4200 TH nas portas USB e garante que existe uma fila de
# impressão apontando pra ela, já que o Windows não cria essa fila
# sozinho mesmo reconhecendo o hardware. Melhor esforço: se não achar
# impressora nenhuma, ou a configuração falhar por qualquer motivo, só
# loga um aviso e o app continua normalmente sem impressora configurada.
impressoraWindows.garantir_impressora_bematech()

import sys
import os

try:
    from PyQt6.QtCore import QObject, pyqtSlot, QVariant, QUrl
    from PyQt6.QtGui import QGuiApplication
    from PyQt6.QtQml import QQmlApplicationEngine

    from controllers.balcaoController import BalcaoController
    from controllers.entregaController import EntregaController
    from controllers.consultaController import ConsultaController
    from services.rede import rede
    from services.iconProvider import IconProvider
    from services.comandaEstiloService import ComandaEstiloController
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

# codigo perigoso
os.environ["QML_XHR_ALLOW_FILE_READ"] = "1"

if __name__ == "__main__":
    app = _app_atualizador or QGuiApplication(sys.argv)
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
    consultaController = ConsultaController()
    engine.rootContext().setContextProperty("consultaController", consultaController)
    comandaEstiloController = ComandaEstiloController()
    engine.rootContext().setContextProperty("comandaEstiloController", comandaEstiloController)

    # Compartilha pedidos com outras instâncias deste app na mesma rede
    # local (ver architecture/EXPLAIN.md). Os sinais entram pelo
    # consultaController, que é quem sabe gravar/apagar os .txt e avisar a
    # tela de Consulta; iniciar() só pode rodar depois do QGuiApplication.
    rede.pedidoRecebido.connect(consultaController.aplicarPedidoRemoto)
    rede.pedidoRemovidoRemoto.connect(consultaController.removerPedidoRemoto)
    engine.rootContext().setContextProperty("redeController", rede)
    rede.iniciar()

    engine.addImportPath(qml_dir)
 
    engine.load(main_qml)

    if not engine.rootObjects():
        sys.exit(-1)

    sys.exit(app.exec())
