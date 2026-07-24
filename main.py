import preConfig

preConfig.garantir_dependencias()

import sys
import os

try:
    from PyQt6.QtCore import QObject, pyqtSlot, QVariant, QUrl
    from PyQt6.QtGui import QGuiApplication
    from PyQt6.QtQml import QQmlApplicationEngine

    from controllers.balcaoController import BalcaoController
    from controllers.entregaController import EntregaController
    from controllers.consultaController import ConsultaController
    from services.redeService import rede
except ModuleNotFoundError as erro:
    # preConfig.garantir_dependencias() já tentou instalar tudo sozinho —
    # se mesmo assim algo continua faltando (sem internet, sem permissão
    # etc.), termina aqui com uma mensagem clara em vez de um traceback cru.
    # erro.name é o módulo exato (ex: "PyQt6.QtCore"), não necessariamente o
    # nome do pacote pip — busca o pacote real em preConfig quando possível.
    pacote = erro.name or "<pacote>"
    for nome_pacote, nome_modulo, _plataforma in preConfig._DEPENDENCIAS_PIP:
        if pacote == nome_modulo or pacote.startswith(nome_modulo.split(".")[0] + "."):
            pacote = nome_pacote
            break
    print(
        f"[main] Não foi possível carregar a dependência '{erro.name}' mesmo "
        "depois do preConfig tentar instalá-la automaticamente. Verifique "
        f"sua conexão com a internet ou instale manualmente: pip install {pacote}"
    )
    sys.exit(1)

# codigo perigoso
os.environ["QML_XHR_ALLOW_FILE_READ"] = "1"

if __name__ == "__main__":
    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()

    # Diretório onde o script está sendo executado
    base_dir = os.path.dirname(os.path.abspath(__file__))
    qml_dir = os.path.join(base_dir, "qml")
    main_qml = os.path.join(qml_dir, "main.qml")
    # Exposto ao QML para montar caminhos absolutos (ex: data/cardapio/*.json)
    # a partir da raiz do projeto, em vez de caminhos relativos "../../../.."
    # que quebram se um arquivo .qml mudar de pasta.
    engine.rootContext().setContextProperty("raizProjeto", QUrl.fromLocalFile(base_dir + os.sep))

    controller = BalcaoController()
    engine.rootContext().setContextProperty("balcaoController", controller)
    entregaController = EntregaController()
    engine.rootContext().setContextProperty("entregaController", entregaController)
    consultaController = ConsultaController()
    engine.rootContext().setContextProperty("consultaController", consultaController)

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
