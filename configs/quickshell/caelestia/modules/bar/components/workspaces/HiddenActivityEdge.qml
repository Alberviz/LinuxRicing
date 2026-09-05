pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

// Aviso de actividad de agente FUERA de la página visible de pips.
//
// Cuando un agente está en curso (o dejó una notificación sin ver) en un
// workspace que no pertenece al grupo paginado que se muestra ahora mismo
// (Config.bar.workspaces.shown), no hay ninguna señal en la barra — el halo y
// el badge de AgentBg/AgentBadges solo dibujan pips dentro del grupo visible.
//
// Este componente parpadea el borde (arriba o abajo, según hacia qué lado
// numérico quede el workspace oculto — los pips suben de número hacia abajo
// en la columna) de la cápsula general de workspaces, y salta al workspace
// oculto con actividad más cercano al hacer clic.
Item {
    id: root

    required property bool active
    required property bool atBottom
    required property int targetWs // -1 si no hay ninguno oculto con actividad

    readonly property color tint: Colours.palette.m3tertiary

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: atBottom ? undefined : parent.top
    anchors.bottom: atBottom ? parent.bottom : undefined
    height: 16 // hit-target del clic; queda contenido dentro del recorte de la cápsula

    visible: active

    // 0..1, animado mientras `active`; en reposo se congela (sin bucle corriendo).
    property real pulse: 0.35
    onActiveChanged: if (!active)
        pulse = 0.35;

    MouseArea {
        anchors.fill: parent
        enabled: root.active && root.targetWs > 0
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        hoverEnabled: true
        onClicked: {
            if (root.targetWs <= 0)
                return;
            Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = "${root.targetWs}" })` : `workspace ${root.targetWs}`);
        }
    }

    Rectangle {
        id: glow

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: root.atBottom ? undefined : parent.top
        anchors.bottom: root.atBottom ? parent.bottom : undefined
        height: 4

        radius: Tokens.rounding.full
        color: root.tint
        opacity: root.pulse

        layer.enabled: root.active
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 0.7
            blurMax: 16
        }
    }

    MaterialIcon {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: root.atBottom ? undefined : parent.top
        anchors.bottom: root.atBottom ? parent.bottom : undefined

        text: root.atBottom ? "keyboard_arrow_down" : "keyboard_arrow_up"
        color: root.tint
        fontStyle: Tokens.font.icon.small
        opacity: root.pulse
    }

    // Parpadeo — solo corre mientras haya actividad oculta que anunciar.
    SequentialAnimation {
        running: root.active
        loops: Animation.Infinite

        NumberAnimation {
            target: root
            property: "pulse"
            to: 0.95
            duration: 420
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: root
            property: "pulse"
            to: 0.18
            duration: 420
            easing.type: Easing.InOutQuad
        }
    }
}
