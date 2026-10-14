import QtQuick

// Cartão de projeto: miniatura 16:9 com o canvas encaixado, duração, menu "…"
// no hover, nome e "Editado há … · formato". Clique abre; botão direito, o menu.
Item {
    id: card
    property string entryId
    property string entryName
    property string entrySubtitle
    property string entryDuration
    property real entryAspect: 16 / 9
    property string entryThumbnail
    signal rename()
    signal remove()

    readonly property bool hovered: hover.hovered || menu.visible
    implicitHeight: thumb.height + 8 + info.height

    HoverHandler { id: hover }

    Rectangle {
        id: thumb
        width: parent.width
        height: width * 9 / 16
        radius: Theme.cardRadius
        color: "black"
        clip: true

        Image {
            id: image
            anchors.fill: parent
            anchors.margins: 1
            visible: status === Image.Ready
            source: card.entryThumbnail
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            smooth: true
        }
        AspectGlyph {
            visible: !image.visible
            anchors.centerIn: parent
            width: 44
            height: 44
            opacity: 0.6
            aspect: card.entryAspect
        }
        Rectangle {
            visible: card.entryDuration !== ""
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 8
            width: durationLabel.implicitWidth + 12
            height: 18
            radius: 9
            color: Qt.rgba(0, 0, 0, 0.6)
            OfText { id: durationLabel; anchors.centerIn: parent; text: card.entryDuration; size: 10; mono: true }
        }
        Rectangle {
            visible: card.hovered
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            width: 26
            height: 26
            radius: 13
            color: Qt.rgba(0, 0, 0, 0.6)
            Icon { anchors.centerIn: parent; name: "ellipsis"; size: 14; color: Theme.textPrimary }
            MouseArea {
                anchors.fill: parent
                onClicked: menu.popup(parent, 0, parent.height + 4)
            }
        }
    }
    Rectangle {
        anchors.fill: thumb
        radius: Theme.cardRadius
        color: "transparent"
        border.width: card.hovered ? 1.5 : 1
        border.color: card.hovered ? Theme.alpha(Theme.accent, 0.7) : Theme.hairline
    }
    Column {
        id: info
        y: thumb.height + 8
        x: 2
        width: parent.width - 4
        spacing: 3
        OfText { width: parent.width; text: card.entryName; size: 13 }
        OfText { width: parent.width; text: card.entrySubtitle; size: 11; color: Theme.textTertiary }
    }
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton)
                menu.popup()
            else
                Editor.openLibraryProject(card.entryId)
        }
    }
    Tip { target: card; text: "Abrir “" + card.entryName + "”" }

    OfMenu {
        id: menu
        onOpened: Editor.modalCount += 1
        onClosed: Editor.modalCount -= 1
        OfMenuItem { text: "Abrir"; onTriggered: Editor.openLibraryProject(card.entryId) }
        OfMenuItem { text: "Renomear…"; onTriggered: card.rename() }
        OfMenuItem { text: "Duplicar"; onTriggered: Editor.duplicateProject(card.entryId) }
        OfMenuItem { text: Qt.platform.os === "windows" ? "Mostrar no Explorador" : "Abrir a pasta"; onTriggered: Editor.revealProject(card.entryId) }
        OfMenuSeparator {}
        OfMenuItem { text: "Apagar…"; destructive: true; onTriggered: card.remove() }
    }
}
