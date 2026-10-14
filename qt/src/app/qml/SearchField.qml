import QtQuick

// Busca em pílula, com o botão de limpar.
Rectangle {
    id: root
    property alias text: input.text
    signal textEdited(string text)

    width: 220
    height: 28
    radius: 14
    color: Theme.raised
    border.color: input.activeFocus ? Theme.alpha(Theme.accent, 0.6) : Theme.hairline

    Icon {
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        name: "search"
        size: 13
        color: Theme.textTertiary
    }
    TextInput {
        id: input
        x: 30
        width: parent.width - 30 - (clear.visible ? 26 : 10)
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.textPrimary
        selectionColor: Theme.alpha(Theme.accent, 0.45)
        font.family: Theme.family
        font.pixelSize: 12
        clip: true
        selectByMouse: true
        onTextEdited: root.textEdited(text)
        Keys.onEscapePressed: {
            text = ""
            root.textEdited("")
            focus = false
        }
        OfText {
            visible: input.text === ""
            text: "Buscar"
            size: 12
            color: Theme.textTertiary
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    GlyphButton {
        id: clear
        visible: input.text !== ""
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        iconName: "circle-x"
        iconSize: 13
        onClicked: {
            input.text = ""
            root.textEdited("")
        }
    }
}
