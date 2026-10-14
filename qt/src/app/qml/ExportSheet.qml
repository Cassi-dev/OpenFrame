import QtQuick
import QtQuick.Templates as T

// Janela de exportação: configurações à esquerda, resumo com o tamanho
// estimado à direita; depois, progresso, conclusão ou erro.
T.Popup {
    id: sheet
    parent: T.Overlay.overlay
    anchors.centerIn: parent
    width: 680
    height: Math.max(540, Math.min(640, (parent ? parent.height : 640) - 80))
    modal: true
    padding: 0
    closePolicy: Editor.exportPhase === "exporting" ? T.Popup.NoAutoClose : T.Popup.CloseOnEscape
    visible: Editor.showExport
    onClosed: Editor.showExport = false

    readonly property var settings: Editor.exportSettings
    readonly property var summary: Editor.exportSummary

    T.Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }
    background: Rectangle {
        color: Theme.surface
        radius: Theme.panelRadius
        border.color: Qt.rgba(1, 1, 1, 0.12)
    }

    contentItem: Item {
        Row {
            id: title
            x: 24
            y: 24
            spacing: 10
            OfText { id: heading; text: "Exportar"; size: 22; weight: Theme.light }
            OfText { anchors.baseline: heading.baseline; text: Editor.projectName; color: Theme.textTertiary }
        }

        // Configurações
        Item {
            visible: Editor.exportPhase === "configuring"
            x: 24
            y: title.y + title.height + 14
            width: parent.width - 48
            height: parent.height - y - footer.height

            Flickable {
                id: form
                width: parent.width - 210 - 20
                height: parent.height
                contentHeight: fields.height + 16
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                T.ScrollBar.vertical: OfScrollBar {}
                Column {
                    id: fields
                    width: form.width
                    spacing: 10
                    SectionHeader { title: "Arquivo" }
                    FieldRow {
                        label: "Formato"
                        MenuField { options: Editor.exportOptions("container"); value: sheet.settings.container; onPicked: (v) => Editor.setExportValue("container", v) }
                    }
                    Column {
                        visible: !sheet.settings.audioOnly
                        width: parent.width
                        spacing: 10
                        SectionHeader { title: "Vídeo" }
                        FieldRow {
                            label: "Resolução"
                            MenuField { options: Editor.exportOptions("resolution"); value: sheet.settings.resolution; onPicked: (v) => Editor.setExportValue("resolution", v) }
                        }
                        FieldRow {
                            visible: sheet.settings.resolution === "custom"
                            label: "Tamanho"
                            Row {
                                spacing: 6
                                InputField { width: 70; monoDigits: true; text: sheet.settings.customWidth; validator: IntValidator { bottom: 16; top: 16384 }
                                    onEditingFinished: Editor.setExportValue("customWidth", parseInt(text)) }
                                OfText { height: 28; text: "×"; color: Theme.textTertiary }
                                InputField { width: 70; monoDigits: true; text: sheet.settings.customHeight; validator: IntValidator { bottom: 16; top: 16384 }
                                    onEditingFinished: Editor.setExportValue("customHeight", parseInt(text)) }
                                OfText { height: 28; text: "px"; color: Theme.textTertiary }
                            }
                        }
                        FieldRow {
                            label: "Quadros/s"
                            MenuField { options: Editor.exportOptions("frameRate"); value: sheet.settings.frameRate; onPicked: (v) => Editor.setExportValue("frameRate", v) }
                        }
                        FieldRow {
                            label: "Codificador"
                            MenuField { options: Editor.exportOptions("codec"); value: sheet.settings.codec; onPicked: (v) => Editor.setExportValue("codec", v) }
                        }
                        Column {
                            visible: sheet.settings.codec !== "proRes422"
                            width: parent.width
                            spacing: 10
                            FieldRow {
                                label: "Qualidade"
                                MenuField { options: Editor.exportOptions("bitrateMode"); value: sheet.settings.bitrateMode; onPicked: (v) => Editor.setExportValue("bitrateMode", v) }
                            }
                            FieldRow {
                                visible: sheet.settings.bitrateMode === "custom"
                                label: "Bitrate"
                                Row {
                                    width: parent.width
                                    spacing: 8
                                    ThinSlider {
                                        width: parent.width - 58 - 40 - 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        from: 0.5; to: 150
                                        value: sheet.settings.customMbps
                                        onMoved: (v) => Editor.setExportValue("customMbps", Math.round(v * 10) / 10)
                                    }
                                    InputField {
                                        width: 58; monoDigits: true
                                        text: Number(sheet.settings.customMbps).toFixed(1)
                                        validator: DoubleValidator { bottom: 0.5; top: 800 }
                                        onEditingFinished: Editor.setExportValue("customMbps", parseFloat(text.replace(",", ".")))
                                    }
                                    OfText { height: 28; text: "Mbps"; color: Theme.textTertiary }
                                }
                            }
                            FieldRow {
                                visible: sheet.settings.bitrateMode === "targetSize"
                                label: "Tamanho alvo"
                                Row {
                                    spacing: 8
                                    InputField {
                                        width: 80; monoDigits: true
                                        text: Math.round(sheet.settings.targetMegabytes)
                                        validator: IntValidator { bottom: 1; top: 20000 }
                                        onEditingFinished: Editor.setExportValue("targetMegabytes", parseInt(text))
                                    }
                                    OfText { height: 28; text: "MB"; color: Theme.textTertiary }
                                    Stepper { onStep: (d) => Editor.setExportValue("targetMegabytes", sheet.settings.targetMegabytes + 5 * d) }
                                }
                            }
                            FieldRow {
                                label: "Quadro-chave"
                                Row {
                                    spacing: 8
                                    OfText { height: 28; text: sheet.summary.keyframeText }
                                    Stepper { onStep: (d) => Editor.setExportValue("keyframeInterval", sheet.settings.keyframeInterval + 0.5 * d) }
                                }
                            }
                        }
                    }
                    SectionHeader { title: "Áudio" }
                    SwitchRow { title: "Incluir áudio"; checked: sheet.settings.audioEnabled; onToggled: (on) => Editor.setExportValue("audioEnabled", on) }
                    Column {
                        visible: sheet.settings.audioEnabled
                        width: parent.width
                        spacing: 10
                        FieldRow {
                            label: "Bitrate"
                            MenuField { options: Editor.exportOptions("audioKbps"); value: sheet.settings.audioKbps; onPicked: (v) => Editor.setExportValue("audioKbps", v) }
                        }
                        FieldRow {
                            label: "Amostragem"
                            MenuField { options: Editor.exportOptions("audioSampleRate"); value: sheet.settings.audioSampleRate; onPicked: (v) => Editor.setExportValue("audioSampleRate", v) }
                        }
                    }
                }
            }

            // Resumo à direita: o tamanho estimado em destaque.
            Rectangle {
                anchors.right: parent.right
                y: 10
                width: 210
                height: summaryColumn.height + 32
                radius: Theme.cardRadius
                color: Theme.raised
                border.color: Theme.hairline
                Column {
                    id: summaryColumn
                    x: 16
                    y: 16
                    width: parent.width - 32
                    spacing: 14
                    Column {
                        spacing: 4
                        OfText { text: "Tamanho estimado"; color: Theme.textSecondary }
                        OfText { text: sheet.summary.estimated; size: 28; weight: Theme.thin; color: Theme.accent }
                    }
                    HDivider {}
                    component SummaryRow: Item {
                        property string label
                        property string value
                        width: summaryColumn.width
                        height: 16
                        OfText { text: parent.label; color: Theme.textTertiary }
                        OfText { anchors.right: parent.right; text: parent.value; mono: true }
                    }
                    SummaryRow { visible: !sheet.settings.audioOnly; label: "Dimensões"; value: sheet.summary.dimensions }
                    SummaryRow { visible: !sheet.settings.audioOnly; label: "Quadros/s"; value: sheet.summary.frameRate }
                    SummaryRow { visible: !sheet.settings.audioOnly; label: "Vídeo"; value: sheet.summary.video }
                    SummaryRow { label: "Áudio"; value: sheet.summary.audio }
                    SummaryRow { label: "Duração"; value: sheet.summary.duration }
                }
            }
        }

        // Rodapé das configurações.
        Item {
            id: footer
            visible: Editor.exportPhase === "configuring"
            anchors.bottom: parent.bottom
            width: parent.width
            height: 66
            HDivider {}
            Row {
                visible: sheet.summary.error !== ""
                x: 24
                width: parent.width - 260
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Icon { anchors.verticalCenter: parent.verticalCenter; name: "triangle-alert"; size: 14; color: Theme.warning }
                OfText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 22
                    text: sheet.summary.error
                    color: Theme.warning
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                }
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                PillButton { kind: "quiet"; text: "Cancelar"; onClicked: Editor.showExport = false }
                PillButton {
                    kind: "primary"
                    text: "Exportar…"
                    enabled: sheet.summary.error === ""
                    onClicked: Editor.requestDialog("exportVideo")
                }
            }
        }

        // Exportando
        Column {
            visible: Editor.exportPhase === "exporting"
            x: 24
            width: parent.width - 48
            anchors.verticalCenter: parent.verticalCenter
            spacing: 16
            OfText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(Editor.exportProgress * 100) + "%"
                size: 44
                weight: Theme.thin
                mono: true
            }
            Item {
                width: parent.width
                height: 4
                Rectangle { anchors.fill: parent; radius: 2; color: Qt.rgba(1, 1, 1, 0.1) }
                Rectangle { width: parent.width * Editor.exportProgress; height: 4; radius: 2; color: Theme.accent }
            }
            Item {
                width: parent.width
                height: 16
                OfText { text: "Renderizando"; color: Theme.textSecondary }
                OfText { anchors.right: parent.right; text: Editor.exportRemaining; color: Theme.textTertiary }
            }
        }
        PillButton {
            visible: Editor.exportPhase === "exporting"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 24
            text: "Cancelar exportação"
            onClicked: Editor.cancelExport()
        }

        // Concluída
        Column {
            visible: Editor.exportPhase === "finished"
            anchors.centerIn: parent
            spacing: 14
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "circle-check"; size: 46; color: Theme.accent }
            OfText { anchors.horizontalCenter: parent.horizontalCenter; text: "Exportação concluída"; size: 18; weight: Theme.light }
            OfText { anchors.horizontalCenter: parent.horizontalCenter; text: Editor.exportResult; color: Theme.textSecondary }
        }
        Item {
            visible: Editor.exportPhase === "finished"
            anchors.bottom: parent.bottom
            width: parent.width
            height: 78
            Row {
                x: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                PillButton { text: Qt.platform.os === "windows" ? "Mostrar no Explorador" : "Abrir a pasta"; onClicked: Editor.revealFile(Editor.exportResultPath) }
                PillButton { text: "Abrir"; onClicked: Editor.openFile(Editor.exportResultPath) }
            }
            PillButton {
                anchors.right: parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                kind: "primary"
                text: "Fechar"
                onClicked: Editor.showExport = false
            }
        }

        // Falhou
        Column {
            visible: Editor.exportPhase === "failed"
            anchors.centerIn: parent
            width: parent.width - 96
            spacing: 14
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "octagon-x"; size: 42; color: Theme.danger }
            OfText { anchors.horizontalCenter: parent.horizontalCenter; text: "A exportação falhou"; size: 18; weight: Theme.light }
            OfText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: Editor.exportError
                color: Theme.textSecondary
                wrapMode: Text.Wrap
                maximumLineCount: 6
            }
        }
        Item {
            visible: Editor.exportPhase === "failed"
            anchors.bottom: parent.bottom
            width: parent.width
            height: 78
            PillButton { x: 24; anchors.verticalCenter: parent.verticalCenter; text: "Voltar às configurações"; onClicked: Editor.resetExport() }
            PillButton { anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter; text: "Fechar"; onClicked: Editor.showExport = false }
        }
    }
}
