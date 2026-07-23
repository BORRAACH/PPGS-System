import preConfig

preConfig.garantir_dependencias()

import sys
import os
from PyQt6.QtCore import QObject, pyqtSlot, QVariant
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import QQmlApplicationEngine

from controllers.balcaoController import BalcaoController

# codigo perigoso
os.environ["QML_XHR_ALLOW_FILE_READ"] = "1"

if __name__ == "__main__":
    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()

    # Diretório onde o script está sendo executado
    base_dir = os.path.dirname(os.path.abspath(__file__))
    qml_dir = os.path.join(base_dir, "qml")
    main_qml = os.path.join(qml_dir, "main.qml")
    controller = BalcaoController()
    engine.rootContext().setContextProperty("balcaoController", controller)
    
    engine.addImportPath(qml_dir)
 
    engine.load(main_qml)

    if not engine.rootObjects():
        sys.exit(-1)

    sys.exit(app.exec())
