import QtQuick
import QtQuick.Templates as T

// Botão redondo só com ícone; `prominent` preenche de ciano.
T.AbstractButton {
    id: control
    property real size: 30
    property bool prominent: false
    property string iconName
    property real iconSize: Math.round(size * 0.5)
    property string help
    /// Ligado (alternância): fica em ciano, como o IconToggleStyle.
    property bool on: false

    readonly property bool filled: prominent || on

    implicitWidth: size
    implicitHeight: size
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    opacity: enabled ? (pressed ? 0.7 : 1) : 0.35

    background: Rectangle {
        radius: width / 2
        color: control.filled ? (control.hovered ? Theme.alpha(Theme.accent, 0.88) : Theme.accent)
                              : (control.hovered ? Theme.raisedHigh : Theme.raised)
        border.width: control.filled ? 0 : 1
        border.color: Theme.hairline
    }
    contentItem: Item {
        Icon {
            anchors.centerIn: parent
            name: control.iconName
            size: control.iconSize
            color: control.filled ? Theme.textOnAccent : (control.hovered ? Theme.textPrimary : Theme.textSecondary)
        }
    }
    Tip { text: control.help }
}
