pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

// Sub-page for connecting to a secured Wi-Fi network requiring a password.
// Reached from NetworkList / AllNetworksPage via nState.openSubPage(7).
PageBase {
    id: root

    readonly property string ssid: nState.pendingNetwork?.ssid ?? nState.selectedNetworkSsid ?? ""
    readonly property var network: nState.pendingNetwork ?? Nmcli.findNetwork(root.ssid) ?? ({ ssid: root.ssid, isSecure: true, bssid: "" })
    property bool connecting: false
    property bool failed: false
    property bool success: false

    function submit(): void {
        const password = passwordField.text;
        if (password.length === 0) {
            passwordField.isError = true;
            passwordField.forceActiveFocus();
            return;
        }

        root.failed = false;
        root.connecting = true;

        NetworkConnection.connectWithPassword(root.network, password, result => {
            root.connecting = false;
            if (result && result.success) {
                root.success = true;
                root.nState.closeSubPage();
            } else {
                root.failed = true;
                passwordField.isError = true;
                passwordField.forceActiveFocus();
                if (root.ssid) {
                    Nmcli.forgetNetwork(root.ssid);
                }
            }
        });
    }

    title: root.ssid ? root.ssid : qsTr("Connect to Wi-Fi")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        Connections {
            function onSubPageClosed(): void {
                root.nState.pendingNetwork = null;
            }

            target: root.nState
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.extraSmall
            text: qsTr("Enter the password for \"%1\"").arg(root.ssid)
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        StyledTextField {
            id: passwordField

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.extraSmall
            placeholderText: qsTr("Password")
            leadingIcon: "key"
            echoMode: TextInput.Password
            supportingText: qsTr("WPA passwords are at least 8 characters")
            errorText: root.failed ? qsTr("Connection failed — check the password") : qsTr("Password is required")
            focus: true

            Component.onCompleted: forceActiveFocus()

            onAccepted: root.submit()
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            Layout.topMargin: Tokens.spacing.extraSmall - parent.spacing
            spacing: Tokens.spacing.small

            TextButton {
                Layout.fillHeight: true
                isRound: true
                horizontalPadding: Tokens.padding.extraLarge
                type: TextButton.Tonal
                text: qsTr("Cancel")
                onClicked: root.nState.closeSubPage()
            }

            ButtonBase {
                id: connectBtn

                shapeMorph: true
                isRound: true
                inactiveColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onPrimary
                stateLayer.disabled: root.connecting || passwordField.text.length === 0

                implicitWidth: connectMetrics.width + Tokens.padding.extraLarge * 2
                implicitHeight: connectMetrics.height + Tokens.padding.medium * 2

                onClicked: {
                    if (!root.connecting && passwordField.text.length > 0)
                        root.submit();
                }

                TextMetrics {
                    id: connectMetrics

                    text: qsTr("Connect")
                    font: connectBtn.font
                }

                AnimLoader {
                    id: connectContent

                    anchors.centerIn: parent
                    sourceComp: root.connecting ? connectLoadingComp : connectTextComp
                    outAnimType: Anim.SlowEffects
                    inAnimType: Anim.SlowEffects
                }

                Component {
                    id: connectLoadingComp

                    LoadingIndicator {
                        implicitSize: Math.round(Tokens.font.body.medium.pointSize * 1.4)
                        color: connectBtn.onColour
                    }
                }

                Component {
                    id: connectTextComp

                    StyledText {
                        text: connectMetrics.text
                        font: connectBtn.font
                        color: connectBtn.onColour
                    }
                }
            }
        }
    }
}
