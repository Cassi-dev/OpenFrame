import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Visão mobile do editor para telas de celular (orientação retrato / touch-first)
// Organizada em: TopBar móvel -> Preview do vídeo -> Timeline touch -> Barra de ferramentas inferior
Item {
    id: mobileEditor
    anchors.fill: parent

    // Estado da gaveta de ferramentas ativa
    property string activeDrawer: "none" // "none", "library", "inspector", "text"

    // 1. Barra Superior Mobile (52px)
    Rectangle {
        id: mobileTopBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 52
        color: Theme.background

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            // Botão Voltar para Projetos
            CircleButton {
                iconName: "chevron-left"
                help: "Voltar aos projetos"
                size: 34
                onClicked: Editor.screen = "home"
            }

            // Timecode compacto
            OfText {
                text: Editor.currentTimecode
                color: Theme.textSecondary
                family: Theme.monoFont
                size: 12
            }

            Item { Layout.fillWidth: true }

            // Desfazer / Refazer
            GlyphButton {
                iconName: "undo-2"
                iconSize: 16
                help: "Desfazer"
                enabled: Editor.canUndo
                onClicked: Editor.undo()
            }
            GlyphButton {
                iconName: "redo-2"
                iconSize: 16
                help: "Refazer"
                enabled: Editor.canRedo
                onClicked: Editor.redo()
            }

            // Botão Exportar destacado
            PillButton {
                kind: "primary"
                text: "Exportar"
                compact: true
                onClicked: Editor.showExport = true
            }
        }

        // Divisor fino
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.border
        }
    }

    // 2. Área de Preview
    Item {
        id: previewArea
        anchors.top: mobileTopBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: timelineArea.top
        anchors.margins: 8

        // Canvas do vídeo
        Item {
            id: canvas
            readonly property real aspect: Editor.aspectValue > 0 ? Editor.aspectValue : 16 / 9
            readonly property bool wide: aspect >= previewArea.width / Math.max(previewArea.height, 1)
            width: wide ? previewArea.width : previewArea.height * aspect
            height: wide ? previewArea.width / aspect : previewArea.height
            anchors.centerIn: parent

            PreviewFrame {
                id: frame
                anchors.fill: parent
                radius: 8
            }

            // Grade dos terços (se ativada)
            Item {
                visible: Editor.showGrid
                anchors.fill: parent
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        x: Math.round(canvas.width * (index + 1) / 3)
                        width: 1
                        height: canvas.height
                        color: Theme.alpha(Theme.accent, 0.55)
                    }
                }
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        y: Math.round(canvas.height * (index + 1) / 3)
                        width: canvas.width
                        height: 1
                        color: Theme.alpha(Theme.accent, 0.55)
                    }
                }
            }

            // Mensagem quando o projeto está vazio
            Rectangle {
                visible: Editor.duration === 0
                anchors.fill: parent
                radius: 8
                color: Theme.alpha(Theme.raised, 0.75)
                Column {
                    anchors.centerIn: parent
                    spacing: 10
                    OfText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Toque em + para adicionar vídeo"
                        color: Theme.textSecondary
                        size: 13
                    }
                    PillButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        compact: true
                        text: "Importar vídeo"
                        onClicked: Editor.requestDialog("importMedia")
                    }
                }
            }
        }

        // Botão flutuante de Play / Pause no centro inferior do preview
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 8
            width: 44
            height: 44
            radius: 22
            color: Theme.alpha(Theme.raised, 0.85)
            border.color: Theme.border
            border.width: 1

            Icon {
                anchors.centerIn: parent
                name: Editor.playing ? "pause" : "play"
                color: Theme.textPrimary
                size: 20
            }

            MouseArea {
                anchors.fill: parent
                onClicked: Editor.togglePlay()
            }
        }
    }

    // 3. Área da Timeline
    Item {
        id: timelineArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: mobileBottomBar.top
        height: Math.max(160, parent.height * 0.35)

        // Barra de Ações Rápidas da Timeline (Dividir, Apagar, Posição)
        Rectangle {
            id: quickBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 38
            color: Theme.background

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                // Botão de Dividir clipe selecionado (Split)
                GlyphButton {
                    iconName: "scissors"
                    text: "Dividir"
                    iconSize: 15
                    enabled: Editor.hasSelection
                    onClicked: Editor.splitAtPlayhead()
                }

                // Botão de Apagar clipe
                GlyphButton {
                    iconName: "trash-2"
                    text: "Apagar"
                    iconSize: 15
                    enabled: Editor.hasSelection
                    onClicked: Editor.deleteSelected()
                }

                Item { Layout.fillWidth: true }

                // Posição no tempo
                OfText {
                    text: Editor.currentTimecode + " / " + Editor.durationTimecode
                    color: Theme.textTertiary
                    size: 11
                    family: Theme.monoFont
                }
            }
        }

        // Timeline propriamente dita
        Panel {
            anchors.top: quickBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 4

            TimelineView {
                anchors.fill: parent
            }
        }
    }

    // 4. Barra de Ferramentas Inferior (Bottom Navigation Touch Bar)
    Rectangle {
        id: mobileBottomBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 64
        color: Theme.background

        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.border
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // 1. Adicionar Mídia
            MobileNavButton {
                Layout.fillWidth: true
                Layout.fillHeight: true
                iconName: "plus"
                label: "Mídia"
                active: mobileEditor.activeDrawer === "library"
                onClicked: {
                    if (mobileEditor.activeDrawer === "library") {
                        mobileEditor.activeDrawer = "none"
                    } else {
                        mobileEditor.activeDrawer = "library"
                    }
                }
            }

            // 2. Adicionar Texto / Legendas
            MobileNavButton {
                Layout.fillWidth: true
                Layout.fillHeight: true
                iconName: "type"
                label: "Texto"
                active: mobileEditor.activeDrawer === "text"
                onClicked: {
                    if (mobileEditor.activeDrawer === "text") {
                        mobileEditor.activeDrawer = "none"
                    } else {
                        mobileEditor.activeDrawer = "text"
                    }
                }
            }

            // 3. Ajustes / Inspetor do Clipe
            MobileNavButton {
                Layout.fillWidth: true
                Layout.fillHeight: true
                iconName: "sliders-horizontal"
                label: "Editar"
                active: mobileEditor.activeDrawer === "inspector"
                onClicked: {
                    if (mobileEditor.activeDrawer === "inspector") {
                        mobileEditor.activeDrawer = "none"
                    } else {
                        mobileEditor.activeDrawer = "inspector"
                    }
                }
            }

            // 4. Proporção da Tela (16:9, 9:16, 1:1)
            MobileNavButton {
                Layout.fillWidth: true
                Layout.fillHeight: true
                iconName: "grid-3x3"
                label: "Formato"
                onClicked: {
                    if (Editor.aspectRatio === "9:16") {
                        Editor.aspectRatio = "16:9"
                    } else if (Editor.aspectRatio === "16:9") {
                        Editor.aspectRatio = "1:1"
                    } else {
                        Editor.aspectRatio = "9:16"
                    }
                }
            }
        }
    }

    // 5. Gaveta Deslizante (BottomSheet Drawer) para Mídia / Inspetor / Texto
    Rectangle {
        id: drawer
        visible: mobileEditor.activeDrawer !== "none"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: mobileBottomBar.top
        height: Math.min(320, parent.height * 0.45)
        color: Theme.raised
        border.color: Theme.border
        border.width: 1
        radius: 12

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8

            // Cabeçalho da Gaveta
            RowLayout {
                Layout.fillWidth: true
                OfText {
                    text: mobileEditor.activeDrawer === "library" ? "Biblioteca de Mídia" :
                          mobileEditor.activeDrawer === "inspector" ? "Ajustes do Clipe" : "Adicionar Texto"
                    size: 13
                    weight: Theme.medium
                    color: Theme.textPrimary
                }
                Item { Layout.fillWidth: true }
                CircleButton {
                    iconName: "x"
                    size: 26
                    onClicked: mobileEditor.activeDrawer = "none"
                }
            }

            // Conteúdo dinâmico da gaveta
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: {
                    if (mobileEditor.activeDrawer === "library") return libraryComponent
                    if (mobileEditor.activeDrawer === "inspector") return inspectorComponent
                    return textComponent
                }
            }
        }
    }

    Component {
        id: libraryComponent
        LibraryView { anchors.fill: parent }
    }
    Component {
        id: inspectorComponent
        InspectorView { anchors.fill: parent }
    }
    Component {
        id: textComponent
        TextTab { anchors.fill: parent }
    }
}
