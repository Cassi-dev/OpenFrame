import QtQuick
import "Fmt.js" as Fmt

SwitchRow {
    property var seg: Editor.selectedSegment
    property string path
    checked: Fmt.at(seg, path, false)
    onToggled: (on) => Editor.setSegmentValue(path, on)
}
