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
    property bool deleteBusy: false
    property string deleteStatusText: ""
    property string deleteResultText: ""
    property string episodeActionBusyId: ""
    property string episodeStatusText: ""
    property string blockedEpisodesStatusText: ""
    property var pendingEpisode: null
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
        if (episodeBlocked(episode)) {
            return "Blocked in Elixir"
        }
        return episode && episode.has_file ? "Available" : "Missing"
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
    }

    function selectSeason(seasonId) {
        if (!seasonId || seasonId === "" || seasonId === activeSeasonId) {
            return
        }
        activeSeasonId = seasonId
        activeSeasonDetail = null
        episodes = []
        seasonStatusText = ""
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
            apiClient.fetchMediaDetails(mediaId)
            refreshReviewQueue()
        }
    }

    onMediaIdChanged: {
        if (mediaId !== "") {
            apiClient.fetchMediaDetails(mediaId)
            refreshReviewQueue()
            resetSeasonState()
        }
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
                    subtitle: seasonStatusText
                }

                SeasonTabs {
                    Layout.fillWidth: true
                    visible: seasons && seasons.length > 0
                    seasons: root.seasons
                    activeSeasonId: root.activeSeasonId
                    onSeasonSelected: root.selectSeason(seasonId)
                }

                EmptyState {
                    Layout.fillWidth: true
                    implicitHeight: 132
                    visible: (!episodes || episodes.length === 0) && seasonStatusText === ""
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
                        available: modelData.has_file === true
                        blocked: root.episodeBlocked(modelData)
                        canDelete: root.episodeCanDelete(modelData)
                        canRestore: root.episodeCanRestore(modelData)
                        busy: root.episodeActionBusyId === modelData.id
                        onPlayRequested: apiClient.startPlayback(mediaId, modelData.id)
                        onDeleteRequested: root.openEpisodeDeleteDialog(modelData)
                        onRestoreRequested: {
                            episodeActionBusyId = modelData.id
                            episodeStatusText = ""
                            apiClient.restoreEpisode(modelData.id)
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
                    apiClient.fetchSeasons(obj.id)
                } else {
                    resetSeasonState()
                }
            }
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
            episodeDeleteDialog.close()
            pendingEpisode = null
            episodeStatusText = result && result.message ? result.message : "Episode deleted."
            refreshEpisodeState()
        }
        function onEpisodeRestored(episodeId, result) {
            episodeActionBusyId = ""
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
                episodes = items
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
                episodeStatusText = "Episode action failed: " + error
                return
            }
            if (endpoint === "/api/v1/library/items/" + mediaId + "/restore-blocked-episodes") {
                blockedEpisodesStatusText = "Restore failed: " + error
                return
            }
            if (endpoint.indexOf("/api/v1/library/items") === 0) {
                statusText = "Request failed: " + error
            } else if (endpoint.indexOf("/api/v1/library/series") === 0 || endpoint.indexOf("/api/v1/library/seasons") === 0) {
                seasonStatusText = "Request failed: " + error
            } else if (endpoint.indexOf("/api/v1/library/review") === 0) {
                reviewStatusText = "Request failed: " + error
            }
        }
    }
}
