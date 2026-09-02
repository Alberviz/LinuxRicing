pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.assistant

// Punto de entrada del overlay de Laura. Se registra en shell.qml
// (`import "modules/assistant"` + `Assistant {}`). Una sola ventana por
// pantalla; su visibilidad la decide un binding sobre el servicio Laura.
Scope {
    // Fuerza la carga del singleton al iniciar el shell (no perezosa),
    // para que enganche el socket de eventos del daemon desde ya.
    Component.onCompleted: Laura.socketPath

    Variants {
        model: Screens.screens

        Scope {
            id: perScreen

            required property ShellScreen modelData

            LauraOverlay {
                modelData: perScreen.modelData
            }
        }
    }
}
