import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "detailsView"
    property StackView stackView: null
    property string mediaId: ""
    property var details: null
    property string statusText: ""
    property var reviewQueue: []
    property string reviewStatusText: ""
    property string activeReviewId: ""
    property var activeReview: null
    property var seasons: []
    property var episodes: []
    property string activeSeasonId: ""
    property var activeSeasonDetail: null
    property string seasonStatusText: ""
    property bool seasonsLoading: false
    property bool seasonLoading: false
    property string pendingSeasonId: ""
    property bool deleteBusy: false
    property string deleteStatusText: ""
    property string deleteResultText: ""
    property string episodeActionBusyId: ""
    property string episodeActionBusyAction: ""
    property string episodeStatusText: ""
    property string blockedEpisodesStatusText: ""
    property bool mediaSegmentAnalysisBusy: false
    property string mediaSegmentAnalysisStatusText: ""
    property var mediaSegmentDiagnostics: ({})
    property bool mediaSegmentDiagnosticsLoading: false
    property string mediaSegmentDiagnosticsStatusText: ""
    property string mediaSegmentActionBusyId: ""
    readonly property bool mediaSegmentSupportToolsEnabled: false
    property bool watchStateBusy: false
    property string watchStateStatusText: ""
    property var pendingEpisode: null
    property string selectedSourceProviderId: ""
    property string acquisitionStatusText: ""
    property string acquisitionBusyKey: ""
    property var pendingAcquisitionTargetKeys: ({})
    property bool pendingAcquisitionTargetsRefreshArmed: false
    property var pendingAcquisitionRequest: null
    property var acquisitionSheetEpisode: null
    property string acquisitionSheetScope: "episode"
    property string acquisitionSheetOrigin: "episode"
    property string acquisitionSheetStatusText: ""
    property var selectedRecoveryEpisodeIds: ({})
    property string recoveryRangeStart: ""
    property string recoveryRangeEnd: ""
    property string recoverySelectionStatusText: ""
    readonly property int acquisitionLargeScopeThreshold: 12
    property var libraryItem: {
        var idx = libraryModel.indexOfId(mediaId)
        return idx >= 0 ? libraryModel.get(idx) : null
    }

    function refreshReviewQueue() {
        apiClient.fetchReviewQueue("pending", 200, 0)
    }

    function reviewEntryForFile(fileId) {
        if (!reviewQueue) {
            return null
        }
        for (var i = 0; i < reviewQueue.length; ++i) {
            var entry = reviewQueue[i]
            if (entry.media_file_id === fileId || entry.mediaFileId === fileId) {
                return entry
            }
        }
        return null
    }

    function openReviewForFile(fileId) {
        var entry = reviewEntryForFile(fileId)
        if (!entry) {
            reviewStatusText = "No review entry found for this file."
            return
        }
        activeReviewId = entry.id
        activeReview = null
        reviewStatusText = ""
        apiClient.fetchReviewQueueDetail(entry.id)
        reviewDialog.open()
    }

    function normalizeCandidates(review) {
        if (!review || !review.candidates) {
            return []
        }
        if (Array.isArray(review.candidates)) {
            return review.candidates
        }
        if (review.candidates.candidates && Array.isArray(review.candidates.candidates)) {
            return review.candidates.candidates
        }
        return []
    }

    function idsLabel(ids) {
        if (!ids) {
            return ""
        }
        var parts = []
        if (ids.imdb) parts.push("IMDb " + ids.imdb)
        if (ids.tmdb) parts.push("TMDB " + ids.tmdb)
        if (ids.tvdb_series || ids.tvdb) parts.push("TVDB " + (ids.tvdb_series || ids.tvdb))
        if (ids.tvdb_movie) parts.push("TVDB Movie " + ids.tvdb_movie)
        if (ids.anilist) parts.push("AniList " + ids.anilist)
        return parts.join(" • ")
    }

    function externalIdsFromCandidate(candidate) {
        if (!candidate) {
            return {}
        }
        var ids = candidate.ids || candidate.external_ids || candidate.externalIds || {}
        var result = {}
        if (ids.imdb) result.imdb = ids.imdb
        if (ids.tmdb) result.tmdb = ids.tmdb
        if (ids.tvdb) result.tvdb = ids.tvdb
        if (ids.tvdb_series) result.tvdb_series = ids.tvdb_series
        if (ids.tvdb_movie) result.tvdb_movie = ids.tvdb_movie
        if (ids.anilist) result.anilist = ids.anilist
        if (!result.imdb && candidate.imdb) result.imdb = candidate.imdb
        if (!result.anilist && candidate.anilist) result.anilist = candidate.anilist
        return result
    }

    function candidateTitle(candidate) {
        if (!candidate) {
            return ""
        }
        var title = candidate.title || candidate.name || ""
        if (candidate.year) {
            title += " (" + candidate.year + ")"
        }
        return title
    }

    function isSeriesType() {
        if (details && details.type) {
            return details.type === "series" || details.type === "anime"
        }
        return libraryItem && (libraryItem.type === "series" || libraryItem.type === "anime")
    }

    function mediaSegmentItemType() {
        if (details && details.type) {
            return String(details.type)
        }
        return libraryItem && libraryItem.type ? String(libraryItem.type) : ""
    }

    function mediaSegmentFileCount() {
        return details && details.files ? details.files.length : 0
    }

    function mediaSegmentAnalysisSubtitle() {
        var count = mediaSegmentFileCount()
        if (count === 0) {
            return "No linked files"
        }
        return count + " linked " + (count === 1 ? "file" : "files")
    }

    function detailRuntimeSeconds() {
        var seconds = details && details.runtime_seconds ? details.runtime_seconds
                    : (details && details.runtimeSeconds ? details.runtimeSeconds
                       : (libraryItem && libraryItem.runtime ? libraryItem.runtime : 0))
        seconds = Number(seconds)
        return isNaN(seconds) || seconds <= 0 ? 0 : Math.round(seconds)
    }

    function watchStateItemType() {
        var type = mediaSegmentItemType()
        if (type === "movie") {
            return "movie"
        }
        return ""
    }

    function canUseWatchStateActions() {
        return details !== null && mediaId !== "" && watchStateItemType() !== ""
    }

    function runWatchStateAction(action) {
        if (watchStateBusy || !canUseWatchStateActions()) {
            return
        }
        watchStateBusy = true
        watchStateStatusText = ""
        apiClient.updateMediaItemWatchState(
            mediaId,
            watchStateItemType(),
            action,
            detailRuntimeSeconds())
    }

    function watchStateActionResultText(action, state) {
        if (action === "watched") {
            return "Marked watched."
        }
        if (action === "unwatched") {
            return "Marked unwatched."
        }
        return "Progress reset."
    }

    function runMediaSegmentAnalysis(force) {
        if (!mediaSegmentSupportToolsEnabled) {
            return
        }
        if (mediaSegmentAnalysisBusy || mediaId === "" || mediaSegmentFileCount() === 0) {
            return
        }
        mediaSegmentAnalysisBusy = true
        mediaSegmentAnalysisStatusText = ""
        apiClient.analyzeMediaSegments(mediaId, mediaSegmentItemType(), force)
    }

    function mediaSegmentAnalysisResultText(summary) {
        var jobs = summary && summary.jobs ? summary.jobs.length : 0
        var failures = summary && summary.failures ? summary.failures.length : 0
        var files = summary ? (summary.media_files_seen || summary.mediaFilesSeen || 0) : 0
        var mode = summary && summary.force ? "Reanalysis" : "Analysis"
        var text = mode + " queued " + jobs + " " + (jobs === 1 ? "job" : "jobs") +
                   " for " + files + " " + (files === 1 ? "file" : "files") + "."
        if (failures > 0) {
            text += " " + failures + " failed to queue."
        }
        return text
    }

    function refreshMediaSegmentDiagnostics(preserveStatus) {
        if (!mediaSegmentSupportToolsEnabled ||
                mediaId === "" || mediaSegmentItemType() === "" || mediaSegmentFileCount() === 0) {
            mediaSegmentDiagnostics = ({})
            mediaSegmentDiagnosticsLoading = false
            mediaSegmentDiagnosticsStatusText = ""
            return
        }
        mediaSegmentDiagnosticsLoading = true
        if (!preserveStatus) {
            mediaSegmentDiagnosticsStatusText = ""
        }
        apiClient.fetchItemMediaSegments(mediaId, mediaSegmentItemType())
    }

    function mediaSegmentActiveList() {
        if (!mediaSegmentDiagnostics) {
            return []
        }
        return mediaSegmentDiagnostics.active || []
    }

    function mediaSegmentField(segment, snakeName, camelName, fallback) {
        if (!segment) {
            return fallback
        }
        if (segment[snakeName] !== undefined && segment[snakeName] !== null) {
            return segment[snakeName]
        }
        if (segment[camelName] !== undefined && segment[camelName] !== null) {
            return segment[camelName]
        }
        return fallback
    }

    function mediaSegmentTypeLabel(segment) {
        var type = String(mediaSegmentField(segment, "segment_type", "segmentType", "segment")).replace(/_/g, " ")
        if (type.length === 0) {
            return "Segment"
        }
        return type.charAt(0).toUpperCase() + type.slice(1)
    }

    function mediaSegmentTimestamp(seconds) {
        seconds = Math.max(0, Math.round(Number(seconds) || 0))
        var h = Math.floor(seconds / 3600)
        var m = Math.floor((seconds % 3600) / 60)
        var s = seconds % 60
        var mm = h > 0 && m < 10 ? "0" + m : String(m)
        var ss = s < 10 ? "0" + s : String(s)
        return h > 0 ? h + ":" + mm + ":" + ss : m + ":" + ss
    }

    function mediaSegmentRangeText(segment) {
        var start = mediaSegmentField(segment, "start_seconds", "startSeconds", 0)
        var end = mediaSegmentField(segment, "end_seconds", "endSeconds", start)
        return mediaSegmentTimestamp(start) + " - " + mediaSegmentTimestamp(end)
    }

    function mediaSegmentSourceText(segment) {
        var source = String(mediaSegmentField(segment, "source_label", "sourceLabel", "") || "")
        var confidence = Number(mediaSegmentField(segment, "confidence", "confidence", -1))
        var parts = []
        if (source !== "") {
            parts.push(source)
        }
        if (!isNaN(confidence) && confidence >= 0) {
            parts.push(Math.round(confidence * 100) + "%")
        }
        return parts.length > 0 ? parts.join(" / ") : "Unknown source"
    }

    function disableMediaSegmentMarker(segment) {
        if (!mediaSegmentSupportToolsEnabled) {
            return
        }
        var segmentId = String(mediaSegmentField(segment, "id", "id", "") || "")
        if (segmentId === "" || mediaSegmentActionBusyId !== "") {
            return
        }
        mediaSegmentActionBusyId = segmentId
        mediaSegmentDiagnosticsStatusText = ""
        apiClient.disableMediaSegment(segmentId, "bad_marker")
    }

    function lifecycleInfo() {
        return details && details.lifecycle ? details.lifecycle : {}
    }

    function canStopTracking() {
        var lifecycle = lifecycleInfo()
        return lifecycle && Boolean(lifecycle.can_stop_tracking || lifecycle.canStopTracking)
    }

    function managerDisplayName() {
        var lifecycle = lifecycleInfo()
        var implementation = lifecycle.manager_implementation || lifecycle.managerImplementation || ""
        if (implementation !== "") {
            return implementation.charAt(0).toUpperCase() + implementation.slice(1)
        }
        return lifecycle.manager_label || lifecycle.managerLabel || "manager"
    }

    function ownerReleaseLabel() {
        var lifecycle = lifecycleInfo()
        if (lifecycle.owner_release_label || lifecycle.ownerReleaseLabel) {
            return lifecycle.owner_release_label || lifecycle.ownerReleaseLabel
        }
        var owner = lifecycle.primary_owner || lifecycle.primaryOwner || null
        if (owner) {
            if (owner.release_label || owner.releaseLabel) {
                return owner.release_label || owner.releaseLabel
            }
            var ownerType = owner.owner_type || owner.ownerType || ""
            if (ownerType === "acquisition") {
                return "Stop Elixir acquisition monitoring"
            }
        }
        return "Stop tracking in owner"
    }

    function ownerReleaseButtonLabel() {
        var lifecycle = lifecycleInfo()
        var owner = lifecycle.primary_owner || lifecycle.primaryOwner || null
        var ownerType = owner ? (owner.owner_type || owner.ownerType || "") : ""
        if (ownerType === "acquisition") {
            return "Stop monitoring"
        }
        return "Stop tracking"
    }

    function deleteTargetLabel() {
        return isSeriesType() ? "show" : "movie"
    }

    function blockedEpisodeCount() {
        var lifecycle = lifecycleInfo()
        if (!lifecycle) {
            return 0
        }
        return lifecycle.blocked_episode_count || lifecycle.blockedEpisodeCount || 0
    }

    function canRestoreBlockedEpisodes() {
        var lifecycle = lifecycleInfo()
        return lifecycle && Boolean(lifecycle.can_restore_blocked_episodes || lifecycle.canRestoreBlockedEpisodes)
    }

    function episodeLifecycleInfo(episode) {
        return episode && episode.lifecycle ? episode.lifecycle : {}
    }

    function episodeBlocked(episode) {
        var lifecycle = episodeLifecycleInfo(episode)
        return lifecycle && Boolean(lifecycle.blocked_in_elixir || lifecycle.blockedInElixir)
    }

    function episodeCanDelete(episode) {
        var lifecycle = episodeLifecycleInfo(episode)
        return lifecycle && Boolean(lifecycle.can_delete_locally || lifecycle.canDeleteLocally)
    }

    function episodeCanBlock(episode) {
        var lifecycle = episodeLifecycleInfo(episode)
        return lifecycle && Boolean(lifecycle.can_block_in_elixir || lifecycle.canBlockInElixir)
    }

    function episodeCanRestore(episode) {
        var lifecycle = episodeLifecycleInfo(episode)
        return lifecycle && Boolean(lifecycle.can_restore || lifecycle.canRestore)
    }

    function episodeStatusLabel(episode) {
        return episodeRecoveryLabel(episode)
    }

    function episodeAcquisitionInfo(episode) {
        return episode && episode.acquisition ? episode.acquisition : ({})
    }

    function episodePlaybackState(episode) {
        if (!episode) {
            return {}
        }
        return episode.playback_state || episode.playbackState || {}
    }

    function episodeWatched(episode) {
        return episodePlaybackState(episode).watched === true
    }

    function episodeResumeSeconds(episode) {
        var state = episodePlaybackState(episode)
        var value = state.resume_seconds !== undefined ? state.resume_seconds : state.resumeSeconds
        value = Number(value)
        return isNaN(value) ? 0 : Math.max(0, value)
    }

    function episodeWatchStateText(episode) {
        if (episodeWatched(episode)) {
            return "Watched"
        }
        var resume = episodeResumeSeconds(episode)
        if (resume >= 30) {
            return "In progress"
        }
        return ""
    }

    function episodeRuntimeSeconds(episode) {
        var value = episode && episode.runtime_seconds !== undefined ? episode.runtime_seconds
                  : (episode && episode.runtimeSeconds !== undefined ? episode.runtimeSeconds : 0)
        value = Number(value)
        return isNaN(value) || value <= 0 ? 0 : Math.round(value)
    }

    function runEpisodeWatchStateAction(episode, action) {
        var id = episodeId(episode)
        if (id === "" || episodeActionBusyId !== "") {
            return
        }
        episodeActionBusyId = id
        episodeActionBusyAction = action
        episodeStatusText = ""
        apiClient.updateMediaItemWatchState(
            id,
            "episode",
            action,
            episodeRuntimeSeconds(episode))
    }

    function stringValue(obj, snake, camel) {
        if (!obj) {
            return ""
        }
        var value = obj[camel]
        if (value === undefined || value === null || value === "") {
            value = obj[snake]
        }
        return value === undefined || value === null ? "" : String(value)
    }

    function targetKeyIsPending(key) {
        return key !== "" && pendingAcquisitionTargetKeys
                && pendingAcquisitionTargetKeys[key] === true
    }

    function targetKeyPending(episode) {
        return targetKeyIsPending(targetKeyForEpisode(episode))
    }

    function markPendingAcquisitionTargets(keys) {
        var next = {}
        var current = pendingAcquisitionTargetKeys || ({})
        for (var key in current) {
            if (current[key] === true) {
                next[key] = true
            }
        }
        for (var i = 0; keys && i < keys.length; ++i) {
            var targetKey = String(keys[i] || "")
            if (targetKey !== "") {
                next[targetKey] = true
            }
        }
        pendingAcquisitionTargetKeys = next
        pendingAcquisitionTargetsRefreshArmed = false
    }

    function clearPendingAcquisitionTargets(keys) {
        if (!keys || keys.length === 0) {
            pendingAcquisitionTargetKeys = ({})
            pendingAcquisitionTargetsRefreshArmed = false
            return
        }
        var next = {}
        var current = pendingAcquisitionTargetKeys || ({})
        for (var key in current) {
            if (current[key] === true) {
                next[key] = true
            }
        }
        for (var i = 0; i < keys.length; ++i) {
            delete next[String(keys[i] || "")]
        }
        pendingAcquisitionTargetKeys = next
        if (Object.keys(next).length === 0) {
            pendingAcquisitionTargetsRefreshArmed = false
        }
    }

    function reconcilePendingAcquisitionTargets(items) {
        if (!pendingAcquisitionTargetsRefreshArmed || !items || !pendingAcquisitionTargetKeys) {
            return
        }
        var keys = []
        for (var i = 0; i < items.length; ++i) {
            var key = targetKeyForEpisode(items[i])
            if (targetKeyIsPending(key)) {
                keys.push(key)
            }
        }
        if (keys.length > 0) {
            clearPendingAcquisitionTargets(keys)
        }
    }

    function episodeRecoveryState(episode) {
        if (episodeBlocked(episode)) {
            return "blocked"
        }
        if (episode && episode.has_file === true) {
            return "available"
        }
        if (targetKeyPending(episode)) {
            return "searching"
        }
        var acquisition = episodeAcquisitionInfo(episode)
        var state = stringValue(acquisition, "state", "state")
        return state !== "" ? state : "missing"
    }

    function episodeRecoveryAction(episode) {
        if (targetKeyPending(episode)) {
            return "view_progress"
        }
        var acquisition = episodeAcquisitionInfo(episode)
        var action = stringValue(acquisition, "action", "action")
        if (action !== "") {
            return action
        }
        var state = episodeRecoveryState(episode)
        if (state === "available") return "play"
        if (state === "blocked") return "allow_again"
        if (state === "review_needed") return "review"
        if (state === "queued" || state === "searching" ||
                state === "downloading" || state === "post_processing") {
            return "view_progress"
        }
        if (state === "no_results") return "search_again"
        if (state === "failed") return "try_again"
        return "get_episode"
    }

    function episodeRecoveryLabel(episode) {
        var state = episodeRecoveryState(episode)
        if (state === "available") {
            return ""
        }
        if (targetKeyPending(episode)) {
            return "Searching"
        }
        var acquisition = episodeAcquisitionInfo(episode)
        var label = stringValue(acquisition, "label", "label")
        if (label !== "") {
            return label
        }
        switch (state) {
        case "blocked": return "Blocked"
        case "queued": return "Queued"
        case "searching": return "Searching"
        case "downloading": return "Downloading"
        case "post_processing": return "Post-processing"
        case "review_needed": return "Review needed"
        case "no_results": return "No results"
        case "failed": return "Search failed"
        default: return "Missing"
        }
    }

    function episodeRecoveryMessage(episode) {
        var state = episodeRecoveryState(episode)
        if (state === "available") {
            return ""
        }
        if (targetKeyPending(episode)) {
            return "Searching for a safe release."
        }
        var acquisition = episodeAcquisitionInfo(episode)
        var message = stringValue(acquisition, "message", "message")
        if (message !== "") {
            return message
        }
        switch (state) {
        case "blocked": return "This episode is hidden until you allow it again."
        case "queued": return "Queued for download."
        case "searching": return "Searching for a safe release."
        case "downloading": return "Download is in progress."
        case "post_processing": return "Download complete. Elixir is importing it."
        case "review_needed": return "Open review to confirm the files before import."
        case "no_results": return "No safe release was found. You can search again."
        case "failed": return "The last search failed. You can try again."
        default: return "No file is linked yet."
        }
    }

    function episodePrimaryActionText(episode) {
        switch (episodeRecoveryAction(episode)) {
        case "review": return "Review"
        case "view_progress": return "View progress"
        case "search_again": return "Search again"
        case "try_again": return "Try again"
        case "allow_again": return "Allow again"
        case "play": return "Play"
        default: return "Get episode"
        }
    }

    function episodeCanUsePrimaryAction(episode) {
        var action = episodeRecoveryAction(episode)
        if (action === "review" || action === "view_progress") {
            return true
        }
        if (action === "get_episode" || action === "search_again" || action === "try_again") {
            return !episodeBlocked(episode)
        }
        return false
    }

    function episodeInProgress(episode) {
        var state = episodeRecoveryState(episode)
        return state === "queued" || state === "searching" ||
               state === "downloading" || state === "post_processing"
    }

    function episodeCanRequeue(episode) {
        var state = episodeRecoveryState(episode)
        return episode && !episodeBlocked(episode) &&
               (state === "missing" || state === "no_results" || state === "failed")
    }

    function episodeId(episode) {
        return String(episode && episode.id ? episode.id : "")
    }

    function episodeSelected(episode) {
        var id = episodeId(episode)
        return id !== "" && selectedRecoveryEpisodeIds && selectedRecoveryEpisodeIds[id] === true
    }

    function setEpisodeSelected(episode, selected) {
        var id = episodeId(episode)
        if (id === "" || !episodeCanRequeue(episode)) {
            return
        }
        var next = {}
        var current = selectedRecoveryEpisodeIds || ({})
        for (var key in current) {
            if (current[key] === true) {
                next[key] = true
            }
        }
        if (selected) {
            next[id] = true
        } else {
            delete next[id]
        }
        selectedRecoveryEpisodeIds = next
        recoverySelectionStatusText = ""
    }

    function clearRecoverySelection() {
        selectedRecoveryEpisodeIds = ({})
        recoverySelectionStatusText = ""
    }

    function recoverableEpisodesForActiveSeason() {
        var result = []
        if (!episodes) {
            return result
        }
        for (var i = 0; i < episodes.length; ++i) {
            if (episodeCanRequeue(episodes[i])) {
                result.push(episodes[i])
            }
        }
        return result
    }

    function recoverableEpisodesByState(state) {
        var result = []
        var candidates = recoverableEpisodesForActiveSeason()
        for (var i = 0; i < candidates.length; ++i) {
            if (episodeRecoveryState(candidates[i]) === state) {
                result.push(candidates[i])
            }
        }
        return result
    }

    function setRecoverySelectionFromEpisodes(items) {
        var next = {}
        for (var i = 0; i < items.length; ++i) {
            var id = episodeId(items[i])
            if (id !== "") {
                next[id] = true
            }
        }
        selectedRecoveryEpisodeIds = next
        recoverySelectionStatusText = items.length === 0
                                      ? "No selectable episodes matched that action."
                                      : (items.length + " episode" + (items.length === 1 ? "" : "s") + " selected.")
    }

    function selectedRecoveryEpisodes() {
        var selected = selectedRecoveryEpisodeIds || ({})
        var result = []
        if (!episodes) {
            return result
        }
        for (var i = 0; i < episodes.length; ++i) {
            var id = episodeId(episodes[i])
            if (id !== "" && selected[id] === true && episodeCanRequeue(episodes[i])) {
                result.push(episodes[i])
            }
        }
        return result
    }

    function selectedRecoveryCount() {
        return selectedRecoveryEpisodes().length
    }

    function recoverableEpisodesExcept(episode) {
        var result = []
        var excludedId = episodeId(episode)
        var candidates = recoverableEpisodesForActiveSeason()
        for (var i = 0; i < candidates.length; ++i) {
            if (episodeId(candidates[i]) !== excludedId) {
                result.push(candidates[i])
            }
        }
        return result
    }

    function formatEpisodeCount(count) {
        return count + " episode" + (count === 1 ? "" : "s")
    }

    function episodeSheetLabel(episode) {
        if (!episode) {
            return "episode"
        }
        var key = targetKeyForEpisode(episode)
        var title = episodeTitle(episode)
        return key !== "" ? key + " · " + title : title
    }

    function seasonIssueSummary() {
        var counts = seasonAcquisitionSummary()
        var parts = []
        if (counts.missing > 0) parts.push(counts.missing + " missing")
        if (counts.noResults > 0) parts.push(counts.noResults + " no results")
        if (counts.failed > 0) parts.push(counts.failed + " failed")
        if (counts.review > 0) parts.push(counts.review + " need review")
        return parts.join(" · ")
    }

    function seasonIssueCount() {
        return recoverableEpisodesForActiveSeason().length
    }

    function openAcquisitionSheetForEpisode(episode) {
        if (!episode || !episodeCanRequeue(episode)) {
            return
        }
        ensureSelectedSourceProvider()
        acquisitionSheetEpisode = episode
        acquisitionSheetOrigin = "episode"
        acquisitionSheetScope = "episode"
        acquisitionSheetStatusText = ""
        acquisitionStatusText = ""
        clearRecoverySelection()
        setEpisodeSelected(episode, true)
        var number = episodeNumberValue(episode, "episode_number", "episodeNumber")
        recoveryRangeStart = number !== null ? String(number) : ""
        recoveryRangeEnd = number !== null ? String(number) : ""
        acquisitionSheetDialog.open()
    }

    function openAcquisitionSheetForSeason() {
        if (recoverableEpisodesForActiveSeason().length === 0) {
            return
        }
        ensureSelectedSourceProvider()
        acquisitionSheetEpisode = null
        acquisitionSheetOrigin = "season"
        acquisitionSheetScope = "season"
        acquisitionSheetStatusText = ""
        acquisitionStatusText = ""
        clearRecoverySelection()
        setRecoverySelectionFromEpisodes(recoverableEpisodesForActiveSeason())
        recoverySelectionStatusText = ""
        recoveryRangeStart = ""
        recoveryRangeEnd = ""
        acquisitionSheetDialog.open()
    }

    function acquisitionSheetSeasonScopeEnabled() {
        var count = recoverableEpisodesForActiveSeason().length
        if (acquisitionSheetOrigin === "season") {
            return count > 0
        }
        return recoverableEpisodesExcept(acquisitionSheetEpisode).length > 0
    }

    function acquisitionSheetScopeOptions() {
        var seasonCount = recoverableEpisodesForActiveSeason().length
        var otherCount = recoverableEpisodesExcept(acquisitionSheetEpisode).length
        var selectedCount = selectedRecoveryCount()
        return [
            {
                id: "episode",
                label: "This episode",
                detail: acquisitionSheetEpisode ? episodeSheetLabel(acquisitionSheetEpisode) : "Open from a missing episode.",
                enabled: acquisitionSheetEpisode !== null && episodeCanRequeue(acquisitionSheetEpisode),
                reason: "Open from a missing episode."
            },
            {
                id: "season",
                label: "Missing in this season",
                detail: seasonCount > 0 ? formatEpisodeCount(seasonCount) : "No missing episodes in this season.",
                enabled: acquisitionSheetSeasonScopeEnabled(),
                reason: otherCount === 0 && acquisitionSheetOrigin === "episode"
                        ? "No other missing episodes in this season."
                        : "No missing episodes in this season."
            },
            {
                id: "range",
                label: "Custom range",
                detail: seasonCount > 1 ? "Enter a contiguous episode slice." : "No other missing episodes in this season.",
                enabled: seasonCount > 1,
                reason: "No other missing episodes in this season."
            },
            {
                id: "selected_targets",
                label: "Selected episodes",
                detail: selectedCount > 0 ? formatEpisodeCount(selectedCount) + " selected" : "Choose exact episodes below.",
                enabled: seasonCount > 1,
                reason: "No episode set to choose from."
            }
        ]
    }

    function acquisitionSheetItemsForScope(scope) {
        if (scope === "episode") {
            return acquisitionSheetEpisode && episodeCanRequeue(acquisitionSheetEpisode)
                   ? [acquisitionSheetEpisode]
                   : []
        }
        if (scope === "season") {
            return recoverableEpisodesForActiveSeason()
        }
        if (scope === "range") {
            return episodesInRange(recoveryRangeStart, recoveryRangeEnd)
        }
        if (scope === "selected_targets") {
            return selectedRecoveryEpisodes()
        }
        return []
    }

    function acquisitionSheetScopeLabel(scope) {
        if (scope === "episode") return "this episode"
        if (scope === "season") return "missing episodes in this season"
        if (scope === "range") return "custom range"
        if (scope === "selected_targets") return "selected episodes"
        return "episodes"
    }

    function acquisitionSheetRequestTitle(scope) {
        if (scope === "episode") return acquisitionSheetEpisode ? episodeSheetLabel(acquisitionSheetEpisode) : "this episode"
        if (scope === "season") return activeSeasonTitle()
        if (scope === "range") return "episodes " + recoveryRangeStart.trim() + "-" + recoveryRangeEnd.trim()
        if (scope === "selected_targets") return "selected episodes"
        return "episodes"
    }

    function acquisitionSheetSummary() {
        var reason = sourceProviderDisabledReason()
        if (reason !== "") {
            return reason
        }
        var items = acquisitionSheetItemsForScope(acquisitionSheetScope)
        if (acquisitionSheetScope === "range" && items.length === 0) {
            return "Enter a range like 1 to 5 or S02E01 to S02E05."
        }
        if (acquisitionSheetScope === "selected_targets" && items.length === 0) {
            return "Select one or more episodes."
        }
        if (items.length === 0) {
            return "No selectable episodes for this scope."
        }
        return "Searching " + formatEpisodeCount(items.length) + " from " + activeSeasonTitle() + "."
    }

    function acquisitionSheetCanSubmit() {
        return root.acquisitionBusyKey === "" &&
               sourceProviderDisabledReason() === "" &&
               acquisitionSheetItemsForScope(acquisitionSheetScope).length > 0
    }

    function activeSeasonNumberValue() {
        if (activeSeasonDetail) {
            var fromDetail = Number(activeSeasonDetail.season_number || activeSeasonDetail.seasonNumber || 0)
            if (fromDetail > 0) return fromDetail
        }
        if (episodes && episodes.length > 0) {
            var fromEpisode = episodeNumberValue(episodes[0], "season_number", "seasonNumber")
            if (fromEpisode !== null) return fromEpisode
        }
        return 0
    }

    function parseEpisodeRangeValue(value) {
        var text = String(value || "").trim().toUpperCase()
        if (text === "") {
            return null
        }
        var episodeMatch = text.match(/^S\d{1,3}E(\d{1,4})$/)
        if (episodeMatch && episodeMatch.length > 1) {
            return Number(episodeMatch[1])
        }
        var plainMatch = text.match(/^E?(\d{1,4})$/)
        if (plainMatch && plainMatch.length > 1) {
            return Number(plainMatch[1])
        }
        return null
    }

    function episodesInRange(startValue, endValue) {
        var start = parseEpisodeRangeValue(startValue)
        var end = parseEpisodeRangeValue(endValue)
        if (start === null || end === null) {
            return []
        }
        if (start > end) {
            var tmp = start
            start = end
            end = tmp
        }
        var result = []
        var candidates = recoverableEpisodesForActiveSeason()
        for (var i = 0; i < candidates.length; ++i) {
            var number = episodeNumberValue(candidates[i], "episode_number", "episodeNumber")
            if (number !== null && number >= start && number <= end) {
                result.push(candidates[i])
            }
        }
        return result
    }

    function selectRecoveryRange() {
        var items = episodesInRange(recoveryRangeStart, recoveryRangeEnd)
        if (items.length === 0) {
            recoverySelectionStatusText = "Enter a range like 1 to 5 or S02E01 to S02E05 with missing, no-result, or failed episodes."
            return
        }
        setRecoverySelectionFromEpisodes(items)
    }

    function hashString(value) {
        var hash = 5381
        var text = String(value || "")
        for (var i = 0; i < text.length; ++i) {
            hash = ((hash << 5) + hash + text.charCodeAt(i)) | 0
        }
        return (hash >>> 0).toString(16)
    }

    function acquisitionIdempotencySuffix(scope, targetKeys) {
        var first = targetKeys.length > 0 ? targetKeys[0] : "none"
        var last = targetKeys.length > 0 ? targetKeys[targetKeys.length - 1] : "none"
        var fingerprint = hashString(targetKeys.join("|"))
        return scope + ":" + activeSeasonId + ":" + targetKeys.length + ":" + first + ":" + last + ":" + fingerprint
    }

    function seasonAcquisitionSummary() {
        var counts = {
            available: 0,
            missing: 0,
            inProgress: 0,
            review: 0,
            noResults: 0,
            failed: 0,
            blocked: 0
        }
        if (!episodes) {
            return counts
        }
        for (var i = 0; i < episodes.length; ++i) {
            var state = episodeRecoveryState(episodes[i])
            if (state === "available") counts.available += 1
            else if (state === "blocked") counts.blocked += 1
            else if (state === "review_needed") counts.review += 1
            else if (state === "no_results") counts.noResults += 1
            else if (state === "failed") counts.failed += 1
            else if (state === "queued" || state === "searching" ||
                     state === "downloading" || state === "post_processing") counts.inProgress += 1
            else counts.missing += 1
        }
        return counts
    }

    function seasonSummaryChips() {
        var counts = seasonAcquisitionSummary()
        var chips = []
        if (counts.missing > 0) chips.push({ label: "Missing", value: counts.missing, tone: "warning" })
        if (counts.inProgress > 0) chips.push({ label: "In progress", value: counts.inProgress, tone: "info" })
        if (counts.review > 0) chips.push({ label: "Review", value: counts.review, tone: "warning" })
        if (counts.noResults > 0) chips.push({ label: "No results", value: counts.noResults, tone: "danger" })
        if (counts.failed > 0) chips.push({ label: "Failed", value: counts.failed, tone: "danger" })
        if (counts.blocked > 0) chips.push({ label: "Blocked", value: counts.blocked, tone: "info" })
        return chips
    }

    function summaryChipFill(tone) {
        if (tone === "success") return Theme.accentSuccessSoft
        if (tone === "danger") return Theme.accentDangerSoft
        if (tone === "info") return Theme.accentInfoSoft
        return Theme.accentSoft
    }

    function summaryChipBorder(tone) {
        if (tone === "success") return Theme.accentSuccess
        if (tone === "danger") return Theme.accentDanger
        if (tone === "info") return Theme.accentInfo
        return Theme.accent
    }

    function openAcquisitionProgress(subscriptionId) {
        var focusId = String(subscriptionId || "")
        if (root.stackView) {
            root.stackView.push(Qt.resolvedUrl("AcquisitionView.qml"), {
                stackView: root.stackView,
                focusIntentId: focusId
            })
        }
        apiClient.fetchMediaAcquisition(focusId === "" ? 12 : 50)
        apiClient.fetchAcquisitionReleases("review_required", "", 50)
    }

    function openEpisodeAcquisitionReview(episode) {
        var acquisition = episodeAcquisitionInfo(episode)
        var releaseId = stringValue(acquisition, "release_id", "releaseId")
        if (releaseId === "") {
            openAcquisitionProgress(stringValue(acquisition, "subscription_id", "subscriptionId"))
            return
        }
        if (root.stackView) {
            root.stackView.push(Qt.resolvedUrl("AcquisitionReviewView.qml"), {
                stackView: root.stackView,
                releaseId: releaseId,
                subscriptionId: stringValue(acquisition, "subscription_id", "subscriptionId")
            })
        }
        apiClient.fetchAcquisitionReleases("review_required", "", 50)
    }

    function handleEpisodePrimaryAction(episode) {
        var action = episodeRecoveryAction(episode)
        if (action === "review") {
            openEpisodeAcquisitionReview(episode)
            return
        }
        if (action === "view_progress") {
            var acquisition = episodeAcquisitionInfo(episode)
            openAcquisitionProgress(stringValue(acquisition, "subscription_id", "subscriptionId"))
            return
        }
        if (action === "get_episode" || action === "search_again" || action === "try_again") {
            openAcquisitionSheetForEpisode(episode)
        }
    }

    function acquisitionMediaType() {
        var type = displayType()
        if (type === "tv") {
            return "series"
        }
        return type === "anime" ? "anime" : "series"
    }

    function listValue(obj, snake, camel) {
        if (!obj) {
            return []
        }
        var value = obj[snake]
        if (value === undefined || value === null) {
            value = obj[camel]
        }
        return value === undefined || value === null ? [] : value
    }

    function sourceProvidersForDetails() {
        var type = acquisitionMediaType()
        var preferences = apiClient.mediaManagerPreferences || {}
        var providers = []
        if (type === "anime") {
            providers = listValue(preferences, "anime_source_providers", "animeSourceProviders")
            if (providers.length === 0) {
                providers = listValue(preferences, "anime_source_candidates", "animeSourceCandidates")
            }
        } else {
            providers = listValue(preferences, "series_source_providers", "seriesSourceProviders")
            if (providers.length === 0) {
                providers = listValue(preferences, "tv_source_providers", "tvSourceProviders")
            }
            if (providers.length === 0) {
                providers = listValue(preferences, "series_source_candidates", "seriesSourceCandidates")
            }
            if (providers.length === 0) {
                providers = listValue(preferences, "tv_source_candidates", "tvSourceCandidates")
            }
        }
        return providers
    }

    function preferencesObject() {
        var value = apiClient.mediaManagerPreferences.preferences
        if (value === undefined || value === null) {
            value = apiClient.mediaManagerPreferences.preferencesState
        }
        return value || {}
    }

    function preferredSourceProviderId() {
        var pref = preferencesObject()
        if (acquisitionMediaType() === "anime") {
            return String(pref.anime_source_provider_id || pref.animeSourceProviderId || "")
        }
        return String(pref.series_source_provider_id || pref.seriesSourceProviderId || "")
    }

    function providerId(provider) {
        return String(provider && (provider.providerId || provider.provider_id || provider.id) || "")
    }

    function providerLabel(provider) {
        if (!provider) {
            return ""
        }
        return String(provider.displayLabel || provider.display_label || provider.label || provider.name || provider.implementation || "Acquisition source")
    }

    function selectedSourceProviderIndex() {
        var providers = sourceProvidersForDetails()
        for (var i = 0; i < providers.length; ++i) {
            if (providerId(providers[i]) === selectedSourceProviderId) {
                return i
            }
        }
        return providers.length > 0 ? 0 : -1
    }

    function sourceProviderOptions() {
        var providers = sourceProvidersForDetails()
        var options = []
        for (var i = 0; i < providers.length; ++i) {
            options.push({
                id: providerId(providers[i]),
                label: providerLabel(providers[i])
            })
        }
        return options
    }

    function ensureSelectedSourceProvider() {
        var providers = sourceProvidersForDetails()
        if (providers.length === 0) {
            selectedSourceProviderId = ""
            return
        }
        for (var i = 0; i < providers.length; ++i) {
            if (providerId(providers[i]) === selectedSourceProviderId) {
                return
            }
        }
        var preferred = preferredSourceProviderId()
        if (preferred !== "") {
            for (var j = 0; j < providers.length; ++j) {
                if (providerId(providers[j]) === preferred) {
                    selectedSourceProviderId = preferred
                    return
                }
            }
        }
        selectedSourceProviderId = providerId(providers[0])
    }

    function sourceProviderDisabledReason() {
        ensureSelectedSourceProvider()
        if (sourceProvidersForDetails().length === 0) {
            return "Install or enable an acquisition source from Extensions."
        }
        if (selectedSourceProviderId === "") {
            return "Select an acquisition source."
        }
        return ""
    }

    function mediaItemForAcquisition() {
        var item = {}
        item.title = displayTitle()
        var year = displayYear()
        if (year !== "") {
            item.year = Number(year)
        }
        if (details && details.external_ids) {
            item.externalIds = details.external_ids
        } else if (details && details.externalIds) {
            item.externalIds = details.externalIds
        }
        return item
    }

    function episodeNumberValue(episode, snake, camel) {
        if (!episode) {
            return null
        }
        var value = episode[snake]
        if (value === undefined || value === null) {
            value = episode[camel]
        }
        if (value === undefined || value === null || value === "") {
            return null
        }
        return Number(value)
    }

    function targetKeyForEpisode(episode) {
        var season = episodeNumberValue(episode, "season_number", "seasonNumber")
        var episodeNo = episodeNumberValue(episode, "episode_number", "episodeNumber")
        var absoluteNo = episodeNumberValue(episode, "absolute_episode_number", "absoluteEpisodeNumber")
        if (season !== null && episodeNo !== null) {
            return "S" + String(season).padStart(2, "0") + "E" + String(episodeNo).padStart(2, "0")
        }
        if (absoluteNo !== null) {
            return "A" + String(absoluteNo).padStart(4, "0")
        }
        return episode && episode.id ? String(episode.id) : ""
    }

    function targetFromEpisode(episode) {
        var target = {
            targetKey: targetKeyForEpisode(episode),
            mediaType: acquisitionMediaType(),
            title: episode && episode.title ? episode.title : targetKeyForEpisode(episode),
            state: "pending",
            metadata: {
                mediaItemId: mediaId,
                libraryEpisodeId: episode && episode.id ? episode.id : ""
            }
        }
        var season = episodeNumberValue(episode, "season_number", "seasonNumber")
        var episodeNo = episodeNumberValue(episode, "episode_number", "episodeNumber")
        var absoluteNo = episodeNumberValue(episode, "absolute_episode_number", "absoluteEpisodeNumber")
        if (season !== null) {
            target.seasonNumber = season
        }
        if (episodeNo !== null) {
            target.episodeNumber = episodeNo
        }
        if (absoluteNo !== null) {
            target.absoluteEpisodeNumber = absoluteNo
        }
        return target
    }

    function missingEpisodesForActiveSeason() {
        return recoverableEpisodesForActiveSeason()
    }

    function acquisitionOptions(scope, target, targets, idempotencySuffix) {
        return {
            sourceProviderId: selectedSourceProviderId,
            routePolicy: "debrid_first",
            requestMode: "one_shot",
            requestScope: scope,
            metadataPolicy: "initial_only",
            completionPolicy: "terminal_selected_targets",
            monitorPolicy: "selected_targets",
            idempotencyKey: "one-shot:" + mediaId + ":" + idempotencySuffix + ":" + selectedSourceProviderId,
            target: target,
            targets: targets,
            scope: {
                requestedFrom: "media_detail",
                mediaItemId: mediaId,
                requestScope: scope,
                targetCount: targets.length
            }
        }
    }

    function buildPendingAcquisitionRequest(scope, title, items) {
        var reason = sourceProviderDisabledReason()
        if (reason !== "") {
            acquisitionSheetStatusText = reason
            return false
        }
        if (!items || items.length === 0) {
            acquisitionSheetStatusText = "No selectable missing, no-result, or failed episodes are visible in this season."
            return false
        }
        var targets = []
        var targetKeys = []
        for (var i = 0; i < items.length; ++i) {
            var target = targetFromEpisode(items[i])
            if (target.targetKey !== "") {
                targets.push(target)
                targetKeys.push(target.targetKey)
            }
        }
        if (targets.length === 0) {
            acquisitionSheetStatusText = "Episode metadata is missing stable target keys."
            return false
        }
        var seasonNumber = activeSeasonNumberValue()
        var requestTarget = {}
        if (scope === "episode") {
            requestTarget = {
                kind: "episode",
                targetKey: targets[0].targetKey,
                seasonNumber: targets[0].seasonNumber,
                episodeNumber: targets[0].episodeNumber,
                absoluteEpisodeNumber: targets[0].absoluteEpisodeNumber,
                title: targets[0].title,
                metadata: targets[0].metadata
            }
        } else {
            requestTarget = {
                kind: scope,
                metadata: {
                    mediaItemId: mediaId,
                    seasonId: activeSeasonId,
                    targetKeys: targetKeys
                }
            }
        }
        if ((scope === "season" || scope === "range" || scope === "selected_targets") && seasonNumber > 0) {
            requestTarget.seasonNumber = seasonNumber
        }
        pendingAcquisitionRequest = {
            scope: scope,
            title: title,
            target: requestTarget,
            targets: targets,
            targetKeys: targetKeys,
            idempotencySuffix: acquisitionIdempotencySuffix(scope, targetKeys)
        }
        acquisitionSheetStatusText = ""
        return true
    }

    function requestEpisodeAcquisition(episode) {
        openAcquisitionSheetForEpisode(episode)
    }

    function prepareScopedAcquisition(scope) {
        openAcquisitionSheetForSeason()
    }

    function prepareSelectedAcquisition() {
        acquisitionSheetScope = "selected_targets"
        submitAcquisitionSheet()
    }

    function prepareRangeAcquisition() {
        acquisitionSheetScope = "range"
        submitAcquisitionSheet()
    }

    function submitAcquisitionSheet() {
        var scope = acquisitionSheetScope
        var items = acquisitionSheetItemsForScope(scope)
        if (scope === "range" && items.length === 0) {
            acquisitionSheetStatusText = "Enter a range like 1 to 5 or S02E01 to S02E05 with missing, no-result, or failed episodes."
            return
        }
        if (scope === "selected_targets" && items.length === 0) {
            acquisitionSheetStatusText = "Select one or more episodes."
            return
        }
        if (!buildPendingAcquisitionRequest(scope, acquisitionSheetRequestTitle(scope), items)) {
            return
        }
        submitPendingAcquisitionRequest()
    }

    function submitPendingAcquisitionRequest() {
        if (!pendingAcquisitionRequest) {
            return
        }
        markPendingAcquisitionTargets(pendingAcquisitionRequest.targetKeys)
        acquisitionBusyKey = pendingAcquisitionRequest.scope === "episode" && pendingAcquisitionRequest.targetKeys.length === 1
                             ? pendingAcquisitionRequest.targetKeys[0]
                             : pendingAcquisitionRequest.scope + ":" + activeSeasonId + ":" + pendingAcquisitionRequest.idempotencySuffix
        acquisitionStatusText = ""
        apiClient.addMediaToAcquisition(
            acquisitionMediaType(),
            mediaItemForAcquisition(),
            acquisitionOptions(
                pendingAcquisitionRequest.scope,
                pendingAcquisitionRequest.target,
                pendingAcquisitionRequest.targets,
                pendingAcquisitionRequest.idempotencySuffix))
        if (pendingAcquisitionRequest.scope === "selected_targets" || pendingAcquisitionRequest.scope === "range") {
            clearRecoverySelection()
        }
        acquisitionSheetDialog.close()
    }

    function openEpisodeDeleteDialog(episode) {
        pendingEpisode = episode
        episodeStatusText = ""
        episodeDeleteDialog.open()
    }

    function refreshEpisodeState() {
        apiClient.fetchMediaDetails(mediaId)
        if (activeSeasonId !== "") {
            apiClient.fetchEpisodes(activeSeasonId)
        }
    }

    function resolveArtworkUrl(url) {
        if (!url || url === "") {
            return ""
        }
        if (url.indexOf("http://") === 0 || url.indexOf("https://") === 0) {
            return url
        }
        if (url.charAt(0) === "/" && apiClient && apiClient.baseUrl) {
            return apiClient.baseUrl + url
        }
        return url
    }

    function detailValue(obj, keys) {
        if (!obj || !keys) {
            return ""
        }
        for (var i = 0; i < keys.length; ++i) {
            var key = keys[i]
            if (obj[key] !== undefined && obj[key] !== null && obj[key] !== "") {
                return obj[key]
            }
        }
        return ""
    }

    function metadataPoster(meta) {
        if (!meta) {
            return ""
        }
        if (meta.coverImage && typeof meta.coverImage === "object") {
            return meta.coverImage.extraLarge || meta.coverImage.large || meta.coverImage.medium || ""
        }
        return meta.poster || meta.posterUrl || meta.poster_url || meta.image || ""
    }

    function metadataBanner(meta) {
        if (!meta) {
            return ""
        }
        return meta.backdrop || meta.background || meta.fanart || meta.bannerImage || meta.banner || ""
    }

    function posterSource() {
        var value = detailValue(details, ["poster_url", "posterUrl"])
        if (value !== "") {
            return resolveArtworkUrl(value)
        }
        var meta = details ? details.metadata : null
        value = metadataPoster(meta)
        if (value !== "") {
            return resolveArtworkUrl(value)
        }
        return libraryItem ? libraryItem.poster : ""
    }

    function bannerSource() {
        var value = detailValue(details, ["backdrop_url", "banner_url", "backdropUrl", "bannerUrl"])
        if (value !== "") {
            return resolveArtworkUrl(value)
        }
        var meta = details ? details.metadata : null
        value = metadataBanner(meta)
        if (value !== "") {
            return resolveArtworkUrl(value)
        }
        return libraryItem ? libraryItem.backdrop : ""
    }

    function artworkUrl(url, width, height) {
        var resolved = resolveArtworkUrl(url)
        if (!resolved || resolved === "") {
            return ""
        }
        var query = []
        if (width && width > 0) {
            query.push("w=" + width)
        }
        if (height && height > 0) {
            query.push("h=" + height)
        }
        if (query.length === 0) {
            return resolved
        }
        var sep = resolved.indexOf("?") >= 0 ? "&" : "?"
        return resolved + sep + query.join("&")
    }

    function displayTitle() {
        return details ? details.title : (libraryItem ? libraryItem.title : "Loading...")
    }

    function displayType() {
        return details && details.type ? details.type : (libraryItem && libraryItem.type ? libraryItem.type : "")
    }

    function displayYear() {
        var value = details && details.year ? details.year : (libraryItem && libraryItem.year ? libraryItem.year : "")
        return value ? String(value) : ""
    }

    function displayDescription() {
        if (details && details.description) {
            return details.description
        }
        return libraryItem && libraryItem.overview ? libraryItem.overview : ""
    }

    function displayRuntime() {
        var seconds = details && details.runtime_seconds ? details.runtime_seconds : (libraryItem && libraryItem.runtime ? libraryItem.runtime : 0)
        if (!seconds || seconds <= 0) {
            return ""
        }
        var minutes = Math.max(1, Math.round(seconds / 60))
        return minutes + " min"
    }

    function displayGenres() {
        var list = details && details.genres ? details.genres : (libraryItem ? libraryItem.genres : [])
        return list || []
    }

    function seasonTitle(season) {
        if (!season) {
            return "Episodes"
        }
        return season.title || ("Season " + season.season_number)
    }

    function activeSeasonTitle() {
        if (activeSeasonDetail) {
            return seasonTitle(activeSeasonDetail)
        }
        if (seasons) {
            for (var i = 0; i < seasons.length; ++i) {
                if (seasons[i].id === activeSeasonId) {
                    return seasonTitle(seasons[i])
                }
            }
        }
        return "Episodes"
    }

    function episodeTitle(episode) {
        if (!episode) {
            return "Episode"
        }
        var number = episode.episode_number ? (episode.episode_number + ". ") : ""
        return number + (episode.title || ("Episode " + episode.episode_number))
    }

    function resetSeasonState() {
        seasons = []
        episodes = []
        activeSeasonId = ""
        activeSeasonDetail = null
        seasonStatusText = ""
        seasonsLoading = false
        seasonLoading = false
        pendingSeasonId = ""
        clearRecoverySelection()
        clearPendingAcquisitionTargets()
        recoveryRangeStart = ""
        recoveryRangeEnd = ""
    }

    function selectSeason(seasonId) {
        if (!seasonId || seasonId === "" || seasonId === activeSeasonId) {
            return
        }
        activeSeasonId = seasonId
        activeSeasonDetail = null
        episodes = []
        seasonStatusText = ""
        seasonLoading = true
        pendingSeasonId = seasonId
        clearRecoverySelection()
        apiClient.fetchSeasonDetail(seasonId)
        apiClient.fetchEpisodes(seasonId)
    }

    function selectDefaultSeason() {
        if (!seasons || seasons.length === 0) {
            return
        }
        var chosen = null
        for (var i = 0; i < seasons.length; ++i) {
            if (seasons[i].has_files) {
                chosen = seasons[i]
                break
            }
        }
        if (!chosen) {
            chosen = seasons[0]
        }
        if (chosen && chosen.id) {
            selectSeason(chosen.id)
        }
    }

    Component.onCompleted: {
        if (mediaId !== "") {
            apiClient.fetchManagerPreferences()
            apiClient.fetchMediaDetails(mediaId)
            refreshReviewQueue()
        }
    }

    onMediaIdChanged: {
        if (mediaId !== "") {
            mediaSegmentAnalysisBusy = false
            mediaSegmentAnalysisStatusText = ""
            mediaSegmentDiagnostics = ({})
            mediaSegmentDiagnosticsLoading = false
            mediaSegmentDiagnosticsStatusText = ""
            mediaSegmentActionBusyId = ""
            watchStateBusy = false
            watchStateStatusText = ""
            episodeActionBusyId = ""
            episodeActionBusyAction = ""
            apiClient.fetchManagerPreferences()
            apiClient.fetchMediaDetails(mediaId)
            refreshReviewQueue()
            resetSeasonState()
        }
    }

    Timer {
        id: managerPreferencesPoll
        interval: 4000
        repeat: true
        running: root.visible && apiClient.authToken !== ""
        onTriggered: apiClient.fetchManagerPreferences()
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + Theme.space56
        clip: true

        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: Theme.space32

            DetailHero {
                Layout.fillWidth: true
                title: root.displayTitle()
                posterSource: root.artworkUrl(root.posterSource(), Theme.posterLargeWidth * 2, Theme.posterLargeHeight * 2)
                backdropSource: root.artworkUrl(root.bannerSource(), 2560, 1440)
                description: root.displayDescription()
                typeLabel: root.displayType()
                yearLabel: root.displayYear()
                runtimeLabel: root.displayRuntime()
                genres: root.displayGenres()
                busy: details === null || deleteBusy
                showRestoreBlocked: root.isSeriesType() && root.canRestoreBlockedEpisodes()
                onPlayRequested: apiClient.startPlayback(mediaId, "")
                onDeleteRequested: {
                    deleteStatusText = ""
                    deleteDialog.open()
                }
                onRestoreBlockedRequested: {
                    blockedEpisodesStatusText = ""
                    apiClient.restoreBlockedEpisodes(mediaId)
                }
                onBackRequested: {
                    if (root.stackView) {
                        root.stackView.pop()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space32
                Layout.rightMargin: Theme.space32
                implicitHeight: mediaSegmentPanel.implicitHeight + Theme.space20
                radius: Theme.radius8
                color: Theme.surface
                border.color: Theme.borderSubtle
                visible: root.canUseWatchStateActions()

                ColumnLayout {
                    id: mediaSegmentPanel
                    anchors.fill: parent
                    anchors.margins: Theme.space10
                    spacing: Theme.space10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space12

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                Layout.fillWidth: true
                                text: "Watch state"
                                color: Theme.textPrimary
                                font.pixelSize: 14
                                font.family: Theme.fontDisplay
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                text: root.watchStateStatusText !== ""
                                      ? root.watchStateStatusText
                                      : "Update this title without opening the player."
                                color: root.watchStateStatusText !== ""
                                       ? Theme.textSecondary
                                       : Theme.textMuted
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                elide: Text.ElideRight
                            }
                        }

                        ActionButton {
                            text: root.mediaSegmentAnalysisBusy ? "Queuing..." : "Analyze"
                            compact: true
                            visible: root.mediaSegmentSupportToolsEnabled
                            enabled: !root.mediaSegmentAnalysisBusy
                            onClicked: root.runMediaSegmentAnalysis(false)
                        }

                        ActionButton {
                            text: "Reanalyze"
                            compact: true
                            variant: "ghost"
                            visible: root.mediaSegmentSupportToolsEnabled
                            enabled: !root.mediaSegmentAnalysisBusy
                            onClicked: root.runMediaSegmentAnalysis(true)
                        }

                        ActionButton {
                            text: root.watchStateBusy ? "Saving..." : "Watched"
                            compact: true
                            variant: "ghost"
                            visible: root.canUseWatchStateActions()
                            enabled: !root.watchStateBusy
                            onClicked: root.runWatchStateAction("watched")
                        }

                        ActionButton {
                            text: "Unwatched"
                            compact: true
                            variant: "ghost"
                            visible: root.canUseWatchStateActions()
                            enabled: !root.watchStateBusy
                            onClicked: root.runWatchStateAction("unwatched")
                        }

                        ActionButton {
                            text: "Reset"
                            compact: true
                            variant: "ghost"
                            visible: root.canUseWatchStateActions()
                            enabled: !root.watchStateBusy
                            onClicked: root.runWatchStateAction("reset")
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.borderSubtle
                        visible: false
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space8
                        visible: root.mediaSegmentSupportToolsEnabled

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space8

                            Label {
                                Layout.fillWidth: true
                                text: "Active skip markers"
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontDisplay
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Label {
                                text: root.mediaSegmentActiveList().length + " active"
                                color: Theme.textMuted
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                visible: !root.mediaSegmentDiagnosticsLoading
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.mediaSegmentDiagnosticsLoading
                                  ? "Loading markers..."
                                  : (root.mediaSegmentDiagnosticsStatusText !== ""
                                     ? root.mediaSegmentDiagnosticsStatusText
                                     : "No active skip markers.")
                            color: root.mediaSegmentDiagnosticsStatusText !== ""
                                   ? Theme.textSecondary
                                   : Theme.textMuted
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            wrapMode: Text.Wrap
                            visible: root.mediaSegmentDiagnosticsLoading ||
                                     root.mediaSegmentDiagnosticsStatusText !== "" ||
                                     root.mediaSegmentActiveList().length === 0
                        }

                        Repeater {
                            model: root.mediaSegmentActiveList()

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: mediaSegmentMarkerRow.implicitHeight + Theme.space8
                                radius: Theme.radius6
                                color: Theme.surfaceRaised
                                border.color: Theme.borderSubtle

                                RowLayout {
                                    id: mediaSegmentMarkerRow
                                    anchors.fill: parent
                                    anchors.margins: Theme.space6
                                    spacing: Theme.space10

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.mediaSegmentTypeLabel(modelData) + "  " +
                                                  root.mediaSegmentRangeText(modelData)
                                            color: Theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: Theme.fontBody
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.mediaSegmentSourceText(modelData)
                                            color: Theme.textMuted
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                            elide: Text.ElideRight
                                        }
                                    }

                                    ActionButton {
                                        text: root.mediaSegmentActionBusyId === String(modelData.id || "")
                                              ? "Saving..."
                                              : "Disable"
                                        compact: true
                                        variant: "danger"
                                        enabled: root.mediaSegmentActionBusyId === ""
                                        onClicked: root.disableMediaSegmentMarker(modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            InlineToast {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space32
                Layout.rightMargin: Theme.space32
                text: blockedEpisodesStatusText
                autoClear: false
                visible: blockedEpisodesStatusText !== ""
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
                wrapMode: Text.Wrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space32
                Layout.rightMargin: Theme.space32
                Layout.preferredHeight: 132
                radius: Theme.radius8
                color: Theme.surface
                border.color: Theme.borderSubtle
                visible: statusText !== "" && details === null

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.space20
                    spacing: Theme.space12

                    Label {
                        text: "Unable to load details"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                        font.weight: Font.DemiBold
                    }

                    InlineToast {
                        text: statusText
                        autoClear: false
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }

                    ActionButton {
                        text: "Retry"
                        compact: true
                        onClicked: apiClient.fetchMediaDetails(mediaId)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space32
                Layout.rightMargin: Theme.space32
                spacing: Theme.space16
                visible: root.isSeriesType() && details !== null

                SectionHeader {
                    Layout.fillWidth: true
                    title: root.activeSeasonTitle()
                    subtitle: root.seasonLoading ? "Loading episodes..." : seasonStatusText
                }

                SeasonTabs {
                    Layout.fillWidth: true
                    visible: seasons && seasons.length > 0
                    seasons: root.seasons
                    activeSeasonId: root.activeSeasonId
                    onSeasonSelected: root.selectSeason(seasonId)
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: seasonIssueRow.implicitHeight + Theme.space16
                    radius: Theme.radius6
                    color: Theme.panelSoft
                    border.color: Theme.borderSubtle
                    visible: !root.seasonLoading
                             && !root.seasonsLoading
                             && root.seasonIssueCount() > 0

                    RowLayout {
                        id: seasonIssueRow
                        anchors.fill: parent
                        anchors.margins: Theme.space8
                        spacing: Theme.space10

                        Rectangle {
                            Layout.preferredWidth: 8
                            Layout.fillHeight: true
                            radius: 4
                            color: Theme.accent
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                text: root.formatEpisodeCount(root.seasonIssueCount()) + " need sources"
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontBody
                                font.weight: Font.DemiBold
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Label {
                                text: root.seasonIssueSummary()
                                color: Theme.textSecondary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        ActionButton {
                            text: root.acquisitionBusyKey !== "" ? "Requesting..." : "Find"
                            compact: true
                            variant: "primary"
                            Layout.preferredWidth: 96
                            enabled: root.acquisitionBusyKey === ""
                            onClicked: root.openAcquisitionSheetForSeason()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: loadingPanel.implicitHeight + Theme.space24
                    radius: Theme.radius8
                    color: Theme.surface
                    border.color: Theme.borderSubtle
                    visible: root.seasonLoading || (root.seasonsLoading && (!seasons || seasons.length === 0))

                    ColumnLayout {
                        id: loadingPanel
                        anchors.fill: parent
                        anchors.margins: Theme.space12
                        spacing: Theme.space12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space10

                            BusyIndicator {
                                running: root.seasonLoading || root.seasonsLoading
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Label {
                                    text: root.seasonLoading ? "Loading episodes" : "Loading seasons"
                                    color: Theme.textPrimary
                                    font.pixelSize: 15
                                    font.family: Theme.fontDisplay
                                    font.weight: Font.DemiBold
                                }

                                Label {
                                    text: root.seasonLoading
                                          ? "Preparing the selected season."
                                          : "Preparing the season list."
                                    color: Theme.textSecondary
                                    font.pixelSize: 12
                                    font.family: Theme.fontBody
                                }
                            }
                        }

                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 36
                                radius: Theme.radiusSmall
                                color: Theme.panelSoft
                                border.color: Theme.borderSubtle

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.space12
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(96, parent.width * (0.36 + index * 0.08))
                                    height: 8
                                    radius: 4
                                    color: Theme.surfaceHover
                                    opacity: 0.75
                                }
                            }
                        }
                    }
                }

                EmptyState {
                    Layout.fillWidth: true
                    implicitHeight: 132
                    visible: !root.seasonLoading
                             && !root.seasonsLoading
                             && (!episodes || episodes.length === 0)
                             && seasonStatusText === ""
                    title: seasons && seasons.length > 0 ? "No episodes in this season" : "No seasons found"
                    message: seasons && seasons.length > 0 ? "Episodes will appear here when metadata is available." : ""
                }

                Repeater {
                    model: episodes ? episodes : []
                    delegate: EpisodeCard {
                        Layout.fillWidth: true
                        title: root.episodeTitle(modelData)
                        description: modelData.description || ""
                        thumbnail: root.artworkUrl(modelData.thumbnail_url || modelData.thumbnailUrl || "", Theme.episodeThumbWidth * 2, Theme.episodeThumbHeight * 2)
                        statusText: root.episodeStatusLabel(modelData)
                        statusMessage: root.episodeRecoveryMessage(modelData)
                        recoveryState: root.episodeRecoveryState(modelData)
                        available: root.episodeRecoveryState(modelData) === "available"
                        blocked: root.episodeBlocked(modelData)
                        canDelete: root.episodeCanDelete(modelData)
                        canRestore: root.episodeCanRestore(modelData)
                        canAcquire: root.episodeCanUsePrimaryAction(modelData)
                                    && root.episodeRecoveryState(modelData) !== "available"
                                    && root.episodeRecoveryState(modelData) !== "blocked"
                        watchStateText: root.episodeWatchStateText(modelData)
                        watchStateWatched: root.episodeWatched(modelData)
                        canMarkWatched: root.episodeRecoveryState(modelData) === "available"
                                        && !root.episodeWatched(modelData)
                        canMarkUnwatched: root.episodeRecoveryState(modelData) === "available"
                                          && root.episodeWatched(modelData)
                        canResetProgress: root.episodeRecoveryState(modelData) === "available"
                                          && root.episodeResumeSeconds(modelData) >= 30
                        selectable: root.episodeCanRequeue(modelData)
                        selected: root.episodeSelected(modelData)
                        acquireText: root.episodePrimaryActionText(modelData)
                        busy: root.episodeActionBusyId === modelData.id
                              || root.acquisitionBusyKey === root.targetKeyForEpisode(modelData)
                              || root.targetKeyPending(modelData)
                        busyAction: root.episodeActionBusyId === modelData.id
                                    ? root.episodeActionBusyAction
                                    : ""
                        onPlayRequested: apiClient.startEpisodePlayback(mediaId, modelData.id)
                        onDeleteRequested: root.openEpisodeDeleteDialog(modelData)
                        onRestoreRequested: {
                            episodeActionBusyId = modelData.id
                            episodeActionBusyAction = ""
                            episodeStatusText = ""
                            apiClient.restoreEpisode(modelData.id)
                        }
                        onAcquireRequested: root.handleEpisodePrimaryAction(modelData)
                        onMarkWatchedRequested: root.runEpisodeWatchStateAction(modelData, "watched")
                        onMarkUnwatchedRequested: root.runEpisodeWatchStateAction(modelData, "unwatched")
                        onResetProgressRequested: root.runEpisodeWatchStateAction(modelData, "reset")
                        onSelectionToggled: function(selected) {
                            root.setEpisodeSelected(modelData, selected)
                        }
                    }
                }

                InlineToast {
                    Layout.fillWidth: true
                    text: episodeStatusText
                    autoClear: false
                    visible: episodeStatusText !== ""
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                    wrapMode: Text.Wrap
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.space32
                Layout.rightMargin: Theme.space32
                visible: details && details.files && details.files.length > 0
                spacing: Theme.space12

                SectionHeader {
                    Layout.fillWidth: true
                    title: "Files"
                }

                Repeater {
                    model: details && details.files ? details.files : []
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 72
                        radius: Theme.radius6
                        color: Qt.rgba(1, 1, 1, 0.045)
                        border.color: Qt.rgba(1, 1, 1, 0.08)

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.space12
                            spacing: Theme.space12

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label {
                                    text: modelData.path
                                    color: Theme.textPrimary
                                    font.pixelSize: 12
                                    font.family: Theme.fontBody
                                    elide: Text.ElideMiddle
                                    Layout.fillWidth: true
                                }
                                Label {
                                    text: (modelData.container || "") + " / " + (modelData.video_codec || "?") + " / " + (modelData.audio_codec || "?")
                                    color: Theme.textSecondary
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            ActionButton {
                                text: "Play file"
                                compact: true
                                enabled: modelData.scan_state !== "missing"
                                onClicked: apiClient.startPlayback(mediaId, modelData.id)
                            }

                            ActionButton {
                                text: "Fix Match"
                                compact: true
                                visible: root.reviewEntryForFile(modelData.id) !== null
                                onClicked: root.openReviewForFile(modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: acquisitionSheetDialog
        modal: true
        x: (parent.width - width) / 2
        y: Math.max(Theme.spacingLarge, (parent.height - height) / 2)
        width: Math.min(parent.width * 0.9, 720)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        onClosed: {
            acquisitionSheetStatusText = ""
            pendingAcquisitionRequest = null
        }

        background: Rectangle {
            color: Theme.backgroundCard
            radius: Theme.radiusLarge
            border.color: Theme.border
        }

        contentItem: ColumnLayout {
            spacing: Theme.space16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Label {
                    text: "Find Episodes"
                    color: Theme.textPrimary
                    font.pixelSize: 20
                    font.family: Theme.fontDisplay
                    font.weight: Font.DemiBold
                }

                Label {
                    Layout.fillWidth: true
                    text: "Choose the exact scope for this one-time search. Elixir will only queue the selected targets."
                    color: Theme.textSecondary
                    font.pixelSize: 13
                    font.family: Theme.fontBody
                    wrapMode: Text.Wrap
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 56
                radius: Theme.radius6
                color: Theme.panelSoft
                border.color: Theme.borderSubtle

                RowLayout {
                    id: sourceSelectorRow
                    anchors.fill: parent
                    anchors.margins: Theme.space10
                    spacing: Theme.space12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Label {
                            text: "Source"
                            color: Theme.textPrimary
                            font.pixelSize: 13
                            font.family: Theme.fontBody
                            font.weight: Font.DemiBold
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.sourceProviderOptions().length > 0
                                  ? "Searches use this installed source extension."
                                  : "Install or enable a source extension before starting a search."
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            elide: Text.ElideRight
                        }
                    }

                    ComboBox {
                        id: acquisitionSheetSourceCombo
                        Layout.preferredWidth: 280
                        model: root.sourceProviderOptions()
                        textRole: "label"
                        valueRole: "id"
                        currentIndex: root.selectedSourceProviderIndex()
                        visible: root.sourceProviderOptions().length > 1
                        enabled: root.acquisitionBusyKey === ""
                        contentItem: Label {
                            leftPadding: 10
                            rightPadding: 26
                            text: acquisitionSheetSourceCombo.displayText
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        onActivated: function(index) {
                            var options = root.sourceProviderOptions()
                            if (index >= 0 && index < options.length) {
                                root.selectedSourceProviderId = String(options[index].id || "")
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredHeight: 30
                        Layout.preferredWidth: Math.min(280, Math.max(sourceLabel.implicitWidth + Theme.space20, 150))
                        radius: Theme.radiusSmall
                        color: root.sourceProviderOptions().length === 0 ? Theme.accentDangerSoft : Theme.surfaceRaised
                        border.color: root.sourceProviderOptions().length === 0 ? Theme.accentDanger : Theme.borderSubtle
                        visible: root.sourceProviderOptions().length <= 1

                        Label {
                            id: sourceLabel
                            anchors.centerIn: parent
                            width: parent.width - Theme.space16
                            text: root.sourceProviderOptions().length === 1
                                  ? root.sourceProviderOptions()[0].label
                                  : "No source installed"
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Flow {
                id: scopeFlow
                Layout.fillWidth: true
                spacing: Theme.space8

                Repeater {
                    model: root.acquisitionSheetScopeOptions()
                    delegate: Rectangle {
                        width: Math.min(320, Math.max(220, (scopeFlow.width - Theme.space8) / 2))
                        height: 76
                        radius: Theme.radius6
                        color: root.acquisitionSheetScope === modelData.id ? Theme.surfaceHover : Theme.panelSoft
                        border.color: root.acquisitionSheetScope === modelData.id
                                      ? Theme.accent
                                      : (modelData.enabled ? Theme.borderSubtle : Theme.textDisabled)
                        opacity: modelData.enabled ? 1.0 : 0.48

                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.enabled && root.acquisitionBusyKey === ""
                            onClicked: {
                                root.acquisitionSheetScope = modelData.id
                                root.acquisitionSheetStatusText = ""
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.space10
                            spacing: 4

                            Label {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontBody
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Label {
                                Layout.fillWidth: true
                                text: modelData.enabled ? modelData.detail : modelData.reason
                                color: Theme.textSecondary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                visible: root.acquisitionSheetScope === "range"

                Label {
                    text: "Episode range"
                    color: Theme.textPrimary
                    font.pixelSize: 13
                    font.family: Theme.fontBody
                    font.weight: Font.DemiBold
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space8

                    TextField {
                        Layout.preferredWidth: 128
                        text: root.recoveryRangeStart
                        placeholderText: "From"
                        color: Theme.textPrimary
                        placeholderTextColor: Theme.textMuted
                        selectionColor: Theme.accent
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        onTextChanged: root.recoveryRangeStart = text
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                    }

                    TextField {
                        Layout.preferredWidth: 128
                        text: root.recoveryRangeEnd
                        placeholderText: "To"
                        color: Theme.textPrimary
                        placeholderTextColor: Theme.textMuted
                        selectionColor: Theme.accent
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        onTextChanged: root.recoveryRangeEnd = text
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: "Use numbers like 647 or ranges like S01E640 to S01E660."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        wrapMode: Text.Wrap
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                visible: root.acquisitionSheetScope === "selected_targets"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space8

                    ActionButton {
                        text: "All"
                        compact: true
                        onClicked: root.setRecoverySelectionFromEpisodes(root.recoverableEpisodesForActiveSeason())
                    }
                    ActionButton {
                        text: "No results"
                        compact: true
                        onClicked: root.setRecoverySelectionFromEpisodes(root.recoverableEpisodesByState("no_results"))
                    }
                    ActionButton {
                        text: "Failed"
                        compact: true
                        onClicked: root.setRecoverySelectionFromEpisodes(root.recoverableEpisodesByState("failed"))
                    }
                    ActionButton {
                        text: "Missing"
                        compact: true
                        onClicked: root.setRecoverySelectionFromEpisodes(root.recoverableEpisodesByState("missing"))
                    }
                    ActionButton {
                        text: "Clear"
                        compact: true
                        onClicked: root.clearRecoverySelection()
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: root.selectedRecoveryCount() + " selected"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }
                }

                ScrollView {
                    id: selectedEpisodesScroll
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(220, Math.max(92, root.recoverableEpisodesForActiveSeason().length * 38))
                    clip: true
                    contentWidth: availableWidth
                    contentHeight: selectedEpisodesColumn.implicitHeight
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical.policy: contentHeight > height + 1
                                               ? ScrollBar.AsNeeded
                                               : ScrollBar.AlwaysOff
                    ScrollBar.vertical.interactive: true
                    ScrollBar.vertical.width: 6
                    ScrollBar.vertical.contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: selectedEpisodesScroll.ScrollBar.vertical.pressed
                               ? Theme.textSecondary
                               : Qt.rgba(1, 1, 1, selectedEpisodesScroll.ScrollBar.vertical.active ? 0.34 : 0.18)
                    }
                    background: Rectangle {
                        color: "transparent"
                    }

                    ColumnLayout {
                        id: selectedEpisodesColumn
                        width: selectedEpisodesScroll.availableWidth
                        spacing: Theme.space4

                        Repeater {
                            model: root.recoverableEpisodesForActiveSeason()
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: Theme.radiusSmall
                                color: root.episodeSelected(modelData) ? Theme.surfaceHover : Theme.panelSoft
                                border.color: root.episodeSelected(modelData) ? Theme.accent : Theme.borderSubtle

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space8
                                    anchors.rightMargin: Theme.space8
                                    spacing: Theme.space8

                                    CheckBox {
                                        checked: root.episodeSelected(modelData)
                                        onToggled: root.setEpisodeSelected(modelData, checked)
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.episodeSheetLabel(modelData)
                                        color: Theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: Theme.fontBody
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        text: root.episodeRecoveryLabel(modelData)
                                        color: Theme.textSecondary
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                    }
                                }
                            }
                        }
                    }
                }
            }

            InlineToast {
                Layout.fillWidth: true
                text: root.acquisitionSheetStatusText !== ""
                      ? root.acquisitionSheetStatusText
                      : root.acquisitionSheetSummary()
                autoClear: false
                color: root.sourceProviderDisabledReason() === "" ? Theme.textSecondary : Theme.accentDanger
                font.pixelSize: 12
                font.family: Theme.fontBody
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8

                ActionButton {
                    text: "Cancel"
                    compact: true
                    enabled: root.acquisitionBusyKey === ""
                    onClicked: acquisitionSheetDialog.close()
                }

                Item { Layout.fillWidth: true }

                ActionButton {
                    text: root.acquisitionBusyKey !== "" ? "Requesting..." : "Start search"
                    compact: true
                    variant: "primary"
                    Layout.preferredWidth: 136
                    enabled: root.acquisitionSheetCanSubmit()
                    onClicked: root.submitAcquisitionSheet()
                }
            }
        }
    }

    Dialog {
        id: episodeDeleteDialog
        modal: true
        x: (parent.width - width) / 2
        y: Math.max(Theme.spacingLarge, (parent.height - height) / 2)
        width: Math.min(parent.width * 0.88, 560)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Theme.backgroundCard
            radius: Theme.radiusLarge
            border.color: Theme.border
        }

        contentItem: ColumnLayout {
            spacing: Theme.spacingMedium

            Label {
                text: pendingEpisode
                      ? ("Delete S" + String(pendingEpisode.season_number).padStart(2, "0")
                         + "E" + String(pendingEpisode.episode_number).padStart(2, "0"))
                      : "Delete episode"
                color: Theme.textPrimary
                font.pixelSize: 18
                font.family: Theme.fontDisplay
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.textSecondary
                font.pixelSize: 13
                font.family: Theme.fontBody
                text: "Delete this episode from Elixir only. You can either remove it locally and allow it to come back later, or block just this episode in Elixir without changing Sonarr."
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Button {
                    text: "Cancel"
                    enabled: episodeActionBusyId === ""
                    onClicked: episodeDeleteDialog.close()
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

                Item { Layout.fillWidth: true }

                Button {
                    text: episodeActionBusyId !== "" ? "Working..." : "Delete locally"
                    enabled: pendingEpisode && episodeActionBusyId === ""
                    onClicked: {
                        if (!pendingEpisode) {
                            return
                        }
                        episodeActionBusyId = pendingEpisode.id
                        episodeActionBusyAction = ""
                        episodeStatusText = ""
                        apiClient.deleteEpisode(pendingEpisode.id, false)
                    }
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: "#5a2b2b"
                        border.color: "#8d4a4a"
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
                    visible: pendingEpisode && episodeCanBlock(pendingEpisode)
                    text: episodeActionBusyId !== "" ? "Working..." : "Delete + Block"
                    enabled: pendingEpisode && episodeActionBusyId === ""
                    onClicked: {
                        if (!pendingEpisode) {
                            return
                        }
                        episodeActionBusyId = pendingEpisode.id
                        episodeActionBusyAction = ""
                        episodeStatusText = ""
                        apiClient.deleteEpisode(pendingEpisode.id, true)
                    }
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.accent
                    }
                    contentItem: Label {
                        text: parent.text
                        color: "#111111"
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteDialog
        modal: true
        x: (parent.width - width) / 2
        y: Math.max(Theme.spacingLarge, (parent.height - height) / 2)
        width: Math.min(parent.width * 0.88, 560)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Theme.backgroundCard
            radius: Theme.radiusLarge
            border.color: Theme.border
        }

        contentItem: ColumnLayout {
            spacing: Theme.spacingMedium

            Label {
                text: "Delete " + deleteTargetLabel()
                color: Theme.textPrimary
                font.pixelSize: 18
                font.family: Theme.fontDisplay
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.textSecondary
                font.pixelSize: 13
                font.family: Theme.fontBody
                text: canStopTracking()
                      ? ("Delete this " + deleteTargetLabel() + " from Elixir. If you also stop tracking, "
                         + "the owner will stop monitoring it and Elixir will block future re-imports until you add it again.")
                      : ("Delete this " + deleteTargetLabel() + " from Elixir. This removes the local library entry and its files from disk.")
            }

            InlineToast {
                Layout.fillWidth: true
                text: deleteStatusText
                autoClear: false
                visible: deleteStatusText !== ""
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Button {
                    text: "Cancel"
                    enabled: !deleteBusy
                    onClicked: deleteDialog.close()
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

                Item { Layout.fillWidth: true }

                Button {
                    text: deleteBusy ? "Deleting..." : "Delete from Elixir"
                    enabled: !deleteBusy
                    onClicked: {
                        deleteBusy = true
                        deleteStatusText = ""
                        apiClient.deleteLibraryItemWithAction(mediaId, "delete_local_only", false)
                    }
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: "#5a2b2b"
                        border.color: "#8d4a4a"
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
                    visible: canStopTracking()
                    text: deleteBusy ? "Working..." : ("Delete + " + ownerReleaseButtonLabel())
                    enabled: !deleteBusy
                    onClicked: {
                        deleteBusy = true
                        deleteStatusText = ""
                        apiClient.deleteLibraryItemWithAction(mediaId, "delete_and_release_owner", false)
                    }
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.accent
                    }
                    contentItem: Label {
                        text: parent.text
                        color: "#111111"
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteResultDialog
        modal: true
        x: (parent.width - width) / 2
        y: Math.max(Theme.spacingLarge, (parent.height - height) / 2)
        width: Math.min(parent.width * 0.72, 420)
        closePolicy: Popup.NoAutoClose

        background: Rectangle {
            color: Theme.backgroundCard
            radius: Theme.radiusLarge
            border.color: Theme.border
        }

        contentItem: ColumnLayout {
            spacing: Theme.spacingMedium

            Label {
                text: "Delete complete"
                color: Theme.textPrimary
                font.pixelSize: 18
                font.family: Theme.fontDisplay
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.textSecondary
                font.pixelSize: 13
                font.family: Theme.fontBody
                text: deleteResultText
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button {
                    text: "Back to library"
                    onClicked: {
                        deleteResultDialog.close()
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

    Dialog {
        id: reviewDialog
        modal: true
        x: (parent.width - width) / 2
        y: Math.max(Theme.spacingLarge, (parent.height - height) / 2)
        width: Math.min(parent.width * 0.9, 720)
        height: Math.min(parent.height * 0.9, 540)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Theme.backgroundCard
            radius: Theme.radiusLarge
            border.color: Theme.border
        }

        contentItem: Flickable {
            clip: true
            contentWidth: width
            contentHeight: dialogContent.implicitHeight + Theme.spacingLarge

            ColumnLayout {
                id: dialogContent
                width: parent.width
                spacing: Theme.spacingMedium
                anchors.margins: Theme.spacingLarge

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall
                    Label {
                        text: "Fix Match"
                        color: Theme.textPrimary
                        font.pixelSize: 18
                        font.family: Theme.fontDisplay
                    }
                    Item { Layout.fillWidth: true }
                    Button {
                        text: "Close"
                        onClicked: reviewDialog.close()
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

                Rectangle {
                    Layout.fillWidth: true
                    radius: Theme.radiusMedium
                    color: Theme.backgroundCardRaised
                    border.color: Theme.border

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingMedium
                        spacing: Theme.spacingSmall

                        Label {
                            text: "Current match"
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                        }

                        Label {
                            text: activeReview && activeReview.current_match
                                  ? (activeReview.current_match.title + " (" + (activeReview.current_match.kind || "") + ")")
                                  : "Unmatched"
                            color: Theme.textPrimary
                            font.pixelSize: 14
                            font.family: Theme.fontDisplay
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    radius: Theme.radiusMedium
                    color: Theme.backgroundCardRaised
                    border.color: Theme.border

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingMedium
                        spacing: Theme.spacingSmall

                        Label {
                            text: "Candidates"
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                        }

                        Repeater {
                            model: normalizeCandidates(activeReview)
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCard
                                border.color: Theme.border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingMedium
                                    spacing: Theme.spacingMedium

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label {
                                            text: candidateTitle(modelData)
                                            color: Theme.textPrimary
                                            font.pixelSize: 13
                                            font.family: Theme.fontBody
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            text: idsLabel(modelData.ids || modelData.external_ids || modelData.externalIds || modelData)
                                            color: Theme.textMuted
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            text: modelData.provider ? ("Source: " + modelData.provider) : ""
                                            color: Theme.textMuted
                                            font.pixelSize: 10
                                            font.family: Theme.fontBody
                                            visible: text !== ""
                                        }
                                    }

                                    Button {
                                        text: "Apply"
                                        enabled: Object.keys(externalIdsFromCandidate(modelData)).length > 0
                                        onClicked: {
                                            var ids = externalIdsFromCandidate(modelData)
                                            apiClient.applyReviewMatch(activeReviewId, details ? details.type : (libraryItem ? libraryItem.type : ""), ids, "")
                                        }
                                        background: Rectangle {
                                            radius: Theme.radiusSmall
                                            color: Theme.accent
                                        }
                                        contentItem: Label {
                                            text: parent.text
                                            color: "#111111"
                                            font.pixelSize: 12
                                            font.family: Theme.fontBody
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }
                        }

                        Label {
                            text: "No candidates available."
                            color: Theme.textMuted
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            visible: normalizeCandidates(activeReview).length === 0
                        }
                    }
                }

                InlineToast {
                    text: reviewStatusText
                    autoClear: false
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                }
            }
        }
    }

    Connections {
        target: apiClient
        function onMediaDetailsReceived(obj) {
            if (obj.id === mediaId) {
                details = obj
                statusText = ""
                refreshReviewQueue()
                if (isSeriesType()) {
                    seasonsLoading = true
                    apiClient.fetchSeasons(obj.id)
                } else {
                    resetSeasonState()
                }
            }
        }
        function onMediaSegmentAnalysisCompleted(itemId, summary) {
            if (itemId !== mediaId) {
                return
            }
            mediaSegmentAnalysisBusy = false
            mediaSegmentAnalysisStatusText = root.mediaSegmentAnalysisResultText(summary)
            refreshMediaSegmentDiagnostics()
        }
        function onItemMediaSegmentsReceived(itemId, itemType, segments) {
            if (itemId !== mediaId) {
                return
            }
            mediaSegmentDiagnostics = segments || ({})
            mediaSegmentDiagnosticsLoading = false
            if (mediaSegmentDiagnosticsStatusText.indexOf("Skip marker") !== 0) {
                mediaSegmentDiagnosticsStatusText = ""
            }
        }
        function onMediaSegmentDisabled(segmentId, result) {
            if (segmentId !== mediaSegmentActionBusyId) {
                return
            }
            mediaSegmentActionBusyId = ""
            mediaSegmentDiagnosticsStatusText = result && result.disabled
                                                ? "Skip marker disabled."
                                                : "Skip marker was already inactive."
            refreshMediaSegmentDiagnostics(true)
        }
        function onMediaWatchStateUpdated(itemId, itemType, action, playbackState) {
            if (itemType === "episode") {
                if (episodeActionBusyId !== "" && itemId !== episodeActionBusyId) {
                    return
                }
                episodeActionBusyId = ""
                episodeActionBusyAction = ""
                episodeStatusText = root.watchStateActionResultText(action, playbackState)
                refreshEpisodeState()
                apiClient.fetchLibrary()
                return
            }
            if (itemId !== mediaId) {
                return
            }
            watchStateBusy = false
            watchStateStatusText = root.watchStateActionResultText(action, playbackState)
            apiClient.fetchLibrary()
            apiClient.fetchMediaDetails(mediaId)
        }
        function onMediaItemDeleted(deletedId, result) {
            if (deletedId !== mediaId) {
                return
            }
            deleteBusy = false
            deleteDialog.close()
            deleteResultText = result && result.message ? result.message : "Deleted."
            deleteResultDialog.open()
        }
        function onEpisodeDeleted(episodeId, result) {
            episodeActionBusyId = ""
            episodeActionBusyAction = ""
            episodeDeleteDialog.close()
            pendingEpisode = null
            episodeStatusText = result && result.message ? result.message : "Episode deleted."
            refreshEpisodeState()
        }
        function onEpisodeRestored(episodeId, result) {
            episodeActionBusyId = ""
            episodeActionBusyAction = ""
            episodeStatusText = result && result.message ? result.message : "Episode restored."
            refreshEpisodeState()
        }
        function onBlockedEpisodesRestored(itemId, result) {
            if (itemId !== mediaId) {
                return
            }
            blockedEpisodesStatusText = result && result.message ? result.message : "Blocked episodes restored."
            refreshEpisodeState()
        }
        function onSeasonsReceived(seriesId, items) {
            if (seriesId !== mediaId) {
                return
            }
            seasonsLoading = false
            seasons = items
            selectDefaultSeason()
        }
        function onSeasonDetailReceived(seasonId, detail) {
            if (seasonId === activeSeasonId) {
                activeSeasonDetail = detail
            }
        }
        function onEpisodesReceived(seasonId, items) {
            if (seasonId === activeSeasonId) {
                reconcilePendingAcquisitionTargets(items)
                episodes = items
                seasonLoading = false
                pendingSeasonId = ""
                seasonStatusText = ""
            }
        }
        function onMediaManagerPreferencesChanged() {
            root.ensureSelectedSourceProvider()
        }
        function onMediaAddResultChanged() {
            if (!apiClient.mediaAddResult.nativeAcquisition) {
                return
            }
            acquisitionBusyKey = ""
            pendingAcquisitionRequest = null
            var mode = String(apiClient.mediaAddResult.requestMode || "")
            var scope = String(apiClient.mediaAddResult.requestScope || "")
            if (mode === "one_shot") {
                pendingAcquisitionTargetsRefreshArmed = true
                acquisitionStatusText = scope === "episode"
                                        ? "One-time episode request queued."
                                        : "One-time request queued."
                apiClient.fetchMediaAcquisition()
                refreshEpisodeState()
            }
        }
        function onMediaAddLoadingChanged() {
            if (!apiClient.mediaAddLoading && acquisitionBusyKey !== "" && acquisitionStatusText === "") {
                acquisitionBusyKey = ""
            }
        }
        function onMediaAcquisitionChanged() {
            if (!root.visible) {
                return
            }
            if (root.isSeriesType() && activeSeasonId !== "") {
                apiClient.fetchEpisodes(activeSeasonId)
            }
        }
        function onReviewQueueReceived(items) {
            reviewQueue = items
        }
        function onReviewDetailReceived(detail) {
            if (detail && detail.id === activeReviewId) {
                activeReview = detail
            }
        }
        function onReviewApplied(reviewId) {
            if (reviewId === activeReviewId) {
                reviewStatusText = "Match applied."
                apiClient.fetchMediaDetails(mediaId)
                refreshReviewQueue()
            }
        }
        function onRequestFailed(endpoint, error) {
            if (endpoint === "/api/v1/library/items/" + mediaId && deleteBusy) {
                deleteBusy = false
                deleteStatusText = "Delete failed: " + error
                return
            }
            if (endpoint.indexOf("/api/v1/library/episodes/") === 0) {
                episodeActionBusyId = ""
                episodeActionBusyAction = ""
                episodeStatusText = "Episode action failed: " + error
                return
            }
            if (endpoint === "/api/v1/library/items/" + mediaId + "/restore-blocked-episodes") {
                blockedEpisodesStatusText = "Restore failed: " + error
                return
            }
            if (endpoint.indexOf("/api/v1/items/") === 0 &&
                    endpoint.indexOf("/media-segment-jobs/analyze") > 0) {
                mediaSegmentAnalysisBusy = false
                mediaSegmentAnalysisStatusText = "Analysis failed: " + error
                return
            }
            if (endpoint.indexOf("/api/v1/items/") === 0 &&
                    endpoint.indexOf("/segments") > 0) {
                mediaSegmentDiagnosticsLoading = false
                mediaSegmentDiagnosticsStatusText = "Marker load failed: " + error
                return
            }
            if (endpoint.indexOf("/api/v1/media-segments/") === 0 &&
                    endpoint.indexOf("/disable") > 0) {
                mediaSegmentActionBusyId = ""
                mediaSegmentDiagnosticsStatusText = "Disable failed: " + error
                return
            }
            if (endpoint.indexOf("/api/v1/items/") === 0 &&
                    endpoint.indexOf("/watch-state") > 0) {
                if (endpoint.indexOf("/api/v1/items/episode/") === 0) {
                    episodeActionBusyId = ""
                    episodeActionBusyAction = ""
                    episodeStatusText = "Watch state failed: " + error
                } else {
                    watchStateBusy = false
                    watchStateStatusText = "Watch state failed: " + error
                }
                return
            }
            if (endpoint === "/api/v1/find/acquisition") {
                acquisitionBusyKey = ""
                clearPendingAcquisitionTargets()
                acquisitionStatusText = "Acquisition request failed: " + error
                return
            }
            if (endpoint === "/api/v1/library/series/:id/seasons") {
                seasonsLoading = false
                seasonLoading = false
                pendingSeasonId = ""
                seasonStatusText = "Unable to load seasons: " + error
                return
            }
            if (endpoint === "/api/v1/library/seasons/:id/episodes") {
                seasonLoading = false
                pendingSeasonId = ""
                seasonStatusText = "Unable to load episodes: " + error
                return
            }
            if (endpoint === "/api/v1/library/seasons/:id") {
                seasonStatusText = "Unable to load season details: " + error
                return
            }
            if (endpoint.indexOf("/api/v1/library/items") === 0) {
                statusText = "Request failed: " + error
            } else if (endpoint.indexOf("/api/v1/library/series") === 0 || endpoint.indexOf("/api/v1/library/seasons") === 0) {
                seasonsLoading = false
                seasonLoading = false
                pendingSeasonId = ""
                seasonStatusText = "Request failed: " + error
            } else if (endpoint.indexOf("/api/v1/library/review") === 0) {
                reviewStatusText = "Request failed: " + error
            }
        }
    }
}
