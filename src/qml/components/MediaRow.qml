import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    property alias model: view.model
    property string title: ""
    property string cardType: "portrait" // "portrait" | "landscape"
    signal cardClicked(string mediaId)

    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column
        width: parent.width
        spacing: 10 // Spec: spacing 10

        // Header
        Label {
            text: root.title
            color: "#a0a0a0" // Spec: #a0a0a0
            font.family: Theme.sectionTitleFont.family
            font.pixelSize: Theme.sectionTitleFont.pixelSize
            font.weight: Theme.sectionTitleFont.weight
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.0
            Layout.fillWidth: true
            Layout.leftMargin: Theme.cardSpacing // Align with cards
        }

        // List
        ListView {
            id: view
            Layout.fillWidth: true
            height: root.cardType === "landscape" ? Theme.landscapeHeight + 40 : Theme.posterHeight + 40
            orientation: ListView.Horizontal
            spacing: Theme.cardSpacing
            clip: true
            
            // Padding for first/last item
            header: Item { width: Theme.cardSpacing }
            footer: Item { width: Theme.cardSpacing }

            delegate: MediaCard {
                mediaId: model.mediaId
                title: model.title
                subtitle: model.year ? model.year : "" // Fallback logic
                imageSource: model.poster // Assuming model has poster, might need backdrop for landscape
                progress: model.progress !== undefined ? model.progress : 0.0
                cardType: root.cardType
                onClicked: root.cardClicked(mediaId)
                
                // For landscape, we might prefer backdrop if available in model
                Component.onCompleted: {
                    if (root.cardType === "landscape" && model.backdrop) {
                        imageSource = model.backdrop
                    }
                }
            }
        }
    }
}
