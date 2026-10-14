import QtQuick
import QtQuick.Layouts

// Linha "rótulo → controle", como nos formulários do app Swift. O rótulo tem
// largura mínima de 84 para alinhar as colunas; rótulos maiores crescem.
RowLayout {
    id: row
    property string label
    default property alias content: holder.data

    width: parent ? parent.width : implicitWidth
    spacing: 10

    OfText {
        text: row.label
        size: 12
        color: Theme.textSecondary
        elide: Text.ElideNone
        Layout.minimumWidth: 84
        Layout.preferredWidth: Math.max(84, implicitWidth)
    }
    Item {
        id: holder
        Layout.fillWidth: true
        implicitHeight: childrenRect.height
        Layout.preferredHeight: Math.max(implicitHeight, 20)
    }
}
