pragma ComponentBehavior: Bound

// TasksWidget — tareas de todos los repos, debajo del reloj del escritorio.
// PLEGADO (por defecto): solo «TAREAS» con el recuento y una flecha, en la misma
// tipografía de instrumento que las etiquetas del sistema solar. Un clic lo despliega:
// lista agrupada por repo con TaskLine (estado, título, prioridad), botón de
// transparencia y botón que abre «Hoy» en Obsidian. Sin animaciones: solo se repinta
// cuando cambia Tasks (cada 30 s como mucho) o al plegar/desplegar.

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
    readonly property bool abierto: Tasks.widgetExpandido
    readonly property int enCurso: Tasks.tareas.filter(t => t.estado === "en-curso").length

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

    visible: Tasks.tareas.length > 0
    implicitWidth: abierto ? 420 : head.implicitWidth + Tokens.padding.large * 2
    implicitHeight: col.implicitHeight + Tokens.padding.large * 2
    radius: Tokens.rounding.large
    // Plegado: sin tarjeta, solo texto. Desplegado: tarjeta, salvo en modo transparente.
    color: abierto && !Tasks.widgetTransparente ? Qt.alpha(Colours.palette.m3surfaceContainer, 0.94) : "transparent"

    ColumnLayout {
        id: col

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            id: head

            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            // Título + recuento + flecha: todo el bloque pliega/despliega.
            RowLayout {
                spacing: Tokens.spacing.small

                StyledText {
                    text: "TAREAS"
                    color: Colours.palette.m3primary
                    font.family: Tokens.font.mono.small.family
                    font.pixelSize: 13
                    font.letterSpacing: 3
                }

                StyledText {
                    text: root.enCurso > 0 ? `${Tasks.pendientes} · ${root.enCurso} EN CURSO` : `${Tasks.pendientes}`
                    color: Colours.palette.m3outline
                    font.family: Tokens.font.mono.small.family
                    font.pixelSize: 11
                    font.letterSpacing: 2
                }

                MaterialIcon {
                    text: root.abierto ? "expand_less" : "expand_more"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3outline
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Tasks.setWidgetExpandido(!root.abierto)
                }
            }

            Item {
                Layout.fillWidth: true
            }

            StyledRect {
                visible: root.abierto
                implicitWidth: 28
                implicitHeight: 28
                radius: Tokens.rounding.full
                color: Colours.palette.m3surfaceContainerHigh

                MaterialIcon {
                    anchors.centerIn: parent
                    text: Tasks.widgetTransparente ? "opacity" : "blur_on"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurface
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Tasks.setWidgetTransparente(!Tasks.widgetTransparente)
                }
            }

            StyledRect {
                visible: root.abierto
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
                    onClicked: Tasks.abrirHoy()
                }
            }
        }

        Repeater {
            model: root.abierto ? root.filas : []

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

                TaskLine {
                    visible: !item.esGrupo
                    Layout.fillWidth: true
                    tarea: item.esGrupo ? ({ titulo: "", estado: "pendiente", prioridad: 0, repo: "" }) : item.modelData.t
                }
            }
        }

        StyledText {
            visible: root.abierto && root.extra > 0
            text: `+${root.extra} más (clic en el cometa)`
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
        }
    }
}
