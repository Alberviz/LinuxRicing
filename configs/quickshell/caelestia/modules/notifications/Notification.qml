pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Notifications
import Caelestia.Components
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

StyledRect {
    id: root

    required property NotifData modelData
    property int defaultWidth: Tokens.sizes.notifs.width
    readonly property int miniBadgeSize: 48
    readonly property bool isAgent: modelData.isAgent
    readonly property bool hasImage: modelData.image.length > 0
    readonly property bool hasAppIcon: modelData.appIcon.length > 0
    readonly property bool minimized: modelData.minimized ?? false
    readonly property int bodyTextFormat: /[<*_`#\[\]]/.test(modelData.body) ? Text.MarkdownText : Text.PlainText
    readonly property int nonAnimHeight: root.minimized ? root.miniBadgeSize : (summary.implicitHeight + (root.expanded ? Tokens.spacing.extraSmall * 2 + appName.height + body.height + actions.height + actions.anchors.topMargin : bodyPreview.height) + inner.anchors.margins * 2)
    property bool expanded: Config.notifs.openExpanded

    color: root.minimized ? Colours.palette.m3primaryContainer : (root.modelData.urgency === NotificationUrgency.Critical ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer)
    radius: root.minimized ? Tokens.rounding.full : Tokens.rounding.large
    border.width: root.minimized ? 2 : 0
    border.color: Colours.palette.m3primary

    implicitWidth: root.minimized ? root.miniBadgeSize : root.defaultWidth
    implicitHeight: root.minimized ? root.miniBadgeSize : inner.implicitHeight
    width: implicitWidth
    height: implicitHeight

    SequentialAnimation on scale {
        running: root.minimized
        loops: Animation.Infinite
        NumberAnimation { to: 1.06; duration: 1000; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 1000; easing.type: Easing.InOutSine }
    }

    Behavior on width {
        Anim {
            easing: Tokens.anim.emphasizedDecel
        }
    }

    Behavior on height {
        Anim {
            easing: Tokens.anim.emphasizedDecel
        }
    }

    Behavior on implicitWidth {
        Anim {
            easing: Tokens.anim.emphasizedDecel
        }
    }

    Behavior on implicitHeight {
        Anim {
            easing: Tokens.anim.emphasizedDecel
        }
    }

    x: implicitWidth
    Component.onCompleted: {
        x = 0;
        modelData.lock(this);
    }
    Component.onDestruction: modelData.unlock(this)

    Behavior on x {
        Anim {
            easing: Tokens.anim.emphasizedDecel
        }
    }

    MouseArea {
        property int startY

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.minimized ? Qt.PointingHandCursor : (root.expanded && body.hoveredLink ? Qt.PointingHandCursor : pressed ? Qt.ClosedHandCursor : undefined)
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        preventStealing: true

        onEntered: root.modelData.timer.stop()
        onExited: {
            if (!pressed)
                root.modelData.timer.start();
        }

        drag.target: root.minimized ? null : parent
        drag.axis: Drag.XAxis

        onPressed: event => {
            root.modelData.timer.stop();
            startY = event.y;
            if (event.button === Qt.MiddleButton || (root.minimized && event.button === Qt.RightButton))
                root.modelData.close();
        }
        onReleased: event => {
            if (!containsMouse)
                root.modelData.timer.start();

            if (!root.minimized) {
                if (Math.abs(root.x) < root.implicitWidth * Config.notifs.clearThreshold)
                    root.x = 0;
                else
                    root.modelData.popup = false;
            }
        }
        onPositionChanged: event => {
            if (pressed && !root.minimized) {
                const diffY = event.y - startY;
                if (Math.abs(diffY) > Config.notifs.expandThreshold)
                    root.expanded = diffY > 0;
            }
        }
        onClicked: event => {
            if (event.button !== Qt.LeftButton)
                return;

            const addr = root.modelData.hints?.address ?? "";
            if (addr && String(addr).length > 0) {
                Agents.focus(String(addr));
                root.modelData.close();
                return;
            }

            if (!GlobalConfig.notifs.actionOnClick)
                return;

            const actions = root.modelData.actions;
            if (actions.length > 0)
                actions[0].invoke();
        }

        Item {
            id: miniBadge

            anchors.fill: parent
            visible: root.minimized

            MaterialIcon {
                anchors.centerIn: parent
                text: "smart_toy"
                color: Colours.palette.m3onPrimaryContainer
                fontStyle: Tokens.font.icon.large
            }

            StyledRect {
                id: wsBadge

                visible: root.modelData.wsNum.length > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -2
                anchors.rightMargin: -2
                implicitWidth: 20
                implicitHeight: 20
                radius: Tokens.rounding.full
                color: Colours.palette.m3primary
                border.width: 1.5
                border.color: Colours.palette.m3surface

                StyledText {
                    anchors.centerIn: parent
                    text: root.modelData.wsNum
                    color: Colours.palette.m3onPrimary
                    font: Tokens.font.label.small
                }
            }
        }

        Item {
            id: inner

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            visible: !root.minimized

            implicitHeight: root.nonAnimHeight

            Behavior on implicitHeight {
                Anim {}
            }

            Loader {
                id: image

                asynchronous: true
                active: root.hasImage

                anchors.left: parent.left
                anchors.top: parent.top
                width: TokenConfig.sizes.notifs.image
                height: TokenConfig.sizes.notifs.image
                visible: root.hasImage || root.hasAppIcon

                sourceComponent: StyledClippingRect {
                    radius: Tokens.rounding.full
                    color: root.modelData.urgency === NotificationUrgency.Critical ? Colours.palette.m3error : root.modelData.urgency === NotificationUrgency.Low ? Colours.layer(Colours.palette.m3surfaceContainerHighest, 2) : Colours.palette.m3secondaryContainer
                    implicitWidth: TokenConfig.sizes.notifs.image
                    implicitHeight: TokenConfig.sizes.notifs.image

                    Image {
                        anchors.fill: parent
                        source: Qt.resolvedUrl(root.modelData.image)
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: {
                            const size = TokenConfig.sizes.notifs.image * ((QsWindow.window as QsWindow)?.devicePixelRatio ?? 1);
                            return Qt.size(size, size);
                        }
                        cache: false
                        asynchronous: true
                    }
                }
            }

            Loader {
                id: appIcon

                asynchronous: true
                active: root.hasAppIcon || !root.hasImage

                anchors.horizontalCenter: root.hasImage ? undefined : image.horizontalCenter
                anchors.verticalCenter: root.hasImage ? undefined : image.verticalCenter
                anchors.right: root.hasImage ? image.right : undefined
                anchors.bottom: root.hasImage ? image.bottom : undefined

                sourceComponent: StyledRect {
                    radius: Tokens.rounding.full
                    color: root.modelData.urgency === NotificationUrgency.Critical ? Colours.palette.m3error : root.modelData.urgency === NotificationUrgency.Low ? Colours.layer(Colours.palette.m3surfaceContainerHighest, 2) : Colours.palette.m3secondaryContainer
                    implicitWidth: root.hasImage ? Tokens.sizes.notifs.badge : TokenConfig.sizes.notifs.image
                    implicitHeight: root.hasImage ? Tokens.sizes.notifs.badge : TokenConfig.sizes.notifs.image

                    Loader {
                        id: icon

                        asynchronous: true
                        active: !root.isAgent && root.hasAppIcon && (Quickshell.iconPath(root.modelData.appIcon) ?? "").length > 0

                        anchors.centerIn: parent

                        width: Math.round(parent.width * 0.6)
                        height: Math.round(parent.width * 0.6)

                        sourceComponent: ColouredIcon {
                            anchors.fill: parent
                            source: Quickshell.iconPath(root.modelData.appIcon)
                            colour: root.modelData.urgency === NotificationUrgency.Critical ? Colours.palette.m3onError : root.modelData.urgency === NotificationUrgency.Low ? Colours.palette.m3onSurface : Colours.palette.m3onSecondaryContainer
                            layer.enabled: root.modelData.appIcon.endsWith("symbolic")
                        }
                    }

                    Loader {
                        asynchronous: true
                        active: root.isAgent || !root.hasAppIcon || (Quickshell.iconPath(root.modelData.appIcon) ?? "").length === 0
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 1

                        sourceComponent: MaterialIcon {
                            text: root.isAgent ? "smart_toy" : Icons.getNotifIcon(root.modelData.summary, root.modelData.urgency)
                            color: root.modelData.urgency === NotificationUrgency.Critical ? Colours.palette.m3onError : root.modelData.urgency === NotificationUrgency.Low ? Colours.palette.m3onSurface : Colours.palette.m3onSecondaryContainer
                            fontStyle: Tokens.font.icon.medium
                        }
                    }
                }
            }

            Shape {
                id: progressIndicator

                anchors.centerIn: appIcon
                width: appIcon.implicitWidth + progressShape.strokeWidth * 2
                height: appIcon.implicitHeight + progressShape.strokeWidth * 2
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    id: progressShape

                    capStyle: ShapePath.RoundCap
                    fillColor: "transparent"
                    strokeWidth: 2
                    strokeColor: Colours.palette.m3primary

                    PathAngleArc {
                        id: progressArc

                        radiusX: progressIndicator.width / 2 - root.Tokens.padding.extraSmall / 2
                        centerX: progressIndicator.width / 2
                        radiusY: progressIndicator.height / 2 - root.Tokens.padding.extraSmall / 2
                        centerY: progressIndicator.height / 2

                        startAngle: -90
                        sweepAngle: ((root.modelData.hints.value ?? 0) / 100) * 360

                        Behavior on sweepAngle {
                            Anim {
                                easing: Tokens.anim.emphasizedDecel
                            }
                        }
                    }
                }
            }

            StyledText {
                id: appName

                anchors.top: parent.top
                anchors.left: image.right
                anchors.leftMargin: Tokens.spacing.medium

                animate: true
                text: appNameMetrics.elidedText
                maximumLineCount: 1
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.label.medium

                opacity: !root.minimized && root.expanded ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            TextMetrics {
                id: appNameMetrics

                text: root.modelData.appName
                font: appName.font
                elide: Text.ElideRight
                elideWidth: expandBtn.x - time.width - timeSep.width - summary.x - root.Tokens.spacing.small * 3
            }

            StyledText {
                id: summary

                anchors.top: parent.top
                anchors.left: image.right
                anchors.leftMargin: Tokens.spacing.medium

                animate: true
                text: summaryMetrics.elidedText
                maximumLineCount: 1
                color: root.minimized ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                height: implicitHeight

                states: [
                    State {
                        name: "minimized"
                        when: root.minimized

                        AnchorChanges {
                            target: summary
                            anchors.top: undefined
                            anchors.verticalCenter: image.verticalCenter
                        }
                    },
                    State {
                        name: "expanded"
                        when: root.expanded && !root.minimized

                        PropertyChanges {
                            summary.maximumLineCount: undefined
                            summary.anchors.topMargin: root.Tokens.spacing.extraSmall
                            bodyPreview.anchors.topMargin: root.Tokens.spacing.extraSmall
                            body.anchors.topMargin: root.Tokens.spacing.extraSmall
                        }

                        AnchorChanges {
                            target: summary
                            anchors.top: appName.bottom
                        }
                    }
                ]

                transitions: Transition {
                    PropertyAction {
                        target: summary
                        property: "maximumLineCount"
                    }
                    Anim {
                        property: "topMargin"
                    }
                    AnchorAnim {}
                }

                Behavior on height {
                    Anim {}
                }
            }

            TextMetrics {
                id: summaryMetrics

                text: root.modelData.summary
                font: summary.font
                elide: Text.ElideRight
                elideWidth: expandBtn.x - (root.minimized ? 0 : (time.width + timeSep.width)) - summary.x - root.Tokens.spacing.small * 3
            }

            StyledText {
                id: timeSep

                anchors.top: parent.top
                anchors.left: summary.right
                anchors.leftMargin: Tokens.spacing.small
                opacity: !root.minimized ? 1 : 0

                text: "•"
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small

                states: State {
                    name: "expanded"
                    when: root.expanded && !root.minimized

                    AnchorChanges {
                        target: timeSep
                        anchors.left: appName.right
                    }
                }

                transitions: Transition {
                    AnchorAnim {}
                }
            }

            StyledText {
                id: time

                anchors.top: parent.top
                anchors.left: timeSep.right
                anchors.leftMargin: Tokens.spacing.small
                opacity: !root.minimized ? 1 : 0

                animate: true
                horizontalAlignment: Text.AlignLeft
                text: root.modelData.timeStr
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }

            Item {
                id: expandBtn

                anchors.right: parent.right
                anchors.top: root.minimized ? undefined : parent.top
                anchors.verticalCenter: root.minimized ? image.verticalCenter : undefined
                anchors.topMargin: -Tokens.padding.extraSmall

                implicitWidth: expandIcon.implicitHeight
                implicitHeight: expandIcon.implicitHeight

                StateLayer {
                    radius: Tokens.rounding.full
                    color: root.minimized ? Colours.palette.m3onPrimaryContainer : (root.modelData.urgency === NotificationUrgency.Critical ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface)
                    onClicked: {
                        if (root.minimized) {
                            root.modelData.minimized = false;
                            root.expanded = true;
                        } else {
                            root.expanded = !root.expanded;
                        }
                    }
                }

                MaterialIcon {
                    id: expandIcon

                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: !root.minimized && root.expanded ? -1 : 1
                    text: root.minimized ? "open_in_full" : "expand_more"
                    color: root.minimized ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                    rotation: root.minimized ? 0 : (root.expanded ? 180 : 0)

                    Behavior on anchors.verticalCenterOffset {
                        Anim {}
                    }

                    Behavior on rotation {
                        Anim {}
                    }
                }
            }

            StyledText {
                id: bodyPreview

                anchors.left: summary.left
                anchors.right: expandBtn.left
                anchors.top: summary.bottom
                anchors.rightMargin: Tokens.spacing.small

                animate: true
                textFormat: root.bodyTextFormat
                text: bodyPreviewMetrics.elidedText
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small

                opacity: !root.minimized && !root.expanded ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            TextMetrics {
                id: bodyPreviewMetrics

                text: root.modelData.body
                font: bodyPreview.font
                elide: Text.ElideRight
                elideWidth: bodyPreview.width
            }

            StyledText {
                id: body

                anchors.left: summary.left
                anchors.right: expandBtn.left
                anchors.top: summary.bottom
                anchors.rightMargin: Tokens.spacing.small

                animate: true
                textFormat: root.bodyTextFormat
                text: root.modelData.body
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                height: text ? implicitHeight : 0

                onLinkActivated: link => {
                    if (!root.expanded)
                        return;

                    Qt.openUrlExternally(link);
                    root.modelData.popup = false;
                }

                opacity: !root.minimized && root.expanded ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }

            ButtonRow {
                id: actions

                anchors.left: body.left
                anchors.right: body.right
                anchors.top: body.bottom
                anchors.topMargin: Tokens.spacing.small

                spacing: Tokens.spacing.extraSmall
                opacity: !root.minimized && root.expanded ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }

                IconButton {
                    isRound: true
                    shapeMorph: true
                    fillWidth: root.modelData.actions.length === 0
                    inactiveColour: root.modelData.urgency === NotificationUrgency.Critical ? Colours.palette.m3secondary : Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
                    inactiveOnColour: root.modelData.urgency === NotificationUrgency.Critical ? Colours.palette.m3onSecondary : Colours.palette.m3onSurfaceVariant
                    icon: "close"
                    padding: Tokens.padding.extraSmall
                    onClicked: root.modelData.close()
                }

                Repeater {
                    model: root.modelData.actions

                    TextButton {
                        required property var modelData

                        isRound: true
                        shapeMorph: true
                        fillWidth: true
                        inactiveColour: root.modelData.urgency === NotificationUrgency.Critical ? Colours.palette.m3secondary : Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
                        inactiveOnColour: root.modelData.urgency === NotificationUrgency.Critical ? Colours.palette.m3onSecondary : Colours.palette.m3onSurfaceVariant
                        text: modelData.text
                        onClicked: modelData.invoke()

                        label.horizontalAlignment: Text.AlignHCenter
                        label.anchors.left: left
                        label.anchors.right: right
                        label.anchors.verticalCenter: verticalCenter
                        label.anchors.centerIn: undefined
                        label.anchors.margins: Tokens.padding.medium
                        label.elide: Text.ElideRight
                    }
                }

                IconButton {
                    isRound: true
                    shapeMorph: true
                    fillWidth: root.modelData.actions.length === 0
                    inactiveColour: root.modelData.urgency === NotificationUrgency.Critical ? Colours.palette.m3secondary : Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
                    inactiveOnColour: root.modelData.urgency === NotificationUrgency.Critical ? Colours.palette.m3onSecondary : Colours.palette.m3onSurfaceVariant
                    icon: copyTimer.running ? "inventory" : "content_copy"
                    padding: Tokens.padding.extraSmall
                    onClicked: {
                        Quickshell.clipboardText = root.modelData.body;
                        copyTimer.restart();
                    }
                    label.animate: true

                    Timer {
                        id: copyTimer

                        interval: 3000
                    }
                }
            }
        }
    }
}
