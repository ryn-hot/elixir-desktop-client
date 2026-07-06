import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import Elixir 1.0

Dialog {
    id: root

    property string mediaType: "series"
    property var mediaItem: ({})
    property var sourceOptions: []
    property string selectedProviderId: ""
    property var activePreview: ({})
    property string selectedScopeType: "entire_title"
    property int selectedSeasonNumber: 0
    property string selectedArcId: ""
    property string selectedArcLabel: ""
    property var selectedArcTargetKeys: []
    property var selectedTargetKeys: []
    property string selectedAudioPreferenceMode: "any"
    property string rangeStartText: ""
    property string rangeEndText: ""
    property string episodeFilterText: ""
    property string statusText: ""
    property bool submitInFlight: false

    signal acceptedScopedAdd()

    function openFor(type, item, providerId, options) {
        mediaType = String(type || "series")
        mediaItem = item || ({})
        sourceOptions = options || []
        selectedProviderId = String(providerId || defaultSourceProviderId())
        if (selectedProviderId === "" && sourceOptions.length > 0) {
            selectedProviderId = String(sourceOptions[0].id || "")
        }
        resetSelectionState()
        open()
        loadPreview()
    }

    function resetSelectionState() {
        activePreview = ({})
        selectedScopeType = "entire_title"
        selectedSeasonNumber = 0
        selectedArcId = ""
        selectedArcLabel = ""
        selectedArcTargetKeys = []
        selectedTargetKeys = []
        selectedAudioPreferenceMode = "any"
        rangeStartText = ""
        rangeEndText = ""
        episodeFilterText = ""
        statusText = ""
        submitInFlight = false
    }

    function defaultSourceProviderId() {
        if (!sourceOptions || sourceOptions.length === 0) {
            return ""
        }
        return String(sourceOptions[0].id || "")
    }

    function sourceIndex() {
        for (var i = 0; i < sourceOptions.length; ++i) {
            if (String(sourceOptions[i].id || "") === selectedProviderId) {
                return i
            }
        }
        return 0
    }

    function mediaTitle() {
        return String(mediaItem.title || mediaItem.name || "this title")
    }

    function loadPreview() {
        resetSelectionState()
        apiClient.fetchFindMediaScopePreview(mediaType, mediaItem, selectedProviderId)
    }

    function previewCapabilities() {
        return activePreview.capabilities || {}
    }

    function capabilityEnabled(camelKey, snakeKey, fallback) {
        var caps = previewCapabilities()
        var value = caps[camelKey]
        if (value === undefined || value === null) {
            value = caps[snakeKey]
        }
        if (value === undefined || value === null) {
            return fallback
        }
        return !!value
    }

    function previewSeasons() {
        return activePreview.seasons || []
    }

    function previewArcs() {
        return activePreview.arcs || []
    }

    function previewBlockers() {
        return activePreview.blockers || []
    }

    function hasBlockers() {
        return previewBlockers().length > 0
    }

    function blockerText() {
        var blockers = previewBlockers()
        if (blockers.length === 0) {
            return ""
        }
        var blocker = blockers[0]
        var text = String(blocker.message || "Elixir cannot preview this title right now.")
        var detail = String(blocker.detail || "")
        return detail === "" ? text : (text + " " + detail)
    }

    function seasonEpisodeCount(season) {
        return Number(season.episodeCount || season.episode_count || (season.episodes || []).length || 0)
    }

    function seasonNumber(season) {
        return Number(season.seasonNumber || season.season_number || 0)
    }

    function seasonLabel(season) {
        var number = seasonNumber(season)
        return number > 0 ? ("Season " + number) : "Specials"
    }

    function seasonByNumber(number) {
        var seasons = previewSeasons()
        if (number <= 0) {
            return null
        }
        for (var i = 0; i < seasons.length; ++i) {
            if (seasonNumber(seasons[i]) === number) {
                return seasons[i]
            }
        }
        return null
    }

    function currentSeason() {
        return seasonByNumber(selectedSeasonNumber)
    }

    function currentSeasonEpisodes() {
        var season = currentSeason()
        return season ? (season.episodes || []) : []
    }

    function totalEpisodeCount() {
        var seasons = previewSeasons()
        var count = 0
        for (var i = 0; i < seasons.length; ++i) {
            count += seasonEpisodeCount(seasons[i])
        }
        return count
    }

    function episodeTargetKey(episode) {
        return String(episode.targetKey || episode.target_key || "")
    }

    function episodeSeasonNumber(episode) {
        return Number(episode.seasonNumber || episode.season_number || selectedSeasonNumber || 0)
    }

    function episodeNumber(episode) {
        return Number(episode.episodeNumber || episode.episode_number || 0)
    }

    function absoluteEpisodeNumber(episode) {
        return Number(episode.absoluteEpisodeNumber || episode.absolute_episode_number || 0)
    }

    function episodeTitle(episode) {
        return String(episode.title || "")
    }

    function episodeDisplayLabel(episode) {
        var key = episodeTargetKey(episode)
        var title = episodeTitle(episode)
        var absolute = absoluteEpisodeNumber(episode)
        if (absolute > 0 && key.indexOf("A") === 0) {
            return "Episode " + absolute + (title !== "" ? (" - " + title) : "")
        }
        var number = episodeNumber(episode)
        var prefix = key !== "" ? key : (number > 0 ? ("Episode " + number) : "Episode")
        return title !== "" ? (prefix + " - " + title) : prefix
    }

    function episodeSearchText(episode) {
        return (episodeTargetKey(episode) + " " +
                episodeDisplayLabel(episode) + " " +
                episodeSeasonNumber(episode) + " " +
                episodeNumber(episode) + " " +
                absoluteEpisodeNumber(episode)).toLowerCase()
    }

    function filteredSeasonEpisodes() {
        var filter = String(episodeFilterText || "").trim().toLowerCase()
        var episodes = currentSeasonEpisodes()
        if (filter === "") {
            return episodes
        }
        var result = []
        for (var i = 0; i < episodes.length; ++i) {
            if (episodeSearchText(episodes[i]).indexOf(filter) >= 0) {
                result.push(episodes[i])
            }
        }
        return result
    }

    function allTargetKeys() {
        var keys = []
        var seasons = previewSeasons()
        for (var i = 0; i < seasons.length; ++i) {
            var episodes = seasons[i].episodes || []
            for (var j = 0; j < episodes.length; ++j) {
                var key = episodeTargetKey(episodes[j])
                if (key !== "") {
                    keys.push(key)
                }
            }
        }
        return keys
    }

    function currentSeasonTargetKeys() {
        var keys = []
        var episodes = currentSeasonEpisodes()
        for (var i = 0; i < episodes.length; ++i) {
            var key = episodeTargetKey(episodes[i])
            if (key !== "") {
                keys.push(key)
            }
        }
        return keys
    }

    function filteredTargetKeys() {
        var keys = []
        var episodes = filteredSeasonEpisodes()
        for (var i = 0; i < episodes.length; ++i) {
            var key = episodeTargetKey(episodes[i])
            if (key !== "") {
                keys.push(key)
            }
        }
        return keys
    }

    function targetSelected(key) {
        var target = String(key || "")
        for (var i = 0; i < selectedTargetKeys.length; ++i) {
            if (String(selectedTargetKeys[i]) === target) {
                return true
            }
        }
        return false
    }

    function setTargetSelected(key, selected) {
        var target = String(key || "")
        if (target === "") {
            return
        }
        var next = []
        var exists = false
        for (var i = 0; i < selectedTargetKeys.length; ++i) {
            var value = String(selectedTargetKeys[i])
            if (value === target) {
                exists = true
                if (selected) {
                    next.push(value)
                }
            } else {
                next.push(value)
            }
        }
        if (selected && !exists) {
            next.push(target)
        }
        selectedTargetKeys = next
        statusText = ""
    }

    function setSelectedTargets(keys) {
        var seen = {}
        var next = []
        for (var i = 0; i < keys.length; ++i) {
            var key = String(keys[i] || "")
            if (key !== "" && !seen[key]) {
                seen[key] = true
                next.push(key)
            }
        }
        selectedTargetKeys = next
        statusText = ""
    }

    function clearSelectedTargets() {
        selectedTargetKeys = []
        statusText = ""
    }

    function firstSeasonNumber() {
        var seasons = previewSeasons()
        return seasons.length > 0 ? seasonNumber(seasons[0]) : 0
    }

    function inferredAnimeSeasonNumber() {
        if (mediaType !== "anime") {
            return 0
        }
        var title = mediaTitle().toLowerCase()
        var ordinal = title.match(/\b(\d+)(?:st|nd|rd|th)\s+season\b/)
        if (ordinal && ordinal.length > 1) {
            return Number(ordinal[1])
        }
        var explicit = title.match(/\bseason\s+(\d+)\b/)
        if (explicit && explicit.length > 1) {
            return Number(explicit[1])
        }
        var words = {
            "second": 2,
            "third": 3,
            "fourth": 4,
            "fifth": 5,
            "sixth": 6,
            "seventh": 7,
            "eighth": 8,
            "ninth": 9,
            "tenth": 10
        }
        for (var word in words) {
            if (title.indexOf(word + " season") >= 0) {
                return words[word]
            }
        }
        return 0
    }

    function preferredAnimeSeason() {
        var inferred = inferredAnimeSeasonNumber()
        if (inferred > 0) {
            return seasonByNumber(inferred)
        }
        var first = seasonByNumber(1)
        if (first !== null) {
            return first
        }
        var seasons = previewSeasons()
        return seasons.length === 1 ? seasons[0] : null
    }

    function preferredAnimeSeasonNumber() {
        var season = preferredAnimeSeason()
        return season ? seasonNumber(season) : 0
    }

    function defaultSeasonNumber() {
        if (mediaType === "anime") {
            return preferredAnimeSeasonNumber()
        }
        return firstSeasonNumber()
    }

    function selectedTitleDetail() {
        var season = preferredAnimeSeason()
        if (season === null) {
            return "Episodes not available"
        }
        var count = seasonEpisodeCount(season)
        return count > 0 ? (count + " episodes") : "Episodes not available"
    }

    function selectDefaultScope() {
        var seasons = previewSeasons()
        var arcs = previewArcs()
        if (mediaType === "anime") {
            if (arcs.length > 0 && capabilityEnabled("animeArcs", "anime_arcs", true)) {
                selectArc(arcs[0])
                return
            }
            var animeSeason = preferredAnimeSeason()
            if (animeSeason !== null && capabilityEnabled("seasons", "seasons", true)) {
                selectSeason(animeSeason)
                return
            }
            selectedScopeType = "season"
            selectedSeasonNumber = 0
            selectedArcId = ""
            selectedArcLabel = ""
            selectedArcTargetKeys = []
            statusText = ""
            return
        }
        if (seasons.length > 0 && capabilityEnabled("seasons", "seasons", true)) {
            selectSeason(seasons[0])
            return
        }
        selectedScopeType = "entire_title"
        selectedSeasonNumber = firstSeasonNumber()
    }

    function selectSeason(season) {
        selectedScopeType = "season"
        selectedSeasonNumber = seasonNumber(season)
        selectedArcId = ""
        selectedArcLabel = ""
        selectedArcTargetKeys = []
        statusText = ""
    }

    function selectRangeMode() {
        selectedScopeType = "range"
        if (selectedSeasonNumber <= 0) {
            selectedSeasonNumber = defaultSeasonNumber()
        }
        selectedArcId = ""
        selectedArcLabel = ""
        selectedArcTargetKeys = []
        statusText = ""
    }

    function selectSelectedTargetsMode() {
        selectedScopeType = "selected_targets"
        if (selectedSeasonNumber <= 0) {
            selectedSeasonNumber = defaultSeasonNumber()
        }
        selectedArcId = ""
        selectedArcLabel = ""
        selectedArcTargetKeys = []
        statusText = ""
    }

    function selectArc(arc) {
        selectedScopeType = "anime_arc"
        selectedArcId = String(arc.arcId || arc.arc_id || "")
        selectedArcLabel = String(arc.label || selectedArcId || "Anime arc")
        selectedArcTargetKeys = arc.targetKeys || arc.target_keys || []
        if (selectedSeasonNumber <= 0) {
            selectedSeasonNumber = firstSeasonNumber()
        }
        statusText = ""
    }

    function selectEntireTitle() {
        selectedScopeType = "entire_title"
        selectedSeasonNumber = firstSeasonNumber()
        selectedArcId = ""
        selectedArcLabel = ""
        selectedArcTargetKeys = []
        statusText = ""
    }

    function parseEpisodeInput(value) {
        var text = String(value || "").trim().toUpperCase()
        if (text === "") {
            return null
        }
        var seasonEpisode = text.match(/^S(\d{1,4})E(\d{1,5})$/)
        if (seasonEpisode && seasonEpisode.length >= 3) {
            return { seasonNumber: Number(seasonEpisode[1]), episodeNumber: Number(seasonEpisode[2]) }
        }
        var absolute = text.match(/^A(\d{1,6})$/)
        if (absolute && absolute.length >= 2) {
            return { absoluteEpisodeNumber: Number(absolute[1]) }
        }
        var plain = text.match(/^E?(\d{1,6})$/)
        if (plain && plain.length >= 2) {
            return { episodeNumber: Number(plain[1]) }
        }
        return null
    }

    function rangeTargets() {
        var start = parseEpisodeInput(rangeStartText)
        var end = parseEpisodeInput(rangeEndText)
        if (start === null || end === null) {
            return []
        }
        var season = selectedSeasonNumber
        if (start.seasonNumber !== undefined) {
            season = start.seasonNumber
        }
        if (end.seasonNumber !== undefined && end.seasonNumber !== season) {
            return []
        }
        var useAbsolute = start.absoluteEpisodeNumber !== undefined || end.absoluteEpisodeNumber !== undefined
        var startNumber = useAbsolute ? start.absoluteEpisodeNumber : start.episodeNumber
        var endNumber = useAbsolute ? end.absoluteEpisodeNumber : end.episodeNumber
        if (startNumber === undefined || endNumber === undefined || startNumber <= 0 || endNumber <= 0) {
            return []
        }
        var low = Math.min(startNumber, endNumber)
        var high = Math.max(startNumber, endNumber)
        var matches = []
        var seasons = previewSeasons()
        for (var i = 0; i < seasons.length; ++i) {
            var episodes = seasons[i].episodes || []
            for (var j = 0; j < episodes.length; ++j) {
                var episode = episodes[j]
                var number = useAbsolute ? absoluteEpisodeNumber(episode) : episodeNumber(episode)
                if (!useAbsolute && episodeSeasonNumber(episode) !== season) {
                    continue
                }
                if (number >= low && number <= high) {
                    matches.push(episode)
                }
            }
        }
        return matches
    }

    function rangeTargetKeys() {
        var keys = []
        var episodes = rangeTargets()
        for (var i = 0; i < episodes.length; ++i) {
            var key = episodeTargetKey(episodes[i])
            if (key !== "") {
                keys.push(key)
            }
        }
        return keys
    }

    function sourceDisabledReason() {
        if (!sourceOptions || sourceOptions.length === 0 || selectedProviderId === "") {
            return "Install or enable an acquisition source from Extensions."
        }
        if (hasBlockers()) {
            return blockerText()
        }
        if (previewSeasons().length === 0 && mediaType !== "movie") {
            return apiClient.mediaScopePreviewLoading ? "" : "No selectable episodes are available yet."
        }
        return ""
    }

    function selectionDisabledReason() {
        if (selectedScopeType === "range") {
            if (rangeStartText.trim() === "" || rangeEndText.trim() === "") {
                return "Enter a start and end episode."
            }
            if (rangeTargetKeys().length === 0) {
                return "No episodes match that range."
            }
        }
        if (selectedScopeType === "selected_targets" && selectedTargetKeys.length === 0) {
            return "Select one or more episodes."
        }
        if (selectedScopeType === "anime_arc" && selectedArcTargetKeys.length === 0) {
            return "This arc has no validated episode coverage."
        }
        if (selectedScopeType === "season" && currentSeasonTargetKeys().length === 0) {
            if (mediaType === "anime") {
                return "This title has no selectable episodes."
            }
            return "This season has no selectable episodes."
        }
        if (selectedScopeType === "entire_title" && totalEpisodeCount() === 0 && mediaType !== "movie") {
            return "No selectable episodes are available yet."
        }
        return ""
    }

    function disabledReason() {
        var source = sourceDisabledReason()
        if (source !== "") {
            return source
        }
        return selectionDisabledReason()
    }

    function canSubmit() {
        return !apiClient.mediaScopePreviewLoading
                && !apiClient.mediaAddLoading
                && selectedProviderId !== ""
                && sourceOptions.length > 0
                && disabledReason() === ""
    }

    function selectedCount() {
        if (selectedScopeType === "season") {
            return currentSeasonTargetKeys().length
        }
        if (selectedScopeType === "range") {
            return rangeTargetKeys().length
        }
        if (selectedScopeType === "selected_targets") {
            return selectedTargetKeys.length
        }
        if (selectedScopeType === "anime_arc") {
            return selectedArcTargetKeys.length
        }
        return totalEpisodeCount()
    }

    function selectedSummary() {
        if (selectedScopeType === "season") {
            if (mediaType === "anime") {
                var titleCount = selectedCount()
                return titleCount > 0 ? ("Selected title, " + titleCount + " episodes") : "Selected title"
            }
            return "Season " + selectedSeasonNumber + ", " + selectedCount() + " episodes"
        }
        if (selectedScopeType === "range") {
            return selectedCount() + " episodes from range"
        }
        if (selectedScopeType === "selected_targets") {
            return selectedCount() + " selected episodes"
        }
        if (selectedScopeType === "anime_arc") {
            return selectedArcLabel + ", " + selectedCount() + " episodes"
        }
        var count = totalEpisodeCount()
        if (count > 0) {
            return count + " episodes"
        }
        return mediaTitle()
    }

    function animeAudioPreferenceForSubmit() {
        if (mediaType === "anime" && selectedAudioPreferenceMode === "dub") {
            return { mode: "prefer_dub", language: "en" }
        }
        return ({})
    }

    function submitLabel() {
        if (apiClient.mediaAddLoading && submitInFlight) {
            return "Adding..."
        }
        if (selectedScopeType === "season") {
            if (mediaType === "anime") {
                return "Add selected title"
            }
            return "Add Season " + selectedSeasonNumber
        }
        if (selectedScopeType === "range") {
            return "Add range"
        }
        if (selectedScopeType === "selected_targets") {
            return "Add selected"
        }
        if (selectedScopeType === "anime_arc") {
            return "Add arc"
        }
        return "Add title"
    }

    function submitScope() {
        if (!canSubmit()) {
            statusText = disabledReason()
            return
        }

        var scope = { type: selectedScopeType }
        if (selectedScopeType === "season") {
            scope.seasonNumber = selectedSeasonNumber
        } else if (selectedScopeType === "range") {
            scope.type = "range"
            scope.targetKeys = rangeTargetKeys()
            scope.seasonNumber = selectedSeasonNumber
            var start = parseEpisodeInput(rangeStartText)
            var end = parseEpisodeInput(rangeEndText)
            if (start && start.episodeNumber !== undefined) {
                scope.episodeStart = start.episodeNumber
            }
            if (end && end.episodeNumber !== undefined) {
                scope.episodeEnd = end.episodeNumber
            }
            if (start && start.absoluteEpisodeNumber !== undefined) {
                scope.absoluteEpisodeStart = start.absoluteEpisodeNumber
            }
            if (end && end.absoluteEpisodeNumber !== undefined) {
                scope.absoluteEpisodeEnd = end.absoluteEpisodeNumber
            }
        } else if (selectedScopeType === "selected_targets") {
            scope.type = "selected_targets"
            scope.targetKeys = selectedTargetKeys
        } else if (selectedScopeType === "anime_arc") {
            scope.type = "anime_arc"
            scope.arcId = selectedArcId
            scope.arcLabel = selectedArcLabel
            scope.targetKeys = selectedArcTargetKeys
        }
        submitInFlight = true
        statusText = ""
        apiClient.addScopedMediaFromFind(
            mediaType,
            mediaItem,
            selectedProviderId,
            scope,
            "",
            animeAudioPreferenceForSubmit())
    }

    modal: true
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? Math.max(Theme.spacingLarge, (parent.height - height) / 2) : Theme.spacingLarge
    width: Math.min((parent ? parent.width : 900) * 0.92, 840)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    onClosed: {
        statusText = ""
        submitInFlight = false
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
            spacing: Theme.space4

            Label {
                text: "Choose what to add"
                color: Theme.textPrimary
                font.pixelSize: 20
                font.family: Theme.fontDisplay
                font.weight: Font.DemiBold
            }

            Label {
                Layout.fillWidth: true
                text: "Create a one-time request for a title, season, range, arc, or exact episodes. Elixir queues only this selection."
                color: Theme.textSecondary
                font.pixelSize: 13
                font.family: Theme.fontBody
                wrapMode: Text.WordWrap
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 58
            radius: Theme.radius6
            color: Theme.panelSoft
            border.color: Theme.borderSubtle

            RowLayout {
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
                        text: root.sourceOptions.length > 0
                              ? "Searches use this installed source extension."
                              : "Install or enable a source extension before adding scoped media."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        elide: Text.ElideRight
                    }
                }

                ComboBox {
                    id: sourceCombo
                    Layout.preferredWidth: 280
                    model: root.sourceOptions
                    textRole: "label"
                    valueRole: "id"
                    currentIndex: root.sourceIndex()
                    visible: root.sourceOptions.length > 1
                    enabled: !apiClient.mediaScopePreviewLoading && !apiClient.mediaAddLoading
                    contentItem: Label {
                        leftPadding: 10
                        rightPadding: 26
                        text: sourceCombo.displayText
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
                        if (index >= 0 && index < root.sourceOptions.length) {
                            root.selectedProviderId = String(root.sourceOptions[index].id || "")
                            root.loadPreview()
                        }
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 30
                    Layout.preferredWidth: Math.min(280, Math.max(sourceLabel.implicitWidth + Theme.space20, 150))
                    radius: Theme.radiusSmall
                    color: root.sourceOptions.length === 0 ? Theme.accentDangerSoft : Theme.surfaceRaised
                    border.color: root.sourceOptions.length === 0 ? Theme.accentDanger : Theme.borderSubtle
                    visible: root.sourceOptions.length <= 1

                    Label {
                        id: sourceLabel
                        anchors.centerIn: parent
                        width: parent.width - Theme.space16
                        text: root.sourceOptions.length === 1
                              ? root.sourceOptions[0].label
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

        BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: apiClient.mediaScopePreviewLoading
            visible: running
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.hasBlockers()
            radius: Theme.radius6
            color: Theme.accentDangerSoft
            border.color: Theme.accentDanger
            implicitHeight: blockerLabel.implicitHeight + Theme.space16

            Label {
                id: blockerLabel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Theme.space8
                text: root.blockerText()
                color: Theme.textPrimary
                font.pixelSize: 12
                font.family: Theme.fontBody
                wrapMode: Text.WordWrap
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space10
            visible: !apiClient.mediaScopePreviewLoading && !root.hasBlockers()

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                visible: root.mediaType === "anime"

                Label {
                    text: "Audio"
                    color: Theme.textPrimary
                    font.pixelSize: 13
                    font.family: Theme.fontBody
                    font.weight: Font.DemiBold
                }

                Repeater {
                    model: [
                        { id: "any", label: "Any" },
                        { id: "dub", label: "Dub" }
                    ]

                    delegate: Button {
                        id: audioPreferenceButton
                        required property var modelData
                        text: modelData.label
                        enabled: !apiClient.mediaAddLoading
                        onClicked: {
                            root.selectedAudioPreferenceMode = modelData.id
                            root.statusText = ""
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: root.selectedAudioPreferenceMode === modelData.id
                                   ? Theme.surfaceHover
                                   : Theme.backgroundCardRaised
                            border.color: root.selectedAudioPreferenceMode === modelData.id
                                          ? Theme.accent
                                          : Theme.border
                        }
                        contentItem: Label {
                            text: audioPreferenceButton.text
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            Flow {
                id: scopeFlow
                Layout.fillWidth: true
                spacing: Theme.space8

                Repeater {
                    model: [
                        {
                            id: "entire_title",
                            label: "Entire title",
                            detail: root.totalEpisodeCount() > 0 ? (root.totalEpisodeCount() + " episodes") : "Everything available",
                            enabled: root.capabilityEnabled("entireTitle", "entire_title", true),
                            visible: root.mediaType !== "anime"
                        },
                        {
                            id: "season",
                            label: root.mediaType === "anime" ? "Selected title" : "Season",
                            detail: root.mediaType === "anime"
                                    ? root.selectedTitleDetail()
                                    : (root.selectedSeasonNumber > 0 ? ("Season " + root.selectedSeasonNumber) : "Choose a season"),
                            enabled: (root.mediaType === "anime"
                                      ? root.preferredAnimeSeason() !== null
                                      : root.previewSeasons().length > 0)
                                     && root.capabilityEnabled("seasons", "seasons", true),
                            visible: root.mediaType === "anime" || root.previewSeasons().length > 0
                        },
                        {
                            id: "range",
                            label: "Range",
                            detail: root.rangeTargetKeys().length > 0 ? (root.rangeTargetKeys().length + " episodes") : "Enter a contiguous slice",
                            enabled: (root.mediaType === "anime"
                                      ? root.preferredAnimeSeason() !== null
                                      : root.previewSeasons().length > 0)
                                     && root.capabilityEnabled("episodeRange", "episode_range", true),
                            visible: root.mediaType === "anime" || root.previewSeasons().length > 0
                        },
                        {
                            id: "selected_targets",
                            label: "Selected episodes",
                            detail: root.selectedTargetKeys.length > 0 ? (root.selectedTargetKeys.length + " selected") : "Pick exact episodes",
                            enabled: (root.mediaType === "anime"
                                      ? root.preferredAnimeSeason() !== null
                                      : root.previewSeasons().length > 0)
                                     && root.capabilityEnabled("selectedEpisodes", "selected_episodes", true),
                            visible: root.mediaType === "anime" || root.previewSeasons().length > 0
                        },
                        {
                            id: "anime_arc",
                            label: "Anime arc",
                            detail: root.selectedArcLabel !== "" ? root.selectedArcLabel : "Choose an arc",
                            enabled: root.previewArcs().length > 0 && root.capabilityEnabled("animeArcs", "anime_arcs", true),
                            visible: root.previewArcs().length > 0
                        }
                    ].filter(function(option) { return option.visible })

                    delegate: Rectangle {
                        required property var modelData
                        width: Math.min(196, Math.max(146, (scopeFlow.width - Theme.space16) / 3))
                        height: 68
                        radius: Theme.radius6
                        color: root.selectedScopeType === modelData.id ? Theme.surfaceHover : Theme.panelSoft
                        border.color: root.selectedScopeType === modelData.id
                                      ? Theme.accent
                                      : (modelData.enabled ? Theme.borderSubtle : Theme.textDisabled)
                        opacity: modelData.enabled ? 1.0 : 0.45

                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.enabled && !apiClient.mediaAddLoading
                            onClicked: {
                                if (modelData.id === "entire_title") {
                                    root.selectEntireTitle()
                                } else if (modelData.id === "season") {
                                    root.selectedScopeType = "season"
                                    if (root.selectedSeasonNumber <= 0) {
                                        root.selectedSeasonNumber = root.defaultSeasonNumber()
                                    }
                                    root.statusText = ""
                                } else if (modelData.id === "range") {
                                    root.selectRangeMode()
                                } else if (modelData.id === "selected_targets") {
                                    root.selectSelectedTargetsMode()
                                } else if (modelData.id === "anime_arc" && root.previewArcs().length > 0) {
                                    root.selectArc(root.previewArcs()[0])
                                }
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.space10
                            spacing: 3

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
                                text: modelData.detail
                                color: Theme.textSecondary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            Flow {
                id: seasonFlow
                Layout.fillWidth: true
                spacing: Theme.space8
                visible: root.mediaType !== "anime" &&
                         root.previewSeasons().length > 0 &&
                         (root.selectedScopeType === "season" ||
                          root.selectedScopeType === "range" ||
                          root.selectedScopeType === "selected_targets")

                Repeater {
                    model: root.previewSeasons()

                    delegate: Button {
                        id: seasonButton
                        required property var modelData
                        text: root.seasonLabel(modelData) + "  " + root.seasonEpisodeCount(modelData)
                        enabled: !apiClient.mediaAddLoading
                        onClicked: {
                            root.selectedSeasonNumber = root.seasonNumber(modelData)
                            root.episodeFilterText = ""
                            root.statusText = ""
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: root.selectedSeasonNumber === root.seasonNumber(modelData)
                                   ? Theme.surfaceHover
                                   : Theme.backgroundCardRaised
                            border.color: root.selectedSeasonNumber === root.seasonNumber(modelData)
                                          ? Theme.accent
                                          : Theme.border
                        }
                        contentItem: Label {
                            text: seasonButton.text
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                visible: root.selectedScopeType === "range"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space8

                    TextField {
                        Layout.preferredWidth: 128
                        text: root.rangeStartText
                        placeholderText: "From"
                        color: Theme.textPrimary
                        placeholderTextColor: Theme.textMuted
                        selectionColor: Theme.accent
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        onTextChanged: root.rangeStartText = text
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                    }

                    TextField {
                        Layout.preferredWidth: 128
                        text: root.rangeEndText
                        placeholderText: "To"
                        color: Theme.textPrimary
                        placeholderTextColor: Theme.textMuted
                        selectionColor: Theme.accent
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        onTextChanged: root.rangeEndText = text
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.mediaType === "anime"
                              ? "Use episode numbers like 1, 12, or A012."
                              : "Use numbers like 647, S01E647, or A0647."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                visible: root.selectedScopeType === "selected_targets"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space8

                    TextField {
                        Layout.fillWidth: true
                        text: root.episodeFilterText
                        placeholderText: root.mediaType === "anime"
                                         ? "Filter by episode, title, or absolute number"
                                         : "Filter by episode, title, SxxEyy, or absolute number"
                        color: Theme.textPrimary
                        placeholderTextColor: Theme.textMuted
                        selectionColor: Theme.accent
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        onTextChanged: root.episodeFilterText = text
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                    }

                    Label {
                        text: root.selectedTargetKeys.length + " selected"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space8

                    ActionButton {
                        text: root.mediaType === "anime" ? "All episodes" : "All in season"
                        compact: true
                        onClicked: root.setSelectedTargets(root.currentSeasonTargetKeys())
                    }

                    ActionButton {
                        text: root.episodeFilterText.trim() === "" ? "All visible" : "Filtered"
                        compact: true
                        enabled: root.filteredTargetKeys().length > 0
                        onClicked: root.setSelectedTargets(root.filteredTargetKeys())
                    }

                    ActionButton {
                        text: "Clear"
                        compact: true
                        onClicked: root.clearSelectedTargets()
                    }

                    Item { Layout.fillWidth: true }
                }

                ScrollView {
                    id: episodeListScroll
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(226, Math.max(96, root.filteredSeasonEpisodes().length * 38))
                    clip: true
                    contentWidth: availableWidth
                    contentHeight: episodeListColumn.implicitHeight
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical.policy: contentHeight > height + 1
                                               ? ScrollBar.AsNeeded
                                               : ScrollBar.AlwaysOff
                    ScrollBar.vertical.interactive: true
                    ScrollBar.vertical.width: 6
                    ScrollBar.vertical.contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: episodeListScroll.ScrollBar.vertical.pressed
                               ? Theme.textSecondary
                               : Qt.rgba(1, 1, 1, episodeListScroll.ScrollBar.vertical.active ? 0.34 : 0.18)
                    }
                    background: Rectangle { color: "transparent" }

                    ColumnLayout {
                        id: episodeListColumn
                        width: episodeListScroll.availableWidth
                        spacing: Theme.space4

                        Repeater {
                            model: root.filteredSeasonEpisodes()

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: Theme.radiusSmall
                                color: root.targetSelected(root.episodeTargetKey(modelData)) ? Theme.surfaceHover : Theme.panelSoft
                                border.color: root.targetSelected(root.episodeTargetKey(modelData)) ? Theme.accent : Theme.borderSubtle

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space8
                                    anchors.rightMargin: Theme.space8
                                    spacing: Theme.space8

                                    CheckBox {
                                        checked: root.targetSelected(root.episodeTargetKey(modelData))
                                        onToggled: root.setTargetSelected(root.episodeTargetKey(modelData), checked)
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.episodeDisplayLabel(modelData)
                                        color: Theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: Theme.fontBody
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        text: root.episodeTargetKey(modelData)
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

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                visible: root.selectedScopeType === "anime_arc" && root.previewArcs().length > 0

                ScrollView {
                    id: arcListScroll
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(180, Math.max(82, root.previewArcs().length * 54))
                    clip: true
                    contentWidth: availableWidth
                    contentHeight: arcListColumn.implicitHeight
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical.policy: contentHeight > height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    background: Rectangle { color: "transparent" }

                    ColumnLayout {
                        id: arcListColumn
                        width: arcListScroll.availableWidth
                        spacing: Theme.space4

                        Repeater {
                            model: root.previewArcs()

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 48
                                radius: Theme.radiusSmall
                                color: root.selectedArcId === String(modelData.arcId || modelData.arc_id || "") ? Theme.surfaceHover : Theme.panelSoft
                                border.color: root.selectedArcId === String(modelData.arcId || modelData.arc_id || "") ? Theme.accent : Theme.borderSubtle

                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !apiClient.mediaAddLoading
                                    onClicked: root.selectArc(modelData)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space10
                                    anchors.rightMargin: Theme.space10
                                    spacing: Theme.space8

                                    Label {
                                        Layout.fillWidth: true
                                        text: String(modelData.label || modelData.arcId || modelData.arc_id || "Anime arc")
                                        color: Theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: Theme.fontBody
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        text: ((modelData.targetKeys || modelData.target_keys || []).length) + " episodes"
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
        }

        InlineToast {
            Layout.fillWidth: true
            text: root.statusText !== ""
                  ? root.statusText
                  : (root.disabledReason() !== "" ? root.disabledReason() : ("Selected: " + root.selectedSummary()))
            autoClear: false
            color: root.disabledReason() === "" ? Theme.textSecondary : Theme.accentDanger
            font.pixelSize: 12
            font.family: Theme.fontBody
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space8

            ActionButton {
                text: "Cancel"
                compact: true
                enabled: !apiClient.mediaAddLoading
                onClicked: root.close()
            }

            Item { Layout.fillWidth: true }

            ActionButton {
                text: root.submitLabel()
                compact: true
                variant: "primary"
                Layout.preferredWidth: 136
                enabled: root.canSubmit()
                onClicked: root.submitScope()
            }
        }
    }

    Connections {
        target: apiClient

        function onMediaScopePreviewChanged() {
            if (!root.opened) {
                return
            }
            root.activePreview = apiClient.mediaScopePreview || ({})
            root.selectDefaultScope()
        }

        function onMediaAddResultChanged() {
            if (!root.opened || !root.submitInFlight) {
                return
            }
            root.submitInFlight = false
            root.acceptedScopedAdd()
            root.close()
        }

        function onMediaAddLoadingChanged() {
            if (!apiClient.mediaAddLoading && root.submitInFlight && root.statusText === "") {
                root.submitInFlight = false
            }
        }

        function onRequestFailed(endpoint, error) {
            if (!root.opened) {
                return
            }
            if (endpoint.indexOf("/api/v1/find-media/scope-preview") === 0
                    || endpoint.indexOf("/api/v1/find/media/scope-preview") === 0
                    || endpoint.indexOf("/api/v1/find/scope-preview") === 0) {
                root.statusText = String(error || "Scope preview failed.")
            } else if (endpoint.indexOf("/api/v1/find-media/scoped-add") === 0
                       || endpoint.indexOf("/api/v1/find/media/scoped-add") === 0
                       || endpoint.indexOf("/api/v1/find/scoped-add") === 0) {
                root.submitInFlight = false
                root.statusText = String(error || "Scoped add failed.")
            }
        }
    }
}
