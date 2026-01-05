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

            RowLayout {
                spacing: Theme.spacingLarge
                Layout.fillWidth: true

                Rectangle {
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 320
                    radius: Theme.radiusMedium
                    color: Theme.backgroundCard
                    border.color: Theme.border
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: libraryItem && (libraryItem.backdrop || libraryItem.poster) ? (libraryItem.backdrop || libraryItem.poster) : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: source !== ""
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.backgroundCard
                        visible: source === ""
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

                    Label {
                        text: details && details.description
                              ? details.description
                              : (libraryItem && libraryItem.overview ? libraryItem.overview : "No description available yet.")
                        color: Theme.textSecondary
                        font.pixelSize: 13
                        font.family: Theme.fontBody
                        wrapMode: Text.Wrap
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
            } else if (endpoint.indexOf("/api/v1/library/review") === 0) {
                reviewStatusText = "Request failed: " + error
            }
        }
    }
}
