import QtQuick

// Cápsula de transporte: tempo, controles e ferramentas de visualização.
Rectangle {
    id: bar
    width: row.implicitWidth + 18 + 12
    height: 48
    radius: height / 2
    color: Theme.raised
    border.color: Theme.hairline

    Row {
        id: row
        x: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        Item {
            width: 128
            height: 24
            anchors.verticalCenter: parent.verticalCenter
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                OfText { id: now; text: Editor.playheadText; size: 17; weight: Theme.light; mono: true }
                OfText { anchors.baseline: now.baseline; text: Editor.durationText; size: 11; mono: true; color: Theme.textTertiary }
            }
        }
        VDivider { anchors.verticalCenter: parent.verticalCenter }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            GlyphButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "skip-back"
                help: "Início"
                padding: 4
                onClicked: Editor.goToStart()
            }
            GlyphButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "chevron-left"
                help: "Quadro anterior (←)"
                padding: 4
                onClicked: Editor.step(-1)
            }
            CircleButton {
                anchors.verticalCenter: parent.verticalCenter
                size: 36
                iconSize: 16
                iconName: Editor.isPlaying ? "pause" : "play"
                help: "Reproduzir/pausar (espaço)"
                onClicked: Editor.togglePlay()
            }
            GlyphButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "chevron-right"
                help: "Próximo quadro (→)"
                padding: 4
                onClicked: Editor.step(1)
            }
            GlyphButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "skip-forward"
                help: "Fim"
                padding: 4
                onClicked: Editor.goToEnd()
            }
        }
        VDivider { anchors.verticalCenter: parent.verticalCenter }
        GlyphButton {
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            iconName: "grid-3x3"
            iconSize: 15
            active: Editor.showGrid
            help: Editor.showGrid ? "Ocultar grade" : "Mostrar grade dos terços"
            onClicked: Editor.showGrid = !Editor.showGrid
        }
    }
}
