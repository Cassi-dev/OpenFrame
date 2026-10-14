import QtQuick
import "Fmt.js" as Fmt

// Slider de um campo do segmento selecionado (caminho das chaves do JSON).
ParamSlider {
    property var seg: Editor.selectedSegment
    property string path
    /// Multiplica o valor guardado para mostrar (µs → s com 1e-6).
    property real scale: 1

    value: Fmt.at(seg, path, defaultValue / scale) * scale
    onMoved: (v) => Editor.setSegmentValue(scale === 1 ? path : path + "Seconds", v)
}
