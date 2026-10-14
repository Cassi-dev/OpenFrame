import QtQuick
import QtQuick.Templates as T

// Tela inicial: criar um projeto (vazio ou num formato pronto) e abrir,
// renomear, duplicar ou apagar os projetos da biblioteca.
Item {
    id: home
    property string search: ""
    property string pendingId
    readonly property var formats: [
        { aspect: "r16x9", title: "16:9", subtitle: "YouTube · tela cheia", ratio: 16 / 9 },
        { aspect: "r9x16", title: "9:16", subtitle: "Reels · TikTok · Shorts", ratio: 9 / 16 },
        { aspect: "r1x1", title: "1:1", subtitle: "Quadrado", ratio: 1 },
        { aspect: "r4x5", title: "4:5", subtitle: "Feed do Instagram", ratio: 4 / 5 }
    ]

    Component.onCompleted: Editor.refreshLibrary()

    // Barra superior
    Item {
        id: topBar
        width: parent.width
        height: 52
        Row {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            LogoMark {
                width: 22
                height: 22
                anchors.verticalCenter: parent.verticalCenter
                frameColor: Theme.textPrimary
            }
            OfText {
                anchors.verticalCenter: parent.verticalCenter
                text: "OpenFrame"
                size: 14
                weight: Theme.medium
            }
        }
        PillButton {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "Abrir arquivo…"
            iconName: "folder-open"
            help: "Trazer um arquivo .openframe para a biblioteca (Ctrl+O)"
            onClicked: Editor.requestDialog("openProject")
        }
    }

    Panel {
        anchors.fill: parent
        anchors.topMargin: topBar.height
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.bottomMargin: 8

        Flickable {
            id: scroll
            anchors.fill: parent
            contentHeight: page.height + 56
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            T.ScrollBar.vertical: OfScrollBar {}

            Column {
                id: page
                x: 28
                y: 28
                width: scroll.width - 56
                spacing: 32

                // Criar
                Column {
                    spacing: 14
                    OfText { text: "Criar"; size: 22; weight: Theme.light }
                    Row {
                        spacing: 12
                        CreateCard {
                            width: 216
                            title: "Novo projeto"
                            subtitle: "Formato do primeiro clipe"
                            help: "Projeto novo; o formato segue o primeiro clipe (Ctrl+N)"
                            accentBorder: true
                            onClicked: Editor.createProject()
                            Rectangle {
                                width: 40
                                height: 40
                                radius: 20
                                color: Theme.accent
                                Icon { anchors.centerIn: parent; name: "plus"; size: 20; color: Theme.textOnAccent }
                            }
                        }
                        Repeater {
                            model: home.formats
                            CreateCard {
                                id: card
                                required property var modelData
                                width: 160
                                title: modelData.title
                                subtitle: modelData.subtitle
                                help: "Projeto novo em " + modelData.title
                                onClicked: Editor.createProject(modelData.aspect)
                                AspectGlyph {
                                    width: 48
                                    height: 48
                                    aspect: card.modelData.ratio
                                    highlighted: card.hovered
                                }
                            }
                        }
                    }
                }

                // Projetos
                Column {
                    width: parent.width
                    spacing: 14
                    Item {
                        width: parent.width
                        height: 30
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            OfText { id: projectsTitle; text: "Projetos"; size: 22; weight: Theme.light }
                            OfText {
                                anchors.baseline: projectsTitle.baseline
                                text: Editor.entries.count
                                size: 13
                                color: Theme.textTertiary
                            }
                        }
                        SearchField {
                            visible: Editor.entries.count > 0
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: home.search
                            onTextEdited: (t) => home.search = t
                        }
                    }

                    EmptyState {
                        visible: Editor.entries.count === 0
                        width: parent.width
                        title: "Nenhum projeto ainda"
                        detail: "Crie um projeto acima ou abra um arquivo .openframe."
                    }
                    EmptyState {
                        visible: Editor.entries.count > 0 && grid.visibleCount === 0
                        width: parent.width
                        title: "Nenhum projeto com “" + home.search.trim() + "”"
                    }

                    // Grade adaptável: colunas de 220 a 300, espaço 18 × 22.
                    Flow {
                        id: grid
                        width: parent.width
                        spacing: 18
                        readonly property int columns: Math.max(1, Math.floor((width + spacing) / (220 + spacing)))
                        readonly property real cardWidth: Math.min(300, (width - spacing * (columns - 1)) / columns)
                        property int visibleCount: {
                            let n = 0
                            const q = home.search.trim().toLowerCase()
                            for (let i = 0; i < Editor.entries.count; ++i)
                                if (q === "" || Editor.entries.get(i).name.toLowerCase().indexOf(q) >= 0) n++
                            return n
                        }
                        Repeater {
                            model: Editor.entries
                            ProjectCard {
                                required property string uid
                                required property string name
                                required property string subtitle
                                required property string durationText
                                required property real aspectValue
                                required property string thumbnail
                                entryId: uid
                                entryName: name
                                entrySubtitle: subtitle
                                entryDuration: durationText
                                entryAspect: aspectValue
                                entryThumbnail: thumbnail
                                width: grid.cardWidth
                                visible: home.search.trim() === "" || name.toLowerCase().indexOf(home.search.trim().toLowerCase()) >= 0
                                onRename: {
                                    home.pendingId = uid
                                    renameDialog.fieldText = name
                                    renameDialog.open()
                                }
                                onRemove: {
                                    home.pendingId = uid
                                    deleteDialog.title = "Apagar “" + name + "”?"
                                    deleteDialog.open()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    OfDialog {
        id: renameDialog
        title: "Renomear projeto"
        hasField: true
        acceptTitle: "Renomear"
        onAccepted: Editor.renameProject(home.pendingId, fieldText)
    }
    OfDialog {
        id: deleteDialog
        message: "O projeto vai para a Lixeira. Os vídeos, fotos e áudios usados nele não são apagados."
        acceptTitle: "Mover para a Lixeira"
        destructive: true
        onAccepted: Editor.deleteProject(home.pendingId)
    }
}
