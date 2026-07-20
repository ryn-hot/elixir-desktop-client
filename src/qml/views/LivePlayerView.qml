import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "livePlayerView"
    required property var playerController
    required property string providerId
    required property string itemKey
    required property string streamOptionKey
    property string eventTitle: "Live event"
    property var expectedEndUtc: null
    property StackView stackView: null
    property var liveModel: null
    property Component playbackSurfaceComponent: null

    property bool componentReady: false
    property bool playbackStarted: false
    property bool routeClosed: false
    property bool controlsVisible: true
    property string preferenceSourceKey: ""
    property bool audioPreferenceApplied: false
    property bool subtitlePreferenceApplied: false

    readonly property var playbackSurface: surfaceLoader.item
    readonly property bool activeSession: ["creating_session", "loading", "playing",
                                           "buffering", "paused", "reconnecting",
                                           "refreshing", "switching_source"].indexOf(
                                              String(playerController.state || "")) >= 0
    readonly property bool recovering: Boolean(playerController.recovering)
    readonly property bool paused: String(playerController.state || "") === "paused"
    readonly property bool terminal: ["ended", "unavailable", "failed"].indexOf(
                                         String(playerController.state || "")) >= 0
    readonly property bool reloadEventRecommended: ["LIVE_STREAM_UNAVAILABLE",
                                                     "LIVE_STREAM_EXPIRED",
                                                     "LIVE_PROTOCOL_UNSUPPORTED"].indexOf(
                                                        String(playerController.errorCode || "")) >= 0

    Rectangle {
        anchors.fill: parent
        color: "#050506"
    }

    function ensureStarted() {
        if (playbackStarted || !componentReady || !playbackSurface || !playerController)
            return
        if (!playerController.attachPlayer(playbackSurface)) {
            return
        }
        playbackStarted = true
        playerController.start(providerId, itemKey, streamOptionKey,
                               eventTitle, expectedEndUtc)
    }

    function readProperty(name, fallback) {
        if (!playbackSurface || typeof playbackSurface.getProperty !== "function")
            return fallback
        var value = playbackSurface.getProperty(name)
        return value === undefined || value === null ? fallback : value
    }

    function finiteNumber(value) {
        var number = Number(value)
        return isFinite(number) ? number : null
    }

    function trackLabel(track) {
        var parts = []
        var language = track.lang || (track.metadata ? track.metadata.language : "")
        var title = track.title || (track.metadata
                                    ? (track.metadata.title || track.metadata.comment) : "")
        if (language) parts.push(String(language).toUpperCase())
        if (title) parts.push(String(title))
        return parts.length > 0 ? parts.join(" / ") : "Track " + String(track.id)
    }

    function tracksOfType(trackList, type) {
        var result = []
        if (!trackList || trackList.length === undefined) return result
        for (var i = 0; i < trackList.length; ++i) {
            var track = trackList[i]
            if (!track || String(track.type || "") !== type) continue
            result.push({
                "id": String(track.id),
                "label": trackLabel(track),
                "language": String(track.lang || ""),
                "title": String(track.title || ""),
                "selected": track.selected === true
            })
        }
        return result
    }

    function samplePlayback() {
        if (!playbackSurface || !playerController) return
        var position = finiteNumber(readProperty("time-pos", null))
        var duration = finiteNumber(readProperty("duration", null))
        var cacheTime = finiteNumber(readProperty("demuxer-cache-time", null))
        var distance = 0
        if (position !== null && cacheTime !== null && cacheTime >= position) {
            distance = cacheTime - position
        } else if (position !== null && duration !== null && duration >= position) {
            distance = duration - position
        }
        var tracks = readProperty("track-list", [])
        var audio = tracksOfType(tracks, "audio")
        var subtitles = tracksOfType(tracks, "sub")
        playerController.observeMpv({
            "coreIdle": Boolean(readProperty("core-idle", false)),
            "pausedForCache": Boolean(readProperty("paused-for-cache", false)),
            "paused": Boolean(readProperty("pause", false)),
            "eofReached": Boolean(readProperty("eof-reached", false)),
            "error": String(readProperty("error", "") || ""),
            "distanceFromLiveEdgeSeconds": Math.max(0, distance),
            "audioTracks": audio,
            "subtitleTracks": subtitles,
            "audioTrackId": String(readProperty("aid", "") || ""),
            "subtitleTrackId": String(readProperty("sid", "") || "")
        })
        applyTrackPreferences(audio, subtitles)
    }

    function matchingTrack(preference, tracks) {
        if (!preference || !preference.trackId || !tracks) return null
        var language = String(preference.language || "").toLowerCase().replace(/_/g, "-")
        var title = String(preference.title || "").toLowerCase()
        var semanticMatches = []
        for (var i = 0; i < tracks.length; ++i) {
            var track = tracks[i]
            var trackLanguage = String(track.language || "").toLowerCase().replace(/_/g, "-")
            var trackTitle = String(track.title || "").toLowerCase()
            if (language && trackLanguage !== language) continue
            if (title && trackTitle !== title) continue
            if (language || title) semanticMatches.push(track)
        }
        if (semanticMatches.length === 1) return semanticMatches[0]
        if (semanticMatches.length > 1) {
            for (var matchIndex = 0; matchIndex < semanticMatches.length; ++matchIndex) {
                if (String(semanticMatches[matchIndex].id) === String(preference.trackId))
                    return semanticMatches[matchIndex]
            }
            return null
        }
        if (language || title) return null
        for (var j = 0; j < tracks.length; ++j) {
            if (String(tracks[j].id) === String(preference.trackId)) return tracks[j]
        }
        return null
    }

    function applyTrackPreferences(audio, subtitles) {
        var sourceKey = String(playerController.selectedSourceKey || "")
        if (preferenceSourceKey !== sourceKey) {
            preferenceSourceKey = sourceKey
            audioPreferenceApplied = false
            subtitlePreferenceApplied = false
        }
        if (!audioPreferenceApplied && audio.length > 0) {
            var preferredAudio = matchingTrack(playerController.preferredAudioTrack, audio)
            audioPreferenceApplied = true
            if (preferredAudio) selectTrack("audio", "aid", preferredAudio.id)
        }
        if (!subtitlePreferenceApplied) {
            var preference = playerController.preferredSubtitleTrack
            if (preference && String(preference.trackId) === "no") {
                subtitlePreferenceApplied = true
                selectTrack("subtitle", "sid", "no")
            } else if (subtitles.length > 0) {
                var preferredSubtitle = matchingTrack(preference, subtitles)
                subtitlePreferenceApplied = true
                if (preferredSubtitle)
                    selectTrack("subtitle", "sid", preferredSubtitle.id)
            }
        }
    }

    function setPaused(value) {
        if (!playerController.seekable || !playbackSurface
                || typeof playbackSurface.setPropertyAsync !== "function") return
        playbackSurface.setPropertyAsync("pause", Boolean(value))
        controlsHideTimer.restart()
    }

    function goLive() {
        if (!playerController.seekable || !playbackSurface
                || typeof playbackSurface.commandAsync !== "function") return
        playbackSurface.commandAsync(["seek", 100, "absolute-percent", "exact"])
        playbackSurface.setPropertyAsync("pause", false)
        controlsHideTimer.restart()
    }

    function seekWithinWindow(seconds) {
        if (!playerController.seekable || playerController.windowSeconds <= 0
                || !playbackSurface || typeof playbackSurface.commandAsync !== "function") return
        var delta = Number(playerController.seekDeltaForWindowPosition(seconds))
        if (!isFinite(delta)) return
        playbackSurface.commandAsync(["seek", delta, "relative", "exact"])
    }

    function selectTrack(type, propertyName, trackId) {
        if (!playbackSurface || typeof playbackSurface.setPropertyAsync !== "function") return
        playbackSurface.setPropertyAsync(propertyName, String(trackId))
        playerController.selectTrack(type, String(trackId))
    }

    function sourceIndex(sources) {
        var selected = String(playerController.selectedSourceKey || "")
        for (var i = 0; i < sources.length; ++i) {
            if (String(sources[i].sourceKey) === selected) return i
        }
        return -1
    }

    function exitRoute(stopSession) {
        if (routeClosed) return
        routeClosed = true
        if (stopSession) playerController.stop()
        else playerController.routeExited()
        if (stackView) stackView.pop()
    }

    function reloadEvent() {
        if (liveModel && typeof liveModel.loadItem === "function") {
            liveModel.loadItem(providerId, itemKey)
        }
        exitRoute(false)
    }

    function toggleFullscreen() {
        var window = root.Window.window
        if (!window) return
        window.visibility = window.visibility === Window.FullScreen
                            ? Window.Windowed : Window.FullScreen
    }

    Component.onCompleted: {
        componentReady = true
        ensureStarted()
    }
    Component.onDestruction: {
        if (!routeClosed && playerController) playerController.routeExited()
    }

    Loader {
        id: surfaceLoader
        objectName: "livePlaybackSurfaceLoader"
        anchors.fill: parent
        sourceComponent: root.playbackSurfaceComponent
        source: root.playbackSurfaceComponent ? "" : Qt.resolvedUrl("LiveMpvSurface.qml")
        onLoaded: root.ensureStarted()
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: {
            root.controlsVisible = true
            controlsHideTimer.restart()
        }
    }

    Rectangle {
        id: topOverlay
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 92
        color: "#B8000000"
        visible: root.controlsVisible || root.terminal

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.width < 520 ? Theme.space8 : Theme.space20
            anchors.rightMargin: root.width < 520 ? Theme.space8 : Theme.space20
            spacing: Theme.space12

            Button {
                id: backButton
                objectName: "livePlayerBack"
                Layout.preferredWidth: 40
                Layout.preferredHeight: 36
                text: "\u2190"
                Accessible.name: "Back to Live event"
                ToolTip.text: Accessible.name
                ToolTip.visible: hovered
                onClicked: root.exitRoute(false)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    Layout.fillWidth: true
                    text: root.eventTitle
                    textFormat: Text.PlainText
                    color: Theme.textPrimary
                    font.family: Theme.fontDisplay
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: [playerController.selectedSourceLabel,
                           playerController.selectedSourceQuality].filter(Boolean).join(" / ")
                    textFormat: Text.PlainText
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }

            Rectangle {
                objectName: "livePlayerStatus"
                Layout.preferredWidth: statusLabel.implicitWidth + Theme.space16
                Layout.preferredHeight: 28
                radius: Theme.radius4
                color: playerController.distanceFromLiveEdge > 5
                       ? Theme.accentInfoSoft : "#CCB3261E"
                border.color: playerController.distanceFromLiveEdge > 5
                              ? Theme.accentInfo : "#FFE2E2"
                Label {
                    id: statusLabel
                    anchors.centerIn: parent
                    text: root.recovering
                          ? String(playerController.statusText || "RECOVERING").toUpperCase()
                          : (playerController.distanceFromLiveEdge > 5
                             ? Math.round(playerController.distanceFromLiveEdge) + "s behind"
                             : String(playerController.statusText || "LIVE").toUpperCase())
                    color: Theme.textPrimary
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
            }
        }
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.space32, 420)
        height: stateColumn.implicitHeight + Theme.space32
        radius: Theme.radius8
        color: Theme.overlayStrong
        border.color: Theme.borderSubtle
        visible: ["creating_session", "loading", "buffering", "reconnecting",
                  "refreshing", "switching_source", "ended", "unavailable",
                  "failed"].indexOf(
                     String(playerController.state || "")) >= 0

        ColumnLayout {
            id: stateColumn
            anchors.fill: parent
            anchors.margins: Theme.space16
            spacing: Theme.space12

            BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: ["creating_session", "loading", "buffering", "reconnecting",
                          "refreshing", "switching_source"].indexOf(
                             String(playerController.state || "")) >= 0
                visible: running
                Accessible.name: String(playerController.statusText || "Starting Live stream")
            }
            Label {
                objectName: "livePlayerStateText"
                Layout.fillWidth: true
                text: {
                    if (playerController.state === "ended") return "Event ended"
                    if (playerController.state === "unavailable") return "Stream unavailable"
                    if (playerController.state === "failed") return "Playback failed"
                    return String(playerController.statusText || "Starting")
                }
                color: Theme.textPrimary
                font.pixelSize: 15
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            Label {
                objectName: "livePlayerFailureMessage"
                Layout.fillWidth: true
                text: String(playerController.failureMessage || "")
                textFormat: Text.PlainText
                visible: root.terminal && text !== ""
                color: Theme.textSecondary
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                Accessible.name: text
            }
            Label {
                objectName: "liveReconnectCountdown"
                Layout.fillWidth: true
                text: playerController.state === "reconnecting"
                      ? (playerController.reconnectSecondsRemaining > 0
                         ? "Retrying in " + playerController.reconnectSecondsRemaining + "s"
                         : "Retrying now") : ""
                visible: text !== ""
                color: Theme.textSecondary
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.space8
                visible: root.recovering
                ActionButton {
                    objectName: "liveRecoveryRetryNow"
                    text: "Retry now"
                    variant: "primary"
                    visible: playerController.state === "reconnecting"
                    onClicked: playerController.retryRecoveryNow()
                }
                ActionButton {
                    objectName: "liveRecoveryCancel"
                    text: "Cancel"
                    onClicked: playerController.cancelRecovery()
                }
            }
            ActionButton {
                objectName: "livePlayerRetry"
                Layout.alignment: Qt.AlignHCenter
                text: "Retry"
                variant: "primary"
                visible: root.terminal && Boolean(playerController.failureRetryable)
                onClicked: playerController.start(root.providerId, root.itemKey,
                                                   root.streamOptionKey, root.eventTitle,
                                                   root.expectedEndUtc)
            }
            ActionButton {
                objectName: "livePlayerReloadEvent"
                Layout.alignment: Qt.AlignHCenter
                text: "Reload event"
                variant: "primary"
                visible: root.terminal && root.reloadEventRecommended
                onClicked: root.reloadEvent()
            }
        }
    }

    Rectangle {
        id: controls
        objectName: "livePlayerControls"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.playerController.seekable && root.playerController.windowSeconds > 0 ? 132 : 82
        color: "#D9000000"
        visible: root.controlsVisible && !root.terminal && !root.recovering

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: root.width < 520 ? Theme.space8 : Theme.space20
            anchors.rightMargin: root.width < 520 ? Theme.space8 : Theme.space20
            anchors.topMargin: Theme.space10
            anchors.bottomMargin: Theme.space10
            spacing: Theme.space8

            Slider {
                id: liveWindowSlider
                objectName: "liveWindowSlider"
                Layout.fillWidth: true
                from: 0
                to: Math.max(1, Number(playerController.windowSeconds || 0))
                value: Math.max(0, to - Number(playerController.distanceFromLiveEdge || 0))
                visible: playerController.seekable && playerController.windowSeconds > 0
                Accessible.name: "Live time-shift window"
                onMoved: root.seekWithinWindow(value)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space10

                ActionButton {
                    id: pauseButton
                    objectName: "livePauseButton"
                    compact: true
                    text: root.paused ? "Play" : "Pause"
                    enabled: playerController.seekable && root.activeSession
                    Accessible.name: root.paused ? "Resume Live stream" : "Pause Live stream"
                    onClicked: root.setPaused(!root.paused)
                }
                ActionButton {
                    objectName: "liveGoLiveButton"
                    compact: true
                    text: "Go Live"
                    variant: "primary"
                    visible: playerController.seekable
                             && playerController.distanceFromLiveEdge > 5
                    onClicked: root.goLive()
                }

                Label {
                    text: playerController.seekable && playerController.distanceFromLiveEdge > 1
                          ? "-" + Math.round(playerController.distanceFromLiveEdge) + "s" : "LIVE"
                    color: playerController.distanceFromLiveEdge > 5
                           ? Theme.accentInfo : Theme.accentDanger
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }

                Item { Layout.fillWidth: true }

                ComboBox {
                    id: sourceChoices
                    objectName: "liveSourceChoices"
                    Layout.maximumWidth: 180
                    model: playerController.availableSources || []
                    textRole: "label"
                    currentIndex: root.sourceIndex(model)
                    visible: root.width >= 900 && model.length > 1
                    Accessible.name: "Live source and quality"
                    onActivated: function(index) {
                        var source = model[index]
                        if (source) playerController.switchSource(source.sourceKey)
                    }
                }

                ComboBox {
                    id: audioTracks
                    objectName: "liveAudioTracks"
                    Layout.maximumWidth: 180
                    model: playerController.audioTracks || []
                    textRole: "label"
                    visible: root.width >= 900 && model.length > 1
                    Accessible.name: "Live audio track"
                    onActivated: function(index) {
                        var track = model[index]
                        if (track) root.selectTrack("audio", "aid", track.id)
                    }
                }

                ComboBox {
                    id: subtitleTracks
                    objectName: "liveSubtitleTracks"
                    Layout.maximumWidth: 180
                    model: [{"id": "no", "label": "Subtitles off"}].concat(
                               playerController.subtitleTracks || [])
                    textRole: "label"
                    visible: root.width >= 900 && model.length > 1
                    Accessible.name: "Live subtitle track"
                    onActivated: function(index) {
                        var track = model[index]
                        if (track) root.selectTrack("subtitle", "sid", track.id)
                    }
                }

                ToolButton {
                    objectName: "liveCompactOptionsButton"
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    text: "\u22ee"
                    visible: root.width < 900
                             && ((playerController.availableSources || []).length > 1
                                 || (playerController.audioTracks || []).length > 1
                                 || (playerController.subtitleTracks || []).length > 0)
                    Accessible.name: "Live source and track options"
                    ToolTip.text: Accessible.name
                    ToolTip.visible: hovered
                    onClicked: compactOptions.open()
                }

                Slider {
                    id: volumeSlider
                    objectName: "liveVolume"
                    Layout.preferredWidth: Math.min(130, Math.max(72, root.width * 0.1))
                    from: 0
                    to: 100
                    value: 100
                    visible: root.width >= 700
                    Accessible.name: "Live volume"
                    onMoved: {
                        if (root.playbackSurface)
                            root.playbackSurface.setPropertyAsync("volume", value)
                    }
                }

                ActionButton {
                    objectName: "liveFullscreenButton"
                    compact: true
                    text: "Full screen"
                    visible: root.width >= 520
                    Accessible.name: "Toggle full screen"
                    onClicked: root.toggleFullscreen()
                }
                ActionButton {
                    objectName: "liveStopButton"
                    compact: true
                    text: "Stop"
                    variant: "danger"
                    onClicked: root.exitRoute(true)
                }
            }
        }
    }

    Popup {
        id: compactOptions
        objectName: "liveCompactOptions"
        parent: root
        width: Math.min(320, root.width - Theme.space16)
        height: compactOptionsColumn.implicitHeight + Theme.space24
        x: Math.max(Theme.space8, root.width - width - Theme.space8)
        y: Math.max(Theme.space8, root.height - controls.height - height - Theme.space8)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Theme.surfaceRaised
            border.color: Theme.borderSubtle
            radius: Theme.radius4
        }

        ColumnLayout {
            id: compactOptionsColumn
            anchors.fill: parent
            anchors.margins: Theme.space12
            spacing: Theme.space8

            ComboBox {
                objectName: "liveCompactSourceChoices"
                Layout.fillWidth: true
                model: playerController.availableSources || []
                textRole: "label"
                currentIndex: root.sourceIndex(model)
                visible: model.length > 1
                Accessible.name: "Live source and quality"
                onActivated: function(index) {
                    var source = model[index]
                    if (source) playerController.switchSource(source.sourceKey)
                    compactOptions.close()
                }
            }
            ComboBox {
                objectName: "liveCompactAudioTracks"
                Layout.fillWidth: true
                model: playerController.audioTracks || []
                textRole: "label"
                visible: model.length > 1
                Accessible.name: "Live audio track"
                onActivated: function(index) {
                    var track = model[index]
                    if (track) root.selectTrack("audio", "aid", track.id)
                    compactOptions.close()
                }
            }
            ComboBox {
                objectName: "liveCompactSubtitleTracks"
                Layout.fillWidth: true
                model: [{"id": "no", "label": "Subtitles off"}].concat(
                           playerController.subtitleTracks || [])
                textRole: "label"
                visible: model.length > 1
                Accessible.name: "Live subtitle track"
                onActivated: function(index) {
                    var track = model[index]
                    if (track) root.selectTrack("subtitle", "sid", track.id)
                    compactOptions.close()
                }
            }
        }
    }

    Timer {
        id: observationTimer
        objectName: "liveObservationTimer"
        interval: 500
        repeat: true
        running: root.activeSession && Boolean(root.playbackSurface)
        onTriggered: root.samplePlayback()
    }

    Timer {
        id: controlsHideTimer
        interval: 3500
        repeat: false
        running: root.activeSession && !root.paused
        onTriggered: root.controlsVisible = false
    }

    Keys.onSpacePressed: {
        if (pauseButton.enabled) root.setPaused(!root.paused)
    }
    Keys.onEscapePressed: root.exitRoute(false)
}
