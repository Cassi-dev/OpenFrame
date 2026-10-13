import QtQuick

// Texto na Inter com os tamanhos e pesos do tema; `mono` liga os dígitos de
// largura fixa (tnum), como o `Theme.mono` do app Swift.
Text {
    property real size: 12
    property int weight: Theme.regular
    property bool mono: false

    color: Theme.textPrimary
    font.family: Theme.family
    font.pixelSize: size
    font.weight: weight
    font.features: mono ? ({ "tnum": 1 }) : ({})
    elide: Text.ElideRight
    maximumLineCount: wrapMode === Text.NoWrap ? 1 : 1000
    verticalAlignment: Text.AlignVCenter
}
