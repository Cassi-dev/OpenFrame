import QtQuick
import QtQuick.Templates as T

// Pílula com texto: "primary" é o único botão preenchido de ciano.
T.AbstractButton {
    id: control
    property string kind: "secondary"   // primary | secondary | quiet
    property bool compact: false
    property string iconName
    property string help
    /// Ocupa a largura disponível, com o conteúdo centrado.
    property bool fill: false

    implicitHeight: compact ? 24 : 30
    implicitWidth: row.implicitWidth + leftPadding + rightPadding
    leftPadding: compact ? 10 : 14
    rightPadding: leftPadding
    hoverEnabled: true
    focusPolicy: Qt.NoFocus
    opacity: enabled ? (pressed ? 0.75 : 1) : 0.35

    /// Cor do texto e do ícone (padrão pelo tipo).
    property color labelColor: foreground
    readonly property color foreground: kind === "primary" ? Theme.textOnAccent
                                       : kind === "secondary" ? Theme.textPrimary
                                       : (hovered ? Theme.textPrimary : Theme.textSecondary)

    background: Rectangle {
        radius: height / 2
        color: control.kind === "primary" ? (control.hovered ? Theme.alpha(Theme.accent, 0.88) : Theme.accent)
             : control.kind === "secondary" ? (control.hovered ? Theme.raisedHigh : Theme.raised)
             : (control.hovered ? Theme.raised : "transparent")
        border.width: control.kind === "secondary" ? 1 : 0
        border.color: Theme.hairline
    }
    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight
        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            x: control.fill ? (parent.width - width) / 2 : 0
            spacing: 6
            Icon {
                visible: control.iconName !== ""
                anchors.verticalCenter: parent.verticalCenter
                name: control.iconName
                size: control.compact ? 12 : 13
                color: control.labelColor
            }
            OfText {
                anchors.verticalCenter: parent.verticalCenter
                text: control.text
                size: control.compact ? 11 : 12
                weight: Theme.medium
                color: control.labelColor
            }
        }
    }
    Tip { text: control.help }
}
