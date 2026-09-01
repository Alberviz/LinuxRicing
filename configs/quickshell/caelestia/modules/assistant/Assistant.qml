pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.modules.assistant

// Punto de entrada del overlay de Aurora. Se registra en shell.qml
// (`import "modules/assistant"` + `Assistant {}`). Las dos ventanas existen
// siempre; su visibilidad la decide un binding sobre el servicio Aurora.
Scope {
    // Fuerza la carga del singleton al iniciar el shell (no perezosa),
    // para que enganche el socket de eventos del daemon desde ya.
    Component.onCompleted: Aurora.socketPath // fuerza la carga del singleton

    Variants {
        model: Screens.screens

        Scope {
            id: perScreen

            required property ShellScreen modelData

            OrbWindow {
                modelData: perScreen.modelData
            }

            BarWindow {
                modelData: perScreen.modelData
            }
        }
    }
}
