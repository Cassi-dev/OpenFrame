import QtQuick
import QtQuick.Templates as T

// Cartão de estilo de texto com uma amostra aproximada.
T.AbstractButton {
    id: card
    property string preset

    implicitHeight: 64 + 6 + 15
    hoverEnabled: true
    focusPolicy: Qt.NoFocus

    component Sample: Text {
        font.family: Theme.family
        font.pixelSize: 22
        font.weight: Theme.medium
        color: "white"
    }

    contentItem: Item {
        Rectangle {
            id: box
            width: parent.width
            height: 64
            radius: 9
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0.22, 0.22, 0.22, 1) }
                GradientStop { position: 1; color: Qt.rgba(0.12, 0.12, 0.12, 1) }
            }
            border.color: card.hovered ? Qt.rgba(1, 1, 1, 0.25) : Theme.hairline

            Item {
                anchors.centerIn: parent
                width: childrenRect.width
                height: childrenRect.height

                // Clássico: branco com sombra suave.
                Item {
                    visible: card.preset === "classic"
                    width: classic.width; height: classic.height
                    Sample { x: 0; y: 1; text: "Aa"; color: Qt.rgba(0, 0, 0, 0.6) }
                    Sample { id: classic; text: "Aa" }
                }
                Sample { visible: card.preset === "outline"; text: "Aa"; style: Text.Outline; styleColor: "black" }
                Rectangle {
                    visible: card.preset === "highlight"
                    width: hl.width + 12; height: hl.height; radius: 3; color: "#FFD91A"
                    Sample { id: hl; anchors.centerIn: parent; text: "Aa"; color: "black" }
                }
                Sample { visible: card.preset === "neon"; text: "Aa"; color: Qt.rgba(0.3, 1, 0.95, 1); style: Text.Outline; styleColor: Qt.rgba(0.3, 1, 0.95, 0.35) }
                Rectangle {
                    visible: card.preset === "caption"
                    width: cap.width + 16; height: cap.height + 4; radius: 5; color: Qt.rgba(0, 0, 0, 0.55)
                    Sample { id: cap; anchors.centerIn: parent; text: "Aa"; font.pixelSize: 20; font.weight: Theme.regular }
                }
                Rectangle {
                    visible: card.preset === "label"
                    width: lab.width + 20; height: lab.height + 6; radius: height / 2; color: Qt.rgba(0.9, 0.2, 0.25, 1)
                    Sample { id: lab; anchors.centerIn: parent; text: "AA"; font.pixelSize: 18; font.letterSpacing: 1.5 }
                }
                Item {
                    visible: card.preset === "longShadow"
                    width: ls.width + 2; height: ls.height + 2
                    Sample { x: 2; y: 2; text: "Aa"; color: "black" }
                    Sample { id: ls; text: "Aa" }
                }
                Sample { visible: card.preset === "spaced"; text: "AA"; font.pixelSize: 18; font.weight: Theme.regular; font.letterSpacing: 6 }
            }
        }
        OfText {
            y: 70
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: card.text
            size: 11
            color: card.hovered ? Theme.textPrimary : Theme.textSecondary
        }
    }
}
