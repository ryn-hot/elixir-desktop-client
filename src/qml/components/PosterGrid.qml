import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import Elixir 1.0

Item {
    id: root
    property alias model: grid.model
    property string title: ""
    signal cardClicked(string mediaId)

    implicitHeight: titleLabel.implicitHeight + grid.contentHeight + Theme.spacingMedium

    ColumnLayout {
        width: parent.width
        spacing: Theme.spacingSmall

        Label {
            id: titleLabel
            text: root.title
            color: Theme.textPrimary
            font.pixelSize: 18
            font.family: Theme.fontDisplay
            Layout.fillWidth: true
            visible: root.title !== ""
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            width: parent.width
            height: contentHeight
            cellWidth: 160
            cellHeight: 240
            interactive: false
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
