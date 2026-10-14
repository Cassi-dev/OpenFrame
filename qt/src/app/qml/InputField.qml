import QtQuick
import QtQuick.Templates as T

// Campo de texto de uma linha com a aparência dos campos do tema.
T.TextField {
    id: field
    property real fieldRadius: Theme.fieldRadius
    property bool monoDigits: false

    implicitHeight: 28
    implicitWidth: 160
    leftPadding: 10
    rightPadding: 10
    verticalAlignment: TextInput.AlignVCenter
    color: Theme.textPrimary
    placeholderTextColor: Theme.textTertiary
    selectionColor: Theme.alpha(Theme.accent, 0.45)
    selectedTextColor: Theme.textPrimary
    font.family: Theme.family
    font.pixelSize: 12
    font.features: monoDigits ? ({ "tnum": 1 }) : ({})
    selectByMouse: true

    background: Rectangle {
        radius: field.fieldRadius
        color: Theme.raised
        border.color: field.activeFocus ? Theme.alpha(Theme.accent, 0.6) : Theme.hairline
    }
    OfText {
        visible: field.text === "" && !field.activeFocus
        x: field.leftPadding
        anchors.verticalCenter: parent.verticalCenter
        text: field.placeholderText
        size: 12
        color: field.placeholderTextColor
    }
}
