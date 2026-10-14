import QtQuick

// Trilho fino com preenchimento ciano a partir do zero (ou do mínimo).
// Controlado: mostra `value` e emite `moved(v)` ao arrastar.
Item {
    id: slider
    property real value: 0
    property real from: 0
    property real to: 1
    signal moved(real value)
    signal released()

    readonly property bool dragging: mouse.pressed
    readonly property real origin: from < 0 && to > 0 ? 0 : from
    function fraction(v) {
        const span = to - from
        return span <= 0 ? 0 : (Math.min(Math.max(v, from), to) - from) / span
    }

    implicitHeight: 16
    implicitWidth: 120

    readonly property real knob: dragging ? 13 : 11
    readonly property real xValue: fraction(value) * width
    readonly property real xOrigin: fraction(origin) * width

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 3
        radius: 1.5
        color: Qt.rgba(1, 1, 1, 0.10)
    }
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: Math.min(slider.xValue, slider.xOrigin)
        width: Math.abs(slider.xValue - slider.xOrigin)
        height: 3
        radius: 1.5
        color: Theme.accent
    }
    Rectangle {
        // Sombra discreta sob o botão.
        x: knobRect.x
        y: knobRect.y + 1
        width: knobRect.width
        height: knobRect.height
        radius: width / 2
        scale: knobRect.scale
        color: Qt.rgba(0, 0, 0, 0.45)
    }
    Rectangle {
        id: knobRect
        width: slider.knob
        height: slider.knob
        radius: width / 2
        color: "white"
        anchors.verticalCenter: parent.verticalCenter
        x: Math.min(Math.max(slider.xValue - width / 2, 0), slider.width - width)
        scale: mouse.containsMouse || slider.dragging ? 1 : 0.85
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        function update(x) {
            const f = Math.min(Math.max(x / Math.max(slider.width, 1), 0), 1)
            slider.moved(slider.from + f * (slider.to - slider.from))
        }
        onPressed: (m) => update(m.x)
        onPositionChanged: (m) => { if (pressed) update(m.x) }
        onReleased: slider.released()
    }
}
