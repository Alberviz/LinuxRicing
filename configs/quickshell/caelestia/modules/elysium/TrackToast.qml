pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.services

// Píldora discreta abajo a la izquierda de la pantalla del juego cuando cambia la canción.
// 4 s, entra deslizando desde la izquierda. Sin foco de teclado ni robo de clics.
PanelWindow {
    id: win

    required property var elysium
    readonly property bool shown: elysium.trackToastVisible
    readonly property color accent: Colours.palette.m3primary

    screen: elysium.consoleScreen
    visible: shown || pill.opacity > 0.01
    color: "transparent"
    WlrLayershell.namespace: "caelestia-elysium-track-toast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors.bottom: true
    anchors.left: true
    implicitWidth: 460
    implicitHeight: 112

    // Puramente informativo: deja pasar todos los clics.
    mask: Region {}

    Rectangle {
        id: pill

        anchors.bottom: parent.bottom
        anchors.bottomMargin: 36
        x: win.shown ? 36 : -width - 40
        width: Math.min(390, Math.max(220, row.implicitWidth + 28))
        height: 68
        radius: 22
        color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.92)
        border.width: 1
        border.color: Qt.alpha(win.accent, 0.35)
        opacity: win.shown ? 1 : 0
        clip: true

        Behavior on x {
            NumberAnimation {
                duration: 380
                easing.type: Easing.OutExpo
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: 280
                easing.type: Easing.OutCubic
            }
        }

        RowLayout {
            id: row

            anchors.fill: parent
            anchors.margins: 10
            spacing: 12

            StyledClippingRect {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                radius: 14
                color: Qt.alpha(Colours.palette.m3onSurface, 0.06)

                Image {
                    id: art

                    anchors.fill: parent
                    source: win.elysium.trackArtUrl
                    sourceSize.width: 96
                    sourceSize.height: 96
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                    asynchronous: true
                    visible: status === Image.Ready
                }

                Item {
                    anchors.fill: parent
                    visible: art.status !== Image.Ready

                    Rectangle {
                        anchors.centerIn: parent
                        width: 38
                        height: 38
                        radius: 19
                        color: Qt.tint("#0a0c14", Qt.alpha(win.accent, 0.16))
                        border.width: 1
                        border.color: Qt.alpha(win.accent, 0.5)

                        Rectangle {
                            anchors.centerIn: parent
                            width: 12
                            height: 12
                            radius: 6
                            color: Qt.alpha(win.accent, 0.35)
                            border.width: 1
                            border.color: win.accent
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: win.elysium.trackTitle
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.title.small
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: win.elysium.trackArtist
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }
            }
        }
    }
}
