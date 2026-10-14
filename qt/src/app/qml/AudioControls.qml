import QtQuick
import "Fmt.js" as Fmt

Column {
    width: parent ? parent.width : implicitWidth
    spacing: 12
    SectionHeader { title: "Som" }
    SegSlider { title: "Volume"; path: "volume"; from: 0; to: 1; defaultValue: 1; format: Fmt.percent }
    SegSlider { title: "Fade de entrada"; path: "fadeIn"; scale: 1e-6; from: 0; to: 5; format: Fmt.seconds }
    SegSlider { title: "Fade de saída"; path: "fadeOut"; scale: 1e-6; from: 0; to: 5; format: Fmt.seconds }
}
