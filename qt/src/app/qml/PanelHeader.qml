import QtQuick

// Título de painel (Inter Light), com detalhe e ações à direita.
Item {
    id: root
    property string title
    property string detail
    default property alias trailing: trailingRow.data

    width: parent ? parent.width : implicitWidth
    implicitHeight: 30

    Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        OfText {
            id: titleText
            text: root.title
            size: 16
            weight: Theme.light
        }
        OfText {
            visible: root.detail !== ""
            anchors.baseline: titleText.baseline
            text: root.detail
            size: 11
            color: Theme.textTertiary
        }
    }
    Row {
        id: trailingRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6
    }
}
