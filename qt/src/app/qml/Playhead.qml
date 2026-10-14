import QtQuick

// Playhead com a cabeça da agulha, que leva o tempo atual. A cabeça pode ser
// arrastada; a linha deixa os cliques passarem para os clipes.
Item {
    id: playhead
    readonly property real headWidth: 60
    readonly property real glow: 6

    /// Posição do tempo 0 no item pai.
    property real originX: 0

    x: originX + Editor.playhead * Editor.zoom - headWidth / 2
    width: headWidth

    // Linha com um brilho suave.
    Rectangle {
        x: playhead.headWidth / 2 - 2.5
        y: 24
        width: 5
        height: playhead.height - y
        color: Theme.alpha(Theme.accent, 0.18)
        radius: 2.5
    }
    Rectangle {
        x: playhead.headWidth / 2 - 0.75
        y: 24
        width: 1.5
        height: playhead.height - y
        color: Theme.accent
    }

    NeedleHead {
        x: -playhead.glow
        y: 4 - playhead.glow
        width: playhead.headWidth + playhead.glow * 2
        height: 21 + playhead.glow
        glow: playhead.glow
        color: Theme.accent
    }
    OfText {
        x: 0
        y: 4
        width: playhead.headWidth
        height: 16
        horizontalAlignment: Text.AlignHCenter
        text: Editor.playheadText
        size: 9.5
        weight: Theme.medium
        mono: true
        color: Theme.textOnAccent
    }
    MouseArea {
        x: 0
        y: 4
        width: playhead.headWidth
        height: 21
        cursorShape: Qt.SizeHorCursor
        preventStealing: true
        hoverEnabled: true
        property real pressX
        property real startTime
        onPressed: (m) => {
            pressX = mapToItem(null, m.x, m.y).x
            startTime = Editor.playhead
        }
        onPositionChanged: (m) => {
            if (!pressed) return
            Editor.scrub(startTime + (mapToItem(null, m.x, m.y).x - pressX) / Editor.zoom)
        }
        readonly property bool hovered: containsMouse
        Tip { text: "Arraste para navegar" }
    }
}
