pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia

Singleton {
    id: root

    // El botón cierra el escritorio entero, así que se confirma con doble toque:
    // el primer toque "arma" durante unos segundos, el segundo lo dispara.
    property bool armed: false

    function request(): void {
        if (armed) {
            armed = false;
            disarmTimer.stop();
            activate();
        } else {
            armed = true;
            disarmTimer.restart();
            Toaster.toast(qsTr("¿Entrar en modo servidor?"), qsTr("Toca otra vez para cerrar el escritorio y caer a consola. El servidor de Minecraft sigue vivo."), "dns", Toast.Warning);
        }
    }

    // ~/.local/bin no está en el PATH del proceso de Quickshell, así que hay que
    // invocar el script por ruta absoluta (mismo patrón que NotificacionesView.qml).
    readonly property string script: Quickshell.env("HOME") + "/.local/bin/caelestia-server-mode"

    function activate(): void {
        Toaster.toast(qsTr("Entrando en modo servidor…"), qsTr("Cerrando el escritorio. Vuelve con «volver-escritorio» desde la consola."), "dns");
        Quickshell.execDetached([root.script, "on"]);
    }

    Timer {
        id: disarmTimer

        interval: 5000
        onTriggered: root.armed = false
    }

    IpcHandler {
        function activate(): void {
            root.activate();
        }

        function isArmed(): bool {
            return root.armed;
        }

        target: "serverMode"
    }
}
