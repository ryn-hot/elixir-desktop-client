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
    color: Theme.appBg
    property string authNotice: ""
    property int acquisitionUnreadCount: 0
    property var seenAcquisitionIds: ({})
    readonly property var navigationStack: stackView

    Component.onCompleted: {
        if (apiClient.hasRefreshToken) {
            apiClient.restoreSession()
        } else if (apiClient.authToken !== "") {
            apiClient.fetchMediaAcquisition()
            apiClient.fetchAcquisitionReleases("review_required", "", 50)
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

    function openLive() {
        if (!stackView.currentItem || stackView.currentItem.objectName !== "liveView") {
            stackView.push(Qt.resolvedUrl("views/LiveView.qml"), {
                stackView: stackView,
                liveModel: liveCatalogModel,
                client: apiClient,
                playerController: livePlayerController,
                serverBaseUrl: apiClient.baseUrl
            })
        }
    }

    function maintainAuth() {
        if (apiClient.hasRefreshToken
                && !apiClient.refreshInFlight
                && (apiClient.authToken === "" || apiClient.accessTokenNearExpiry(60))) {
            apiClient.refreshAuth()
        }
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
        if (stackView.currentItem &&
                (stackView.currentItem.objectName === "acquisitionView" ||
                 stackView.currentItem.objectName === "acquisitionReviewView")) {
            markCurrentAcquisitionSeen()
            return
        }
        var items = apiClient.mediaAcquisitionItems || []
        var reviewRows = apiClient.acquisitionReviewReleases || []
        var seen = seenAcquisitionIds || ({})
        var unread = reviewRows.length
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
            apiClient.fetchAcquisitionReleases("review_required", "", 50)
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#181818" }
            GradientStop { position: 0.62; color: "#121315" }
            GradientStop { position: 1.0; color: "#090A0C" }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: parent.height * 0.35
        opacity: 0.45
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#2D271C" }
            GradientStop { position: 1.0; color: "#090A0C" }
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        Sidebar {
            id: sidebar
            Layout.fillHeight: true
            Layout.preferredWidth: collapsed ? collapsedWidth : Theme.sidebarWidth
            visible: stackView.currentItem
                     && stackView.currentItem.objectName !== "connectView"
                     && stackView.currentItem.objectName !== "livePlayerView"
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
                if (stackView.currentItem.objectName === "liveView" ||
                        stackView.currentItem.objectName === "liveDetailsView" ||
                        stackView.currentItem.objectName === "livePlayerView") return "live"
                if (stackView.currentItem.objectName === "acquisitionView" ||
                        stackView.currentItem.objectName === "acquisitionReviewView") return "acquisition"
                if (stackView.currentItem.objectName === "extensionsView" ||
                        stackView.currentItem.objectName === "advancedExtensionsView" ||
                        stackView.currentItem.objectName === "extensionControlView") return "extensions"
                return "home"
            }
            acquisitionBadgeCount: root.acquisitionUnreadCount
            
            onHomeRequested: root.goHome()
            onLiveRequested: root.openLive()
            onSettingsRequested: {
                if (!stackView.currentItem || stackView.currentItem.objectName !== "settingsView") {
                    stackView.push(Qt.resolvedUrl("views/SettingsView.qml"), { stackView: stackView })
                }
            }
            onExtensionsRequested: {
                if (!stackView.currentItem) {
                    stackView.push(Qt.resolvedUrl("views/ExtensionsRouteView.qml"), {
                        stackView: stackView,
                        openLiveRequested: root.openLive
                    })
                } else if (stackView.currentItem.objectName === "advancedExtensionsView" ||
                           stackView.currentItem.objectName === "extensionControlView") {
                    stackView.replace(Qt.resolvedUrl("views/ExtensionsRouteView.qml"), {
                        stackView: stackView,
                        openLiveRequested: root.openLive
                    })
                } else if (stackView.currentItem.objectName !== "extensionsView") {
                    stackView.push(Qt.resolvedUrl("views/ExtensionsRouteView.qml"), {
                        stackView: stackView,
                        openLiveRequested: root.openLive
                    })
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
                visible: stackView.currentItem
                         && stackView.currentItem.objectName !== "connectView"
                         && stackView.currentItem.objectName !== "livePlayerView"
                searchVisible: stackView.currentItem && stackView.currentItem.objectName === "homeView"
                onActivityRequested: root.openAcquisition()
                onSettingsRequested: {
                    if (!stackView.currentItem || stackView.currentItem.objectName !== "settingsView") {
                        stackView.push(Qt.resolvedUrl("views/SettingsView.qml"), { stackView: stackView })
                    }
                }
                onSearchChanged: function(text) {
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
                initialItem: apiClient.authToken !== "" ? homeInitial : connectInitial
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
                
                background: Rectangle {
                    color: Theme.appBg
                }
            }
        }
    }

    Component {
        id: connectInitial
        ConnectServerView {
            stackView: root.navigationStack
            notice: root.authNotice
        }
    }

    Component {
        id: homeInitial
        HomeView {
            stackView: root.navigationStack
            sectionFilter: "all"
        }
    }

    Connections {
        target: apiClient
        function onAuthTokenChanged() {
            if (apiClient.authToken !== "") {
                apiClient.fetchMediaAcquisition()
                apiClient.fetchAcquisitionReleases("review_required", "", 50)
            } else {
                root.seenAcquisitionIds = ({})
                root.acquisitionUnreadCount = 0
            }
        }
        function onMediaAcquisitionChanged() {
            root.refreshAcquisitionUnread()
        }
        function onAcquisitionReviewChanged() {
            root.refreshAcquisitionUnread()
        }
        function onPlaybackStarted(info) {
            Qt.callLater(function() {
                console.log("playbackStarted", "session=" + String(info.session_id || ""), "mode=" + String(info.mode || ""))
                playerController.beginPlayback(info)
                if (!stackView.currentItem || stackView.currentItem.objectName !== "playerView") {
                    stackView.push(Qt.resolvedUrl("views/PlayerView.qml"), { stackView: stackView })
                }
            })
        }
        function onPlaybackFailed(error) {
            Qt.callLater(function() {
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
        function onSessionRestored() {
            root.authNotice = ""
            apiClient.fetchMediaAcquisition()
            apiClient.fetchAcquisitionReleases("review_required", "", 50)
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

    Timer {
        id: acquisitionReviewPoll
        interval: 15000
        repeat: true
        running: apiClient.authToken !== "" && stackView.currentItem && stackView.currentItem.objectName !== "connectView"
        onTriggered: apiClient.fetchAcquisitionReleases("review_required", "", 50)
    }

    Timer {
        id: authExpiryPoll
        interval: 30000
        repeat: true
        running: apiClient.hasRefreshToken
        onTriggered: root.maintainAuth()
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
