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
    property var addedResultKeys: ({})
    property var pendingAcquisitionAction: null

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

    function displayText(value, context) {
        var text = String(value || "")
        if (text === "") return ""
        if (context === "Debrid account" && text === "Add account") {
            return "Add debrid account"
        }
        text = text.split("Real-Debrid API token is not configured").join("Add debrid account")
        text = text.split("Real Debrid API token is not configured").join("Add debrid account")
        if (text === "Direct HTTPS debrid") {
            return "Direct HTTPS debrid download"
        }
        return text
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

    function sourceProvidersFor(type) {
        var key = type + "_source_providers"
        var camel = type + "SourceProviders"
        var providers = listValue(apiClient.mediaManagerPreferences, key, camel)
        if (providers.length > 0) {
            return providers
        }
        if (type === "movie") {
            providers = listValue(apiClient.mediaManagerPreferences, "movies_source_candidates", "movieSourceProviders")
        } else if (type === "series") {
            providers = listValue(apiClient.mediaManagerPreferences, "tv_source_candidates", "seriesSourceProviders")
        } else {
            providers = listValue(apiClient.mediaManagerPreferences, "anime_source_candidates", "animeSourceProviders")
        }
        if (providers.length > 0) {
            return providers
        }
        return sourceProvidersFromResult()
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

    function selectedSourcePreferenceId() {
        var pref = preferencesObject()
        if (selectedType === "movie") {
            return String(pref.movie_source_provider_id || pref.movieSourceProviderId || "")
        }
        if (selectedType === "series") {
            return String(pref.series_source_provider_id || pref.seriesSourceProviderId || "")
        }
        return String(pref.anime_source_provider_id || pref.animeSourceProviderId || "")
    }

    function providerId(provider) {
        if (!provider) {
            return ""
        }
        var value = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
        return String(value || "")
    }

    function providerLabel(provider) {
        if (!provider) {
            return ""
        }
        var label = provider.label
        if (label === undefined || label === "") {
            label = provider.instance_name !== undefined ? provider.instance_name : provider.instanceName
        }
        return String(label || "")
    }

    function routeValue(kind, providerId) {
        var id = String(providerId || "")
        return id === "" ? "" : (kind + ":" + id)
    }

    function routeKind(value) {
        var text = String(value || "")
        var index = text.indexOf(":")
        return index > 0 ? text.substring(0, index) : ""
    }

    function routeProviderId(value) {
        var text = String(value || "")
        var index = text.indexOf(":")
        return index > 0 ? text.substring(index + 1) : ""
    }

    function routeOptionsForSelectedType() {
        var options = [{ label: "Auto-select", value: "" }]
        var sources = sourceProvidersFor(selectedType)
        for (var i = 0; i < sources.length; ++i) {
            var sourceId = providerId(sources[i])
            if (sourceId !== "") {
                options.push({ label: providerLabel(sources[i]), value: routeValue("source", sourceId) })
            }
        }
        var managers = managerProvidersFor(selectedType)
        for (var j = 0; j < managers.length; ++j) {
            var managerId = providerId(managers[j])
            if (managerId !== "") {
                options.push({ label: providerLabel(managers[j]), value: routeValue("manager", managerId) })
            }
        }
        return options
    }

    function optionIndexForValue(options, value) {
        var needle = String(value || "")
        for (var i = 0; i < options.length; ++i) {
            if (String(options[i].value || "") === needle) {
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

    function sourceLabelByProviderId(providerId) {
        var id = String(providerId || "")
        if (id === "") {
            return ""
        }
        var providers = sourceProvidersFromResult()
        if (providers.length === 0) {
            providers = sourceProvidersFor(selectedType)
        }
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var value = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            if (String(value || "") === id) {
                return provider.label || provider.instance_name || provider.instanceName || id
            }
        }
        return id
    }

    function routeLabelByValue(value) {
        var kind = routeKind(value)
        var id = routeProviderId(value)
        if (kind === "source") {
            return sourceLabelByProviderId(id)
        }
        if (kind === "manager") {
            return managerLabelByProviderId(id)
        }
        return ""
    }

    function selectedRoutePreferenceValue() {
        var sourceId = selectedSourcePreferenceId()
        if (sourceId !== "" && sourceExists(sourceId)) {
            return routeValue("source", sourceId)
        }
        var managerId = selectedManagerPreferenceId()
        if (managerId !== "" && managerExists(managerId)) {
            return routeValue("manager", managerId)
        }
        return ""
    }

    function updateSelectedRoutePreference(value) {
        var pref = preferencesObject()
        var movieId = String(pref.movie_provider_id || pref.movieProviderId || "")
        var seriesId = String(pref.series_provider_id || pref.seriesProviderId || "")
        var animeId = String(pref.anime_provider_id || pref.animeProviderId || "")
        var movieSourceId = String(pref.movie_source_provider_id || pref.movieSourceProviderId || "")
        var seriesSourceId = String(pref.series_source_provider_id || pref.seriesSourceProviderId || "")
        var animeSourceId = String(pref.anime_source_provider_id || pref.animeSourceProviderId || "")
        var kind = routeKind(value)
        var target = routeProviderId(value)
        if (selectedType === "movie") {
            movieId = kind === "manager" ? target : ""
            movieSourceId = kind === "source" ? target : ""
        } else if (selectedType === "series") {
            seriesId = kind === "manager" ? target : ""
            seriesSourceId = kind === "source" ? target : ""
        } else {
            animeId = kind === "manager" ? target : ""
            animeSourceId = kind === "source" ? target : ""
        }
        apiClient.updateManagerPreferences(movieId, seriesId, animeId, movieSourceId, seriesSourceId, animeSourceId)
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

    function sourceProvidersFromResult() {
        return listValue(apiClient.mediaFindResult, "source_providers", "sourceProviders")
    }

    function scopedSourceOptionsForSelectedType() {
        var providers = sourceProvidersFromResult()
        if (providers.length === 0) {
            providers = sourceProvidersFor(selectedType)
        }
        var options = []
        var seen = {}
        for (var i = 0; i < providers.length; ++i) {
            var id = providerId(providers[i])
            if (id === "" || seen[id]) {
                continue
            }
            seen[id] = true
            options.push({
                id: id,
                label: providerLabel(providers[i]) || id
            })
        }
        return options
    }

    function defaultManagerProviderId() {
        var providerId = apiClient.mediaFindResult.default_manager_provider_id
        if (providerId === undefined || providerId === null) {
            providerId = apiClient.mediaFindResult.defaultManagerProviderId
        }
        return String(providerId || "")
    }

    function defaultSourceProviderId() {
        var providerId = apiClient.mediaFindResult.default_source_provider_id
        if (providerId === undefined || providerId === null) {
            providerId = apiClient.mediaFindResult.defaultSourceProviderId
        }
        return String(providerId || "")
    }

    function managerExists(providerId) {
        var id = String(providerId || "")
        if (id === "") {
            return false
        }
        var providers = managerProvidersFromResult()
        if (providers.length === 0) {
            providers = managerProvidersFor(selectedType)
        }
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var value = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            if (String(value || "") === id) {
                return true
            }
        }
        return false
    }

    function sourceExists(providerId) {
        var id = String(providerId || "")
        if (id === "") {
            return false
        }
        var providers = sourceProvidersFromResult()
        if (providers.length === 0) {
            providers = sourceProvidersFor(selectedType)
        }
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var value = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            if (String(value || "") === id) {
                return true
            }
        }
        return false
    }

    function routeExists(value) {
        var kind = routeKind(value)
        var id = routeProviderId(value)
        if (kind === "source") {
            return sourceExists(id)
        }
        if (kind === "manager") {
            return managerExists(id)
        }
        return false
    }

    function resolvedRouteForAdd() {
        var selected = selectedRoutePreferenceValue()
        if (selected !== "" && routeExists(selected)) {
            return selected
        }
        var defaultSource = defaultSourceProviderId()
        if (defaultSource !== "" && sourceExists(defaultSource)) {
            return routeValue("source", defaultSource)
        }
        var defaultManager = defaultManagerProviderId()
        if (defaultManager !== "" && managerExists(defaultManager)) {
            return routeValue("manager", defaultManager)
        }
        return ""
    }

    function resolvedSourceProviderForScopedAdd() {
        var route = resolvedRouteForAdd()
        if (routeKind(route) === "source" && sourceExists(routeProviderId(route))) {
            return routeProviderId(route)
        }
        var sourceId = selectedSourcePreferenceId()
        if (sourceId !== "" && sourceExists(sourceId)) {
            return sourceId
        }
        var defaultSource = defaultSourceProviderId()
        if (defaultSource !== "" && sourceExists(defaultSource)) {
            return defaultSource
        }
        var options = scopedSourceOptionsForSelectedType()
        return options.length > 0 ? String(options[0].id || "") : ""
    }

    function scopedOptionsVisible(item) {
        var type = lower(item && item.type ? item.type : selectedType)
        return type === "series" || type === "tv" || type === "anime"
    }

    function routeAddDisabledReason() {
        if (sourceProvidersFromResult().length === 0 && managerProvidersFromResult().length === 0) {
            return "No healthy route is available for this media type."
        }
        if (resolvedRouteForAdd() === "") {
            return "Select a route before adding."
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
                return displayText(payload.message, "error")
            }
        } catch (e) {
        }
        return displayText(text, "error")
    }

    function isFindEndpoint(endpoint, suffix) {
        return endpoint.indexOf("/api/v1/find/" + suffix) === 0
                || endpoint.indexOf("/api/v1/find-media/" + suffix) === 0
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
        var type = item && item.type ? String(item.type) : selectedType
        return lower(type) + "::" + title + "::" + year
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

    function markResultAdded(key) {
        var rowKey = String(key || "")
        if (rowKey === "") {
            return
        }
        var next = {}
        var current = addedResultKeys || {}
        for (var existingKey in current) {
            next[existingKey] = current[existingKey]
        }
        next[rowKey] = true
        addedResultKeys = next
    }

    function syncAddedResultsFromAcquisition() {
        var next = {}
        var current = addedResultKeys || {}
        for (var existingKey in current) {
            next[existingKey] = current[existingKey]
        }
        var results = findResults()
        for (var i = 0; i < results.length; ++i) {
            if (acquisitionForResult(results[i]) !== null) {
                next[resultKey(results[i])] = true
            }
        }
        addedResultKeys = next
    }

    function resultAlreadyAdded(item) {
        var key = resultKey(item)
        return acquisitionForResult(item) !== null || (addedResultKeys && addedResultKeys[key] === true)
    }

    function acquisitionPhaseCode(acquisition) {
        if (!acquisition) {
            return ""
        }
        return String(acquisition.phase || acquisition.stage || "")
    }

    function acquisitionStageColor(stage) {
        if (stage === "needs_attention" || stage === "failed" ||
                stage === "review_required" || stage === "quarantined") {
            return Theme.accentDanger
        }
        if (stage === "completed" || stage === "ready") {
            return Theme.accentSuccess
        }
        return Theme.accent
    }

    function acquisitionStageFill(stage) {
        if (stage === "needs_attention" || stage === "failed" ||
                stage === "review_required" || stage === "quarantined") {
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
        if (phase !== "downloading" && phase !== "materializing" &&
                phase !== "post_processing" && phase !== "importing") {
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

    function runAcquisitionAction(action, acquisition) {
        var confirmText = String(action.confirmText || action.confirm_text || "")
        if (confirmText !== "") {
            pendingAcquisitionAction = {
                action: action,
                acquisition: acquisition
            }
            acquisitionActionConfirmText.text = confirmText
            acquisitionActionConfirmDialog.title = String(action.label || "Confirm action")
            acquisitionActionConfirmDialog.open()
            return
        }
        executeAcquisitionAction(action, acquisition)
    }

    function executeAcquisitionAction(action, acquisition) {
        var actionId = String(action.id || "")
        if (actionId === "remove_acquisition_request" || actionId === "cancel_acquisition_downloads") {
            var subscriptionId = String(action.subscriptionId || action.subscription_id || "")
            if (subscriptionId === "" && acquisition) {
                subscriptionId = String(acquisition.intentId || acquisition.intent_id || "")
            }
            if (subscriptionId !== "") {
                apiClient.cancelAcquisitionSubscription(
                    subscriptionId,
                    String(action.cancelMode || action.cancel_mode || "dismiss"),
                    "User requested acquisition removal from Find Media.",
                    false)
            }
            return
        }
        if (actionId === "find_another_release") {
            var retryReleaseId = String(action.releaseId || action.release_id || "")
            if (retryReleaseId !== "") {
                apiClient.retryAcquisitionRelease(retryReleaseId, {
                    mode: String(action.retryMode || action.retry_mode || "source_discovery"),
                    reason: "Find another release from Find Media status."
                })
                return
            }
            apiClient.findAnotherRelease(String((acquisition && (acquisition.intentId || acquisition.intent_id)) || ""))
            return
        }
        if (actionId === "open_review") {
            var releaseId = String(action.releaseId || action.release_id || "")
            if (releaseId !== "" && stackView) {
                stackView.push(Qt.resolvedUrl("AcquisitionReviewView.qml"), {
                    stackView: stackView,
                    releaseId: releaseId,
                    subscriptionId: String(action.subscriptionId || action.subscription_id || "")
                })
            }
            return
        }
        if (actionId === "retry_import") {
            var importReleaseId = String(action.releaseId || action.release_id || "")
            if (importReleaseId !== "") {
                apiClient.retryAcquisitionRelease(importReleaseId, {
                    mode: String(action.retryMode || action.retry_mode || "import"),
                    reason: "Retry import from Find Media status."
                })
            }
            return
        }
        var extensionId = String(action.navigateExtensionId || action.navigate_extension_id || "")
        var view = String(action.navigateView || action.navigate_view || "")
        if (extensionId !== "" && (view === "" || view === "extension_control")) {
            if (stackView) {
                stackView.push(Qt.resolvedUrl("ExtensionControlView.qml"), {
                    stackView: stackView,
                    extensionId: extensionId
                })
            }
        }
    }

    function routeTargetLabel() {
        var route = resolvedRouteForAdd()
        var label = routeLabelByValue(route)
        if (label === "") {
            return "No route selected"
        }
        return "Route: " + label
    }

    function addResultToSelectedRoute(item) {
        var blockedReason = routeAddDisabledReason()
        if (blockedReason !== "") {
            addStatusText = blockedReason
            return
        }
        var route = resolvedRouteForAdd()
        var kind = routeKind(route)
        var providerId = routeProviderId(route)
        pendingAddKey = resultKey(item)
        addStatusText = ""
        if (kind === "source") {
            var options = {}
            if (providerId !== "") {
                options.sourceProviderId = providerId
            }
            apiClient.addMediaToAcquisition(selectedType, item, options)
            return
        }
        apiClient.addMediaToManager(selectedType, item, providerId, {})
    }

    function openScopedAddOptions(item) {
        addStatusText = ""
        scopedAddDialog.openFor(
            selectedType,
            item,
            resolvedSourceProviderForScopedAdd(),
            scopedSourceOptionsForSelectedType())
    }

    onSelectedTypeChanged: {
        selectedProviderIds = []
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
            root.syncAddedResultsFromAcquisition()
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
                root.statusText = root.displayText(error, "error")
            } else if (root.isFindEndpoint(endpoint, "preferences")) {
                root.statusText = root.displayText(error, "error")
            } else if (root.isFindEndpoint(endpoint, "add")) {
                root.pendingAddKey = ""
                root.addStatusText = root.formatAddError(error)
            } else if (root.isFindEndpoint(endpoint, "acquisition")) {
                root.pendingAddKey = ""
                root.addStatusText = root.formatAddError(error)
            }
        }

        function onMediaAddResultChanged() {
            var completedKey = root.pendingAddKey
            if (completedKey !== "") {
                root.markResultAdded(completedKey)
            }
            root.pendingAddKey = ""
            root.lastAddedIntentId = String(apiClient.mediaAddResult.intent_id || apiClient.mediaAddResult.intentId || "")
            var title = apiClient.mediaAddResult.title || "Media"
            var manager = apiClient.mediaAddResult.manager_label || apiClient.mediaAddResult.managerLabel || "manager"
            if (apiClient.mediaAddResult.nativeAcquisition) {
                root.addStatusText = title + " queued in Elixir acquisition."
            } else {
                root.addStatusText = title + " added via " + manager + "."
            }
            apiClient.fetchMediaAcquisition()
        }

        function onMediaAddLoadingChanged() {
            if (!apiClient.mediaAddLoading && root.pendingAddKey !== "" && root.addStatusText === "") {
                root.pendingAddKey = ""
            }
        }

        function onMediaAcquisitionChanged() {
            root.syncAddedResultsFromAcquisition()
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
                        text: "Routing"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        text: "Use for " + root.mediaTypeLabel(root.selectedType) + ":"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    ComboBox {
                        id: routePreferenceCombo
                        Layout.fillWidth: true
                        model: root.routeOptionsForSelectedType()
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: root.optionIndexForValue(model, root.selectedRoutePreferenceValue())
                        onActivated: {
                            var value = currentValue !== undefined ? String(currentValue) : ""
                            root.updateSelectedRoutePreference(value)
                        }
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
                        text: root.displayText(modelData.message || "", "providerError")
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
                    readonly property bool addComplete: root.resultAlreadyAdded(modelData)
                    readonly property string routeAddReason: root.routeAddDisabledReason()
                    readonly property var acquisition: root.acquisitionForResult(modelData)

                    width: ListView.view ? ListView.view.width : 0
                    radius: Theme.radiusMedium
                    color: index % 2 === 0 ? Theme.backgroundCard : Theme.backgroundCardRaised
                    border.color: rowHover.hovered ? Theme.accent : Theme.border
                    implicitHeight: rowContent.implicitHeight + Theme.spacingSmall * 2

                    HoverHandler {
                        id: rowHover
                    }

                    RowLayout {
                        id: rowContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingSmall
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
                                text: root.routeTargetLabel()
                                color: Theme.textMuted
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignRight
                                wrapMode: Text.WordWrap
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignRight
                                spacing: 6

                                Button {
                                    id: scopedOptionsButton
                                    text: "Options"
                                    visible: root.scopedOptionsVisible(modelData) && !resultRow.addComplete
                                    enabled: !apiClient.mediaAddLoading
                                    onClicked: root.openScopedAddOptions(modelData)
                                    background: Rectangle {
                                        radius: Theme.radiusSmall
                                        color: scopedOptionsButton.enabled ? Theme.backgroundCardRaised : Theme.surface
                                        border.color: scopedOptionsButton.enabled ? Theme.border : Theme.textDisabled
                                    }
                                    contentItem: Label {
                                        text: scopedOptionsButton.text
                                        color: scopedOptionsButton.enabled ? Theme.textPrimary : Theme.textDisabled
                                        font.pixelSize: 12
                                        font.family: Theme.fontBody
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }

                                Button {
                                    id: addResultButton
                                    text: resultRow.addPending ? "Adding..." : (resultRow.addComplete ? "Added" : "Add")
                                    enabled: !apiClient.mediaAddLoading &&
                                             !resultRow.addComplete &&
                                             resultRow.routeAddReason === ""
                                    onClicked: root.addResultToSelectedRoute(modelData)
                                    background: Rectangle {
                                        radius: Theme.radiusSmall
                                        color: addResultButton.enabled
                                               ? Theme.accent
                                               : (resultRow.addComplete
                                                  ? Theme.accentSuccessSoft
                                                  : Theme.backgroundCardRaised)
                                        border.color: addResultButton.enabled
                                                      ? Theme.accent
                                                      : (resultRow.addComplete
                                                         ? Theme.accentSuccess
                                                         : Theme.border)
                                    }
                                    contentItem: Label {
                                        text: addResultButton.text
                                        color: addResultButton.enabled
                                               ? "#17120A"
                                               : (resultRow.addComplete ? Theme.textPrimary : Theme.textDisabled)
                                        font.pixelSize: 12
                                        font.family: Theme.fontBody
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                text: resultRow.addComplete ? "" : resultRow.routeAddReason
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
                                              ? root.displayText(resultRow.acquisition.headline || resultRow.acquisition.detail || resultRow.acquisition.description || "", "acquisition")
                                              : ""
                                        color: Theme.textSecondary
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

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        visible: resultRow.acquisition !== null
                                                 && (resultRow.acquisition.actions || []).length > 0

                                        Repeater {
                                            model: resultRow.acquisition ? (resultRow.acquisition.actions || []) : []

                                            delegate: Button {
                                                required property var modelData
                                                text: root.displayText(modelData.label || "", "action")
                                                visible: text !== ""
                                                onClicked: root.runAcquisitionAction(modelData, resultRow.acquisition)
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

    ScopedAddDialog {
        id: scopedAddDialog

        onAcceptedScopedAdd: {
            root.addStatusText = "Scoped request queued in Elixir acquisition."
            apiClient.fetchMediaAcquisition()
        }
    }

    Dialog {
        id: acquisitionActionConfirmDialog
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Cancel | Dialog.Ok
        width: Math.min(root.width - 48, 420)
        onAccepted: {
            if (root.pendingAcquisitionAction) {
                root.executeAcquisitionAction(
                    root.pendingAcquisitionAction.action,
                    root.pendingAcquisitionAction.acquisition)
            }
            root.pendingAcquisitionAction = null
        }
        onRejected: root.pendingAcquisitionAction = null

        contentItem: Label {
            id: acquisitionActionConfirmText
            width: acquisitionActionConfirmDialog.width - 48
            wrapMode: Text.WordWrap
            color: Theme.textPrimary
            font.pixelSize: 13
            font.family: Theme.fontBody
        }
    }
}
