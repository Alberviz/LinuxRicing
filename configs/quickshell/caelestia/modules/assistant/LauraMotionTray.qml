pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Bandeja cinemática superior que se expande dentro de la píldora de Laura
// para mostrar feedback instantáneo de acciones de sistema (Zero-Latency).
Item {
    id: root

    readonly property var motion: Laura.activeMotion
    readonly property bool active: motion !== null

    implicitHeight: active ? 96 : 0
    implicitWidth: 480
    clip: true

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 380
            easing.type: Easing.OutCubic
        }
    }

    opacity: active ? 1 : 0
    Behavior on opacity {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutQuad
        }
    }

    // Identificador para re-disparar animaciones cuando cambie la orden
    property int motionCounter: 0
    onMotionChanged: {
        if (motion)
            motionCounter++;
    }

    // -------------------------------------------------------------
    // 1. SLIDE DE CANCIÓN (Next / Prev)
    // -------------------------------------------------------------
    Item {
        id: trackSlideWrap
        anchors.fill: parent
        visible: root.motion?.tipo === "track_slide"

        property real progress: 0
        readonly property string dir: root.motion?.direccion ?? "next"
        readonly property string prevTitle: root.motion?.prev_title ?? "Pista anterior"
        readonly property string prevArtist: root.motion?.prev_artist ?? ""
        readonly property string nextTitle: root.motion?.next_title ?? "Siguiente pista"
        readonly property string nextArtist: root.motion?.next_artist ?? ""
        readonly property string artUrl: root.motion?.art ?? ""

        Connections {
            target: root
            function onMotionCounterChanged(): void {
                if (root.motion?.tipo === "track_slide") {
                    trackSlideWrap.progress = 0;
                    slideAnim.restart();
                }
            }
        }

        NumberAnimation {
            id: slideAnim
            target: trackSlideWrap
            property: "progress"
            from: 0
            to: 1
            duration: 480
            easing.type: Easing.OutCubic
        }

        // Pista saliente (Slide out)
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 48
            height: 64
            x: 24 + (trackSlideWrap.dir === "next" ? -trackSlideWrap.progress * (width + 40) : trackSlideWrap.progress * (width + 40))
            opacity: Math.max(0, 1 - trackSlideWrap.progress * 1.4)

            Row {
                anchors.fill: parent
                spacing: 16
                anchors.verticalCenter: parent.verticalCenter

                // Carátula / Vinilo procedimental
                Rectangle {
                    width: 58
                    height: 58
                    radius: 12
                    color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.9)
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3onSurface, 0.12)
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter

                    // Anillos de vinilo
                    Rectangle {
                        anchors.centerIn: parent
                        width: 44
                        height: 44
                        radius: 22
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.1)
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        radius: 14
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.15)
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 6
                        color: Colours.palette.m3primary
                    }

                    Image {
                        anchors.fill: parent
                        source: trackSlideWrap.artUrl
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 74
                    spacing: 2

                    Row {
                        spacing: 6
                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            color: Colours.palette.m3primary
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: "SPOTIFY"
                            color: Colours.palette.m3primary
                            font.family: "JetBrains Mono, monospace"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 1.1
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: trackSlideWrap.prevTitle
                        color: Colours.palette.m3onSurface
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: trackSlideWrap.prevArtist
                        color: Colours.palette.m3onSurfaceVariant
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }
                }
            }
        }

        // Pista entrante (Slide in)
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 48
            height: 64
            x: 24 + (trackSlideWrap.dir === "next" ? (1 - trackSlideWrap.progress) * (width + 40) : -(1 - trackSlideWrap.progress) * (width + 40))
            opacity: Math.min(1, trackSlideWrap.progress * 1.5)

            Row {
                anchors.fill: parent
                spacing: 16
                anchors.verticalCenter: parent.verticalCenter

                // Carátula / Vinilo entrante
                Rectangle {
                    width: 58
                    height: 58
                    radius: 12
                    color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.9)
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3primary, 0.35)
                    clip: true
                    anchors.verticalCenter: parent.verticalCenter

                    // Anillos de vinilo
                    Rectangle {
                        anchors.centerIn: parent
                        width: 44
                        height: 44
                        radius: 22
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3primary, 0.2)
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        radius: 14
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3primary, 0.25)
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 6
                        color: Colours.palette.m3primary
                    }

                    Image {
                        anchors.fill: parent
                        source: trackSlideWrap.artUrl
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 74
                    spacing: 2

                    Row {
                        spacing: 6
                        MaterialIcon {
                            text: trackSlideWrap.dir === "next" ? "skip_next" : "skip_previous"
                            color: Colours.palette.m3primary
                            fontStyle: Tokens.font.icon.small
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        StyledText {
                            text: trackSlideWrap.dir === "next" ? "SIGUIENTE PISTA" : "PISTA ANTERIOR"
                            color: Colours.palette.m3primary
                            font.family: "JetBrains Mono, monospace"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 1.1
                        }
                    }

                    StyledText {
                        width: parent.width
                        text: trackSlideWrap.nextTitle
                        color: Colours.palette.m3onSurface
                        font.pixelSize: 17
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: trackSlideWrap.nextArtist
                        color: Colours.palette.m3tertiary
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        visible: text.length > 0
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------
    // 2. PAUSA / PLAY CINÉTICO («PUM» CON ANILLO DE IMPACTO)
    // -------------------------------------------------------------
    Item {
        id: playbackWrap
        anchors.fill: parent
        visible: root.motion?.tipo === "playback_impact"

        property real impactAnim: 0
        readonly property bool isPause: root.motion?.estado === "pause"
        readonly property string songTitle: root.motion?.titulo ?? "Música"
        readonly property string songArtist: root.motion?.artista ?? ""

        Connections {
            target: root
            function onMotionCounterChanged(): void {
                if (root.motion?.tipo === "playback_impact") {
                    playbackWrap.impactAnim = 0;
                    impactTimer.restart();
                }
            }
        }

        NumberAnimation {
            id: impactTimer
            target: playbackWrap
            property: "impactAnim"
            from: 0
            to: 1
            duration: 450
            easing.type: Easing.OutBack
        }

        Row {
            anchors.centerIn: parent
            spacing: 20

            // Icono central con choque expansivo
            Item {
                width: 56
                height: 56
                anchors.verticalCenter: parent.verticalCenter

                // Onda expansiva de impacto
                Rectangle {
                    anchors.centerIn: parent
                    width: 54 * (0.8 + playbackWrap.impactAnim * 1.5)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Colours.palette.m3primary
                    opacity: Math.max(0, (1 - playbackWrap.impactAnim) * 0.85)
                }

                // Círculo del botón que brota con "pum"
                Rectangle {
                    anchors.centerIn: parent
                    width: 52
                    height: 52
                    radius: 26
                    scale: 0.6 + playbackWrap.impactAnim * 0.4
                    color: playbackWrap.isPause ? Colours.palette.m3surfaceContainerHigh : Colours.palette.m3primary
                    border.width: 1
                    border.color: Qt.alpha(Colours.palette.m3primary, 0.4)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: playbackWrap.isPause ? "pause" : "play_arrow"
                        color: playbackWrap.isPause ? Colours.palette.m3onSurface : Colours.palette.m3onPrimary
                        fontStyle: Tokens.font.icon.medium
                    }
                }
            }

            // Metadatos
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3

                StyledText {
                    text: playbackWrap.isPause ? "PAUSADO" : "REANUDANDO"
                    color: Colours.palette.m3onSurface
                    font.pixelSize: 18
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                }

                StyledText {
                    text: playbackWrap.songTitle + (playbackWrap.songArtist.length > 0 ? " · " + playbackWrap.songArtist : "")
                    color: Colours.palette.m3onSurfaceVariant
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }

    // -------------------------------------------------------------
    // 3. MEDIDOR EN DELTA CON INERCIA (Volumen / Brillo)
    // -------------------------------------------------------------
    Item {
        id: deltaWrap
        anchors.fill: parent
        visible: root.motion?.tipo === "delta_meter"

        property real animatedVal: root.motion ? (root.motion.from ?? 0) : 0
        readonly property bool isVol: root.motion?.medidor === "volumen"
        readonly property real fromPct: root.motion ? (root.motion.from ?? 0) : 0
        readonly property real toPct: root.motion ? (root.motion.to ?? 0) : 0
        readonly property bool isMuted: root.motion?.silenciado ?? false

        Connections {
            target: root
            function onMotionCounterChanged(): void {
                if (root.motion?.tipo === "delta_meter") {
                    deltaAnim.stop();
                    deltaWrap.animatedVal = deltaWrap.fromPct;
                    deltaAnim.from = deltaWrap.fromPct;
                    deltaAnim.to = deltaWrap.toPct;
                    deltaAnim.restart();
                }
            }
        }

        NumberAnimation {
            id: deltaAnim
            target: deltaWrap
            property: "animatedVal"
            duration: 600
            easing.type: Easing.OutCubic
        }

        Column {
            anchors.centerIn: parent
            width: parent.width - 56
            spacing: 10

            // Fila superior: icono, título y números en vivo
            Item {
                width: parent.width
                height: 26

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    MaterialIcon {
                        text: deltaWrap.isVol ? (deltaWrap.isMuted ? "volume_off" : (deltaWrap.toPct < deltaWrap.fromPct ? "volume_down" : "volume_up")) : "brightness_6"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: deltaWrap.isVol ? "VOLUMEN" : "BRILLO"
                        color: Colours.palette.m3onSurfaceVariant
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    spacing: 8

                    StyledText {
                        text: Math.round(deltaWrap.fromPct) + "%"
                        color: Colours.palette.m3onSurfaceVariant
                        font.family: "JetBrains Mono, monospace"
                        font.pixelSize: 13
                        font.strikeout: true
                        opacity: 0.55
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                    }

                    StyledText {
                        text: "→"
                        color: Colours.palette.m3onSurfaceVariant
                        font.pixelSize: 13
                        opacity: 0.5
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                    }

                    StyledText {
                        text: Math.round(deltaWrap.animatedVal) + "%"
                        color: Colours.palette.m3primary
                        font.family: "JetBrains Mono, monospace"
                        font.pixelSize: 22
                        font.weight: Font.Bold
                        anchors.bottom: parent.bottom
                    }
                }
            }

            // Pista de la barra con marca fantasma del valor previo
            Item {
                width: parent.width
                height: 10

                // Fondo de la barra
                Rectangle {
                    anchors.fill: parent
                    radius: 5
                    color: Qt.alpha(Colours.palette.m3onSurface, 0.12)
                }

                // Marca fantasma del valor previo
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: (parent.width * Math.min(100, Math.max(0, deltaWrap.fromPct))) / 100
                    radius: 5
                    color: Qt.alpha(Colours.palette.m3onSurface, 0.14)
                }

                // Barra de llenado fluido con inercia
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.max(8, (parent.width * Math.min(100, Math.max(0, deltaWrap.animatedVal))) / 100)
                    radius: 5

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: Colours.palette.m3primary
                        }
                        GradientStop {
                            position: 1
                            color: Colours.palette.m3tertiary
                        }
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------
    // 4. ACCIÓN DE SISTEMA (Captura, Bloqueo, etc.)
    // -------------------------------------------------------------
    Item {
        id: sysActionWrap
        anchors.fill: parent
        visible: root.motion?.tipo === "system_action"

        property real pulseScale: 0
        readonly property string iconName: root.motion?.icono ?? "bolt"
        readonly property string actionTitle: root.motion?.titulo ?? "Acción ejecutada"

        Connections {
            target: root
            function onMotionCounterChanged(): void {
                if (root.motion?.tipo === "system_action") {
                    sysActionWrap.pulseScale = 0;
                    pulseTimer.restart();
                }
            }
        }

        NumberAnimation {
            id: pulseTimer
            target: sysActionWrap
            property: "pulseScale"
            from: 0
            to: 1
            duration: 400
            easing.type: Easing.OutBack
        }

        Row {
            anchors.centerIn: parent
            spacing: 16

            Rectangle {
                width: 48
                height: 48
                radius: 24
                scale: 0.7 + sysActionWrap.pulseScale * 0.3
                color: Qt.alpha(Colours.palette.m3primary, 0.2)
                border.width: 1
                border.color: Colours.palette.m3primary

                MaterialIcon {
                    anchors.centerIn: parent
                    text: sysActionWrap.iconName
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.medium
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                StyledText {
                    text: sysActionWrap.actionTitle
                    color: Colours.palette.m3onSurface
                    font.pixelSize: 17
                    font.weight: Font.Bold
                }

                StyledText {
                    text: "Ejecutado al instante"
                    color: Colours.palette.m3onSurfaceVariant
                    font.pixelSize: 13
                }
            }
        }
    }

    // Línea divisoria inferior suave hacia el contenido base de la píldora
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        height: 1
        color: Qt.alpha(Colours.palette.m3onSurface, 0.08)
        visible: root.implicitHeight > 10
    }
}
