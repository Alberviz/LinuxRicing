pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.services

// Pantalla completa de Elysium: campo de estrellas, el limbo de un planeta que
// se ilumina con el acento del tema y la fila de juegos posada en el horizonte.
PanelWindow {
    id: win

    required property var elysium

    readonly property bool shown: elysium.consoleShown && !launching
    property bool launching: false
    property int index: 0

    readonly property var items: elysium.games.concat([
        {
            "system": "gamemode",
            "name": qsTr("Modo juego"),
            "subtitle": qsTr("Volver al escritorio y seguir con el modo juego activo"),
            "tag": qsTr("Sistema"),
            "glyph": "sports_esports"
        },
        {
            "system": "desktop",
            "name": qsTr("Escritorio"),
            "subtitle": qsTr("Salir de Elysium y restaurar el sistema"),
            "tag": qsTr("Sistema"),
            "glyph": "space_dashboard"
        }
    ])
    readonly property var current: items[index]
    readonly property bool isRunning: elysium.playing && current.proc !== undefined && elysium.runningGame?.proc === current.proc
    readonly property color accent: Colours.palette.m3primary

    function activate(): void {
        const it = current;
        if (it.system === "desktop")
            elysium.leave(false);
        else if (it.system === "gamemode")
            elysium.leave(true);
        else if (isRunning)
            elysium.summoned = false;
        else
            launchSeq.start();
    }

    function pad(b: string): void {
        if (launching)
            return;
        if (b === "left")
            index = Math.max(0, index - 1);
        else if (b === "right")
            index = Math.min(items.length - 1, index + 1);
        else if (b === "a" || b === "start")
            activate();
        else if (b === "b" || b === "home") {
            if (elysium.playing)
                elysium.summoned = false;
            else if (current.system === "desktop")
                elysium.leave(false);   // B dos veces = salir
            else
                index = items.length - 1;
        }
    }

    Connections {
        target: win.elysium

        function onPad(b: string): void {
            win.pad(b);
        }
    }

    screen: Quickshell.screens.find(s => Hypr.monitorFor(s) === Hypr.focusedMonitor) ?? Quickshell.screens[0]
    visible: elysium.consoleShown || stage.opacity > 0.01
    color: "transparent"
    WlrLayershell.namespace: "caelestia-elysium"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: elysium.consoleShown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Item {
        id: stage

        anchors.fill: parent
        opacity: win.elysium.consoleShown ? 1 : 0
        focus: true

        Behavior on opacity {
            NumberAnimation {
                duration: 450
                easing.type: Easing.OutCubic
            }
        }

        Keys.onPressed: e => {
            const m = {
                [Qt.Key_Left]: "left",
                [Qt.Key_Right]: "right",
                [Qt.Key_Return]: "a",
                [Qt.Key_Enter]: "a",
                [Qt.Key_Space]: "a",
                [Qt.Key_Backspace]: "b"
            };
            // Esc desde teclado: salida inmediata, siempre.
            if (e.key === Qt.Key_Escape) {
                win.elysium.leave(false);
                e.accepted = true;
                return;
            }
            if (m[e.key]) {
                win.pad(m[e.key]);
                e.accepted = true;
            }
        }

        // --- cielo ---
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: "#030409"
                }
                GradientStop {
                    position: 0.7
                    color: Qt.tint("#05060c", Qt.alpha(win.accent, 0.10))
                }
                GradientStop {
                    position: 1
                    color: "#000000"
                }
            }
        }

        // Arte del juego, gigante y desenfocado, a la derecha.
        Image {
            id: heroArt

            anchors.right: parent.right
            anchors.rightMargin: -parent.width * 0.06
            anchors.top: parent.top
            anchors.topMargin: -parent.height * 0.1
            width: parent.height * 0.95
            height: width
            source: win.current.logo ?? win.current.icon ?? ""
            sourceSize.width: 512
            fillMode: Image.PreserveAspectFit
            visible: false
        }

        MultiEffect {
            anchors.fill: heroArt
            source: heroArt
            visible: heroArt.status === Image.Ready
            blurEnabled: true
            blur: 0.7
            blurMax: 48
            saturation: 0.2
            opacity: win.shown ? 0.32 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 900
                }
            }
        }

        // Estrellas: dos copias pintadas una vez; solo se desplaza el Item.
        Item {
            id: starfield

            width: parent.width * 2
            height: parent.height * 0.75

            NumberAnimation on x {
                from: 0
                to: -win.width
                duration: 300000
                loops: Animation.Infinite
                running: win.shown
            }

            Canvas {
                anchors.fill: parent
                renderStrategy: Canvas.Cooperative
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    let seed = 7;
                    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
                    const half = width / 2;
                    for (let i = 0; i < 260; i++) {
                        const x = rnd() * half, y = rnd() * height, r = rnd() < 0.08 ? 1.6 : 0.5 + rnd() * 0.7;
                        ctx.globalAlpha = 0.25 + rnd() * 0.65;
                        ctx.fillStyle = rnd() < 0.15 ? String(win.accent) : "#ffffff";
                        for (const off of [0, half]) {
                            ctx.beginPath();
                            ctx.arc(x + off, y, r, 0, Math.PI * 2);
                            ctx.fill();
                        }
                    }
                }
            }
        }

        // --- el planeta ---
        Item {
            id: planet

            readonly property real horizon: win.height * 0.72
            readonly property real d: win.width * 2.4

            anchors.fill: parent

            transform: Translate {
                y: win.shown ? 0 : win.height * 0.28
                Behavior on y {
                    NumberAnimation {
                        duration: 1400
                        easing.type: Easing.OutQuart
                    }
                }
            }

            // Atmósfera sobre el horizonte.
            Rectangle {
                x: 0
                width: parent.width
                y: planet.horizon - height + 40
                height: win.height * 0.34
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 0.88
                        color: Qt.alpha(win.accent, 0.13)
                    }
                    GradientStop {
                        position: 1
                        color: "transparent"
                    }
                }
            }
            // Limbo del planeta en GPU (Shape). Un Canvas aquí colgaba el shell.
            Shape {
                id: limb

                readonly property real rr: planet.d / 2
                readonly property real cx: win.width / 2
                readonly property real cy: planet.horizon + rr

                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: LinearGradient {
                        y1: planet.horizon
                        y2: win.height
                        GradientStop {
                            position: 0
                            color: Qt.tint("#07080e", Qt.alpha(win.accent, 0.22))
                        }
                        GradientStop {
                            position: 0.25
                            color: "#030306"
                        }
                        GradientStop {
                            position: 1
                            color: "#000000"
                        }
                    }
                    PathAngleArc {
                        centerX: limb.cx
                        centerY: limb.cy
                        radiusX: limb.rr
                        radiusY: limb.rr
                        startAngle: 180
                        sweepAngle: 180
                    }
                }

                GlowArc {
                    strokeWidth: 30
                    strokeColor: Qt.alpha(win.accent, 0.05)
                }

                GlowArc {
                    strokeWidth: 16
                    strokeColor: Qt.alpha(win.accent, 0.09)
                }

                GlowArc {
                    strokeWidth: 8
                    strokeColor: Qt.alpha(win.accent, 0.16)
                }

                GlowArc {
                    strokeWidth: 4
                    strokeColor: Qt.alpha(win.accent, 0.32)
                }

                ShapePath {
                    fillColor: "transparent"
                    strokeWidth: 1.6
                    strokeColor: Qt.alpha("white", 0.85)
                    PathAngleArc {
                        centerX: limb.cx
                        centerY: limb.cy
                        radiusX: limb.rr
                        radiusY: limb.rr
                        startAngle: 200
                        sweepAngle: 140
                    }
                }
            }

            // Amanecer en el centro del horizonte.
            Rectangle {
                x: win.width * 0.2
                y: planet.horizon - height / 2
                width: win.width * 0.6
                height: win.height * 0.5
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop {
                        position: 0
                        color: "transparent"
                    }
                    GradientStop {
                        position: 0.5
                        color: Qt.alpha(win.accent, 0.10)
                    }
                    GradientStop {
                        position: 1
                        color: "transparent"
                    }
                }
                opacity: 0.8
                visible: false
            }
        }

        // --- barra superior ---
        Row {
            x: 72
            y: 48
            spacing: 14
            opacity: win.shown ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 600
                }
            }

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: "stadia_controller"
                color: win.accent
                fontStyle: Tokens.font.icon.builders.medium.scale(1.4).build()
                fill: 1
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "ELYSIUM"
                color: Colours.palette.m3onSurface
                font.family: Tokens.font.title.large.family
                font.pointSize: 15
                font.weight: Font.Light
                font.letterSpacing: win.shown ? 9 : 30

                Behavior on font.letterSpacing {
                    NumberAnimation {
                        duration: 1100
                        easing.type: Easing.OutExpo
                    }
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 72
            y: 48
            spacing: 26
            opacity: win.shown ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 600
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                opacity: win.elysium.padName ? 1 : 0.35

                MaterialIcon {
                    text: win.elysium.padName ? "gamepad" : "videogame_asset_off"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.medium.scale(1.1).build()
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                visible: UPower.displayDevice.isLaptopBattery

                MaterialIcon {
                    text: UPower.onBattery ? "battery_5_bar" : "bolt"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.medium.scale(1.1).build()
                }

                StyledText {
                    text: Math.round(UPower.displayDevice.percentage * 100) + "%"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.large
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Time.format("HH:mm")
                color: Colours.palette.m3onSurface
                font.family: Tokens.font.title.large.family
                font.pointSize: 18
                font.weight: Font.Light
            }
        }

        // --- héroe: el elemento seleccionado ---
        Column {
            id: hero

            x: 96
            y: win.height * 0.12
            spacing: 10
            opacity: win.shown ? 1 : 0

            transform: Translate {
                x: win.shown ? 0 : -40
                Behavior on x {
                    NumberAnimation {
                        duration: 900
                        easing.type: Easing.OutExpo
                    }
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 700
                }
            }

            StyledText {
                text: (win.isRunning ? qsTr("En juego") : win.current.tag).toUpperCase()
                color: win.accent
                font.family: Tokens.font.label.small.family
                font.pointSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 3.5
            }

            Image {
                visible: !!win.current.logo
                source: win.current.logo ?? ""
                height: win.height * 0.15
                width: height * 2.08
                sourceSize.height: height
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }

            StyledText {
                id: heroName

                visible: !win.current.logo
                text: win.current.name
                color: Colours.palette.m3onSurface
                font.family: Tokens.font.title.large.family
                font.pointSize: 50
                font.weight: Font.Light
            }

            StyledText {
                text: win.current.subtitle
                color: Colours.palette.m3onSurfaceVariant
                font.family: Tokens.font.title.large.family
                font.pointSize: 19
                width: win.width * 0.45
                wrapMode: Text.WordWrap
            }

            Item {
                width: 1
                height: 18
            }

            Rectangle {
                implicitHeight: 52
                implicitWidth: playRow.implicitWidth + 40
                radius: 26
                color: win.accent

                Row {
                    id: playRow

                    anchors.centerIn: parent
                    spacing: 12

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        letter: "A"
                        tone: Colours.palette.m3onPrimary
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.current.system === "desktop" ? qsTr("Salir") : win.current.system === "gamemode" ? qsTr("Ir al escritorio") : win.isRunning ? qsTr("Volver al juego") : qsTr("Jugar")
                        color: Colours.palette.m3onPrimary
                        font: Tokens.font.title.medium
                    }
                }
            }
        }

        // --- fila de juegos sobre el horizonte ---
        Row {
            id: shelf

            readonly property int tile: Math.round(win.height * 0.17)

            x: 96
            y: planet.horizon - tile - 48
            spacing: 28

            Repeater {
                model: win.items

                Item {
                    id: slot

                    required property var modelData
                    required property int index
                    readonly property bool sel: index === win.index

                    width: shelf.tile
                    height: shelf.tile
                    z: sel ? 1 : 0

                    property real rise: win.shown ? 0 : 80
                    opacity: win.shown ? (sel ? 1 : 0.55) : 0

                    Behavior on rise {
                        SequentialAnimation {
                            PauseAnimation {
                                duration: win.shown ? 300 + slot.index * 80 : 0
                            }
                            NumberAnimation {
                                duration: 700
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.2
                            }
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                        }
                    }

                    Rectangle {
                        id: face

                        property real lift: slot.sel ? -14 : 0

                        width: parent.width
                        height: parent.height
                        y: slot.rise + lift
                        scale: slot.sel ? 1.12 : 0.9
                        radius: 22
                        color: slot.modelData.system ? Qt.alpha(Colours.palette.m3onSurface, 0.06) : (slot.modelData.tint ?? "#222")
                        border.width: slot.sel ? 3 : 1
                        border.color: slot.sel ? win.accent : Qt.alpha(Colours.palette.m3onSurface, 0.12)

                        Behavior on scale {
                            NumberAnimation {
                                duration: 320
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.6
                            }
                        }

                        Behavior on lift {
                            NumberAnimation {
                                duration: 320
                                easing.type: Easing.OutCubic
                            }
                        }

                        Image {
                            anchors.fill: parent
                            anchors.margins: parent.width * 0.12
                            visible: !slot.modelData.system
                            source: slot.modelData.logo ?? slot.modelData.icon ?? ""
                            sourceSize.width: 400
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: !!slot.modelData.system
                            text: slot.modelData.glyph ?? ""
                            color: slot.sel ? win.accent : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.builders.medium.scale(2.6).build()
                            fill: slot.sel ? 1 : 0
                        }

                        // Punto verde si el juego está abierto.
                        Rectangle {
                            visible: win.elysium.playing && slot.modelData.proc !== undefined && win.elysium.runningGame?.proc === slot.modelData.proc
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 12
                            width: 10
                            height: 10
                            radius: 5
                            color: "#5ee08a"
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (slot.sel)
                                    win.activate();
                                else
                                    win.index = slot.index;
                            }
                        }
                    }

                    // Reflejo del acento en el horizonte bajo el seleccionado.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: parent.height + 34
                        height: 3
                        radius: 2
                        width: slot.sel ? parent.width * 0.7 : 0
                        color: win.accent
                        opacity: 0.9

                        Behavior on width {
                            NumberAnimation {
                                duration: 380
                                easing.type: Easing.OutExpo
                            }
                        }
                    }
                }
            }
        }

        // --- pistas de mando ---
        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 56
            spacing: 30
            opacity: win.shown ? 0.85 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 800
                }
            }

            Hint {
                letter: "A"
                label: qsTr("Seleccionar")
            }

            Hint {
                letter: "B"
                label: win.elysium.playing ? qsTr("Volver al juego") : qsTr("Salir")
            }

            Hint {
                letter: "⌂"
                label: qsTr("Mantener: Laura")
            }
        }

        // --- lanzamiento: el acento se expande desde la carátula ---
        Rectangle {
            id: burst

            readonly property real cx: shelf.x + win.index * (shelf.tile + shelf.spacing) + shelf.tile / 2
            readonly property real cy: shelf.y + shelf.tile / 2

            width: 40
            height: 40
            radius: 20
            x: cx - 20
            y: cy - 20
            color: win.current.tint ?? win.accent
            scale: 0
            visible: scale > 0
        }

        Rectangle {
            id: blackout

            anchors.fill: parent
            color: "black"
            opacity: 0

            StyledText {
                id: launchText

                anchors.centerIn: parent
                text: win.current.name
                color: "white"
                opacity: 0
                font.family: Tokens.font.title.large.family
                font.pointSize: 30
                font.weight: Font.Light
                font.letterSpacing: 6
            }
        }
    }

    SequentialAnimation {
        id: launchSeq

        ScriptAction {
            script: win.launching = true
        }
        NumberAnimation {
            target: burst
            property: "scale"
            from: 0
            to: Math.hypot(win.width, win.height) / 18
            duration: 650
            easing.type: Easing.InQuart
        }
        NumberAnimation {
            target: blackout
            property: "opacity"
            to: 1
            duration: 250
        }
        NumberAnimation {
            target: launchText
            property: "opacity"
            to: 1
            duration: 400
        }
        ScriptAction {
            script: win.elysium.launch(win.current)
        }
        PauseAnimation {
            duration: 1300
        }
        ScriptAction {
            script: {
                burst.scale = 0;
                blackout.opacity = 0;
                launchText.opacity = 0;
                win.launching = false;
            }
        }
    }

    component Glyph: Rectangle {
        property string letter
        property color tone: Colours.palette.m3onSurface

        width: 26
        height: 26
        radius: 13
        color: "transparent"
        border.width: 1.5
        border.color: tone

        StyledText {
            anchors.centerIn: parent
            text: parent.letter
            color: parent.tone
            font.pointSize: 9
            font.weight: Font.Bold
        }
    }

    component Hint: Row {
        property string letter
        property string label

        spacing: 10

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            letter: parent.letter
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: Colours.palette.m3onSurface
            font: Tokens.font.label.large
        }
    }

    component GlowArc: ShapePath {
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        PathAngleArc {
            centerX: limb.cx
            centerY: limb.cy
            radiusX: limb.rr
            radiusY: limb.rr
            startAngle: 200
            sweepAngle: 140
        }
    }
}
