import QtQuick

// Interruptor com rótulo, no ciano da marca.
Item {
    id: root
    property string title
    property bool checked: false
    signal toggled(bool checked)

    width: parent ? parent.width : implicitWidth
    implicitHeight: 20

    OfText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        size: 12
        color: Theme.textSecondary
    }
    Rectangle {
        id: track
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 15
        radius: height / 2
        color: root.checked ? Theme.accent : Qt.rgba(1, 1, 1, 0.16)
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 13
            height: 13
            radius: width / 2
            y: 1
            x: root.checked ? parent.width - width - 1 : 1
            color: "white"
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
        }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.toggled(!root.checked)
    }
}
