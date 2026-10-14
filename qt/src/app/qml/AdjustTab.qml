import QtQuick
import "Fmt.js" as Fmt

Column {
    spacing: 12
    SectionHeader { title: "Luz e cor"; hasAction: true; onAction: Editor.resetSegment("adjust") }
    SegSlider { title: "Brilho"; path: "adjust.brightness"; format: Fmt.signedPercent }
    SegSlider { title: "Contraste"; path: "adjust.contrast"; format: Fmt.signedPercent }
    SegSlider { title: "Saturação"; path: "adjust.saturation"; format: Fmt.signedPercent }
    SegSlider { title: "Exposição"; path: "adjust.exposure"; format: Fmt.signedPercent }
    SegSlider { title: "Temperatura"; path: "adjust.temperature"; format: Fmt.signedPercent }
    SegSlider { title: "Matiz (tint)"; path: "adjust.tint"; format: Fmt.signedPercent }
    SegSlider { title: "Realces"; path: "adjust.highlights"; format: Fmt.signedPercent }
    SegSlider { title: "Sombras"; path: "adjust.shadows"; format: Fmt.signedPercent }
    SegSlider { title: "Tom (hue)"; path: "adjust.hue"; format: Fmt.signedPercent }
    SectionHeader { title: "Detalhes" }
    SegSlider { title: "Nitidez"; path: "adjust.sharpen"; from: 0; to: 1; format: Fmt.percent }
    SegSlider { title: "Vinheta"; path: "adjust.vignette"; from: 0; to: 1; format: Fmt.percent }
    SegSlider { title: "Desbotar"; path: "adjust.fade"; from: 0; to: 1; format: Fmt.percent }
    SegSlider { title: "Granulado"; path: "adjust.grain"; from: 0; to: 1; format: Fmt.percent }
}
