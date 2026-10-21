pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Tarjeta del tablero (propuesta C): compacta (media columna) con título,
// resumen de 2 líneas y la jerarquía agente · estado · tiempo; se expande a
// ancho completo al pulsarla. Las que esperan un OK van siempre expandidas, en
// ámbar, con la vista previa del evento o del borrador. Lo que Laura hace por su
// cuenta lleva tono terciario, borde discontinuo y campana.
Item {
    id: card

    required property string jid
    // Ancho útil de la rejilla y reloj en segundos (los pone el cajón)
    property real flowW: 540
    property real nowSec: Date.now() / 1000
    property real clock: 0
    property bool open: false
    property bool flash: false

    readonly property var job: Laura.jobs.find(j => j.id === jid) ?? ({})
    readonly property string kind: job.kind ?? "running"
    readonly property string destino: job.destino ?? "laura"
    readonly property bool aviso: Laura.isAviso(job)
    readonly property bool cfm: kind === "confirm"
    readonly property bool isEvt: !!job.evento
    readonly property bool isMail: !!job.correo
    readonly property bool final: kind === "done" || kind === "fail"
    readonly property bool wide: cfm || open || (isEvt && (kind === "done" || kind === "agent"))
    readonly property color agentCol: Laura.agentColor(aviso ? "laura" : destino)
    readonly property color tert: Colours.palette.m3tertiary
    readonly property color okCol: "#6fdcb4"
    readonly property color stCol: cfm ? Laura.cWait : kind === "fail" ? Laura.cFail : aviso ? tert : agentCol

    readonly property string stLabel: {
        switch (kind) {
        case "running":
            return "En curso";
        case "agent":
            return isEvt ? "Creando…" : "En espera";
        case "confirm":
            return "Necesita tu OK";
        case "done":
            return aviso ? "Aviso" : isEvt ? "Creado" : "Hecho";
        case "fail":
            return "Fallido";
        }
        return "Cancelado";
    }
    function _fmt(s: real): string {
        s = Math.max(0, Math.round(s));
        return s < 60 ? s + " s" : s < 3600 ? Math.round(s / 60) + " min" : Math.round(s / 3600) + " h";
    }
    readonly property string timeLabel: {
        const inicio = job.inicio ?? nowSec;
        if (final) {
            const fin = job.fin ?? nowSec;
            return nowSec - fin < 4 ? "ahora" : "hace " + _fmt(nowSec - fin);
        }
        return kind === "cancel" ? "" : _fmt(nowSec - inicio);
    }
    readonly property string heading: cfm && (job.pregunta ?? "").length > 0 ? job.pregunta.split("\n")[0] : (job.titulo ?? "")
    readonly property string sub: {
        if (kind === "running")
            return "Trabajando…";
        if (kind === "agent")
            return isEvt ? "Creando el evento en Calendar" : "Esperando a " + Laura.agentName(destino);
        return job.resumen ?? "";
    }
    readonly property string noteName: (job.nota ?? "").split("/").pop()

    function openNote(): void {
        if (job.nota)
            Quickshell.execDetached(["xdg-open", "obsidian://open?path=" + encodeURIComponent(job.nota)]);
    }
    function openUrl(): void {
        const f = job.fuentes ?? [];
        if (f.length > 0 && f[0].url)
            Quickshell.execDetached(["xdg-open", f[0].url]);
    }

    // Una columna = (flowW - gap) / 2
    implicitWidth: wide ? flowW : (flowW - 9) / 2
    implicitHeight: body.implicitHeight
    Behavior on implicitWidth {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    // entrada de una tarjeta nueva (una sola vez)
    opacity: 0
    scale: 0.96
    Component.onCompleted: pop.start()
    ParallelAnimation {
        id: pop

        NumberAnimation {
            target: card
            property: "opacity"
            to: 1
            duration: 300
        }
        NumberAnimation {
            target: card
            property: "scale"
            to: 1
            duration: 380
            easing.type: Easing.OutBack
        }
    }

    onFlashChanged: if (flash)
        flashT.restart()
    Timer {
        id: flashT

        interval: 1500
        onTriggered: card.flash = false
    }

    component Btn: Rectangle {
        id: btn

        property string label
        property color tone: Colours.palette.m3onSurface
        property bool primary: false
        property bool solid: false
        property bool enable: true
        signal activated

        implicitWidth: t.implicitWidth + 20
        implicitHeight: 28
        radius: 9
        color: solid ? tone : primary ? Qt.alpha(tone, 0.22) : (ma.containsMouse && enable ? Colours.palette.m3surfaceContainerHigh : "transparent")
        border.width: primary || solid ? 0 : 1
        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.14)
        opacity: enable ? 1 : 0.35

        StyledText {
            id: t

            anchors.centerIn: parent
            text: btn.label
            color: btn.solid ? "#2a1d00" : btn.tone
            font.family: Tokens.font.label.small.family
            font.pixelSize: Tokens.font.label.small.pixelSize
            font.bold: btn.solid
        }
        MouseArea {
            id: ma

            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enable
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }
    }

    Rectangle {
        id: body

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: col.implicitHeight + (card.cfm ? 26 : 21)
        radius: 16
        clip: true
        color: card.cfm ? Qt.tint(Colours.palette.m3surfaceContainer, Qt.alpha(Laura.cWait, 0.16)) : card.kind === "fail" ? Qt.tint(Colours.palette.m3surfaceContainer, Qt.alpha(Laura.cFail, 0.1)) : card.aviso ? Qt.tint(Colours.palette.m3surfaceContainer, Qt.alpha(card.tert, 0.09)) : (hover.containsMouse ? Colours.palette.m3surfaceContainerHigh : Colours.palette.m3surfaceContainer)
        opacity: card.kind === "cancel" ? 0.5 : 1
        border.width: 1.5
        border.color: card.flash ? card.agentCol : card.cfm ? Qt.alpha(Laura.cWait, 0.75) : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 600
            }
        }

        MouseArea {
            id: hover

            anchors.fill: parent
            hoverEnabled: true
            enabled: !card.cfm
            cursorShape: Qt.PointingHandCursor
            onClicked: card.open = !card.open
        }

        // borde discontinuo (avisos del vigía)
        Shape {
            anchors.fill: parent
            visible: card.aviso
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.alpha(card.tert, 0.65)
                strokeWidth: 1.5
                strokeStyle: ShapePath.DashLine
                dashPattern: [4, 3]
                PathRectangle {
                    x: 1
                    y: 1
                    width: body.width - 2
                    height: body.height - 2
                    radius: 15
                }
            }
        }

        // cinta «Por su cuenta»
        Rectangle {
            visible: card.aviso
            anchors.right: parent.right
            anchors.top: parent.top
            width: ribT.implicitWidth + 19
            height: ribT.implicitHeight + 6
            color: card.tert
            topRightRadius: 15
            bottomLeftRadius: 11

            StyledText {
                id: ribT

                anchors.centerIn: parent
                text: "🔔 POR SU CUENTA"
                color: Colours.palette.m3surface
                font.pixelSize: 10
                font.weight: Font.ExtraBold
                font.letterSpacing: 0.8
            }
        }

        ColumnLayout {
            id: col

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: card.aviso ? 20 : card.cfm ? 13 : 11
            spacing: card.cfm ? 9 : 6

            // título con glifo del agente
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: card.cfm ? 30 : 24
                    Layout.preferredHeight: width
                    radius: width / 2
                    color: Qt.alpha(card.agentCol, 0.2)

                    AgentGlyph {
                        anchors.centerIn: parent
                        agent: card.aviso ? "aviso" : card.destino
                        color: card.agentCol
                        size: card.cfm ? 17 : 14
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: card.heading
                    wrapMode: Text.Wrap
                    maximumLineCount: card.cfm ? 3 : (card.open ? 4 : 2)
                    elide: Text.ElideRight
                    font.pixelSize: card.cfm ? 16 : 13.5
                    font.weight: card.cfm ? Font.DemiBold : Font.DemiBold
                }
                Rectangle {
                    visible: card.cfm
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: okT.implicitWidth + 16
                    Layout.preferredHeight: okT.implicitHeight + 4
                    radius: height / 2
                    color: Qt.alpha(Laura.cWait, 0.2)

                    StyledText {
                        id: okT

                        anchors.centerIn: parent
                        text: "● OK"
                        color: Laura.cWait
                        font.family: Tokens.font.label.small.family
                        font.pixelSize: Tokens.font.label.small.pixelSize
                        font.bold: true
                    }
                }
            }

            // línea agente · tiempo (solo confirmación)
            StyledText {
                Layout.fillWidth: true
                visible: card.cfm
                text: Laura.agentName(card.destino) + " · " + card.timeLabel + (card.job.titulo ? " · " + card.job.titulo : "")
                elide: Text.ElideRight
                color: Colours.palette.m3onSurfaceVariant
                font.pixelSize: 13
            }

            // vista previa: evento o borrador
            EventPreview {
                Layout.fillWidth: true
                visible: card.isEvt && card.kind !== "cancel" && card.kind !== "fail" && (card.cfm || card.open || card.kind === "agent" || card.kind === "done")
                ev: card.job.evento ?? ({})
                created: card.kind === "done"
                full: card.open
            }
            MailPreview {
                Layout.fillWidth: true
                visible: card.isMail && card.cfm
                mail: card.job.correo ?? ({})
                full: card.open
            }
            // pregunta cuando no hay datos estructurados
            StyledText {
                Layout.fillWidth: true
                visible: card.cfm && !card.isEvt && !card.isMail && (card.job.pregunta ?? "").length > 0 && card.heading !== card.job.pregunta
                text: card.job.pregunta ?? ""
                wrapMode: Text.Wrap
                color: Colours.palette.m3onSurface
                font.pixelSize: 13
            }

            // resumen (2 líneas compacta; completo si está abierta)
            StyledText {
                Layout.fillWidth: true
                visible: !card.cfm && text.length > 0 && !(card.isEvt && (card.open || card.kind === "done" || card.kind === "agent"))
                text: card.sub
                wrapMode: Text.Wrap
                maximumLineCount: card.open ? 12 : 2
                elide: Text.ElideRight
                color: card.open ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                font.pixelSize: 13
                lineHeight: 1.05
            }

            // barra de progreso indeterminada (en curso / espera): se mueve solo con el cajón visible
            Rectangle {
                Layout.fillWidth: true
                visible: card.kind === "running" || card.kind === "agent"
                implicitHeight: 3
                radius: 2
                color: Qt.alpha(card.agentCol, 0.2)
                clip: true

                Rectangle {
                    width: parent.width * 0.3
                    height: parent.height
                    radius: 2
                    color: card.agentCol
                    x: -width + (parent.width + width) * ((card.clock * 0.6) % 1)
                }
            }

            // detalles al expandir: fuentes y nota
            Flow {
                Layout.fillWidth: true
                spacing: 5
                visible: card.open && !card.cfm && ((card.job.fuentes ?? []).length > 0 || card.noteName.length > 0)

                Repeater {
                    model: card.open ? (card.job.fuentes ?? []) : []

                    Rectangle {
                        id: src

                        required property var modelData

                        implicitWidth: Math.min(card.flowW - 40, srcT.implicitWidth + 22)
                        implicitHeight: srcT.implicitHeight + 7
                        radius: 8
                        color: srcMa.containsMouse ? Colours.palette.m3surfaceContainerHighest : Colours.palette.m3surfaceContainerHigh

                        StyledText {
                            id: srcT

                            anchors.verticalCenter: parent.verticalCenter
                            x: 9
                            width: parent.width - 18
                            elide: Text.ElideRight
                            text: "↗ " + (src.modelData.titulo || src.modelData.url || "")
                            font: Tokens.font.label.small
                        }
                        MouseArea {
                            id: srcMa

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !!src.modelData.url
                            onClicked: Quickshell.execDetached(["xdg-open", src.modelData.url])
                        }
                    }
                }
                // nota como chip con el nombre del fichero
                Rectangle {
                    visible: card.noteName.length > 0
                    implicitWidth: Math.min(card.flowW - 40, noteT.implicitWidth + 22)
                    implicitHeight: noteT.implicitHeight + 7
                    radius: 8
                    color: Qt.alpha(card.agentCol, noteMa.containsMouse ? 0.3 : 0.18)

                    StyledText {
                        id: noteT

                        anchors.verticalCenter: parent.verticalCenter
                        x: 9
                        width: parent.width - 18
                        elide: Text.ElideRight
                        text: "▤ " + card.noteName
                        color: card.agentCol
                        font: Tokens.font.mono.small
                    }
                    MouseArea {
                        id: noteMa

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.openNote()
                    }
                }
            }

            // pie compacto: estado · tiempo (· descartar)
            RowLayout {
                Layout.fillWidth: true
                visible: !card.cfm
                spacing: 6

                Rectangle {
                    Layout.preferredWidth: stT.implicitWidth + 16
                    Layout.preferredHeight: stT.implicitHeight + 4
                    radius: height / 2
                    color: Qt.alpha(card.stCol, 0.18)

                    StyledText {
                        id: stT

                        anchors.centerIn: parent
                        text: card.stLabel
                        color: card.stCol
                        font: Tokens.font.label.small
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                StyledText {
                    text: card.timeLabel
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }
                StyledText {
                    visible: card.aviso && !card.open
                    text: "✕"
                    color: dMa.containsMouse ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    font.pixelSize: 13

                    MouseArea {
                        id: dMa

                        anchors.fill: parent
                        anchors.margins: -6
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Laura.dismiss(card.jid)
                    }
                }
            }

            // acciones: solo las útiles según el estado
            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: card.cfm || card.open

                // confirmación
                Btn {
                    visible: card.cfm
                    label: card.isEvt ? "Crear" : card.isMail ? "Enviar" : "Confirmar"
                    tone: Laura.cWait
                    solid: true
                    onActivated: Laura.confirm(card.jid, true)
                }
                Btn {
                    visible: card.cfm
                    label: card.isEvt || card.isMail ? "Cancelar" : "Rechazar"
                    tone: Laura.cFail
                    onActivated: Laura.confirm(card.jid, false)
                }
                Btn {
                    visible: card.cfm && card.isMail
                    label: card.open ? "Menos" : "Ver completo"
                    onActivated: card.open = !card.open
                }
                // en marcha
                Btn {
                    visible: !card.cfm && (card.kind === "running" || card.kind === "agent")
                    label: "Cancelar"
                    tone: Laura.cFail
                    onActivated: Laura.cancel(card.jid)
                }
                // avisos
                Btn {
                    visible: !card.cfm && card.aviso && card.final
                    label: (card.job.fuentes ?? []).length > 0 && /calendar/i.test(card.job.fuentes[0].url ?? "") ? "Ver evento" : "Abrir en Gmail"
                    tone: card.tert
                    primary: true
                    enable: (card.job.fuentes ?? []).length > 0 && !!card.job.fuentes[0].url
                    onActivated: card.openUrl()
                }
                Btn {
                    visible: !card.cfm && card.aviso && card.final
                    label: "Descartar"
                    tone: Laura.cFail
                    onActivated: Laura.dismiss(card.jid)
                }
                // trabajos terminados
                Btn {
                    visible: !card.cfm && !card.aviso && card.final && card.noteName.length > 0
                    label: "Leer nota"
                    tone: card.agentCol
                    primary: true
                    onActivated: card.openNote()
                }
                Btn {
                    visible: !card.cfm && !card.aviso && card.kind === "done" && (card.job.resumen ?? "").length > 0
                    label: "Copiar"
                    onActivated: Quickshell.execDetached(["wl-copy", card.job.resumen ?? ""])
                }
                Btn {
                    visible: !card.cfm && !card.aviso && card.final
                    label: card.kind === "fail" ? "Reintentar" : "Seguir con esto"
                    onActivated: Laura.follow(card.jid)
                }
            }

            Item {
                implicitHeight: 1
                Layout.fillWidth: true
            }
        }
    }
}
