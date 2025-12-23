import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../"

Item {
    id: root
    signal homeRequested()
    signal settingsRequested()

    height: 72

    Rectangle {
        anchors.fill: parent
        color: Theme.backgroundMid
        border.color: Theme.border
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingLarge

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Label {
                text: "Elixir"
                color: Theme.textPrimary
                font.pixelSize: 20
                font.family: Theme.fontDisplay
                font.weight: Font.DemiBold
            }
            Label {
                text: "Home media, cinematic control"
                color: Theme.textMuted
                font.pixelSize: 11
                font.family: Theme.fontBody
            }
        }

        Button {
            text: "Home"
            onClicked: root.homeRequested()
            background: Rectangle {
                radius: Theme.radiusSmall
                color: Theme.backgroundCard
                border.color: Theme.border
            }
            contentItem: Label {
                text: parent.text
                color: Theme.textPrimary
                font.family: Theme.fontBody
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        Button {
            text: "Settings"
            onClicked: root.settingsRequested()
            background: Rectangle {
                radius: Theme.radiusSmall
                color: Theme.backgroundCard
                border.color: Theme.border
            }
            contentItem: Label {
                text: parent.text
                color: Theme.textPrimary
                font.family: Theme.fontBody
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
