import QtQuick

QtObject {
    property string currentName
    property bool hasCurrent
    property int agentsWs: 0

    signal detachRequested(mode: string)
}
