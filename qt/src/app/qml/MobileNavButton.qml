import QtQuick
import QtQuick.Templates as T

// Botão de navegação do rodapé mobile, otimizado para toque com o polegar (48px+ de área)
T.AbstractButton {
    id: control
    property string iconName
    property string label
    property bool active: false

    readonly property color tint: active ? Theme.accent : (hovered ? Theme.textPrimary : Theme.textSecondary)

    implicitWidth: 64
    implicitHeight: 56
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    opacity: enabled ? (pressed ? 0.6 : 1.0) : 0.35

    contentItem: Column {
        anchors.centerIn: parent
        spacing: 4

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: control.iconName
            size: 20
            color: control.tint
        }

        OfText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: control.label
            size: 11
            color: control.tint
            font.weight: control.active ? Font.DemiBold : Font.Normal
        }
    }

    background: Rectangle {
        color: control.pressed ? Theme.alpha(Theme.raised, 0.5) : "transparent"
        radius: 8
    }
}
