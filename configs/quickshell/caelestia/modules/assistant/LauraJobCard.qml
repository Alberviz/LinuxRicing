pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Tarjeta de un trabajo en el cajón (panel 1 del mockup).
Rectangle {
    id: card

    required property string jid
    // Segundos epoch «ahora», lo refresca el cajón mientras está visible
    property real nowSec: Date.now() / 1000
    property bool flash: false

    readonly property var job: Laura.jobs.find(j => j.id === jid) ?? ({})
    readonly property string kind: job.kind ?? "running"
    readonly property string destino: job.destino ?? "laura"
    readonly property color agentCol: Laura.agentColor(destino)
    readonly property color stCol: kind === "confirm" ? Laura.cWait : kind === "fail" ? Laura.cFail : agentCol
    readonly property bool active: Laura.isActive(job)
    readonly property bool final: kind === "done" || kind === "fail"

    readonly property string stLabel: {
        switch (kind) {
        case "running":
            return "En curso";
        case "agent":
            return "En espera";
        case "confirm":
            return "Pide confirmación";
        case "done":
            return Laura.isAviso(job) ? "Aviso" : "Hecho";
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
            return (nowSec - fin < 4 ? "ahora" : "hace " + _fmt(nowSec - fin)) + " · " + _fmt(fin - inicio);
        }
        if (kind === "cancel")
            return "cancelado";
        return _fmt(nowSec - inicio);
    }

    function openNote(): void {
        if (job.nota)
            Quickshell.execDetached(["xdg-open", "obsidian://open?path=" + encodeURIComponent(job.nota)]);
    }
    function copySummary(): void {
        Quickshell.execDetached(["wl-copy", job.resumen ?? ""]);
    }

    implicitHeight: col.implicitHeight + 22
    radius: 14
    color: Colours.palette.m3surfaceContainer
    border.width: flash ? 2 : 1
    border.color: flash ? Qt.alpha(agentCol, 0.9) : Qt.alpha(Colours.palette.m3onSurface, 0.11)
    opacity: kind === "cancel" ? 0.5 : 1
    Behavior on border.color {
        ColorAnimation {
            duration: 700
        }
    }

    onFlashChanged: if (flash)
        flashT.restart()
    Timer {
        id: flashT

        interval: 1600
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

        implicitWidth: t.implicitWidth + 18
        implicitHeight: 24
        radius: 8
        color: solid ? tone : primary ? Qt.alpha(tone, 0.22) : (ma.containsMouse && enable ? Colours.palette.m3surfaceContainerHigh : "transparent")
        border.width: primary || solid ? 0 : 1
        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.11)
        opacity: enable ? 1 : 0.35

        StyledText {
            id: t

            anchors.centerIn: parent
            text: btn.label
            color: btn.solid ? "#2a1d00" : btn.primary ? btn.tone : btn.tone
            font: Tokens.font.label.small
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

    Column {
        id: col

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 11
        spacing: 7

        // Cabecera: agente · estado · tiempo
        Item {
            width: parent.width
            height: 22

            Rectangle {
                id: chip

                width: 22
                height: 22
                radius: 11
                color: Qt.alpha(card.agentCol, 0.2)

                AgentGlyph {
                    anchors.centerIn: parent
                    agent: card.destino
                    color: card.agentCol
                    size: 13
                }
            }
            StyledText {
                id: who

                anchors.left: chip.right
                anchors.leftMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                text: Laura.agentName(card.destino)
                font.bold: true
            }
            Rectangle {
                anchors.left: who.right
                anchors.leftMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                width: st.implicitWidth + 16
                height: st.implicitHeight + 4
                radius: height / 2
                color: Qt.alpha(card.stCol, 0.18)

                StyledText {
                    id: st

                    anchors.centerIn: parent
                    text: card.stLabel
                    color: card.stCol
                    font: Tokens.font.label.small
                }
            }
            StyledText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: card.timeLabel
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
            }
        }

        // Etiqueta de aviso espontáneo
        Rectangle {
            visible: Laura.isAviso(card.job)
            width: ownT.implicitWidth + 14
            height: ownT.implicitHeight + 4
            radius: height / 2
            color: Qt.alpha(card.agentCol, 0.14)
            border.width: 1
            border.color: Qt.alpha(card.agentCol, 0.5)

            StyledText {
                id: ownT

                anchors.centerIn: parent
                text: "🔔 Por su cuenta"
                color: card.agentCol
                font: Tokens.font.label.small
            }
        }

        // Petición / título
        StyledText {
            width: parent.width
            visible: text.length > 0
            text: card.job.titulo ?? ""
            wrapMode: Text.Wrap
            color: Colours.palette.m3onSurfaceVariant
            font.italic: true
        }

        // Pregunta pendiente de confirmación
        StyledText {
            width: parent.width
            visible: card.kind === "confirm" && text.length > 0
            text: card.job.pregunta ?? ""
            wrapMode: Text.Wrap
            color: Laura.cWait
            font: Tokens.font.body.small
        }

        // Resumen (1-2 frases)
        StyledText {
            width: parent.width
            visible: text.length > 0
            text: card.job.resumen ?? ""
            wrapMode: Text.Wrap
            font: Tokens.font.body.small
        }

        // Fuentes
        Flow {
            width: parent.width
            spacing: 5
            visible: (card.job.fuentes ?? []).length > 0

            Repeater {
                model: card.job.fuentes ?? []

                Rectangle {
                    id: src

                    required property var modelData

                    implicitWidth: Math.min(col.width, srcT.implicitWidth + 24)
                    implicitHeight: srcT.implicitHeight + 6
                    radius: 7
                    color: srcMa.containsMouse ? Colours.palette.m3surfaceContainerHigh : Colours.palette.m3surfaceContainerHighest

                    StyledText {
                        id: srcT

                        anchors.verticalCenter: parent.verticalCenter
                        x: 8
                        width: parent.width - 16
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
        }

        // Ruta de la nota
        Rectangle {
            width: parent.width
            visible: (card.job.nota ?? "").length > 0
            implicitHeight: pathT.implicitHeight + 10
            radius: 8
            color: "#38000000"

            StyledText {
                id: pathT

                anchors.verticalCenter: parent.verticalCenter
                x: 8
                width: parent.width - 16
                wrapMode: Text.WrapAnywhere
                color: Colours.palette.m3onSurfaceVariant
                text: {
                    const n = card.job.nota ?? "";
                    const i = n.lastIndexOf("/vault/");
                    return "▤ " + (i >= 0 ? n.slice(i + 1) : n);
                }
                font: Tokens.font.mono.small
            }
        }

        // Acciones
        Flow {
            width: parent.width
            spacing: 5

            Btn {
                visible: card.kind === "confirm"
                label: "Confirmar"
                tone: Laura.cWait
                solid: true
                onActivated: Laura.confirm(card.jid, true)
            }
            Btn {
                visible: card.kind === "confirm"
                label: "Rechazar"
                tone: Laura.cFail
                onActivated: Laura.confirm(card.jid, false)
            }
            Btn {
                visible: card.final && Laura.isAviso(card.job)
                label: "Abrir"
                tone: card.agentCol
                primary: true
                enable: (card.job.fuentes ?? []).length > 0 && !!card.job.fuentes[0].url
                onActivated: Quickshell.execDetached(["xdg-open", card.job.fuentes[0].url])
            }
            Btn {
                visible: card.final && Laura.isAviso(card.job)
                label: "Descartar"
                tone: Laura.cFail
                onActivated: Laura.dismiss(card.jid)
            }
            Btn {
                visible: card.final && (!Laura.isAviso(card.job) || (card.job.nota ?? "").length > 0)
                label: "Abrir nota"
                tone: card.agentCol
                primary: true
                enable: (card.job.nota ?? "").length > 0
                onActivated: card.openNote()
            }
            Btn {
                visible: card.final
                label: "Copiar"
                enable: (card.job.resumen ?? "").length > 0
                onActivated: card.copySummary()
            }
            Btn {
                label: card.kind === "fail" ? "Reintentar" : "Seguir con esto"
                visible: card.final && !Laura.isAviso(card.job)
                onActivated: Laura.follow(card.jid)
            }
            Btn {
                visible: card.kind === "running" || card.kind === "agent"
                label: "Cancelar"
                tone: Laura.cFail
                onActivated: Laura.cancel(card.jid)
            }
        }
    }
}
