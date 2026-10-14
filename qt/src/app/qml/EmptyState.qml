import QtQuick

// Estado vazio: ícone fino, título e detalhe opcional.
Column {
    id: root
    property string title
    property string detail
    property string iconName: "clapperboard"

    spacing: 8
    topPadding: 56
    bottomPadding: 56

    Icon {
        anchors.horizontalCenter: parent.horizontalCenter
        name: root.iconName
        size: 28
        color: Theme.textTertiary
    }
    OfText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.title
        size: 14
        color: Theme.textSecondary
    }
    OfText {
        visible: root.detail !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.detail
        size: 12
        color: Theme.textTertiary
    }
}
