pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.assistant

// Orbe de Laura (convergencia «a» + orbe «i» del mockup aprobado).
//
// Dos ventanas por pantalla, ambas transparentes:
//  · `LauraConverge`: pantalla completa y click-through, solo existe ~1,4 s al
//    nacer el primer trabajo.
//  · el dock: ventana ESTRECHA pegada al borde derecho (capa Overlay, sin foco
//    de teclado) con máscara de entrada solo sobre el orbe, los satélites y la
//    píldora. En reposo no existe (visible: false).
//
// Rendimiento: un único Timer (25 fps) mueve el reloj de los orbes y solo
// corre mientras haya un trabajo trabajando / esperando / pidiendo OK. Con todo
// terminado la imagen queda quieta; sin trabajos pendientes la ventana se oculta.
Scope {
    id: root

    required property ShellScreen modelData

    readonly property int maxShown: 6
    // Trabajos mostrados, ordenados: confirmación > fallido > terminado sin leer > trabajando
    property var order: []
    property int more: 0
    property bool holdDock: false
    // ¿Es este el monitor del orbe? Se fija al nacer y se suelta al disolverse.
    property bool mine: false

    function _pr(j): int {
        if (j.kind === "confirm")
            return 0;
        if (j.kind === "fail" && !j.leido)
            return 1;
        if (j.kind === "done" && !j.leido)
            return 2;
        return Laura.isActive(j) ? 3 : 4;
    }

    function rebuild(): void {
        if (root.holdDock)
            return;
        const keep = Laura.keepIds;
        const shown = Laura.jobs.filter(j => Laura.isActive(j) || Laura.isUnseen(j) || keep[j.id]);
        shown.sort((a, b) => root._pr(a) - root._pr(b) || b.inicio - a.inicio);
        const ids = shown.slice(0, root.maxShown).map(j => j.id);
        root.more = Math.max(0, shown.length - root.maxShown);
        const wasEmpty = root.order.length === 0;
        if (wasEmpty && ids.length > 0)
            root.claim();
        root.order = ids;
        // Sincronizar el modelo (altas / bajas con animación)
        for (let i = 0; i < entries.count; i++) {
            const gone = ids.indexOf(entries.get(i).jid) < 0;
            if (entries.get(i).gone !== gone)
                entries.setProperty(i, "gone", gone);
        }
        for (const id of ids) {
            let found = false;
            for (let i = 0; i < entries.count; i++)
                if (entries.get(i).jid === id)
                    found = true;
            if (!found)
                entries.append({
                    jid: id,
                    gone: false
                });
        }
        purge.restart();
    }

    function claim(): void {
        const f = Hypr.focusedMonitor;
        root.mine = !f || f.name === root.modelData.name;
        if (root.mine)
            Laura.dockScreen = root.modelData.name;
    }

    ListModel {
        id: entries
    }

    // Quita del modelo (y suelta el monitor) cuando las salidas terminan de disolverse
    Timer {
        id: purge

        interval: 850
        onTriggered: {
            for (let i = entries.count - 1; i >= 0; i--)
                if (entries.get(i).gone)
                    entries.remove(i);
            if (entries.count === 0 && !root.holdDock)
                root.mine = false;
        }
    }

    Connections {
        target: Laura

        function onJobsChanged(): void {
            root.rebuild();
        }
        function onKeepIdsChanged(): void {
            root.rebuild();
        }
        function onJobStarted(job): void {
            // Convergencia solo si no había orbe en pantalla
            if (root.order.length === 0 && entries.count === 0) {
                root.claim();
                if (!root.mine)
                    return;
                root.holdDock = true;
                conv.start(Laura.agentColor(job.destino), dockWin.orbCenterY);
            }
        }
        function onJobFinished(job): void {
            if (!root.mine || Laura.drawerOpen)
                return;
            pill.show(job);
        }
    }

    Component.onCompleted: rebuild()

    LauraConverge {
        id: conv

        modelData: root.modelData
        onBorn: {
            root.holdDock = false;
            root.rebuild();
        }
    }

    // --- Dock del orbe -------------------------------------------------------
    StyledWindow {
        id: dockWin

        readonly property real orbCenterY: screen.height * 0.4
        // Cuánto se aparta el dock a la izquierda cuando el cajón está abierto
        property real shift: Laura.drawerOpen ? 340 : 0
        Behavior on shift {
            NumberAnimation {
                duration: 350
                easing.type: Easing.OutCubic
            }
        }

        screen: root.modelData
        name: "laura-orb"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors.top: true
        anchors.right: true
        margins.top: Math.max(0, orbCenterY - 23 - 12)
        implicitWidth: 820
        implicitHeight: 12 + 46 + 5 * 29 + 40

        // Solo el orbe, los satélites y la píldora capturan el ratón.
        mask: Region {
            item: dockHit

            Region {
                item: pillHit
            }
        }

        visible: root.mine && (entries.count > 0 || root.holdDock) && !root.holdDock

        // Reloj compartido: solo corre con trabajos en movimiento
        property real clock: 0
        readonly property real t0: Date.now()
        readonly property bool moving: {
            for (const id of root.order) {
                const j = Laura.jobs.find(x => x.id === id);
                if (j && Laura.isActive(j))
                    return true;
            }
            return false;
        }
        Timer {
            interval: 40
            repeat: true
            running: dockWin.visible && dockWin.moving
            onTriggered: dockWin.clock = (Date.now() - dockWin.t0) / 1000
        }

        Item {
            id: dock

            x: dockWin.width - 46 - 3 - dockWin.shift
            y: 12
            width: 46
            height: parent.height - 12

            // Zona de entrada (se ajusta a lo que hay)
            Item {
                id: dockHit

                width: 46 + 3
                height: root.order.length === 0 ? 0 : 46 + Math.max(0, root.order.length - 1) * 29 + (root.more > 0 ? 18 : 0)
                x: 0
                y: 0
            }

            Repeater {
                model: entries

                LauraOrbItem {
                    id: o

                    required property string jid
                    required gone
                    required property int index

                    readonly property int rk: root.order.indexOf(jid)
                    property int lastRk: 0
                    onRkChanged: if (rk >= 0)
                        lastRk = rk
                    Component.onCompleted: lastRk = Math.max(0, rk)

                    job: Laura.jobs.find(j => j.id === jid) ?? ({})
                    isMain: lastRk === 0
                    clock: dockWin.clock
                    x: 46 - d
                    y: lastRk === 0 ? 0 : 46 + 9 + (lastRk - 1) * 29
                    Behavior on y {
                        NumberAnimation {
                            duration: 450
                            easing.type: Easing.OutCubic
                        }
                    }
                    onClicked: {
                        pill.hide();
                        Laura.openDrawer(jid);
                    }
                }
            }

            Text {
                visible: root.more > 0
                anchors.right: parent.right
                y: 46 + 9 + Math.max(0, root.order.length - 1) * 29
                text: "+" + root.more
                color: Colours.palette.m3onSurfaceVariant
                font.pixelSize: 11
            }
        }

        // Píldora de aviso al terminar un trabajo
        Item {
            id: pillHit

            x: pill.x
            y: pill.y
            width: pill.shown ? pill.width : 0
            height: pill.shown ? pill.height : 0
        }

        Rectangle {
            id: pill

            property bool shown: false
            property var pjob: ({})
            readonly property color col: Laura.agentColor(pjob.destino ?? "laura")

            function _phrase(j): string {
                const r = (j.resumen ?? "").trim();
                if (r.length > 0) {
                    const m = r.match(/^[^.!?\n]+[.!?]?/);
                    const t = (m ? m[0] : r).trim();
                    return t.length > 46 ? t.slice(0, 45) + "…" : t;
                }
                const t = (j.titulo ?? "").trim();
                return (j.kind === "fail" ? "Falló: " : "Listo: ") + (t.length > 38 ? t.slice(0, 37) + "…" : t);
            }
            function show(j): void {
                pjob = j;
                label.text = _phrase(j);
                shown = true;
                hideT.restart();
            }
            function hide(): void {
                shown = false;
                hideT.stop();
            }

            x: dock.x - width - 19
            y: dock.y + 9
            width: row.implicitWidth + 22
            height: row.implicitHeight + 14
            radius: height / 2
            color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.96)
            border.width: 1
            border.color: Qt.alpha(col, 0.45)
            opacity: shown ? 1 : 0
            visible: opacity > 0.01
            transform: Translate {
                x: pill.shown ? 0 : 10
                Behavior on x {
                    NumberAnimation {
                        duration: 350
                        easing.type: Easing.OutCubic
                    }
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 350
                }
            }

            Timer {
                id: hideT

                interval: 6000
                onTriggered: pill.shown = false
            }

            Row {
                id: row

                anchors.centerIn: parent
                spacing: 8

                AgentGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    agent: pill.pjob.destino ?? "laura"
                    color: pill.col
                    size: 16
                }
                StyledText {
                    id: label

                    anchors.verticalCenter: parent.verticalCenter
                    font: Tokens.font.body.small
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: pill.shown
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    pill.hide();
                    Laura.openDrawer(pill.pjob.id);
                }
            }
        }
    }
}
