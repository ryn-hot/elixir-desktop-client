import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "acquisitionView"
    property StackView stackView: null

    function stageBorderColor(stage) {
        if (stage === "needs_attention" || stage === "failed") {
            return Theme.accentDanger
        }
        if (stage === "downloading" || stage === "post_processing" || stage === "importing") {
            return Theme.accent
        }
        if (stage === "ready") {
            return Theme.accentSuccess
        }
        return Theme.border
    }

    function stageFillColor(stage) {
        if (stage === "needs_attention" || stage === "failed") {
            return Theme.accentDangerSoft
        }
        if (stage === "downloading" || stage === "post_processing" || stage === "importing") {
            return Theme.accentSoft
        }
        if (stage === "ready") {
            return Theme.accentSuccessSoft
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
                        required property var modelData

                        Layout.fillWidth: true
                        radius: Theme.radiusLarge
                        color: Theme.backgroundCard
                        border.color: root.stageBorderColor(String(modelData.stage || ""))
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
                                        text: String(modelData.description || "")
                                        color: Theme.textSecondary
                                        font.pixelSize: 12
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                        visible: text !== ""
                                    }
                                }

                                Rectangle {
                                    radius: Theme.radiusSmall
                                    color: root.stageFillColor(String(modelData.stage || ""))
                                    border.color: root.stageBorderColor(String(modelData.stage || ""))
                                    implicitWidth: stageLabel.implicitWidth + 12
                                    implicitHeight: stageLabel.implicitHeight + 4

                                    Label {
                                        id: stageLabel
                                        anchors.centerIn: parent
                                        text: String(modelData.stageLabel || modelData.stage || "")
                                        color: Theme.textPrimary
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                    }
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSmall

                                Repeater {
                                    model: [
                                        modelData.managerLabel ? { label: "Manager", value: modelData.managerLabel } : null,
                                        modelData.downloaderLabel ? { label: "Downloader", value: modelData.downloaderLabel } : null,
                                        formatRate(modelData.downloadRateBps) !== "" ? { label: "Speed", value: formatRate(modelData.downloadRateBps) } : null,
                                        modelData.eta ? { label: "ETA", value: String(modelData.eta) } : null
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        visible: modelData !== null
                                        radius: Theme.radiusSmall
                                        color: Theme.backgroundCardRaised
                                        border.color: Theme.border
                                        implicitHeight: 28
                                        implicitWidth: metricLabel.implicitWidth + 18

                                        Label {
                                            id: metricLabel
                                            anchors.centerIn: parent
                                            text: modelData ? String(modelData.label + ": " + modelData.value) : ""
                                            color: Theme.textSecondary
                                            font.pixelSize: 11
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

            Item {
                Layout.fillWidth: true
                height: Theme.spacingXLarge
            }
        }
    }
}
