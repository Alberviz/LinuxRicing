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
    // Último texto transcrito de Alberto
    property string transcript: ""
    // Última respuesta de Aurora, al completo (para el bocadillo del modo principal)
    property string reply: ""
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
        // Cualquier línea (incluido el ping) prueba que el enlace sigue vivo.
        linkWatch.restart();
        if (ev.type === "ping")
            return;
        // Los eventos de "progreso" reinician el guardián de estado atascado;
        // amplitude no cuenta (fluye sin que el ciclo avance).
        if (ev.type !== "amplitude")
            stuckWatch.restart();
        switch (ev.type) {
        case "state":
            root.state = ev.value;
            if (ev.mode)
                root.mode = ev.mode;
            if (ev.value === "listening") {
                root.transcript = "";
                root.reply = "";
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
        case "reply":
            root.reply = ev.value;
            break;
        case "result":
            root.actions = ev.actions ?? [];
            break;
        }
    }

    // Quickshell no reconecta un Socket que ya erró: reasignar `connected` no
    // basta. Hay que recrear el objeto. El Socket vive en un Loader y lo
    // reciclamos cuando el enlace lleva demasiado tiempo mudo.
    Component {
        id: socketComp

        Socket {
            path: root.socketPath
            connected: true
            parser: SplitParser {
                onRead: line => root._handle(line)
            }
        }
    }

    Loader {
        id: sockLoader
        active: true
        sourceComponent: socketComp
    }

    // El daemon manda un "ping" cada 5 s; cada línea reinicia este timer. Si
    // pasan 9 s sin recibir NADA, el enlace está muerto (o el daemon aún no
    // estaba) -> recrear el Socket.
    Timer {
        id: linkWatch
        interval: 9000
        repeat: true
        running: true
        onTriggered: {
            sockLoader.active = false;
            sockLoader.active = true;
        }
    }

    // Si el ciclo se atasca (p. ej. Ollama no responde) y el estado no avanza
    // en 75 s, devolver el overlay a idle para no quedarse en "pensando".
    Timer {
        id: stuckWatch
        interval: 75000
        onTriggered: {
            root.state = "idle";
            root.amplitude = 0;
        }
    }
}
