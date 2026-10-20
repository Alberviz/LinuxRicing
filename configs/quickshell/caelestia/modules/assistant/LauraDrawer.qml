pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.modules.assistant

// Cajón lateral de Laura (panel 1 del mockup): una tarjeta por trabajo de las
// últimas 24 h. Ventana estrecha pegada al borde derecho; solo existe mientras
// está abierto o deslizándose. La máscara de entrada es el propio panel.
StyledWindow {
    id: win

    required property ShellScreen modelData

    // 0..1 de la apertura
    property real prog: Laura.drawerOpen && root.mineScreen ? 1 : 0
    Behavior on prog {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutCubic
        }
    }

    screen: modelData
    name: "laura-drawer"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: Laura.drawerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors.top: true
    anchors.bottom: true
    anchors.right: true
    implicitWidth: 372

    mask: Region {
        item: panel
    }
    visible: prog > 0.001

    // Atajo para el nombre (evita repetir la comparación)
    QtObject {
        id: root

        readonly property bool mineScreen: Laura.dockScreen === win.modelData.name
    }

    property string filter: "all"
    property real nowSec: Date.now() / 1000
    // IDs de las tarjetas visibles; solo se reasigna si el conjunto cambia
    property var ids: []

    function _rank(j): int {
        return j.kind === "confirm" ? 0 : (j.kind === "running" || j.kind === "agent") ? 1 : (j.kind === "done" || j.kind === "fail") ? 2 : 3;
    }
    function rebuild(): void {
        let l = Laura.jobs.slice();
        if (win.filter === "run")
            l = l.filter(j => Laura.isActive(j));
        else if (win.filter === "done")
            l = l.filter(j => j.kind === "done" || j.kind === "fail");
        l.sort((a, b) => win._rank(a) - win._rank(b) || (b.fin ?? b.inicio) - (a.fin ?? a.inicio));
        const next = l.map(j => j.id);
        if (next.join("|") !== win.ids.join("|"))
            win.ids = next;
    }
    onFilterChanged: rebuild()
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

    Timer {
        interval: 1000
        repeat: true
        running: win.visible
        onTriggered: win.nowSec = Date.now() / 1000
    }
    // Tras abrir, resalta y desplaza hasta la tarjeta pedida
    Timer {
        id: flashT

        interval: 120
        onTriggered: {
            const id = Laura.drawerFocusId;
            if (!id)
                return;
            for (let i = 0; i < cards.count; i++) {
                const c = cards.itemAt(i);
                if (c && c.jid === id) {
                    c.flash = true;
                    const top = c.y, bot = c.y + c.height;
                    if (top < flick.contentY)
                        flick.contentY = top;
                    else if (bot > flick.contentY + flick.height)
                        flick.contentY = bot - flick.height;
                }
            }
        }
    }

    // Sombra a la izquierda del panel (gradiente, sin blur)
    Rectangle {
        x: panel.x - width
        y: 0
        width: 36
        height: parent.height
        opacity: win.prog
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0
                color: "transparent"
            }
            GradientStop {
                position: 1
                color: "#59000000"
            }
        }
    }

    Rectangle {
        id: panel

        x: parent.width - 330 * win.prog
        width: 330
        height: parent.height
        color: Qt.alpha(Colours.palette.m3surface, 0.98)

        Rectangle {
            width: 1
            height: parent.height
            color: Qt.alpha(Colours.palette.m3onSurface, 0.11)
        }

        FocusScope {
            anchors.fill: parent
            focus: Laura.drawerOpen
            Keys.onEscapePressed: Laura.closeDrawer()

            // Cabecera
            Item {
                id: head

                x: 14
                y: 12
                width: parent.width - 28
                height: 26

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Laura · segundo plano"
                    font.bold: true
                    font.pixelSize: 15
                }
                StyledText {
                    id: closeT

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cerrar"
                    color: closeMa.containsMouse ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small

                    MouseArea {
                        id: closeMa

                        anchors.fill: parent
                        anchors.margins: -5
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Laura.closeDrawer()
                    }
                }
            }

            // Filtros
            Row {
                id: chips

                x: 14
                anchors.top: head.bottom
                anchors.topMargin: 6
                spacing: 6

                Repeater {
                    model: [["all", "Todos"], ["run", "En curso"], ["done", "Hechos"]]

                    Rectangle {
                        id: chip

                        required property var modelData
                        readonly property bool on: win.filter === modelData[0]

                        implicitWidth: ct.implicitWidth + 20
                        implicitHeight: ct.implicitHeight + 8
                        radius: height / 2
                        color: on ? Colours.palette.m3surfaceContainerHigh : "transparent"
                        border.width: on ? 0 : 1
                        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.11)

                        StyledText {
                            id: ct

                            anchors.centerIn: parent
                            text: chip.modelData[1]
                            color: chip.on ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.filter = chip.modelData[0]
                        }
                    }
                }
            }

            Flickable {
                id: flick

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: chips.bottom
                anchors.bottom: parent.bottom
                anchors.topMargin: 10
                contentWidth: width
                contentHeight: list.implicitHeight + 16
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: list

                    x: 12
                    width: parent.width - 24
                    spacing: 10

                    Repeater {
                        id: cards

                        model: win.ids

                        LauraJobCard {
                            required property string modelData

                            jid: modelData
                            width: list.width
                            nowSec: win.nowSec
                        }
                    }

                    StyledText {
                        visible: win.ids.length === 0
                        padding: 14
                        text: "Nada por aquí todavía."
                        color: Colours.palette.m3onSurfaceVariant
                    }
                }
            }
        }
    }
}
