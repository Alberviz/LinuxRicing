pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.containers
import qs.services

// Diálogo que aparece si se desconecta el cable HDMI mientras la Tele estaba en uso:
// pregunta si pasar la sesión a Wi-Fi (Chromecast) o dejarla como workspace normal en el portátil.
Scope {
    id: scope

    LazyLoader {
        active: Tele.hdmiLostPrompt

        Variants {
            model: Screens.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData

                screen: modelData
                name: "tele-hotplug-dialog"

                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                visible: Hypr.monitorFor(win.modelData) === Hypr.focusedMonitor || win.modelData.name.startsWith("eDP")

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.5)
                }

                StyledRect {
                    anchors.centerIn: parent
                    width: 440
                    implicitHeight: col.implicitHeight + Tokens.padding.large * 2
                    radius: Tokens.rounding.extraLarge
                    color: Colours.palette.m3surfaceContainer
                    border.width: 1
                    border.color: Colours.palette.m3outlineVariant

                    ColumnLayout {
                        id: col

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.large
                        spacing: Tokens.spacing.medium

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.medium

                            MaterialIcon {
                                text: "cable"
                                fontStyle: Tokens.font.icon.large
                                color: Colours.palette.m3tertiary
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                StyledText {
                                    Layout.fillWidth: true
                                    text: qsTr("Cable HDMI desconectado")
                                    font: Tokens.font.title.medium
                                    color: Colours.palette.m3onSurface
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: qsTr("¿Quieres pasar la Tele al modo Wi-Fi (%1) o dejar las ventanas en un workspace normal del portátil?").arg(Tele.chromecastName)
                                    font: Tokens.font.body.small
                                    color: Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            TextButton {
                                Layout.fillWidth: true
                                text: qsTr("Dejar en portátil")
                                type: TextButton.Tonal
                                onClicked: Tele.answerHdmiLost(false)
                            }

                            TextButton {
                                Layout.fillWidth: true
                                text: qsTr("Pasar a Wi-Fi")
                                type: TextButton.Filled
                                onClicked: Tele.answerHdmiLost(true)
                            }
                        }
                    }
                }
            }
        }
    }
}
