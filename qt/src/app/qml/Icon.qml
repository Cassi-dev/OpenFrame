import QtQuick

// Ícone da fonte Lucide, centrado numa caixa quadrada.
Text {
    property string name
    property real size: 14

    text: Icons.glyph(name)
    color: Theme.textSecondary
    font.family: Theme.iconFamily
    font.pixelSize: size
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    width: size
    height: size
}
