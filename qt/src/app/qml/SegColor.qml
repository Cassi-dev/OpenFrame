import QtQuick
import "Fmt.js" as Fmt

ColorRow {
    property var seg: Editor.selectedSegment
    property string path
    color: Fmt.color(Fmt.at(seg, path, null), "white")
    onPicked: (c) => Editor.setSegmentValue(path, c)
}
