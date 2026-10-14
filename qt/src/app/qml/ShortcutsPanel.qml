import QtQuick

// Atalhos de teclado (os do Mac, com Ctrl no lugar de Cmd).
Flickable {
    id: panel
    contentHeight: column.height + 28
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    readonly property var items: [
        ["Espaço", "Reproduzir / pausar"],
        ["← →", "Quadro a quadro"],
        ["Shift ← →", "10 quadros"],
        ["↑ ↓", "Corte anterior / seguinte"],
        ["Home  End", "Início / fim do projeto"],
        ["Ctrl+B", "Dividir no cursor"],
        ["Ctrl+D", "Duplicar"],
        ["Delete", "Apagar clipe"],
        ["Esc", "Tirar a seleção"],
        ["Ctrl+T", "Adicionar texto"],
        ["Ctrl+I", "Importar mídia"],
        ["Ctrl+Z", "Desfazer"],
        ["Ctrl+Shift+Z", "Refazer"],
        ["Ctrl+=  Ctrl+−", "Zoom da timeline"],
        ["Ctrl + rolar", "Zoom no cursor"],
        ["Shift+Z", "Ajustar timeline à janela"],
        ["Ctrl+S", "Salvar"],
        ["Ctrl+E", "Exportar"]
    ]

    Column {
        id: column
        x: 14
        y: 14
        width: panel.width - 28
        spacing: 12
        PanelHeader { title: "Atalhos" }
        Column {
            width: parent.width
            Repeater {
                model: panel.items
                Item {
                    required property var modelData
                    width: parent.width
                    height: 30
                    OfText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - keys.width - 8
                        text: modelData[1]
                        color: Theme.textSecondary
                    }
                    Rectangle {
                        id: keys
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: keyText.implicitWidth + 14
                        height: 20
                        radius: 5
                        color: Theme.raised
                        border.color: Theme.hairline
                        OfText { id: keyText; anchors.centerIn: parent; text: modelData[0]; size: 11; weight: Theme.medium }
                    }
                }
            }
        }
    }
}
