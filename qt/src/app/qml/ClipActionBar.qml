import QtQuick

// Ações do clipe selecionado, flutuando junto dele: acima do clipe ou, na
// primeira faixa, abaixo (para não cobrir a régua). Fica dentro da área visível.
Rectangle {
    id: bar
    property real viewportWidth: 0

    readonly property var seg: Editor.selectedSegment
    readonly property int row: Editor.selectedRow
    readonly property real start: (seg.start || 0) * Editor.zoom
    readonly property real end: (seg.end || 0) * Editor.zoom
    readonly property bool canSplit: Editor.playhead > (seg.start || 0) && Editor.playhead < (seg.end || 0)
    readonly property int actions: canSplit ? 3 : 2
    readonly property real barWidth: actions * 30 + (actions - 1) + 8

    // Ao lado da linha do playhead (ou no início do clipe), dentro da área
    // visível, sem se afastar do clipe e sem passar das bordas do conteúdo.
    readonly property real anchorX: canSplit ? Editor.playhead * Editor.zoom + 8 : start + 8
    readonly property real visibleLeft: Editor.timelineScrollX
    readonly property real visibleRight: visibleLeft + viewportWidth
    readonly property real inView: viewportWidth > 0 ? Math.max(Math.min(anchorX, visibleRight - barWidth - 8), visibleLeft + 8) : anchorX
    readonly property real nearClip: Math.min(Math.max(inView, start - barWidth + 24), end - 24)

    visible: !Editor.gestureActive && Editor.selection !== "" && row >= 0
    x: Math.max(0, Math.min(nearClip, Editor.timelineContentWidth - 24 - barWidth))
    y: row === 0 ? 36 + 50 - 2 : 36 + row * 56 - 30 + 2
    width: barWidth
    height: 30
    radius: 15
    color: Theme.raisedHigh
    border.color: Qt.rgba(1, 1, 1, 0.12)

    // Sombra.
    Rectangle {
        z: -1
        x: 0
        y: 3
        width: parent.width
        height: parent.height
        radius: parent.radius
        color: Qt.rgba(0, 0, 0, 0.45)
    }

    Row {
        x: 4
        height: parent.height
        GlyphButton {
            visible: bar.canSplit
            width: 30
            height: 30
            iconName: "scissors"
            iconSize: 13
            help: "Dividir (Ctrl+B)"
            onClicked: Editor.splitAtPlayhead()
        }
        Rectangle { visible: bar.canSplit; width: 1; height: 16; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(1, 1, 1, 0.1) }
        GlyphButton {
            width: 30
            height: 30
            iconName: "copy-plus"
            iconSize: 13
            help: "Duplicar (Ctrl+D)"
            onClicked: Editor.duplicateSelection()
        }
        Rectangle { width: 1; height: 16; anchors.verticalCenter: parent.verticalCenter; color: Qt.rgba(1, 1, 1, 0.1) }
        GlyphButton {
            width: 30
            height: 30
            iconName: "trash-2"
            iconSize: 13
            help: "Apagar (Delete)"
            onClicked: Editor.deleteSelection()
        }
    }
}
