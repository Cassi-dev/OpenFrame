import QtQuick
import QtQuick.Templates as T

// Ícone (ou texto) simples, sem fundo, que acende no hover; `active` fica em ciano.
T.AbstractButton {
    id: control
    property string iconName
    property real iconSize: 14
    property bool active: false
    property string help
    property real textSize: 11

    readonly property color tint: active ? Theme.accent : (hovered ? Theme.textPrimary : Theme.textSecondary)

    implicitWidth: Math.max(iconName !== "" ? iconSize : 0, label.visible ? label.implicitWidth : 0) + leftPadding + rightPadding
    implicitHeight: Math.max(iconSize, label.visible ? label.implicitHeight : 0) + topPadding + bottomPadding
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    opacity: enabled ? (pressed ? 0.6 : 1) : 0.3

    contentItem: Item {
        Icon {
            visible: control.iconName !== ""
            anchors.centerIn: parent
            name: control.iconName
            size: control.iconSize
            color: control.tint
        }
        OfText {
            id: label
            visible: control.iconName === "" && control.text !== ""
            anchors.centerIn: parent
            text: control.text
            size: control.textSize
            color: control.tint
        }
    }
    background: Item {}
    Tip { text: control.help }
}
