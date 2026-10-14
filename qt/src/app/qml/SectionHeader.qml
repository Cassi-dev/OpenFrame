import QtQuick

// Título de seção do formulário, com uma ação opcional ("Redefinir") à direita.
Item {
    id: root
    property string title
    property string actionTitle: "Redefinir"
    property bool hasAction: false
    signal action()

    implicitHeight: 10 + Math.max(titleText.implicitHeight, 16)
    width: parent ? parent.width : implicitWidth

    OfText {
        id: titleText
        y: 10
        text: root.title
        size: 12
        weight: Theme.medium
    }
    GlyphButton {
        visible: root.hasAction
        anchors.right: parent.right
        anchors.verticalCenter: titleText.verticalCenter
        text: root.actionTitle
        onClicked: root.action()
    }
}
