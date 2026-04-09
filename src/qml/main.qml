import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "components"
import "views"
import Elixir 1.0

ApplicationWindow {
    id: root
    width: 1280
    height: 720
    visible: true
    title: "Elixir"
    color: Theme.bgMain // Spec: #282a2d
    property string authNotice: ""
    property int acquisitionUnreadCount: 0
    property var seenAcquisitionIds: ({})

    Component.onCompleted: {
        if (apiClient.authToken !== "") {
            apiClient.fetchMediaAcquisition()
        }
    }

    function showLibrarySection(section) {
        stackView.clear()
        if (apiClient.authToken !== "") {
            stackView.push(Qt.resolvedUrl("views/HomeView.qml"), { stackView: stackView, sectionFilter: section })
        } else {
            stackView.push(Qt.resolvedUrl("views/ConnectServerView.qml"), { stackView: stackView, notice: root.authNotice })
        }
    }

    function goHome() {
        showLibrarySection("all")
    }

    function acquisitionItemId(item) {
        if (!item) {
            return ""
        }
        var directId = String(item.intentId || item.id || "")
        if (directId !== "") {
            return directId
        }
        return String(item.title || "") + "|" + String(item.stage || "")
    }

    function markCurrentAcquisitionSeen() {
        var items = apiClient.mediaAcquisitionItems || []
        var seen = seenAcquisitionIds || ({})
        for (var i = 0; i < items.length; ++i) {
            var id = acquisitionItemId(items[i])
            if (id !== "") {
                seen[id] = true
            }
        }
        seenAcquisitionIds = seen
        acquisitionUnreadCount = 0
    }

    function refreshAcquisitionUnread() {
        if (stackView.currentItem && stackView.currentItem.objectName === "acquisitionView") {
            markCurrentAcquisitionSeen()
            return
        }
        var items = apiClient.mediaAcquisitionItems || []
        var seen = seenAcquisitionIds || ({})
        var unread = 0
        for (var i = 0; i < items.length; ++i) {
            var id = acquisitionItemId(items[i])
            if (id !== "" && !seen[id]) {
                unread += 1
            }
        }
        acquisitionUnreadCount = unread
    }

    function openAcquisition() {
        if (!stackView.currentItem) {
            stackView.push(Qt.resolvedUrl("views/AcquisitionView.qml"), { stackView: stackView })
        } else if (stackView.currentItem.objectName !== "acquisitionView") {
            stackView.push(Qt.resolvedUrl("views/AcquisitionView.qml"), { stackView: stackView })
        }
        markCurrentAcquisitionSeen()
        if (apiClient.authToken !== "") {
            apiClient.fetchMediaAcquisition()
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0B0E14" }
            GradientStop { position: 0.6; color: "#080A10" }
            GradientStop { position: 1.0; color: "#050509" }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height * 0.35
        opacity: 0.45
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1A2436" }
            GradientStop { position: 1.0; color: "#050509" }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Sidebar {
            id: sidebar
            Layout.fillHeight: true
            Layout.preferredWidth: 240
            visible: stackView.currentItem && stackView.currentItem.objectName !== "connectView"
            currentView: {
                if (!stackView.currentItem) return "home"
                if (stackView.currentItem.objectName === "homeView") {
                    if (stackView.currentItem.sectionFilter === "movies") return "movies"
                    if (stackView.currentItem.sectionFilter === "series") return "series"
                    if (stackView.currentItem.sectionFilter === "anime") return "anime"
                    return "home"
                }
                if (stackView.currentItem.objectName === "settingsView") return "settings"
                if (stackView.currentItem.objectName === "findMediaView") return "find_media"
                if (stackView.currentItem.objectName === "acquisitionView") return "acquisition"
                if (stackView.currentItem.objectName === "extensionsView" ||
                        stackView.currentItem.objectName === "advancedExtensionsView" ||
                        stackView.currentItem.objectName === "extensionControlView") return "extensions"
                // Add logic for movies/series/anime views when they exist as separate pages
                return "home"
            }
            acquisitionBadgeCount: root.acquisitionUnreadCount
            
            onHomeRequested: root.goHome()
            onSettingsRequested: {
                if (!stackView.currentItem || stackView.currentItem.objectName !== "settingsView") {
                    stackView.push(Qt.resolvedUrl("views/SettingsView.qml"), { stackView: stackView })
                }
            }
            onExtensionsRequested: {
                if (!stackView.currentItem) {
                    stackView.push(Qt.resolvedUrl("views/ExtensionsRouteView.qml"), { stackView: stackView })
                } else if (stackView.currentItem.objectName === "advancedExtensionsView" ||
                           stackView.currentItem.objectName === "extensionControlView") {
                    stackView.replace(Qt.resolvedUrl("views/ExtensionsRouteView.qml"), { stackView: stackView })
                } else if (stackView.currentItem.objectName !== "extensionsView") {
                    stackView.push(Qt.resolvedUrl("views/ExtensionsRouteView.qml"), { stackView: stackView })
                }
            }
            onFindMediaRequested: {
                if (!stackView.currentItem || stackView.currentItem.objectName !== "findMediaView") {
                    stackView.push(Qt.resolvedUrl("views/FindMediaView.qml"), { stackView: stackView })
                }
            }
            onAcquisitionRequested: root.openAcquisition()
            onMoviesRequested: root.showLibrarySection("movies")
            onSeriesRequested: root.showLibrarySection("series")
            onAnimeRequested: root.showLibrarySection("anime")
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            TopBar {
                Layout.fillWidth: true
                visible: stackView.currentItem && stackView.currentItem.objectName !== "connectView"
                searchVisible: stackView.currentItem && stackView.currentItem.objectName === "homeView"
                // Global top bar search is reserved for library views.
                onSearchChanged: {
                    if (stackView.currentItem &&
                            stackView.currentItem.objectName === "homeView" &&
                            typeof stackView.currentItem.setSearchQuery === "function") {
                        stackView.currentItem.setSearchQuery(text)
                    }
                }
            }

            StackView {
                id: stackView
                Layout.fillWidth: true
                Layout.fillHeight: true
                initialItem: ConnectServerView { stackView: stackView; notice: root.authNotice }
                pushEnter: Transition {
                    NumberAnimation { property: "x"; from: stackView.width * 0.03; to: 0; duration: 150; easing.type: Easing.OutCubic }
                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 130 }
                }
                pushExit: Transition {
                    NumberAnimation { property: "opacity"; from: 1.0; to: 0.97; duration: 90 }
                }
                popEnter: Transition {
                    NumberAnimation { property: "opacity"; from: 0.97; to: 1.0; duration: 110 }
                }
                popExit: Transition {
                    NumberAnimation { property: "x"; from: 0; to: stackView.width * 0.02; duration: 120; easing.type: Easing.InCubic }
                    NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 120 }
                }
                
                // Add background for stackview area
                background: Rectangle {
                    color: Theme.backgroundDark
                }
            }
        }
    }

    Connections {
        target: apiClient
        function onAuthTokenChanged() {
            if (apiClient.authToken !== "") {
                apiClient.fetchMediaAcquisition()
            } else {
                root.seenAcquisitionIds = ({})
                root.acquisitionUnreadCount = 0
            }
        }
        function onMediaAcquisitionChanged() {
            root.refreshAcquisitionUnread()
        }
        function onPlaybackStarted(info) {
            Qt.callLater(function() {
                console.log("playbackStarted", JSON.stringify(info))
                playerController.beginPlayback(info)
                if (!stackView.currentItem || stackView.currentItem.objectName !== "playerView") {
                    stackView.push(Qt.resolvedUrl("views/PlayerView.qml"), { stackView: stackView })
                }
            })
        }
        function onAuthExpired(message) {
            root.authNotice = message !== "" ? message : "Session expired. Please sign in again."
            playerController.endSession()
            sessionManager.clearAuth()
            root.seenAcquisitionIds = ({})
            root.acquisitionUnreadCount = 0
            root.goHome()
        }
    }

    Timer {
        id: acquisitionPoll
        interval: 4000
        repeat: true
        running: apiClient.authToken !== "" && stackView.currentItem && stackView.currentItem.objectName !== "connectView"
        onTriggered: apiClient.fetchMediaAcquisition()
    }

    Connections {
        target: controlPlaneClient
        function onAuthExpired(message) {
            root.authNotice = message !== "" ? message : "Control plane session expired."
            sessionManager.clearControlPlaneAuth()
            root.goHome()
        }
    }
}
