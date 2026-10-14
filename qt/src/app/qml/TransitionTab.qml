import QtQuick
import "Fmt.js" as Fmt

Column {
    id: tab
    readonly property var seg: Editor.selectedSegment
    readonly property string current: Fmt.at(seg, "transition.kind", "")
    spacing: 12

    Note { text: "Para o próximo clipe da faixa principal." }
    TileGrid {
        id: grid
        ChoiceTile {
            width: grid.tileWidth
            text: "Nenhuma"
            iconName: "ban"
            selected: tab.current === ""
            onClicked: Editor.setTransition("")
        }
        Repeater {
            model: Editor.transitionOptions()
            ChoiceTile {
                required property var modelData
                width: grid.tileWidth
                text: modelData.title
                iconName: "arrow-left-right"
                selected: tab.current === modelData.value
                onClicked: Editor.setTransition(modelData.value)
            }
        }
    }
    SegSlider {
        visible: tab.current !== ""
        title: "Duração"
        path: "transition.duration"
        scale: 1e-6
        from: 0.1; to: 2; defaultValue: 0.5
        format: Fmt.seconds
    }
    Note {
        visible: tab.current !== ""
        text: "A transição sobrepõe o fim deste clipe ao início do próximo."
    }
}
