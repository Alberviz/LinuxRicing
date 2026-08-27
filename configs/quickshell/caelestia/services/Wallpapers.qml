pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear
    // [claude-rgb-preview-patch] holds the colours JSON from the last wallpaper
    // preview, so the debounce timer below can push it to sync-rgb.py.
    property string lastPreviewColoursJson: ""
    // [claude-rgb-preview-patch] true for a few seconds after a real pick /
    // random, so closing the picker doesn't fight the confirmed postHook.
    property bool justSelected: false

    function getCategoryFor(w: FileSystemEntry): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setRandom(): void {
        root.justSelected = true;
        justSelectedTimer.restart();
        Quickshell.execDetached(["caelestia", "wallpaper", "-r", ...smartArg]);
    }

    function setWallpaper(path: string): void {
        actualCurrent = path;
        root.justSelected = true;
        justSelectedTimer.restart();
        Quickshell.execDetached(["caelestia", "wallpaper", "-f", path, ...smartArg]);
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;

        if (Colours.scheme === "dynamic")
            getPreviewColoursProc.running = true;
    }

    function stopPreview(): void {
        showPreview = false;
        previewSyncTimer.stop();
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;

        // [claude-rgb-preview-patch] the preview pushed a colour to the LEDs.
        // If the picker is closing WITHOUT a pick (Escape), nothing else will
        // restore them, so re-run sync-rgb.py with no args (reads the real
        // scheme.json). On a real pick the confirmed postHook already does it.
        if (root.lastPreviewColoursJson && !root.justSelected)
            rgbRestoreTimer.restart();
        root.lastPreviewColoursJson = "";
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: wallpapers.entries
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall) {
                wall = root.fallback;
                Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
            }
            root.actualCurrent = wall;
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
            Quickshell.execDetached(["caelestia", "wallpaper", "-f", root.fallback, ...root.smartArg]);
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
    }

    // [claude-rgb-preview-patch] debounced trigger so scrolling fast through
    // the wallpaper list doesn't spawn a sync-rgb.py process per keystroke.
    Timer {
        id: previewSyncTimer

        interval: 150
        onTriggered: {
            if (root.lastPreviewColoursJson)
                Quickshell.execDetached(["env", `SCHEME_COLOURS=${root.lastPreviewColoursJson}`, "python3", "/home/alberviz/.config/caelestia/sync-rgb.py", "--only", "openrgb,magichome,mchose_base,akko_keyboard"]);
        }
    }

    // [claude-rgb-preview-patch] restores the LEDs to the real scheme after a
    // cancelled preview. Delayed so any in-flight preview write lands first.
    Timer {
        id: rgbRestoreTimer

        interval: 400
        onTriggered: Quickshell.execDetached(["python3", "/home/alberviz/.config/caelestia/sync-rgb.py"])
    }

    Timer {
        id: justSelectedTimer

        interval: 3000
        onTriggered: root.justSelected = false
    }

    Process {
        id: getPreviewColoursProc

        command: ["caelestia", "wallpaper", "-p", root.previewPath, ...root.smartArg]
        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
                // [claude-rgb-preview-patch]
                root.lastPreviewColoursJson = JSON.stringify(JSON.parse(text).colours);
                previewSyncTimer.restart();
            }
        }
    }
}
