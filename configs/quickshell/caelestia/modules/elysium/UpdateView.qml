pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Caelestia.Config
import qs.components
import qs.services

// Pantalla de progreso de la actualización de Hookshot: anillo con el total, lista de
// etapas (hecha / en curso / pendiente), detalle de la etapa actual (descarga %,
// módulos compilados, tiempo restante) y, en los shaders, el aviso de que puede
// seguir en segundo plano. B = segundo plano · Y = cancelar · A = cerrar al terminar.
Item {
    id: root

    required property var elysium
    readonly property var u: elysium.upd
    readonly property bool shown: elysium.updView
    readonly property bool running: elysium.updRunning
    readonly property bool done: u.state === "done"
    readonly property bool failed: u.state === "error"
    readonly property color accent: Colours.palette.m3primary
    readonly property var stages: [
        ["download", qsTr("Descargar la versión nueva"), "download"],
        ["read", qsTr("Leer los archivos del juego"), "folder_open"],
        ["lift", qsTr("Traducir el juego a código de PC"), "translate"],
        ["compile", qsTr("Compilar"), "memory"],
        ["finish", qsTr("Montar la carpeta del juego"), "inventory_2"],
        ["shaders", qsTr("Precompilar shaders"), "deployed_code"]
    ]
    readonly property int curIdx: stages.findIndex(s => s[0] === u.stage)

    function fmtTime(sec: var): string {
        if (sec === null || sec === undefined || sec < 0)
            return "";
        if (sec < 60)
            return qsTr("~%1 s").arg(Math.round(sec));
        const m = Math.round(sec / 60);
        return m < 60 ? qsTr("~%1 min").arg(m) : qsTr("~%1 h %2 min").arg(Math.floor(m / 60)).arg(m % 60);
    }

    function detail(id: string): string {
        if (id !== u.stage)
            return "";
        if (id === "download")
            return qsTr("%1 %").arg(Math.round((u.stagePct ?? 0) * 100));
        if (id === "compile" && u.files)
            return qsTr("%1 de %2 módulos").arg(u.files[0]).arg(u.files[1]) + (u.eta ? "  ·  " + fmtTime(u.eta) : "");
        return qsTr("%1 %").arg(Math.round((u.stagePct ?? 0) * 100));
    }

    visible: opacity > 0.01
    opacity: shown ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutCubic
        }
    }

    // Velo: deja entrever el planeta.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.01, 0.01, 0.03, 0.94)
    }

    // ---------- anillo ----------
    Item {
        id: ring

        readonly property real d: Math.min(root.height * 0.46, 460)
        readonly property real pct: root.done ? 1 : (root.u.pct ?? 0)

        x: root.width * 0.12
        anchors.verticalCenter: parent.verticalCenter
        width: d
        height: d
        scale: root.shown ? 1 : 0.9

        Behavior on scale {
            NumberAnimation {
                duration: 600
                easing.type: Easing.OutBack
                easing.overshoot: 1.2
            }
        }

        property real shownPct: pct

        Behavior on shownPct {
            NumberAnimation {
                duration: 900
                easing.type: Easing.OutCubic
            }
        }

        // Aro exterior de trazos que gira despacio mientras trabaja.
        Shape {
            anchors.fill: parent
            anchors.margins: -26
            preferredRendererType: Shape.CurveRenderer
            opacity: root.running ? 0.5 : 0.18

            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 40000
                loops: Animation.Infinite
                running: root.shown && root.running
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(root.accent, 0.6)
                strokeWidth: 1.4
                strokeStyle: ShapePath.DashLine
                dashPattern: [2, 9]
                PathAngleArc {
                    centerX: ring.d / 2 + 26
                    centerY: ring.d / 2 + 26
                    radiusX: ring.d / 2 + 18
                    radiusY: ring.d / 2 + 18
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // pista
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(Colours.palette.m3onSurface, 0.08)
                strokeWidth: 10
                PathAngleArc {
                    centerX: ring.d / 2
                    centerY: ring.d / 2
                    radiusX: ring.d / 2 - 10
                    radiusY: ring.d / 2 - 10
                    startAngle: -90
                    sweepAngle: 360
                }
            }

            // halo del progreso
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(root.failed ? Colours.palette.m3error : root.accent, 0.18)
                strokeWidth: 26
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.d / 2
                    centerY: ring.d / 2
                    radiusX: ring.d / 2 - 10
                    radiusY: ring.d / 2 - 10
                    startAngle: -90
                    sweepAngle: Math.max(0.5, 360 * ring.shownPct)
                }
            }

            // progreso
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.failed ? Colours.palette.m3error : root.accent
                strokeWidth: 10
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.d / 2
                    centerY: ring.d / 2
                    radiusX: ring.d / 2 - 10
                    radiusY: ring.d / 2 - 10
                    startAngle: -90
                    sweepAngle: Math.max(0.5, 360 * ring.shownPct)
                }
            }
        }

        // Centro: porcentaje (o resultado).
        Column {
            anchors.centerIn: parent
            spacing: 6

            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.done || root.failed
                text: root.done ? "check_circle" : "error"
                color: root.done ? root.accent : Colours.palette.m3error
                fill: 1
                fontStyle: Tokens.font.icon.builders.medium.scale(3.6).build()
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: !root.done && !root.failed

                StyledText {
                    text: Math.floor(ring.shownPct * 100)
                    color: Colours.palette.m3onSurface
                    font.family: Tokens.font.title.large.family
                    font.pointSize: 64
                    font.weight: Font.Light
                }

                StyledText {
                    anchors.baseline: parent.children[0].baseline
                    text: "%"
                    color: Colours.palette.m3onSurfaceVariant
                    font.family: Tokens.font.title.large.family
                    font.pointSize: 26
                    font.weight: Font.Light
                }
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.done ? qsTr("Listo") : root.failed ? qsTr("Se detuvo") : (root.u.latest ? "Hookshot " + root.u.latest : "Hookshot")
                color: Colours.palette.m3onSurfaceVariant
                font.family: Tokens.font.label.small.family
                font.pointSize: 11
                font.letterSpacing: 2.5
                font.capitalization: Font.AllUppercase
            }
        }
    }

    // ---------- etapas ----------
    ColumnLayout {
        x: ring.x + ring.width + root.width * 0.08
        width: Math.min(root.width * 0.42, 720)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        StyledText {
            text: root.done ? qsTr("Hookshot está al día") : root.failed ? qsTr("La actualización se detuvo") : qsTr("Actualizando Hookshot")
            color: Colours.palette.m3onSurface
            font.family: Tokens.font.title.large.family
            font.pointSize: 34
            font.weight: Font.Light
        }

        StyledText {
            text: root.u.current && root.u.latest ? qsTr("%1  →  %2").arg(root.u.current).arg(root.u.latest) + (root.u.simulated ? qsTr("  ·  simulación") : "") : ""
            color: root.accent
            font: Tokens.font.title.small
        }

        Item {
            implicitHeight: 10
        }

        Repeater {
            model: root.stages

            RowLayout {
                id: row

                required property var modelData
                required property int index
                readonly property bool isDone: root.done || (root.curIdx >= 0 && index < root.curIdx)
                readonly property bool isCur: !root.done && index === root.curIdx

                Layout.fillWidth: true
                spacing: 16
                opacity: isDone || isCur ? 1 : 0.38

                Behavior on opacity {
                    NumberAnimation {
                        duration: 400
                    }
                }

                Item {
                    implicitWidth: 30
                    implicitHeight: 30

                    Rectangle {
                        anchors.fill: parent
                        radius: 15
                        color: row.isDone ? root.accent : "transparent"
                        border.width: 1.5
                        border.color: row.isCur ? (root.failed ? Colours.palette.m3error : root.accent) : Qt.alpha(Colours.palette.m3onSurface, row.isDone ? 0 : 0.3)

                        // Pulso de la etapa en curso.
                        Rectangle {
                            id: pulse

                            anchors.centerIn: parent
                            width: parent.width
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 1.5
                            border.color: root.accent
                            visible: row.isCur && root.running
                            opacity: 0

                            ParallelAnimation {
                                running: row.isCur && root.running && root.shown
                                loops: Animation.Infinite

                                NumberAnimation {
                                    target: pulse
                                    property: "scale"
                                    from: 1
                                    to: 1.7
                                    duration: 1400
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: pulse
                                    property: "opacity"
                                    from: 0.8
                                    to: 0
                                    duration: 1400
                                }
                            }
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: row.isDone ? "check" : row.modelData[2]
                        color: row.isDone ? Colours.palette.m3onPrimary : row.isCur ? root.accent : Colours.palette.m3onSurfaceVariant
                        fill: row.isDone ? 1 : 0
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true

                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData[1]
                            color: Colours.palette.m3onSurface
                            font: row.isCur ? Tokens.font.title.medium : Tokens.font.body.large
                        }

                        StyledText {
                            text: root.detail(row.modelData[0])
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.medium
                        }
                    }

                    // Barra de la etapa en curso.
                    Rectangle {
                        visible: row.isCur
                        Layout.fillWidth: true
                        implicitHeight: 3
                        radius: 2
                        color: Qt.alpha(Colours.palette.m3onSurface, 0.08)

                        Rectangle {
                            height: parent.height
                            radius: 2
                            color: root.failed ? Colours.palette.m3error : root.accent
                            width: parent.width * (root.u.stagePct ?? 0)

                            Behavior on width {
                                NumberAnimation {
                                    duration: 600
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }
                }
            }
        }

        // Aviso de shaders / error / hecho.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 16
            visible: root.u.stage === "shaders" || root.failed || root.done
            implicitHeight: note.implicitHeight + 32
            radius: 18
            color: Qt.alpha(root.failed ? Colours.palette.m3error : root.accent, 0.10)
            border.width: 1
            border.color: Qt.alpha(root.failed ? Colours.palette.m3error : root.accent, 0.35)

            RowLayout {
                id: note

                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                MaterialIcon {
                    text: root.failed ? "error" : root.done ? "sports_esports" : "deployed_code"
                    color: root.failed ? Colours.palette.m3error : root.accent
                    fill: 1
                    fontStyle: Tokens.font.icon.builders.medium.scale(1.5).build()
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.body.large
                    text: root.failed ? (root.u.error || qsTr("Algo falló.")) + qsTr("  Mira journalctl --user -u elysium-hookshot-update.") : root.done ? qsTr("Versión %1 instalada y shaders listos: el juego irá fluido desde el primer momento.").arg(root.u.latest ?? "") : qsTr("Se están precompilando los shaders para que el juego no dé tirones. Puedes dejarlo en segundo plano y seguir usando el PC: te aviso al terminar.")
                }
            }
        }
    }

    // ---------- pistas ----------
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 56
        spacing: 30

        HintRow {
            visible: root.running
            letter: "B"
            label: qsTr("Seguir en segundo plano")
        }

        HintRow {
            visible: root.running
            letter: "Y"
            label: qsTr("Cancelar")
        }

        HintRow {
            visible: !root.running
            letter: "A"
            label: qsTr("Cerrar")
        }
    }

    component HintRow: Row {
        property string letter
        property string label

        spacing: 10

        PadGlyph {
            anchors.verticalCenter: parent.verticalCenter
            letter: parent.letter
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: Colours.palette.m3onSurface
            font: Tokens.font.label.large
        }
    }
}
