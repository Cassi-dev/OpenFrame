import QtQuick
import QtQuick.Templates as T

// Legendas: importar/exportar SRT e a lista dos textos da timeline.
Item {
    id: panel

    Column {
        id: top
        x: 14
        y: 14
        width: parent.width - 28
        spacing: 12
        PanelHeader {
            title: "Legendas"
            detail: Editor.cues.count > 0 ? Editor.cues.count : ""
        }
        Row {
            width: parent.width
            spacing: 8
            PillButton {
                width: (parent.width - 8) / 2
                fill: true
                compact: true
                text: "Importar SRT"
                iconName: "download"
                onClicked: Editor.requestDialog("importSrt")
            }
            PillButton {
                width: (parent.width - 8) / 2
                fill: true
                compact: true
                text: "Exportar SRT"
                iconName: "upload"
                enabled: Editor.cues.count > 0
                onClicked: Editor.requestDialog("exportSrt")
            }
        }
        OfText {
            visible: Editor.cues.count === 0
            width: parent.width
            topPadding: 4
            text: "Nenhum texto na timeline. Importe um arquivo SRT ou adicione textos pelo painel Texto."
            size: 11
            color: Theme.textTertiary
            wrapMode: Text.Wrap
        }
    }

    ListView {
        id: list
        visible: Editor.cues.count > 0
        x: 14
        y: top.y + top.height + 12 - Theme.scrollFade / 2
        width: parent.width - 28
        height: parent.height - y
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        header: Item { height: Theme.scrollFade }
        model: Editor.cues
        T.ScrollBar.vertical: OfScrollBar {}
        delegate: T.AbstractButton {
            id: row
            required property string uid
            required property real start
            required property string startText
            required property string caption
            readonly property bool selected: Editor.selection === uid
            width: ListView.view.width
            implicitHeight: Math.max(textLabel.implicitHeight, 14) + 16
            hoverEnabled: true
            focusPolicy: Qt.NoFocus
            background: Rectangle {
                radius: 8
                color: row.selected || row.hovered ? Theme.raised : "transparent"
            }
            contentItem: Item {
                OfText {
                    id: timeLabel
                    x: 10
                    y: 8
                    text: row.startText
                    size: 10
                    mono: true
                    color: row.selected ? Theme.accent : Theme.textTertiary
                    height: 15
                }
                OfText {
                    id: textLabel
                    x: timeLabel.x + timeLabel.implicitWidth + 10
                    y: 8
                    width: parent.width - x - 10
                    text: row.caption
                    size: 12
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    verticalAlignment: Text.AlignTop
                    color: row.selected ? Theme.textPrimary : Theme.textSecondary
                }
            }
            onClicked: {
                Editor.selection = uid
                Editor.inspectorTab = "text"
                Editor.seek(start)
            }
        }
    }
    ScrollFade {
        visible: list.visible
        x: list.x
        y: list.y
        width: list.width
    }
}
