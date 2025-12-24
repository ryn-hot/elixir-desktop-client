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
    property bool statusIsError: false
    property bool isLoading: false
    property bool searchActive: libraryModel.searchQuery.trim() !== ""

    property var heroItem: libraryModel.count > 0 ? libraryModel.get(0) : null

    ListModel {
        id: filterOptions
        ListElement { label: "All"; value: "all" }
        ListElement { label: "Movies"; value: "movies" }
        ListElement { label: "Series"; value: "series" }
        ListElement { label: "Anime"; value: "anime" }
        ListElement { label: "Continue Watching"; value: "continue" }
    }

    ListModel {
        id: sortOptions
        ListElement { label: "Recently updated"; value: "recent" }
        ListElement { label: "Title A-Z"; value: "title" }
        ListElement { label: "Year (newest)"; value: "year" }
    }

    function indexForValue(model, value) {
        for (var i = 0; i < model.count; i++) {
            if (model.get(i).value === value) {
                return i
            }
        }
        return 0
    }

    Component.onCompleted: {
        isLoading = true
        statusText = "Loading library..."
        statusIsError = false
        apiClient.fetchLibrary()
    }

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

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    TextField {
                        Layout.fillWidth: true
                        text: libraryModel.searchQuery
                        placeholderText: "Search library..."
                        onTextChanged: libraryModel.searchQuery = text
                    }

                    ComboBox {
                        id: filterCombo
                        model: filterOptions
                        textRole: "label"
                        currentIndex: indexForValue(filterOptions, libraryModel.filterMode)
                        onActivated: libraryModel.filterMode = filterOptions.get(index).value
                    }

                    ComboBox {
                        id: sortCombo
                        model: sortOptions
                        textRole: "label"
                        currentIndex: indexForValue(sortOptions, libraryModel.sortMode)
                        onActivated: libraryModel.sortMode = sortOptions.get(index).value
                    }

                    Button {
                        text: "Clear"
                        enabled: root.searchActive
                        onClicked: libraryModel.searchQuery = ""
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

                    Button {
                        text: "Refresh"
                        onClicked: {
                            isLoading = true
                            statusText = "Refreshing library..."
                            statusIsError = false
                            apiClient.fetchLibrary()
                        }
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

            HeroBanner {
                Layout.fillWidth: true
                Layout.preferredHeight: root.height * 0.35
                media: root.heroItem
                visible: !root.searchActive
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
                visible: !root.searchActive && libraryModel.count === 0 && !root.statusIsError && !root.isLoading

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
                                isLoading = true
                                statusIsError = false
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
                            onClicked: {
                                isLoading = true
                                statusText = "Refreshing library..."
                                statusIsError = false
                                apiClient.fetchLibrary()
                            }
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

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 160
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                visible: root.statusIsError

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    Label {
                        text: "Library error"
                        color: Theme.textPrimary
                        font.pixelSize: 18
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        text: statusText
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        spacing: Theme.spacingMedium
                        Button {
                            text: "Retry"
                            onClicked: {
                                isLoading = true
                                statusText = "Retrying..."
                                statusIsError = false
                                apiClient.fetchLibrary()
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
                    }
                }
            }

            PosterGrid {
                Layout.fillWidth: true
                title: "Search results"
                visible: root.searchActive && libraryModel.searchModel.count > 0
                model: libraryModel.searchModel
                onCardClicked: {
                    if (root.stackView) {
                        root.stackView.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId, stackView: root.stackView })
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                visible: root.searchActive && libraryModel.searchModel.count === 0

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    Label {
                        text: "No matches"
                        color: Theme.textPrimary
                        font.pixelSize: 18
                        font.family: Theme.fontDisplay
                    }
                    Label {
                        text: "Try adjusting your search, filters, or sort order."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }
                }
            }

            MediaRow {
                Layout.fillWidth: true
                title: "Continue Watching"
                model: libraryModel.continueWatchingModel()
                visible: !root.searchActive
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
                visible: !root.searchActive
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
                visible: !root.searchActive
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
                visible: !root.searchActive
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
                visible: statusText !== "" && !root.statusIsError
            }
        }
    }

    Connections {
        target: apiClient
        function onScanCompleted() {
            statusText = "Scan completed. Refreshing..."
            isLoading = true
            statusIsError = false
            apiClient.fetchLibrary()
        }
        function onLibraryReceived(items) {
            statusText = ""
            statusIsError = false
            isLoading = false
        }
        function onRequestFailed(endpoint, error) {
            statusText = "Request failed: " + error
            statusIsError = true
            isLoading = false
        }
    }
}
