import QtQuick
import QtQuick.Templates as T

// Cartão de criação da tela inicial: um desenho no topo, título e subtítulo embaixo.
T.AbstractButton {
    id: card
    property string title
    property string subtitle
    property string help
    /// Borda ciano no hover (o cartão "Novo projeto").
    property bool accentBorder: false
    default property alias glyph: glyphHolder.data

    implicitHeight: 140
    hoverEnabled: true
    focusPolicy: Qt.NoFocus

    background: Rectangle {
        radius: Theme.cardRadius + 2
        color: card.hovered ? Theme.raisedHigh : Theme.raised
        border.color: card.hovered && card.accentBorder ? Theme.alpha(Theme.accent, 0.6) : Theme.hairline
    }
    contentItem: Item {
        Item {
            id: glyphHolder
            x: 16
            y: 16
            width: 48
            height: 48
        }
        Column {
            x: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            width: parent.width - 32
            spacing: 2
            OfText { width: parent.width; text: card.title; size: 14; weight: Theme.medium }
            OfText { width: parent.width; text: card.subtitle; size: 11; color: Theme.textTertiary }
        }
    }
    Tip { text: card.help }
}
