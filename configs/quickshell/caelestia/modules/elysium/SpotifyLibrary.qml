pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Vista a pantalla completa de la biblioteca de playlists de Spotify.
// ←/→: moverse · A: poner playlist (o abrir Spotify) · B: volver.
Item {
    id: root

    required property var elysium
    readonly property bool shown: elysium.spotifyLibraryOpen
    readonly property color accent: Colours.palette.m3primary
    readonly property var playlists: elysium.playlists ?? []
    property int index: 0

    function clampIndex(): void {
        if (playlists.length === 0)
            index = 0;
        else if (index >= playlists.length)
            index = playlists.length - 1;
        else if (index < 0)
            index = 0;
    }

    onPlaylistsChanged: clampIndex()
    onShownChanged: {
        if (shown)
            clampIndex();
    }

    function pad(b: string): void {
        const E = elysium;
        if (b === "b" || b === "home" || b === "y") {
            E.spotifyLibraryOpen = false;
            E.sfx("back");
            return;
        }
        if (b === "a" || b === "start") {
            if (E.playlistsLoading)
                return;
            if (E.playlistsError.length > 0 || playlists.length === 0) {
                E.sfx("select");
                E.loadPlaylists(true);
                return;
            }
            const pl = playlists[index];
            if (pl) {
                E.sfx("select");
                E.playPlaylist(pl);
            }
            return;
        }
        if (b === "left" || b === "right") {
            if (playlists.length === 0)
                return;
            const next = Math.max(0, Math.min(playlists.length - 1, index + (b === "left" ? -1 : 1)));
            if (next !== index) {
                index = next;
                E.sfx("move");
            }
        }
    }

    function displayName(pl: var): string {
        const n = (pl?.nombre ?? "").trim();
        return n.length > 0 ? n : qsTr("Playlist sin título");
    }

    function glyphChar(pl: var): string {
        const n = (pl?.nombre ?? "").trim();
        if (!n)
            return "♪";
        return Array.from(n)[0].toUpperCase();
    }

    visible: opacity > 0.01
    opacity: shown ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: 320
            easing.type: Easing.OutCubic
        }
    }

    // Velo oscuro: deja entrever sutilmente el planeta debajo sin traslucir textos.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.01, 0.01, 0.03, 0.97)
    }

    // Halo del acento en la esquina superior izquierda.
    Rectangle {
        x: -220
        y: -220
        width: 680
        height: 680
        radius: 340
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Qt.alpha(root.accent, 0.14)
            }
            GradientStop {
                position: 1
                color: "transparent"
            }
        }
    }

    // ---------- cabecera ----------
    Column {
        x: 96
        y: 68
        spacing: 8

        StyledText {
            text: qsTr("SPOTIFY")
            color: root.accent
            font.family: Tokens.font.label.small.family
            font.pointSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 3.5
        }

        StyledText {
            text: qsTr("Biblioteca")
            color: Colours.palette.m3onSurface
            font.family: Tokens.font.title.large.family
            font.pointSize: 42
            font.weight: Font.Light
        }

        StyledText {
            text: root.elysium.playlistsLoading
                ? qsTr("Cargando tus playlists…")
                : root.elysium.playlistsError.length > 0
                    ? root.elysium.playlistsError
                    : qsTr("%1 playlists en tu biblioteca · A para escuchar").arg(root.playlists.length)
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.title.small
        }
    }

    // ---------- estado: cargando (shimmer suave) ----------
    Row {
        id: shimmerRow

        visible: root.elysium.playlistsLoading
        anchors.verticalCenter: parent.verticalCenter
        x: 96
        spacing: 28

        property real phase: 0

        NumberAnimation on phase {
            from: 0
            to: 1
            duration: 1300
            loops: Animation.Infinite
            running: root.shown && root.elysium.playlistsLoading
        }

        Repeater {
            model: 5

            Column {
                required property int index
                readonly property real wave: 0.5 + 0.5 * Math.sin((shimmerRow.phase * Math.PI * 2) - index * 0.7)

                spacing: 16

                Rectangle {
                    width: 220
                    height: 220
                    radius: 24
                    color: Qt.alpha(Colours.palette.m3onSurface, 0.04 + wave * 0.06)
                    border.width: 1
                    border.color: Qt.alpha(root.accent, 0.12 + wave * 0.18)
                }

                Rectangle {
                    width: 150
                    height: 16
                    radius: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: Qt.alpha(Colours.palette.m3onSurface, 0.05 + wave * 0.05)
                }
            }
        }
    }

    // ---------- estado: error / Spotify cerrado ----------
    Rectangle {
        visible: !root.elysium.playlistsLoading && (root.elysium.playlistsError.length > 0 || root.playlists.length === 0)
        anchors.centerIn: parent
        width: 620
        height: errCol.implicitHeight + 72
        radius: 28
        color: Colours.palette.m3surfaceContainer
        border.width: 1
        border.color: Qt.alpha(root.accent, 0.38)

        ColumnLayout {
            id: errCol

            anchors.centerIn: parent
            width: parent.width - 72
            spacing: 14

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 60
                implicitHeight: 60
                radius: 30
                color: Qt.alpha(root.accent, 0.15)
                border.width: 1
                border.color: Qt.alpha(root.accent, 0.45)

                MaterialIcon {
                    anchors.centerIn: parent
                    text: root.elysium.playlistsNeedSpotify ? "library_music" : "error_outline"
                    color: root.accent
                    fill: 1
                    fontStyle: Tokens.font.icon.builders.medium.scale(1.6).build()
                }
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.elysium.playlistsNeedSpotify ? qsTr("Spotify no está abierto") : qsTr("No se pudo cargar la biblioteca")
                color: Colours.palette.m3onSurface
                font: Tokens.font.title.large
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.elysium.playlistsNeedSpotify
                    ? qsTr("Abre Spotify desde aquí para ver tus playlists y empezar a escuchar música.")
                    : (root.elysium.playlistsError || qsTr("No tienes playlists disponibles en tu biblioteca."))
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.large
                wrapMode: Text.WordWrap
            }

            Item {
                implicitHeight: 6
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 14

                Rectangle {
                    implicitHeight: 50
                    implicitWidth: openRow.implicitWidth + 36
                    radius: 25
                    color: root.accent

                    Row {
                        id: openRow

                        anchors.centerIn: parent
                        spacing: 10

                        PadGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            letter: "A"
                            tone: Colours.palette.m3onPrimary
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.elysium.playlistsNeedSpotify ? qsTr("Abrir Spotify") : qsTr("Reintentar")
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.title.small
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pad("a")
                    }
                }

                Rectangle {
                    implicitHeight: 50
                    implicitWidth: backRow.implicitWidth + 36
                    radius: 25
                    color: Qt.alpha(Colours.palette.m3onSurface, 0.08)

                    Row {
                        id: backRow

                        anchors.centerIn: parent
                        spacing: 10

                        PadGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            letter: "B"
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: qsTr("Volver")
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.title.small
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pad("b")
                    }
                }
            }
        }
    }

    // ---------- fila horizontal de playlists ----------
    ListView {
        id: listView

        visible: !root.elysium.playlistsLoading && root.elysium.playlistsError.length === 0 && root.playlists.length > 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 24
        height: 390
        orientation: ListView.Horizontal
        spacing: 28
        leftMargin: 96
        rightMargin: 96
        clip: false
        interactive: true
        currentIndex: root.index
        preferredHighlightBegin: Math.max(96, width * 0.22)
        preferredHighlightEnd: Math.max(360, width * 0.45)
        highlightRangeMode: ListView.ApplyRange
        highlightMoveDuration: 340
        model: root.playlists

        delegate: Item {
            id: cardSlot

            required property var modelData
            required property int index
            readonly property bool sel: index === root.index
            readonly property string coverUrl: modelData.imagen ?? modelData.cover ?? modelData.art ?? ""
            readonly property bool launchingThis: root.elysium.launchingPlaylistUri === (modelData.uri ?? "")
            readonly property real tileSize: 224

            width: tileSize
            height: 360
            z: sel ? 2 : 0

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: cardSlot.sel ? 16 : 32
                spacing: cardSlot.sel ? 24 : 18

                Behavior on y {
                    NumberAnimation {
                        duration: 320
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {
                    id: tile

                    width: cardSlot.tileSize
                    height: cardSlot.tileSize
                    radius: 24
                    scale: cardSlot.sel ? 1.14 : 0.88
                    opacity: cardSlot.sel ? 1.0 : 0.56
                    color: "#0b0d16"
                    border.width: cardSlot.sel ? 3 : 1
                    border.color: cardSlot.sel ? root.accent : Qt.alpha(Colours.palette.m3onSurface, 0.14)
                    clip: true

                    Behavior on scale {
                        NumberAnimation {
                            duration: 320
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.4
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 240
                        }
                    }

                    // Portada si el CLI la proporciona.
                    StyledClippingRect {
                        anchors.fill: parent
                        anchors.margins: cardSlot.sel ? 3 : 1
                        radius: 22
                        visible: cover.status === Image.Ready

                        Image {
                            id: cover

                            anchors.fill: parent
                            source: cardSlot.coverUrl
                            sourceSize.width: 450
                            sourceSize.height: 450
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            mipmap: true
                            asynchronous: true
                        }
                    }

                    // Degradado del acento con inicial cuando no hay portada.
                    Item {
                        anchors.fill: parent
                        visible: cover.status !== Image.Ready

                        Rectangle {
                            anchors.fill: parent
                            radius: 22
                            gradient: Gradient {
                                GradientStop {
                                    position: 0
                                    color: Qt.tint("#121526", Qt.alpha(root.accent, (cardSlot.index % 3 === 0) ? 0.36 : (cardSlot.index % 3 === 1) ? 0.24 : 0.48))
                                }
                                GradientStop {
                                    position: 1
                                    color: Qt.tint("#06070d", Qt.alpha(Colours.palette.m3tertiary, (cardSlot.index % 2 === 0) ? 0.16 : 0.08))
                                }
                            }
                        }

                        // Brillo radial sutil en esquina superior izquierda.
                        Rectangle {
                            x: -40
                            y: -40
                            width: 160
                            height: 160
                            radius: 80
                            gradient: Gradient {
                                GradientStop {
                                    position: 0
                                    color: Qt.alpha(root.accent, 0.28)
                                }
                                GradientStop {
                                    position: 1
                                    color: "transparent"
                                }
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: root.glyphChar(cardSlot.modelData)
                            color: Qt.alpha(Colours.palette.m3onSurface, cardSlot.sel ? 0.95 : 0.78)
                            font.family: Tokens.font.title.large.family
                            font.pointSize: 58
                            font.weight: Font.Light
                        }

                        MaterialIcon {
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.margins: 14
                            text: "queue_music"
                            color: Qt.alpha(root.accent, 0.75)
                            fontStyle: Tokens.font.icon.builders.medium.scale(1.1).build()
                        }
                    }

                    // Overlay mientras lanza la playlist.
                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        color: Qt.rgba(0, 0, 0, 0.55)
                        visible: cardSlot.launchingThis

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "play_circle"
                            color: root.accent
                            fill: 1
                            fontStyle: Tokens.font.icon.builders.medium.scale(2.4).build()
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (cardSlot.sel)
                                root.pad("a");
                            else {
                                root.index = cardSlot.index;
                                root.elysium.sfx("move");
                            }
                        }
                    }
                }

                // Reflejo del acento bajo la seleccionada.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 3
                    radius: 2
                    width: cardSlot.sel ? tile.width * 0.55 : 0
                    color: root.accent

                    Behavior on width {
                        NumberAnimation {
                            duration: 320
                            easing.type: Easing.OutExpo
                        }
                    }
                }

                StyledText {
                    width: cardSlot.tileSize + 24
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: root.displayName(cardSlot.modelData)
                    color: cardSlot.sel ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                    font: cardSlot.sel ? Tokens.font.title.medium : Tokens.font.body.large
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ---------- pistas de mando ----------
    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 56
        spacing: 30

        HintRow {
            letter: "←→"
            label: qsTr("Moverse")
        }

        HintRow {
            letter: "A"
            label: root.elysium.playlistsNeedSpotify ? qsTr("Abrir Spotify") : qsTr("Poner playlist")
        }

        HintRow {
            letter: "B"
            label: qsTr("Volver")
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
