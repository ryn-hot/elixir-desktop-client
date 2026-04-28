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
        return "Home"
    }
    property int activeCount: {
        if (root.searchActive) return libraryModel.searchModel.count
        if (sectionFilter === "movies") return libraryModel.moviesModel().count
        if (sectionFilter === "series") return libraryModel.seriesModel().count
        if (sectionFilter === "anime") return libraryModel.animeModel().count
        return libraryModel.count
    }
    property var heroItem: libraryModel.count > 0 ? libraryModel.get(0) : ({})

    function setSearchQuery(query) {
        libraryModel.searchQuery = query
    }

    function shouldShowSection(section) {
        return sectionFilter === "all" || sectionFilter === section
    }

    function sectionModel() {
        if (sectionFilter === "movies") return libraryModel.moviesModel()
        if (sectionFilter === "series") return libraryModel.seriesModel()
        if (sectionFilter === "anime") return libraryModel.animeModel()
        return libraryModel.allModel()
    }

    function openDetails(mediaId) {
        if (root.stackView && mediaId !== "") {
            root.stackView.push(Qt.resolvedUrl("DetailsView.qml"), { mediaId: mediaId, stackView: root.stackView })
        }
    }

    function heroTitle() {
        if (root.heroItem && root.heroItem.title) return root.heroItem.title
        return libraryModel.count > 0 ? "Recently Added" : "Home"
    }

    function heroSubtitle() {
        if (root.heroItem && root.heroItem.overview) return root.heroItem.overview
        if (root.heroItem && root.heroItem.year) return String(root.heroItem.year)
        return "Your media, acquisition, and automation in one place."
    }

    function heroMeta() {
        var item = root.heroItem || {}
        var parts = []
        if (item.type) {
            if (item.type === "series") parts.push("TV Show")
            else if (item.type === "anime") parts.push("Anime")
            else parts.push("Movie")
        }
        if (item.year) parts.push(String(item.year))
        if (item.managerLabel) parts.push(item.managerLabel)
        return parts.join("  /  ")
    }

    Component.onCompleted: {
        isLoading = true
        statusText = "Loading library..."
        statusIsError = false
        apiClient.fetchLibrary()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.appBg
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + Theme.space56
        clip: true

        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: root.filterActive || root.searchActive ? Theme.space28 : Theme.space40

            Item {
                id: hero
                Layout.fillWidth: true
                Layout.preferredHeight: root.searchActive || root.filterActive ? 164 : (libraryModel.count > 0 ? 388 : 210)
                visible: !root.searchActive

                Image {
                    anchors.fill: parent
                    source: !root.filterActive && root.heroItem && root.heroItem.backdrop ? root.heroItem.backdrop : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready && source !== ""
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.filterActive ? "#EF151515" : "#99151515" }
                        GradientStop { position: 0.46; color: root.filterActive ? "#F8151515" : "#B0151515" }
                        GradientStop { position: 1.0; color: Theme.appBg }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.min(parent.width * 0.72, 880)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#F4151515" }
                        GradientStop { position: 0.72; color: "#A6151515" }
                        GradientStop { position: 1.0; color: "#00151515" }
                    }
                    visible: !root.filterActive
                }

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: Theme.space32
                    anchors.rightMargin: Theme.space32
                    anchors.bottomMargin: root.filterActive ? Theme.space28 : Theme.space36
                    spacing: Theme.space12

                    Label {
                        text: root.filterActive ? root.sectionLabel : root.heroTitle()
                        color: Theme.textPrimary
                        font.family: Theme.fontDisplay
                        font.pixelSize: root.filterActive ? 34 : 44
                        font.weight: Font.DemiBold
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.maximumWidth: 760
                        Layout.fillWidth: true
                    }

                    Label {
                        text: root.filterActive ? (root.activeCount + " item" + (root.activeCount === 1 ? "" : "s")) : root.heroMeta()
                        color: Theme.accent
                        font.family: Theme.fontBody
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0
                        visible: text !== ""
                        Layout.fillWidth: true
                    }

                    Label {
                        text: root.filterActive ? "" : root.heroSubtitle()
                        color: Theme.textSecondary
                        font.family: Theme.fontBody
                        font.pixelSize: 15
                        lineHeight: 1.18
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                        visible: text !== ""
                        Layout.maximumWidth: 650
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: Theme.space12
                        visible: !root.filterActive && libraryModel.count > 0

                        ActionButton {
                            text: "Play"
                            variant: "primary"
                            iconSource: "qrc:/icons/play.svg"
                            onClicked: apiClient.startPlayback(root.heroItem.mediaId || root.heroItem.id || "", "")
                        }

                        ActionButton {
                            text: "Details"
                            variant: "secondary"
                            onClicked: root.openDetails(root.heroItem.mediaId || root.heroItem.id || "")
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 118
                visible: root.searchActive

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: Theme.space32
                    anchors.rightMargin: Theme.space32
                    anchors.bottomMargin: Theme.space18
                    spacing: Theme.space8

                    Label {
                        text: "Search Results"
                        color: Theme.textPrimary
                        font.family: Theme.fontDisplay
                        font.pixelSize: 34
                        font.weight: Font.DemiBold
                    }

                    Label {
                        text: root.activeCount + " match" + (root.activeCount === 1 ? "" : "es") + " for \"" + libraryModel.searchQuery + "\""
                        color: Theme.textSecondary
                        font.family: Theme.fontBody
                        font.pixelSize: 13
                    }
                }
            }

            EmptyState {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space32
                Layout.rightMargin: Theme.space32
                visible: !root.searchActive && !root.filterActive && libraryModel.count === 0 && !root.statusIsError && !root.isLoading
                title: "Welcome to Elixir"
                message: "Scan your library or use Find Media to start building your server."
                actionText: "Scan Library"
                onActionRequested: {
                    statusText = "Scanning..."
                    isLoading = true
                    statusIsError = false
                    apiClient.runScan(false)
                }
            }

            EmptyState {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space32
                Layout.rightMargin: Theme.space32
                visible: !root.searchActive && root.filterActive && root.activeCount === 0 && !root.statusIsError && !root.isLoading
                title: "Nothing here yet"
                message: "Scan your library or acquire media to populate " + root.sectionLabel.toLowerCase() + "."
            }

            EmptyState {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space32
                Layout.rightMargin: Theme.space32
                visible: root.searchActive && root.activeCount === 0
                title: "No matches found"
                message: "Try a different title, year, or library section."
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space32
                Layout.rightMargin: Theme.space32
                spacing: Theme.space16
                visible: !root.searchActive && root.filterActive && root.activeCount > 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space16

                    SectionHeader {
                        Layout.fillWidth: true
                        title: "Library"
                        subtitle: root.activeCount + " title" + (root.activeCount === 1 ? "" : "s")
                    }

                    Rectangle {
                        Layout.preferredHeight: 30
                        Layout.preferredWidth: sortLabel.implicitWidth + 22
                        radius: Theme.radius6
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: Qt.rgba(1, 1, 1, 0.08)

                        Label {
                            id: sortLabel
                            anchors.centerIn: parent
                            text: "Recently Added"
                            color: Theme.textSecondary
                            font.family: Theme.fontBody
                            font.pixelSize: 12
                        }
                    }
                }

                PosterGrid {
                    Layout.fillWidth: true
                    title: ""
                    model: root.sectionModel()
                    onCardClicked: root.openDetails(mediaId)
                }
            }

            PosterGrid {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space32
                Layout.rightMargin: Theme.space32
                title: ""
                visible: root.searchActive && root.activeCount > 0
                model: libraryModel.searchModel
                onCardClicked: root.openDetails(mediaId)
            }

            MediaShelf {
                Layout.fillWidth: true
                title: "Continue Watching"
                subtitle: "Pick up where you left off"
                cardType: "landscape"
                model: libraryModel.continueWatchingModel()
                visible: !root.searchActive && !root.filterActive && count > 0
                count: libraryModel.continueWatchingModel().count
                onCardClicked: root.openDetails(mediaId)
            }

            MediaShelf {
                Layout.fillWidth: true
                title: "Recently Added Movies"
                cardType: "portrait"
                model: libraryModel.moviesModel()
                visible: !root.searchActive && !root.filterActive && count > 0
                count: libraryModel.moviesModel().count
                onCardClicked: root.openDetails(mediaId)
            }

            MediaShelf {
                Layout.fillWidth: true
                title: "Recently Added TV Shows"
                cardType: "portrait"
                model: libraryModel.seriesModel()
                visible: !root.searchActive && !root.filterActive && count > 0
                count: libraryModel.seriesModel().count
                onCardClicked: root.openDetails(mediaId)
            }

            MediaShelf {
                Layout.fillWidth: true
                title: "Recently Added Anime"
                cardType: "portrait"
                model: libraryModel.animeModel()
                visible: !root.searchActive && !root.filterActive && count > 0
                count: libraryModel.animeModel().count
                onCardClicked: root.openDetails(mediaId)
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.leftMargin: Theme.space32
                Layout.rightMargin: Theme.space32
                radius: Theme.radius6
                color: root.statusIsError ? "#332A1515" : "transparent"
                border.color: root.statusIsError ? Theme.danger : "transparent"
                visible: statusText !== ""

                Label {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space16
                    anchors.rightMargin: Theme.space16
                    text: statusText
                    color: root.statusIsError ? Theme.danger : Theme.textMuted
                    font.family: Theme.fontBody
                    font.pixelSize: 12
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
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
            if (endpoint.indexOf("/api/v1/library") !== 0) {
                return
            }
            statusText = "Request failed: " + error
            statusIsError = true
            isLoading = false
        }
    }
}
