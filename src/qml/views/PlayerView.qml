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
    property string automationActionsText: (typeof playbackAutomationActions === "string") ? playbackAutomationActions : ""
    property var automationActions: []
    property int automationActionIndex: 0
    property int automationDefaultActionIntervalMs: 900
    property bool automationStarted: false
    property bool automationRetryIssued: false
    property int automationResumeActionIndex: -1
    property string automationCaptureDir: (typeof playbackAutomationCaptureDir === "string") ? playbackAutomationCaptureDir : ""
    property real lastAutomationObservationPosition: -1
    property bool automationFrameCaptureRequested: false
    property bool videoSelectionRepairRequested: false
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
        if (!playerController.active || !playerController.serverSeekRequired) {
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
        videoSelectionRepairRequested = false
        clearTracks()
    }

    function parseAutomationActions() {
        var raw = automationActionsText || ""
        var parts = raw.split(/[\s,;]+/)
        var actions = []
        for (var i = 0; i < parts.length; i++) {
            var action = String(parts[i] || "").trim().toLowerCase()
            if (action !== "") {
                actions.push(action)
            }
        }
        return actions
    }

    function automationActionName(action) {
        var text = String(action || "").trim().toLowerCase()
        var separator = text.indexOf(":")
        if (separator < 0) {
            separator = text.indexOf("=")
        }
        if (separator > 0) {
            text = text.substring(0, separator)
        }
        return text
    }

    function automationActionDelayMs(action) {
        var text = String(action || "").trim().toLowerCase()
        var separator = text.indexOf(":")
        if (separator < 0) {
            separator = text.indexOf("=")
        }
        if (separator < 0) {
            return automationDefaultActionIntervalMs
        }
        var seconds = Number(text.substring(separator + 1))
        if (!isFinite(seconds) || seconds <= 0) {
            return automationDefaultActionIntervalMs
        }
        return Math.max(automationDefaultActionIntervalMs, Math.min(120000, Math.round(seconds * 1000)))
    }

    function maybeStartAutomation() {
        if (automationStarted || automationActionsText === "" || !playerController.active) {
            return
        }
        automationActions = parseAutomationActions()
        if (automationActions.length === 0) {
            return
        }
        var startIndex = automationResumeActionIndex >= 0
            ? Math.min(automationResumeActionIndex, automationActions.length)
            : 0
        if (startIndex >= automationActions.length) {
            automationResumeActionIndex = -1
            return
        }
        var firstAction = automationActions[startIndex]
        var startsWithRecoveryRetry = firstAction === "retry_same" || firstAction === "retry_from_current"
        if (!startsWithRecoveryRetry && playerController.position < 1.0 && playerController.duration > 3.0) {
            return
        }
        var resumed = automationResumeActionIndex >= 0
        automationStarted = true
        automationActionIndex = startIndex
        automationResumeActionIndex = -1
        playerController.recordAutomationEvent("automation_started", {
            actions: automationActions.join(","),
            start_index: automationActionIndex,
            resumed: resumed
        })
        automationActionTimer.restart()
    }

    function finishAutomation() {
        playerController.recordAutomationEvent("automation_finished", {
            action_count: automationActionIndex
        })
    }

    function automationFileSafe(value) {
        var text = String(value || "unknown")
        text = text.replace(/[^A-Za-z0-9_.-]/g, "_")
        if (text === "" || text === "_") {
            return "unknown"
        }
        return text
    }

    function trackCounts() {
        var counts = {
            audio: 0,
            subtitle: 0,
            video: 0
        }
        var trackList = mpv.getProperty("track-list")
        if (!trackList || trackList.length === undefined) {
            return counts
        }
        for (var i = 0; i < trackList.length; i++) {
            var track = trackList[i]
            if (!track || !track.type) {
                continue
            }
            if (track.type === "audio") {
                counts.audio += 1
            } else if (track.type === "sub") {
                counts.subtitle += 1
            } else if (track.type === "video") {
                counts.video += 1
            }
        }
        return counts
    }

    function hasObjectData(value) {
        if (value === undefined || value === null) {
            return false
        }
        if (typeof value !== "object") {
            return true
        }
        for (var key in value) {
            if (value[key] !== undefined && value[key] !== null && String(value[key]) !== "") {
                return true
            }
        }
        return false
    }

    function maybeCaptureAutomationFrame(videoReady) {
        if (automationFrameCaptureRequested || automationCaptureDir === "" || !videoReady) {
            return
        }
        if (playerController.position < 1.0 && playerController.duration > 3.0) {
            return
        }
        automationFrameCaptureRequested = true
        var path = automationCaptureDir + "/frame-" +
            automationFileSafe(playerController.sessionId) + "-" +
            automationFileSafe(playerController.mode) + "-" +
            Math.max(0, Math.round(playerController.position * 1000)) + ".png"
        mpv.captureVideoFrame(path)
        playerController.recordAutomationEvent("video_frame_capture_requested", {
            capture_path: path,
            mode: playerController.mode,
            delivery: playerController.delivery,
            position_seconds: playerController.position
        })
    }

    function recordAutomationObservation(force) {
        if (!playerController.active) {
            return
        }
        if (!force && automationActionsText === "" && automationCaptureDir === "") {
            return
        }
        var current = playerController.position
        if (!force && lastAutomationObservationPosition >= 0 &&
                Math.abs(current - lastAutomationObservationPosition) < 1.5) {
            return
        }
        lastAutomationObservationPosition = current

        var counts = trackCounts()
        var videoParams = mpv.getProperty("video-params") || ({})
        var audioParams = mpv.getProperty("audio-params") || ({})
        var videoReady = (mpv.getProperty("vo-configured") === true) ||
            hasObjectData(videoParams) || counts.video > 0
        var audioReady = hasObjectData(audioParams) || counts.audio > 0
        var subtitleVisible = mpv.getProperty("sub-visibility") === true
        var subtitleSid = mpv.getProperty("sid")
        var audioAid = mpv.getProperty("aid")
        var videoVid = mpv.getProperty("vid")
        playerController.recordAutomationEvent("player_observation", {
            session_id: playerController.sessionId,
            mode: playerController.mode,
            delivery: playerController.delivery,
            position_seconds: current,
            video_ready: videoReady,
            audio_ready: audioReady,
            audio_track_count: counts.audio,
            video_track_count: counts.video,
            subtitle_track_count: counts.subtitle,
            selected_audio_id: String(audioAid),
            selected_video_id: String(videoVid),
            selected_subtitle_id: String(subtitleSid),
            subtitle_visible: subtitleVisible,
            server_seek_required: playerController.serverSeekRequired,
            paused: playerController.paused,
            decision_reason: playerController.decisionReason,
            quality_label: playerController.qualityLabel,
            video_params: videoParams,
            audio_params: audioParams
        })
        maybeCaptureAutomationFrame(videoReady)
    }

    function automationSeekTarget(direction) {
        var current = playerController.position
        if (!isFinite(current)) {
            current = 0
        }
        var duration = playerController.duration
        if (!isFinite(duration) || duration <= 0) {
            duration = current + 12
        }
        if (direction < 0) {
            return Math.max(0, current - 2.0)
        }
        return Math.min(Math.max(0, duration - 1.0), current + 4.0)
    }

    function requestSeek(target) {
        if (playerController.serverSeekRequired) {
            mpv.setPropertyAsync("pause", true)
            playerController.setPaused(true)
            playerController.seek(target)
        } else {
            mpv.setPropertyAsync("time-pos", target)
            playerController.seek(target)
        }
    }

    function runAutomationAction(action) {
        var actionName = automationActionName(action)
        playerController.recordAutomationEvent("automation_action", {
            action: actionName,
            raw_action: action
        })
        if (actionName === "pause") {
            mpv.setPropertyAsync("pause", true)
            playerController.setPaused(true)
            return
        }
        if (actionName === "resume") {
            mpv.setPropertyAsync("pause", false)
            playerController.setPaused(false)
            return
        }
        if (actionName === "seek_forward") {
            requestSeek(automationSeekTarget(1))
            return
        }
        if (actionName === "seek_backward") {
            requestSeek(automationSeekTarget(-1))
            return
        }
        if (actionName === "audio_next") {
            refreshTracks()
            if (audioTracks.count <= 1) {
                playerController.recordAutomationEvent("audio_track_switch_unavailable", {
                    reason: "no_alternate_audio_tracks"
                })
                return
            }
            var nextAudioIndex = audioCombo.currentIndex + 1
            if (nextAudioIndex >= audioTracks.count) {
                nextAudioIndex = 0
            }
            var audioEntry = audioTracks.get(nextAudioIndex)
            audioCombo.currentIndex = nextAudioIndex
            if (audioEntry.trackId === "auto") {
                preferredAudioLabel = ""
                mpv.setPropertyAsync("aid", "auto")
            } else {
                preferredAudioLabel = audioEntry.label
                mpv.setPropertyAsync("aid", Number(audioEntry.trackId))
            }
            playerController.recordAutomationEvent("audio_track_switch_requested", {
                label: audioEntry.label,
                track_id: String(audioEntry.trackId)
            })
            return
        }
        if (actionName === "subtitle_next") {
            refreshTracks()
            if (subtitleTracks.count <= 1) {
                playerController.recordAutomationEvent("subtitle_track_switch_unavailable", {
                    reason: "no_subtitle_tracks"
                })
                return
            }
            var nextSubtitleIndex = subtitleCombo.currentIndex + 1
            if (nextSubtitleIndex >= subtitleTracks.count) {
                nextSubtitleIndex = 0
            }
            var subtitleEntry = subtitleTracks.get(nextSubtitleIndex)
            subtitleCombo.currentIndex = nextSubtitleIndex
            if (subtitleEntry.trackId === "no") {
                sessionManager.subtitleMode = "off"
                sessionManager.subtitleLang = ""
                sessionManager.subtitleTitle = ""
                applySubtitleSid("no", "automation=off")
            } else {
                sessionManager.subtitleMode = "track"
                sessionManager.subtitleLang = subtitleEntry.lang || ""
                sessionManager.subtitleTitle = subtitleEntry.title || subtitleEntry.label || ""
                applySubtitleSid(Number(subtitleEntry.trackId), "automation=track")
                requestSubtitleReload("automation-switch")
            }
            userSelectedSubtitle = true
            playerController.recordAutomationEvent("subtitle_track_switch_requested", {
                label: subtitleEntry.label,
                track_id: String(subtitleEntry.trackId)
            })
            return
        }
        if (actionName === "lower_quality") {
            if (!playerController.lowerQualityRetryAvailable) {
                playerController.recordAutomationEvent("lower_quality_unavailable", {
                    reason: "no_lower_quality_retry"
                })
                return
            }
            playerController.recordAutomationEvent("lower_quality_requested", {})
            playerController.retryWithLowerQuality()
            return
        }
        if (actionName === "wait") {
            automationActionTimer.interval = automationActionDelayMs(action)
            playerController.recordAutomationEvent("automation_wait", {
                position_seconds: playerController.position,
                delay_ms: automationActionTimer.interval
            })
            return
        }
        if (actionName === "retry_same" || actionName === "retry_from_current") {
            if (automationRetryIssued) {
                playerController.recordAutomationEvent("retry_recovery_already_requested", {
                    action: actionName
                })
                return
            }
            automationRetryIssued = true
            automationResumeActionIndex = automationActionIndex
            playerController.recordAutomationEvent("retry_recovery_requested", {
                action: actionName,
                position_seconds: playerController.position
            })
            if (actionName === "retry_from_current") {
                playerController.retryFromCurrentPosition()
            } else {
                playerController.retrySamePlan()
            }
            return
        }
        if (actionName === "stop") {
            playerController.recordAutomationEvent("stop_requested", {})
            playerController.endSession()
            mpv.commandAsync(["stop"])
            return
        }
        playerController.recordAutomationEvent("automation_action_unknown", {
            action: actionName,
            raw_action: action
        })
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

    function mapValue(map, key) {
        if (!map || map[key] === undefined || map[key] === null) {
            return ""
        }
        return String(map[key])
    }

    function joinParts(parts) {
        var out = []
        for (var i = 0; i < parts.length; i++) {
            if (parts[i] !== "") {
                out.push(parts[i])
            }
        }
        return out.join(" · ")
    }

    function diagnosticJobState() {
        var job = playerController.jobState || ({})
        var state = mapValue(job, "state")
        var errorKind = mapValue(job, "error_kind")
        if (state !== "" && errorKind !== "") {
            return state + " (" + errorKind + ")"
        }
        if (state !== "") {
            return state
        }
        return errorKind
    }

    function structuredErrorSummary() {
        var err = playerController.lastStructuredError || ({})
        var message = mapValue(err, "message")
        var code = mapValue(err, "code")
        var status = mapValue(err, "status")
        var parts = []
        if (code !== "") {
            parts.push(code)
        }
        if (status !== "") {
            parts.push(status)
        }
        if (message !== "") {
            parts.push(message)
        }
        return parts.join(" · ")
    }

    function objectValue(source, key) {
        if (!source || source[key] === undefined || source[key] === null) {
            return ({})
        }
        return (typeof source[key] === "object") ? source[key] : ({})
    }

    function arrayValue(source, key) {
        if (!source || source[key] === undefined || source[key] === null) {
            return []
        }
        var value = source[key]
        return (value && value.length !== undefined) ? value : []
    }

    function firstMapValue(source, keys) {
        if (!source) {
            return ""
        }
        for (var i = 0; i < keys.length; i++) {
            var value = source[keys[i]]
            if (value !== undefined && value !== null && String(value) !== "") {
                return value
            }
        }
        return ""
    }

    function preferredRemediation() {
        var err = playerController.lastStructuredError || ({})
        var details = objectValue(err, "details")
        var remediation = objectValue(details, "remediation")
        if (hasObjectData(remediation)) {
            return remediation
        }
        var plan = preferredPlanSummary(details)
        remediation = objectValue(plan, "feasibility_remediation")
        if (hasObjectData(remediation)) {
            return remediation
        }
        return ({})
    }

    function actionLabel(action) {
        var value = String(action || "")
        if (value === "try_original_quality") {
            return "Try Original Quality on this client."
        }
        if (value === "lower_quality") {
            return "Retry at a lower quality."
        }
        if (value === "update_gpu_driver") {
            return "Update the server GPU driver."
        }
        if (value === "allow_software_decode_or_lower_quality") {
            return "Allow software decode or choose a lower quality."
        }
        if (value === "allow_software_encode") {
            return "Allow software encode for this workload."
        }
        if (value === "use_software_filter_path") {
            return "Use a software filter path for this playback."
        }
        if (value === "use_hdr_capable_client") {
            return "Use an HDR-capable client or display."
        }
        if (value === "disable_subtitle_burn_in") {
            return "Disable subtitle burn-in for this playback."
        }
        if (value === "choose_text_subtitles") {
            return "Choose text subtitles instead of image subtitles."
        }
        if (value === "upgrade_server_hardware") {
            return "Use faster server hardware for this transcode."
        }
        if (value === "enable_certification_seed_or_probe") {
            return "Seed certification evidence or enable bounded server probes."
        }
        if (value === "retry_later") {
            return "Retry after other transcodes finish."
        }
        if (value === "increase_transcode_capacity") {
            return "Increase the server transcode capacity."
        }
        if (value === "check_server_playback_settings") {
            return "Check server playback settings."
        }
        return titleCaseFromId(value)
    }

    function titleCaseFromId(value) {
        var parts = String(value || "").split("_")
        for (var i = 0; i < parts.length; i++) {
            if (parts[i].length > 0) {
                parts[i] = parts[i].charAt(0).toUpperCase() + parts[i].substring(1)
            }
        }
        return parts.join(" ")
    }

    function remediationDetailsText() {
        var remediation = preferredRemediation()
        if (!hasObjectData(remediation)) {
            return ""
        }
        var lines = []
        var userMessage = String(firstMapValue(remediation, ["user_message", "userMessage"]) || "")
        var adminMessage = String(firstMapValue(remediation, ["admin_message", "adminMessage"]) || "")
        if (userMessage !== "" && userMessage !== sessionMessage) {
            lines.push(userMessage)
        }
        var actions = arrayValue(remediation, "suggested_actions")
        if (actions.length === 0) {
            actions = arrayValue(remediation, "suggestedActions")
        }
        if (actions.length > 0) {
            var labels = []
            for (var i = 0; i < actions.length; i++) {
                var label = actionLabel(actions[i])
                if (label !== "") {
                    labels.push(label)
                }
            }
            if (labels.length > 0) {
                lines.push("Actions: " + labels.join(" "))
            }
        }
        if (adminMessage !== "") {
            lines.push("Admin: " + adminMessage)
        }
        return lines.join("\n")
    }

    function joinArrayValues(value) {
        if (!value || value.length === undefined) {
            return ""
        }
        var out = []
        for (var i = 0; i < value.length; i++) {
            var text = String(value[i] || "")
            if (text !== "") {
                out.push(text)
            }
        }
        return out.join(", ")
    }

    function feasibilityDiagnosticsText() {
        var err = playerController.lastStructuredError || ({})
        var details = objectValue(err, "details")
        var plan = preferredPlanSummary(details)
        if (!hasObjectData(plan)) {
            return ""
        }
        var feasibility = objectValue(plan, "feasibility")
        if (!hasObjectData(feasibility)) {
            feasibility = objectValue(details, "feasibility")
        }
        if (!hasObjectData(feasibility)) {
            return ""
        }

        var lines = []
        var reason = String(firstMapValue(feasibility, ["reason"]) || "")
        if (reason !== "") {
            lines.push("Reason: " + reason)
        }
        var confidence = String(firstMapValue(feasibility, ["confidence"]) || "")
        var performance = String(firstMapValue(feasibility, ["performance_decision", "performanceDecision"]) || "")
        var support = String(firstMapValue(feasibility, ["support_decision", "supportDecision"]) || "")
        var envelopeParts = []
        if (support !== "") {
            envelopeParts.push("support " + support)
        }
        if (performance !== "") {
            envelopeParts.push("performance " + performance)
        }
        if (confidence !== "") {
            envelopeParts.push("confidence " + confidence)
        }
        var sampleCount = firstMapValue(feasibility, ["selected_envelope_sample_count", "selectedEnvelopeSampleCount"])
        var failureCount = firstMapValue(feasibility, ["selected_envelope_failure_count", "selectedEnvelopeFailureCount"])
        if (sampleCount !== "") {
            envelopeParts.push("samples " + sampleCount)
        }
        if (failureCount !== "") {
            envelopeParts.push("failures " + failureCount)
        }
        if (envelopeParts.length > 0) {
            lines.push("Envelope: " + envelopeParts.join(" · "))
        }

        var workload = objectValue(plan, "workload_class")
        if (hasObjectData(workload)) {
            var labels = joinArrayValues(workload.cost_labels || workload.costLabels)
            if (labels !== "") {
                lines.push("Workload: " + labels)
            }
            var stages = joinArrayValues(workload.pipeline_stages || workload.pipelineStages)
            if (stages !== "") {
                lines.push("Pipeline: " + stages)
            }
        }
        if (feasibility.background_probe_queued === true || feasibility.backgroundProbeQueued === true) {
            lines.push("Background probe: queued")
        }
        return lines.join("\n")
    }

    function preferredPlanSummary(details) {
        var plan = playerController.planSummary || ({})
        if (hasObjectData(plan)) {
            return plan
        }
        plan = objectValue(details, "plan_summary")
        if (hasObjectData(plan)) {
            return plan
        }
        return objectValue(details, "planSummary")
    }

    function errorDetailsText() {
        var summary = structuredErrorSummary()
        var remediation = remediationDetailsText()
        var feasibility = feasibilityDiagnosticsText()
        var logTail = playerController.ffmpegLogTail || ""
        var sections = []
        if (summary !== "") {
            sections.push(summary)
        }
        if (remediation !== "") {
            sections.push(remediation)
        }
        if (feasibility !== "") {
            sections.push(feasibility)
        }
        if (logTail !== "") {
            sections.push(logTail)
        }
        return sections.join("\n\n")
    }

    function loadCurrentStream(reason) {
        if (playerController.streamUrl === "") {
            return
        }
        applyHeaders()
        resetTrackState()
        mpv.setPropertyAsync("vid", "auto")
        mpv.commandAsync(["loadfile", playerController.streamUrl, "replace"])
        mpv.setPropertyAsync("pause", false)
        trackRefreshTimer.interval = mpv.hlsDelivery ? 1200 : 500
        trackRefreshTimer.restart()
        showControls()
        dumpTrackList(reason)
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
        var videoTrackCount = 0
        var selectedVideo = false
        var firstVideoTrackId = -1

        for (var i = 0; i < trackList.length; i++) {
            var track = trackList[i]
            if (!track || !track.type) {
                continue
            }
            if (track.type === "video") {
                videoTrackCount += 1
                if (firstVideoTrackId < 0) {
                    firstVideoTrackId = Number(track.id)
                }
                selectedVideo = selectedVideo || track.selected === true
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

        if (videoTrackCount > 0 && !selectedVideo && !videoSelectionRepairRequested) {
            videoSelectionRepairRequested = true
            console.log("VIDEO_SELECT", "repair vid=" + firstVideoTrackId)
            mpv.selectVideoTrack(firstVideoTrackId)
        }

        if (playerController.serverSeekRequired) {
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
        mpv.setAuthorizationHeader(apiClient.authToken)
    }

    MpvItem {
        id: mpv
        anchors.fill: parent
        focus: true
        delivery: playerController.delivery
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
            height: 190
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
                    text: joinParts([
                        playerController.mode !== "" ? ("Mode: " + playerController.mode) : "",
                        playerController.delivery !== "" ? ("Delivery: " + playerController.delivery) : "",
                        playerController.qualityLabel !== "" ? ("Quality: " + playerController.qualityLabel) : ""
                    ])
                    visible: text !== ""
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    text: joinParts([
                        playerController.mediaFileId !== "" ? ("File: " + playerController.mediaFileId) : "",
                        playerController.selectedAudioTrack !== "" ? ("Audio: " + playerController.selectedAudioTrack) : "",
                        playerController.selectedSubtitleTrack !== "" ? ("Subtitles: " + playerController.selectedSubtitleTrack) : ""
                    ])
                    visible: text !== ""
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    text: playerController.decisionReason !== "" ? ("Reason: " + playerController.decisionReason) : ""
                    visible: text !== ""
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontBody
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    text: diagnosticJobState() !== "" ? ("Job: " + diagnosticJobState()) : ""
                    visible: text !== ""
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontBody
                    elide: Text.ElideRight
                    Layout.fillWidth: true
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
                        if (playerController.serverSeekRequired) {
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
        id: noticeCard
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.72, 760)
        height: Math.min(parent.height * 0.78, noticeColumn.implicitHeight + Theme.spacingLarge * 2)
        radius: Theme.radiusLarge
        color: Theme.backgroundCard
        border.color: Theme.border
        visible: sessionMessage !== ""
        clip: true

        ColumnLayout {
            id: noticeColumn
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
                Layout.fillWidth: true
            }

            Label {
                text: errorDetailsText()
                visible: text !== "" && text !== sessionMessage
                color: Theme.textMuted
                font.pixelSize: 11
                font.family: Theme.fontBody
                wrapMode: Text.Wrap
                maximumLineCount: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            RowLayout {
                spacing: Theme.spacingMedium
                Button {
                    text: "Retry"
                    visible: playerController.retryAvailable
                    onClicked: playerController.retrySamePlan()
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.accent
                    }
                    contentItem: Label {
                        text: parent.text
                        color: "#FFFFFF"
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
                Button {
                    text: "Retry from " + formatTime(playerController.position)
                    visible: playerController.retryAvailable
                    onClicked: playerController.retryFromCurrentPosition()
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
                Button {
                    text: "Lower quality"
                    visible: playerController.lowerQualityRetryAvailable
                    onClicked: playerController.retryWithLowerQuality()
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
                Button {
                    text: "Stop"
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
                recordAutomationObservation(false)
                maybeStartAutomation()
            }
            var paused = mpv.getProperty("pause")
            if (paused !== undefined && paused !== null) {
                playerController.setPaused(paused)
            }
            var eofReached = mpv.getProperty("eof-reached")
            if (eofReached === true && playerController.active) {
                playerController.endSession()
            }
        }
    }

    Timer {
        interval: 4000
        running: playerController.active
        repeat: true
        onTriggered: {
            if (playerController.sessionId !== "") {
                if (playerController.paused) {
                    apiClient.heartbeatSession(playerController.sessionId)
                } else {
                    apiClient.pollSession(playerController.sessionId)
                }
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
        id: automationActionTimer
        interval: automationDefaultActionIntervalMs
        repeat: false
        onTriggered: {
            if (!automationStarted || automationActionIndex >= automationActions.length) {
                finishAutomation()
                return
            }
            var action = automationActions[automationActionIndex]
            automationActionIndex += 1
            interval = automationDefaultActionIntervalMs
            runAutomationAction(action)
            if (automationActionIndex < automationActions.length && playerController.active) {
                restart()
            } else {
                finishAutomation()
            }
        }
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
            playerController.recordAutomationEvent("subtitle_replan_requested", {
                position_seconds: playerController.position
            })
            playerController.retryFromCurrentPosition()
        }
    }

    Component.onCompleted: {
        applyHeaders()
        if (playerController.streamUrl !== "") {
            console.log("PlayerView ready", playerController.mode)
            loadCurrentStream("on-load")
        }
        showControls()
    }

    Component.onDestruction: {
        playerController.endSession()
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
            automationStarted = false
            if (automationResumeActionIndex < 0) {
                automationActionIndex = 0
            }
            lastAutomationObservationPosition = -1
            automationFrameCaptureRequested = false
            ensureEnglishDefaultForSession()
        }
        function onStreamUrlChanged() {
            if (playerController.streamUrl === "") {
                return
            }
            console.log("Stream URL changed", playerController.mode)
            mpv.commandAsync(["stop"])
            loadCurrentStream("stream-url-changed")
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
