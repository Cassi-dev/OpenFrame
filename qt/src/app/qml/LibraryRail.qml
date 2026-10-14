import QtQuick
import QtQuick.Templates as T

// Barra de ferramentas flutuante da esquerda. Clicar no painel aberto o recolhe.
Panel {
    id: rail
    panelRadius: 18
    width: 50
    height: column.implicitHeight + 12

    readonly property var items: [
        { panel: "media", title: "Mídia", icon: "images" },
        { panel: "text", title: "Texto", icon: "type" },
        { panel: "captions", title: "Legendas", icon: "captions" }
    ]

    component RailButton: T.AbstractButton {
        id: button
        property string panel
        property string iconName
        property string help
        readonly property bool active: Editor.libraryVisible && Editor.libraryPanel === panel
        width: 38
        height: 38
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        background: Rectangle {
            radius: 11
            color: button.active ? Theme.raisedHigh : "transparent"
        }
        contentItem: Item {
            Icon {
                anchors.centerIn: parent
                name: button.iconName
                size: 17
                color: button.active ? Theme.accent : (button.hovered ? Theme.textPrimary : Theme.textSecondary)
            }
        }
        onClicked: {
            if (active) {
                Editor.libraryVisible = false
            } else {
                Editor.libraryPanel = panel
                Editor.libraryVisible = true
            }
        }
        Tip { text: button.help }
    }

    Column {
        id: column
        x: 6
        y: 6
        spacing: 4
        Repeater {
            model: rail.items
            RailButton {
                required property var modelData
                panel: modelData.panel
                iconName: modelData.icon
                help: modelData.title
            }
        }
        Item {
            width: 38
            height: 9
            Rectangle { anchors.centerIn: parent; width: 20; height: 1; color: Theme.hairline }
        }
        RailButton { panel: "shortcuts"; iconName: "keyboard"; help: "Atalhos" }
    }
}
