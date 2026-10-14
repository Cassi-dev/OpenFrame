import QtQuick
import "Fmt.js" as Fmt

Column {
    id: tab
    readonly property var seg: Editor.selectedSegment
    spacing: 12

    SectionHeader { title: "Transformar"; hasAction: true; onAction: Editor.resetSegment("transform") }
    SegSlider { title: "Escala"; path: "transform.scale"; from: 0.1; to: 4; defaultValue: 1; format: Fmt.percent }
    SegSlider { title: "Posição X"; path: "transform.x"; format: Fmt.signedPercent }
    SegSlider { title: "Posição Y"; path: "transform.y"; format: Fmt.signedPercent }
    SegSlider { title: "Rotação"; path: "transform.rotation"; from: -180; to: 180; format: Fmt.degrees }
    SegSlider { title: "Opacidade"; path: "opacity"; from: 0; to: 1; defaultValue: 1; format: Fmt.percent }

    SectionHeader { title: "Velocidade" }
    SpeedPresets {}
    SegSlider { title: "Velocidade"; path: "speed"; from: 0.1; to: 4; defaultValue: 1; format: Fmt.speed }

    Loader {
        width: parent.width
        active: tab.seg.hasAudio === true
        visible: active
        sourceComponent: AudioControls {}
    }
}
