pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia

Singleton {
    id: root

    // ~/.local/bin no está en el PATH del proceso de Quickshell, así que hay que
    // invocar el script por ruta absoluta (mismo patrón que NotificacionesView.qml).
    readonly property string script: Quickshell.env("HOME") + "/.local/bin/caelestia-server-mode"

    // La confirmación la hace el botón: mantener pulsado ~1 s (ver HoldToggle en
    // modules/utilities/cards/Toggles.qml). Aquí solo se dispara la acción.
    function activate(): void {
        Toaster.toast(qsTr("Entrando en modo servidor…"), qsTr("Cerrando el escritorio. Vuelve con «volver-escritorio» desde la consola."), "dns");
        Quickshell.execDetached([root.script, "on"]);
    }

    IpcHandler {
        function activate(): void {
            root.activate();
        }

        target: "serverMode"
    }
}
