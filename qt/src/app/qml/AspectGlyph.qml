import QtQuick

// Retângulo na proporção do formato, encaixado no quadro disponível.
Item {
    id: glyph
    property real aspect: 16 / 9
    property bool highlighted: false

    Rectangle {
        anchors.centerIn: parent
        width: glyph.aspect >= glyph.width / Math.max(glyph.height, 1) ? glyph.width : glyph.height * glyph.aspect
        height: glyph.aspect >= glyph.width / Math.max(glyph.height, 1) ? glyph.width / glyph.aspect : glyph.height
        radius: 4
        color: "transparent"
        border.width: 1.5
        border.color: glyph.highlighted ? Theme.accent : Theme.textSecondary
    }
}
