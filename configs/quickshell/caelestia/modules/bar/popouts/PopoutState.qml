import QtQuick

QtObject {
    property string currentName
    property bool hasCurrent
    property int agentsWs: 0
    property var passwordNetwork: null

    onHasCurrentChanged: {
        if (!hasCurrent) {
            passwordNetwork = null;
        }
    }

    signal detachRequested(mode: string)
}
