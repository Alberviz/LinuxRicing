pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Feedback de acciones rápidas dentro de la píldora de Laura (sin voz):
// track_slide · playback_impact · delta_meter · system_action.
// Sin bucles infinitos: todo son animaciones de un disparo, salvo el ecualizador,
// que solo corre mientras la bandeja está abierta y la música suena.
Item {
    id: root

    // se queda con la última orden mientras se repliega (si no, el contenido se vacía a mitad)
    property var motion: null
    readonly property bool active: Laura.activeMotion !== null
    readonly property string tipo: motion?.tipo ?? ""
    readonly property color acc: Colours.palette.m3primary
    property int shot: 0

    Connections {
        target: Laura
        function onActiveMotionChanged(): void {
            if (!Laura.activeMotion)
                return;
            root.motion = Laura.activeMotion;
            root.shot++;
        }
    }

    implicitHeight: active ? 84 : 0
    clip: true
    opacity: active ? 1 : 0
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 420
            easing.type: Easing.OutExpo
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 220
        }
    }

    // ---------- piezas comunes ----------
    component Tile: Rectangle {
        width: 56
        height: 56
        radius: 16
        color: Qt.alpha(root.acc, 0.14)
        border.width: 1
        border.color: Qt.alpha(root.acc, 0.22)
        clip: true
    }
    component Cover: Tile {
        id: cv
        property string src: ""
        property bool fallback: true
        MaterialIcon {
            anchors.centerIn: parent
            visible: cv.fallback && img.status !== Image.Ready
            text: "music_note"
            color: root.acc
            fontStyle: Tokens.font.icon.large
        }
        Image {
            id: img
            anchors.fill: parent
            source: cv.src
            asynchronous: true
            sourceSize: Qt.size(112, 112)
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
        }
    }
    component Overline: Row {
        property string icon
        property string text
        spacing: 6
        MaterialIcon {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.icon
            color: root.acc
            fill: 1
            fontStyle: Tokens.font.icon.small
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.text.toUpperCase()
            color: root.acc
            font.pointSize: 8.5
            font.weight: Font.DemiBold
            font.letterSpacing: 1.4
        }
    }
    component Title: StyledText {
        width: parent.width
        elide: Text.ElideRight
        color: Colours.palette.m3onSurface
        font.pointSize: 13
        font.weight: Font.DemiBold
    }
    component Sub: StyledText {
        width: parent.width
        elide: Text.ElideRight
        visible: text.length > 0
        color: Colours.palette.m3onSurfaceVariant
        font.pointSize: 10
    }

    Item {
        id: stage
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 18
        anchors.topMargin: 14
        anchors.bottomMargin: 14

        // ---------- 1. siguiente / anterior: la pista vieja se va, la nueva entra ----------
        Item {
            id: slide
            anchors.fill: parent
            visible: root.tipo === "track_slide"
            readonly property real sgn: root.motion?.direccion === "prev" ? -1 : 1
            property real t: 1

            Connections {
                target: root
                function onShotChanged(): void {
                    if (root.tipo === "track_slide")
                        slideAnim.restart();
                }
            }
            NumberAnimation {
                id: slideAnim
                target: slide
                property: "t"
                from: 0
                to: 1
                duration: 620
                easing.type: Easing.OutQuint
            }

            Repeater {
                model: 2 // 0 = saliente, 1 = entrante
                Item {
                    id: card
                    required property int index
                    readonly property bool inn: index === 1
                    readonly property real k: inn ? 1 - slide.t : -slide.t
                    width: slide.width
                    height: slide.height
                    x: k * 70 * slide.sgn
                    opacity: inn ? Math.min(1, slide.t * 1.6) : Math.max(0, 1 - slide.t * 2.2)
                    scale: inn ? 0.94 + 0.06 * slide.t : 1 - 0.06 * slide.t

                    Cover {
                        id: cov
                        anchors.verticalCenter: parent.verticalCenter
                        src: card.inn ? (root.motion?.art ?? "") : (root.motion?.prev_art ?? root.motion?.art ?? "")
                    }
                    Column {
                        anchors.left: cov.right
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Overline {
                            icon: slide.sgn > 0 ? "skip_next" : "skip_previous"
                            text: slide.sgn > 0 ? "Siguiente" : "Anterior"
                        }
                        Title {
                            text: card.inn ? (root.motion?.next_title ?? "") : (root.motion?.prev_title ?? "")
                        }
                        Sub {
                            text: card.inn ? (root.motion?.next_artist ?? "") : (root.motion?.prev_artist ?? "")
                        }
                    }
                }
            }
        }

        // ---------- 2. pausa / play: golpe en la carátula + onda ----------
        Item {
            id: play
            anchors.fill: parent
            visible: root.tipo === "playback_impact"
            readonly property bool paused: root.motion?.estado === "pause"
            property real t: 1

            Connections {
                target: root
                function onShotChanged(): void {
                    if (root.tipo === "playback_impact")
                        playAnim.restart();
                }
            }
            NumberAnimation {
                id: playAnim
                target: play
                property: "t"
                from: 0
                to: 1
                duration: 700
                easing.type: Easing.OutCubic
            }

            Item {
                id: coverBox
                width: 56
                height: 56
                anchors.verticalCenter: parent.verticalCenter

                // onda expansiva
                Rectangle {
                    anchors.centerIn: parent
                    width: 56
                    height: 56
                    radius: 18
                    color: "transparent"
                    border.width: 2
                    border.color: root.acc
                    scale: 1 + play.t * 0.55
                    opacity: (1 - play.t) * 0.8
                }
                Cover {
                    id: pc
                    src: root.motion?.art ?? ""
                    fallback: false
                    scale: play.t < 0.18 ? 1 - play.t * 0.4 : 0.93 + 0.07 * Math.min(1, (play.t - 0.18) / 0.5)
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.alpha(Colours.palette.m3surface, play.paused ? 0.55 : 0.25)
                        Behavior on color {
                            ColorAnimation {
                                duration: 300
                            }
                        }
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        text: play.paused ? "pause" : "play_arrow"
                        color: Colours.palette.m3onSurface
                        fill: 1
                        fontStyle: Tokens.font.icon.large
                        scale: 1.7 - 0.7 * Math.min(1, play.t * 1.8)
                        opacity: Math.min(1, play.t * 4)
                    }
                }
            }
            Column {
                anchors.left: coverBox.right
                anchors.leftMargin: 14
                anchors.right: eq.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Overline {
                    icon: play.paused ? "pause_circle" : "play_circle"
                    text: play.paused ? "En pausa" : "Reproduciendo"
                }
                Title {
                    text: root.motion?.titulo ?? ""
                }
                Sub {
                    text: root.motion?.artista ?? ""
                }
            }
            // ecualizador: baila sonando, se aplana en pausa
            Row {
                id: eq
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 22
                spacing: 3
                Repeater {
                    model: 4
                    Rectangle {
                        id: bar
                        required property int index
                        property real lv: 0.3
                        width: 3
                        radius: 1.5
                        height: Math.max(3, 22 * (play.paused ? 0.14 : lv))
                        anchors.bottom: parent.bottom
                        color: root.acc
                        opacity: play.paused ? 0.45 : 1
                        Behavior on height {
                            NumberAnimation {
                                duration: 260
                                easing.type: Easing.OutCubic
                            }
                        }
                        Timer {
                            interval: 170 + bar.index * 37
                            repeat: true
                            running: play.visible && root.active && !play.paused
                            onTriggered: bar.lv = 0.25 + Math.random() * 0.75
                        }
                    }
                }
            }
        }

        // ---------- 3. volumen / brillo: barra que se llena desde la marca anterior ----------
        Item {
            id: meter
            anchors.fill: parent
            visible: root.tipo === "delta_meter"
            readonly property bool vol: root.motion?.medidor === "volumen"
            readonly property bool muted: root.motion?.silenciado ?? false
            readonly property real from: root.motion?.from ?? 0
            readonly property real to: root.motion?.to ?? 0
            property real v: 0

            Connections {
                target: root
                function onShotChanged(): void {
                    if (root.tipo !== "delta_meter")
                        return;
                    meterAnim.stop();
                    meterAnim.from = root.motion.from ?? 0;
                    meterAnim.to = root.motion.to ?? 0;
                    meterAnim.restart();
                }
            }
            NumberAnimation {
                id: meterAnim
                target: meter
                property: "v"
                duration: 650
                easing.type: Easing.OutExpo
            }

            Tile {
                id: mt
                anchors.verticalCenter: parent.verticalCenter
                MaterialIcon {
                    anchors.centerIn: parent
                    color: root.acc
                    fill: 1
                    fontStyle: Tokens.font.icon.large
                    text: meter.vol ? (meter.muted ? "volume_off" : meter.v < 34 ? "volume_mute" : meter.v < 67 ? "volume_down" : "volume_up") : (meter.v < 34 ? "brightness_low" : meter.v < 67 ? "brightness_medium" : "brightness_high")
                    scale: meterAnim.running ? 1.08 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.OutBack
                        }
                    }
                }
            }
            Column {
                anchors.left: mt.right
                anchors.leftMargin: 14
                anchors.right: num.left
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9
                Overline {
                    icon: meter.to >= meter.from ? "arrow_upward" : "arrow_downward"
                    text: meter.vol ? (meter.muted ? "Silenciado" : "Volumen") : "Brillo"
                }
                Item {
                    id: track
                    width: parent.width
                    height: 8
                    readonly property real scaleMax: meter.vol ? Math.max(100, meter.from, meter.to) : 100
                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: Qt.alpha(Colours.palette.m3onSurface, 0.1)
                    }
                    Rectangle {
                        height: parent.height
                        radius: 4
                        width: Math.max(height, parent.width * Math.min(1, meter.v / track.scaleMax))
                        color: root.acc
                    }
                    // marca de dónde estaba
                    Rectangle {
                        width: 2
                        height: 14
                        radius: 1
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.min(parent.width - 2, parent.width * meter.from / track.scaleMax)
                        color: Colours.palette.m3onSurface
                        opacity: Math.abs(meter.v - meter.from) > 1 ? 0.55 : 0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 200
                            }
                        }
                    }
                }
            }
            Row {
                id: num
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                StyledText {
                    text: Math.round(meter.v)
                    color: Colours.palette.m3onSurface
                    font.pointSize: 22
                    font.weight: Font.DemiBold
                    font.features: {
                        "tnum": 1
                    }
                }
                StyledText {
                    anchors.baseline: parent.children[0].baseline
                    text: "%"
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: 11
                }
            }
        }

        // ---------- 4. acciones del sistema: icono que aterriza ----------
        Item {
            id: sys
            anchors.fill: parent
            visible: root.tipo === "system_action"
            property real t: 1

            Connections {
                target: root
                function onShotChanged(): void {
                    if (root.tipo === "system_action")
                        sysAnim.restart();
                }
            }
            NumberAnimation {
                id: sysAnim
                target: sys
                property: "t"
                from: 0
                to: 1
                duration: 600
                easing.type: Easing.OutBack
                easing.overshoot: 2.2
            }

            Tile {
                id: st
                anchors.verticalCenter: parent.verticalCenter
                scale: 0.6 + 0.4 * sys.t
                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.motion?.icono ?? "bolt"
                    color: root.acc
                    fill: 1
                    fontStyle: Tokens.font.icon.large
                }
            }
            Column {
                anchors.left: st.right
                anchors.leftMargin: 14
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                opacity: Math.min(1, sys.t)
                Overline {
                    icon: "check_circle"
                    text: "Hecho"
                }
                Title {
                    text: root.motion?.titulo ?? ""
                }
            }
        }
    }
}
