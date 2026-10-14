import QtQuick
import QtQuick.Templates as T
import "Fmt.js" as Fmt

// Inspetor do projeto (nada selecionado): nome, duração, canvas e fundo.
Flickable {
    id: root
    contentHeight: column.height + 28
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    T.ScrollBar.vertical: OfScrollBar {}

    readonly property var canvas: Editor.canvas

    Column {
        id: column
        x: 14
        y: 14
        width: root.width - 28
        spacing: 12

        PanelHeader { title: "Projeto" }
        FieldRow {
            label: "Nome"
            InputField {
                width: parent.width
                text: Editor.projectName
                onEditingFinished: Editor.setProjectName(text)
            }
        }
        FieldRow {
            label: "Duração"
            OfText { text: Editor.durationText; mono: true }
        }
        FieldRow {
            label: "Clipes"
            OfText { text: Editor.clipCount; mono: true }
        }

        SectionHeader { title: "Canvas" }
        FieldRow {
            label: "Proporção"
            MenuField {
                options: Editor.aspectOptions
                value: Editor.aspect
                onPicked: (v) => Editor.setAspect(v)
            }
        }
        // Rótulo em cima: ao lado dele, "Desfoque" não cabia na pílula.
        Column {
            width: parent.width
            spacing: 6
            OfText { text: "Fundo"; color: Theme.textSecondary }
            PillPicker {
                width: parent.width
                options: [{ value: "black", title: "Preto" }, { value: "color", title: "Cor" }, { value: "blur", title: "Desfoque" }]
                value: root.canvas.background
                onPicked: (v) => Editor.setCanvasBackground(v)
            }
        }
        ColorRow {
            visible: root.canvas.background === "color"
            title: "Cor do fundo"
            color: root.canvas.color || "black"
            onPicked: (c) => Editor.setCanvasColor(c)
        }
        ParamSlider {
            visible: root.canvas.background === "blur"
            title: "Intensidade do desfoque"
            value: root.canvas.blur || 0
            from: 0; to: 1; defaultValue: 0.5
            format: Fmt.percent
            onMoved: (v) => Editor.setCanvasBlur(v)
        }
        Note { text: "O fundo aparece onde o vídeo não cobre o canvas, por exemplo ao converter 16:9 para 9:16." }

        SectionHeader { title: "Dica" }
        Note { text: "Selecione um clipe na timeline para ajustar transformação, cor, filtros, efeitos, animações e transições." }
    }
}
