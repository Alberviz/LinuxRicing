pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    required property Item wsRoot // Workspaces
    required property Item list // LazyListView de los pips

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

            readonly property Item pip: root.wsRoot.pipFor(modelData)

            // "En curso" solo mientras no haya un resultado ya terminado en ese workspace.
            readonly property bool running: Agents.hasRunningForWs(modelData) && !Agents.hasCompletedForWs(modelData)
            readonly property color ringColour: running ? Qt.rgba(0.93, 1.0, 0.97, 1.0) : Colours.palette.m3primary

            // Late el halo solo cuando hay agente en curso Y no estamos en ahorro
            // de energía: en batería el anillo queda estático y visible (sigues
            // sabiendo qué workspace tiene agente) pero sin bucle de animación.
            readonly property bool pulsing: running && !PowerSaving.active

            // 0..1, animado por el estilo de pulso activo
            property real pulse: 1.0
            property real pulseScale: 1.0

            visible: !!pip
            anchors.horizontalCenter: root.horizontalCenter

            // layoutY es relativo al LazyListView; hay que sumar su offset (igual que ActiveIndicator con mask.y).
            y: (pip?.LazyListView.layoutY ?? 0) + root.list.y - 3
            implicitWidth: Tokens.sizes.bar.innerWidth - Tokens.padding.small + 6
            implicitHeight: (pip?.LazyListView.preferredHeight ?? 0) + 6

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

                    // En ahorro no se instancia el blur (gaussian por-píxel).
                    layer.enabled: !PowerSaving.active
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
                running: halo.pulsing && Agents.runningStyle === "blink"
                loops: Animation.Infinite

                NumberAnimation { target: halo; property: "pulse"; to: 1.0; duration: 90; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 460 }
                NumberAnimation { target: halo; property: "pulse"; to: 0.05; duration: 240; easing.type: Easing.InQuad }
                PauseAnimation { duration: 300 }
            }

            // ---- Estilo B: respiración en color de paleta ----
            SequentialAnimation {
                running: halo.pulsing && Agents.runningStyle === "breathe"
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

            // Al dejar de latir (agente terminado, o entrada en modo ahorro con un
            // agente aún en curso), devolver el pulso a reposo para que el anillo
            // no se quede clavado a medio parpadeo.
            onPulsingChanged: if (!pulsing) {
                pulse = 1.0;
                pulseScale = 1.0;
            }
        }
    }
}
