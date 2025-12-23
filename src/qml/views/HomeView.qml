import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "homeView"
    property StackView stackView: null
    property string statusText: ""

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
                    if (root.stackView) {
                        root.stackView.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId, stackView: root.stackView })
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                visible: libraryModel.count === 0

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    Label {
                        text: "No library items yet"
                        color: Theme.textPrimary
                        font.pixelSize: 18
                        font.family: Theme.fontDisplay
                    }
                    Label {
                        text: "Run a scan or check your server connection."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }
                    RowLayout {
                        spacing: Theme.spacingMedium
                        Button {
                            text: "Scan now"
                            onClicked: {
                                statusText = "Scanning..."
                                apiClient.runScan(false)
                            }
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.accent
                            }
                            contentItem: Label {
                                text: parent.text
                                color: "#111111"
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        Button {
                            text: "Refresh"
                            onClicked: apiClient.fetchLibrary()
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                            }
                            contentItem: Label {
                                text: parent.text
                                color: Theme.textPrimary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }

            MediaRow {
                Layout.fillWidth: true
                title: "Continue Watching"
                model: libraryModel.continueWatchingModel()
                onCardClicked: {
                    if (root.stackView) {
                        root.stackView.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId, stackView: root.stackView })
                    }
                }
            }

            MediaRow {
                Layout.fillWidth: true
                title: "Movies"
                model: libraryModel.moviesModel()
                onCardClicked: {
                    if (root.stackView) {
                        root.stackView.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId, stackView: root.stackView })
                    }
                }
            }

            MediaRow {
                Layout.fillWidth: true
                title: "Series"
                model: libraryModel.seriesModel()
                onCardClicked: {
                    if (root.stackView) {
                        root.stackView.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId, stackView: root.stackView })
                    }
                }
            }

            MediaRow {
                Layout.fillWidth: true
                title: "Anime"
                model: libraryModel.animeModel()
                onCardClicked: {
                    if (root.stackView) {
                        root.stackView.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId, stackView: root.stackView })
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: statusText
                color: Theme.textMuted
                font.pixelSize: 11
                font.family: Theme.fontBody
                visible: statusText !== ""
            }
        }
    }

    Connections {
        target: apiClient
        function onScanCompleted() {
            statusText = "Scan completed. Refreshing..."
            apiClient.fetchLibrary()
        }
        function onRequestFailed(endpoint, error) {
            statusText = "Request failed: " + error
        }
    }
}
