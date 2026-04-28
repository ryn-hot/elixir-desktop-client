import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    property alias model: grid.model
    property string title: ""
    property string subtitle: ""
    signal cardClicked(string mediaId)

    implicitHeight: header.implicitHeight + grid.contentHeight + Theme.space24

    ColumnLayout {
        width: parent.width
        spacing: Theme.space16

        SectionHeader {
            id: header
            title: root.title
            subtitle: root.subtitle
            Layout.fillWidth: true
            visible: root.title !== ""
        }

        GridView {
            id: grid
            Layout.fillWidth: true
            width: parent.width
            Layout.preferredHeight: contentHeight
            cellWidth: Theme.posterWidth + Theme.cardSpacing
            cellHeight: Theme.posterHeight + 68
            interactive: false
            clip: true

            delegate: Item {
                id: cardDelegate
                required property string mediaId
                required property string title
                required property var year
                required property string poster
                required property var progress
                required property bool trackedByManager

                width: Theme.posterWidth
                height: Theme.posterHeight + 58

                MediaPosterCard {
                    anchors.fill: parent
                    mediaId: cardDelegate.mediaId
                    title: cardDelegate.title
                    subtitle: cardDelegate.year ? String(cardDelegate.year) : ""
                    imageSource: cardDelegate.poster
                    progress: cardDelegate.progress !== undefined ? cardDelegate.progress : 0
                    trackedByManager: cardDelegate.trackedByManager === true
                    onClicked: root.cardClicked(mediaId)
                }
            }
        }
    }
}
