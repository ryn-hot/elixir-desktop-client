import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "liveDetailsView"
    required property var liveModel
    required property string providerId
    required property string itemKey
    property StackView stackView: null
    property string serverBaseUrl: ""
    property var client: null
    property var playerController: null
    signal backRequested()
    signal streamRequested(string providerId, string itemKey, string streamOptionKey)

    readonly property var item: liveModel.selectedItem || ({})
    readonly property var currentProvider: provider()
    readonly property bool accountRequired: String(
                                                liveModel.lastError
                                                ? liveModel.lastError.code : "")
                                            === "LIVE_ACCOUNT_REQUIRED"
    readonly property int pageMargin: width < 700 ? Theme.space16 : Theme.space32

    Rectangle {
        anchors.fill: parent
        color: Theme.appBg
        z: -1
    }

    function absoluteArtwork(artwork) {
        if (!artwork || !artwork.url || serverBaseUrl === "") return ""
        var base = String(serverBaseUrl)
        while (base.endsWith("/")) base = base.slice(0, -1)
        return base + String(artwork.url)
    }

    function formattedDate(value) {
        if (!value) return ""
        var date = new Date(value)
        return isNaN(date.getTime()) ? "" : Qt.formatDateTime(date, "dddd, MMMM d - h:mm AP")
    }

    function providerName() {
        var value = provider()
        return value ? String(value.name || "Live provider") : "Live provider"
    }

    function provider() {
        var providers = liveModel.providers || []
        for (var i = 0; i < providers.length; ++i) {
            if (String(providers[i].providerId) === String(root.providerId))
                return providers[i]
        }
        return null
    }

    function openProviderAccount() {
        if (!stackView || !currentProvider) return
        stackView.push(Qt.resolvedUrl("ExtensionControlView.qml"), {
            stackView: stackView,
            extensionId: String(currentProvider.extensionId || ""),
            instanceId: String(currentProvider.instanceId || "")
        })
    }

    function goBack() {
        backRequested()
        if (stackView) stackView.pop()
    }

    function playStream(stream) {
        if (!playerController || !stream || !stream.streamOptionKey) return
        var streamKey = String(stream.streamOptionKey)
        streamRequested(providerId, itemKey, streamKey)
        if (stackView) {
            stackView.push(Qt.resolvedUrl("LivePlayerView.qml"), {
                stackView: stackView,
                liveModel: liveModel,
                client: client,
                playerController: playerController,
                providerId: providerId,
                itemKey: itemKey,
                streamOptionKey: streamKey,
                eventTitle: String(item.title || "Live event"),
                expectedEndUtc: item.endsAtUtc || item.endsAt || null
            })
        }
    }

    Component.onCompleted: liveModel.loadItem(providerId, itemKey)
    Component.onDestruction: {
        if (liveModel && liveModel.itemLoading) liveModel.cancelItemRequest()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            Button {
                id: backButton
                objectName: "liveDetailsBack"
                anchors.left: parent.left
                anchors.leftMargin: root.pageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: 38
                height: 34
                text: "\u2190"
                focusPolicy: Qt.StrongFocus
                Accessible.name: "Back to Live catalogs"
                ToolTip.text: Accessible.name
                ToolTip.visible: hovered
                onClicked: root.goBack()
                background: Rectangle {
                    radius: Theme.radius6
                    color: backButton.hovered ? Theme.surfaceHover : Theme.surface
                    border.color: backButton.activeFocus ? Theme.accent : Theme.borderSubtle
                }
                contentItem: Label {
                    text: backButton.text
                    color: Theme.textPrimary
                    font.pixelSize: 20
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Label {
                anchors.left: backButton.right
                anchors.leftMargin: Theme.space12
                anchors.verticalCenter: parent.verticalCenter
                text: "Live"
                color: Theme.textSecondary
                font.pixelSize: 13
            }
        }

        Item {
            objectName: "liveDetailsLoading"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.liveModel.itemLoading
            BusyIndicator {
                anchors.centerIn: parent
                running: parent.visible
                Accessible.name: "Loading Live event details"
            }
        }

        EmptyState {
            objectName: "liveDetailsError"
            Layout.fillWidth: true
            Layout.leftMargin: root.pageMargin
            Layout.rightMargin: root.pageMargin
            title: root.accountRequired ? "Live provider needs an account"
                                        : "Live details unavailable"
            message: root.liveModel.lastError && root.liveModel.lastError.message
                     ? String(root.liveModel.lastError.message) : "This event could not be loaded."
            actionText: root.accountRequired
                        ? (root.currentProvider
                           && String(root.currentProvider.accountState || "") === "needs_account"
                           ? "Connect account" : "Reconnect account")
                        : "Retry"
            visible: Boolean(!root.liveModel.itemLoading && !root.item.title
                             && root.liveModel.lastError && root.liveModel.lastError.message)
            onActionRequested: root.accountRequired ? root.openProviderAccount()
                                                    : root.liveModel.loadItem(root.providerId,
                                                                              root.itemKey)
        }

        ScrollView {
            id: detailsScroll
            objectName: "liveDetailsContent"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.liveModel.itemLoading && Boolean(root.item.title)
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            Column {
                width: detailsScroll.availableWidth
                spacing: 0

                Item {
                    id: hero
                    width: parent.width
                    height: Math.max(260, Math.min(380, root.height * 0.48))
                    clip: true

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.panelSoft
                    }

                    Image {
                        id: heroArtwork
                        anchors.fill: parent
                        source: root.absoluteArtwork(root.item.background || root.item.poster)
                        asynchronous: true
                        cache: true
                        fillMode: Image.PreserveAspectCrop
                        visible: source !== "" && status !== Image.Error
                        sourceSize.width: Math.max(960, width * Screen.devicePixelRatio)
                        sourceSize.height: Math.max(540, height * Screen.devicePixelRatio)
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: "#B8000000"
                    }

                    ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: root.pageMargin
                        anchors.rightMargin: root.pageMargin
                        anchors.bottomMargin: Theme.space28
                        spacing: Theme.space8

                        LiveStatusPill {
                            status: String(root.item.status || "unknown")
                        }

                        Label {
                            id: detailTitle
                            objectName: "liveDetailsTitle"
                            Layout.fillWidth: true
                            text: String(root.item.title || "Untitled live event")
                            textFormat: Text.PlainText
                            color: Theme.textPrimary
                            font.family: Theme.fontDisplay
                            font.pixelSize: root.width < 600 ? 26 : 36
                            font.weight: Font.Bold
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }

                        Label {
                            objectName: "liveDetailsSubtitle"
                            Layout.fillWidth: true
                            text: String(root.item.subtitle || "")
                            textFormat: Text.PlainText
                            color: Theme.textSecondary
                            font.pixelSize: 14
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            visible: text !== ""
                        }

                        Label {
                            objectName: "liveDetailsSource"
                            Layout.fillWidth: true
                            text: root.formattedDate(root.item.startsAtLocal || root.item.startsAt)
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            visible: text !== ""
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.providerName()
                            textFormat: Text.PlainText
                            color: Theme.textMuted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                ColumnLayout {
                    width: Math.max(0, parent.width - root.pageMargin * 2)
                    x: root.pageMargin
                    spacing: Theme.space24

                    Item { Layout.preferredHeight: 1; Layout.preferredWidth: 1 }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.space8
                        Repeater {
                            model: root.item.badges || []
                            Rectangle {
                                required property string modelData
                                width: badgeText.implicitWidth + 14
                                height: 24
                                radius: Theme.radius4
                                color: Theme.surfaceRaised
                                border.color: Theme.borderSubtle
                                Label {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: modelData
                                    textFormat: Text.PlainText
                                    color: Theme.textSecondary
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }

                    Label {
                        id: detailDescription
                        objectName: "liveDetailsDescription"
                        Layout.fillWidth: true
                        text: String(root.item.description || "")
                        textFormat: Text.PlainText
                        color: Theme.textSecondary
                        font.family: Theme.fontBody
                        font.pixelSize: 14
                        lineHeight: 1.35
                        wrapMode: Text.Wrap
                        visible: text !== ""
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space10
                        visible: (root.item.facts || []).length > 0

                        Label {
                            text: "Event information"
                            color: Theme.textPrimary
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: root.item.facts || []
                            RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.space16
                                Label {
                                    Layout.preferredWidth: 120
                                    Layout.maximumWidth: 180
                                    text: String(modelData.label || "")
                                    textFormat: Text.PlainText
                                    color: Theme.textMuted
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: String(modelData.value || "")
                                    textFormat: Text.PlainText
                                    color: Theme.textSecondary
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space10
                        visible: (root.liveModel.selectedStreams || []).length > 0

                        Label {
                            text: "Available streams"
                            color: Theme.textPrimary
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: root.liveModel.selectedStreams || []
                            Button {
                                id: streamButton
                                objectName: "liveStreamOption"
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 58
                                enabled: Boolean(root.playerController && modelData.streamOptionKey)
                                Accessible.name: String(modelData.label || "Stream option")
                                Accessible.description: "Play Live stream"
                                onClicked: root.playStream(modelData)

                                background: Rectangle {
                                    radius: Theme.radius6
                                    color: streamButton.hovered ? Theme.surfaceHover : Theme.surface
                                    border.color: streamButton.activeFocus ? Theme.accent : Theme.borderSubtle
                                    opacity: streamButton.enabled ? 1 : 0.55
                                }

                                contentItem: RowLayout {
                                    spacing: Theme.space12
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Label {
                                            Layout.fillWidth: true
                                            text: String(modelData.label || "Stream")
                                            textFormat: Text.PlainText
                                            color: Theme.textPrimary
                                            font.pixelSize: 13
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: [modelData.quality, modelData.language, modelData.protocolHint]
                                                  .filter(Boolean).join(" / ")
                                            textFormat: Text.PlainText
                                            color: Theme.textMuted
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                    }
                                    Image {
                                        source: "qrc:/icons/play.svg"
                                        sourceSize.width: 18
                                        sourceSize.height: 18
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        opacity: streamButton.enabled ? 1 : 0.5
                                    }
                                }
                            }
                        }
                    }

                    EmptyState {
                        objectName: "liveDetailsNoStreams"
                        Layout.fillWidth: true
                        title: "No streams available"
                        message: "No streams are available for this event right now."
                        actionText: "Refresh"
                        visible: Boolean(root.item.title)
                                 && (root.liveModel.selectedStreams || []).length === 0
                        onActionRequested: root.liveModel.loadItem(root.providerId, root.itemKey)
                    }

                    Item { Layout.preferredHeight: Theme.space8; Layout.preferredWidth: 1 }
                }
            }
        }
    }
}
