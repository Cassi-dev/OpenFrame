import QtQuick

// Painel da biblioteca, escolhido na barra de ferramentas da esquerda.
Item {
    Loader {
        anchors.fill: parent
        sourceComponent: {
            switch (Editor.libraryPanel) {
            case "text": return textPanel
            case "captions": return captionsPanel
            case "shortcuts": return shortcutsPanel
            default: return mediaPanel
            }
        }
    }
    Component { id: mediaPanel; MediaPanel {} }
    Component { id: textPanel; TextPanel {} }
    Component { id: captionsPanel; CaptionsPanel {} }
    Component { id: shortcutsPanel; ShortcutsPanel {} }
}
