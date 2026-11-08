pragma Singleton
pragma ComponentBehavior: Bound

// DragWatch — cliente del socket de `drag-watch` (widgets/drag-watch). Publica si hay un
// arrastre de archivo en curso y la posición global del cursor mientras dure. Sin servicio
// no hay arrastre: solo reintenta conectar cada 5 s (nunca hay sondeo si está conectado).

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool dragging: false
    property real cx: 0
    property real cy: 0
    readonly property bool online: sock.connected

    Socket {
        id: sock

        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/drag-watch.sock`
        connected: true
        onConnectedChanged: {
            if (!connected)
                root.dragging = false;
        }

        parser: SplitParser {
            onRead: line => {
                try {
                    const d = JSON.parse(line);
                    root.cx = d.x ?? root.cx;
                    root.cy = d.y ?? root.cy;
                    root.dragging = !!d.dragging;
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: !sock.connected
        onTriggered: sock.connected = true
    }
}
