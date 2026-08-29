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
    required property int groupOffset

    function getWsIdx(ws: int): int {
        let i = ws - 1;
        while (i < 0)
            i += Config.bar.workspaces.shown;
        return i % Config.bar.workspaces.shown;
    }

    Repeater {
        model: ScriptModel {
            // ids de workspace (int) que tienen algun agente
            values: Object.keys(Agents.wsMap).map(k => parseInt(k, 10)).filter(n => Agents.wsMap[n].length > 0)
        }

        StyledRect {
            id: halo

            required property int modelData

            readonly property int idx: root.getWsIdx(modelData)
            readonly property Item pip: root.workspaces.count > idx ? root.workspaces.itemAt(idx) : null
            readonly property bool inGroup: modelData > root.groupOffset && modelData <= root.groupOffset + Config.bar.workspaces.shown

            visible: inGroup && pip
            anchors.horizontalCenter: root.horizontalCenter

            y: (pip?.y ?? 0) - 1
            implicitWidth: Tokens.sizes.bar.innerWidth - Tokens.padding.small + 2
            implicitHeight: (pip?.size ?? 0) + 2
            radius: Tokens.rounding.full

            color: Colours.palette.m3primary
            opacity: 0.22

            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.6
                blurMax: 12
            }

            scale: 0
            Component.onCompleted: scale = 1
            Behavior on scale {
                Anim { easing: Tokens.anim.standardDecel }
            }
            Behavior on y {
                Anim {}
            }
        }
    }
}
