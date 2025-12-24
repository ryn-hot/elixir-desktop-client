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
    property bool controlsVisible: true
    property bool scrubbing: timeSlider.pressed
    property string sessionMessage: playerController.sessionState === "ended"
        ? "Session ended"
        : (playerController.sessionState === "error"
           ? (playerController.sessionError !== "" ? playerController.sessionError : "Playback session error")
           : (playerController.sessionError !== "" ? playerController.sessionError : ""))

    ListModel { id: audioTracks }
    ListModel { id: subtitleTracks }

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

    function showControls() {
        controlsVisible = true
        hideTimer.restart()
    }

    function labelForTrack(track) {
        var labelParts = []
        if (track.lang) {
            labelParts.push(String(track.lang).toUpperCase())
        }
        if (track.title) {
            labelParts.push(track.title)
        }
        if (labelParts.length === 0) {
            labelParts.push("Track " + track.id)
        }
        return labelParts.join(" • ")
    }

    function clearTracks() {
        audioTracks.clear()
        subtitleTracks.clear()
    }

    function refreshTracks() {
        var trackList = mpv.getProperty("track-list")
        if (!trackList || trackList.length === undefined) {
            return
        }

        audioTracks.clear()
        subtitleTracks.clear()
        audioTracks.append({ label: "Auto", id: "auto" })
        subtitleTracks.append({ label: "Off", id: "no" })

        var audioIndex = 0
        var subtitleIndex = 0

        for (var i = 0; i < trackList.length; i++) {
            var track = trackList[i]
            if (!track || !track.type) {
                continue
            }
            if (track.type === "audio") {
                audioTracks.append({ label: labelForTrack(track), id: track.id })
                if (track.selected) {
                    audioIndex = audioTracks.count - 1
                }
            }
            if (track.type === "sub") {
                subtitleTracks.append({ label: labelForTrack(track), id: track.id })
                if (track.selected) {
                    subtitleIndex = subtitleTracks.count - 1
                }
            }
        }

        audioCombo.currentIndex = Math.min(audioIndex, audioTracks.count - 1)
        subtitleCombo.currentIndex = Math.min(subtitleIndex, subtitleTracks.count - 1)
    }

    function applyHeaders() {
        if (apiClient.authToken !== "") {
            mpv.setPropertyAsync("http-header-fields", ["Authorization: Bearer " + apiClient.authToken])
        } else {
            mpv.setPropertyAsync("http-header-fields", [])
        }
    }

    MpvItem {
        id: mpv
        anchors.fill: parent
        focus: true
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        propagateComposedEvents: true
        z: 20
        onPositionChanged: root.showControls()
        onPressed: {
            root.showControls()
            mouse.accepted = false
        }
        onClicked: {
            root.showControls()
            mouse.accepted = false
        }
    }

    Timer {
        id: hideTimer
        interval: 2400
        onTriggered: {
            if (!playerController.paused && !root.scrubbing) {
                controlsVisible = false
            }
        }
    }

    Item {
        id: overlay
        anchors.fill: parent
        opacity: controlsVisible ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 80
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#CC000000" }
                GradientStop { position: 1.0; color: "#00000000" }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 180
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 1.0; color: "#DD000000" }
            }
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingLarge
            spacing: Theme.spacingMedium

            IconButton {
                label: "Back"
                onClicked: {
                    playerController.endSession()
                    mpv.commandAsync(["stop"])
                    if (root.stackView) {
                        root.stackView.pop()
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    text: "Now Playing"
                    color: Theme.textPrimary
                    font.pixelSize: 14
                    font.family: Theme.fontDisplay
                }
                Label {
                    text: playerController.mode !== "" ? ("Mode: " + playerController.mode) : ""
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                }
            }

            Rectangle {
                radius: Theme.radiusSmall
                color: Theme.backgroundCard
                border.color: Theme.border
                visible: playerController.sessionState !== ""

                Label {
                    anchors.centerIn: parent
                    text: playerController.sessionState
                    color: Theme.textSecondary
                    font.pixelSize: 10
                    font.family: Theme.fontBody
                    padding: 6
                }
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
                    text: formatTime(playerController.position)
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                Label {
                    text: "/ " + formatTime(playerController.duration)
                    color: Theme.textMuted
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                Item { Layout.fillWidth: true }

                ColumnLayout {
                    spacing: 4
                    visible: audioTracks.count > 1

                    Label {
                        text: "Audio"
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.family: Theme.fontBody
                    }

                    ComboBox {
                        id: audioCombo
                        model: audioTracks
                        textRole: "label"
                        onActivated: {
                            var entry = audioTracks.get(index)
                            if (entry.id === "auto") {
                                mpv.setPropertyAsync("aid", "auto")
                            } else {
                                mpv.setPropertyAsync("aid", entry.id)
                            }
                        }
                    }
                }

                ColumnLayout {
                    spacing: 4
                    visible: subtitleTracks.count > 1

                    Label {
                        text: "Subtitles"
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.family: Theme.fontBody
                    }

                    ComboBox {
                        id: subtitleCombo
                        model: subtitleTracks
                        textRole: "label"
                        onActivated: {
                            var entry = subtitleTracks.get(index)
                            if (entry.id === "no") {
                                mpv.setPropertyAsync("sid", "no")
                            } else {
                                mpv.setPropertyAsync("sid", entry.id)
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.55
        radius: Theme.radiusLarge
        color: Theme.backgroundCard
        border.color: Theme.border
        visible: sessionMessage !== ""

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingLarge
            spacing: Theme.spacingSmall

            Label {
                text: "Playback notice"
                color: Theme.textPrimary
                font.pixelSize: 18
                font.family: Theme.fontDisplay
            }

            Label {
                text: sessionMessage
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
                wrapMode: Text.Wrap
            }

            RowLayout {
                spacing: Theme.spacingMedium
                Button {
                    text: "Close"
                    onClicked: {
                        playerController.endSession()
                        mpv.commandAsync(["stop"])
                        if (root.stackView) {
                            root.stackView.pop()
                        }
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

    Timer {
        interval: 4000
        running: playerController.active
        repeat: true
        onTriggered: {
            if (playerController.sessionId !== "") {
                apiClient.pollSession(playerController.sessionId)
            }
        }
    }

    Timer {
        id: trackRefreshTimer
        interval: 900
        repeat: false
        onTriggered: refreshTracks()
    }

    Timer {
        interval: 6000
        running: playerController.active
        repeat: true
        onTriggered: refreshTracks()
    }

    Component.onCompleted: {
        applyHeaders()
        if (playerController.streamUrl !== "") {
            mpv.commandAsync(["loadfile", playerController.streamUrl, "replace"])
            mpv.setPropertyAsync("pause", false)
            trackRefreshTimer.restart()
        }
        showControls()
    }

    Connections {
        target: apiClient
        function onAuthTokenChanged() {
            applyHeaders()
        }
        function onSessionPolled(info) {
            playerController.applySessionPoll(info)
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
            trackRefreshTimer.restart()
            showControls()
        }
        function onActiveChanged() {
            if (!playerController.active) {
                mpv.commandAsync(["stop"])
                clearTracks()
            }
        }
        function onPausedChanged() {
            if (playerController.paused) {
                controlsVisible = true
                hideTimer.stop()
            } else {
                showControls()
            }
        }
        function onSessionStateChanged() {
            if (playerController.sessionState === "ended" || playerController.sessionState === "error") {
                mpv.commandAsync(["stop"])
            }
        }
    }
}
