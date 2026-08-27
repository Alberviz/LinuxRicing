pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    signal close

    property int tab: 0
    readonly property var tabs: [qsTr("Inicio"), qsTr("Dispositivos"), qsTr("Notificaciones")]

    implicitWidth: 560
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.extraLarge
    color: Colours.palette.m3surfaceContainer

    // Swallow clicks so they don't reach the backdrop dismiss handler.
    MouseArea {
        anchors.fill: parent
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.large

        // Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: "colors"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.normal
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Centro de Iluminación")
                font: Tokens.font.title.small
                color: Colours.palette.m3onSurface
            }

            StyledRect {
                implicitWidth: 30
                implicitHeight: 30
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.6)

                StateLayer {
                    radius: Tokens.rounding.full
                    onClicked: root.close()
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "close"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                }
            }
        }

        // Tab bar
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 46
            radius: height / 2
            color: Qt.alpha(Colours.palette.m3surfaceContainerLowest, 0.55)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 5
                spacing: 5

                Repeater {
                    model: root.tabs

                    StyledRect {
                        id: tabBtn

                        required property int index
                        required property string modelData
                        readonly property bool active: root.tab === index

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: height / 2
                        color: active ? Colours.palette.m3secondaryContainer : "transparent"

                        Behavior on color {
                            CAnim {}
                        }

                        StateLayer {
                            radius: parent.radius
                            onClicked: root.tab = tabBtn.index
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: tabBtn.modelData
                            font: tabBtn.active ? Tokens.font.label.large : Tokens.font.label.medium
                            color: tabBtn.active ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }
        }

        // Tab content
        StackLayout {
            Layout.fillWidth: true
            currentIndex: root.tab

            component Placeholder: StyledRect {
                property string label

                Layout.fillWidth: true
                implicitHeight: 160
                radius: Tokens.rounding.large
                color: Colours.palette.m3surfaceContainerHigh

                StyledText {
                    anchors.centerIn: parent
                    text: qsTr("%1 · próximamente").arg(parent.label)
                    font: Tokens.font.body.medium
                    color: Colours.palette.m3onSurfaceVariant
                }
            }

            InicioView {
                Layout.fillWidth: true
            }
            DispositivosView {
                Layout.fillWidth: true
            }
            NotificacionesView {
                Layout.fillWidth: true
            }
        }

        // Footer
        StyledRect {
            Layout.fillWidth: true
            implicitHeight: 44
            radius: Tokens.rounding.full
            color: Colours.palette.m3primary

            StateLayer {
                radius: Tokens.rounding.full
                color: Colours.palette.m3onPrimary
                onClicked: RgbConfig.apply()
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "done"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onPrimary
                }
                StyledText {
                    text: qsTr("Aplicar ahora")
                    font: Tokens.font.label.large
                    color: Colours.palette.m3onPrimary
                }
            }
        }
    }
}
