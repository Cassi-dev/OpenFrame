import QtQuick
import QtQuick.Templates as T

// Mídia do projeto: grade de miniaturas; arraste arquivos do sistema para cá
// ou arraste uma mídia para a timeline.
Item {
    id: panel

    PanelHeader {
        id: header
        x: 14
        y: 14
        width: parent.width - 28
        title: "Mídia"
        detail: Editor.materials.count > 0 ? Editor.materials.count : ""
        CircleButton {
            size: 28
            iconName: "plus"
            help: "Importar mídia (Ctrl+I)"
            onClicked: Editor.requestDialog("importMedia")
        }
    }

    // Vazio: área tracejada com o convite para importar.
    Item {
        visible: Editor.materials.count === 0
        x: 14
        y: header.y + header.height + 12
        width: parent.width - 28
        height: parent.height - y - 14
        DashedRect {
            anchors.fill: parent
            radius: Theme.cardRadius
            color: Qt.rgba(1, 1, 1, 0.14)
        }
        Column {
            anchors.centerIn: parent
            spacing: 12
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "download"
                size: 26
                color: Theme.textTertiary
            }
            OfText {
                anchors.horizontalCenter: parent.horizontalCenter
                horizontalAlignment: Text.AlignHCenter
                text: "Arraste vídeos, fotos\nou músicas para cá"
                wrapMode: Text.Wrap
                color: Theme.textSecondary
            }
            PillButton {
                anchors.horizontalCenter: parent.horizontalCenter
                compact: true
                text: "Importar mídia"
                onClicked: Editor.requestDialog("importMedia")
            }
        }
    }

    Flickable {
        id: scroll
        visible: Editor.materials.count > 0
        x: 14
        y: header.y + header.height + 12 - Theme.scrollFade / 2
        width: parent.width - 28
        height: parent.height - y
        contentHeight: grid.height + Theme.scrollFade + 8
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        T.ScrollBar.vertical: OfScrollBar {}

        // Grade adaptável: colunas de pelo menos 112.
        Flow {
            id: grid
            y: Theme.scrollFade
            width: parent.width
            spacing: 10
            readonly property int columns: Math.max(1, Math.floor((width + spacing) / (112 + spacing)))
            readonly property real tileWidth: (width - spacing * (columns - 1)) / columns
            Repeater {
                model: Editor.materials
                MaterialTile { width: grid.tileWidth }
            }
        }
    }
    ScrollFade {
        visible: scroll.visible
        x: scroll.x
        y: scroll.y
        width: scroll.width
    }

    // Arquivos soltos do sistema.
    DropArea {
        id: drop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: (d) => {
            if (d.hasUrls) Editor.importMedia(d.urls)
        }
    }
    Rectangle {
        visible: drop.containsDrag
        anchors.fill: parent
        anchors.margins: 4
        radius: Theme.panelRadius - 4
        color: Theme.accentSoft
        border.color: Theme.accent
        border.width: 1.5
    }
}
