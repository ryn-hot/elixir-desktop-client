import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

RowLayout {
    id: root
    property string title: ""
    property string subtitle: ""
    property string actionText: ""
    signal actionRequested()

    spacing: Theme.space12

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Label {
            text: root.title
            color: Theme.textSecondary
            font.family: Theme.fontDisplay
            font.pixelSize: Theme.fontSection
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Label {
            text: root.subtitle
            visible: root.subtitle !== ""
            color: Theme.textMuted
            font.family: Theme.fontBody
            font.pixelSize: Theme.fontCaption
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    ActionButton {
        text: root.actionText
        compact: true
        variant: "ghost"
        visible: root.actionText !== ""
        onClicked: root.actionRequested()
    }
}
