import QtQuick

PillPicker {
    width: parent ? parent.width : implicitWidth
    options: [0.5, 1, 1.5, 2, 3].map(s => ({ value: s, title: s + "x" }))
    value: Editor.selectedSegment.speed
    onPicked: (v) => Editor.setSpeed(v)
}
