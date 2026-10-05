pragma ComponentBehavior: Bound

// TasksPanel — lista completa de tareas con filtros por repo y prioridad. Se abre
// al hacer clic en el cometa de tareas; clic fuera lo cierra.

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

Item {
    id: root

    property bool open: false
    property string repoFiltro: ""     // "" = todos
    property int prioMax: 5            // muestra prioridad <= prioMax
    signal closed()

    visible: open

    readonly property var lista: Tasks.tareas.filter(t =>
        (repoFiltro === "" || t.repo === repoFiltro) && t.prioridad <= prioMax)

    // Velo: clic fuera cierra.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closed()
        }
    }

    StyledRect {
        anchors.centerIn: parent
        width: Math.min(560, parent.width - 64)
        height: Math.min(parent.height - 96, col.implicitHeight + Tokens.padding.large * 2)
        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer

        // Absorbe los clics dentro del panel para que no lleguen al velo.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: col

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            StyledText {
                text: `${root.lista.length} de ${Tasks.pendientes} tareas`
                color: Colours.palette.m3primary
                font: Tokens.font.title.medium
            }

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: [""].concat(Tasks.repos.map(r => r.nombre))

                    delegate: StyledRect {
                        id: chip

                        required property string modelData

                        implicitWidth: chipLabel.implicitWidth + Tokens.padding.large
                        implicitHeight: chipLabel.implicitHeight + Tokens.padding.small
                        radius: Tokens.rounding.full
                        color: root.repoFiltro === modelData ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHigh

                        StyledText {
                            id: chipLabel

                            anchors.centerIn: parent
                            text: chip.modelData === "" ? "Todos" : chip.modelData
                            font: Tokens.font.label.small
                            color: root.repoFiltro === chip.modelData ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.repoFiltro = chip.modelData
                        }
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: [{ t: "Todas", v: 5 }, { t: "P1-P2", v: 2 }, { t: "P1-P3", v: 3 }]

                    delegate: StyledRect {
                        id: pchip

                        required property var modelData

                        implicitWidth: plabel.implicitWidth + Tokens.padding.large
                        implicitHeight: plabel.implicitHeight + Tokens.padding.small
                        radius: Tokens.rounding.full
                        color: root.prioMax === modelData.v ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHigh

                        StyledText {
                            id: plabel

                            anchors.centerIn: parent
                            text: pchip.modelData.t
                            font: Tokens.font.label.small
                            color: root.prioMax === pchip.modelData.v ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.prioMax = pchip.modelData.v
                        }
                    }
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.min(contentHeight, 420)
                clip: true
                spacing: Tokens.spacing.small
                model: root.lista

                delegate: TaskLine {
                    required property var modelData

                    width: ListView.view.width
                    mostrarRepo: true
                    tarea: modelData
                }
            }
        }
    }
}
