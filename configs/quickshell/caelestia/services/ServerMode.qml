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

    function activate(): void {
        Toaster.toast(qsTr("Entrando en modo servidor…"), qsTr("Cerrando el escritorio. Vuelve con «volver-escritorio» desde la consola."), "dns");
        Quickshell.execDetached(["caelestia-server-mode", "on"]);
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
