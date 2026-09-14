pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

ColumnLayout {
    id: root

    required property PopoutState popouts
    property var network: root.popouts.passwordNetwork
    property bool isClosing: false

    readonly property bool shouldBeVisible: root.popouts.currentName === "wirelesspassword"

    function checkConnectionStatus(): void {
        if (!root.shouldBeVisible || !connectButton.connecting) {
            return;
        }

        // Check if we're connected to the target network (case-insensitive SSID comparison)
        const isConnected = root.network && Nmcli.active && Nmcli.active.ssid && Nmcli.active.ssid.toLowerCase().trim() === root.network.ssid.toLowerCase().trim();

        if (isConnected) {
            // Successfully connected - give it a moment for network list to update
            // Use Timer for actual delay
            connectionSuccessTimer.start();
            return;
        }

        // Check for connection failures - if pending connection was cleared but we're not connected
        if (Nmcli.pendingConnection === null && connectButton.connecting) {
            // Wait a bit more before giving up (allow time for connection to establish)
            if (connectionMonitor.repeatCount > 10) {
                connectionMonitor.stop();
                connectButton.connecting = false;
                connectButton.hasError = true;
                connectButton.enabled = true;
                connectButton.text = qsTr("Connect");
                if (passwordField) {
                    passwordField.text = "";
                }
                // Delete the failed connection
                if (root.network && root.network.ssid) {
                    Nmcli.forgetNetwork(root.network.ssid);
                }
            }
        }
    }

    function closeDialog(): void {
        if (isClosing) {
            return;
        }

        isClosing = true;
        if (passwordField) {
            passwordField.text = "";
        }
        connectButton.connecting = false;
        connectButton.hasError = false;
        connectButton.text = qsTr("Connect");
        connectionMonitor.stop();
        root.popouts.passwordNetwork = null;

        // Return to network popout
        if (root.popouts.currentName === "wirelesspassword") {
            root.popouts.currentName = "network";
        }
    }

    spacing: Tokens.spacing.medium
    implicitWidth: 400
    implicitHeight: content.implicitHeight + Tokens.padding.extraLargeIncreased
    visible: shouldBeVisible || isClosing
    enabled: shouldBeVisible && !isClosing
    focus: enabled

    Component.onCompleted: {
        if (shouldBeVisible) {
            // Use Timer for actual delay to ensure dialog is fully rendered
            focusTimer.start();
        }
    }

    onShouldBeVisibleChanged: {
        if (shouldBeVisible) {
            // Use Timer for actual delay to ensure dialog is fully rendered
            focusTimer.start();
        }
    }

    Keys.onEscapePressed: closeDialog()

    Connections {
        function onCurrentNameChanged() {
            if (root.popouts.currentName === "wirelesspassword") {
                if (!root.network && root.popouts.passwordNetwork) {
                    root.network = root.popouts.passwordNetwork;
                }
                focusTimer.start();
            }
        }

        target: root.popouts
    }

    Timer {
        id: focusTimer

        interval: 150
        onTriggered: {
            root.forceActiveFocus();
            if (passwordField) {
                passwordField.forceActiveFocus();
            }
        }
    }

    StyledRect {
        Layout.fillWidth: true
        Layout.preferredWidth: 400
        implicitHeight: content.implicitHeight + Tokens.padding.extraLargeIncreased
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer
        visible: root.shouldBeVisible || root.isClosing
        opacity: root.shouldBeVisible && !root.isClosing ? 1 : 0
        scale: root.shouldBeVisible && !root.isClosing ? 1 : 0.7
        Keys.onEscapePressed: root.closeDialog()

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }

        ParallelAnimation {
            running: root.isClosing
            onFinished: {
                if (root.isClosing) {
                    root.isClosing = false;
                }
            }

            Anim {
                type: Anim.DefaultEffects
                target: parent
                property: "opacity"
                to: 0
            }
            Anim {
                target: parent
                property: "scale"
                to: 0.7
            }
        }

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.padding.large

            spacing: Tokens.spacing.medium

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "lock"
                fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).build()
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: qsTr("Enter password")
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }

            StyledText {
                id: networkNameText

                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (root.network) {
                        const ssid = root.network.ssid;
                        if (ssid && ssid.length > 0) {
                            return qsTr("Network: %1").arg(ssid);
                        }
                    }
                    return qsTr("Network: Unknown");
                }
                color: Colours.palette.m3outline
                font: Tokens.font.body.small
            }


            StyledText {
                id: statusText

                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacing.small
                visible: connectButton.connecting || connectButton.hasError
                text: {
                    if (connectButton.hasError) {
                        return qsTr("Connection failed. Please check your password and try again.");
                    }
                    if (connectButton.connecting) {
                        return qsTr("Connecting...");
                    }
                    return "";
                }
                color: connectButton.hasError ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.small.weight(Font.Normal).build()
                wrapMode: Text.WordWrap
                Layout.maximumWidth: parent.width - Tokens.padding.extraLargeIncreased
            }

            StyledTextField {
                id: passwordField

                Layout.topMargin: Tokens.spacing.largeIncreased
                Layout.fillWidth: true
                placeholderText: qsTr("Password")
                leadingIcon: "key"
                echoMode: TextInput.Password
                isError: connectButton.hasError
                focus: true

                onAccepted: {
                    if (connectButton.enabled) {
                        connectButton.clicked();
                    }
                }

                onTextEdited: {
                    if (connectButton.hasError) {
                        connectButton.hasError = false;
                    }
                }

                Connections {
                    function onShouldBeVisibleChanged(): void {
                        if (root.shouldBeVisible) {
                            passwordField.text = "";
                            connectButton.hasError = false;
                            focusTimer.start();
                        }
                    }

                    target: root
                }
            }

            RowLayout {
                Layout.topMargin: Tokens.spacing.medium
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                TextButton {
                    id: cancelButton

                    Layout.fillWidth: true
                    Layout.minimumHeight: Tokens.font.body.medium.pointSize + Tokens.padding.medium * 2
                    inactiveColour: Colours.palette.m3secondaryContainer
                    inactiveOnColour: Colours.palette.m3onSecondaryContainer
                    text: qsTr("Cancel")

                    onClicked: root.closeDialog()
                }

                TextButton {
                    id: connectButton

                    property bool connecting: false
                    property bool hasError: false

                    Layout.fillWidth: true
                    Layout.minimumHeight: Tokens.font.body.medium.pointSize + Tokens.padding.medium * 2
                    inactiveColour: Colours.palette.m3primary
                    inactiveOnColour: Colours.palette.m3onPrimary
                    text: qsTr("Connect")
                    enabled: (passwordField?.text?.length ?? 0) > 0 && !connecting

                    onClicked: {
                        if (!root.network || connecting) {
                            return;
                        }

                        const password = passwordField.text;
                        if (!password || password.length === 0) {
                            return;
                        }

                        // Clear any previous error
                        hasError = false;

                        // Set connecting state
                        connecting = true;
                        enabled = false;
                        text = qsTr("Connecting...");

                        // Connect to network
                        NetworkConnection.connectWithPassword(root.network, password, result => {
                            if (result && result.success)
                            // Connection successful, monitor will handle the rest
                            {} else if (result && result.needsPassword) {
                                // Shouldn't happen since we provided password
                                connectionMonitor.stop();
                                connecting = false;
                                hasError = true;
                                enabled = true;
                                text = qsTr("Connect");
                                passwordField.text = "";
                                // Delete the failed connection
                                if (root.network && root.network.ssid) {
                                    Nmcli.forgetNetwork(root.network.ssid);
                                }
                            } else {
                                // Connection failed immediately - show error
                                connectionMonitor.stop();
                                connecting = false;
                                hasError = true;
                                enabled = true;
                                text = qsTr("Connect");
                                passwordField.text = "";
                                // Delete the failed connection
                                if (root.network && root.network.ssid) {
                                    Nmcli.forgetNetwork(root.network.ssid);
                                }
                            }
                        });

                        // Start monitoring connection
                        connectionMonitor.start();
                    }
                }
            }
        }
    }

    Timer {
        id: connectionMonitor

        property int repeatCount: 0

        interval: 1000
        repeat: true
        triggeredOnStart: false

        onTriggered: {
            repeatCount++;
            root.checkConnectionStatus();
        }

        onRunningChanged: {
            if (!running) {
                repeatCount = 0;
            }
        }
    }

    Timer {
        id: connectionSuccessTimer

        interval: 500
        onTriggered: {
            // Double-check connection is still active
            if (root.shouldBeVisible && Nmcli.active && Nmcli.active.ssid) {
                const stillConnected = Nmcli.active.ssid.toLowerCase().trim() === root.network.ssid.toLowerCase().trim();
                if (stillConnected) {
                    connectionMonitor.stop();
                    connectButton.connecting = false;
                    connectButton.text = qsTr("Connect");
                    // Return to network popout on successful connection
                    if (root.popouts.currentName === "wirelesspassword") {
                        root.popouts.currentName = "network";
                    }
                    closeDialog();
                }
            }
        }
    }

    Connections {
        function onActiveChanged() {
            if (root.shouldBeVisible) {
                root.checkConnectionStatus();
            }
        }

        function onConnectionFailed(ssid: string) {
            if (root.shouldBeVisible && root.network && root.network.ssid === ssid && connectButton.connecting) {
                connectionMonitor.stop();
                connectButton.connecting = false;
                connectButton.hasError = true;
                connectButton.enabled = true;
                connectButton.text = qsTr("Connect");
                if (passwordField) {
                    passwordField.text = "";
                }
                // Delete the failed connection
                Nmcli.forgetNetwork(ssid);
            }
        }

        target: Nmcli
    }
}
