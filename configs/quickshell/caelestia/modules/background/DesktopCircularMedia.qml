pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.Services
import Caelestia.Components
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.images
import qs.services

Item {
    id: mediaRoot

    implicitWidth: 460
    implicitHeight: contentCol.implicitHeight

    ServiceRef {
        service: Audio.cava
    }

    readonly property var cavaVals: Audio.cava.values || []
    property var smoothedVals: []
    property var smoothedVals2: []

    FrameAnimation {
        id: frameAnim
        // Gatear a actividad real: solo late si el widget se ve y hay música
        // sonando. Un FrameAnimation incondicional repinta un Canvas FBO de
        // 448px a 60fps para siempre y clava un núcleo (ver CLAUDE.md).
        running: mediaRoot.visible && (Players.active?.isPlaying ?? false)
        
        property real lastTime: Date.now() / 1000
        
        onRunningChanged: {
            if (running) {
                lastTime = Date.now() / 1000;
            } else {
                const len = 48;
                mediaRoot.smoothedVals = new Array(len).fill(0.02);
                mediaRoot.smoothedVals2 = new Array(len).fill(0.02);
                radialCanvas.requestPaint();
            }
        }
        onTriggered: {
            const now = Date.now() / 1000;
            const dt = Math.min(now - frameAnim.lastTime, 0.1);
            frameAnim.lastTime = now;
            radialCanvas.orbitPhase += dt;
            
            const vals = mediaRoot.cavaVals || [];
            const len = 48;
            if (!mediaRoot.smoothedVals || mediaRoot.smoothedVals.length !== len) {
                mediaRoot.smoothedVals = new Array(len).fill(0.02);
                mediaRoot.smoothedVals2 = new Array(len).fill(0.02);
            }
            const cur1 = mediaRoot.smoothedVals.slice();
            const cur2 = mediaRoot.smoothedVals2.slice();
            for (let i = 0; i < len; i++) {
                const ratio = (i / (len - 1)) * (vals.length - 1);
                const idx = Math.floor(ratio);
                const frac = ratio - idx;
                const v1 = vals[idx] || 0.0;
                const v2 = vals[Math.min(idx + 1, vals.length - 1)] || 0.0;
                const target = Math.max(0.02, v1 * (1 - frac) + v2 * frac);

                cur1[i] += (target - cur1[i]) * 0.36;
                cur2[i] += (target - cur2[i]) * 0.20;
            }
            mediaRoot.smoothedVals = cur1;
            mediaRoot.smoothedVals2 = cur2;
            radialCanvas.requestPaint();
        }
    }

    ColumnLayout {
        id: contentCol
        anchors.centerIn: parent
        spacing: Tokens.spacing.large

        // Visualizer and Circular Cover Area
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 380
            implicitHeight: 380

            // 360° Concentric Gravitational Resonance Rings Canvas
            Canvas {
                id: radialCanvas
                anchors.centerIn: parent
                width: 448
                height: 448
                renderTarget: Canvas.FramebufferObject

                property real orbitPhase: 0.0

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();

                    const cx = width / 2;
                    const cy = height / 2;
                    const vals = mediaRoot.smoothedVals;
                    if (!vals || vals.length < 8) return;

                    // Calculate Frequency Band Intensities
                    let bSum = 0, mSum = 0, tSum = 0;
                    for (let i = 0; i < 8; i++) bSum += (vals[i] || 0.0);
                    for (let i = 8; i < 24; i++) mSum += (vals[i] || 0.0);
                    for (let i = 24; i < vals.length; i++) tSum += (vals[i] || 0.0);

                    const bass = Math.min(1.0, (bSum / 8) * 1.4);
                    const mid = Math.min(1.0, (mSum / 16) * 1.5);
                    const treble = Math.min(1.0, (tSum / (vals.length - 24)) * 1.8);

                    // Base cover radius = 120px
                    // Ring 1: Bass Core Gravity Well (Thick, pulsating with kick drum)
                    const r1 = 128 + bass * 18;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r1, 0, 2 * Math.PI);
                    ctx.strokeStyle = Qt.alpha(Colours.palette.m3primary, 0.75 + bass * 0.25);
                    ctx.lineWidth = 2.5 + bass * 3.5;
                    ctx.stroke();

                    // Ring 2: Mid-Range Orbit (Dashed satellite ring reacting to vocals/melody)
                    const r2 = 150 + mid * 22;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r2, 0, 2 * Math.PI);
                    ctx.setLineDash([10, 6]);
                    ctx.strokeStyle = Qt.alpha(Colours.palette.m3secondary, 0.6 + mid * 0.4);
                    ctx.lineWidth = 2.0 + mid * 1.5;
                    ctx.stroke();
                    ctx.setLineDash([]); // Reset dash

                    // Ring 3: Treble Orbit (Outer delicate harmonic resonance)
                    const r3 = 172 + treble * 26;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r3, 0, 2 * Math.PI);
                    ctx.strokeStyle = Qt.alpha(Colours.palette.m3tertiary, 0.45 + treble * 0.55);
                    ctx.lineWidth = 1.5 + treble * 1.5;
                    ctx.stroke();

                    // Ring 4: Faint Cosmic Boundary
                    const r4 = 192 + (bass * 0.5 + treble * 0.5) * 16;
                    ctx.beginPath();
                    ctx.arc(cx, cy, r4, 0, 2 * Math.PI);
                    ctx.setLineDash([4, 8]);
                    ctx.strokeStyle = Qt.alpha(Colours.palette.m3outlineVariant, 0.25 + bass * 0.3);
                    ctx.lineWidth = 1.0;
                    ctx.stroke();
                    ctx.setLineDash([]);

                    // Orbiting Photons / Satellites
                    const t = radialCanvas.orbitPhase;
                    const ang1 = (t * 1.2) % (2 * Math.PI);
                    const ang2 = (-t * 0.8) % (2 * Math.PI);
                    const ang3 = (t * 1.6 + Math.PI) % (2 * Math.PI);

                    // Photon 1 on Ring 1
                    ctx.beginPath();
                    ctx.fillStyle = Colours.palette.m3primary;
                    ctx.arc(cx + r1 * Math.cos(ang1), cy + r1 * Math.sin(ang1), 4.0 + bass * 3, 0, 2 * Math.PI);
                    ctx.fill();

                    // Photon 2 on Ring 2
                    ctx.beginPath();
                    ctx.fillStyle = Colours.palette.m3secondary;
                    ctx.arc(cx + r2 * Math.cos(ang2), cy + r2 * Math.sin(ang2), 3.5 + mid * 2.5, 0, 2 * Math.PI);
                    ctx.fill();

                    // Photon 3 on Ring 3
                    ctx.beginPath();
                    ctx.fillStyle = Colours.palette.m3tertiary;
                    ctx.arc(cx + r3 * Math.cos(ang3), cy + r3 * Math.sin(ang3), 3.0 + treble * 2.5, 0, 2 * Math.PI);
                    ctx.fill();

                    // Cardinal Coordinate Crosshair Accents
                    const crossLen = 6 + bass * 8;
                    ctx.strokeStyle = Qt.alpha(Colours.palette.m3primary, 0.6);
                    ctx.lineWidth = 1.5;
                    const angles = [0, Math.PI / 2, Math.PI, 3 * Math.PI / 2];
                    for (let a of angles) {
                        const x0 = cx + (r1 - 4) * Math.cos(a);
                        const y0 = cy + (r1 - 4) * Math.sin(a);
                        const x1 = cx + (r1 + crossLen) * Math.cos(a);
                        const y1 = cy + (r1 + crossLen) * Math.sin(a);
                        ctx.beginPath();
                        ctx.moveTo(x0, y0);
                        ctx.lineTo(x1, y1);
                        ctx.stroke();
                    }
                }
            }

            // Large Circular Album Cover Art (240px)
            StyledClippingRect {
                id: coverCircle
                anchors.centerIn: parent
                width: 240
                height: 240
                radius: width / 2
                color: Colours.palette.m3surfaceContainerHigh
                border.color: Qt.alpha(Colours.palette.m3primary, 0.6)
                border.width: 3

                // Fallback Vinyl Center & Music Note Icon (visible when FadeImage has no art)
                Item {
                    anchors.fill: parent

                    // Subtle vinyl record grooves
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const cx = width / 2;
                            const cy = height / 2;
                            ctx.strokeStyle = Qt.alpha(Colours.palette.m3outlineVariant, 0.18);
                            ctx.lineWidth = 1;
                            for (let r of [45, 65, 85, 105]) {
                                ctx.beginPath();
                                ctx.arc(cx, cy, r, 0, 2 * Math.PI);
                                ctx.stroke();
                            }
                        }
                    }

                    // Center Vinyl Hub
                    StyledRect {
                        anchors.centerIn: parent
                        width: 90
                        height: 90
                        radius: width / 2
                        color: Colours.palette.m3primaryContainer
                        border.color: Qt.alpha(Colours.palette.m3primary, 0.4)
                        border.width: 2

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "music_note"
                            color: Colours.palette.m3onPrimaryContainer
                            fontStyle: Tokens.font.icon.builders.extraLarge.scale(2.2).build()
                        }
                    }
                }

                FadeImage {
                    id: coverFadeImg
                    anchors.fill: parent
                    source: (Players.active?.trackArtUrl, Players.active?.metadata, Players.getArtUrl(Players.active))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }

                // Inner soft dark vignette
                StyledRect {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.color: Qt.alpha("#000000", 0.35)
                    border.width: 4
                }

                // Click to toggle play/pause
                StateLayer {
                    radius: coverCircle.radius
                    onClicked: Players.active?.togglePlaying()
                }
            }
        }

        // Track Details (Centered cleanly below)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall

            StyledText {
                Layout.fillWidth: true
                text: Players.active?.trackTitle ?? qsTr("Sin reproducción")
                color: Colours.palette.m3onSurface
                horizontalAlignment: Text.AlignHCenter
                font: Tokens.font.headline.small
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: Players.active?.trackArtist ?? qsTr("Abre Spotify o YouTube para escuchar")
                color: Colours.palette.m3onSurfaceVariant
                horizontalAlignment: Text.AlignHCenter
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }
        }
    }
}
