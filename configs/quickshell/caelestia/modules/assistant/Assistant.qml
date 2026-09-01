pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// Punto de entrada del overlay de Aurora. Se registra en shell.qml
// (`import "modules/assistant"` + `Assistant {}`). Las dos ventanas existen
// siempre; su visibilidad la decide un binding sobre el servicio Aurora.
Scope {
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
