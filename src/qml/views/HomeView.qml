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
    property string sectionFilter: "all"
    property bool filterActive: sectionFilter !== "all"
    property string sectionLabel: {
        if (sectionFilter === "movies") return "Movies"
        if (sectionFilter === "series") return "TV Shows"
        if (sectionFilter === "anime") return "Anime"
        return ""
    }

    function setSearchQuery(query) {
        libraryModel.searchQuery = query
    }

    function shouldShowSection(section) {
        return sectionFilter === "all" || sectionFilter === section
    }

    function filteredCount() {
        if (sectionFilter === "movies") return libraryModel.moviesModel().count
        if (sectionFilter === "series") return libraryModel.seriesModel().count
        if (sectionFilter === "anime") return libraryModel.animeModel().count
        return libraryModel.count
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
        contentHeight: column.implicitHeight + Theme.sectionSpacing
        clip: true
        
        // Gradient Background Effect (Simulated)
        Rectangle {
            width: parent.width
            height: 400
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#333538" } // Lighter top
                GradientStop { position: 1.0; color: Theme.bgMain } // Fade to main bg
            }
            z: -1
        }

        ColumnLayout {
            id: column
            width: parent.width
            spacing: Theme.sectionSpacing // Spec: 30-40px spacing
            anchors.top: parent.top
            anchors.topMargin: Theme.sectionSpacing

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Theme.cardSpacing
                spacing: 12
                visible: root.filterActive

                Label {
                    text: root.sectionLabel
                    color: Theme.textPrimary
                    font.pixelSize: 22
                    font.family: Theme.headerFont.family
                }
            }

            // Continue Watching Section
            MediaRow {
                Layout.fillWidth: true
                title: "Continue Watching"
                cardType: "landscape"
                model: libraryModel.continueWatchingModel()
                visible: !root.searchActive && !root.filterActive && count > 0
                property int count: libraryModel.continueWatchingModel().count
                onCardClicked: {
                    if (root.stackView) {
                        root.stackView.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId, stackView: root.stackView })
                    }
                }
            }

            // Search Results
            PosterGrid {
                Layout.fillWidth: true
                title: "Search Results"
                visible: root.searchActive && libraryModel.searchModel.count > 0
                model: libraryModel.searchModel
                onCardClicked: {
                    if (root.stackView) {
                        root.stackView.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId, stackView: root.stackView })
                    }
                }
            }

            // No Search Results
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                Layout.margins: Theme.cardSpacing
                radius: Theme.radiusLarge
                color: Theme.bgCard
                visible: root.searchActive && libraryModel.searchModel.count === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    Label {
                        text: "No matches found"
                        color: Theme.textPrimary
                        font.pixelSize: 18
                        font.family: Theme.headerFont.family
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: "Try adjusting your search terms."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.bodyFont.family
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // Empty Library State
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 180
                Layout.margins: Theme.cardSpacing
                radius: Theme.radiusLarge
                color: Theme.bgCard
                visible: !root.searchActive && !root.filterActive && libraryModel.count === 0 && !root.statusIsError && !root.isLoading

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    Label {
                        text: "Welcome to Elixir"
                        color: Theme.textPrimary
                        font.pixelSize: 20
                        font.family: Theme.headerFont.family
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: "Scan your library to get started."
                        color: Theme.textSecondary
                        font.pixelSize: 13
                        font.family: Theme.bodyFont.family
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Button {
                        text: "Scan Library"
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 16
                        onClicked: {
                            statusText = "Scanning..."
                            isLoading = true
                            statusIsError = false
                            apiClient.runScan(false)
                        }
                        background: Rectangle {
                            radius: 4
                            color: Theme.accent
                        }
                        contentItem: Label {
                            text: parent.text
                            color: "#111"
                            font.pixelSize: 13
                            font.family: Theme.bodyFont.family
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                Layout.margins: Theme.cardSpacing
                radius: Theme.radiusLarge
                color: Theme.bgCard
                visible: !root.searchActive && root.filterActive && root.filteredCount() === 0 && !root.statusIsError && !root.isLoading

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 8

                    Label {
                        text: "Nothing here yet"
                        color: Theme.textPrimary
                        font.pixelSize: 18
                        font.family: Theme.headerFont.family
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: "Scan your library to populate " + root.sectionLabel.toLowerCase() + "."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.bodyFont.family
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // Library Sections
            MediaRow {
                Layout.fillWidth: true
                title: root.sectionFilter === "movies" ? "Movies" : "Recently Added Movies"
                cardType: "portrait"
                model: libraryModel.moviesModel()
                visible: !root.searchActive && root.shouldShowSection("movies") && count > 0
                property int count: libraryModel.moviesModel().count
                onCardClicked: {
                    if (root.stackView) {
                        root.stackView.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId, stackView: root.stackView })
                    }
                }
            }

            MediaRow {
                Layout.fillWidth: true
                title: root.sectionFilter === "series" ? "TV Shows" : "Recently Added TV Shows"
                cardType: "portrait"
                model: libraryModel.seriesModel()
                visible: !root.searchActive && root.shouldShowSection("series") && count > 0
                property int count: libraryModel.seriesModel().count
                onCardClicked: {
                    if (root.stackView) {
                        root.stackView.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId, stackView: root.stackView })
                    }
                }
            }

            MediaRow {
                Layout.fillWidth: true
                title: root.sectionFilter === "anime" ? "Anime" : "Recently Added Anime"
                cardType: "portrait"
                model: libraryModel.animeModel()
                visible: !root.searchActive && root.shouldShowSection("anime") && count > 0
                property int count: libraryModel.animeModel().count
                onCardClicked: {
                    if (root.stackView) {
                        root.stackView.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId, stackView: root.stackView })
                    }
                }
            }

            InlineToast {
                Layout.fillWidth: true
                text: root.statusIsError ? "" : statusText
                autoClear: false
                color: Theme.textSecondary
                font.pixelSize: 11
                font.family: Theme.bodyFont.family
                horizontalAlignment: Text.AlignRight
                Layout.rightMargin: Theme.cardSpacing
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
