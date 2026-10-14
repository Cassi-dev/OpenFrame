import QtQuick
import "Fmt.js" as Fmt

Column {
    id: tab
    readonly property var seg: Editor.selectedSegment
    readonly property var effects: seg.effects || []
    function active(kind) {
        for (let i = 0; i < effects.length; ++i)
            if (effects[i].kind === kind) return true
        return false
    }
    spacing: 12

    TileGrid {
        id: grid
        topPadding: 8
        Repeater {
            model: Editor.effectOptions()
            ChoiceTile {
                required property var modelData
                width: grid.tileWidth
                text: modelData.title
                iconName: modelData.icon
                selected: tab.active(modelData.value)
                onClicked: Editor.toggleEffect(modelData.value)
            }
        }
    }
    SectionHeader {
        visible: tab.effects.length > 0
        title: "Aplicados"
        hasAction: true
        onAction: Editor.resetSegment("effects")
    }
    Repeater {
        model: tab.effects.length
        SegSlider {
            required property int index
            title: Editor.effectOptions().find(e => e.value === tab.effects[index].kind).title
            path: "effects." + index + ".intensity"
            from: 0; to: 1; defaultValue: 0.5
            format: Fmt.percent
        }
    }
}
