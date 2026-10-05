pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Caelestia.Services
import qs.services

// Componente para visualizar la música dentro del agujero negro.
// Se ancla al centro geométrico del agujero negro (horizonte de sucesos).
Item {
    id: root

    // Datos geométricos desde SolarSystem
    property point center: Qt.point(0, 0)
    property real radius: 100
    property real time: 0

    // Métricas de audio reactivo (desde SolarSystemModel / Sim.js)
    property real musicBass: 0
    property real musicPulse: 0
    property real musicTreble: 0

    // Versiones muy suavizadas (≈450 ms): las variantes alternativas nunca
    // parpadean con el beat; sólo derivan despacio con la energía.
    property real _calmBass: musicBass * 0.5
    property real _calmPulse: musicPulse * 0.5
    property real _calmTreble: musicTreble * 0.5
    Behavior on _calmBass { NumberAnimation { duration: 450 } }
    Behavior on _calmPulse { NumberAnimation { duration: 450 } }
    Behavior on _calmTreble { NumberAnimation { duration: 450 } }

    // Paleta de colores M3
    property color colPrimary: "#f7b999"
    property color colInk: "#f8e1d6"
    property color colVoid: "#060403"
    property color colError: "#f97758"
    property string fontFamily: "JetBrainsMono NF"

    // Variante activa (1 a 6)
    property int variant: 2

    x: center.x - radius
    y: center.y - radius
    width: radius * 2
    height: radius * 2
    z: 10

    // Lectura de metadatos del reproductor MPRIS global (Players.active)
    readonly property string trackTitle: Players.active?.trackTitle || "Sin reproducción"
    readonly property string trackArtist: Players.active?.trackArtist || "Caelestia Audio"
    readonly property bool isPlaying: Players.active?.isPlaying ?? false
    readonly property real position: Players.active?.position ?? 0
    readonly property real length: Players.active?.length ?? 0

    // Formateador de tiempo mm:ss
    function formatTime(s) {
        if (typeof s !== "number" || isNaN(s) || s < 0) return "--:--";
        const sec = Math.floor(s);
        const m = Math.floor(sec / 60);
        const remSec = sec % 60;
        return (m < 10 ? "0" : "") + m + ":" + (remSec < 10 ? "0" : "") + remSec;
    }

    // Catálogo de nombres de variantes
    readonly property var variantNames: [
        "Disco desnudo (sin overlay)",
        "Órbita de Acreción + Espectro",
        "Minimalista Clásico + Anillo GPU",
        "Ondas Gravitacionales / Vinilo",
        "Reloj de Púlsares Relativistas",
        "Espiral de Singularidad",
        "Lente Gravitacional / Radar HUD"
    ]

    // Temporizador para el badge informativo al cambiar de variante
    Timer {
        id: badgeTimer
        interval: 2200
        onTriggered: badge.opacity = 0
    }

    // Variante 0 = «disco desnudo» (sin overlay, ver mockup O9): todo lo lleva
    // el disco de acreción del shader, esta capa no dibuja nada.
    function nextVariant() {
        root.variant = (root.variant + 1) % 7;
        badge.opacity = 1;
        badgeTimer.restart();
    }

    function prevVariant() {
        root.variant = root.variant === 0 ? 6 : root.variant - 1;
        badge.opacity = 1;
        badgeTimer.restart();
    }

    // =========================================================================
    // VARIANTE 1: Órbita de Acreción + Espectro Perimetral (Idea A)
    // =========================================================================
    Item {
        anchors.fill: parent
        visible: root.variant === 1

        // Anillo perimetral que late con graves y golpe
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * (0.92 + root._calmBass * 0.06)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1.5 + root._calmPulse * 2.5
            border.color: Qt.rgba(root.colPrimary.r, root.colPrimary.g, root.colPrimary.b, 0.25 + root._calmPulse * 0.5)
        }

        // Texto en órbita continua tangente al horizonte
        Item {
            anchors.fill: parent
            rotation: (root.time * 18) % 360

            Item {
                x: parent.width / 2 + root.radius * 0.60
                y: parent.height / 2
                rotation: 90
                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: root.trackTitle
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: root.colInk
                    }
                    Text {
                        text: "·  " + root.trackArtist
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        color: root.colPrimary
                        opacity: 0.8
                    }
                }
            }
        }

        // Mini ecualizador central de 5 barras
        Row {
            anchors.centerIn: parent
            spacing: 4
            Repeater {
                model: 5
                Rectangle {
                    required property int index
                    width: 3
                    height: 5 + (index === 0 || index === 4 ? root._calmBass * 20 : (index === 2 ? root._calmPulse * 26 : root._calmTreble * 18))
                    radius: 1.5
                    color: root.colPrimary
                    opacity: 0.5 + root._calmPulse * 0.5
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // =========================================================================
    // VARIANTE 2: Minimalista Clásico + Anillo de Progreso en GPU (Idea B)
    // =========================================================================
    Item {
        anchors.fill: parent
        visible: root.variant === 2

        // Bloque de texto e información centrado en el vacío
        Column {
            anchors.centerIn: parent
            width: parent.width * 0.72
            spacing: 4

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Text {
                    text: root.isPlaying ? "󰐊" : "󰏤"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    color: root.colPrimary
                }
                Text {
                    text: root.formatTime(root.position) + " / " + root.formatTime(root.length)
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    color: root.colInk
                    opacity: 0.6
                }
            }

            Text {
                width: parent.width
                text: root.trackTitle
                color: root.colInk
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: root.trackArtist
                color: root.colPrimary
                font.family: root.fontFamily
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                opacity: 0.85
            }
        }
    }

    // =========================================================================
    // VARIANTE 3: Ondas Gravitacionales / Disco Vinilo Espectral (Idea C)
    // =========================================================================
    Item {
        anchors.fill: parent
        visible: root.variant === 3

        Repeater {
            model: 4
            Rectangle {
                required property int index
                anchors.centerIn: parent
                width: parent.width * (0.34 + index * 0.17 + (index % 2 === 0 ? root._calmBass * 0.05 : root._calmTreble * 0.05))
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(root.colInk.r, root.colInk.g, root.colInk.b, 0.06 + (index === 1 ? root._calmPulse * 0.28 : root._calmBass * 0.16))
            }
        }

        // Etiqueta central circular estilo vinilo
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.38
            height: width
            radius: width / 2
            color: Qt.rgba(root.colVoid.r, root.colVoid.g, root.colVoid.b, 0.88)
            border.width: 1
            border.color: Qt.rgba(root.colPrimary.r, root.colPrimary.g, root.colPrimary.b, 0.4)

            Column {
                anchors.centerIn: parent
                width: parent.width * 0.85
                spacing: 2
                Text {
                    width: parent.width
                    text: root.trackTitle
                    color: root.colInk
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.trackArtist
                    color: root.colPrimary
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }

    // =========================================================================
    // VARIANTE 4: Reloj de Púlsares Binarios Relativistas (Idea D)
    // =========================================================================
    Item {
        anchors.fill: parent
        visible: root.variant === 4

        Item {
            anchors.centerIn: parent
            width: parent.width * 0.86
            height: width
            rotation: (root.time * 24) % 360

            // Haz diametral que atraviesa la singularidad
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: 1 + root._calmPulse * 2.5
                color: root.colPrimary
                opacity: 0.2 + root._calmBass * 0.5
            }

            // Púlsar Alfa
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: -4
                width: 7 + root._calmPulse * 5
                height: width
                radius: width / 2
                color: root.colPrimary
                border.width: 1
                border.color: root.colInk
            }

            // Púlsar Beta
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - 4
                width: 7 + root._calmPulse * 5
                height: width
                radius: width / 2
                color: root.colError
                border.width: 1
                border.color: root.colInk
            }
        }

        Column {
            anchors.centerIn: parent
            width: parent.width * 0.70
            spacing: 6
            Text {
                width: parent.width
                text: root.trackTitle
                color: root.colInk
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.trackArtist
                color: root.colPrimary
                font.family: root.fontFamily
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }

    // =========================================================================
    // VARIANTE 5: Espiral de Singularidad (Idea E)
    // =========================================================================
    Item {
        anchors.fill: parent
        visible: root.variant === 5

        Shape {
            anchors.fill: parent
            rotation: (root.time * 22) % 360
            scale: 1.0 - root._calmBass * 0.08
            Behavior on scale { NumberAnimation { duration: 100 } }

            ShapePath {
                strokeColor: Qt.rgba(root.colPrimary.r, root.colPrimary.g, root.colPrimary.b, 0.28 + root._calmBass * 0.35)
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: root.width / 2
                startY: root.height / 2 - (root.radius * 0.82)
                PathAngleArc {
                    centerX: root.width / 2
                    centerY: root.height / 2
                    radiusX: root.radius * 0.82
                    radiusY: root.radius * 0.44
                    startAngle: -90
                    sweepAngle: 240
                }
            }

            ShapePath {
                strokeColor: Qt.rgba(root.colInk.r, root.colInk.g, root.colInk.b, 0.20 + root._calmPulse * 0.35)
                strokeWidth: 1.5
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: root.width / 2
                startY: root.height / 2 + (root.radius * 0.82)
                PathAngleArc {
                    centerX: root.width / 2
                    centerY: root.height / 2
                    radiusX: root.radius * 0.82
                    radiusY: root.radius * 0.44
                    startAngle: 90
                    sweepAngle: 240
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.54
            height: width
            radius: width / 2
            color: Qt.rgba(root.colVoid.r, root.colVoid.g, root.colVoid.b, 0.82)
            border.width: 1
            border.color: Qt.rgba(root.colPrimary.r, root.colPrimary.g, root.colPrimary.b, 0.3)

            Column {
                anchors.centerIn: parent
                width: parent.width * 0.85
                spacing: 3
                Text {
                    width: parent.width
                    text: root.trackTitle
                    color: root.colInk
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: root.trackArtist
                    color: root.colPrimary
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }
        }
    }

    // =========================================================================
    // VARIANTE 6: Lente Gravitacional / Radar Espectral HUD (Idea F)
    // =========================================================================
    Item {
        anchors.fill: parent
        visible: root.variant === 6

        // 12 marcas de graduación alrededor del horizonte
        Item {
            anchors.centerIn: parent
            width: parent.width * 0.88
            height: width
            Repeater {
                model: 12
                Item {
                    required property int index
                    anchors.fill: parent
                    rotation: index * 30
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 2
                        width: index % 3 === 0 ? 2 : 1
                        height: index % 3 === 0 ? 8 : 4
                        color: index % 3 === 0 ? root.colPrimary : root.colInk
                        opacity: 0.3 + (index % 2 === 0 ? root._calmBass * 0.5 : root._calmTreble * 0.4)
                    }
                }
            }
        }

        Column {
            anchors.centerIn: parent
            width: parent.width * 0.72
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SINGULARITY · AUDIO HUD"
                color: root.colPrimary
                font.family: root.fontFamily
                font.pixelSize: 8
                font.weight: Font.Bold
                font.letterSpacing: 1.5
                opacity: 0.8
            }

            Text {
                width: parent.width
                text: root.trackTitle.toUpperCase()
                color: root.colInk
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: Font.Black
                font.letterSpacing: 1.0 + root._calmBass * 1.5
                Behavior on font.letterSpacing { NumberAnimation { duration: 100 } }
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: root.trackArtist
                color: root.colPrimary
                font.family: root.fontFamily
                font.pixelSize: 10
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                opacity: 0.9
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 3
                Repeater {
                    model: 5
                    Rectangle {
                        required property int index
                        width: 4
                        height: 3 + (index === 2 ? root._calmPulse * 16 : (index === 0 || index === 4 ? root._calmBass * 14 : root._calmTreble * 12))
                        radius: 1
                        color: root.colPrimary
                        anchors.bottom: parent.bottom
                    }
                }
            }
        }
    }

    // =========================================================================
    // INTERACTIVIDAD Y CONTROLES: Clic o rueda para probar las 6 variantes
    // =========================================================================
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) root.prevVariant();
            else root.nextVariant();
        }
        onWheel: wheel => {
            if (wheel.angleDelta.y > 0) root.nextVariant();
            else root.prevVariant();
        }
    }

    // Cartel emergente con el nombre de la variante activa al cambiar
    Rectangle {
        id: badge
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height * 0.78
        width: badgeRow.width + 16
        height: 22
        radius: 11
        color: Qt.rgba(root.colVoid.r, root.colVoid.g, root.colVoid.b, 0.92)
        border.width: 1
        border.color: Qt.rgba(root.colPrimary.r, root.colPrimary.g, root.colPrimary.b, 0.5)
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

        Row {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 6
            Text {
                text: "V" + root.variant + ":"
                color: root.colPrimary
                font.family: root.fontFamily
                font.pixelSize: 9
                font.weight: Font.Bold
            }
            Text {
                text: root.variantNames[root.variant] || ""
                color: root.colInk
                font.family: root.fontFamily
                font.pixelSize: 9
            }
        }
    }

}
