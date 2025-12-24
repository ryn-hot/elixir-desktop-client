import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import Elixir 1.0

Item {
    id: root
    property var media: null
    signal playRequested(string mediaId)
    signal detailsRequested(string mediaId)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: Theme.backgroundCard
        border.color: Theme.border
        clip: true

        Image {
            anchors.fill: parent
            source: media && (media.backdrop || media.poster) ? (media.backdrop || media.poster) : ""
            fillMode: Image.PreserveAspectCrop
            visible: source !== ""
            opacity: 0.85
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#AA050509" }
                GradientStop { position: 0.5; color: "#550509" }
                GradientStop { position: 1.0; color: "#050509" }
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Theme.spacingXLarge
            spacing: Theme.spacingMedium
            width: parent.width * 0.6

            RowLayout {
                spacing: Theme.spacingSmall
                visible: media !== null

                PillTag { text: media ? media.type : "" }
                PillTag { text: media && media.year ? media.year : "" }
            }

            Label {
                text: media ? media.title : "No library items yet"
                color: Theme.textPrimary
                font.pixelSize: 28
                font.family: Theme.fontDisplay
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }

            Label {
                text: media ? (media.overview || "No synopsis available yet.") : "Scan your library to populate the dashboard."
                color: Theme.textSecondary
                font.pixelSize: 13
                font.family: Theme.fontBody
                wrapMode: Text.Wrap
                maximumLineCount: 3
            }

            RowLayout {
                spacing: Theme.spacingMedium

                Button {
                    text: "Play"
                    enabled: media !== null
                    onClicked: root.playRequested(media.mediaId)
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.accent
                    }
                    contentItem: Label {
                        text: parent.text
                        color: "#111111"
                        font.pixelSize: 13
                        font.family: Theme.fontBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Button {
                    text: "Details"
                    enabled: media !== null
                    onClicked: root.detailsRequested(media.mediaId)
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCard
                        border.color: Theme.border
                    }
                    contentItem: Label {
                        text: parent.text
                        color: Theme.textPrimary
                        font.pixelSize: 13
                        font.family: Theme.fontBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
