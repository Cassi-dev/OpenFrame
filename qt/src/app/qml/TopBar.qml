import QtQuick

// Barra superior do editor: voltar aos projetos, nome, proporção e tamanho de
// saída no centro, menu, desfazer/refazer e Exportar (o único botão ciano).
Item {
    id: bar

    Row {
        id: leading
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        GlyphButton {
            id: back
            anchors.verticalCenter: parent.verticalCenter
            help: "Voltar aos projetos (Ctrl+Shift+P)"
            implicitWidth: 44
            implicitHeight: 26
            contentItem: Row {
                spacing: 8
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-left"
                    size: 13
                    color: back.hovered ? Theme.textPrimary : Theme.textSecondary
                }
                LogoMark {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    frameColor: Theme.textPrimary
                }
            }
            onClicked: Editor.showHome()
        }
        ProjectNameField {
            anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
            visible: Editor.isDirty && !Editor.libraryProject
            anchors.verticalCenter: parent.verticalCenter
            width: 5
            height: 5
            radius: 2.5
            color: Theme.textTertiary
        }
    }

    // Centro: proporção do canvas e tamanho de saída.
    Row {
        anchors.centerIn: parent
        spacing: 8
        PillPicker {
            fill: false
            options: Editor.aspectOptions
            value: Editor.aspect
            onPicked: (v) => Editor.setAspect(v)
        }
        Rectangle {
            id: sizeChip
            anchors.verticalCenter: parent.verticalCenter
            width: sizeRow.implicitWidth + 20
            height: 28
            radius: 14
            color: Theme.raised
            border.color: Theme.hairline
            Row {
                id: sizeRow
                anchors.centerIn: parent
                spacing: 4
                OfText { text: "L"; size: 11; mono: true; color: Theme.textTertiary }
                OfText { text: Editor.outputSize.width; size: 11; mono: true }
                OfText { text: "A"; size: 11; mono: true; color: Theme.textTertiary; leftPadding: 4 }
                OfText { text: Editor.outputSize.height; size: 11; mono: true }
            }
            HoverHandler { id: sizeHover }
            readonly property bool hovered: sizeHover.hovered
            Tip { target: sizeChip; text: "Tamanho de saída (largura × altura)" }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
        CircleButton {
            id: menuButton
            iconName: "menu"
            help: "Menu"
            onClicked: appMenu.popup(menuButton, menuButton.width - appMenu.width, menuButton.height + 6)
        }
        CircleButton {
            iconName: "undo-2"
            enabled: Editor.canUndo
            help: "Desfazer (Ctrl+Z)"
            onClicked: Editor.undo()
        }
        CircleButton {
            iconName: "redo-2"
            enabled: Editor.canRedo
            help: "Refazer (Ctrl+Shift+Z)"
            onClicked: Editor.redo()
        }
        Item { width: 4; height: 1 }
        PillButton {
            kind: "primary"
            text: "Exportar"
            iconName: "arrow-up-right"
            enabled: Editor.duration > 0
            help: "Exportar vídeo (Ctrl+E)"
            onClicked: Editor.showExport = true
        }
    }

    AppMenu { id: appMenu }
}
