pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// Punto de entrada del overlay de hologramas (HoloOverlay).
// Instancia una capa HoloLayer por cada pantalla conectada.
Variants {
    model: Screens.screens

    Scope {
        id: perScreen

        required property ShellScreen modelData

        HoloLayer {
            modelData: perScreen.modelData
            screen: perScreen.modelData
        }
    }
}
