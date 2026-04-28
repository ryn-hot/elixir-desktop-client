import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Rectangle {
    id: root
    property string title: "Nothing here yet"
    property string message: ""
    property string actionText: ""
    signal actionRequested()

    radius: Theme.radius8
    color: Theme.surface
    border.color: Theme.borderSubtle
    implicitHeight: 180

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.space40, 520)
        spacing: Theme.space12

        Label {
            text: root.title
            color: Theme.textPrimary
            font.family: Theme.fontDisplay
            font.pixelSize: 20
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        Label {
            text: root.message
            color: Theme.textSecondary
            font.family: Theme.fontBody
            font.pixelSize: 13
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            visible: root.message !== ""
        }

        ActionButton {
            text: root.actionText
            variant: "primary"
            visible: root.actionText !== ""
            Layout.alignment: Qt.AlignHCenter
            onClicked: root.actionRequested()
        }
    }
}
