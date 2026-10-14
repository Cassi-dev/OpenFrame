import QtQuick

// Par de botões − / + (o Stepper do macOS).
Row {
    id: stepper
    signal step(int delta)
    spacing: 4
    CircleButton { size: 24; iconName: "minus"; onClicked: stepper.step(-1) }
    CircleButton { size: 24; iconName: "plus"; onClicked: stepper.step(1) }
}
