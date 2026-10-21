pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.assistant

// Cajón de Laura (SUPER+I) — propuesta C «Tablero de agentes».
//
// Arriba, cuatro chips de agente (Laura, Gemini, Claude, Aurora) con su
// actividad; pulsar uno filtra la rejilla y volver a pulsarlo quita el filtro.
// Debajo, una rejilla de tarjetas compactas en este orden: lo que espera tu OK
// (ámbar), lo que está en marcha, lo que Laura hace por su cuenta y lo hecho.
//
// Ventana estrecha pegada a la derecha, solo existe mientras el cajón está
// abierto o moviéndose; la máscara de entrada es el propio panel. Revelado tipo
// cortina (clip), sin blur ni sombras caras. El reloj de las animaciones
// internas solo corre con el cajón visible.
StyledWindow {
    id: win

    required property ShellScreen modelData

    readonly property int panelW: 580
    readonly property bool shown: Laura.drawerOpen && root.mineScreen

    property real prog: shown ? 1 : 0
    Behavior on prog {
        NumberAnimation {
            duration: 420
            easing.type: Easing.OutCubic
        }
    }

    screen: modelData
    name: "laura-drawer"

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors.top: true
    anchors.bottom: true
    anchors.right: true
    implicitWidth: panelW + 24

    mask: Region {
        item: clipper
    }
    visible: prog > 0.001

    QtObject {
        id: root

        readonly property bool mineScreen: Laura.dockScreen === win.modelData.name
    }

    // --- estado de la vista ---
    property string seg: "all"      // all | mine | own
    property string agente: ""      // "" = sin filtro
    property real nowSec: Date.now() / 1000
    property real clock: 0
    property var entries: []

    Timer {
        interval: 1000
        repeat: true
        running: win.visible
        onTriggered: win.nowSec = Date.now() / 1000
    }
    // Reloj de las animaciones internas (anillos, barras): ~25 fps, solo visible
    Timer {
        interval: 40
        repeat: true
        running: win.visible
        property real t0: 0
        onRunningChanged: t0 = Date.now()
        onTriggered: win.clock += 0.04
    }

    function _fits(j): bool {
        if (win.agente === "laura")
            return Laura.isAviso(j) || (j.destino === "laura" && !Laura.isAviso(j));
        if (win.agente !== "")
            return j.destino === win.agente && !Laura.isAviso(j);
        return true;
    }
    function _rank(j): int {
        return j.prioridad === "alta" ? 0 : j.prioridad === "normal" ? 1 : 2;
    }
    function rebuild(): void {
        let l = Laura.jobs.filter(j => win._fits(j));
        if (win.seg === "mine")
            l = l.filter(j => !Laura.isAviso(j));
        else if (win.seg === "own")
            l = l.filter(j => Laura.isAviso(j));
        const cf = l.filter(j => j.kind === "confirm").sort((a, b) => a.inicio - b.inicio);
        const run = l.filter(j => (j.kind === "running" || j.kind === "agent") && !Laura.isAviso(j)).sort((a, b) => b.inicio - a.inicio);
        const own = l.filter(j => Laura.isAviso(j) && j.kind !== "confirm" && j.kind !== "running" && j.kind !== "agent").sort((a, b) => win._rank(a) - win._rank(b) || (b.fin ?? b.inicio) - (a.fin ?? a.inicio));
        const done = l.filter(j => !Laura.isAviso(j) && (j.kind === "done" || j.kind === "fail" || j.kind === "cancel")).sort((a, b) => (b.fin ?? b.inicio) - (a.fin ?? a.inicio));
        const out = [];
        const add = (label, tone, arr) => {
            if (arr.length === 0)
                return;
            out.push({
                k: "hdr",
                label: label,
                tone: tone,
                n: arr.length
            });
            for (const j of arr)
                out.push({
                    k: "job",
                    id: j.id
                });
        };
        add("Necesita tu OK", "wait", cf);
        add("Activos", "", run);
        add("Por su cuenta", "own", own);
        add("Hecho", "", done);
        const key = out.map(e => e.k === "hdr" ? "h" + e.label + e.n : e.id).join("|");
        if (key !== win._key) {
            win._key = key;
            win.entries = out;
        }
    }
    property string _key: ""

    onSegChanged: rebuild()
    onAgenteChanged: rebuild()
    Connections {
        target: Laura

        function onJobsChanged(): void {
            win.rebuild();
        }
        function onDrawerFocusIdChanged(): void {
            flashT.restart();
        }
    }
    Component.onCompleted: rebuild()

    // Tras abrir, resalta y lleva la vista a la tarjeta pedida
    Timer {
        id: flashT

        interval: 160
        onTriggered: {
            const id = Laura.drawerFocusId;
            if (!id)
                return;
            for (let i = 0; i < grid.children.length; i++) {
                const c = grid.children[i];
                if (c.item && c.item.jid === id) {
                    c.item.flash = true;
                    const top = c.y, bot = c.y + c.height;
                    if (top < flick.contentY)
                        flick.contentY = Math.max(0, top - 8);
                    else if (bot > flick.contentY + flick.height)
                        flick.contentY = bot - flick.height + 8;
                }
            }
        }
    }

    // Cortina: el panel va fijo a la derecha y el recorte lo va revelando
    Item {
        id: clipper

        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: (win.panelW + 24) * win.prog
        clip: true

        Rectangle {
            id: panel

            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.top: parent.top
            anchors.topMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            width: win.panelW
            radius: 22
            color: Qt.alpha(Colours.palette.m3surface, 0.98)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3onSurface, 0.11)
            opacity: 0.4 + 0.6 * win.prog

            FocusScope {
                anchors.fill: parent
                focus: win.shown
                Keys.onEscapePressed: Laura.closeDrawer()

                // Cabecera
                Item {
                    id: head

                    x: 18
                    y: 14
                    width: parent.width - 32
                    height: 30

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Laura"
                        font.pixelSize: 19
                        font.bold: true
                    }

                    Row {
                        id: tools

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        // Todo / Mío / Suyo
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: segRow.width + 4
                            height: 28
                            radius: 10
                            color: Colours.palette.m3surfaceContainer

                            Row {
                                id: segRow

                                anchors.centerIn: parent
                                spacing: 0

                                Repeater {
                                    model: [["all", "Todo"], ["mine", "Mío"], ["own", "Suyo"]]

                                    Rectangle {
                                        id: sb

                                        required property var modelData
                                        readonly property bool on: win.seg === modelData[0]

                                        width: st.implicitWidth + 20
                                        height: 24
                                        radius: 8
                                        color: on ? Colours.palette.m3surfaceContainerHigh : "transparent"

                                        StyledText {
                                            id: st

                                            anchors.centerIn: parent
                                            text: sb.modelData[1]
                                            color: sb.on ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                                            font.pixelSize: 12
                                            font.bold: true
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: win.seg = sb.modelData[0]
                                        }
                                    }
                                }
                            }
                        }
                        // Buscar novedades (vigía)
                        Rectangle {
                            width: 30
                            height: 30
                            radius: 15
                            color: rMa.containsMouse ? Colours.palette.m3surfaceContainerHigh : "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: "↻"
                                color: Colours.palette.m3onSurfaceVariant
                                font.pixelSize: 17
                            }
                            MouseArea {
                                id: rMa

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Laura.vigiaNow()
                            }
                            Rectangle {
                                visible: rMa.containsMouse
                                anchors.right: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 6
                                width: tipT.implicitWidth + 16
                                height: tipT.implicitHeight + 8
                                radius: 8
                                color: Colours.palette.m3surfaceContainerHigh

                                StyledText {
                                    id: tipT

                                    anchors.centerIn: parent
                                    text: "Buscar novedades"
                                    font.pixelSize: 11.5
                                }
                            }
                        }
                        Rectangle {
                            width: 30
                            height: 30
                            radius: 15
                            color: xMa.containsMouse ? Colours.palette.m3surfaceContainerHigh : "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: "✕"
                                color: Colours.palette.m3onSurfaceVariant
                                font.pixelSize: 14
                            }
                            MouseArea {
                                id: xMa

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Laura.closeDrawer()
                            }
                        }
                    }
                }

                // Chips de agentes
                Row {
                    id: chips

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: head.bottom
                    anchors.topMargin: 10
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8

                    Repeater {
                        model: ["laura", "gemini", "claude", "aurora"]

                        AgentChip {
                            required property string modelData

                            width: (chips.width - 24) / 4
                            agent: modelData
                            clock: win.clock
                            selected: win.agente === modelData
                            onClicked: win.agente = win.agente === modelData ? "" : modelData
                        }
                    }
                }

                // Rejilla
                Flickable {
                    id: flick

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: chips.bottom
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 10
                    contentWidth: width
                    contentHeight: grid.implicitHeight + 20
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Flow {
                        id: grid

                        x: 14
                        y: 2
                        width: parent.width - 28
                        spacing: 9

                        Repeater {
                            model: win.entries

                            Loader {
                                id: ld

                                required property var modelData

                                sourceComponent: modelData.k === "hdr" ? hdrC : jobC
                                implicitWidth: item ? item.implicitWidth : 0
                                implicitHeight: item ? item.implicitHeight : 0
                                width: implicitWidth
                                height: implicitHeight
                            }
                        }

                        Component {
                            id: hdrC

                            Item {
                                readonly property var m: ld.modelData

                                implicitWidth: grid.width
                                implicitHeight: 24

                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: 4
                                    width: parent.width
                                    spacing: 9

                                    StyledText {
                                        id: hl

                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (m.label + " · " + m.n).toUpperCase()
                                        color: m.tone === "wait" ? Laura.cWait : m.tone === "own" ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant
                                        font.pixelSize: 10.5
                                        font.bold: true
                                        font.letterSpacing: 1.2
                                    }
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - hl.width - 9
                                        height: 1
                                        color: Qt.alpha(Colours.palette.m3onSurface, 0.11)
                                    }
                                }
                            }
                        }

                        Component {
                            id: jobC

                            LauraJobCard {
                                jid: ld.modelData.id
                                flowW: grid.width
                                nowSec: win.nowSec
                                clock: win.clock
                            }
                        }
                    }

                    StyledText {
                        visible: win.entries.length === 0
                        x: 18
                        y: 14
                        text: "Nada por aquí todavía."
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }
}
