pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Hyprland
import Caelestia
import Caelestia.Config
import qs.components.misc
import qs.services
import qs.utils

Singleton {
    id: root

    property list<NotifData> list: []
    readonly property list<NotifData> notClosed: list.filter(n => !n.closed)
    readonly property list<NotifData> popups: list.filter(n => n.popup)
    property alias dnd: props.dnd

    property bool loaded

    function hasFullscreen(): bool {
        for (const monitor of Hypr.monitors.values) {
            if (monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1))
                return true;
        }
        return false;
    }

    function shouldShowPopup(): bool {
        if (props.dnd || ShellState.anySidebarOpen())
            return false;
        if (GlobalConfig.notifs.fullscreen === "off" && hasFullscreen())
            return false;
        return true;
    }

    function triggerAgentNotify(name: string, task: string, ws: int, addr: string): void {
        agentNotifyProcComp.createObject(root, {
            command: ["agent-notify", "notify", "-n", name, "-t", task, "-w", String(ws), "-a", addr || "0x1"],
            running: true
        });
    }

    Component {
        id: agentNotifyProcComp

        Process {
            onExited: destroy()
        }
    }

    onDndChanged: {
        if (!GlobalConfig.utilities.toasts.dndChanged)
            return;

        if (dnd)
            Toaster.toast(qsTr("Do not disturb enabled"), qsTr("Popup notifications are now disabled"), "do_not_disturb_on");
        else
            Toaster.toast(qsTr("Do not disturb disabled"), qsTr("Popup notifications are now enabled"), "do_not_disturb_off");
    }

    onListChanged: {
        if (loaded)
            saveTimer.restart();
    }

    Timer {
        id: saveTimer

        interval: 1000
        onTriggered: storage.setText(JSON.stringify(root.notClosed.map(n => ({
                    time: n.time,
                    id: n.id,
                    summary: n.summary,
                    body: n.body,
                    appIcon: n.appIcon,
                    appName: n.appName,
                    image: n.image,
                    expireTimeout: n.expireTimeout,
                    urgency: n.urgency,
                    resident: n.resident,
                    hasActionIcons: n.hasActionIcons,
                    actions: n.actions
                }))))
    }

    PersistentProperties {
        id: props

        property bool dnd

        reloadableId: "notifs"
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: notif => {
            notif.tracked = true;

            const app = (notif.appName || "").toLowerCase();
            const sum = (notif.summary || "").toLowerCase();
            const isNativeAgent = (app === "antigravity" || app === "agy" || app === "claude" || app === "claude code" ||
                                   sum.includes("antigravity") || sum.includes("claude code") || sum.includes("claude")) &&
                                  app !== "caelestia-agents";

            if (isNativeAgent) {
                notif.dismiss();

                const name = (app.includes("claude") || sum.includes("claude")) ? "Claude" : "Antigravity";
                const taskText = notif.body || notif.summary || "Tarea completada";

                let targetAddr = "";
                let targetWs = 1;
                const pid = notif.hints?.["sender-pid"] ?? notif.hints?.pid;
                if (pid) {
                    const tlByPid = Hyprland.toplevels.values.find(tl => tl.pid === Number(pid));
                    if (tlByPid) {
                        targetAddr = tlByPid.address;
                        targetWs = tlByPid.workspace?.id || 1;
                    }
                }

                if (!targetAddr) {
                    const terminals = Hyprland.toplevels.values.filter(tl => {
                        const cls = (tl.class || "").toLowerCase();
                        return cls.includes("kitty") || cls.includes("foot") || cls.includes("alacritty") || cls.includes("wezterm") || cls.includes("terminal");
                    });
                    if (terminals.length > 0) {
                        const activeTl = Hyprland.activeToplevel;
                        const activeIsTerm = terminals.find(t => t.address === activeTl?.address);
                        const chosen = activeIsTerm || terminals[0];
                        targetAddr = chosen.address;
                        targetWs = chosen.workspace?.id || Hypr.activeWsId || 1;
                    } else {
                        targetWs = Hypr.activeWsId || 1;
                    }
                }

                root.triggerAgentNotify(name, taskText, targetWs, targetAddr);
                return;
            }

            const comp = notifComp.createObject(root, {
                popup: root.shouldShowPopup(),
                notification: notif
            });
            root.list = [comp, ...root.list];
        }
    }

    FileView {
        id: storage

        printErrors: false
        path: `${Paths.state}/notifs.json`
        onLoaded: {
            const data = JSON.parse(text());
            for (const notif of data) {
                const properties = Object.assign({}, notif);

                // Backwards compatibility for old notifications
                if (properties.notificationId === undefined && properties.id !== undefined)
                    properties.notificationId = properties.id;

                delete properties.id;
                root.list.push(notifComp.createObject(root, properties));
            }
            root.list.sort((a, b) => b.time - a.time);
            root.loaded = true;
        }
        onLoadFailed: err => {
            if (err === FileViewError.FileNotFound) {
                root.loaded = true;
                Qt.callLater(() => setText("[]"));
            }
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "clearNotifs"
        description: "Clear all notifications"
        onPressed: {
            for (const notif of root.list.slice())
                notif.close();
        }
    }

    IpcHandler {
        function clear(): void {
            for (const notif of root.list.slice())
                notif.close();
        }

        function isDndEnabled(): bool {
            return props.dnd;
        }

        function toggleDnd(): void {
            props.dnd = !props.dnd;
        }

        function enableDnd(): void {
            props.dnd = true;
        }

        function disableDnd(): void {
            props.dnd = false;
        }

        target: "notifs"
    }

    Component {
        id: notifComp

        NotifData {}
    }
}
