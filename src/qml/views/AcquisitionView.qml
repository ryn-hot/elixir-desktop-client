import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "acquisitionView"
    property StackView stackView: null
    property var batchExpansionByIntentId: ({})
    property string initialReviewReleaseId: ""
    property string initialReviewSubscriptionId: ""
    property bool initialReviewOpened: false

    function acquisitionPhase(item) {
        return String((item && (item.phase || item.stage)) || "")
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

    function evidenceValue(evidence) {
        if (!evidence) {
            return ""
        }
        return displayText(evidence.value, String(evidence.label || ""))
    }

    function acquisitionChildren(item) {
        if (!item) {
            return []
        }
        var value = item.children
        return value === undefined || value === null ? [] : value
    }

    function batchUnitLabel(item, count) {
        return count === 1 ? "download" : "downloads"
    }

    function batchSectionTitle(item, count) {
        var total = Number((item && item.targetCount) || count)
        var hidden = Number((item && item.hiddenChildCount) || 0)
        if (hidden > 0) {
            return count + " of " + total + " targets shown"
        }
        return total + " " + (total === 1 ? "target" : "targets")
    }

    function acquisitionItemKey(item) {
        if (!item) {
            return ""
        }
        return String(item.intentId || item.id || item.title || "")
    }

    function isBatchExpanded(item, childCount) {
        var key = acquisitionItemKey(item)
        if (key === "" || batchExpansionByIntentId[key] === undefined) {
            return childCount <= 5
        }
        return !!batchExpansionByIntentId[key]
    }

    function setBatchExpanded(item, expanded) {
        var key = acquisitionItemKey(item)
        if (key === "") {
            return
        }
        var next = {}
        var current = batchExpansionByIntentId || {}
        for (var existingKey in current) {
            next[existingKey] = current[existingKey]
        }
        next[key] = expanded
        batchExpansionByIntentId = next
    }

    function blockerBorderColor(blocker) {
        var severity = String((blocker && blocker.severity) || "").toLowerCase()
        return severity === "warning" ? Theme.accent : Theme.accentDanger
    }

    function blockerFillColor(blocker) {
        var severity = String((blocker && blocker.severity) || "").toLowerCase()
        return severity === "warning" ? Theme.accentSoft : Theme.accentDangerSoft
    }

    function phaseBorderColor(phase) {
        if (phase === "needs_attention" || phase === "failed" ||
                phase === "review_required" || phase === "quarantined") {
            return Theme.accentDanger
        }
        if (phase === "finding_another_release" || phase === "staged" || phase === "submitted") {
            return Theme.accent
        }
        if (phase === "downloading" || phase === "materializing" ||
                phase === "post_processing" || phase === "importing") {
            return Theme.accent
        }
        if (phase === "completed" || phase === "ready") {
            return Theme.accentSuccess
        }
        if (phase === "accepted_by_manager" || phase === "queued_in_downloader") {
            return Theme.accent
        }
        return Theme.border
    }

    function phaseFillColor(phase) {
        if (phase === "needs_attention" || phase === "failed" ||
                phase === "review_required" || phase === "quarantined") {
            return Theme.accentDangerSoft
        }
        if (phase === "finding_another_release" || phase === "staged" || phase === "submitted") {
            return Theme.accentSoft
        }
        if (phase === "downloading" || phase === "materializing" ||
                phase === "post_processing" || phase === "importing") {
            return Theme.accentSoft
        }
        if (phase === "completed" || phase === "ready") {
            return Theme.accentSuccessSoft
        }
        if (phase === "accepted_by_manager" || phase === "queued_in_downloader") {
            return Theme.accentSoft
        }
        return Theme.backgroundCardRaised
    }

    function formatRate(value) {
        if (value === undefined || value === null || Number(value) <= 0) {
            return ""
        }
        var units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var amount = Number(value)
        var unit = 0
        while (amount >= 1024 && unit < units.length - 1) {
            amount /= 1024
            unit += 1
        }
        return amount.toFixed(amount >= 100 || unit === 0 ? 0 : 1) + " " + units[unit]
    }

    function formatBytes(value) {
        if (value === undefined || value === null || Number(value) <= 0) {
            return ""
        }
        var units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var amount = Number(value)
        var unit = 0
        while (amount >= 1024 && unit < units.length - 1) {
            amount /= 1024
            unit += 1
        }
        return amount.toFixed(amount >= 100 || unit === 0 ? 0 : 1) + " " + units[unit]
    }

    function formatEtaSeconds(value) {
        if (value === undefined || value === null) {
            return ""
        }
        var seconds = Math.max(0, Number(value))
        if (!isFinite(seconds) || seconds <= 0) {
            return ""
        }
        var hours = Math.floor(seconds / 3600)
        var minutes = Math.floor((seconds % 3600) / 60)
        if (hours > 0) {
            return hours + "h " + minutes + "m"
        }
        return Math.max(1, minutes) + "m"
    }

    function formatAvailability(value) {
        if (value === undefined || value === null || !isFinite(Number(value)) || Number(value) < 0) {
            return ""
        }
        return Number(value).toFixed(Number(value) >= 10 ? 1 : 2) + "x"
    }

    function transferMetricParts(item) {
        var parts = []
        if (!item) {
            return parts
        }
        var size = formatBytes(item.sizeBytes)
        if (size !== "") {
            parts.push({ label: "Size", value: size, tone: "neutral" })
        }
        var downloaded = formatBytes(item.downloadedBytes)
        if (downloaded !== "") {
            parts.push({ label: "Done", value: downloaded, tone: "neutral" })
        }
        var down = formatRate(item.downloadRateBps)
        if (down !== "") {
            parts.push({ label: "Down", value: down, tone: "success" })
        }
        var up = formatRate(item.uploadRateBps)
        if (up !== "") {
            parts.push({ label: "Up", value: up, tone: "neutral" })
        }
        var eta = formatEtaSeconds(item.etaSeconds)
        if (eta !== "") {
            parts.push({ label: "ETA", value: eta, tone: "neutral" })
        }
        if (item.connectedSeeds !== undefined && item.connectedSeeds !== null) {
            var seedValue = String(item.connectedSeeds)
            if (item.knownSeeds !== undefined && item.knownSeeds !== null) {
                seedValue += " (" + item.knownSeeds + ")"
            }
            parts.push({ label: "Seeds", value: seedValue, tone: Number(item.connectedSeeds) > 0 ? "success" : "warning" })
        }
        if (item.connectedPeers !== undefined && item.connectedPeers !== null) {
            var peerValue = String(item.connectedPeers)
            if (item.knownPeers !== undefined && item.knownPeers !== null) {
                peerValue += " (" + item.knownPeers + ")"
            }
            parts.push({ label: "Peers", value: peerValue, tone: "neutral" })
        }
        var availability = formatAvailability(item.availability)
        if (availability !== "") {
            parts.push({ label: "Availability", value: availability, tone: Number(item.availability) >= 1 ? "success" : "warning" })
        }
        if (item.category !== undefined && item.category !== null && String(item.category).trim() !== "") {
            parts.push({ label: "Category", value: String(item.category), tone: "neutral" })
        }
        return parts
    }

    function phaseShowsProgress(phase) {
        return phase === "downloading" || phase === "materializing" ||
               phase === "post_processing" || phase === "importing"
    }

    function phaseShowsMetrics(phase) {
        return phase !== "completed"
    }

    function progressVisible(item) {
        if (!item || !phaseShowsProgress(acquisitionPhase(item))) {
            return false
        }
        return item.progressPercent !== undefined
               && item.progressPercent !== null
               && Number(item.progressPercent) > 0
               && Number(item.progressPercent) < 100
    }

    function runAcquisitionAction(action, item) {
        var actionId = String(action.id || "")
        if (actionId === "find_another_release") {
            var retryReleaseId = String(action.releaseId || action.release_id || "")
            if (retryReleaseId !== "") {
                apiClient.retryAcquisitionRelease(retryReleaseId, {
                    mode: String(action.retryMode || action.retry_mode || "source_discovery"),
                    reason: "Find another release from acquisition status."
                })
                return
            }
            apiClient.findAnotherRelease(String(item.intentId || item.intent_id || ""))
            return
        }
        if (actionId === "open_review") {
            var releaseId = String(action.releaseId || action.release_id || "")
            if (releaseId !== "") {
                reviewPanel.openReleaseId(
                    releaseId,
                    String(action.subscriptionId || action.subscription_id || ""))
            }
            return
        }
        if (actionId === "retry_import") {
            var importReleaseId = String(action.releaseId || action.release_id || "")
            if (importReleaseId !== "") {
                apiClient.retryAcquisitionRelease(importReleaseId, {
                    mode: String(action.retryMode || action.retry_mode || "import"),
                    reason: "Retry import from acquisition status."
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

    Component.onCompleted: {
        if (apiClient.authToken !== "") {
            apiClient.fetchMediaAcquisition()
            apiClient.fetchAcquisitionReleases("review_required", "", 50)
        }
        if (!initialReviewOpened && initialReviewReleaseId !== "") {
            initialReviewOpened = true
            Qt.callLater(function() {
                reviewPanel.openReleaseId(initialReviewReleaseId, initialReviewSubscriptionId)
            })
        }
    }

    ScrollView {
        id: scrollView
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth
        contentHeight: pageContent.implicitHeight

        ColumnLayout {
            id: pageContent
            width: scrollView.availableWidth
            spacing: Theme.spacingLarge

            Item {
                Layout.fillWidth: true
                height: Theme.spacingLarge
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXLarge
                Layout.rightMargin: Theme.spacingXLarge
                spacing: Theme.spacingMedium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Label {
                        text: "Acquisition"
                        color: Theme.textPrimary
                        font.pixelSize: 24
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        text: {
                            var active = apiClient.mediaAcquisitionActiveCount
                            var downloading = apiClient.mediaAcquisitionDownloadingCount
                            var attention = apiClient.mediaAcquisitionNeedsAttentionCount
                            var parts = []
                            if (active > 0) parts.push(active + " active")
                            if (downloading > 0) parts.push(downloading + " downloading")
                            if (attention > 0) parts.push(attention + " need attention")
                            var rate = formatRate((apiClient.mediaAcquisitionStatus || {}).totalDownloadRateBps)
                            if (rate !== "") parts.push(rate)
                            return parts.length > 0
                                   ? parts.join(" • ")
                                   : "Track requests, downloads, and import progress here."
                        }
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Button {
                    text: "Refresh"
                    onClicked: {
                        apiClient.fetchMediaAcquisition()
                        apiClient.fetchAcquisitionReleases("review_required", "", 50)
                    }
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                    }
                    contentItem: Label {
                        text: parent.text
                        color: Theme.textPrimary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            AcquisitionReviewPanel {
                id: reviewPanel
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXLarge
                Layout.rightMargin: Theme.spacingXLarge
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXLarge
                Layout.rightMargin: Theme.spacingXLarge
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                visible: (apiClient.mediaAcquisitionItems || []).length === 0
                         && (apiClient.acquisitionReviewReleases || []).length === 0
                implicitHeight: emptyState.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: emptyState
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        Layout.fillWidth: true
                        text: "Nothing is being acquired right now."
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        Layout.fillWidth: true
                        text: "When you add media from Find Media, its search, download, and import progress will appear here."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXLarge
                Layout.rightMargin: Theme.spacingXLarge
                spacing: Theme.spacingMedium
                visible: (apiClient.mediaAcquisitionItems || []).length > 0

                Repeater {
                    model: apiClient.mediaAcquisitionItems || []

                    delegate: Rectangle {
                        id: acquisitionCard
                        required property var modelData
                        property var acquisitionItem: modelData
                        readonly property var childItems: root.acquisitionChildren(modelData)
                        readonly property string itemKey: root.acquisitionItemKey(modelData)
                        property bool batchExpanded: root.isBatchExpanded(modelData, childItems.length)
                        readonly property int collapsedChildCount: Math.max(0, childItems.length - 5)

                        Layout.fillWidth: true
                        radius: Theme.radiusLarge
                        color: Theme.backgroundCard
                        border.color: root.phaseBorderColor(root.acquisitionPhase(modelData))
                        implicitHeight: itemContent.implicitHeight + Theme.spacingLarge * 2

                        ColumnLayout {
                            id: itemContent
                            anchors.fill: parent
                            anchors.margins: Theme.spacingLarge
                            spacing: Theme.spacingMedium

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSmall

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSmall

                                    Label {
                                        Layout.fillWidth: true
                                        text: String(modelData.title || "Media")
                                        color: Theme.textPrimary
                                        font.pixelSize: 18
                                        font.family: Theme.fontDisplay
                                        wrapMode: Text.WordWrap
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.displayText(modelData.headline || modelData.description || "", "headline")
                                        color: Theme.textPrimary
                                        font.pixelSize: 13
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                        visible: text !== ""
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.displayText(modelData.detail || "", "detail")
                                        color: Theme.textSecondary
                                        font.pixelSize: 12
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                        visible: text !== ""
                                    }
                                }

                                Rectangle {
                                    radius: Theme.radiusSmall
                                    color: root.phaseFillColor(root.acquisitionPhase(modelData))
                                    border.color: root.phaseBorderColor(root.acquisitionPhase(modelData))
                                    implicitWidth: stageLabel.implicitWidth + 12
                                    implicitHeight: stageLabel.implicitHeight + 4

                                    Label {
                                        id: stageLabel
                                        anchors.centerIn: parent
                                        text: String(modelData.phaseLabel || modelData.stageLabel || modelData.phase || modelData.stage || "")
                                        color: Theme.textPrimary
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                radius: Theme.radiusSmall
                                color: root.blockerFillColor(modelData.blocker)
                                border.color: root.blockerBorderColor(modelData.blocker)
                                visible: modelData.blocker !== undefined
                                         && modelData.blocker !== null
                                         && String(modelData.blocker.detail || "") !== ""
                                implicitHeight: blockerColumn.implicitHeight + 12

                                ColumnLayout {
                                    id: blockerColumn
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 4

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.displayText((modelData.blocker && (modelData.blocker.title || modelData.blocker.code)) || "", "blocker")
                                        color: Theme.textPrimary
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: root.displayText((modelData.blocker && modelData.blocker.detail) || "", "blocker")
                                        color: Theme.textSecondary
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                        visible: text !== ""
                                    }
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSmall
                                visible: root.phaseShowsMetrics(root.acquisitionPhase(modelData))

                                Repeater {
                                    model: (function() {
                                        var parts = []
                                        if (modelData.managerLabel) {
                                            parts.push({ label: "Manager", value: modelData.managerLabel, tone: "neutral" })
                                        }
                                        var evidence = modelData.evidence || []
                                        for (var i = 0; i < evidence.length; ++i) {
                                            parts.push({
                                                label: evidence[i].label,
                                                value: root.evidenceValue(evidence[i]),
                                                tone: evidence[i].tone
                                            })
                                        }
                                        var eta = formatEtaSeconds(modelData.etaSeconds)
                                        if (eta !== "") {
                                            parts.push({ label: "ETA", value: eta, tone: "neutral" })
                                        }
                                        return parts
                                    })()
                                    delegate: Rectangle {
                                        required property var modelData
                                        radius: Theme.radiusSmall
                                        color: Theme.backgroundCardRaised
                                        border.color: modelData.tone === "success"
                                                      ? Theme.accentSuccess
                                                      : (modelData.tone === "warning"
                                                         ? Theme.accent
                                                         : Theme.border)
                                        implicitHeight: 28
                                        implicitWidth: metricLabel.implicitWidth + 18

                                        Label {
                                            id: metricLabel
                                            anchors.centerIn: parent
                                            text: String(modelData.label + ": " + root.displayText(modelData.value, modelData.label))
                                            color: Theme.textSecondary
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                radius: Theme.radiusMedium
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                                visible: acquisitionCard.childItems.length > 0
                                implicitHeight: batchColumn.implicitHeight + 12

                                ColumnLayout {
                                    id: batchColumn
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSmall

                                        Label {
                                            Layout.fillWidth: true
                                            text: root.batchSectionTitle(acquisitionCard.acquisitionItem, acquisitionCard.childItems.length)
                                            color: Theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                        }

                                        Button {
                                            visible: acquisitionCard.collapsedChildCount > 0
                                            text: acquisitionCard.batchExpanded
                                                  ? "Hide"
                                                  : ("Show " + acquisitionCard.collapsedChildCount + " more")
                                            onClicked: root.setBatchExpanded(
                                                           acquisitionCard.acquisitionItem,
                                                           !acquisitionCard.batchExpanded)
                                            background: Rectangle {
                                                radius: Theme.radiusSmall
                                                color: Theme.backgroundCard
                                                border.color: Theme.border
                                            }
                                            contentItem: Label {
                                                text: parent.text
                                                color: Theme.textSecondary
                                                font.pixelSize: 10
                                                font.family: Theme.fontBody
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: acquisitionCard.batchExpanded
                                               ? acquisitionCard.childItems
                                               : acquisitionCard.childItems.slice(0, 5)

                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            radius: Theme.radiusSmall
                                            color: Theme.backgroundCard
                                            border.color: root.phaseBorderColor(root.acquisitionPhase(modelData))
                                            implicitHeight: childColumn.implicitHeight + 10

                                            ColumnLayout {
                                                id: childColumn
                                                anchors.fill: parent
                                                anchors.margins: 5
                                                spacing: 4

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 2

                                                        Label {
                                                            Layout.fillWidth: true
                                                            text: String(modelData.title || "Item")
                                                            color: Theme.textPrimary
                                                            font.pixelSize: 12
                                                            font.family: Theme.fontBody
                                                            wrapMode: Text.WordWrap
                                                        }

                                                        Label {
                                                            Layout.fillWidth: true
                                                            text: String(modelData.subtitle || "")
                                                            color: Theme.textSecondary
                                                            font.pixelSize: 10
                                                            font.family: Theme.fontBody
                                                            wrapMode: Text.WordWrap
                                                            visible: text !== ""
                                                        }
                                                    }

                                                    Rectangle {
                                                        radius: Theme.radiusSmall
                                                        color: root.phaseFillColor(root.acquisitionPhase(modelData))
                                                        border.color: root.phaseBorderColor(root.acquisitionPhase(modelData))
                                                        implicitWidth: childStageLabel.implicitWidth + 10
                                                        implicitHeight: childStageLabel.implicitHeight + 4

                                                        Label {
                                                            id: childStageLabel
                                                            anchors.centerIn: parent
                                                            text: String(modelData.phaseLabel || modelData.stageLabel || modelData.phase || modelData.stage || "")
                                                            color: Theme.textPrimary
                                                            font.pixelSize: 10
                                                            font.family: Theme.fontBody
                                                        }
                                                    }
                                                }

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: root.displayText((modelData.blocker && modelData.blocker.detail) || "", "blocker")
                                                    color: Theme.textSecondary
                                                    font.pixelSize: 10
                                                    font.family: Theme.fontBody
                                                    wrapMode: Text.WordWrap
                                                    visible: text !== ""
                                                }

                                                Flow {
                                                    Layout.fillWidth: true
                                                    spacing: 5
                                                    visible: root.transferMetricParts(modelData).length > 0

                                                    Repeater {
                                                        model: root.transferMetricParts(modelData)

                                                        delegate: Rectangle {
                                                            required property var modelData
                                                            radius: Theme.radiusSmall
                                                            color: Theme.backgroundCardRaised
                                                            border.color: modelData.tone === "success"
                                                                          ? Theme.accentSuccess
                                                                          : (modelData.tone === "warning"
                                                                             ? Theme.accent
                                                                             : Theme.border)
                                                            implicitHeight: 24
                                                            implicitWidth: transferMetricLabel.implicitWidth + 14

                                                            Label {
                                                                id: transferMetricLabel
                                                                anchors.centerIn: parent
                                                                text: String(modelData.label + ": " + modelData.value)
                                                                color: Theme.textSecondary
                                                                font.pixelSize: 10
                                                                font.family: Theme.fontBody
                                                            }
                                                        }
                                                    }
                                                }

                                                ProgressBar {
                                                    Layout.fillWidth: true
                                                    from: 0
                                                    to: 100
                                                    value: Number(modelData.progressPercent || 0)
                                                    visible: root.progressVisible(modelData)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSmall
                                visible: (modelData.actions || []).length > 0

                                Repeater {
                                    model: modelData.actions || []

                                    delegate: Button {
                                        required property var modelData
                                        text: root.displayText(modelData.label || "", "action")
                                        visible: text !== ""
                                        onClicked: {
                                            root.runAcquisitionAction(modelData, acquisitionCard.acquisitionItem)
                                        }
                                        background: Rectangle {
                                            radius: Theme.radiusSmall
                                            color: modelData.kind === "primary"
                                                   ? Theme.accent
                                                   : Theme.backgroundCardRaised
                                            border.color: modelData.kind === "primary"
                                                          ? Theme.accent
                                                          : Theme.border
                                        }
                                        contentItem: Label {
                                            text: parent.text
                                            color: Theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }
                            }

                            ProgressBar {
                                Layout.fillWidth: true
                                from: 0
                                to: 100
                                value: Number(modelData.progressPercent || 0)
                                visible: root.progressVisible(modelData)
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                height: Theme.spacingXLarge
            }
        }
    }
}
