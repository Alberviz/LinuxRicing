pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Caelestia
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.services

StyledClippingRect {
    id: root

    required property ShellScreen screen
    required property bool fullscreen

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property bool onSpecial: monitor?.lastIpcObject.specialWorkspace?.name !== ""
    readonly property int activeWsId: monitor.activeWorkspace?.id ?? 1
    readonly property int activeWsIdx: workspaceIndex(activeWsId)
    readonly property int shown: Math.max(1, Config.bar.workspaces.shown)

    readonly property var wsIds: {
        if (Config.bar.workspaces.showUnoccupied)
            return Array.from({
                length: shown
            }, (_, i) => i + 1);

        const allMonitors = !Config.bar.workspaces.perMonitor;
        const ignoredTags = GlobalConfig.bar.workspaces.ignoredTags;
        const workspaces = Hypr.workspaces.values.filter(w => w.id > 0 && (allMonitors || w.monitor === root.monitor) && (w.id === activeWsId || w.toplevels.values.some(t => !Hypr.isToplevelIgnored(t, ignoredTags))));
        const currentIdx = workspaces.findIndex(w => w.id === activeWsId);
        if (currentIdx < 0)
            return [];

        const end = CUtils.clamp(currentIdx + 1, Math.min(shown, workspaces.length), workspaces.length);
        const start = Math.max(0, end - shown);

        return workspaces.slice(start, end).map(w => w.id);
    }

    readonly property var workspaces: {
        workspaces.itemsDirty;
        return wsIds.map(id => workspaces.itemAtIndex(workspaceIndex(id)));
    }

    // Only relevant for when showUnoccupied is true
    readonly property int groupOffset: {
        if (!Config.bar.workspaces.showUnoccupied)
            return 0;
        return Math.floor((activeWsId - 1) / shown) * shown;
    }

    // Ids de workspace con un agente en curso, o con una notificación completada
    // sin ver, dentro o fuera del grupo visible.
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

    // Actividad de agente en workspaces fuera del grupo visible: si el workspace
    // oculto queda "por delante" (número mayor) parpadea el borde de abajo de la
    // cápsula; si queda "por detrás" (número menor), el de arriba.
    readonly property var hiddenAgentIds: agentWsIdsWithActivity().filter(id => !wsIds.includes(id))
    readonly property var hiddenBelowIds: wsIds.length > 0 ? hiddenAgentIds.filter(id => id > Math.max(...wsIds)) : []
    readonly property var hiddenAboveIds: wsIds.length > 0 ? hiddenAgentIds.filter(id => id < Math.min(...wsIds)) : []
    readonly property bool hiddenActivityBelow: hiddenBelowIds.length > 0
    readonly property bool hiddenActivityAbove: hiddenAboveIds.length > 0
    readonly property int nearestHiddenBelowWs: hiddenBelowIds.length > 0 ? Math.min(...hiddenBelowIds) : -1
    readonly property int nearestHiddenAboveWs: hiddenAboveIds.length > 0 ? Math.max(...hiddenAboveIds) : -1

    property real blur: onSpecial ? 1 : 0

    function wsAt(yInRoot: real): var {
        const p = mapToItem(workspaces, workspaces.width / 2, yInRoot);
        return workspaces.itemAt(p.x, p.y) as Workspace;
    }

    // El pip (Workspace) de un workspace concreto, si está en el grupo visible.
    function pipFor(wsId: int): var {
        return root.workspaces.find(w => w && (w as Workspace).ws === wsId) ?? null;
    }

    function workspaceIndex(id: int): int {
        if (!Config.bar.workspaces.showUnoccupied)
            return wsIds.indexOf(id);

        let index = id - 1;
        while (index < 0)
            index += shown;
        return index % shown;
    }

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: workspaces.layoutHeight + workspaces.anchors.margins * 2

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
            opacity: Config.bar.workspaces.occupiedBg ? 1 : 0
            active: opacity > 0

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall

            sourceComponent: OccupiedBg {
                workspaces: root.workspaces
                wsSpacing: workspaces.spacing
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        AgentBg {
            anchors.fill: parent
            wsRoot: root
            list: workspaces
        }

        LazyListView {
            id: workspaces

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.extraSmall
            implicitHeight: contentHeight

            spacing: Tokens.spacing.extraSmall
            removeDuration: Tokens.anim.durations.expressiveDefaultEffects

            model: ScriptModel {
                values: root.wsIds
            }

            delegate: Workspace {
                activeWsId: root.activeWsId
                ws: Config.bar.workspaces.showUnoccupied ? root.groupOffset + index + 1 : modelData
                monitor: root.monitor

                displayType: Config.bar.workspaces.displayType
                showWindows: Config.bar.workspaces.showWindows
                iconRules: GlobalConfig.bar.workspaces.workspaceIcons
                activeLabel: Config.bar.workspaces.activeLabel
                occupiedLabel: Config.bar.workspaces.occupiedLabel
                label: Config.bar.workspaces.label
            }
        }

        Loader {
            asynchronous: true
            opacity: Config.bar.workspaces.showUnoccupied ? 0 : 1
            active: opacity > 0

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall

            sourceComponent: GapMarkers {
                workspaces: root.workspaces
                wsSpacing: workspaces.spacing
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        Loader {
            asynchronous: true
            anchors.left: workspaces.left
            anchors.right: workspaces.right
            active: Config.bar.workspaces.activeIndicator

            sourceComponent: ActiveIndicator {
                activeWs: {
                    workspaces.itemsDirty;
                    return workspaces.itemAtIndex(root.activeWsIdx) as Workspace;
                }
                mask: workspaces
            }
        }

        MouseArea {
            anchors.fill: workspaces
            onClicked: event => {
                const ws = (workspaces.itemAt(event.x, event.y) as Workspace)?.ws;
                if (!ws)
                    return;
                if (Hypr.activeWsId !== ws)
                    Hypr.focusWorkspace(ws);
                else
                    Hypr.toggleSpecial("special");
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

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: specialWs

        anchors.fill: parent

        asynchronous: true
        active: opacity > 0
        opacity: root.onSpecial ? 1 : 0

        sourceComponent: Item {
            StyledRect {
                anchors.fill: parent
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3scrim, Colours.light ? 0 : 0.2)
            }

            SpecialWorkspaces {
                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall
                monitor: root.monitor

                scale: 0.5
                Component.onCompleted: scale = Qt.binding(() => root.onSpecial ? 1 : 0.5)

                Behavior on scale {
                    Anim {}
                }
            }
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

    Behavior on implicitHeight {
        Anim {}
    }
}
