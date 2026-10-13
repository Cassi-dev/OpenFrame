import QtQuick
import QtQuick.Templates as T

// Diálogo modal do tema (alertas e confirmações do app Swift): título,
// mensagem, campo de texto opcional e botões à direita.
T.Popup {
    id: dialog
    property string title
    property string message
    property bool hasField: false
    property alias fieldText: field.text
    property string acceptTitle: "OK"
    property string cancelTitle: "Cancelar"
    property bool destructive: false
    property bool showCancel: true
    signal accepted()

    parent: T.Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    width: 400
    padding: 20
    closePolicy: T.Popup.CloseOnEscape
    implicitHeight: content.implicitHeight + topPadding + bottomPadding

    onOpened: {
        Editor.modalCount += 1
        if (hasField) {
            field.forceActiveFocus()
            field.selectAll()
        }
    }
    onClosed: Editor.modalCount -= 1

    function accept() {
        accepted()
        close()
    }

    T.Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }
    background: Rectangle {
        color: "#121212"
        radius: Theme.panelRadius
        border.color: Qt.rgba(1, 1, 1, 0.12)
    }
    contentItem: Column {
        id: content
        spacing: 12
        OfText {
            width: parent.width
            text: dialog.title
            size: 15
            weight: Theme.medium
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        OfText {
            visible: dialog.message !== ""
            width: parent.width
            text: dialog.message
            size: 12
            color: Theme.textSecondary
            wrapMode: Text.Wrap
            elide: Text.ElideNone
        }
        InputField {
            id: field
            visible: dialog.hasField
            width: parent.width
            onAccepted: dialog.accept()
        }
        Row {
            anchors.right: parent.right
            spacing: 8
            topPadding: 6
            PillButton {
                visible: dialog.showCancel
                text: dialog.cancelTitle
                kind: "quiet"
                onClicked: dialog.close()
            }
            PillButton {
                text: dialog.acceptTitle
                kind: dialog.destructive ? "secondary" : "primary"
                labelColor: dialog.destructive ? Theme.danger : foreground
                onClicked: dialog.accept()
            }
        }
    }
}
