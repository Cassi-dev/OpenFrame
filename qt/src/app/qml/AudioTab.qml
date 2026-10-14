import QtQuick
import "Fmt.js" as Fmt

Column {
    spacing: 12
    AudioControls {}
    SectionHeader { title: "Velocidade" }
    SpeedPresets {}
    SegSlider { title: "Velocidade"; path: "speed"; from: 0.25; to: 4; defaultValue: 1; format: Fmt.speed }
    Note { text: "O tom é preservado ao mudar a velocidade." }
}
