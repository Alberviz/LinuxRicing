pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services

// Mini-reproductor flotante encima del juego (LB + ↓).
// Esquina superior derecha, margen 40 px, sin foco de teclado y con máscara solo
// en la tarjeta para no bloquear clics fuera. Aro de 6 s en el borde.
PanelWindow {
    id: win

    required property var elysium
    readonly property bool shown: elysium.musicHudVisible
    readonly property color accent: Colours.palette.m3primary
    property real ringFrac: 0

    screen: elysium.consoleScreen
    visible: shown || card.opacity > 0.01
    color: "transparent"
    WlrLayershell.namespace: "caelestia-elysium-music-hud"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors.top: true
    anchors.right: true
    implicitWidth: 540
    implicitHeight: 240

    mask: Region {
        item: maskTarget
    }

    Item {
        id: maskTarget

        x: win.shown ? card.x : 0
        y: win.shown ? card.y : 0
        width: win.shown ? card.width : 0
        height: win.shown ? card.height : 0
    }

    // Reinicia el aro de 6 s cada vez que se abre o se pulsa un botón en el HUD.
    function restartRing(): void {
        ringAnim.stop();
        win.ringFrac = 1.0;
        if (win.shown)
            ringAnim.start();
    }

    onShownChanged: {
        if (shown)
            restartRing();
        else
            ringAnim.stop();
    }

    Connections {
        target: win.elysium

        function onHudIdleTokenChanged(): void {
            if (win.shown)
                win.restartRing();
        }
    }

    NumberAnimation {
        id: ringAnim

        target: win
        property: "ringFrac"
        from: 1.0
        to: 0.0
        duration: 6000
    }

    onRingFracChanged: {
        if (borderRing.visible)
            borderRing.requestPaint();
    }

    Rectangle {
        id: card

        readonly property int r: 24

        anchors.right: parent.right
        anchors.rightMargin: 40
        y: win.shown ? 40 : 0
        width: 460
        height: 158
        radius: r
        color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.92)
        border.width: 1
        border.color: Qt.alpha(win.accent, 0.30)
        opacity: win.shown ? 1 : 0
        clip: true

        Behavior on y {
            NumberAnimation {
                duration: 380
                easing.type: Easing.OutExpo
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 380
                easing.type: Easing.OutExpo
            }
        }

        // Resplandor sutil del acento detrás de la carátula.
        Rectangle {
            x: -50
            y: -50
            width: 200
            height: 200
            radius: 100
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(win.accent, 0.16)
                }
                GradientStop {
                    position: 1
                    color: "transparent"
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 16

            // Carátula 110 px con esquinas redondeadas + fallback disco.
            StyledClippingRect {
                Layout.preferredWidth: 110
                Layout.preferredHeight: 110
                Layout.alignment: Qt.AlignVCenter
                radius: 16
                color: Qt.alpha(Colours.palette.m3onSurface, 0.06)

                Image {
                    id: hudCover

                    anchors.fill: parent
                    source: win.elysium.trackArtUrl
                    sourceSize.width: 240
                    sourceSize.height: 240
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    visible: status === Image.Ready
                }

                Item {
                    anchors.fill: parent
                    visible: hudCover.status !== Image.Ready

                    Rectangle {
                        anchors.centerIn: parent
                        width: 90
                        height: 90
                        radius: 45
                        color: Qt.tint("#0a0c14", Qt.alpha(win.accent, 0.14))
                        border.width: 1.5
                        border.color: Qt.alpha(win.accent, 0.45)

                        Rectangle {
                            anchors.centerIn: parent
                            width: 62
                            height: 62
                            radius: 31
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha(Colours.palette.m3onSurface, 0.12)
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            radius: 14
                            color: Qt.alpha(win.accent, 0.28)
                            border.width: 1
                            border.color: Qt.alpha(win.accent, 0.75)

                            Rectangle {
                                anchors.centerIn: parent
                                width: 8
                                height: 8
                                radius: 4
                                color: Colours.palette.m3surfaceContainer
                            }
                        }
                    }
                }

                // Insignia de Me gusta en la esquina si está marcado.
                Rectangle {
                    visible: win.elysium.spotifyLiked
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    width: 24
                    height: 24
                    radius: 12
                    color: Qt.rgba(0, 0, 0, 0.65)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "favorite"
                        fill: 1
                        color: win.accent
                        fontStyle: Tokens.font.icon.builders.small.build()
                    }
                }
            }

            // Metadatos, progreso y pistas.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    MaterialIcon {
                        text: win.elysium.spotifyPlaying ? "graphic_eq" : "music_note"
                        color: win.accent
                        fontStyle: Tokens.font.icon.builders.small.build()
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: (win.elysium.spotifyDeviceLabel ? qsTr("SPOTIFY · %1").arg(win.elysium.spotifyDeviceLabel) : "SPOTIFY").toUpperCase()
                        color: win.accent
                        font.family: Tokens.font.label.small.family
                        font.pointSize: 8
                        font.weight: Font.DemiBold
                        font.letterSpacing: 2.2
                        elide: Text.ElideRight
                    }

                    StyledText {
                        visible: win.elysium.spotifyVolumeText.length > 0
                        text: win.elysium.spotifyVolumeText
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.label.small
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: win.elysium.hasTrack ? win.elysium.trackTitle : qsTr("Nada sonando")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.title.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: win.elysium.hasTrack
                        ? ([win.elysium.trackArtist, win.elysium.trackAlbum].filter(Boolean).join(" · ") || "Spotify")
                        : qsTr("Pulsa A para reproducir")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                // Progreso fino.
                Item {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    implicitHeight: 4
                    visible: win.elysium.hasTrack && win.elysium.trackLength > 0

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Qt.alpha(Colours.palette.m3onSurface, 0.16)

                        Rectangle {
                            height: parent.height
                            radius: 2
                            color: win.accent
                            width: parent.width * Math.max(0, Math.min(1, win.elysium.trackPosition / Math.max(1, win.elysium.trackLength)))

                            Behavior on width {
                                NumberAnimation {
                                    duration: 280
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillHeight: true
                }

                // Fila compacta de pistas.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    HudHint {
                        letter: "A"
                        label: win.elysium.spotifyPlaying ? qsTr("Pausa") : qsTr("Play")
                    }

                    HudHint {
                        letter: "LB/RB"
                        label: qsTr("Pista")
                    }

                    HudHint {
                        letter: "↑↓"
                        label: qsTr("Vol")
                    }

                    HudHint {
                        letter: "X"
                        label: "♥"
                        accented: win.elysium.spotifyLiked
                    }

                    HudHint {
                        letter: "B"
                        label: qsTr("Cerrar")
                    }
                }
            }
        }

        // Aro de 6 s en el borde que se va vaciando hasta ocultarse.
        Canvas {
            id: borderRing

            anchors.fill: parent
            visible: card.opacity > 0.01 && win.ringFrac > 0.002

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (win.ringFrac <= 0.002)
                    return;

                const pad = 1.5;
                const w = width - pad * 2;
                const h = height - pad * 2;
                const r = card.r - pad;
                const straight = 2 * (w - 2 * r) + 2 * (h - 2 * r);
                const perim = straight + 2 * Math.PI * r;
                const drawLen = perim * Math.max(0, Math.min(1, win.ringFrac));

                ctx.save();
                ctx.beginPath();
                ctx.moveTo(pad + w / 2, pad);
                ctx.lineTo(pad + w - r, pad);
                ctx.arcTo(pad + w, pad, pad + w, pad + r, r);
                ctx.lineTo(pad + w, pad + h - r);
                ctx.arcTo(pad + w, pad + h, pad + w - r, pad + h, r);
                ctx.lineTo(pad + r, pad + h);
                ctx.arcTo(pad, pad + h, pad, pad + h - r, r);
                ctx.lineTo(pad, pad + r);
                ctx.arcTo(pad, pad, pad + r, pad, r);
                ctx.closePath();

                ctx.strokeStyle = String(win.accent);
                ctx.lineWidth = 2.5;
                ctx.lineCap = "round";
                ctx.setLineDash([drawLen, perim]);
                ctx.stroke();
                ctx.restore();
            }
        }
    }

    component HudHint: Row {
        property string letter
        property string label
        property bool accented: false

        spacing: 4

        PadGlyph {
            anchors.verticalCenter: parent.verticalCenter
            size: 18
            letter: parent.letter
            tone: parent.accented ? win.accent : Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: parent.accented ? win.accent : Colours.palette.m3onSurfaceVariant
            font.family: Tokens.font.label.small.family
            font.pointSize: 8.5
        }
    }
}
