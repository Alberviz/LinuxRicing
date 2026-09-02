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

Variants {
    model: Screens.screens.filter(s => GlobalConfig.forScreen(s.name).background.enabled)

    StyledWindow {
        id: win

        required property ShellScreen modelData
        property bool transparentWidgets: true

        FileView {
            id: widgetConfigFile
            path: `${Quickshell.env("HOME")}/.config/caelestia/widgets-config.json`
            printErrors: false
            watchChanges: true
            onFileChanged: reload()
            onLoaded: {
                try {
                    const data = JSON.parse(text());
                    if (typeof data.transparent_widgets === "boolean") {
                        win.transparentWidgets = data.transparent_widgets;
                    }
                } catch (e) {}
            }
        }

        function toggleTransparency(): void {
            win.transparentWidgets = !win.transparentWidgets;
            const json = JSON.stringify({
                transparent_widgets: win.transparentWidgets
            }, null, 2) + "\n";
            widgetConfigFile.setText(json);
        }

        screen: modelData
        name: "background"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: contentItem.Config.background.wallpaperEnabled ? WlrLayer.Background : WlrLayer.Bottom
        color: contentItem.Config.background.wallpaperEnabled ? "black" : "transparent"
        surfaceFormat.opaque: false

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        ShellState.ComponentRef {
            screen: win.screen
            slot: "background"
            component: win
        }

        Item {
            id: behindClock

            anchors.fill: parent

            Loader {
                id: wallpaper

                asynchronous: true

                anchors.fill: parent
                active: Config.background.wallpaperEnabled

                sourceComponent: Wallpaper {}
            }

            DesktopCircularMedia {
                anchors.right: parent.right
                anchors.rightMargin: Math.max(80, Math.round((parent.width - 640 - width) / 2))
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Loader {
            id: clockLoader

            asynchronous: true
            active: Config.background.desktopClock.enabled
            width: item ? (item as Item).implicitWidth : implicitWidth
            height: item ? (item as Item).implicitHeight : implicitHeight

            anchors.margins: Tokens.padding.extraLargeIncreased
            anchors.leftMargin: Tokens.padding.extraLargeIncreased + Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness)

            state: Config.background.desktopClock.position
            states: [
                State {
                    name: "top-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "top-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "top-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "middle-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "middle-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "bottom-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "bottom-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "bottom-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                    }
                }
            ]

            transitions: Transition {
                AnchorAnim {}
            }

            sourceComponent: DesktopClock {
                wallpaper: behindClock
                absX: clockLoader.x
                absY: clockLoader.y
            }
        }

        Loader {
            id: peripheralsLoader

            asynchronous: false
            active: Config.background.desktopClock.enabled
            width: 640
            height: item ? (item as Item).implicitHeight : 0

            sourceComponent: DesktopPeripherals {
                transparentWidgets: win.transparentWidgets
                onToggleTransparencyRequested: win.toggleTransparency()
            }

            anchors.top: clockLoader.bottom
            anchors.topMargin: Tokens.spacing.extraLarge
            anchors.left: clockLoader.left
        }

        Loader {
            id: deckLoader

            asynchronous: false
            active: Config.background.desktopClock.enabled
            width: 640
            height: item ? (item as Item).implicitHeight : 0

            sourceComponent: DesktopWidgetDeck {
                transparentWidgets: win.transparentWidgets
            }

            anchors.top: peripheralsLoader.bottom
            anchors.topMargin: Tokens.spacing.large
            anchors.left: clockLoader.left
        }

        Loader {
            id: ledStripLoader

            asynchronous: false
            active: Config.background.desktopClock.enabled
            width: 640
            height: item ? (item as Item).implicitHeight : 0

            sourceComponent: DesktopLedStrip {
                transparentWidgets: win.transparentWidgets
            }

            anchors.top: deckLoader.bottom
            anchors.topMargin: Tokens.spacing.large
            anchors.left: clockLoader.left
        }
    }
}
