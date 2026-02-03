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
                if (stackView.currentItem.objectName === "extensionsView") return "extensions"
                // Add logic for movies/series/anime views when they exist as separate pages
                return "home"
            }
            
            onHomeRequested: root.goHome()
            onSettingsRequested: {
                if (!stackView.currentItem || stackView.currentItem.objectName !== "settingsView") {
                    stackView.push(Qt.resolvedUrl("views/SettingsView.qml"), { stackView: stackView })
                }
            }
            onExtensionsRequested: {
                if (!stackView.currentItem || stackView.currentItem.objectName !== "extensionsView") {
                    stackView.push(Qt.resolvedUrl("views/ExtensionsView.qml"), { stackView: stackView })
                }
            }
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
                // Connect search signal to current view if applicable
                onSearchChanged: {
                    if (stackView.currentItem && stackView.currentItem.objectName === "homeView") {
                        stackView.currentItem.setSearchQuery(text)
                    }
                }
            }

            StackView {
                id: stackView
                Layout.fillWidth: true
                Layout.fillHeight: true
                initialItem: ConnectServerView { stackView: stackView; notice: root.authNotice }
                
                // Add background for stackview area
                background: Rectangle {
                    color: Theme.backgroundDark
                }
            }
        }
    }

    Connections {
        target: apiClient
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
            root.goHome()
        }
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
