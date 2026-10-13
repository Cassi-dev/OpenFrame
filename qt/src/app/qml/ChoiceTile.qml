import QtQuick
import QtQuick.Templates as T

// Cartão selecionável usado nas grades de filtros, efeitos e transições.
T.AbstractButton {
    id: tile
    property bool selected: false
    property string iconName
    /// Imagem de prévia (ex.: o filtro aplicado à miniatura); sem ela, o ícone.
    property url preview: ""

    implicitWidth: 80
    implicitHeight: 50 + 6 + 15
    hoverEnabled: true
    focusPolicy: Qt.NoFocus

    contentItem: Item {
        Rectangle {
            id: box
            width: parent.width
            height: 50
            radius: 8
            color: Theme.raised
            clip: true
            Image {
                anchors.fill: parent
                anchors.margins: 1
                id: previewImage
                visible: status === Image.Ready
                cache: false
                source: tile.preview
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
            }
            Icon {
                visible: !previewImage.visible
                anchors.centerIn: parent
                name: tile.iconName
                size: 18
                color: tile.selected ? Theme.accent : Theme.textSecondary
            }
        }
        Rectangle {
            anchors.fill: box
            radius: 8
            color: "transparent"
            border.width: tile.selected ? 1.5 : 1
            border.color: tile.selected ? Theme.accent : (tile.hovered ? Qt.rgba(1, 1, 1, 0.22) : Theme.hairline)
        }
        OfText {
            y: 56
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: tile.text
            size: 11
            weight: tile.selected ? Theme.medium : Theme.regular
            color: tile.selected ? Theme.accent : (tile.hovered ? Theme.textPrimary : Theme.textSecondary)
        }
    }
}
