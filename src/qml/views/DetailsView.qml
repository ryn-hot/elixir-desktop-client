import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Qt5Compat.GraphicalEffects

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
        return meta.bannerImage || meta.banner || meta.backdrop || meta.background || ""
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
        var value = detailValue(details, ["banner_url", "backdrop_url", "bannerUrl", "backdropUrl"])
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
        contentHeight: contentColumn.implicitHeight + Theme.spacingXLarge
        clip: true

        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: Theme.spacingXLarge
            anchors.margins: Theme.spacingXLarge

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                clip: true
                implicitHeight: headerRow.implicitHeight + Theme.spacingLarge * 2

                Image {
                    id: headerBanner
                    anchors.fill: parent
                    source: bannerSource()
                    fillMode: Image.PreserveAspectCrop
                    visible: source !== ""
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.55)
                    visible: headerBanner.visible
                }

                RowLayout {
                    id: headerRow
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingLarge

                    Rectangle {
                        Layout.preferredWidth: 220
                        Layout.preferredHeight: 320
                        radius: Theme.radiusMedium
                        color: Theme.backgroundCard
                        border.color: Theme.border
                        clip: true

                        Image {
                            id: posterImage
                            anchors.fill: parent
                            source: posterSource()
                            fillMode: Image.PreserveAspectCrop
                            visible: source !== ""
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Theme.backgroundCard
                            visible: posterImage.source === ""
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: details ? details.title : (libraryItem ? libraryItem.title : "Loading...")
                            color: Theme.textPrimary
                            font.pixelSize: 24
                            font.family: Theme.fontDisplay
                            font.weight: Font.DemiBold
                        }

                        RowLayout {
                            spacing: Theme.spacingSmall
                            PillTag { text: details ? details.type : (libraryItem ? libraryItem.type : "") }
                            PillTag { text: details && details.year ? details.year : (libraryItem && libraryItem.year ? libraryItem.year : "") }
                            PillTag { text: details && details.runtime_seconds ? details.runtime_seconds + "s" : (libraryItem && libraryItem.runtime ? libraryItem.runtime + "s" : "") }
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall
                            visible: {
                                var list = details && details.genres ? details.genres : (libraryItem ? libraryItem.genres : [])
                                return list && list.length > 0
                            }

                            Repeater {
                                model: details && details.genres ? details.genres : (libraryItem ? libraryItem.genres : [])
                                delegate: PillTag { text: modelData }
                            }
                        }

                        Label {
                            text: details && details.description
                                  ? details.description
                                  : (libraryItem && libraryItem.overview ? libraryItem.overview : "No description available yet.")
                            color: Theme.textSecondary
                            font.pixelSize: 13
                            font.family: Theme.fontBody
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            spacing: Theme.spacingMedium
                            Button {
                                text: "Play"
                                enabled: details !== null
                                onClicked: apiClient.startPlayback(mediaId, "")
                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: Theme.accent
                                }
                                contentItem: Label {
                                    text: parent.text
                                    color: "#111111"
                                    font.pixelSize: 13
                                    font.family: Theme.fontBody
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                            Button {
                                text: "Back"
                                onClicked: {
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
                                    font.pixelSize: 13
                                    font.family: Theme.fontBody
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                        Label {
                            text: statusText
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            visible: statusText !== "" && details !== null
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                visible: statusText !== "" && details === null

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    Label {
                        text: "Unable to load details"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        text: statusText
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        wrapMode: Text.Wrap
                    }

                    Button {
                        text: "Retry"
                        onClicked: apiClient.fetchMediaDetails(mediaId)
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

            // Season Selector (Dropdown)
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                Layout.leftMargin: Theme.spacingLarge
                visible: isSeriesType() && details !== null && seasons && seasons.length > 0
                z: 100 // Ensure dropdown appears on top

                property bool isOpen: false
                property var currentSeason: {
                    if (!seasons) return null
                    for (var i = 0; i < seasons.length; i++) {
                        if (seasons[i].id === activeSeasonId) return seasons[i]
                    }
                    return null
                }

                // Dropdown Header
                RowLayout {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    TapHandler {
                        onTapped: parent.parent.isOpen = !parent.parent.isOpen
                    }

                    // Arrow Icon
                    Text {
                        text: "▼"
                        color: "white"
                        font.pixelSize: 14
                        rotation: parent.parent.isOpen ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: 200 } }
                    }

                    // Selected Season Text
                    Label {
                        text: parent.parent.currentSeason 
                              ? (parent.parent.currentSeason.title || "Season " + parent.parent.currentSeason.season_number)
                              : "Select Season"
                        color: "white"
                        font.pixelSize: 24
                        font.family: Theme.headerFont.family
                        font.weight: Font.Bold
                    }
                }

                // Dropdown List Overlay
                Rectangle {
                    id: dropdownList
                    width: 400
                    height: Math.min(seasonListView.contentHeight + 20, 400)
                    color: "#1f2124" // Theme.bgSidebar or similar dark
                    radius: 8
                    border.color: Theme.border
                    border.width: 1
                    visible: parent.isOpen
                    y: 40 // Below header
                    x: 0
                    
                    // Shadow
                    layer.enabled: true
                    layer.effect: DropShadow {
                        transparentBorder: true
                        horizontalOffset: 0
                        verticalOffset: 4
                        radius: 12
                        samples: 25
                        color: "#80000000"
                    }

                    ListView {
                        id: seasonListView
                        anchors.fill: parent
                        anchors.margins: 10
                        clip: true
                        model: seasons ? seasons : []
                        
                        delegate: Rectangle {
                            width: ListView.view.width
                            height: 40
                            color: hoverHandler.hovered ? "#33ffffff" : "transparent"
                            radius: 4

                            HoverHandler { id: hoverHandler }

                            TapHandler {
                                onTapped: {
                                    selectSeason(modelData.id)
                                    dropdownList.parent.isOpen = false
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                
                                Label {
                                    text: modelData.title || ("Season " + modelData.season_number)
                                    color: modelData.id === activeSeasonId ? Theme.accent : "white"
                                    font.pixelSize: 16
                                    font.weight: modelData.id === activeSeasonId ? Font.Bold : Font.Normal
                                    Layout.fillWidth: true
                                }

                                Label {
                                    text: (modelData.episode_count || 0) + " Episodes"
                                    color: "#80ffffff"
                                    font.pixelSize: 14
                                }
                            }
                        }
                    }
                }
            }

            // Episodes List
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingLarge
                spacing: 15
                visible: isSeriesType() && details !== null

                Label {
                    text: "Episodes"
                    color: Theme.textPrimary
                    font.pixelSize: 18
                    font.family: Theme.headerFont.family
                    font.weight: Font.Bold
                    visible: episodes && episodes.length > 0
                }

                Repeater {
                    model: episodes ? episodes : []
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        height: 100
                        color: "transparent" // Transparent background for list items
                        
                        RowLayout {
                            anchors.fill: parent
                            spacing: 15

                            // Thumbnail
                            Rectangle {
                                Layout.preferredWidth: 178 // 16:9 roughly
                                Layout.preferredHeight: 100
                                radius: 4
                                color: Theme.bgCard
                                clip: true
                                
                                Image {
                                    anchors.fill: parent
                                    source: artworkUrl(modelData.thumbnail_url, 356, 200)
                                    fillMode: Image.PreserveAspectCrop
                                    visible: source !== ""
                                }
                                
                                // Play Overlay
                                Rectangle {
                                    anchors.fill: parent
                                    color: "#66000000"
                                    visible: episodeMouseArea.containsMouse
                                    
                                    Image {
                                        source: "qrc:/icons/play.svg" // Ensure this icon exists or use a shape
                                        width: 32
                                        height: 32
                                        anchors.centerIn: parent
                                        visible: false // Hiding for now if icon missing, or use rectangle
                                    }
                                    
                                    // Fallback Play Icon
                                    Rectangle {
                                        width: 30
                                        height: 30
                                        radius: 15
                                        color: Theme.accent
                                        anchors.centerIn: parent
                                        
                                        Canvas {
                                            anchors.fill: parent
                                            onPaint: {
                                                var ctx = getContext("2d");
                                                ctx.fillStyle = "#111";
                                                ctx.beginPath();
                                                ctx.moveTo(11, 8);
                                                ctx.lineTo(21, 15);
                                                ctx.lineTo(11, 22);
                                                ctx.closePath();
                                                ctx.fill();
                                            }
                                        }
                                    }
                                }
                            }

                            // Info
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 4
                                
                                Label {
                                    text: (modelData.episode_number ? (modelData.episode_number + ". ") : "") + (modelData.title || "Episode " + modelData.episode_number)
                                    color: modelData.has_file ? Theme.textPrimary : Theme.textMuted
                                    font.pixelSize: 15
                                    font.family: Theme.bodyFont.family
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                
                                Label {
                                    text: modelData.description || "No description available."
                                    color: Theme.textSecondary
                                    font.pixelSize: 13
                                    font.family: Theme.bodyFont.family
                                    elide: Text.ElideRight
                                    maximumLineCount: 3
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                }
                                
                                Label {
                                    text: modelData.has_file ? "Available" : "Missing" // Could add duration here
                                    color: modelData.has_file ? Theme.textMuted : Theme.accent
                                    font.pixelSize: 11
                                    font.family: Theme.bodyFont.family
                                }
                            }
                        }
                        
                        MouseArea {
                            id: episodeMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: modelData.has_file ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (modelData.has_file) {
                                    apiClient.startPlayback(mediaId, modelData.id) // Assuming episode ID is file ID or handled
                                    // Note: API might need specific file ID logic if episode maps to file
                                }
                            }
                        }
                    }
                }

                Label {
                    text: "No episodes found."
                    color: Theme.textMuted
                    font.pixelSize: 13
                    font.family: Theme.bodyFont.family
                    visible: episodes && episodes.length === 0
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        text: "Files"
                        color: Theme.textPrimary
                        font.pixelSize: 18
                        font.family: Theme.fontDisplay
                    }

                    Repeater {
                        model: details && details.files ? details.files : []
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 72
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingMedium
                                spacing: Theme.spacingMedium

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: modelData.path
                                        color: Theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: Theme.fontBody
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        text: (modelData.container || "") + " / " + (modelData.video_codec || "?") + " / " + (modelData.audio_codec || "?")
                                        color: Theme.textSecondary
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                        elide: Text.ElideRight
                                    }
                                }

                                Button {
                                    text: "Play file"
                                    enabled: modelData.scan_state !== "missing"
                                    onClicked: apiClient.startPlayback(mediaId, modelData.id)
                                    background: Rectangle {
                                        radius: Theme.radiusSmall
                                        color: Theme.backgroundCard
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
                                    text: "Fix Match"
                                    visible: reviewEntryForFile(modelData.id) !== null
                                    onClicked: openReviewForFile(modelData.id)
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

                Label {
                    text: reviewStatusText
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                    visible: reviewStatusText !== ""
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
