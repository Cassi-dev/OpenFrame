import QtQuick
import "Fmt.js" as Fmt

Column {
    id: tab
    readonly property var seg: Editor.selectedSegment
    readonly property var kinds: Editor.animationOptions(seg.isText === true)
    spacing: 12

    component Picker: Column {
        id: picker
        property string title
        property string key
        property string which
        readonly property var anim: Fmt.at(tab.seg, key, null)
        width: parent.width
        spacing: 12
        SectionHeader { title: picker.title }
        FieldRow {
            label: "Tipo"
            MenuField {
                options: tab.kinds
                value: picker.anim ? picker.anim.kind : ""
                onPicked: (v) => Editor.setAnimation(picker.which, v)
            }
        }
        SegSlider {
            visible: picker.anim !== null
            title: "Duração"
            path: picker.key + ".duration"
            scale: 1e-6
            from: 0.1; to: 3; defaultValue: 0.5
            format: Fmt.seconds
        }
    }

    Picker { title: "Entrada"; key: "animationIn"; which: "in" }
    Picker { title: "Saída"; key: "animationOut"; which: "out" }
}
