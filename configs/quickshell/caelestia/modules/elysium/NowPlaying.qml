pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Componente reutilizable «Ahora suena» para Elysium (Companion, HUD y otros).
ColumnLayout {
    id: root

    required property var elysium
    property bool compact: false
    property bool showHints: false
    property bool showControls: false
    property bool showDevice: false

    readonly property color accent: Colours.palette.m3primary
    readonly property int artSize: compact ? 64 : 108
    readonly property real pos: elysium.trackPosition
    readonly property real len: elysium.trackLength
    readonly property real frac: len > 0 ? Math.max(0, Math.min(1, pos / len)) : 0

    function fmtTime(sec: real): string {
        if (sec < 0 || !isFinite(sec))
            return "0:00";
        const s = Math.floor(sec);
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const r = (s % 60).toString().padStart(2, "0");
        return h > 0 ? `${h}:${m.toString().padStart(2, "0")}:${r}` : `${m}:${r}`;
    }

    spacing: compact ? 10 : 12

    RowLayout {
        Layout.fillWidth: true
        spacing: root.compact ? 14 : 18

        // Carátula redondeada o disco dibujado si no hay carátula.
        StyledClippingRect {
            Layout.preferredWidth: root.artSize
            Layout.preferredHeight: root.artSize
            radius: root.compact ? 14 : 18
            color: Qt.alpha(Colours.palette.m3onSurface, 0.06)

            Image {
                id: coverImg

                anchors.fill: parent
                source: root.elysium.trackArtUrl
                sourceSize.width: root.artSize * 2
                sourceSize.height: root.artSize * 2
                fillMode: Image.PreserveAspectCrop
                smooth: true
                mipmap: true
                asynchronous: true
                visible: status === Image.Ready
            }

            // Disco dibujado (círculos concéntricos con el acento).
            Item {
                anchors.fill: parent
                visible: coverImg.status !== Image.Ready

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.82
                    height: width
                    radius: width / 2
                    color: Qt.tint("#0a0c14", Qt.alpha(root.accent, 0.14))
                    border.width: 1.5
                    border.color: Qt.alpha(root.accent, 0.45)

                    // Surcos concéntricos.
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.72
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.12)
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.50
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.10)
                    }

                    // Etiqueta central con el acento.
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.30
                        height: width
                        radius: width / 2
                        color: Qt.alpha(root.accent, 0.28)
                        border.width: 1
                        border.color: Qt.alpha(root.accent, 0.75)

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.max(4, parent.width * 0.28)
                            height: width
                            radius: width / 2
                            color: Colours.palette.m3surfaceContainer
                        }
                    }
                }
            }

            // Borde sutil sobre la carátula.
            Rectangle {
                anchors.fill: parent
                radius: root.compact ? 14 : 18
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3onSurface, 0.14)
            }
        }

        // Metadatos y progreso.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: root.compact ? 4 : 6

            RowLayout {
                visible: root.showDevice
                spacing: 6

                MaterialIcon {
                    text: root.elysium.spotifyPlaying ? "graphic_eq" : "music_note"
                    color: root.accent
                    fontStyle: Tokens.font.icon.builders.small.build()
                }

                StyledText {
                    Layout.fillWidth: true
                    text: (root.elysium.spotifyDeviceLabel ? qsTr("SPOTIFY · %1").arg(root.elysium.spotifyDeviceLabel) : "SPOTIFY").toUpperCase()
                    color: root.accent
                    font.family: Tokens.font.label.small.family
                    font.pointSize: 8
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2.2
                    elide: Text.ElideRight
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.elysium.hasTrack ? root.elysium.trackTitle : qsTr("Nada sonando")
                color: Colours.palette.m3onSurface
                font: root.compact ? Tokens.font.title.small : Tokens.font.title.medium
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    if (!root.elysium.hasTrack)
                        return qsTr("Pon algo desde Elysium o con Laura");
                    const sub = [root.elysium.trackArtist, root.elysium.trackAlbum].filter(Boolean).join(" · ");
                    return sub || "Spotify";
                }
                color: Colours.palette.m3onSurfaceVariant
                font: root.compact ? Tokens.font.body.small : Tokens.font.body.medium
                elide: Text.ElideRight
            }

            // Barra de progreso fina con tiempos.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: root.compact ? 4 : 6
                visible: root.elysium.hasTrack && root.len > 0
                spacing: 4

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: root.compact ? 3 : 4
                    radius: 2
                    color: Qt.alpha(Colours.palette.m3onSurface, 0.12)

                    Rectangle {
                        height: parent.height
                        radius: 2
                        color: root.accent
                        width: parent.width * root.frac

                        Behavior on width {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    StyledText {
                        text: root.fmtTime(root.pos)
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    StyledText {
                        text: root.fmtTime(root.len)
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }
    }

    // Controles táctiles / ratón (pantalla de apoyo).
    RowLayout {
        visible: root.showControls
        Layout.fillWidth: true
        spacing: 10

        Item {
            Layout.fillWidth: true
        }

        CtrlBtn {
            icon: "skip_previous"
            onClicked: root.elysium.spotifyPrev()
        }

        CtrlBtn {
            icon: root.elysium.spotifyPlaying ? "pause" : "play_arrow"
            primary: true
            onClicked: root.elysium.spotifyPlayPause()
        }

        CtrlBtn {
            icon: "skip_next"
            onClicked: root.elysium.spotifyNext()
        }

        Item {
            Layout.fillWidth: true
        }
    }

    // Fila opcional de pistas de mando.
    RowLayout {
        visible: root.showHints
        Layout.fillWidth: true
        spacing: 12

        HintChip {
            letter: "A"
            label: root.elysium.spotifyPlaying ? qsTr("Pausa") : qsTr("Play")
        }

        HintChip {
            letter: "LB/RB"
            label: qsTr("Pista")
        }

        HintChip {
            letter: "X"
            label: root.elysium.spotifyLiked ? qsTr("♥") : qsTr("Gusta")
            accented: root.elysium.spotifyLiked
        }

        HintChip {
            letter: "B"
            label: qsTr("Cerrar")
        }
    }

    component CtrlBtn: Rectangle {
        id: cb

        property string icon
        property bool primary: false

        signal clicked

        implicitWidth: primary ? 46 : 38
        implicitHeight: implicitWidth
        radius: implicitWidth / 2
        color: primary ? root.accent : Qt.alpha(Colours.palette.m3onSurface, cbMa.containsMouse ? 0.14 : 0.07)
        border.width: primary ? 0 : 1
        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.12)
        scale: cbMa.pressed ? 0.92 : 1.0

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 100
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            text: cb.icon
            fill: 1
            color: cb.primary ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            fontStyle: Tokens.font.icon.builders.medium.scale(cb.primary ? 1.2 : 1.0).build()
        }

        MouseArea {
            id: cbMa

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cb.clicked()
        }
    }

    component HintChip: Row {
        property string letter
        property string label
        property bool accented: false

        spacing: 5

        PadGlyph {
            anchors.verticalCenter: parent.verticalCenter
            size: 20
            letter: parent.letter
            tone: parent.accented ? root.accent : Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: parent.accented ? root.accent : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }
    }
}
