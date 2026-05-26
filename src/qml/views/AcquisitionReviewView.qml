import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "acquisitionReviewView"
    property StackView stackView: null
    property string releaseId: ""
    property string subscriptionId: ""
    property bool detailMode: false
    property string activeReleaseId: ""
    property string activeSubscriptionId: ""

    function openReleaseReview(nextReleaseId, nextSubscriptionId) {
        activeReleaseId = String(nextReleaseId || "")
        activeSubscriptionId = String(nextSubscriptionId || "")
        if (activeReleaseId === "") return
        detailMode = true
        Qt.callLater(function() {
            detailPanel.openReleaseId(root.activeReleaseId, root.activeSubscriptionId)
        })
    }

    Component.onCompleted: {
        if (apiClient.authToken !== "") {
            apiClient.fetchAcquisitionReleases("review_required", "", 50)
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
                Layout.preferredHeight: Theme.spacingLarge
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXLarge
                Layout.rightMargin: Theme.spacingXLarge
                spacing: Theme.spacingMedium

                Button {
                    id: backButton
                    text: root.detailMode ? "Review queue" : "Back"
                    onClicked: {
                        if (root.detailMode) {
                            root.detailMode = false
                            return
                        }
                        if (root.stackView && root.stackView.depth > 1) {
                            root.stackView.pop()
                        }
                    }
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                    }
                    contentItem: Label {
                        text: backButton.text
                        color: Theme.textPrimary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Label {
                        Layout.fillWidth: true
                        text: root.detailMode ? "Review Release" : "Review Queue"
                        color: Theme.textPrimary
                        font.pixelSize: 24
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.detailMode
                              ? "Confirm that this release contains the right files, map every target, then approve or reject it."
                              : "Elixir paused these releases because it could not safely match them automatically. Open a candidate to review the files and target mappings."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                    }
                }
            }

            AcquisitionReviewPanel {
                id: queuePanel
                visible: !root.detailMode
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXLarge
                Layout.rightMargin: Theme.spacingXLarge
                showQueue: true
                queueOnly: true
                highlightedReleaseId: root.releaseId
                onReviewOpenRequested: function(nextReleaseId, nextSubscriptionId) {
                    root.openReleaseReview(nextReleaseId, nextSubscriptionId)
                }
            }

            AcquisitionReviewPanel {
                id: detailPanel
                visible: root.detailMode
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXLarge
                Layout.rightMargin: Theme.spacingXLarge
                showQueue: false
                onReturnToQueueRequested: {
                    root.detailMode = false
                    apiClient.fetchAcquisitionReleases("review_required", "", 50)
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.spacingXLarge
            }
        }
    }
}
