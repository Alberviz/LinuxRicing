pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property Repeater workspaces
    required property Item layout
    required property int groupOffset

    function getWsIdx(ws: int): int {
        let i = ws - 1;
        while (i < 0)
            i += Config.bar.workspaces.shown;
        return i % Config.bar.workspaces.shown;
    }

    Repeater {
        model: ScriptModel {
            // ids de workspace (int) con algún agente, en curso o terminado
            values: {
                const _deps = [Agents.completedAgents.length, Agents.runningAgents.length];
                const s = new Set();
                for (const k of Object.keys(Agents.wsMap))
                    if (Agents.wsMap[k].length > 0)
                        s.add(parseInt(k, 10));
                for (const k of Object.keys(Agents.runningWsMap))
                    if (Agents.runningWsMap[k].length > 0)
                        s.add(parseInt(k, 10));
                return Array.from(s);
            }
        }

        Item {
            id: halo

            required property int modelData

            readonly property int idx: root.getWsIdx(modelData)
            readonly property Item pip: root.workspaces.count > idx ? root.workspaces.itemAt(idx) : null
            readonly property bool inGroup: modelData > root.groupOffset && modelData <= root.groupOffset + Config.bar.workspaces.shown

            // "En curso" solo mientras no haya un resultado ya terminado en ese workspace.
            readonly property bool running: Agents.hasRunningForWs(modelData) && !Agents.hasCompletedForWs(modelData)
            readonly property color ringColour: running ? Qt.rgba(0.93, 1.0, 0.97, 1.0) : Colours.palette.m3primary

            // 0..1, animado por el estilo de pulso activo
            property real pulse: 1.0
            property real pulseScale: 1.0

            visible: inGroup && pip
            anchors.horizontalCenter: root.horizontalCenter

            // pip.y es relativo al ColumnLayout; hay que sumar su offset (igual que ActiveIndicator con mask.y).
            y: (pip?.y ?? 0) + root.layout.y - 3
            implicitWidth: Tokens.sizes.bar.innerWidth - Tokens.padding.small + 6
            implicitHeight: (pip?.size ?? 0) + 6

            scale: 0
            Component.onCompleted: scale = 1
            Behavior on scale {
                Anim { easing: Tokens.anim.standardDecel }
            }
            Behavior on y {
                Anim {}
            }

            Item {
                id: ringWrap

                anchors.fill: parent
                scale: halo.running ? halo.pulseScale : 1.0

                // Resplandor difuso — SOLO el contorno (borde), nunca el relleno del pip.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -1
                    radius: Tokens.rounding.full
                    color: "transparent"
                    border.width: 3
                    border.color: halo.ringColour
                    opacity: halo.running ? 0.5 * halo.pulse : 0.32

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: 0.85
                        blurMax: 18
                    }
                }

                // Contorno neón nítido
                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.rounding.full
                    color: "transparent"
                    border.width: 2
                    border.color: halo.ringColour
                    opacity: halo.running ? 0.12 + 0.88 * halo.pulse : 0.9
                }
            }

            // ---- Estilo A: parpadeo blanco ----
            SequentialAnimation {
                running: halo.running && Agents.runningStyle === "blink"
                loops: Animation.Infinite

                NumberAnimation { target: halo; property: "pulse"; to: 1.0; duration: 90; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 460 }
                NumberAnimation { target: halo; property: "pulse"; to: 0.05; duration: 240; easing.type: Easing.InQuad }
                PauseAnimation { duration: 300 }
            }

            // ---- Estilo B: respiración en color de paleta ----
            SequentialAnimation {
                running: halo.running && Agents.runningStyle === "breathe"
                loops: Animation.Infinite

                ParallelAnimation {
                    NumberAnimation { target: halo; property: "pulse"; to: 1.0; duration: 850; easing.type: Easing.InOutSine }
                    NumberAnimation { target: halo; property: "pulseScale"; to: 1.03; duration: 850; easing.type: Easing.InOutSine }
                }
                ParallelAnimation {
                    NumberAnimation { target: halo; property: "pulse"; to: 0.32; duration: 850; easing.type: Easing.InOutSine }
                    NumberAnimation { target: halo; property: "pulseScale"; to: 0.97; duration: 850; easing.type: Easing.InOutSine }
                }
            }

            // Al dejar de estar "en curso", devolver el pulso a reposo.
            onRunningChanged: if (!running) {
                pulse = 1.0;
                pulseScale = 1.0;
            }
        }
    }
}
