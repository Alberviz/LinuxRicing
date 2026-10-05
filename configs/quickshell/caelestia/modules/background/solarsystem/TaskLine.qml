pragma ComponentBehavior: Bound

// TaskLine — una fila de tarea, compartida por el widget y el panel del cometa.
// Icono de estado (clic = pendiente → en curso → hecha), título (clic = abrir la
// nota en Obsidian), etiqueta de estado, prioridad y botón «hecha» directo.

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

RowLayout {
    id: root

    required property var tarea
    property bool mostrarRepo: false

    readonly property bool enCurso: tarea.estado === "en-curso"

    spacing: Tokens.spacing.small

    MaterialIcon {
        text: root.enCurso ? "play_circle" : "radio_button_unchecked"
        fontStyle: Tokens.font.icon.small
        color: root.enCurso ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Tasks.cambiarEstado(root.tarea, Tasks.siguienteEstado(root.tarea.estado))
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: root.tarea.titulo
        elide: Text.ElideRight
        color: root.enCurso ? Colours.palette.m3primary : Colours.palette.m3onSurface
        font: Tokens.font.label.medium

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Tasks.abrir(root.tarea)
        }
    }

    StyledText {
        text: `${root.mostrarRepo ? root.tarea.repo + " · " : ""}${Tasks.etiquetaEstado(root.tarea.estado)} · P${root.tarea.prioridad}`
        color: root.enCurso ? Colours.palette.m3primary : Colours.palette.m3outline
        font: Tokens.font.label.small
    }

    MaterialIcon {
        text: "check_circle"
        fontStyle: Tokens.font.icon.small
        color: Colours.palette.m3outline

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Tasks.marcarHecha(root.tarea)
        }
    }
}
