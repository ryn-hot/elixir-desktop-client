import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    property alias model: grid.model
    property string title: ""
    signal cardClicked(string mediaId)

    implicitHeight: titleLabel.implicitHeight + grid.contentHeight + Theme.sectionSpacing

    ColumnLayout {
        width: parent.width
        spacing: Theme.cardSpacing

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
            cellWidth: Theme.posterWidth + Theme.cardSpacing
            cellHeight: Theme.posterHeight + 60 // + metadata + spacing
            interactive: false
            clip: true

            delegate: MediaCard {
                mediaId: model.mediaId
                title: model.title
                imageSource: model.poster
                progress: model.progress
                cardType: "portrait"
                onClicked: root.cardClicked(model.mediaId)
            }
        }
    }
}
