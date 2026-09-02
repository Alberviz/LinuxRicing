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

ColumnLayout {
    id: root

    // Referencia al DesktopWidgetDeck dueño de los datos y las acciones.
    required property var deck

    spacing: Tokens.spacing.small

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        StyledText {
            text: root.deck.listTitle
            color: Colours.palette.m3primary
            font: Tokens.font.title.small
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        StyledRect {
            readonly property int pendingCount: (root.deck.taskItems || []).filter(t => !t.completed).length
            radius: Tokens.rounding.full
            color: Colours.palette.m3primaryContainer
            implicitWidth: pendingLabel.implicitWidth + Tokens.padding.medium
            implicitHeight: pendingLabel.implicitHeight + Tokens.padding.extraSmall

            StyledText {
                id: pendingLabel
                anchors.centerIn: parent
                text: `${parent.pendingCount} pendientes`
                color: Colours.palette.m3onPrimaryContainer
                font: Tokens.font.label.small
            }
        }

        StyledRect {
            implicitWidth: 28
            implicitHeight: 28
            radius: Tokens.rounding.full
            color: (root.deck.transparentWidgets ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.4) : Colours.palette.m3surfaceContainerHigh)

            MaterialIcon {
                id: tasksRefreshIcon
                anchors.centerIn: parent
                text: "refresh"
                fontStyle: Tokens.font.icon.small
                color: root.deck.isSyncing ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

                // Spin only while an actual sync is in flight, then stop.
                RotationAnimator {
                    target: tasksRefreshIcon
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    running: root.deck.isSyncing
                    onRunningChanged: if (!running) tasksRefreshIcon.rotation = 0
                }
            }

            StateLayer {
                radius: Tokens.rounding.full
                onClicked: root.deck.refreshTasks()
            }
        }
    }

    Repeater {
        model: (root.deck.taskItems || []).slice(0, 4)
        TaskRow {
            Layout.fillWidth: true
            transparentWidgets: root.deck.transparentWidgets
            onToggled: root.deck.toggleLocalTask(modelData.id)
        }
    }

    StyledText {
        visible: (root.deck.taskItems?.length ?? 0) === 0
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        Layout.bottomMargin: Tokens.spacing.small
        text: root.deck.isAuthenticated ? "No hay tareas pendientes ✨" : "Cargando tareas..."
        color: Colours.palette.m3onSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        font: Tokens.font.body.medium
    }
}
