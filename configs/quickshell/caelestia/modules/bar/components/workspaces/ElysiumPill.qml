pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// Píldora en la barra de tareas cuando Hookshot/Elysium tiene una descarga o actualización en segundo plano.
// Clic izquierdo: entra a Elysium para ver el progreso o jugar.
// Clic derecho: muestra un aviso con los detalles exactos (etapa, archivos, tiempo estimado).
StyledRect {
    id: root

    visible: ElysiumService.updating
    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: visible ? col.implicitHeight + 12 : 0
    radius: Tokens.rounding.full
    color: Colours.palette.m3secondaryContainer
    border.width: 1
    border.color: Colours.palette.m3secondary

    Behavior on implicitHeight {
        Anim {}
    }

    StateLayer {
        radius: parent.radius
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => {
            if (event.button === Qt.RightButton) {
                Toaster.toast(
                    qsTr("Hookshot %1").arg(ElysiumService.version || qsTr("Actualizando")),
                    (ElysiumService.text || qsTr("En segundo plano")) +
                        (ElysiumService.files && ElysiumService.files.length >= 2 ? ` (${ElysiumService.files[0]}/${ElysiumService.files[1]})` : "") +
                        (ElysiumService.eta > 0 ? ` · ~${ElysiumService.eta} s` : ""),
                    ElysiumService.stage === "shaders" ? "deployed_code" : "downloading"
                );
            } else {
                Quickshell.execDetached(["qs", "-c", "caelestia", "ipc", "call", "elysium", "enter"]);
            }
        }
    }

    ColumnLayout {
        id: col

        anchors.centerIn: parent
        spacing: 2

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            text: ElysiumService.stage === "shaders" ? "deployed_code" : (ElysiumService.stage === "download" ? "downloading" : "build")
            fontStyle: Tokens.font.icon.small
            color: Colours.palette.m3onSecondaryContainer
        }

        // Porcentaje compacto: ej. "42%"
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Math.round(ElysiumService.pct * 100) + "%"
            font.pixelSize: 8
            font.weight: Font.Bold
            color: Colours.palette.m3onSecondaryContainer
        }

        // Mini etiqueta de fase: "DL", "CP", "SH"
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: ElysiumService.stage === "shaders" ? "SH" : (ElysiumService.stage === "download" ? "DL" : "CP")
            font.pixelSize: 7
            font.weight: Font.DemiBold
            color: Colours.palette.m3secondary
        }
    }
}
