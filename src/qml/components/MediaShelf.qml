import QtQuick 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    property alias model: view.model
    property string title: ""
    property string subtitle: ""
    property string cardType: "portrait"
    property int count: model && model.count !== undefined ? model.count : 0
    signal cardClicked(string mediaId)

    implicitHeight: column.implicitHeight
    visible: count > 0

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 14

        SectionHeader {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.space32
            Layout.rightMargin: Theme.space32
            title: root.title
            subtitle: root.subtitle
        }

        ListView {
            id: view
            Layout.fillWidth: true
            Layout.preferredHeight: root.cardType === "landscape" ? Theme.landscapeHeight + 56 : Theme.posterHeight + 58
            orientation: ListView.Horizontal
            spacing: Theme.cardSpacing
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            header: Item { width: Theme.space32 }
            footer: Item { width: Theme.space32 }

            delegate: Item {
                id: cardDelegate
                required property string mediaId
                required property string title
                required property var year
                required property string poster
                required property string backdrop
                required property var progress
                required property bool trackedByManager

                width: root.cardType === "landscape" ? Theme.landscapeWidth : Theme.posterWidth
                height: view.height

                MediaPosterCard {
                    anchors.fill: parent
                    visible: root.cardType !== "landscape"
                    mediaId: cardDelegate.mediaId
                    title: cardDelegate.title
                    subtitle: cardDelegate.year ? String(cardDelegate.year) : ""
                    imageSource: cardDelegate.poster
                    progress: cardDelegate.progress !== undefined ? cardDelegate.progress : 0
                    trackedByManager: cardDelegate.trackedByManager === true
                    onClicked: root.cardClicked(mediaId)
                }

                MediaLandscapeCard {
                    anchors.fill: parent
                    visible: root.cardType === "landscape"
                    mediaId: cardDelegate.mediaId
                    title: cardDelegate.title
                    subtitle: cardDelegate.year ? String(cardDelegate.year) : ""
                    imageSource: cardDelegate.backdrop !== "" ? cardDelegate.backdrop : cardDelegate.poster
                    progress: cardDelegate.progress !== undefined ? cardDelegate.progress : 0
                    onClicked: root.cardClicked(mediaId)
                }
            }
        }
    }
}
