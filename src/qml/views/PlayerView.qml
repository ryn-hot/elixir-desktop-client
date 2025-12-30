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
    property int lastTrackCount: -1
    property int lastAudioTrackCount: 0
    property int lastSubtitleTrackCount: 0
    property string lastTrackDumpSignature: ""
    property string preferredAudioLabel: ""
    property int pendingSubtitleSid: -1
    property int subtitleSwitchAttempts: 0
    property bool userSelectedSubtitle: false
    property bool subtitleReloadPending: false
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
        var lang = track.lang
        if (!lang && track.metadata && track.metadata.language) {
            lang = track.metadata.language
        }
        if (lang) {
            labelParts.push(String(lang).toUpperCase())
        }
        var title = track.title
        if (!title && track.metadata) {
            title = track.metadata.comment || track.metadata.title || ""
        }
        if (title) {
            labelParts.push(title)
        }
        if (labelParts.length === 0) {
            labelParts.push("Track " + track.id)
        }
        return labelParts.join(" • ")
    }

    function normalizeKey(value) {
        if (value === undefined || value === null) {
            return ""
        }
        return String(value).trim().toLowerCase()
    }

    function dumpTrackList(reason, trackList) {
        var tracks = trackList || mpv.getProperty("track-list")
        if (!tracks || tracks.length === undefined) {
            console.log("TRACK_DUMP", reason, "track-list unavailable")
            return
        }
        var signatureParts = []
        var lines = []
        for (var i = 0; i < tracks.length; i++) {
            var t = tracks[i]
            if (!t) {
                continue
            }
            var lang = t.lang || (t.metadata ? t.metadata.language : "")
            var title = t.title || (t.metadata ? (t.metadata.comment || t.metadata.title) : "")
            var sig = [t.type, t.id, lang, title, t.default, t.selected].join("|")
            signatureParts.push(sig)
            lines.push(
                "[" + i + "]" +
                " type=" + t.type +
                " id=" + t.id +
                " lang=" + (lang || "-") +
                " title=" + (title || "-") +
                " default=" + (t.default === true) +
                " selected=" + (t.selected === true)
            )
        }
        var signature = signatureParts.join(";")
        if (signature === lastTrackDumpSignature) {
            return
        }
        lastTrackDumpSignature = signature
        var sid = mpv.getProperty("sid")
        var subVis = mpv.getProperty("sub-visibility")
        console.log("TRACK_DUMP", reason, "tracks=" + tracks.length, "sid=" + sid, "subVis=" + subVis)
        for (var j = 0; j < lines.length; j++) {
            console.log("TRACK_DUMP", lines[j])
        }
    }

    function findSubtitleMatch(langKey, titleKey) {
        var matchIndex = -1
        for (var i = 1; i < subtitleTracks.count; i++) {
            var entry = subtitleTracks.get(i)
            var entryLang = normalizeKey(entry.lang)
            var entryTitle = normalizeKey(entry.title || entry.label)
            if (langKey && entryLang !== langKey) {
                continue
            }
            if (titleKey && entryTitle !== titleKey) {
                continue
            }
            matchIndex = i
            break
        }
        return matchIndex
    }

    function applySubtitlePreference(selectedIndex) {
        var mode = sessionManager.subtitleMode || "default"
        if (mode === "off") {
            subtitleCombo.currentIndex = 0
            applySubtitleSid("no", "mode=off")
            console.log("SUB_APPLY", "mode=off")
            return
        }

        if (mode === "track") {
            var langKey = normalizeKey(sessionManager.subtitleLang)
            var titleKey = normalizeKey(sessionManager.subtitleTitle)
            var matchIndex = findSubtitleMatch(langKey, titleKey)
            if (matchIndex > 0) {
                subtitleCombo.currentIndex = matchIndex
                applySubtitleSid(Number(subtitleTracks.get(matchIndex).trackId), "mode=track")
                console.log("SUB_APPLY", "mode=track", "index=" + matchIndex, "label=" + subtitleTracks.get(matchIndex).label)
                return
            }
        }

        var preferredIndex = -1
        var englishIndex = -1
        for (var i = 1; i < subtitleTracks.count; i++) {
            var entry = subtitleTracks.get(i)
            if (entry.isDefault && preferredIndex === -1) {
                preferredIndex = i
            }
            if (normalizeKey(entry.lang) === "eng" && englishIndex === -1) {
                englishIndex = i
            }
        }
        if (preferredIndex < 1 && englishIndex > 0) {
            preferredIndex = englishIndex
        }
        if (preferredIndex < 1 && subtitleTracks.count > 1) {
            preferredIndex = 1
        }
        if (preferredIndex < 1) {
            preferredIndex = Math.min(selectedIndex, subtitleTracks.count - 1)
        }

        subtitleCombo.currentIndex = preferredIndex
        if (preferredIndex > 0) {
            applySubtitleSid(Number(subtitleTracks.get(preferredIndex).trackId), "mode=default")
            console.log("SUB_APPLY", "mode=default", "index=" + preferredIndex, "label=" + subtitleTracks.get(preferredIndex).label)
        } else {
            console.log("SUB_APPLY", "mode=default", "no-subtitles")
        }
    }

    function applySubtitleSid(targetSid, reason) {
        var target = targetSid
        var current = mpv.getProperty("sid")
        if (target === "no") {
            mpv.setPropertyAsync("sid", "no")
            mpv.setPropertyAsync("sub-visibility", false)
            pendingSubtitleSid = -1
            subtitleSwitchAttempts = 0
            console.log("SUB_SWITCH", reason, "sid=no current=" + current)
            return
        }
        if (String(current) === String(target)) {
            mpv.setPropertyAsync("sub-visibility", true)
            pendingSubtitleSid = -1
            subtitleSwitchAttempts = 0
            console.log("SUB_SWITCH", reason, "sid=" + target, "already-selected")
            return
        }
        pendingSubtitleSid = Number(target)
        subtitleSwitchAttempts = 0
        mpv.setPropertyAsync("sid", pendingSubtitleSid)
        mpv.setPropertyAsync("sub-visibility", true)
        console.log("SUB_SWITCH", reason, "sid=" + pendingSubtitleSid, "current=" + current)
        subtitleVerifyTimer.restart()
    }

    function ensureEnglishDefaultForSession() {
        if (normalizeKey(sessionManager.subtitleLang) !== "eng" || sessionManager.subtitleMode !== "track") {
            sessionManager.subtitleMode = "track"
            sessionManager.subtitleLang = "eng"
            sessionManager.subtitleTitle = ""
            console.log("SUB_DEFAULT", "english")
        }
    }

    function requestSubtitleReload(reason) {
        if (!playerController.active || playerController.mode !== "transcode") {
            return
        }
        subtitleReloadPending = true
        subtitleReloadTimer.restart()
        console.log("SUB_RELOAD", reason)
    }

    function clearTracks() {
        audioTracks.clear()
        subtitleTracks.clear()
    }

    function resetTrackState() {
        lastTrackCount = -1
        lastAudioTrackCount = 0
        lastSubtitleTrackCount = 0
        clearTracks()
    }

    function toFiniteNumber(value) {
        var num = Number(value)
        if (isNaN(num) || !isFinite(num)) {
            return null
        }
        return num
    }

    function readPlaybackPosition() {
        var pos = toFiniteNumber(mpv.getProperty("time-pos"))
        if (pos === null) {
            pos = toFiniteNumber(mpv.getProperty("playback-time"))
        }
        if (pos === null) {
            var percent = toFiniteNumber(mpv.getProperty("percent-pos"))
            if (percent !== null && playerController.duration > 0) {
                pos = (percent / 100.0) * playerController.duration
            }
        }
        return pos
    }

    function refreshTracks() {
        var trackList = mpv.getProperty("track-list")
        if (!trackList || trackList.length === undefined) {
            return
        }
        if (trackList.length !== lastTrackCount) {
            console.log("track-list updated", trackList.length)
            lastTrackCount = trackList.length
        }
        dumpTrackList("refresh-start", trackList)

        var nextAudio = []
        var nextSubtitles = []
        var audioIndex = 0
        var subtitleIndex = 0

        for (var i = 0; i < trackList.length; i++) {
            var track = trackList[i]
            if (!track || !track.type) {
                continue
            }
            if (track.type === "audio") {
                var audioLang = track.lang
                if (!audioLang && track.metadata && track.metadata.language) {
                    audioLang = track.metadata.language
                }
                var audioTitle = track.title
                if (!audioTitle && track.metadata) {
                    audioTitle = track.metadata.comment || track.metadata.title || ""
                }
                nextAudio.push({
                    label: labelForTrack(track),
                    trackId: String(track.id),
                    lang: audioLang || "",
                    title: audioTitle || ""
                })
                if (track.selected && audioIndex === 0) {
                    audioIndex = nextAudio.length
                }
            }
            if (track.type === "sub") {
                var subLang = track.lang
                if (!subLang && track.metadata && track.metadata.language) {
                    subLang = track.metadata.language
                }
                var subTitle = track.title
                if (!subTitle && track.metadata) {
                    subTitle = track.metadata.comment || track.metadata.title || ""
                }
                nextSubtitles.push({
                    label: labelForTrack(track),
                    trackId: String(track.id),
                    lang: subLang || "",
                    title: subTitle || "",
                    isDefault: track.default === true
                })
                if (track.selected && subtitleIndex === 0) {
                    subtitleIndex = nextSubtitles.length
                }
            }
        }

        if (playerController.mode === "transcode") {
            if (nextSubtitles.length === 0 && lastSubtitleTrackCount > 0) {
                dumpTrackList("refresh-skip-empty", trackList)
                return
            }
            if (nextSubtitles.length < lastSubtitleTrackCount) {
                dumpTrackList("refresh-skip-shrink", trackList)
                return
            }
            if (nextAudio.length < lastAudioTrackCount) {
                dumpTrackList("refresh-skip-audio", trackList)
                return
            }
        }

        audioTracks.clear()
        subtitleTracks.clear()
        audioTracks.append({ label: "Auto", trackId: "auto" })
        subtitleTracks.append({ label: "Off", trackId: "no" })

        for (var ai = 0; ai < nextAudio.length; ai++) {
            audioTracks.append(nextAudio[ai])
        }
        for (var si = 0; si < nextSubtitles.length; si++) {
            subtitleTracks.append(nextSubtitles[si])
        }

        audioCombo.currentIndex = Math.min(audioIndex, audioTracks.count - 1)
        subtitleCombo.currentIndex = Math.min(subtitleIndex, subtitleTracks.count - 1)

        if (preferredAudioLabel !== "") {
            for (var prefAudioIndex = 1; prefAudioIndex < audioTracks.count; prefAudioIndex++) {
                if (audioTracks.get(prefAudioIndex).label === preferredAudioLabel) {
                    audioCombo.currentIndex = prefAudioIndex
                    mpv.setPropertyAsync("aid", Number(audioTracks.get(prefAudioIndex).trackId))
                    break
                }
            }
        }
        applySubtitlePreference(subtitleIndex)

        lastAudioTrackCount = nextAudio.length
        lastSubtitleTrackCount = nextSubtitles.length
        dumpTrackList("refresh-applied", trackList)
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
                            mpv.setPropertyAsync("pause", true)
                            playerController.setPaused(true)
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
                            if (entry.trackId === "auto") {
                                preferredAudioLabel = ""
                                mpv.setPropertyAsync("aid", "auto")
                            } else {
                                preferredAudioLabel = entry.label
                                mpv.setPropertyAsync("aid", Number(entry.trackId))
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
                            if (entry.trackId === "no") {
                                sessionManager.subtitleMode = "off"
                                sessionManager.subtitleLang = ""
                                sessionManager.subtitleTitle = ""
                                applySubtitleSid("no", "user=off")
                                userSelectedSubtitle = true
                            } else {
                                sessionManager.subtitleMode = "track"
                                sessionManager.subtitleLang = entry.lang || ""
                                sessionManager.subtitleTitle = entry.title || entry.label || ""
                                applySubtitleSid(Number(entry.trackId), "user=track")
                                userSelectedSubtitle = true
                                requestSubtitleReload("user-switch")
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
            var pos = readPlaybackPosition()
            if (pos !== null) {
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

    Timer {
        id: subtitleVerifyTimer
        interval: 450
        repeat: false
        onTriggered: {
            if (pendingSubtitleSid < 0) {
                return
            }
            var current = mpv.getProperty("sid")
            if (String(current) === String(pendingSubtitleSid)) {
                console.log("SUB_VERIFY", "ok sid=" + current)
                pendingSubtitleSid = -1
                subtitleSwitchAttempts = 0
                return
            }
            subtitleSwitchAttempts += 1
            console.log("SUB_VERIFY", "mismatch sid=" + current, "target=" + pendingSubtitleSid, "attempt=" + subtitleSwitchAttempts)
            pendingSubtitleSid = -1
        }
    }

    Timer {
        id: subtitleReloadTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (!subtitleReloadPending) {
                return
            }
            subtitleReloadPending = false
            var resumeAt = playerController.position
            playerController.seek(resumeAt)
        }
    }

    Component.onCompleted: {
        applyHeaders()
        if (playerController.streamUrl !== "") {
            console.log("PlayerView ready", playerController.streamUrl, playerController.mode)
            mpv.commandAsync(["loadfile", playerController.streamUrl, "replace"])
            mpv.setPropertyAsync("pause", false)
            resetTrackState()
            trackRefreshTimer.restart()
            dumpTrackList("on-load")
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
        function onSessionIdChanged() {
            userSelectedSubtitle = false
            ensureEnglishDefaultForSession()
        }
        function onStreamUrlChanged() {
            if (playerController.streamUrl === "") {
                return
            }
            console.log("Stream URL changed", playerController.streamUrl, playerController.mode)
            resetTrackState()
            mpv.commandAsync(["stop"])
            mpv.commandAsync(["loadfile", playerController.streamUrl, "replace"])
            mpv.setPropertyAsync("pause", false)
            trackRefreshTimer.restart()
            showControls()
            dumpTrackList("stream-url-changed")
        }
        function onActiveChanged() {
            if (!playerController.active) {
                mpv.commandAsync(["stop"])
                resetTrackState()
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
