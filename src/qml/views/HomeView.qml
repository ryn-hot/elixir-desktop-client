import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root

    property var heroItem: libraryModel.count > 0 ? libraryModel.get(0) : null

    Component.onCompleted: apiClient.fetchLibrary()

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + Theme.spacingXLarge
        clip: true

        ColumnLayout {
            id: column
            width: parent.width
            spacing: Theme.spacingXLarge
            anchors.margins: Theme.spacingXLarge

            HeroBanner {
                Layout.fillWidth: true
                Layout.preferredHeight: root.height * 0.35
                media: root.heroItem
                onPlayRequested: apiClient.startPlayback(mediaId, "")
                onDetailsRequested: {
                    if (StackView.view) {
                        StackView.view.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId })
                    }
                }
            }

            MediaRow {
                Layout.fillWidth: true
                title: "Continue Watching"
                model: libraryModel.continueWatchingModel()
                onCardClicked: {
                    if (StackView.view) {
                        StackView.view.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId })
                    }
                }
            }

            MediaRow {
                Layout.fillWidth: true
                title: "Movies"
                model: libraryModel.moviesModel()
                onCardClicked: {
                    if (StackView.view) {
                        StackView.view.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId })
                    }
                }
            }

            MediaRow {
                Layout.fillWidth: true
                title: "Series"
                model: libraryModel.seriesModel()
                onCardClicked: {
                    if (StackView.view) {
                        StackView.view.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId })
                    }
                }
            }

            MediaRow {
                Layout.fillWidth: true
                title: "Anime"
                model: libraryModel.animeModel()
                onCardClicked: {
                    if (StackView.view) {
                        StackView.view.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId })
                    }
                }
            }
        }
    }
}
