import QtQuick

// Nome do projeto na barra superior: clique para renomear (Enter confirma, Esc desiste).
Item {
    id: root
    property bool editing: false
    implicitWidth: editing ? 220 : label.implicitWidth
    implicitHeight: 26
    width: implicitWidth
    height: implicitHeight

    OfText {
        id: label
        visible: !root.editing
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, 320)
        text: Editor.projectName
        size: 13
        MouseArea {
            id: labelArea
            anchors.fill: parent
            hoverEnabled: true
            readonly property bool hovered: containsMouse && Editor.libraryProject
            cursorShape: Editor.libraryProject ? Qt.IBeamCursor : Qt.ArrowCursor
            onClicked: {
                if (!Editor.libraryProject) return
                field.text = Editor.projectName
                root.editing = true
                field.forceActiveFocus()
                field.selectAll()
            }
            Tip { target: labelArea; text: "Clique para renomear" }
        }
    }
    InputField {
        id: field
        visible: root.editing
        anchors.fill: parent
        fieldRadius: 7
        font.pixelSize: 13
        leftPadding: 8
        function commit() {
            if (!root.editing) return
            Editor.renameCurrentProject(text)
            root.editing = false
        }
        onAccepted: commit()
        onActiveFocusChanged: if (!activeFocus) commit()
        Keys.onEscapePressed: {
            root.editing = false
            focus = false
        }
    }
}
