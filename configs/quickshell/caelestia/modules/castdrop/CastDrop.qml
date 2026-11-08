pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services

// Zona de destino «Enviar a <dispositivo>» para arrastrar archivos hacia el borde derecho.
// En Wayland solo la superficie bajo el cursor recibe un DnD y no hay detección global de
// arrastre, así que esta ventana layer-shell deja una franja fina (6 px, banda central del
// borde) con la región de input activa; al entrar un arrastre se expande con animación a
// la tarjeta de destino. Fuera de la franja/tarjeta es click-through total.
Variants {
    model: Screens.screens

    StyledWindow {
        id: win

        required property ShellScreen modelData

        // Estados: reposo (franja) -> over (arrastre encima) -> sent (feedback tras soltar).
        property bool over: false
        property bool sent: false
        readonly property bool expanded: over || sent
        readonly property string deviceName: Cast.selectedDevice?.name ?? ""

        screen: modelData
        name: "castdrop"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors.top: true
        anchors.bottom: true
        anchors.right: true
        implicitWidth: 320

        mask: Region {
            item: hit
        }

        Timer {
            id: retract

            interval: 2200
            onTriggered: {
                win.sent = false;
                win.over = false;
            }
        }

        Item {
            id: hit

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: win.expanded ? 300 : 6
            height: win.expanded ? 170 : win.height * 0.4

            Behavior on width {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }
            Behavior on height {
                Anim {
                    type: Anim.DefaultSpatial
                }
            }

            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list", "text/plain"]

                onEntered: drag => {
                    Cast.refresh();
                    if (!win.sent)
                        win.over = true;
                }
                onExited: {
                    if (!win.sent)
                        win.over = false;
                }
                onDropped: drop => {
                    let t = "";
                    if (drop.hasUrls && drop.urls.length > 0)
                        t = Cast.normalizeTarget(drop.urls[0].toString());
                    else if (drop.hasText)
                        t = Cast.normalizeTarget(drop.text);
                    Cast.cmdError = "";
                    win.sent = true;
                    if (t)
                        Cast.castSelected(t);
                    else
                        Cast.cmdError = "Lo soltado no es un archivo ni una URL";
                    retract.restart();
                }
            }

            StyledRect {
                id: card

                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.rightMargin: -radius // pegada al borde: esquinas derechas fuera
                width: 300 + radius

                radius: Tokens.rounding.large
                color: win.over && !win.sent ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainer
                opacity: win.expanded ? 1 : 0
                border.width: 2
                border.color: Colours.palette.m3primary

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
                Behavior on color {
                    CAnim {}
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: -card.radius / 2
                    spacing: Tokens.spacing.medium
                    width: 260

                    MaterialIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: win.sent && Cast.cmdError ? "error" : "cast"
                        color: win.sent && Cast.cmdError ? Colours.palette.m3error : Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: win.sent ? (Cast.cmdError || "Enviando…") : (win.deviceName ? "Enviar a " + win.deviceName : "Sin Chromecast")
                        color: win.over && !win.sent ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                        font: Tokens.font.body.medium
                    }
                }
            }
        }
    }
}
