pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

StyledClippingRect {
    id: root

    required property ShellScreen screen
    required property bool fullscreen

    readonly property bool onSpecial: (GlobalConfig.bar.workspaces.perMonitorWorkspaces ? Hypr.monitorFor(screen) : Hypr.focusedMonitor)?.lastIpcObject.specialWorkspace?.name !== ""
    readonly property int activeWsId: GlobalConfig.bar.workspaces.perMonitorWorkspaces ? (Hypr.monitorFor(screen).activeWorkspace?.id ?? 1) : Hypr.activeWsId

    readonly property var occupied: {
        const occ = {};
        for (const ws of Hypr.workspaces.values)
            occ[ws.id] = ws.lastIpcObject.windows > 0;
        return occ;
    }
    readonly property int groupOffset: Math.floor((activeWsId - 1) / Config.bar.workspaces.shown) * Config.bar.workspaces.shown

    // Ids de workspace con un agente en curso, o con una notificación completada
    // sin ver, dentro o fuera del grupo paginado visible.
    function agentWsIdsWithActivity(): var {
        const _deps = [Agents.completedAgents.length, Agents.runningAgents.length, Hypr.activeWsId];
        const s = new Set();
        for (const k of Object.keys(Agents.wsMap))
            if (Agents.unseenCountForWs(parseInt(k, 10)) > 0)
                s.add(parseInt(k, 10));
        for (const k of Object.keys(Agents.runningWsMap))
            if (Agents.hasRunningForWs(parseInt(k, 10)))
                s.add(parseInt(k, 10));
        return Array.from(s);
    }

    // Actividad de agente en workspaces fuera del grupo paginado visible: si
    // el workspace oculto queda "por delante" (número mayor) parpadea el borde
    // de abajo de la cápsula; si queda "por detrás" (número menor), el de arriba.
    readonly property var hiddenBelowIds: agentWsIdsWithActivity().filter(id => id > groupOffset + Config.bar.workspaces.shown)
    readonly property var hiddenAboveIds: agentWsIdsWithActivity().filter(id => id <= groupOffset)
    readonly property bool hiddenActivityBelow: hiddenBelowIds.length > 0
    readonly property bool hiddenActivityAbove: hiddenAboveIds.length > 0
    readonly property int nearestHiddenBelowWs: hiddenBelowIds.length > 0 ? Math.min(...hiddenBelowIds) : -1
    readonly property int nearestHiddenAboveWs: hiddenAboveIds.length > 0 ? Math.max(...hiddenAboveIds) : -1

    property real blur: onSpecial ? 1 : 0

    function wsAt(yInRoot: real): var {
        const p = mapToItem(layout, layout.width / 2, yInRoot);
        let c = layout.childAt(p.x, p.y);
        while (c && !c.isWorkspace)
            c = c.parent;
        return (c && c.isWorkspace) ? c : null;
    }

    // El pip (Workspace) de un workspace concreto, si está en el grupo visible.
    function pipFor(wsId: int): var {
        for (let i = 0; i < workspaces.count; i++) {
            const w = workspaces.itemAt(i);
            if (w && w.ws === wsId)
                return w;
        }
        return null;
    }

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: layout.implicitHeight + Tokens.padding.small

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    Item {
        anchors.fill: parent
        scale: root.onSpecial ? 0.8 : 1
        opacity: root.onSpecial ? 0.5 : 1
        visible: !root.fullscreen

        layer.enabled: root.blur > 0
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: root.blur
            blurMax: 32
        }

        Loader {
            asynchronous: true
            active: Config.bar.workspaces.occupiedBg

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall

            sourceComponent: OccupiedBg {
                workspaces: workspaces
                occupied: root.occupied
                groupOffset: root.groupOffset
            }
        }

        AgentBg {
            anchors.fill: parent
            workspaces: workspaces
            layout: layout
            groupOffset: root.groupOffset
        }

        ColumnLayout {
            id: layout

            anchors.centerIn: parent
            spacing: Math.floor(Tokens.spacing.extraSmall)

            Repeater {
                id: workspaces

                model: Config.bar.workspaces.shown

                Workspace {
                    activeWsId: root.activeWsId
                    occupied: root.occupied
                    groupOffset: root.groupOffset
                }
            }
        }

        Loader {
            asynchronous: true
            anchors.horizontalCenter: parent.horizontalCenter
            active: Config.bar.workspaces.activeIndicator

            sourceComponent: ActiveIndicator {
                activeWsId: root.activeWsId
                workspaces: workspaces
                mask: layout
                fullscreen: root.fullscreen
            }
        }

        MouseArea {
            anchors.fill: layout
            onClicked: event => {
                const ws = (layout.childAt(event.x, event.y) as Workspace)?.ws;
                if (!ws)
                    return;
                if (Hypr.activeWsId !== ws)
                    Hypr.dispatch(Hypr.usingLua ? `hl.dsp.focus({ workspace = "${ws}" })` : `workspace ${ws}`);
                else
                    Hypr.dispatch(Hypr.usingLua ? 'hl.dsp.workspace.toggle_special("special")' : "togglespecialworkspace special");
            }
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        HiddenActivityEdge {
            atBottom: false
            active: root.hiddenActivityAbove
            targetWs: root.nearestHiddenAboveWs
        }

        HiddenActivityEdge {
            atBottom: true
            active: root.hiddenActivityBelow
            targetWs: root.nearestHiddenBelowWs
        }
    }

    Loader {
        id: specialWs

        asynchronous: true

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall

        active: opacity > 0

        scale: root.onSpecial ? 1 : 0.5
        opacity: root.onSpecial ? 1 : 0

        sourceComponent: SpecialWorkspaces {
            screen: root.screen
        }

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Behavior on blur {
        Anim {
            type: Anim.StandardSmall
        }
    }
}
