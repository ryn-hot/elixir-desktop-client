import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "acquisitionView"
    property StackView stackView: null

    function acquisitionPhase(item) {
        return String((item && (item.phase || item.stage)) || "")
    }

    function phaseBorderColor(phase) {
        if (phase === "needs_attention" || phase === "failed") {
            return Theme.accentDanger
        }
        if (phase === "downloading" || phase === "post_processing" || phase === "importing") {
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
        if (phase === "needs_attention" || phase === "failed") {
            return Theme.accentDangerSoft
        }
        if (phase === "downloading" || phase === "post_processing" || phase === "importing") {
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

    function progressVisible(item) {
        return item.progressPercent !== undefined
               && item.progressPercent !== null
               && Number(item.progressPercent) > 0
               && Number(item.progressPercent) < 100
    }

    Component.onCompleted: {
        if (apiClient.authToken !== "") {
            apiClient.fetchMediaAcquisition()
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
                    onClicked: apiClient.fetchMediaAcquisition()
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

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXLarge
                Layout.rightMargin: Theme.spacingXLarge
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                visible: (apiClient.mediaAcquisitionItems || []).length === 0
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
                                        text: String(modelData.headline || modelData.description || "")
                                        color: Theme.textPrimary
                                        font.pixelSize: 13
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                        visible: text !== ""
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: String(modelData.detail || "")
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
                                color: Theme.accentDangerSoft
                                border.color: Theme.accentDanger
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
                                        text: String((modelData.blocker && (modelData.blocker.title || modelData.blocker.code)) || "")
                                        color: Theme.textPrimary
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: String((modelData.blocker && modelData.blocker.detail) || "")
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

                                Repeater {
                                    model: (function() {
                                        var parts = []
                                        if (modelData.managerLabel) {
                                            parts.push({ label: "Manager", value: modelData.managerLabel, tone: "neutral" })
                                        }
                                        var evidence = modelData.evidence || []
                                        for (var i = 0; i < evidence.length; ++i) {
                                            parts.push(evidence[i])
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
                                            text: String(modelData.label + ": " + modelData.value)
                                            color: Theme.textSecondary
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
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
                                        text: String(modelData.label || "")
                                        visible: text !== ""
                                        onClicked: {
                                            if (String(modelData.id || "") === "find_another_release") {
                                                apiClient.findAnotherRelease(String(acquisitionCard.acquisitionItem.intentId || ""))
                                            }
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
