import QtQuick
import QtQuick.Dialogs

// Seletor de cor como linha de formulário.
FieldRow {
    id: root
    property string title
    property color color: "white"
    signal picked(color color)

    label: title

    Rectangle {
        id: swatch
        width: 44
        height: 22
        radius: 6
        color: root.color
        border.color: Qt.rgba(1, 1, 1, 0.25)
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: dialog.open()
        }
    }
    ColorDialog {
        id: dialog
        title: root.title
        selectedColor: root.color
        options: ColorDialog.ShowAlphaChannel
        onAccepted: root.picked(selectedColor)
    }
}
