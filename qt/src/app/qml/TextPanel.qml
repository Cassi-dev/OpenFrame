import QtQuick

// Texto: adicionar no cursor e estilos prontos.
Column {
    id: panel
    padding: 14
    spacing: 12
    readonly property real inner: width - 28

    PanelHeader { width: panel.inner; title: "Texto" }
    PillButton {
        width: panel.inner
        fill: true
        text: "Adicionar texto"
        iconName: "plus"
        help: "Adicionar texto no cursor (Ctrl+T)"
        onClicked: Editor.addText()
    }
    SectionHeader { width: panel.inner; title: "Estilos" }
    Grid {
        columns: 2
        spacing: 10
        Repeater {
            model: Editor.textPresets()
            StyleCard {
                required property var modelData
                width: (panel.inner - 10) / 2
                preset: modelData.value
                text: modelData.title
                onClicked: Editor.addText(modelData.value)
            }
        }
    }
    OfText {
        width: panel.inner
        text: "Clique num estilo para adicionar um texto no cursor."
        size: 11
        color: Theme.textTertiary
        wrapMode: Text.Wrap
    }
}
