import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "findMediaView"
    property StackView stackView: null
    property int minLiveSearchChars: 2
    property string searchQuery: ""
    property string selectedType: "movie"
    property var selectedProviderIds: []
    property bool requestPending: false
    property string statusText: ""
    property string addStatusText: ""
    property string pendingAddKey: ""
    property string lastAddedIntentId: ""
    property string torrentioOwnerId: "elixir.extensions.torrentio"
    property string activeCandidateKey: ""
    property string pendingCandidateKey: ""
    property string pendingSubmitCandidateId: ""
    property string sourceStatusText: ""
    property var candidateResultsByKey: ({})
    property var candidateRouteSelections: ({})

    function setSearchQuery(query) {
        updateSearchQuery(query, false)
    }

    function updateSearchQuery(query, immediate) {
        searchQuery = query
        var trimmed = query.trim()
        if (trimmed === "") {
            selectedProviderIds = []
            requestPending = false
            statusText = ""
            activeCandidateKey = ""
            pendingCandidateKey = ""
            sourceStatusText = ""
            apiClient.findMedia("", selectedType, [])
            return
        }
        if (!immediate && trimmed.length < minLiveSearchChars) {
            requestPending = false
            statusText = ""
            apiClient.findMedia("", selectedType, [])
            return
        }
        if (immediate) {
            triggerSearch()
        } else {
            searchDebounce.restart()
        }
    }

    function lower(value) {
        if (value === undefined || value === null) {
            return ""
        }
        return String(value).toLowerCase()
    }

    function mediaTypeLabel(value) {
        var normalized = lower(value)
        if (normalized === "movie" || normalized === "movies") {
            return "Movies"
        }
        if (normalized === "series" || normalized === "tv") {
            return "TV"
        }
        if (normalized === "anime") {
            return "Anime"
        }
        return "Movies"
    }

    function listValue(objectValue, snakeKey, camelKey) {
        if (!objectValue) {
            return []
        }
        var value = objectValue[snakeKey]
        if (value === undefined && camelKey !== "") {
            value = objectValue[camelKey]
        }
        return value === undefined || value === null ? [] : value
    }

    function searchProviderOptions() {
        var providers = listValue(apiClient.mediaFindResult, "search_providers", "searchProviders")
        var options = []
        var seen = {}
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var label = provider.label
            if (label === undefined || label === "") {
                var instance = provider.instance_name !== undefined ? provider.instance_name : provider.instanceName
                var implementation = provider.implementation !== undefined ? provider.implementation : ""
                label = implementation ? (instance + " (" + implementation + ")") : instance
            }
            var providerId = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            var id = String(providerId || "")
            if (id !== "" && !seen[id]) {
                seen[id] = true
                options.push({ label: label, value: id })
            }
        }
        return options
    }

    function providerSelected(providerId) {
        var id = String(providerId || "")
        for (var i = 0; i < selectedProviderIds.length; ++i) {
            if (String(selectedProviderIds[i]) === id) {
                return true
            }
        }
        return false
    }

    function toggleProvider(providerId, enabled) {
        var id = String(providerId || "")
        if (id === "") {
            return
        }
        var next = []
        var exists = false
        for (var i = 0; i < selectedProviderIds.length; ++i) {
            var value = String(selectedProviderIds[i])
            if (value === id) {
                exists = true
                if (enabled) {
                    next.push(value)
                }
                continue
            }
            next.push(value)
        }
        if (enabled && !exists) {
            next.push(id)
        }
        selectedProviderIds = next
    }

    function managerProvidersFor(type) {
        var key = type + "_providers"
        var camel = type + "Providers"
        var providers = listValue(apiClient.mediaManagerPreferences, key, camel)
        if (providers.length > 0) {
            return providers
        }
        if (type === "movie") {
            providers = listValue(apiClient.mediaManagerPreferences, "movies_manager_candidates", "moviesManagerCandidates")
        } else if (type === "series") {
            providers = listValue(apiClient.mediaManagerPreferences, "tv_manager_candidates", "tvManagerCandidates")
        } else {
            providers = listValue(apiClient.mediaManagerPreferences, "anime_manager_candidates", "animeManagerCandidates")
        }
        if (providers.length > 0) {
            return providers
        }
        return managerProvidersFromResult()
    }

    function preferencesObject() {
        var value = apiClient.mediaManagerPreferences.preferences
        if (value === undefined || value === null) {
            value = apiClient.mediaManagerPreferences.preferencesState
        }
        return value || {}
    }

    function selectedManagerPreferenceId() {
        var pref = preferencesObject()
        if (selectedType === "movie") {
            return String(pref.movie_provider_id || pref.movieProviderId || "")
        }
        if (selectedType === "series") {
            return String(pref.series_provider_id || pref.seriesProviderId || "")
        }
        return String(pref.anime_provider_id || pref.animeProviderId || "")
    }

    function managerOptionsForSelectedType() {
        var providers = managerProvidersFor(selectedType)
        var options = [{ label: "Auto-select", value: "" }]
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var providerId = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            var label = provider.label
            if (label === undefined || label === "") {
                label = provider.instance_name !== undefined ? provider.instance_name : provider.instanceName
            }
            options.push({ label: label, value: String(providerId || "") })
        }
        return options
    }

    function optionIndexForValue(options, value) {
        var needle = String(value || "")
        for (var i = 0; i < options.length; ++i) {
            var optionValue = options[i].value
            if (optionValue === undefined || optionValue === null) {
                optionValue = options[i].logicalId
            }
            if (optionValue === undefined || optionValue === null) {
                optionValue = options[i].logical_id
            }
            if (String(optionValue || "") === needle) {
                return i
            }
        }
        return 0
    }

    function managerLabelByProviderId(providerId) {
        var id = String(providerId || "")
        if (id === "") {
            return ""
        }
        var providers = managerProvidersFromResult()
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var value = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            if (String(value || "") === id) {
                return provider.label || provider.instance_name || provider.instanceName || id
            }
        }
        return id
    }

    function updateSelectedManagerPreference(providerId) {
        var pref = preferencesObject()
        var movieId = String(pref.movie_provider_id || pref.movieProviderId || "")
        var seriesId = String(pref.series_provider_id || pref.seriesProviderId || "")
        var animeId = String(pref.anime_provider_id || pref.animeProviderId || "")
        var target = String(providerId || "")
        if (selectedType === "movie") {
            movieId = target
        } else if (selectedType === "series") {
            seriesId = target
        } else {
            animeId = target
        }
        apiClient.updateManagerPreferences(movieId, seriesId, animeId)
    }

    function findResults() {
        return listValue(apiClient.mediaFindResult, "results", "results")
    }

    function providerErrors() {
        return listValue(apiClient.mediaFindResult, "provider_errors", "providerErrors")
    }

    function managerProvidersFromResult() {
        return listValue(apiClient.mediaFindResult, "manager_providers", "managerProviders")
    }

    function defaultManagerProviderId() {
        var providerId = apiClient.mediaFindResult.default_manager_provider_id
        if (providerId === undefined || providerId === null) {
            providerId = apiClient.mediaFindResult.defaultManagerProviderId
        }
        return String(providerId || "")
    }

    function validSelectedManagerPreferenceId() {
        var preferred = selectedManagerPreferenceId()
        if (preferred !== "" && managerExists(preferred)) {
            return preferred
        }
        return ""
    }

    function managerExists(providerId) {
        var id = String(providerId || "")
        if (id === "") {
            return false
        }
        var providers = managerProvidersFromResult()
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var value = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            if (String(value || "") === id) {
                return true
            }
        }
        return false
    }

    function resolvedManagerProviderIdForAdd() {
        var preferred = validSelectedManagerPreferenceId()
        if (preferred !== "") {
            return preferred
        }
        var defaultId = defaultManagerProviderId()
        if (defaultId !== "" && managerExists(defaultId)) {
            return defaultId
        }
        return ""
    }

    function addDisabledReason() {
        var managers = managerProvidersFromResult()
        if (managers.length === 0) {
            return "No healthy manager provider is available for this media type."
        }
        if (resolvedManagerProviderIdForAdd() === "") {
            return "Select a manager before adding."
        }
        return ""
    }

    function formatAddError(error) {
        var text = String(error || "")
        if (text === "") {
            return "Add request failed."
        }
        try {
            var payload = JSON.parse(text)
            if (payload.code === "manager_selection_required") {
                return "Multiple managers match this media type. Select one and retry."
            }
            if (payload.code === "missing_manager") {
                return "No compatible manager provider is currently available."
            }
            if (payload.code === "missing_required_secrets") {
                return "Manager is missing required credentials. Configure secrets and retry."
            }
            if (payload.message !== undefined && payload.message !== null) {
                return String(payload.message)
            }
        } catch (e) {
        }
        return text
    }

    function isFindEndpoint(endpoint, suffix) {
        return endpoint.indexOf("/api/v1/find/" + suffix) === 0
                || endpoint.indexOf("/api/v1/find-media/" + suffix) === 0
    }

    function defaultManagerLabel() {
        return managerLabelByProviderId(defaultManagerProviderId())
    }

    function triggerSearch() {
        var query = searchQuery.trim()
        if (query === "" || apiClient.authToken === "") {
            requestPending = false
            return
        }
        statusText = ""
        requestPending = true
        apiClient.findMedia(query, selectedType, selectedProviderIds)
    }

    function resultKey(item) {
        var title = item && item.title ? String(item.title) : ""
        var year = item && item.year ? String(item.year) : ""
        return title + "::" + year
    }

    function resultPosterUrl(item) {
        if (!item) {
            return ""
        }
        var value = item.poster_url
        if (value === undefined || value === null || String(value) === "") {
            value = item.posterUrl
        }
        return value !== undefined && value !== null ? String(value) : ""
    }

    function resultDescription(item) {
        if (!item) {
            return ""
        }
        var text = item.description || ""
        text = String(text)
        return text.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim()
    }

    function resultPopularityLabel(item) {
        if (!item) {
            return ""
        }
        var value = item.popularity_score
        if (value === undefined || value === null) {
            value = item.popularityScore
        }
        if (value === undefined || value === null || isNaN(Number(value))) {
            return ""
        }
        return "Popularity " + Number(value).toFixed(1)
    }

    function resultTitleWithYear(item) {
        if (!item) {
            return "Untitled"
        }
        var title = item.title || "Untitled"
        var year = item.year || ""
        return year !== "" ? (title + " (" + year + ")") : title
    }

    function resultSourceSummary(item) {
        if (!item) {
            return ""
        }
        var labels = item.source_labels || item.sourceLabels || []
        if (!labels || labels.length === 0) {
            return ""
        }
        if (labels.length === 1) {
            return "Source: " + labels[0]
        }
        return "Sources: " + labels.join(", ")
    }

    function acquisitionItems() {
        return apiClient.mediaAcquisitionItems || []
    }

    function stringValue(value) {
        if (value === undefined || value === null) {
            return ""
        }
        return String(value)
    }

    function externalIdsFor(value) {
        if (!value) {
            return {}
        }
        var ids = value.external_ids
        if (ids === undefined || ids === null) {
            ids = value.externalIds
        }
        return ids || {}
    }

    function externalIdsOverlap(left, right) {
        var leftIds = externalIdsFor(left)
        var rightIds = externalIdsFor(right)
        var keys = ["imdb", "tmdb", "tvdb", "tvdb_series", "tvdb_movie", "anilist", "anidb", "mal", "kitsu"]
        for (var i = 0; i < keys.length; ++i) {
            var key = keys[i]
            var leftValue = stringValue(leftIds[key]).trim()
            var rightValue = stringValue(rightIds[key]).trim()
            if (leftValue !== "" && rightValue !== "" && leftValue === rightValue) {
                return true
            }
        }
        return false
    }

    function acquisitionMatchesResult(acquisition, item) {
        if (!acquisition || !item) {
            return false
        }
        if (externalIdsOverlap(acquisition, item)) {
            return true
        }
        var acquisitionTitle = lower(acquisition.title)
        var resultTitle = lower(item.title)
        if (acquisitionTitle === "" || acquisitionTitle !== resultTitle) {
            return false
        }
        var acquisitionYear = stringValue(acquisition.year).trim()
        var resultYear = stringValue(item.year).trim()
        if (acquisitionYear === "" || resultYear === "") {
            return true
        }
        return acquisitionYear === resultYear
    }

    function acquisitionForResult(item) {
        var items = acquisitionItems()
        var best = null
        for (var i = 0; i < items.length; ++i) {
            var acquisition = items[i]
            if (!acquisitionMatchesResult(acquisition, item)) {
                continue
            }
            if (stringValue(acquisition.intent_id || acquisition.intentId) === root.lastAddedIntentId) {
                return acquisition
            }
            if (best === null) {
                best = acquisition
            }
        }
        return best
    }

    function acquisitionPhaseCode(acquisition) {
        if (!acquisition) {
            return ""
        }
        return String(acquisition.phase || acquisition.stage || "")
    }

    function acquisitionStageColor(stage) {
        if (stage === "needs_attention" || stage === "failed") {
            return Theme.accentDanger
        }
        if (stage === "completed" || stage === "ready") {
            return Theme.accentSuccess
        }
        return Theme.accent
    }

    function acquisitionStageFill(stage) {
        if (stage === "needs_attention" || stage === "failed") {
            return Theme.accentDangerSoft
        }
        if (stage === "completed" || stage === "ready") {
            return Theme.accentSuccessSoft
        }
        return Theme.accentSoft
    }

    function acquisitionProgressVisible(acquisition) {
        if (!acquisition) {
            return false
        }
        var phase = acquisitionPhaseCode(acquisition)
        if (phase !== "downloading" && phase !== "post_processing") {
            return false
        }
        var value = acquisition.progress_percent
        if (value === undefined || value === null) {
            value = acquisition.progressPercent
        }
        return value !== undefined && value !== null && Number(value) > 0 && Number(value) < 100
    }

    function acquisitionProgressValue(acquisition) {
        if (!acquisition) {
            return 0
        }
        var value = acquisition.progress_percent
        if (value === undefined || value === null) {
            value = acquisition.progressPercent
        }
        return Number(value || 0)
    }

    function acquisitionSourceLine(acquisition) {
        if (!acquisition) {
            return ""
        }
        var label = String(acquisition.source_label || acquisition.sourceLabel || "")
        var children = acquisition.children || []
        var child = children.length > 0 ? children[0] : null
        if (label === "" && child) {
            label = String(child.source_label || child.sourceLabel || "")
        }
        var details = []
        if (child) {
            var size = formatBytes(child.candidate_size_bytes || child.candidateSizeBytes || child.size_bytes || child.sizeBytes)
            if (size !== "") {
                details.push(size)
            }
            var language = String(child.candidate_language || child.candidateLanguage || "")
            if (language !== "") {
                details.push(language)
            }
        }
        if (label === "") {
            return details.join(" · ")
        }
        return details.length > 0 ? (label + " · " + details.join(" · ")) : label
    }

    function addTargetLabel() {
        var managerId = resolvedManagerProviderIdForAdd()
        if (managerId === "") {
            return "Target manager not selected"
        }
        var label = managerLabelByProviderId(managerId)
        return label !== "" ? ("Add to " + label) : "Add to selected manager"
    }

    function addResultToManager(item) {
        var blockedReason = addDisabledReason()
        if (blockedReason !== "") {
            addStatusText = blockedReason
            return
        }
        var managerProviderId = resolvedManagerProviderIdForAdd()
        pendingAddKey = resultKey(item)
        addStatusText = ""
        apiClient.addMediaToManager(selectedType, item, managerProviderId, {})
    }

    function sourceDisabledReason(item) {
        if (!item) {
            return "Select a media result first."
        }
        var type = lower(item.type || selectedType)
        var ids = externalIdsFor(item)
        if (type === "series" || type === "tv") {
            return "Episode source search requires season and episode selection."
        }
        if (type === "anime") {
            if (stringValue(ids.imdb).trim() === "" && stringValue(ids.kitsu).trim() === "") {
                return "Anime source search requires an IMDb or Kitsu id."
            }
            return ""
        }
        if (stringValue(ids.imdb).trim() === "") {
            return "Movie source search requires an IMDb id."
        }
        return ""
    }

    function candidateResultForKey(key) {
        var value = candidateResultsByKey[String(key || "")]
        return value === undefined || value === null ? null : value
    }

    function candidateList(result) {
        if (!result) {
            return []
        }
        var value = result.candidates
        return value === undefined || value === null ? [] : value
    }

    function routeOptionsForResult(result) {
        if (!result) {
            return []
        }
        var value = result.route_options
        if (value === undefined || value === null) {
            value = result.routeOptions
        }
        return value === undefined || value === null ? [] : value
    }

    function candidateRouteIds(candidate) {
        if (!candidate) {
            return []
        }
        var value = candidate.route_logical_ids
        if (value === undefined || value === null) {
            value = candidate.routeLogicalIds
        }
        return value === undefined || value === null ? [] : value
    }

    function routeSupportsCandidate(route, candidate) {
        var routeId = String(route.logical_id || route.logicalId || "")
        var ids = candidateRouteIds(candidate)
        for (var i = 0; i < ids.length; ++i) {
            if (String(ids[i] || "") === routeId) {
                return true
            }
        }
        return false
    }

    function candidateRouteOptions(candidate, result) {
        var routes = routeOptionsForResult(result)
        var options = []
        for (var i = 0; i < routes.length; ++i) {
            var route = routes[i]
            if (routeSupportsCandidate(route, candidate)) {
                options.push(route)
            }
        }
        return options
    }

    function defaultRouteId(candidate) {
        var value = candidate ? candidate.default_route_logical_id : ""
        if (value === undefined || value === null || String(value) === "") {
            value = candidate ? candidate.defaultRouteLogicalId : ""
        }
        return String(value || "")
    }

    function selectedRouteIdForCandidate(candidate, result) {
        var candidateId = String(candidate && candidate.id ? candidate.id : "")
        var selected = String(candidateRouteSelections[candidateId] || "")
        var options = candidateRouteOptions(candidate, result)
        for (var i = 0; i < options.length; ++i) {
            var optionId = String(options[i].logical_id || options[i].logicalId || "")
            if (selected !== "" && optionId === selected) {
                return selected
            }
        }
        var preferred = defaultRouteId(candidate)
        for (var j = 0; j < options.length; ++j) {
            var routeId = String(options[j].logical_id || options[j].logicalId || "")
            if (preferred !== "" && routeId === preferred) {
                return preferred
            }
        }
        return options.length > 0 ? String(options[0].logical_id || options[0].logicalId || "") : ""
    }

    function routeOptionById(result, logicalId) {
        var routes = routeOptionsForResult(result)
        var needle = String(logicalId || "")
        for (var i = 0; i < routes.length; ++i) {
            var route = routes[i]
            if (String(route.logical_id || route.logicalId || "") === needle) {
                return route
            }
        }
        return null
    }

    function setCandidateRoute(candidate, routeId) {
        var candidateId = String(candidate && candidate.id ? candidate.id : "")
        if (candidateId === "") {
            return
        }
        var next = {}
        for (var key in candidateRouteSelections) {
            next[key] = candidateRouteSelections[key]
        }
        next[candidateId] = String(routeId || "")
        candidateRouteSelections = next
    }

    function setCandidateResult(targetKey, result) {
        var next = {}
        for (var key in candidateResultsByKey) {
            next[key] = candidateResultsByKey[key]
        }
        next[String(targetKey || "")] = result || {}
        candidateResultsByKey = next
    }

    function searchSourcesForResult(item) {
        var reason = sourceDisabledReason(item)
        if (reason !== "") {
            sourceStatusText = reason
            return
        }
        var key = resultKey(item)
        activeCandidateKey = key
        pendingCandidateKey = key
        sourceStatusText = ""
        apiClient.searchAcquisitionCandidates(key, selectedType, item, 0, 0)
    }

    function routeUnavailableReason(route) {
        if (!route) {
            return "No acquisition route is available for this source."
        }
        var blocker = route.blocker
        if (blocker !== undefined && blocker !== null && String(blocker) !== "") {
            return String(blocker)
        }
        if (route.available === false) {
            return "No provider is selected for this acquisition route."
        }
        return ""
    }

    function submitDisabledReason(candidate, result) {
        var routeId = selectedRouteIdForCandidate(candidate, result)
        var route = routeOptionById(result, routeId)
        return routeUnavailableReason(route)
    }

    function submitCandidate(candidate, result) {
        var routeId = selectedRouteIdForCandidate(candidate, result)
        var reason = submitDisabledReason(candidate, result)
        if (reason !== "") {
            sourceStatusText = reason
            return
        }
        pendingSubmitCandidateId = String(candidate.id || "")
        sourceStatusText = ""
        apiClient.submitAcquisitionCandidate(routeId, candidate, torrentioOwnerId)
    }

    function openRouteAccount(route) {
        var extensionId = String(route && (route.account_extension_id || route.accountExtensionId) || "")
        if (!stackView || extensionId === "") {
            return
        }
        stackView.push(Qt.resolvedUrl("ExtensionControlView.qml"), {
            stackView: stackView,
            extensionId: extensionId
        })
    }

    function formatBytes(value) {
        var bytes = Number(value || 0)
        if (!isFinite(bytes) || bytes <= 0) {
            return ""
        }
        var units = ["B", "KB", "MB", "GB", "TB"]
        var idx = 0
        while (bytes >= 1024 && idx < units.length - 1) {
            bytes = bytes / 1024
            idx += 1
        }
        var decimals = idx < 2 ? 0 : 1
        return bytes.toFixed(decimals) + " " + units[idx]
    }

    function candidateSummary(candidate) {
        var parts = []
        var quality = String(candidate.quality || "")
        if (quality !== "") {
            parts.push(quality)
        }
        var size = formatBytes(candidate.size_bytes || candidate.sizeBytes)
        if (size !== "") {
            parts.push(size)
        }
        var seeders = candidate.seeders
        if (seeders !== undefined && seeders !== null && Number(seeders) > 0) {
            parts.push(Number(seeders) + " seeders")
        }
        var language = String(candidate.language || "")
        if (language !== "") {
            parts.push(language)
        }
        var cachedDebrid = candidate.cached_debrid
        if (cachedDebrid === undefined || cachedDebrid === null) {
            cachedDebrid = candidate.cachedDebrid
        }
        if (cachedDebrid === true || cachedDebrid === "true") {
            parts.push("cached debrid")
        }
        var kind = String(candidate.source_kind || candidate.sourceKind || "")
        if (kind !== "") {
            parts.push(kind === "http" ? "hoster link" : kind)
        }
        return parts.join(" / ")
    }

    function candidateScoreBadges(candidate) {
        if (!candidate) {
            return []
        }
        var badges = candidate.score_badges
        if (badges === undefined || badges === null) {
            badges = candidate.scoreBadges
        }
        return badges === undefined || badges === null ? [] : badges
    }

    onSelectedTypeChanged: {
        selectedProviderIds = []
        activeCandidateKey = ""
        pendingCandidateKey = ""
        sourceStatusText = ""
        if (apiClient.authToken !== "") {
            apiClient.fetchManagerPreferences()
            apiClient.findMedia("", selectedType, [])
        }
        if (searchQuery.trim().length >= minLiveSearchChars) {
            searchDebounce.restart()
        }
    }

    onSelectedProviderIdsChanged: {
        if (searchQuery.trim().length >= minLiveSearchChars) {
            searchDebounce.restart()
        }
    }

    Component.onCompleted: {
        if (apiClient.authToken !== "") {
            apiClient.fetchManagerPreferences()
            apiClient.findMedia("", selectedType, [])
            apiClient.fetchMediaAcquisition()
        }
    }

    Timer {
        id: searchDebounce
        interval: 350
        repeat: false
        onTriggered: root.triggerSearch()
    }

    Timer {
        id: managerPreferencesPoll
        interval: 4000
        repeat: true
        running: root.visible && apiClient.authToken !== ""
        onTriggered: apiClient.fetchManagerPreferences()
    }

    Connections {
        target: apiClient

        function onAuthTokenChanged() {
            if (apiClient.authToken !== "") {
                apiClient.fetchManagerPreferences()
                apiClient.findMedia("", root.selectedType, [])
                apiClient.fetchMediaAcquisition()
                if (root.searchQuery.trim().length >= root.minLiveSearchChars) {
                    searchDebounce.restart()
                }
            } else {
                root.requestPending = false
                root.statusText = ""
            }
        }

        function onMediaFindResultChanged() {
            root.requestPending = false
            root.statusText = ""
            var options = root.searchProviderOptions()
            var valid = {}
            for (var i = 0; i < options.length; ++i) {
                valid[String(options[i].value || "")] = true
            }
            var filtered = []
            for (var j = 0; j < root.selectedProviderIds.length; ++j) {
                var providerId = String(root.selectedProviderIds[j] || "")
                if (valid[providerId]) {
                    filtered.push(providerId)
                }
            }
            if (filtered.length !== root.selectedProviderIds.length) {
                root.selectedProviderIds = filtered
            }
        }

        function onMediaFindLoadingChanged() {
            if (apiClient.mediaFindLoading) {
                root.requestPending = true
            }
        }

        function onRequestFailed(endpoint, error) {
            if (root.isFindEndpoint(endpoint, "search") ||
                    root.isFindEndpoint(endpoint, "targets")) {
                root.requestPending = false
                root.statusText = error
            } else if (root.isFindEndpoint(endpoint, "preferences")) {
                root.statusText = error
            } else if (root.isFindEndpoint(endpoint, "add")) {
                root.pendingAddKey = ""
                root.addStatusText = root.formatAddError(error)
            } else if (endpoint.indexOf("/api/v1/acquisition/candidates/search") === 0) {
                root.pendingCandidateKey = ""
                root.sourceStatusText = error
            } else if (endpoint.indexOf("/api/v1/download-broker") === 0) {
                root.pendingSubmitCandidateId = ""
                root.sourceStatusText = error
            }
        }

        function onMediaAddResultChanged() {
            root.pendingAddKey = ""
            root.lastAddedIntentId = String(apiClient.mediaAddResult.intent_id || apiClient.mediaAddResult.intentId || "")
            var title = apiClient.mediaAddResult.title || "Media"
            var manager = apiClient.mediaAddResult.manager_label || apiClient.mediaAddResult.managerLabel || "manager"
            root.addStatusText = title + " added via " + manager + "."
            apiClient.fetchMediaAcquisition()
        }

        function onMediaAddLoadingChanged() {
            if (!apiClient.mediaAddLoading && root.pendingAddKey !== "" && root.addStatusText === "") {
                root.pendingAddKey = ""
            }
        }

        function onAcquisitionCandidatesReceived(targetKey, result) {
            root.pendingCandidateKey = ""
            root.activeCandidateKey = String(targetKey || "")
            root.sourceStatusText = ""
            root.setCandidateResult(targetKey, result)
        }

        function onAcquisitionCandidateSubmitCompleted(candidateId, result) {
            root.pendingSubmitCandidateId = ""
            var accepted = result && (result.accepted === true || result.accepted === "true")
            var route = result ? String(result.logical_id || result.logicalId || "") : ""
            root.sourceStatusText = accepted
                                  ? ("Download submitted" + (route !== "" ? (" via " + route) : "") + ".")
                                  : "Download broker did not accept the candidate."
            apiClient.fetchMediaAcquisition()
        }

        function onExtensionsCatalogChanged() {
            if (apiClient.authToken !== "") {
                apiClient.fetchManagerPreferences()
                apiClient.findMedia("", root.selectedType, [])
            }
        }

        function onExtensionsInstancesChanged() {
            if (apiClient.authToken !== "") {
                apiClient.fetchManagerPreferences()
                apiClient.findMedia("", root.selectedType, [])
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + Theme.spacingXLarge * 2
        clip: true

        ColumnLayout {
            id: content
            x: Theme.spacingXLarge
            y: Theme.spacingXLarge
            width: Math.max(0, parent.width - Theme.spacingXLarge * 2)
            spacing: Theme.spacingLarge

            Label {
                text: "Find Media"
                color: Theme.textPrimary
                font.pixelSize: 24
                font.family: Theme.fontDisplay
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: searchRow.implicitHeight + Theme.spacingLarge * 2

                RowLayout {
                    id: searchRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    TextField {
                        id: findSearchField
                        Layout.fillWidth: true
                        text: root.searchQuery
                        placeholderText: "Search " + root.mediaTypeLabel(root.selectedType) + " titles"
                        onTextEdited: root.updateSearchQuery(text, false)
                        onAccepted: root.updateSearchQuery(text, true)
                    }

                    Button {
                        text: "Search"
                        enabled: findSearchField.text.trim() !== ""
                        onClicked: root.updateSearchQuery(findSearchField.text, true)
                    }

                    Button {
                        text: "Clear"
                        enabled: findSearchField.text.trim() !== ""
                        onClicked: root.updateSearchQuery("", true)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Repeater {
                    model: [
                        { key: "movie", label: "Movies" },
                        { key: "series", label: "TV" },
                        { key: "anime", label: "Anime" }
                    ]

                    delegate: Button {
                        text: modelData.label
                        checkable: true
                        checked: root.selectedType === modelData.key
                        onClicked: root.selectedType = modelData.key
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            border.color: checked ? Theme.accent : Theme.border
                            color: checked ? Theme.accentSoft
                                           : Theme.backgroundCardRaised
                        }
                        contentItem: Label {
                            text: parent.text
                            color: checked ? Theme.textPrimary : Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: managerColumn.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: managerColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    Label {
                        text: "Manager Routing"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        text: "Default manager for " + root.mediaTypeLabel(root.selectedType) + ":"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    ComboBox {
                        id: managerPreferenceCombo
                        Layout.fillWidth: true
                        model: root.managerOptionsForSelectedType()
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: root.optionIndexForValue(model, root.selectedManagerPreferenceId())
                        onActivated: {
                            var value = currentValue !== undefined ? String(currentValue) : ""
                            root.updateSelectedManagerPreference(value)
                        }
                    }

                    Label {
                        text: root.defaultManagerLabel() !== ""
                              ? "Current default from provider graph: " + root.defaultManagerLabel()
                              : "No manager currently available for this media type."
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: providersColumn.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: providersColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    Label {
                        text: "Search In"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Repeater {
                            model: root.searchProviderOptions()

                            delegate: Button {
                                readonly property string providerId: modelData.value || ""
                                text: modelData.label || providerId
                                checkable: true
                                checked: root.providerSelected(providerId)
                                onClicked: root.toggleProvider(providerId, checked)
                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    border.color: checked ? Theme.accent : Theme.border
                                    color: checked ? Theme.accentSoft : Theme.backgroundCardRaised
                                }
                                contentItem: Label {
                                    text: parent.text
                                    color: checked ? Theme.textPrimary : Theme.textSecondary
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    Label {
                        text: root.selectedProviderIds.length > 0
                              ? (root.selectedProviderIds.length + " provider filter(s) active.")
                              : "All providers selected."
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }
                }
            }

            BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: root.requestPending || apiClient.mediaFindLoading
                visible: running
            }

            Label {
                Layout.fillWidth: true
                text: root.statusText
                color: "#f26d6d"
                font.pixelSize: 11
                font.family: Theme.fontBody
                visible: root.statusText !== ""
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: root.addStatusText
                color: Theme.textSecondary
                font.pixelSize: 11
                font.family: Theme.fontBody
                visible: root.addStatusText !== ""
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: root.sourceStatusText
                color: root.sourceStatusText.indexOf("Download submitted") === 0
                       ? Theme.textSecondary
                       : "#f26d6d"
                font.pixelSize: 11
                font.family: Theme.fontBody
                visible: root.sourceStatusText !== ""
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.providerErrors()
                delegate: Rectangle {
                    Layout.fillWidth: true
                    radius: Theme.radiusSmall
                    color: "#3a2222"
                    border.color: "#7a3a3a"
                    implicitHeight: errorText.implicitHeight + Theme.spacingSmall * 2

                    Label {
                        id: errorText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingSmall
                        text: modelData.message || ""
                        color: Theme.textPrimary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: searchQuery.trim() === ""
                      ? "Enter a title to search."
                      : (searchQuery.trim().length < root.minLiveSearchChars
                         ? ("Type at least " + root.minLiveSearchChars + " characters for live search, or press Enter.")
                      : (root.findResults().length === 0 && !root.requestPending && !apiClient.mediaFindLoading
                         ? "No results found."
                         : ""))
                color: Theme.textMuted
                font.pixelSize: 12
                font.family: Theme.fontBody
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: root.findResults().length > 0
                      ? (root.findResults().length + " result" + (root.findResults().length === 1 ? "" : "s"))
                      : ""
                color: Theme.textMuted
                font.pixelSize: 11
                font.family: Theme.fontBody
                visible: text !== ""
            }

            ListView {
                id: resultsList
                Layout.fillWidth: true
                Layout.preferredHeight: contentHeight
                model: root.findResults()
                spacing: Theme.spacingSmall
                clip: true
                interactive: false
                reuseItems: true
                delegate: Rectangle {
                    id: resultRow
                    required property var modelData
                    required property int index

                    readonly property string rowKey: root.resultKey(modelData)
                    readonly property bool addPending: root.pendingAddKey === rowKey && apiClient.mediaAddLoading
                    readonly property string addReason: root.addDisabledReason()
                    readonly property var acquisition: root.acquisitionForResult(modelData)

                    width: ListView.view ? ListView.view.width : 0
                    radius: Theme.radiusMedium
                    color: index % 2 === 0 ? Theme.backgroundCard : Theme.backgroundCardRaised
                    border.color: rowHover.hovered ? Theme.accent : Theme.border
                    implicitHeight: resultContainer.implicitHeight + Theme.spacingSmall * 2

                    HoverHandler {
                        id: rowHover
                    }

                    ColumnLayout {
                        id: resultContainer
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingSmall
                        spacing: Theme.spacingSmall

                    RowLayout {
                        id: rowContent
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium

                        Rectangle {
                            Layout.preferredWidth: 78
                            Layout.preferredHeight: 114
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCard
                            border.color: Theme.border
                            clip: true

                            Image {
                                id: posterImage
                                anchors.fill: parent
                                source: root.resultPosterUrl(modelData)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                visible: source !== "" && status === Image.Ready
                            }

                            Label {
                                anchors.centerIn: parent
                                text: root.mediaTypeLabel(modelData.type || "")
                                color: Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontBody
                                visible: !posterImage.visible
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Label {
                                Layout.fillWidth: true
                                text: root.resultTitleWithYear(modelData)
                                color: Theme.textPrimary
                                font.pixelSize: 17
                                font.family: Theme.fontDisplay
                                elide: Text.ElideRight
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    radius: Theme.radiusSmall
                                    color: Theme.backgroundCard
                                    border.color: Theme.border
                                    implicitWidth: mediaTypeChip.implicitWidth + 12
                                    implicitHeight: mediaTypeChip.implicitHeight + 4

                                    Label {
                                        id: mediaTypeChip
                                        anchors.centerIn: parent
                                        text: root.mediaTypeLabel(modelData.type || "")
                                        color: Theme.textSecondary
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                    }
                                }

                                Rectangle {
                                    radius: Theme.radiusSmall
                                    color: Theme.backgroundCard
                                    border.color: Theme.border
                                    visible: (modelData.year || "") !== ""
                                    implicitWidth: yearChip.implicitWidth + 12
                                    implicitHeight: yearChip.implicitHeight + 4

                                    Label {
                                        id: yearChip
                                        anchors.centerIn: parent
                                        text: String(modelData.year || "")
                                        color: Theme.textSecondary
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                    }
                                }

                                Rectangle {
                                    radius: Theme.radiusSmall
                                    color: Theme.backgroundCard
                                    border.color: Theme.border
                                    visible: root.resultPopularityLabel(modelData) !== ""
                                    implicitWidth: popularityChip.implicitWidth + 12
                                    implicitHeight: popularityChip.implicitHeight + 4

                                    Label {
                                        id: popularityChip
                                        anchors.centerIn: parent
                                        text: root.resultPopularityLabel(modelData)
                                        color: Theme.textSecondary
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.resultDescription(modelData)
                                color: Theme.textSecondary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                visible: text !== ""
                            }

                            Label {
                                Layout.fillWidth: true
                                text: root.resultSourceSummary(modelData)
                                color: Theme.textMuted
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                visible: text !== ""
                                elide: Text.ElideRight
                            }
                        }

                        ColumnLayout {
                            Layout.preferredWidth: 190
                            Layout.alignment: Qt.AlignTop
                            spacing: 6

                            Label {
                                Layout.fillWidth: true
                                text: root.addTargetLabel()
                                color: Theme.textMuted
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.WordWrap
                            }

                            Button {
                                Layout.alignment: Qt.AlignRight
                                text: resultRow.addPending ? "Adding..." : "Add"
                                enabled: !apiClient.mediaAddLoading && resultRow.addReason === ""
                                onClicked: root.addResultToManager(modelData)
                            }

                            Button {
                                Layout.alignment: Qt.AlignRight
                                text: root.pendingCandidateKey === resultRow.rowKey
                                      ? "Searching..."
                                      : (root.activeCandidateKey === resultRow.rowKey ? "Hide Sources" : "Sources")
                                enabled: root.pendingCandidateKey === ""
                                onClicked: {
                                    if (root.activeCandidateKey === resultRow.rowKey) {
                                        root.activeCandidateKey = ""
                                    } else {
                                        root.searchSourcesForResult(modelData)
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                text: resultRow.addReason !== ""
                                      ? resultRow.addReason
                                      : root.sourceDisabledReason(modelData)
                                color: Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.WordWrap
                                visible: text !== ""
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                radius: Theme.radiusSmall
                                color: root.acquisitionStageFill(root.acquisitionPhaseCode(resultRow.acquisition))
                                border.color: root.acquisitionStageColor(root.acquisitionPhaseCode(resultRow.acquisition))
                                visible: resultRow.acquisition !== null
                                implicitHeight: acquisitionColumn.implicitHeight + 8

                                ColumnLayout {
                                    id: acquisitionColumn
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: 4
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Label {
                                            text: resultRow.acquisition
                                                  ? String(resultRow.acquisition.phaseLabel || resultRow.acquisition.stageLabel || resultRow.acquisition.phase || resultRow.acquisition.stage || "")
                                                  : ""
                                            color: Theme.textPrimary
                                            font.pixelSize: 10
                                            font.family: Theme.fontBody
                                        }

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.acquisitionProgressVisible(resultRow.acquisition)
                                                  ? (root.acquisitionProgressValue(resultRow.acquisition).toFixed(0) + "%")
                                                  : ""
                                            color: Theme.textSecondary
                                            font.pixelSize: 10
                                            font.family: Theme.fontBody
                                            horizontalAlignment: Text.AlignRight
                                            visible: text !== ""
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: resultRow.acquisition
                                              ? String(resultRow.acquisition.headline || resultRow.acquisition.detail || resultRow.acquisition.description || "")
                                              : ""
                                        color: Theme.textSecondary
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                        visible: text !== ""
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.acquisitionSourceLine(resultRow.acquisition)
                                        color: Theme.textMuted
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                        visible: text !== ""
                                    }

                                    ProgressBar {
                                        Layout.fillWidth: true
                                        from: 0
                                        to: 100
                                        value: root.acquisitionProgressValue(resultRow.acquisition)
                                        visible: root.acquisitionProgressVisible(resultRow.acquisition)
                                    }
                                }
                            }
                        }
                    }

                        Rectangle {
                            id: sourcePanel
                            Layout.fillWidth: true
                            visible: root.activeCandidateKey === resultRow.rowKey
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCard
                            border.color: Theme.border
                            implicitHeight: sourcePanelColumn.implicitHeight + Theme.spacingSmall * 2

                            readonly property var candidateResult: root.candidateResultForKey(resultRow.rowKey)
                            readonly property var candidates: root.candidateList(candidateResult)
                            readonly property bool loading: root.pendingCandidateKey === resultRow.rowKey

                            ColumnLayout {
                                id: sourcePanelColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingSmall
                                spacing: Theme.spacingSmall

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSmall

                                    Label {
                                        Layout.fillWidth: true
                                        text: "Download Sources"
                                        color: Theme.textPrimary
                                        font.pixelSize: 13
                                        font.family: Theme.fontDisplay
                                    }

                                    BusyIndicator {
                                        running: sourcePanel.loading
                                        visible: running
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                    }

                                    Button {
                                        text: "Refresh"
                                        enabled: !sourcePanel.loading
                                                 && root.sourceDisabledReason(resultRow.modelData) === ""
                                        onClicked: root.searchSourcesForResult(resultRow.modelData)
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: root.sourceDisabledReason(resultRow.modelData)
                                    color: Theme.textMuted
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    wrapMode: Text.WordWrap
                                    visible: text !== ""
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: !sourcePanel.loading
                                          && root.sourceDisabledReason(resultRow.modelData) === ""
                                          && sourcePanel.candidates.length === 0
                                          && sourcePanel.candidateResult !== null
                                          ? "No downloadable candidates were returned."
                                          : ""
                                    color: Theme.textMuted
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    wrapMode: Text.WordWrap
                                    visible: text !== ""
                                }

                                Repeater {
                                    model: sourcePanel.candidates.slice(0, 8)

                                    delegate: Rectangle {
                                        id: candidateRow
                                        required property var modelData

                                        readonly property string selectedRouteId: root.selectedRouteIdForCandidate(modelData, sourcePanel.candidateResult)
                                        readonly property var selectedRoute: root.routeOptionById(sourcePanel.candidateResult, selectedRouteId)
                                        readonly property string submitReason: root.submitDisabledReason(modelData, sourcePanel.candidateResult)
                                        readonly property bool submitPending: root.pendingSubmitCandidateId === String(modelData.id || "")

                                        Layout.fillWidth: true
                                        radius: Theme.radiusSmall
                                        color: Theme.backgroundCardRaised
                                        border.color: submitReason !== "" ? Theme.accentDanger : Theme.border
                                        implicitHeight: candidateColumn.implicitHeight + Theme.spacingSmall * 2

                                        ColumnLayout {
                                            id: candidateColumn
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: Theme.spacingSmall
                                            spacing: 6

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.spacingSmall

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 3

                                                    Label {
                                                        Layout.fillWidth: true
                                                        text: String(modelData.title || modelData.name || "Untitled source")
                                                        color: Theme.textPrimary
                                                        font.pixelSize: 12
                                                        font.family: Theme.fontBody
                                                        elide: Text.ElideRight
                                                    }

                                                    Label {
                                                        Layout.fillWidth: true
                                                        text: root.candidateSummary(modelData)
                                                        color: Theme.textMuted
                                                        font.pixelSize: 10
                                                        font.family: Theme.fontBody
                                                        elide: Text.ElideRight
                                                        visible: text !== ""
                                                    }

                                                    Flow {
                                                        Layout.fillWidth: true
                                                        spacing: 4
                                                        visible: root.candidateScoreBadges(modelData).length > 0

                                                        Repeater {
                                                            model: root.candidateScoreBadges(modelData).slice(0, 5)

                                                            delegate: Rectangle {
                                                                required property var modelData
                                                                readonly property int badgeValue: Number(modelData.value || 0)

                                                                radius: Theme.radiusSmall
                                                                color: badgeValue < 0 ? Theme.backgroundCard
                                                                                      : Theme.accentSoft
                                                                border.color: badgeValue < 0 ? Theme.border
                                                                                             : Theme.accent
                                                                implicitWidth: badgeLabel.implicitWidth + 10
                                                                implicitHeight: badgeLabel.implicitHeight + 4

                                                                Label {
                                                                    id: badgeLabel
                                                                    anchors.centerIn: parent
                                                                    text: String(modelData.label || "")
                                                                    color: badgeValue < 0 ? Theme.textMuted
                                                                                          : Theme.textPrimary
                                                                    font.pixelSize: 9
                                                                    font.family: Theme.fontBody
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                ComboBox {
                                                    Layout.preferredWidth: 220
                                                    model: root.candidateRouteOptions(modelData, sourcePanel.candidateResult)
                                                    textRole: "label"
                                                    valueRole: "logicalId"
                                                    currentIndex: root.optionIndexForValue(model, candidateRow.selectedRouteId)
                                                    onActivated: {
                                                        var value = currentValue !== undefined
                                                                  ? String(currentValue)
                                                                  : String(model[currentIndex].logical_id || model[currentIndex].logicalId || "")
                                                        root.setCandidateRoute(modelData, value)
                                                    }
                                                }

                                                Button {
                                                    text: candidateRow.submitPending ? "Submitting..." : "Download"
                                                    enabled: !candidateRow.submitPending
                                                             && root.pendingSubmitCandidateId === ""
                                                             && candidateRow.submitReason === ""
                                                    onClicked: root.submitCandidate(modelData, sourcePanel.candidateResult)
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.spacingSmall
                                                visible: candidateRow.submitReason !== ""

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: candidateRow.submitReason
                                                    color: Theme.textMuted
                                                    font.pixelSize: 10
                                                    font.family: Theme.fontBody
                                                    wrapMode: Text.WordWrap
                                                }

                                                Button {
                                                    text: "Add account"
                                                    visible: candidateRow.selectedRoute
                                                             && (candidateRow.selectedRoute.needs_account === true
                                                                 || candidateRow.selectedRoute.needsAccount === true)
                                                    onClicked: root.openRouteAccount(candidateRow.selectedRoute)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
