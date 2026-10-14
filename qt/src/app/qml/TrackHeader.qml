import QtQuick

// Cabeçalho da faixa: ícone do tipo, silenciar e ocultar.
Item {
    id: header
    required property string uid
    required property string kind
    required property bool isMain
    required property bool muted
    required property bool hidden
    required property string icon

    width: 58
    height: 50

    Column {
        anchors.centerIn: parent
        spacing: 7
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: header.icon
            size: 13
            color: header.isMain ? Theme.textSecondary : Theme.textTertiary
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 9
            GlyphButton {
                visible: header.kind !== "text"
                iconName: header.muted ? "volume-x" : "volume-2"
                iconSize: 12
                active: header.muted
                help: header.muted ? "Ativar som" : "Silenciar faixa"
                onClicked: Editor.toggleTrack(header.uid, "muted")
            }
            GlyphButton {
                visible: header.kind !== "audio"
                iconName: header.hidden ? "eye-off" : "eye"
                iconSize: 12
                active: header.hidden
                help: header.hidden ? "Mostrar faixa" : "Ocultar faixa"
                onClicked: Editor.toggleTrack(header.uid, "hidden")
            }
        }
    }
}
