import QtQuick

// Painel flutuante sobre o fundo preto.
Rectangle {
    property real panelRadius: Theme.panelRadius
    radius: panelRadius
    color: Theme.surface
    border.color: Theme.hairline
    clip: true
}
