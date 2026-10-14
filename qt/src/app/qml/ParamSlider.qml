import QtQuick

// Slider com rótulo e valor; duplo clique no rótulo redefine.
Column {
    id: root
    property string title
    property real value: 0
    property real from: -1
    property real to: 1
    property real defaultValue: 0
    /// Formata o valor mostrado (padrão: × 100, sem casas).
    property var format: function (v) { return Math.round(v * 100).toString() }
    signal moved(real value)

    width: parent ? parent.width : implicitWidth
    spacing: 5

    Item {
        width: parent.width
        height: 16
        OfText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            size: 12
            color: Theme.textSecondary
        }
        OfText {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.format(root.value)
            size: 12
            mono: true
            color: Math.abs(root.value - root.defaultValue) < 1e-9 ? Theme.textTertiary : Theme.textPrimary
        }
        MouseArea {
            id: labelArea
            anchors.fill: parent
            hoverEnabled: true
            onDoubleClicked: root.moved(root.defaultValue)
            readonly property bool hovered: containsMouse
            Tip { target: labelArea; text: "Clique duas vezes para redefinir" }
        }
    }
    ThinSlider {
        width: parent.width
        value: root.value
        from: root.from
        to: root.to
        onMoved: (v) => root.moved(v)
    }
}
