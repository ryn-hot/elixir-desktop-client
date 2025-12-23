import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir.Mpv 1.0

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "playerView"
    property StackView stackView: null

    function formatTime(seconds) {
        var s = Math.floor(seconds || 0)
        var m = Math.floor(s / 60)
        var h = Math.floor(m / 60)
        s = s % 60
        m = m % 60
        if (h > 0) {
            return h + ":" + (m < 10 ? "0" + m : m) + ":" + (s < 10 ? "0" + s : s)
        }
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    MpvItem {
        id: mpv
        anchors.fill: parent
        focus: true
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 140
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#00000000" }
            GradientStop { position: 1.0; color: "#DD000000" }
        }
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Theme.spacingLarge
        spacing: Theme.spacingSmall

        Slider {
            id: timeSlider
            Layout.fillWidth: true
            from: 0
            to: playerController.duration
            value: playerController.position
            onPressedChanged: {
                if (!pressed) {
                    if (playerController.mode === "transcode") {
                        playerController.seek(value)
                    } else {
                        mpv.setPropertyAsync("time-pos", value)
                        playerController.seek(value)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingMedium

            IconButton {
                label: playerController.paused ? "Play" : "Pause"
                onClicked: {
                    var next = !playerController.paused
                    mpv.setPropertyAsync("pause", next)
                    playerController.setPaused(next)
                }
            }

            IconButton {
                label: "Stop"
                onClicked: {
                    playerController.endSession()
                    mpv.commandAsync(["stop"])
                    if (root.stackView) {
                        root.stackView.pop()
                    }
                }
            }

            Label {
                text: formatTime(playerController.position) + " / " + formatTime(playerController.duration)
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
            }

            Item { Layout.fillWidth: true }

            Label {
                text: playerController.mode !== "" ? playerController.mode : ""
                color: Theme.textMuted
                font.pixelSize: 11
                font.family: Theme.fontBody
            }
        }
    }

    Timer {
        interval: 500
        running: playerController.active
        repeat: true
        onTriggered: {
            var pos = mpv.getProperty("time-pos")
            if (pos !== undefined && pos !== null) {
                playerController.updateLocalPosition(pos)
            }
            var paused = mpv.getProperty("pause")
            if (paused !== undefined && paused !== null) {
                playerController.setPaused(paused)
            }
        }
    }

    function applyHeaders() {
        if (apiClient.authToken !== "") {
            mpv.setPropertyAsync("http-header-fields", ["Authorization: Bearer " + apiClient.authToken])
        } else {
            mpv.setPropertyAsync("http-header-fields", [])
        }
    }

    Component.onCompleted: {
        applyHeaders()
        if (playerController.streamUrl !== "") {
            mpv.commandAsync(["loadfile", playerController.streamUrl, "replace"])
            mpv.setPropertyAsync("pause", false)
        }
    }

    Connections {
        target: apiClient
        function onAuthTokenChanged() {
            applyHeaders()
        }
    }

    Connections {
        target: playerController
        function onStreamUrlChanged() {
            if (playerController.streamUrl === "") {
                return
            }
            mpv.commandAsync(["loadfile", playerController.streamUrl, "replace"])
            mpv.setPropertyAsync("pause", false)
        }
        function onActiveChanged() {
            if (!playerController.active) {
                mpv.commandAsync(["stop"])
            }
        }
    }
}
