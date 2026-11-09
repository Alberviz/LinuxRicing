pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Filas de ajustes (Calidad / Codificador / Audio) para meter dentro de una tarjeta. Sirve en reposo
// (lo de la próxima proyección) y proyectando (en caliente): quien lo usa decide qué hacer con `picked`.
ColumnLayout {
    id: root

    property string quality: "auto"
    property string encoder: "auto"
    property bool audio: true
    signal picked(string key, var value)

    readonly property var opt: Cast.options
    readonly property bool hasEncoder: opt?.encoder_auto !== undefined

    function autoReason(): string {
        const p = opt?.power;
        if (!p)
            return "";
        const parts = [p.ac ? "enchufado" : "batería"];
        if (p.profile === "power-saver")
            parts.push("ahorro");
        return (opt.encoder_auto === "nvidia" ? "GPU" : "CPU") + " · " + parts[parts.length - 1];
    }

    spacing: Tokens.spacing.medium

    component SettingRow: RowLayout {
        id: sr

        property string icon
        property string title
        property string subtitle

        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        MaterialIcon {
            Layout.alignment: Qt.AlignVCenter
            text: sr.icon
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.medium
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: sr.title
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: sr.subtitle !== ""
                text: sr.subtitle
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }
    }

    SettingRow {
        visible: root.opt !== null
        icon: "high_quality"
        title: "Calidad"
        subtitle: root.quality === "auto" ? "720p" : root.quality === "1080p" ? "Más nítido" : "Más fluido"

        Segmented {
            model: [["auto", "Auto"], ["720p", "720p"], ["1080p", "1080p"]]
            value: root.quality
            onPicked: v => root.picked("quality", v)
        }
    }

    SettingRow {
        visible: root.hasEncoder
        icon: "memory"
        title: "Codificador"
        subtitle: root.encoder === "auto" ? (root.quality === "1080p" ? "CPU · más fluido a 1080p" : root.autoReason()) : root.encoder === "nvidia" ? (root.quality === "1080p" ? "Entrecorta a 1080p" : "Despierta la gráfica") : "Usa más CPU"

        Segmented {
            model: [["auto", "Auto"], ["cpu", "CPU"], ["nvidia", "GPU"]]
            value: root.encoder
            onPicked: v => root.picked("encoder", v)
        }
    }

    SettingRow {
        icon: root.audio ? "volume_up" : "volume_off"
        title: "Audio del sistema"
        subtitle: root.audio ? "Se oye en la tele" : "Solo imagen"

        StyledSwitch {
            checked: root.audio
            onToggled: root.picked("audio", checked)
        }
    }
}
