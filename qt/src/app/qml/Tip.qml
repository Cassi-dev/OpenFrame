import QtQuick
import QtQuick.Templates as T

// Dica ao parar o mouse sobre um controle (o `.help` do SwiftUI).
T.ToolTip {
    id: tip
    property Item target: parent
    visible: target && target.hovered === true && text !== ""
    delay: 650
    timeout: 8000
    margins: 6
    x: target ? (target.width - implicitWidth) / 2 : 0
    y: target ? target.height + 6 : 0
    padding: 6
    leftPadding: 9
    rightPadding: 9
    implicitWidth: Math.min(contentItem.implicitWidth + leftPadding + rightPadding, 320)
    implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
    closePolicy: T.Popup.CloseOnEscape | T.Popup.CloseOnPressOutsideParent | T.Popup.CloseOnReleaseOutsideParent

    contentItem: OfText {
        text: tip.text
        size: 11
        color: Theme.textPrimary
        wrapMode: Text.Wrap
        elide: Text.ElideNone
    }
    background: Rectangle {
        color: "#1C1C1C"
        radius: 6
        border.color: Qt.rgba(1, 1, 1, 0.12)
    }
}
