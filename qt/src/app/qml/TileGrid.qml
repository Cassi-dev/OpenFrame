import QtQuick

// Grade adaptável de cartões (colunas de pelo menos 80, espaço 8 × 12).
Flow {
    id: grid
    property real minimum: 80
    width: parent ? parent.width : implicitWidth
    spacing: 8
    readonly property int columns: Math.max(1, Math.floor((width + spacing) / (minimum + spacing)))
    readonly property real tileWidth: (width - spacing * (columns - 1)) / columns
}
