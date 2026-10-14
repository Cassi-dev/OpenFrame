import QtQuick
import QtQuick.Templates as T

T.MenuItem {
    id: item
    property bool destructive: false
    property string shortcutText
    /// Marca de escolha (itens de seleção, como o Picker inline do SwiftUI).
    property bool marked: false

    implicitWidth: 28 + label.implicitWidth + (shortcutText !== "" ? shortcut.implicitWidth + 24 : 0) + 14
    implicitHeight: 26
    hoverEnabled: true
    opacity: enabled ? 1 : 0.35

    contentItem: Item {
        Icon {
            visible: item.marked || item.checked
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            name: "circle-check"
            size: 12
            color: item.highlighted ? Theme.textOnAccent : Theme.accent
        }
        OfText {
            id: label
            x: 28
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - (item.shortcutText !== "" ? shortcut.implicitWidth + 20 : 8)
            text: item.text
            size: 12
            color: item.highlighted ? Theme.textOnAccent : (item.destructive ? Theme.danger : Theme.textPrimary)
        }
        OfText {
            id: shortcut
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: item.shortcutText
            size: 11
            color: item.highlighted ? Theme.alpha(Theme.textOnAccent, 0.7) : Theme.textTertiary
        }
    }
    background: Rectangle {
        radius: 5
        color: item.highlighted ? Theme.accent : "transparent"
    }
}
