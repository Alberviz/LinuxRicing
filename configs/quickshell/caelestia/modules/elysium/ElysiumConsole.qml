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
        ...(elysium.onTv ? [
                {
                    "system": "laptop",
                    "name": qsTr("Portátil"),
                    "subtitle": ({ "apoyo": qsTr("Pantalla de apoyo: métricas, Laura y avisos"), "escritorio": qsTr("Escritorio normal para trabajar"), "apagada": qsTr("Pantalla apagada, todo para la tele") })[elysium.companionMode],
                    "tag": qsTr("Pantalla del portátil · A para cambiar"),
                    "glyph": ({ "apoyo": "monitoring", "escritorio": "laptop_chromebook", "apagada": "desktop_access_disabled" })[elysium.companionMode]
                }
            ] : []),
        ...(elysium.tvScreen ? [
                {
                    "system": "screen",
                    "name": qsTr("Pantalla de juego"),
                    "subtitle": elysium.playOnTv ? qsTr("Jugando en la tele · A para jugar en el portátil") : qsTr("Jugando en el portátil · A para jugar en la tele"),
                    "tag": qsTr("Sistema"),
                    "glyph": elysium.playOnTv ? "tv" : "laptop"
                }
            ] : []),
        {
            "system": "laura",
            "name": "Laura",
            "subtitle": ({ "on": qsTr("Lista · A para apagarla y liberar la gráfica"), "off": qsTr("Apagada · A para encenderla (~%1 s)").arg(Math.round(LauraService.typicalStart)), "starting": qsTr("Encendiéndose…"), "stopping": qsTr("Apagándose…"), "error": qsTr("No arrancó · A para reintentar") })[LauraService.state] ?? "",
            "tag": qsTr("Asistente"),
            "glyph": LauraService.state === "off" ? "voice_over_off" : "graphic_eq"
        },
        {
            "system": "music",
            "name": qsTr("Música"),
            "subtitle": elysium.musicOn ? (elysium.userTracks.length ? qsTr("Sonando tu música (%1 pistas en ~/Música/Elysium) · A para quitarla").arg(elysium.userTracks.length) : qsTr("Sonando la música de Elysium · A para quitarla")) : qsTr("En silencio · A para poner música"),
            "tag": qsTr("Ambiente"),
            "glyph": elysium.musicOn ? "music_note" : "music_off"
        },
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
    readonly property var current: items[Math.min(index, items.length - 1)]
    readonly property bool isRunning: elysium.playing && current.proc !== undefined && elysium.runningGame?.proc === current.proc
    readonly property color accent: Colours.palette.m3primary

    function activate(): void {
        const it = current;
        if (it.system === "laptop")
            elysium.cycleCompanion();
        else if (it.system === "laura")
            LauraService.toggle();
        else if (it.system === "music")
            elysium.setMusic(!elysium.musicOn);
        else if (it.system === "screen")
            elysium.setPlayOnTv(!elysium.playOnTv);
        else if (it.system === "desktop")
            elysium.leave(false);
        else if (it.system === "gamemode")
            elysium.leave(true);
        else if (isRunning)
            elysium.summoned = false;
        else if (it.updates && elysium.updRunning) {
            elysium.updView = true;   // se está actualizando: enseñar el progreso
            elysium.sfx("dialog");
        } else if (it.updates && elysium.hsCheck.update) {
            elysium.updAskGame = it;
            elysium.updAsk = true;    // hay versión nueva: preguntar
            elysium.sfx("dialog");
        } else {
            elysium.sfx("launch");
            launchSeq.start();
        }
    }

    property bool confirmClose: false

    function pad(b: string): void {
        const E = elysium;
        if (launching)
            return;
        // Pantalla de progreso de la actualización: B = segundo plano, Y = cancelar.
        if (E.updView) {
            if (b === "b" || b === "home" || ((b === "a" || b === "start") && !E.updRunning)) {
                E.updView = false;
                E.sfx("back");
            } else if (b === "y" && E.updRunning) {
                E.hookshotCancel();
            }
            return;
        }
        // «Hay una versión nueva»: A actualiza, B juega con la actual, Y/Home más tarde.
        if (E.updAsk) {
            if (b === "a" || b === "start") {
                E.hookshotUpdate(false);
            } else if (b === "b") {
                E.updAsk = false;
                E.sfx("launch");
                launchSeq.start();
            } else if (b === "y" || b === "home") {
                E.updAsk = false;
                E.sfx("back");
            }
            return;
        }
        // Diálogo «¿Cerrar el juego?»: A cierra, B (o Y otra vez) cancela.
        if (confirmClose) {
            if (b === "a" || b === "start") {
                confirmClose = false;
                E.sfx("toggle_off");
                E.closeGame();
            } else if (b === "b" || b === "y" || b === "home") {
                confirmClose = false;
                E.sfx("back");
            }
            return;
        }
        if (b === "y") {
            if (isRunning) {
                confirmClose = true;
                E.sfx("dialog");
            }
            return;
        }
        // X en un juego: Laura sí/no en ese juego (se recuerda).
        if (b === "x") {
            if (current.proc) {
                const on = !E.lauraFor(current);
                E.setLauraFor(current, on);
                E.sfx(on ? "toggle_on" : "toggle_off");
            }
            return;
        }
        if (b === "left" || b === "right") {
            const next = Math.max(0, Math.min(items.length - 1, index + (b === "left" ? -1 : 1)));
            if (next !== index) {
                index = next;
                E.sfx("move");
            }
        } else if (b === "a" || b === "start") {
            if (current.system)
                E.sfx("select");
            activate();
        } else if (b === "b" || b === "home") {
            E.sfx("back");
            if (E.playing)
                E.summoned = false;
            else if (current.system === "desktop")
                E.leave(false);   // B dos veces = salir
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

    screen: elysium.consoleScreen
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
                [Qt.Key_Backspace]: "b",
                [Qt.Key_Y]: "y",
                [Qt.Key_Delete]: "y"
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
                visible: win.elysium.updRunning && !win.elysium.updView
                spacing: 8

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.elysium.upd.stage === "shaders" ? "deployed_code" : "downloading"
                    color: win.accent
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Hookshot %1 %").arg(Math.round((win.elysium.upd.pct ?? 0) * 100))
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.large
                }
            }

            LauraStatus {
                anchors.verticalCenter: parent.verticalCenter
                compact: true
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

            // Juego con actualizaciones: versión y estado.
            Row {
                visible: !!win.current.updates
                spacing: 10

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.elysium.updRunning ? "downloading" : win.elysium.hsChecking ? "sync" : win.elysium.hsCheck.update ? "system_update_alt" : "verified"
                    color: win.elysium.hsCheck.update || win.elysium.updRunning ? win.accent : Colours.palette.m3onSurfaceVariant
                    fill: 1
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.elysium.updRunning ? qsTr("Actualizando · %1 %  ·  A para ver el progreso").arg(Math.round((win.elysium.upd.pct ?? 0) * 100)) : win.elysium.hsChecking ? qsTr("Buscando actualizaciones…") : win.elysium.hsCheck.update ? qsTr("Nueva versión %1 disponible (tienes %2)").arg(win.elysium.hsCheck.latest).arg(win.elysium.hsCheck.current) : win.elysium.hsCheck.current ? qsTr("%1 · al día").arg(win.elysium.hsCheck.current) : ""
                    color: win.elysium.hsCheck.update || win.elysium.updRunning ? win.accent : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.large
                }
            }

            // Juego: Laura sí/no en este juego (X).
            Row {
                visible: !!win.current.proc
                spacing: 10

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.elysium.lauraFor(win.current) ? "graphic_eq" : "voice_over_off"
                    color: win.elysium.lauraFor(win.current) ? win.accent : Colours.palette.m3onSurfaceVariant
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.elysium.lauraFor(win.current) ? qsTr("Laura activa en este juego") : qsTr("Laura apagada en este juego (más gráfica para el juego)")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.large
                }

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    letter: "X"
                    tone: Colours.palette.m3onSurfaceVariant
                }
            }

            // Tarjeta Laura: estado con fases y progreso.
            LauraStatus {
                visible: win.current.system === "laura"
                barWidth: win.width * 0.32
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
                        text: win.current.updates && win.elysium.updRunning && !win.isRunning ? qsTr("Ver progreso") : win.current.updates && win.elysium.hsCheck.update && !win.isRunning ? qsTr("Jugar o actualizar") : win.current.system === "laptop" || win.current.system === "screen" ? qsTr("Cambiar") : win.current.system === "laura" ? (LauraService.on || LauraService.state === "starting" ? qsTr("Apagar") : qsTr("Encender")) : win.current.system === "music" ? (win.elysium.musicOn ? qsTr("Silenciar") : qsTr("Poner música")) : win.current.system === "desktop" ? qsTr("Salir") : win.current.system === "gamemode" ? qsTr("Ir al escritorio") : win.isRunning ? qsTr("Volver al juego") : qsTr("Jugar")
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

                        // Progreso de la actualización sobre la carátula.
                        Shape {
                            anchors.centerIn: parent
                            width: parent.width * 0.5
                            height: width
                            visible: !!slot.modelData.updates && win.elysium.updRunning
                            preferredRendererType: Shape.CurveRenderer

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + 14
                                height: width
                                radius: width / 2
                                color: Qt.rgba(0, 0, 0, 0.55)
                                z: -1
                            }

                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: win.accent
                                strokeWidth: 4
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: face.width * 0.25
                                    centerY: face.width * 0.25
                                    radiusX: face.width * 0.25 - 4
                                    radiusY: face.width * 0.25 - 4
                                    startAngle: -90
                                    sweepAngle: Math.max(1, 360 * (win.elysium.upd.pct ?? 0))
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: Math.round((win.elysium.upd.pct ?? 0) * 100) + "%"
                                color: "white"
                                font: Tokens.font.title.small
                            }
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
                visible: win.isRunning
                letter: "Y"
                label: qsTr("Cerrar juego")
            }

            Hint {
                visible: !!win.current.proc
                letter: "X"
                label: qsTr("Laura en este juego")
            }

            Hint {
                letter: "−"
                label: qsTr("Mantener: Laura")
            }
        }

        // --- diálogo «¿Cerrar el juego?» ---
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.6)
            opacity: win.confirmClose ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: win.confirmClose = false
            }

            Rectangle {
                anchors.centerIn: parent
                width: 560
                height: dlg.implicitHeight + 72
                radius: 28
                color: Colours.palette.m3surfaceContainer
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3error, 0.45)
                scale: win.confirmClose ? 1 : 0.92

                Behavior on scale {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.4
                    }
                }

                Column {
                    id: dlg

                    anchors.centerIn: parent
                    width: parent.width - 72
                    spacing: 14

                    MaterialIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "power_settings_new"
                        color: Colours.palette.m3error
                        fill: 1
                        fontStyle: Tokens.font.icon.builders.medium.scale(1.8).build()
                    }

                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("¿Cerrar %1?").arg(win.elysium.runningGame?.subtitle?.split(" · ")[0] ?? qsTr("el juego"))
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.title.large
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Lo que no hayas guardado se perderá.")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                    }

                    Item {
                        width: 1
                        height: 10
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 16

                        Rectangle {
                            implicitHeight: 52
                            implicitWidth: closeRow.implicitWidth + 40
                            radius: 26
                            color: Colours.palette.m3error

                            Row {
                                id: closeRow

                                anchors.centerIn: parent
                                spacing: 12

                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    letter: "A"
                                    tone: Colours.palette.m3onError
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Cerrar juego")
                                    color: Colours.palette.m3onError
                                    font: Tokens.font.title.medium
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.pad("a")
                            }
                        }

                        Rectangle {
                            implicitHeight: 52
                            implicitWidth: cancelRow.implicitWidth + 40
                            radius: 26
                            color: Qt.alpha(Colours.palette.m3onSurface, 0.08)

                            Row {
                                id: cancelRow

                                anchors.centerIn: parent
                                spacing: 12

                                Glyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    letter: "B"
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: qsTr("Cancelar")
                                    color: Colours.palette.m3onSurface
                                    font: Tokens.font.title.medium
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.pad("b")
                            }
                        }
                    }
                }
            }
        }

        // --- actualización de Hookshot: diálogo y progreso ---
        UpdateDialog {
            anchors.fill: parent
            elysium: win.elysium
        }

        UpdateView {
            anchors.fill: parent
            elysium: win.elysium
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

            StyledText {
                id: launchSub

                anchors.top: launchText.bottom
                anchors.topMargin: 18
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.elysium.onTv ? qsTr("Abriendo en la tele…") : qsTr("Abriendo…")
                color: "white"
                opacity: 0
                font: Tokens.font.title.small
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
        NumberAnimation {
            target: launchSub
            property: "opacity"
            to: 0.7
            duration: 300
        }
        ScriptAction {
            script: win.elysium.launch(win.current)
        }
        // La pantalla de carga se queda hasta que la ventana del juego está en su sitio.
    }

    function resetLaunch(): void {
        launchSeq.stop();
        burst.scale = 0;
        blackout.opacity = 0;
        launchText.opacity = 0;
        launchSub.opacity = 0;
        launching = false;
    }

    Connections {
        target: win.elysium

        function onGameReadyChanged(): void {
            if (win.elysium.gameReady && win.launching)
                fadeOut.start();
        }

        function onConsoleShownChanged(): void {
            win.confirmClose = false;
        }

        function onActiveChanged(): void {
            if (!win.elysium.active)
                win.resetLaunch();
        }
    }

    SequentialAnimation {
        id: fadeOut

        NumberAnimation {
            target: blackout
            property: "opacity"
            to: 0
            duration: 300
        }
        ScriptAction {
            script: win.resetLaunch()
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
