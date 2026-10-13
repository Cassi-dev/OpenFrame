import QtQuick
import QtQuick.Templates as T

// Menu escuro do tema (os menus do sistema no app Swift).
T.Menu {
    id: menu
    implicitWidth: Math.max(180, contentItem.implicitWidth + leftPadding + rightPadding)
    implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
    padding: 5
    margins: 6
    overlap: 0
    delegate: OfMenuItem {}

    contentItem: ListView {
        implicitHeight: contentHeight
        implicitWidth: {
            let w = 0
            for (let i = 0; i < count; ++i) {
                const item = itemAtIndex(i)
                if (item) w = Math.max(w, item.implicitWidth)
            }
            return w
        }
        model: menu.contentModel
        interactive: Window.window ? contentHeight + menu.topPadding + menu.bottomPadding > menu.height : false
        clip: true
        currentIndex: menu.currentIndex
    }
    background: Rectangle {
        implicitWidth: 180
        color: "#191919"
        radius: 9
        border.color: Qt.rgba(1, 1, 1, 0.12)
    }
    T.Overlay.modal: Rectangle { color: "transparent" }
}
