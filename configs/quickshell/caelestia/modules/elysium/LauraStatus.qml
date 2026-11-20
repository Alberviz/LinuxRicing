pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Estado del daemon de Laura de un vistazo: icono, texto de fase, barra de progreso
// y tiempo restante mientras arranca o se apaga. `compact` = una sola línea (chip).
ColumnLayout {
    id: root

    property bool compact: false
    property real barWidth: 360
    readonly property string st: LauraService.state
    readonly property color tone: st === "on" ? Colours.palette.m3primary : st === "error" ? Colours.palette.m3error : st === "off" ? Colours.palette.m3outline : Colours.palette.m3tertiary

    spacing: 8

    RowLayout {
        spacing: 8

        Rectangle {
            implicitWidth: root.compact ? 8 : 10
            implicitHeight: implicitWidth
            radius: implicitWidth / 2
            color: root.tone

            SequentialAnimation on opacity {
                running: LauraService.busy
                loops: Animation.Infinite
                onRunningChanged: if (!running)
                    parent.opacity = 1
                NumberAnimation {
                    to: 0.25
                    duration: 500
                }
                NumberAnimation {
                    to: 1
                    duration: 500
                }
            }
        }

        StyledText {
            text: ({
                    "on": qsTr("Laura lista"),
                    "off": qsTr("Laura apagada"),
                    "starting": root.compact ? qsTr("Laura %1%").arg(Math.round(LauraService.progress * 100)) : qsTr("Encendiendo Laura"),
                    "stopping": qsTr("Apagando Laura"),
                    "error": qsTr("Laura: error")
                })[root.st] ?? root.st
            color: root.st === "off" ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
            font: root.compact ? Tokens.font.label.large : Tokens.font.title.small
        }

        StyledText {
            visible: LauraService.busy && LauraService.eta > 0
            text: qsTr("· ~%1 s").arg(LauraService.eta)
            color: Colours.palette.m3onSurfaceVariant
            font: root.compact ? Tokens.font.label.large : Tokens.font.body.medium
        }
    }

    // Detalle (no compacto): fase actual + barra.
    StyledText {
        visible: !root.compact && (LauraService.busy || root.st === "error")
        Layout.preferredWidth: root.barWidth
        text: LauraService.phase
        color: root.st === "error" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.medium
        wrapMode: Text.WordWrap
    }

    Rectangle {
        visible: !root.compact && LauraService.busy
        Layout.preferredWidth: root.barWidth
        implicitHeight: 4
        radius: 2
        color: Qt.alpha(Colours.palette.m3onSurface, 0.1)

        Rectangle {
            height: parent.height
            radius: 2
            color: root.tone
            width: parent.width * (LauraService.state === "stopping" ? 1 - LauraService.progress : LauraService.progress)

            Behavior on width {
                NumberAnimation {
                    duration: 700
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
