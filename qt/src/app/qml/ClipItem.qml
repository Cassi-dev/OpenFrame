import QtQuick

// Clipe na timeline: fundo cinza pelo tipo, miniaturas ou forma de onda,
// nome e indicadores dentro do clipe; selecionado ganha borda, brilho e alças
// ciano. Arrastar move (também para outra faixa); as alças aparam.
Item {
    id: root
    required property string uid
    required property int row
    required property real start
    required property real duration
    required property string kind
    required property string icon
    required property string title
    required property string badges
    required property string materialId
    required property real sourceStart
    required property real sourceDuration
    required property real materialDuration
    required property real aspect
    required property real volume
    required property bool isMain
    required property bool dragged
    required property int rowShift
    required property bool hidden

    /// Janela visível da timeline, em coordenadas do conteúdo.
    property real visibleLeft: 0
    property real visibleRight: 0

    readonly property bool selected: Editor.selection === uid
    readonly property real radius: 9
    readonly property real stride: 56

    x: start * Editor.zoom
    y: 36 + (row + rowShift) * stride + 4
    width: Math.max(4, duration * Editor.zoom)
    height: 42
    z: dragged ? 3 : selected ? 2 : 1
    opacity: hidden ? 0.4 : 1

    Behavior on x {
        enabled: Editor.slideAnimation && !root.dragged
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
    }
    Behavior on y {
        enabled: Editor.slideAnimation && !root.dragged
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
    }

    // Parte visível do clipe (os itens desenhados só pintam essa janela).
    readonly property real visL: Math.max(0, visibleLeft - x)
    readonly property real visR: Math.min(width, visibleRight - x)

    // Brilho da seleção.
    Rectangle {
        visible: root.selected
        anchors.fill: parent
        anchors.margins: -4
        radius: root.radius + 4
        color: "transparent"
        border.width: 4
        border.color: Theme.alpha(Theme.accent, 0.14)
    }
    Rectangle {
        id: body
        anchors.fill: parent
        radius: root.radius
        clip: true
        color: root.kind === "text" ? Theme.clipText
             : root.kind === "audio" ? Theme.clipAudio
             : root.kind === "missing" ? Theme.raised : Theme.clipVideo

        ThumbnailStrip {
            visible: root.kind === "video" || root.kind === "photo"
            x: Math.max(2, root.visL)
            y: 2
            width: Math.max(0, Math.min(root.width - 2, root.visR) - x)
            height: root.height - 4
            offset: x - 2
            fullWidth: root.width - 4
            radius: root.radius - 2
            materialId: root.materialId
            video: root.kind === "video"
            aspect: root.aspect
            sourceStart: root.sourceStart
            sourceDuration: root.sourceDuration
            materialDuration: root.materialDuration
        }
        WaveformView {
            visible: root.kind === "audio"
            x: Math.max(6, root.visL)
            width: Math.max(0, Math.min(root.width - 6, root.visR) - x)
            height: root.height * 0.5
            y: root.height - height - 5
            offset: x - 6
            fullWidth: root.width - 12
            materialId: root.materialId
            from: root.sourceStart
            to: root.sourceStart + root.sourceDuration
            color: root.selected ? Theme.alpha(Theme.accent, 0.7) : Theme.waveform
            opacity: 0.4 + 0.6 * Math.min(root.volume, 1)
        }

        // Ícone e nome dentro do clipe, mais os indicadores de ajustes.
        Rectangle {
            visible: root.width > 46
            x: Math.max(6, Math.min(root.visL + 6, root.width - width - 6))
            y: 6
            height: 18
            radius: 9
            width: Math.min(chip.implicitWidth + 14, root.width - 12)
            color: root.kind === "text" ? "transparent" : Qt.rgba(0, 0, 0, 0.55)
            clip: true
            Row {
                id: chip
                x: 7
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                Icon { anchors.verticalCenter: parent.verticalCenter; name: root.icon; size: 10; color: Theme.textPrimary }
                OfText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.title
                    size: 10
                    weight: Theme.medium
                    width: Math.min(implicitWidth, Math.max(0, root.width - 12 - 14 - 15 - (badge.visible ? badge.implicitWidth + 5 : 0)))
                }
                OfText {
                    id: badge
                    visible: root.badges !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.badges
                    size: 9
                    weight: Theme.medium
                    color: Theme.textSecondary
                }
            }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: root.selected ? 2 : 1
        border.color: root.selected ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)
    }

    MouseArea {
        id: area
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        property point pressPoint
        property bool moving: false
        onPressed: (m) => {
            pressPoint = mapToItem(null, m.x, m.y)
            moving = false
        }
        onPositionChanged: (m) => {
            if (!(m.buttons & Qt.LeftButton)) return
            const p = mapToItem(null, m.x, m.y)
            const dx = p.x - pressPoint.x, dy = p.y - pressPoint.y
            if (!moving && Math.hypot(dx, dy) < 4) return
            moving = true
            Editor.dragMove(root.uid, dx, Math.round(dy / root.stride))
        }
        onReleased: (m) => {
            if (moving) {
                moving = false
                Editor.endDragMove(root.uid)
            } else if (m.button === Qt.RightButton) {
                Editor.selection = root.uid
                menu.popup()
            } else {
                Editor.selection = root.uid
            }
        }
        onCanceled: {
            if (moving) Editor.endDragMove(root.uid)
            moving = false
        }
    }

    component Handle: Item {
        id: handle
        property bool leading
        width: 9
        height: root.height
        clip: true
        Rectangle {
            x: handle.leading ? 0 : -root.radius
            width: handle.width + root.radius
            height: parent.height
            radius: root.radius
            color: Theme.accent
        }
        Rectangle {
            anchors.centerIn: parent
            width: 2
            height: 14
            radius: 1
            color: Theme.alpha(Theme.textOnAccent, 0.75)
        }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -3
            cursorShape: Qt.SizeHorCursor
            preventStealing: true
            property real pressX
            onPressed: (m) => pressX = mapToItem(null, m.x, m.y).x
            onPositionChanged: (m) => {
                const dx = mapToItem(null, m.x, m.y).x - pressX
                if (Math.abs(dx) >= 1) Editor.dragTrim(root.uid, handle.leading, dx)
            }
            onReleased: Editor.endDragTrim()
            onCanceled: Editor.endDragTrim()
        }
    }
    Handle { visible: root.selected; leading: true }
    Handle { visible: root.selected; leading: false; x: root.width - width }

    OfMenu {
        id: menu
        onOpened: Editor.modalCount += 1
        onClosed: Editor.modalCount -= 1
        OfMenuItem { text: "Dividir no cursor"; onTriggered: { Editor.selection = root.uid; Editor.splitAtPlayhead() } }
        OfMenuItem { text: "Duplicar"; onTriggered: { Editor.selection = root.uid; Editor.duplicateSelection() } }
        OfMenuSeparator {}
        OfMenuItem { text: "Apagar"; destructive: true; onTriggered: { Editor.selection = root.uid; Editor.deleteSelection() } }
    }
}
