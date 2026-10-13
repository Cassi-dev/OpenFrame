import QtQuick
import QtQuick.Templates as T

// Grupo de opções em pílula; a escolhida fica elevada. `options` é uma lista de
// { value, title, icon? }. Com `fill`, as opções dividem a largura.
Rectangle {
    id: picker
    property var options: []
    property var value
    property bool fill: true
    signal picked(var value)

    implicitHeight: 28
    implicitWidth: row.implicitWidth + 4
    radius: height / 2
    color: Theme.raised
    border.color: Theme.hairline

    Row {
        id: row
        x: 2
        y: 2
        spacing: 2
        Repeater {
            model: picker.options
            T.AbstractButton {
                id: option
                required property var modelData
                required property int index
                readonly property bool selected: modelData.value === picker.value
                readonly property bool hasIcon: (modelData.icon || "") !== ""
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                height: 24
                implicitWidth: (hasIcon ? 14 : label.implicitWidth) + 14
                width: picker.fill && picker.options.length > 0
                       ? (picker.width - 4 - 2 * (picker.options.length - 1)) / picker.options.length
                       : implicitWidth
                background: Rectangle {
                    radius: height / 2
                    color: option.selected ? Theme.raisedHigh : "transparent"
                }
                contentItem: Item {
                    Icon {
                        visible: option.hasIcon
                        anchors.centerIn: parent
                        name: option.modelData.icon || ""
                        size: 13
                        color: option.selected ? Theme.textPrimary : (option.hovered ? Theme.textPrimary : Theme.textSecondary)
                    }
                    OfText {
                        id: label
                        visible: !option.hasIcon
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width)
                        horizontalAlignment: Text.AlignHCenter
                        text: option.modelData.title
                        size: 11
                        weight: option.selected ? Theme.medium : Theme.regular
                        color: option.selected ? Theme.textPrimary : (option.hovered ? Theme.textPrimary : Theme.textSecondary)
                    }
                }
                onClicked: picker.picked(modelData.value)
                Tip { text: option.hasIcon ? option.modelData.title : "" }
            }
        }
    }
}
