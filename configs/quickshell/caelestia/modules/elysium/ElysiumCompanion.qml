pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.assistant

// Pantalla de apoyo en el portátil mientras el juego va en la tele: métricas,
// Laura, avisos desviados y la partida. Estática: se actualiza con los datos
// (~1,5 s), sin bucles de animación salvo el pulso de Laura cuando habla.
PanelWindow {
    id: win

    required property var elysium
    readonly property bool off: elysium.companionMode === "apagada"
    readonly property color accent: Colours.palette.m3primary
    property var st: ({})

    screen: elysium.laptopScreen
    color: "black"
    WlrLayershell.namespace: "caelestia-elysium-companion"
    // Top (no Overlay): si un juego a pantalla completa acaba en el portátil, se ve
    // el juego y no esta pantalla encima.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    Process {
        running: !win.off
        command: [`${Quickshell.env("HOME")}/.local/bin/elysium-stats`]
        stdout: SplitParser {
            onRead: line => {
                try {
                    win.st = JSON.parse(line);
                } catch (e) {}
            }
        }
    }

    // Reloj de sesión (minutos).
    property int mins: 0

    Timer {
        interval: 30000
        repeat: true
        running: !win.off
        triggeredOnStart: true
        onTriggered: win.mins = Math.floor((Date.now() - win.elysium.enteredAt.getTime()) / 60000)
    }

    readonly property var notifs: Notifs.list.filter(n => n.time >= win.elysium.enteredAt).slice(-6).reverse()

    function fmt(v: var, dec: int): string {
        return v === undefined || v === null ? "—" : Number(v).toFixed(dec);
    }

    Item {
        anchors.fill: parent
        visible: !win.off

        // Cielo + horizonte, igual que en la tele pero quieto.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: "#030409"
                }
                GradientStop {
                    position: 1
                    color: Qt.tint("#05060c", Qt.alpha(win.accent, 0.08))
                }
            }
        }

        Repeater {
            model: 90

            Rectangle {
                required property int index
                readonly property real r1: ((index * 7919) % 1000) / 1000
                readonly property real r2: ((index * 104729) % 997) / 997

                x: r1 * win.width
                y: r2 * win.height * 0.8
                width: index % 11 === 0 ? 2.5 : 1.5
                height: width
                radius: width / 2
                color: index % 9 === 0 ? win.accent : "white"
                opacity: 0.2 + ((index * 31) % 50) / 100
            }
        }

        Shape {
            id: limb

            readonly property real rr: win.width * 1.6
            readonly property real hz: win.height * 0.9

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "#020205"
                strokeWidth: 1.4
                strokeColor: Qt.alpha(win.accent, 0.7)
                PathAngleArc {
                    centerX: win.width / 2
                    centerY: limb.hz + limb.rr
                    radiusX: limb.rr
                    radiusY: limb.rr
                    startAngle: 180
                    sweepAngle: 180
                }
            }
        }

        // --- cabecera ---
        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 64
            spacing: 14

            MaterialIcon {
                text: "stadia_controller"
                color: win.accent
                fill: 1
                fontStyle: Tokens.font.icon.builders.medium.scale(1.4).build()
            }

            StyledText {
                text: "ELYSIUM"
                color: Colours.palette.m3onSurface
                font.family: Tokens.font.title.large.family
                font.pointSize: 15
                font.weight: Font.Light
                font.letterSpacing: 9
            }

            Rectangle {
                implicitHeight: 28
                implicitWidth: tvRow.implicitWidth + 22
                radius: 14
                color: Qt.alpha(win.accent, 0.14)
                border.width: 1
                border.color: Qt.alpha(win.accent, 0.4)

                Row {
                    id: tvRow

                    anchors.centerIn: parent
                    spacing: 6

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "tv"
                        color: win.accent
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("En la tele")
                        color: win.accent
                        font: Tokens.font.label.medium
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                text: win.elysium.playing ? qsTr("Jugando · %1").arg(win.elysium.runningGame?.subtitle ?? "") : qsTr("En el menú")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.title.small
            }

            StyledText {
                Layout.leftMargin: 24
                text: Time.format("HH:mm")
                color: Colours.palette.m3onSurface
                font.family: Tokens.font.title.large.family
                font.pointSize: 20
                font.weight: Font.Light
            }
        }

        // --- cuerpo: tres columnas ---
        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 150
            anchors.leftMargin: 72
            anchors.rightMargin: 72
            spacing: 56

            // Rendimiento
            ColumnLayout {
                Layout.preferredWidth: win.width * 0.24
                Layout.alignment: Qt.AlignTop
                spacing: 22

                Caption {
                    text: qsTr("Rendimiento")
                }

                Stat {
                    label: qsTr("Gráfica")
                    value: win.fmt(win.st.gpu, 0)
                    unit: "%"
                    frac: (win.st.gpu ?? 0) / 100
                }

                Stat {
                    label: qsTr("Temp. gráfica")
                    value: win.fmt(win.st.gpuTemp, 0)
                    unit: "°C"
                    frac: (win.st.gpuTemp ?? 0) / 95
                    hot: (win.st.gpuTemp ?? 0) > 82
                }

                Stat {
                    label: qsTr("Memoria de vídeo")
                    value: win.fmt((win.st.vram ?? 0) / 1024, 1)
                    unit: win.st.vramTotal ? `/ ${win.fmt(win.st.vramTotal / 1024, 1)} GB` : "GB"
                    frac: win.st.vramTotal ? win.st.vram / win.st.vramTotal : 0
                }

                Stat {
                    label: qsTr("Procesador")
                    value: win.fmt(win.st.cpu, 0)
                    unit: "%"
                    frac: (win.st.cpu ?? 0) / 100
                }

                Stat {
                    label: qsTr("Temp. procesador")
                    value: win.fmt(win.st.cpuTemp, 0)
                    unit: "°C"
                    frac: (win.st.cpuTemp ?? 0) / 100
                    hot: (win.st.cpuTemp ?? 0) > 90
                }

                StyledText {
                    text: `${win.fmt(win.st.gpuW, 0)} W ${qsTr("gráfica")}  ·  ${UPower.onBattery ? qsTr("batería %1%").arg(Math.round(UPower.displayDevice.percentage * 100)) : qsTr("enchufado")}`
                    color: UPower.onBattery ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }
            }

            // Laura
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 22

                Caption {
                    text: qsTr("Laura")
                }

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 180
                    implicitHeight: 180

                    Rectangle {
                        id: orb

                        anchors.centerIn: parent
                        width: 120
                        height: 120
                        radius: 60
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: Qt.lighter(win.accent, 1.4)
                            }
                            GradientStop {
                                position: 1
                                color: Qt.alpha(win.accent, 0.25)
                            }
                        }
                        opacity: Laura.active ? 1 : 0.45

                        SequentialAnimation on scale {
                            running: Laura.active && !win.off
                            loops: Animation.Infinite
                            onRunningChanged: if (!running)
                                orb.scale = 1
                            NumberAnimation {
                                to: 1.12
                                duration: 700
                                easing.type: Easing.InOutSine
                            }
                            NumberAnimation {
                                to: 0.96
                                duration: 700
                                easing.type: Easing.InOutSine
                            }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 176
                        height: 176
                        radius: 88
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(win.accent, 0.3)
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: ({ "idle": qsTr("Mantén ⌂ en el mando para hablar"), "listening": qsTr("Te escucho…"), "thinking": qsTr("Pensando…"), "speaking": qsTr("Hablando") })[Laura.state] ?? Laura.state
                    color: Laura.active ? win.accent : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.title.small
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: Laura.transcript ? `«${Laura.transcript}»` : ""
                    color: Colours.palette.m3onSurfaceVariant
                    font.family: Tokens.font.body.large.family
                    font.pointSize: 15
                    font.italic: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumHeight: win.height * 0.32
                    text: Laura.reply
                    color: Colours.palette.m3onSurface
                    font.family: Tokens.font.title.large.family
                    font.pointSize: 19
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                }
            }

            // Avisos + mandos
            ColumnLayout {
                Layout.preferredWidth: win.width * 0.24
                Layout.alignment: Qt.AlignTop
                spacing: 14

                Caption {
                    text: qsTr("Avisos")
                }

                StyledText {
                    visible: win.notifs.length === 0
                    text: qsTr("Nada nuevo. A jugar.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.medium
                }

                Repeater {
                    model: win.notifs

                    Rectangle {
                        id: nc

                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: ncCol.implicitHeight + 24
                        radius: 14
                        color: Qt.alpha(Colours.palette.m3onSurface, 0.05)
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.08)

                        ColumnLayout {
                            id: ncCol

                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: `${nc.modelData.appName} · ${Qt.formatTime(nc.modelData.time, "HH:mm")}`
                                color: win.accent
                                font: Tokens.font.label.small
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: nc.modelData.summary
                                color: Colours.palette.m3onSurface
                                font: Tokens.font.title.small
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: nc.modelData.body
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.body.small
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                textFormat: Text.PlainText
                            }
                        }
                    }
                }

                Caption {
                    Layout.topMargin: 18
                    visible: (win.st.pads ?? []).length > 0
                    text: qsTr("Mandos")
                }

                Repeater {
                    model: win.st.pads ?? []

                    StyledText {
                        required property var modelData

                        // xpadneo solo da nivel (llena/media/baja/crítica); otros dan %.
                        text: `${modelData.name}  ·  ${modelData.level ? qsTr("batería %1").arg(modelData.level) : modelData.pct + "%"}${modelData.charging ? "  ·  " + qsTr("cargando") : ""}`
                        color: (modelData.pct ?? 100) < 20 ? Colours.palette.m3error : Colours.palette.m3onSurface
                        font: Tokens.font.body.medium
                    }
                }
            }
        }

        // --- acciones (ratón / táctil del portátil) ---
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 48
            spacing: 14

            Action {
                icon: "laptop_chromebook"
                label: qsTr("Escritorio")
                onClicked: win.elysium.setCompanion("escritorio")
            }

            Action {
                icon: "desktop_access_disabled"
                label: qsTr("Apagar pantalla")
                onClicked: win.elysium.setCompanion("apagada")
            }

            Action {
                icon: "logout"
                label: qsTr("Salir de Elysium")
                onClicked: win.elysium.leave(false)
            }
        }
    }

    // Pantalla «apagada»: negro + brillo a 0. Un toque la enciende.
    MouseArea {
        anchors.fill: parent
        visible: win.off
        onClicked: win.elysium.setCompanion("apoyo")
    }

    component Caption: StyledText {
        text: ""
        color: Colours.palette.m3onSurfaceVariant
        font.family: Tokens.font.label.small.family
        font.pointSize: 9
        font.weight: Font.DemiBold
        font.letterSpacing: 3
        font.capitalization: Font.AllUppercase
    }

    component Stat: ColumnLayout {
        id: stat

        property string label
        property string value
        property string unit
        property real frac
        property bool hot

        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: stat.label
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }

            StyledText {
                text: stat.value
                color: stat.hot ? Colours.palette.m3error : Colours.palette.m3onSurface
                font.family: Tokens.font.title.large.family
                font.pointSize: 24
                font.weight: Font.Light
            }

            StyledText {
                Layout.alignment: Qt.AlignBaseline
                text: stat.unit
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 3
            radius: 2
            color: Qt.alpha(Colours.palette.m3onSurface, 0.08)

            Rectangle {
                height: parent.height
                radius: 2
                width: parent.width * Math.max(0, Math.min(1, stat.frac))
                color: stat.hot ? Colours.palette.m3error : win.accent

                Behavior on width {
                    NumberAnimation {
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    component Action: Rectangle {
        id: act

        property string icon
        property string label

        signal clicked

        implicitHeight: 48
        implicitWidth: actRow.implicitWidth + 36
        radius: 24
        color: Qt.alpha(Colours.palette.m3onSurface, actMa.containsMouse ? 0.14 : 0.07)
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.12)

        Behavior on color {
            ColorAnimation {
                duration: 120
            }
        }

        Row {
            id: actRow

            anchors.centerIn: parent
            spacing: 10

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: act.icon
                color: Colours.palette.m3onSurface
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: act.label
                color: Colours.palette.m3onSurface
                font: Tokens.font.label.large
            }
        }

        MouseArea {
            id: actMa

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: act.clicked()
        }
    }
}
