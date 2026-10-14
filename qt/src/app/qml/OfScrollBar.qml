import QtQuick
import QtQuick.Templates as T

// Barra de rolagem fina, que só aparece durante a rolagem ou com o mouse em cima.
T.ScrollBar {
    id: bar
    implicitWidth: orientation === Qt.Vertical ? 8 : 100
    implicitHeight: orientation === Qt.Horizontal ? 8 : 100
    padding: 1
    minimumSize: 0.05
    visible: policy !== T.ScrollBar.AlwaysOff && size < 1
    hoverEnabled: true
    contentItem: Rectangle {
        implicitWidth: 6
        implicitHeight: 6
        radius: 3
        color: bar.pressed ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(1, 1, 1, 0.28)
        opacity: bar.active || bar.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
}
