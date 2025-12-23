import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import Elixir 1.0

Item {
    id: root
    property alias model: view.model
    property string title: ""
    signal cardClicked(string mediaId)

    ColumnLayout {
        width: parent.width
        spacing: Theme.spacingSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Label {
                text: root.title
                color: Theme.textPrimary
                font.pixelSize: 18
                font.family: Theme.fontDisplay
                Layout.fillWidth: true
            }
        }

        ListView {
            id: view
            Layout.fillWidth: true
            height: 240
            orientation: ListView.Horizontal
            spacing: Theme.spacingMedium
            clip: true

            delegate: MediaCard {
                mediaId: mediaId
                title: title
                posterUrl: poster
                progress: progress
                onClicked: root.cardClicked(mediaId)
            }
        }
    }
}
