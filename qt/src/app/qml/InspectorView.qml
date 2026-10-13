import QtQuick
import QtQuick.Templates as T

// Inspetor: o clipe selecionado (abas por ícone) ou o projeto.
Item {
    id: inspector

    ProjectInspector {
        visible: Editor.selection === ""
        anchors.fill: parent
    }

    Item {
        id: segmentInspector
        visible: Editor.selection !== ""
        anchors.fill: parent
        readonly property var seg: Editor.selectedSegment
        readonly property var tabs: Editor.availableTabs
        readonly property string current: Editor.inspectorTab
        readonly property string currentTitle: {
            for (let i = 0; i < tabs.length; ++i)
                if (tabs[i].value === current) return tabs[i].title
            return ""
        }

        // Ícone do tipo, nome e intervalo na timeline.
        Item {
            id: header
            x: 14
            y: 14
            width: parent.width - 28
            height: 30
            Rectangle {
                width: 30
                height: 30
                radius: 9
                color: Theme.raised
                border.color: Theme.hairline
                Icon { anchors.centerIn: parent; name: segmentInspector.seg.icon || "film"; size: 14; color: Theme.textPrimary }
            }
            Column {
                x: 40
                width: parent.width - 40 - 34
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                OfText { width: parent.width; text: segmentInspector.seg.title || ""; size: 13; elide: Text.ElideMiddle }
                OfText { width: parent.width; text: segmentInspector.seg.rangeText || ""; size: 10; mono: true; color: Theme.textTertiary }
            }
            CircleButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                size: 24
                iconName: "x"
                help: "Fechar (mostra o projeto)"
                onClicked: Editor.selection = ""
            }
        }
        PillPicker {
            id: tabPicker
            visible: segmentInspector.tabs.length > 1
            x: 14
            y: header.y + header.height + 12
            width: parent.width - 28
            options: segmentInspector.tabs
            value: segmentInspector.current
            onPicked: (v) => Editor.inspectorTab = v
        }
        OfText {
            id: tabTitle
            x: 14
            y: (tabPicker.visible ? tabPicker.y + tabPicker.height : header.y + header.height) + 14
            text: segmentInspector.currentTitle
            size: 16
            weight: Theme.light
        }

        Flickable {
            id: scroll
            objectName: "inspectorScroll"
            x: 0
            y: tabTitle.y + tabTitle.height + 2
            width: parent.width
            height: parent.height - y
            contentHeight: tabLoader.height + Theme.scrollFade + 16
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            T.ScrollBar.vertical: OfScrollBar {}

            Loader {
                id: tabLoader
                x: 14
                y: Theme.scrollFade
                width: scroll.width - 28
                sourceComponent: {
                    switch (segmentInspector.current) {
                    case "adjust": return adjustTab
                    case "filters": return filtersTab
                    case "effects": return effectsTab
                    case "animation": return animationTab
                    case "transition": return transitionTab
                    case "text": return textTab
                    case "audio": return audioTab
                    default: return basicTab
                    }
                }
            }
        }
        ScrollFade {
            x: scroll.x
            y: scroll.y
            width: scroll.width
        }
        Connections {
            target: Editor
            function onUiChanged() { }
        }
        onCurrentChanged: scroll.contentY = 0
    }

    Component { id: basicTab; BasicTab {} }
    Component { id: adjustTab; AdjustTab {} }
    Component { id: filtersTab; FiltersTab {} }
    Component { id: effectsTab; EffectsTab {} }
    Component { id: animationTab; AnimationTab {} }
    Component { id: transitionTab; TransitionTab {} }
    Component { id: textTab; TextTab {} }
    Component { id: audioTab; AudioTab {} }
}
