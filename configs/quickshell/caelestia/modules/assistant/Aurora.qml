pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Servicio del asistente de voz Aurora.
//
// Lee el bus de eventos del daemon (`$XDG_RUNTIME_DIR/aurora-events.sock`,
// JSON por líneas — ver assistant/events.py) y lo expone como propiedades
// reactivas para el overlay. Si el daemon aún no está, reintenta la conexión.
Singleton {
    id: root

    readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/aurora-events.sock`

    // Estado del ciclo: idle | listening | thinking | speaking
    property string state: "idle"
    // Modo de invocación del ciclo en curso: centro | barra
    property string mode: "centro"
    // Último texto transcrito de Alberto (para el bocadillo)
    property string transcript: ""
    // Acciones ejecutadas en el ciclo: [{icon, text}, ...]
    property var actions: []
    // Nivel de voz 0..1 (grabando y hablando), ya suavizado
    property real amplitude: 0

    readonly property bool active: state !== "idle"

    // --- Colores del theming dinámico de Caelestia (nunca hardcodear) ---
    readonly property color accent: Colours.palette.m3primary
    readonly property color accentAlt: Colours.palette.m3tertiary
    readonly property color onAccent: Colours.palette.m3onPrimary
    readonly property color surface: Colours.palette.m3surfaceContainer
    readonly property color onSurface: Colours.palette.m3onSurface

    Behavior on amplitude {
        NumberAnimation {
            duration: 90
            easing.type: Easing.OutQuad
        }
    }

    function _handle(line: string): void {
        if (!line)
            return;
        let ev;
        try {
            ev = JSON.parse(line);
        } catch (e) {
            return;
        }
        switch (ev.type) {
        case "state":
            root.state = ev.value;
            if (ev.mode)
                root.mode = ev.mode;
            if (ev.value === "listening") {
                root.transcript = "";
                root.actions = [];
            }
            if (ev.value === "idle")
                root.amplitude = 0;
            break;
        case "amplitude":
            root.amplitude = ev.value;
            break;
        case "transcript":
            root.transcript = ev.value;
            break;
        case "result":
            root.actions = ev.actions ?? [];
            break;
        }
    }

    Socket {
        id: sock

        path: root.socketPath
        parser: SplitParser {
            onRead: line => root._handle(line)
        }
    }

    // El daemon puede arrancar después del shell (o reiniciarse). Reengancha.
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!sock.connected)
                sock.connected = true;
        }
    }
}
