import QtQuick
import QtQuick.Window

// Mídia na biblioteca: miniatura (ou forma de onda), duração, ponto ciano se
// estiver em uso, "+" no hover. Duplo clique adiciona; arrastar leva à timeline.
Item {
    id: tile
    required property string uid
    required property string name
    required property string kind
    required property string durationText
    required property bool used
    required property bool isVisual

    implicitHeight: 70 + 6 + 15
    readonly property bool hovered: hover.hovered

    HoverHandler { id: hover }

    Rectangle {
        id: box
        width: parent.width
        height: 70
        radius: 9
        color: tile.kind === "audio" ? Theme.clipAudio : Theme.raised
        clip: true

        MaterialThumb {
            id: thumb
            anchors.fill: parent
            materialId: tile.uid
        }
        WaveformView {
            visible: tile.kind === "audio"
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 14
            anchors.bottomMargin: 14
            materialId: tile.uid
            from: 0
            to: 1e9
            color: Theme.waveform
        }
        Icon {
            visible: !thumb.available && !(tile.kind === "audio")
            anchors.centerIn: parent
            name: tile.kind === "photo" ? "image" : "film"
            size: 20
            color: Theme.textTertiary
        }
    }
    Rectangle {
        anchors.fill: box
        radius: 9
        color: "transparent"
        border.color: tile.hovered ? Qt.rgba(1, 1, 1, 0.25) : Theme.hairline
    }
    Rectangle {
        visible: tile.kind !== "photo"
        anchors.right: box.right
        anchors.bottom: box.bottom
        anchors.margins: 5
        width: duration.implicitWidth + 10
        height: 16
        radius: 8
        color: Qt.rgba(0, 0, 0, 0.6)
        OfText { id: duration; anchors.centerIn: parent; text: tile.durationText; size: 9.5; mono: true; weight: Theme.medium }
    }
    Rectangle {
        visible: tile.used
        x: 7
        y: 7
        width: 6
        height: 6
        radius: 3
        color: Theme.accent
    }
    CircleButton {
        visible: tile.hovered
        anchors.right: box.right
        anchors.top: box.top
        anchors.margins: 5
        size: 22
        prominent: true
        iconName: "plus"
        help: "Adicionar à timeline"
        onClicked: Editor.addToTimeline(tile.uid)
    }
    OfText {
        y: 76
        x: 2
        width: parent.width - 4
        text: tile.name
        size: 11
        elide: Text.ElideMiddle
        color: tile.hovered ? Theme.textPrimary : Theme.textSecondary
    }

    MouseArea {
        id: area
        anchors.fill: box
        z: -1
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        drag.target: ghost
        drag.threshold: 6
        onPressed: (m) => {
            const p = mapToItem(ghost.parent, m.x, m.y)
            ghost.x = p.x - ghost.width / 2
            ghost.y = p.y - ghost.height / 2
        }
        onDoubleClicked: Editor.addToTimeline(tile.uid)
        onClicked: (m) => { if (m.button === Qt.RightButton) menu.popup() }
        drag.onActiveChanged: {
            if (drag.active) {
                Editor.draggingMaterial = tile.uid
            } else {
                ghost.Drag.drop()
                Editor.draggingMaterial = ""
            }
        }
    }

    // Fantasma que acompanha o cursor no arraste para a timeline.
    Rectangle {
        id: ghost
        parent: tile.Window.contentItem
        visible: area.drag.active
        width: 72
        height: 44
        radius: 8
        color: Theme.raisedHigh
        border.color: Theme.accent
        opacity: 0.9
        z: 1000
        property string materialId: tile.uid
        Drag.active: area.drag.active
        Drag.keys: ["openframe/material"]
        Drag.hotSpot.x: width / 2
        Drag.hotSpot.y: height / 2
        MaterialThumb { anchors.fill: parent; anchors.margins: 2; materialId: tile.uid }
        Icon {
            visible: tile.kind === "audio"
            anchors.centerIn: parent
            name: "music"
            size: 16
            color: Theme.textSecondary
        }
    }

    OfMenu {
        id: menu
        onOpened: Editor.modalCount += 1
        onClosed: Editor.modalCount -= 1
        OfMenuItem {
            text: tile.kind === "audio" ? "Adicionar à faixa de áudio" : "Adicionar à faixa principal"
            onTriggered: Editor.addToTimeline(tile.uid)
        }
        OfMenuItem {
            visible: tile.isVisual
            height: visible ? implicitHeight : 0
            text: "Adicionar como sobreposição"
            onTriggered: Editor.addAsOverlay(tile.uid)
        }
        OfMenuSeparator {}
        OfMenuItem { text: "Remover do projeto"; destructive: true; onTriggered: Editor.removeMaterial(tile.uid) }
    }
}
