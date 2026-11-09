import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Calidad / Codificador / Audio. Sirve en reposo (elige lo de la próxima proyección) y proyectando
// (cambia en caliente): quien lo usa decide qué hacer con `picked`.
ColumnLayout {
    id: root

    property string quality: "auto"
    property string encoder: "auto"
    property bool audio: true
    property bool showAudio: true
    signal picked(string key, var value)

    readonly property var opt: Cast.options
    readonly property bool hasEncoder: opt?.encoder_auto !== undefined

    function autoReason(): string {
        const p = opt?.power;
        if (!p)
            return "";
        const parts = [p.ac ? "enchufado" : "batería"];
        if (p.profile === "power-saver")
            parts.push("modo ahorro");
        else if (p.ac)
            parts.push(p.profile === "performance" ? "rendimiento" : "equilibrado");
        return (opt.encoder_auto === "nvidia" ? "NVIDIA" : "CPU") + " · " + parts.join(", ");
    }

    spacing: Tokens.spacing.small

    StyledText {
        visible: root.opt !== null
        text: "Calidad"
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }
    Flow {
        Layout.fillWidth: true
        visible: root.opt !== null
        spacing: Tokens.spacing.small

        Repeater {
            model: [["auto", "Auto"], ["720p", "720p"], ["1080p", "1080p"]]

            Chip {
                required property var modelData

                label: modelData[1]
                selected: root.quality === modelData[0]
                onClicked: root.picked("quality", modelData[0])
            }
        }
    }

    StyledText {
        visible: root.hasEncoder
        text: "Codificador"
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }
    Flow {
        Layout.fillWidth: true
        visible: root.hasEncoder
        spacing: Tokens.spacing.small

        Repeater {
            model: [["auto", "Auto"], ["cpu", "CPU"], ["nvidia", "NVIDIA"]]

            Chip {
                required property var modelData

                label: modelData[1]
                selected: root.encoder === modelData[0]
                onClicked: root.picked("encoder", modelData[0])
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: root.hasEncoder && root.encoder === "auto" && root.autoReason() !== ""
        text: "Ahora elegirá: " + root.autoReason()
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
        wrapMode: Text.WordWrap
    }

    StyledRect {
        Layout.fillWidth: true
        visible: root.showAudio
        implicitHeight: al.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        RowLayout {
            id: al

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "volume_up"
                color: Colours.palette.m3onSurfaceVariant
            }
            StyledText {
                Layout.fillWidth: true
                text: "Enviar el audio del sistema"
                font: Tokens.font.body.medium
            }
            StyledSwitch {
                checked: root.audio
                onToggled: root.picked("audio", checked)
            }
        }
    }
}
