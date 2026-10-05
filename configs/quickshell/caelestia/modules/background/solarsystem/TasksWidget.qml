pragma ComponentBehavior: Bound

// TasksWidget — tareas de todos los repos, abajo a la derecha del escritorio.
// Variante A de la maqueta: agrupadas por repo. Sin animaciones: solo se repinta
// cuando cambia Tasks (cada 30 s como mucho). Casilla = marcar hecha; clic en el
// título = abrir la nota en Obsidian; el botón de la cabecera abre la nota «Hoy».

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property int maxRows: 8
    readonly property int extra: Math.max(0, Tasks.tareas.length - maxRows)

    // Filas: cabecera de repo ({grupo}) seguida de sus tareas ({t}).
    readonly property var filas: {
        const sh = Tasks.tareas.slice(0, maxRows);
        const repos = [];
        for (const t of sh)
            if (!repos.includes(t.repo))
                repos.push(t.repo);
        const out = [];
        for (const r of repos) {
            out.push({ grupo: r });
            for (const t of sh)
                if (t.repo === r)
                    out.push({ t: t });
        }
        return out;
    }

    function abrirObsidian(): void {
        Quickshell.execDetached(["xdg-open", "obsidian://open?vault=vault&file=%F0%9F%8E%AF%20Hoy"]);
    }

    visible: Tasks.tareas.length > 0
    implicitWidth: 360
    implicitHeight: col.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.large
    color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.82)

    ColumnLayout {
        id: col

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: `${Tasks.pendientes} tareas`
                color: Colours.palette.m3primary
                font: Tokens.font.title.small
            }

            StyledRect {
                implicitWidth: 28
                implicitHeight: 28
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHigh

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "open_in_new"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurface
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.abrirObsidian()
                }
            }
        }

        Repeater {
            model: root.filas

            delegate: ColumnLayout {
                id: item

                required property var modelData
                readonly property bool esGrupo: modelData.grupo !== undefined

                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    visible: item.esGrupo
                    Layout.topMargin: Tokens.spacing.small
                    text: item.esGrupo ? item.modelData.grupo.toUpperCase() : ""
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }

                RowLayout {
                    visible: !item.esGrupo
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "check_box_outline_blank"
                        fontStyle: Tokens.font.icon.small
                        color: Colours.palette.m3onSurfaceVariant

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Tasks.marcarHecha(item.modelData.t)
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: item.esGrupo ? "" : item.modelData.t.titulo
                        elide: Text.ElideRight
                        color: !item.esGrupo && item.modelData.t.estado === "en-curso" ? Colours.palette.m3primary : Colours.palette.m3onSurface
                        font: Tokens.font.label.medium

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Tasks.abrir(item.modelData.t)
                        }
                    }

                    StyledText {
                        text: item.esGrupo ? "" : `P${item.modelData.t.prioridad}`
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        StyledText {
            visible: root.extra > 0
            text: `+${root.extra} más (clic en el cometa)`
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
        }
    }
}
