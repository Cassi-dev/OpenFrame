import QtQuick
import QtQuick.Templates as T

// Menu com a aparência de um campo: valor atual e uma seta. `options` é uma
// lista de { value, title }; ao escolher, emite `picked(value)`.
T.AbstractButton {
    id: field
    property var options: []
    property var value
    property string help
    signal picked(var value)

    readonly property string currentTitle: {
        for (let i = 0; i < options.length; ++i)
            if (options[i].value === value) return options[i].title
        return ""
    }

    implicitHeight: 28
    implicitWidth: 120
    width: parent ? parent.width : implicitWidth
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    opacity: enabled ? 1 : 0.35

    background: Rectangle {
        radius: Theme.fieldRadius
        color: field.hovered || menu.visible ? Theme.raisedHigh : Theme.raised
        border.color: Theme.hairline
    }
    contentItem: Item {
        OfText {
            x: 10
            width: parent.width - 34
            anchors.verticalCenter: parent.verticalCenter
            text: field.currentTitle
            size: 12
        }
        Icon {
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron-down"
            size: 11
            color: Theme.textTertiary
        }
    }
    onClicked: menu.visible ? menu.close() : menu.popup(field, 0, field.height + 4)

    OfMenu {
        id: menu
        width: Math.max(field.width, implicitWidth)
        Repeater {
            model: field.options
            OfMenuItem {
                required property var modelData
                text: modelData.title
                marked: modelData.value === field.value
                onTriggered: field.picked(modelData.value)
            }
        }
    }
    Tip { text: field.help }
}
