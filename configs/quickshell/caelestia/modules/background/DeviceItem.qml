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

StyledClippingRect {
    id: devItem

    required property string name
    required property string icon
    required property int battery
    // false = el dispositivo no reporta % (p.ej. el Akko por cable): se
    // muestra sólo el estado/modo, sin porcentaje ni relleno líquido.
    property bool batteryKnown: true
    required property string status
    property string mode: "Desconectado"
    required property bool charging
    required property bool connected
    required property color accentColor
    property bool isClickable: false
    // Se propaga desde la ventana: fondos translúcidos vs. sólidos.
    property bool transparentWidgets: true
    signal clicked()

    readonly property bool isLowBattery: connected && batteryKnown && battery <= 20 && !charging
    readonly property real fillPercent: (devItem.connected && devItem.batteryKnown) ? Math.max(0.06, Math.min(1.0, devItem.battery / 100.0)) : 0.0

    implicitHeight: Math.max(116, itemCol.implicitHeight + Tokens.padding.medium * 2)
    radius: Tokens.rounding.large
    color: isLowBattery ? Qt.alpha(Colours.palette.m3errorContainer, 0.4) : (devItem.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

    Behavior on color {
        CAnim {}
    }

    // --- ANIMATED LIQUID WAVE FILL & ENERGY FLOW ---
    Item {
        id: liquidContainer
        anchors.fill: parent
        clip: true
        visible: devItem.connected && devItem.batteryKnown

        property real animatedHeight: devItem.height * devItem.fillPercent

        Behavior on animatedHeight {
            NumberAnimation {
                duration: 1000
                easing.type: Easing.OutCubic
            }
        }

        Canvas {
            id: waveCanvas
            anchors.fill: parent

            property real phase: 0.0
            property real particleProgress: 0.0

            property color waveColor1: devItem.isLowBattery ? Qt.alpha(Colours.palette.m3error, 0.25) : (devItem.charging ? Qt.alpha(Colours.palette.m3primary, 0.35) : Qt.alpha(devItem.accentColor, 0.22))
            property color waveColor2: devItem.isLowBattery ? Qt.alpha(Colours.palette.m3error, 0.42) : (devItem.charging ? Qt.alpha(Colours.palette.m3primary, 0.52) : Qt.alpha(devItem.accentColor, 0.36))
            property color plasmaColor: devItem.isLowBattery ? Colours.palette.m3error : Colours.palette.m3primary

            NumberAnimation on phase {
                from: 0
                to: Math.PI * 2
                duration: devItem.charging ? 1600 : 3400
                loops: Animation.Infinite
                running: devItem.connected
            }

            NumberAnimation on particleProgress {
                from: 0
                to: 1.0
                duration: 2200
                loops: Animation.Infinite
                running: devItem.charging
            }

            onPhaseChanged: requestPaint()
            onParticleProgressChanged: if (devItem.charging) requestPaint()

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                const baseH = liquidContainer.animatedHeight;
                const w = width;
                const h = height;
                const surfaceY = h - baseH;

                const amplitude = (baseH < 8 || baseH > h - 6) ? 1.5 : (devItem.charging ? 4.0 : 3.0);

                // Wave 1: Capa profunda
                ctx.beginPath();
                ctx.moveTo(0, h);
                for (let x = 0; x <= w; x += 4) {
                    const y = surfaceY + Math.sin(x * 0.05 + phase) * amplitude;
                    ctx.lineTo(x, y);
                }
                ctx.lineTo(w, h);
                ctx.closePath();
                ctx.fillStyle = waveColor1;
                ctx.fill();

                // Wave 2: Capa superficial en contrafase
                ctx.beginPath();
                ctx.moveTo(0, h);
                for (let x = 0; x <= w; x += 4) {
                    const y = surfaceY + Math.sin(x * 0.05 - phase + 1.2) * (amplitude * 0.85);
                    ctx.lineTo(x, y);
                }
                ctx.lineTo(w, h);
                ctx.closePath();
                ctx.fillStyle = waveColor2;
                ctx.fill();

                // --- ENERGÍA FLUIDA: RAYO DE PLASMA & BURBUJAS DE VOLTAJE AL CARGAR ---
                if (devItem.charging && baseH > 8) {
                    // 1. Línea brillante de Plasma en la superficie
                    ctx.beginPath();
                    for (let x = 0; x <= w; x += 4) {
                        const y = surfaceY + Math.sin(x * 0.05 - phase + 1.2) * (amplitude * 0.85);
                        if (x === 0) ctx.moveTo(x, y);
                        else ctx.lineTo(x, y);
                    }
                    ctx.strokeStyle = Qt.alpha(plasmaColor, 0.95);
                    ctx.lineWidth = 2.2;
                    ctx.stroke();

                    // 2. Chispas y burbujas de energía ascendentes
                    const count = 5;
                    for (let i = 0; i < count; i++) {
                        const seed = (i * 29 + 11) % (w - 16) + 8;
                        const pProg = (particleProgress + i * (1.0 / count)) % 1.0;
                        const px = seed + Math.sin(pProg * Math.PI * 2 + i) * 3;
                        const py = h - (pProg * baseH);
                        const pRadius = 1.4 + (i % 2) * 1.0;
                        const pAlpha = Math.sin(pProg * Math.PI) * 0.85;

                        if (py >= surfaceY - 2 && py <= h) {
                            ctx.beginPath();
                            ctx.arc(px, py, pRadius, 0, Math.PI * 2);
                            ctx.fillStyle = Qt.alpha(plasmaColor, pAlpha);
                            ctx.fill();
                        }
                    }
                }
            }
        }
    }

    StateLayer {
        enabled: devItem.isClickable
        radius: Tokens.rounding.large
        onClicked: devItem.clicked()
    }

    MaterialIcon {
        visible: devItem.isClickable
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 6
        text: "tune"
        fontStyle: Tokens.font.icon.small
        color: Qt.alpha(devItem.accentColor, 0.6)
    }

    ColumnLayout {
        id: itemCol

        anchors.centerIn: parent
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: devItem.name
            color: devItem.connected ? Colours.palette.m3onSurface : Colours.palette.m3outline
            font: Tokens.font.label.medium
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.extraSmall

            MaterialIcon {
                text: devItem.charging ? "battery_charging_full" : (devItem.isLowBattery ? "battery_alert" : devItem.icon)
                fontStyle: Tokens.font.icon.medium
                color: devItem.connected ? (devItem.isLowBattery ? Colours.palette.m3error : (devItem.charging ? Colours.palette.m3primary : devItem.accentColor)) : Colours.palette.m3outline
            }

            StyledText {
                // Sin conexión → "Off". Conectado sin % reportado (Akko por
                // cable) → sin texto; el chip de modo de abajo dice el estado.
                text: !devItem.connected ? "Off" : (devItem.batteryKnown ? `${devItem.battery}%` : "")
                visible: text.length > 0
                color: devItem.connected ? (devItem.isLowBattery ? Colours.palette.m3error : (devItem.charging ? Colours.palette.m3primary : Colours.palette.m3onSurface)) : Colours.palette.m3outline
                font: Tokens.font.title.medium
            }
        }

        StyledRect {
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: 22
            implicitWidth: modeRow.implicitWidth + 12
            radius: Tokens.rounding.full
            color: {
                if (!devItem.connected) return Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.7);
                if (devItem.isLowBattery) return Qt.alpha(Colours.palette.m3errorContainer, 0.9);
                if (devItem.charging) return Qt.alpha(Colours.palette.m3primaryContainer, 0.9);
                return Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.75);
            }
            border.width: 1
            border.color: {
                if (!devItem.connected) return Qt.alpha(Colours.palette.m3outlineVariant, 0.2);
                if (devItem.isLowBattery) return Qt.alpha(Colours.palette.m3error, 0.6);
                if (devItem.charging) return Qt.alpha(Colours.palette.m3primary, 0.6);
                return Qt.alpha(Colours.palette.m3outlineVariant, 0.35);
            }

            RowLayout {
                id: modeRow
                anchors.centerIn: parent
                spacing: 4

                MaterialIcon {
                    text: {
                        if (!devItem.connected) return "power_off";
                        if (devItem.charging) return "bolt";
                        if (devItem.isLowBattery) return "battery_alert";
                        const m = devItem.mode.toLowerCase();
                        if (m.includes("usb")) return "usb";
                        if (m.includes("bluetooth")) return "bluetooth";
                        if (m.includes("2.4g") || m.includes("inalámbrico") || m.includes("inalambrico")) return "sensors";
                        return "devices";
                    }
                    fontStyle: Tokens.font.icon.extraSmall
                    color: {
                        if (!devItem.connected) return Colours.palette.m3outline;
                        if (devItem.isLowBattery) return Colours.palette.m3onErrorContainer;
                        if (devItem.charging) return Colours.palette.m3onPrimaryContainer;
                        return Colours.palette.m3onSurface;
                    }
                }

                StyledText {
                    text: {
                        if (!devItem.connected) return "Desconectado";
                        if (devItem.isLowBattery) return "¡Batería Baja!";
                        if (devItem.charging) {
                            const cleanMode = devItem.mode.replace(" Inalámbrico", "").replace(" Inalambrico", "");
                            return cleanMode ? `Cargando · ${cleanMode}` : "Cargando";
                        }
                        return devItem.mode || devItem.status;
                    }
                    font: Tokens.font.label.small
                    color: {
                        if (!devItem.connected) return Colours.palette.m3outline;
                        if (devItem.isLowBattery) return Colours.palette.m3onErrorContainer;
                        if (devItem.charging) return Colours.palette.m3onPrimaryContainer;
                        return Colours.palette.m3onSurface;
                    }
                }
            }
        }
    }
}
