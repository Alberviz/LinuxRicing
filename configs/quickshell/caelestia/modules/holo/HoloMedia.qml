pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Visor multimedia holográfico (vídeo o audio).
// Para vídeo: MediaPlayer + VideoOutput, mostrando el póster al inicio en pausa.
// Para audio: MediaPlayer + AudioOutput con una barra de onda estilizada.
// Clic en el área conmuta reproducción/pausa. Barra de progreso fina en m3primary.
// Detiene la reproducción de forma limpia al destruirse el componente.
Item {
    id: root

    required property var panel

    readonly property var payload: panel && panel.payload ? panel.payload : ({})
    readonly property bool isAudio: (root.payload && root.payload.tipo === "audio")
    readonly property bool isVideo: !isAudio

    readonly property string mediaSrc: {
        const s = (root.payload && root.payload.src) ? root.payload.src : "";
        if (!s)
            return "";
        return s.startsWith("file://") ? s : ("file://" + s);
    }

    readonly property string posterSrc: {
        const s = (root.payload && root.payload.poster) ? root.payload.poster : "";
        if (!s)
            return "";
        return s.startsWith("file://") ? s : ("file://" + s);
    }

    MediaPlayer {
        id: player
        source: root.mediaSrc
        audioOutput: AudioOutput {
            id: audioOut
            volume: 1.0
        }
        videoOutput: root.isVideo ? videoOut : null
    }

    Component.onDestruction: {
        player.stop();
    }

    // Superficie de vídeo
    VideoOutput {
        id: videoOut
        anchors.fill: parent
        anchors.bottomMargin: 26
        visible: root.isVideo
        fillMode: VideoOutput.PreserveAspectFit
    }

    // Póster inicial de vídeo cuando está en pausa
    Image {
        id: posterImg
        anchors.fill: videoOut
        visible: root.isVideo && root.posterSrc.length > 0 && player.playbackState !== MediaPlayer.PlayingState && player.position === 0
        source: root.posterSrc
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }

    // Vista de audio con barra de onda falsa estilizada
    Item {
        id: audioContainer
        anchors.fill: parent
        anchors.bottomMargin: 26
        visible: root.isAudio

        Column {
            anchors.centerIn: parent
            spacing: 14

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "graphic_eq"
                fontStyle: Tokens.font.icon.size(38).build()
                color: Colours.palette.m3tertiary
            }

            // Barra de ondas falsa estática
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 3

                Repeater {
                    model: [8, 14, 22, 12, 28, 36, 18, 24, 32, 40, 26, 16, 30, 42, 34, 20, 28, 38, 22, 14, 26, 18, 10, 6]

                    Rectangle {
                        id: waveBar
                        required property int modelData
                        required property int index

                        readonly property real progress: player.duration > 0 ? (player.position / player.duration) : 0
                        readonly property bool active: (waveBar.index / 24.0) <= waveBar.progress

                        width: 3
                        height: waveBar.modelData
                        radius: 1.5
                        color: waveBar.active ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3primary, 0.35)
                    }
                }
            }
        }
    }

    // Indicador circular flotante de play/pausa
    Rectangle {
        id: playOverlay
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.isAudio ? 40 : -13
        width: 44
        height: 44
        radius: 22
        color: Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.72)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3primary, 0.5)
        opacity: (player.playbackState === MediaPlayer.PlayingState && !clickArea.containsMouse) ? 0.0 : 1.0

        scale: clickArea.pressed ? 0.92 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: HoloGeo.tRapido
                easing.type: HoloGeo.curvaFundido
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: HoloGeo.tMicro
                easing.type: HoloGeo.curvaEntra
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: (player.playbackState === MediaPlayer.PlayingState) ? "pause" : "play_arrow"
            fontStyle: Tokens.font.icon.medium
            color: Colours.palette.m3primary
        }
    }

    // Clic en toda el área superior para conmutar reproducción/pausa
    MouseArea {
        id: clickArea
        anchors.fill: parent
        anchors.bottomMargin: 26
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (player.playbackState === MediaPlayer.PlayingState) {
                player.pause();
            } else {
                player.play();
            }
        }
    }

    // Barra de progreso fina m3primary y tiempo
    Item {
        id: progressArea
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 26

        Rectangle {
            id: track
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            height: 3
            radius: 1.5
            color: Qt.alpha(Colours.palette.m3onSurface, 0.22)

            Rectangle {
                id: fill
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: (player.duration > 0) ? (parent.width * Math.max(0, Math.min(1.0, player.position / player.duration))) : 0
                color: Colours.palette.m3primary
                radius: 1.5
            }
        }

        Text {
            anchors.right: track.right
            anchors.bottom: track.top
            anchors.bottomMargin: 2
            text: root.fmtTime(player.position) + " / " + root.fmtTime(player.duration)
            color: Colours.palette.m3onSurfaceVariant
            font.family: Tokens.font.label.small.family
            font.pixelSize: 10
        }

        MouseArea {
            anchors.fill: track
            anchors.margins: -4
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => {
                if (player.duration > 0 && track.width > 0) {
                    const pos = Math.max(0, Math.min(1.0, mouse.x / track.width));
                    player.position = Math.floor(pos * player.duration);
                }
            }
        }
    }

    function fmtTime(ms: real): string {
        if (!ms || ms < 0)
            return "0:00";
        const s = Math.floor(ms / 1000);
        const m = Math.floor(s / 60);
        const sec = s % 60;
        return m + ":" + (sec < 10 ? "0" : "") + sec;
    }
}
