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
    color: Theme.backgroundDark
    property string authNotice: ""

    function goHome() {
        stackView.clear()
        if (apiClient.authToken !== "") {
            stackView.push(Qt.resolvedUrl("views/HomeView.qml"), { stackView: stackView })
        } else {
            stackView.push(Qt.resolvedUrl("views/ConnectServerView.qml"), { stackView: stackView, notice: root.authNotice })
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

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TopBar {
            Layout.fillWidth: true
            onHomeRequested: {
                root.goHome()
            }
            onSettingsRequested: {
                if (!stackView.currentItem || stackView.currentItem.objectName !== "settingsView") {
                    stackView.push(Qt.resolvedUrl("views/SettingsView.qml"), { stackView: stackView })
                }
            }
        }

        StackView {
            id: stackView
            Layout.fillWidth: true
            Layout.fillHeight: true
            initialItem: ConnectServerView { stackView: stackView; notice: root.authNotice }
        }
    }

    Connections {
        target: apiClient
        function onPlaybackStarted(info) {
            playerController.beginPlayback(info)
            if (!stackView.currentItem || stackView.currentItem.objectName !== "playerView") {
                stackView.push(Qt.resolvedUrl("views/PlayerView.qml"), { stackView: stackView })
            }
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
