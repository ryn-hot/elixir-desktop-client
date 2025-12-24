import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "settingsView"
    property StackView stackView: null

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingXLarge
        spacing: Theme.spacingLarge

        function parseList(text) {
            return text.split(/\\s*,\\s*/).filter(function(item) { return item.length > 0 })
        }

        Label {
            text: "Settings"
            color: Theme.textPrimary
            font.pixelSize: 24
            font.family: Theme.fontDisplay
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
                    text: "Server"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.family: Theme.fontDisplay
                }

                TextField {
                    text: sessionManager.baseUrl
                    placeholderText: "http://192.168.1.10:44301"
                    onTextChanged: sessionManager.baseUrl = text
                }

                Label {
                    text: "Network profile"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                ComboBox {
                    model: ["auto", "lan", "wan"]
                    currentIndex: model.indexOf(sessionManager.networkType)
                    onActivated: sessionManager.networkType = model[index]
                }

                Label {
                    text: "Control plane URL"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                TextField {
                    text: sessionManager.registryUrl
                    placeholderText: "https://control.elixir.media"
                    onTextChanged: sessionManager.registryUrl = text
                }

                Label {
                    text: controlPlaneClient.authToken !== "" ? "Control plane authenticated" : "Control plane not signed in"
                    color: controlPlaneClient.authToken !== "" ? Theme.accent : Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                }

                Rectangle {
                    height: 1
                    color: Theme.border
                    Layout.fillWidth: true
                }

                Label {
                    text: "Discovery"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.family: Theme.fontDisplay
                }

                RowLayout {
                    spacing: Theme.spacingSmall

                    Button {
                        text: "Refresh LAN"
                        onClicked: serverDiscovery.refreshMdns()
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

                    Button {
                        text: "Refresh registry"
                        enabled: controlPlaneClient.authToken !== ""
                        onClicked: serverDiscovery.refreshRegistry()
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

                    Button {
                        text: "Probe"
                        onClicked: serverDiscovery.probeAll()
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

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 260
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: Theme.spacingSmall

                        Label {
                            text: "Local servers"
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                        }

                        Repeater {
                            model: serverDiscovery.mdnsModel
                            delegate: ServerListItem {
                                Layout.fillWidth: true
                                name: model.name
                                source: model.source
                                status: model.status
                                lastSeenAt: model.lastSeenAt
                                selectedEndpoint: model.selectedEndpoint
                                selectedNetwork: model.selectedNetwork
                                selectedReachable: model.selectedReachable
                                onUseRequested: function(endpoint, network) {
                                    sessionManager.baseUrl = endpoint
                                    if (network !== "") {
                                        sessionManager.networkType = network
                                    }
                                    sessionManager.clearAuth()
                                    if (root.stackView) {
                                        root.stackView.clear()
                                        root.stackView.push(Qt.resolvedUrl("ConnectServerView.qml"), { stackView: root.stackView })
                                    }
                                }
                            }
                        }

                        Label {
                            text: "No local servers yet."
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: serverDiscovery.mdnsModel.count === 0
                        }

                        Rectangle {
                            height: 1
                            color: Theme.border
                            Layout.fillWidth: true
                        }

                        Label {
                            text: "Registry servers"
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                        }

                        Label {
                            text: controlPlaneClient.authToken === "" ? "Sign in to the control plane to load registry servers." : ""
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: controlPlaneClient.authToken === ""
                        }

                        Repeater {
                            model: serverDiscovery.registryModel
                            delegate: ServerListItem {
                                Layout.fillWidth: true
                                name: model.name
                                source: model.source
                                status: model.status
                                lastSeenAt: model.lastSeenAt
                                selectedEndpoint: model.selectedEndpoint
                                selectedNetwork: model.selectedNetwork
                                selectedReachable: model.selectedReachable
                                onUseRequested: function(endpoint, network) {
                                    sessionManager.baseUrl = endpoint
                                    if (network !== "") {
                                        sessionManager.networkType = network
                                    }
                                    sessionManager.clearAuth()
                                    if (root.stackView) {
                                        root.stackView.clear()
                                        root.stackView.push(Qt.resolvedUrl("ConnectServerView.qml"), { stackView: root.stackView })
                                    }
                                }
                            }
                        }

                        Label {
                            text: "No registry servers yet."
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: serverDiscovery.registryModel.count === 0
                        }
                    }
                }

                Label {
                    text: serverDiscovery.statusMessage
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontBody
                    visible: serverDiscovery.statusMessage !== ""
                }

                Rectangle {
                    height: 1
                    color: Theme.border
                    Layout.fillWidth: true
                }

                Label {
                    text: "Playback profile"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.family: Theme.fontDisplay
                }

                Label {
                    text: "Max resolution"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                ComboBox {
                    id: resolutionCombo
                    model: ["480p", "720p", "1080p", "4k"]
                    currentIndex: model.indexOf(sessionManager.playbackMaxResolution)
                    onActivated: sessionManager.playbackMaxResolution = model[index]
                }

                Label {
                    text: "Max bitrate (bps)"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                TextField {
                    id: bitrateField
                    inputMethodHints: Qt.ImhDigitsOnly
                    text: sessionManager.playbackMaxBitrateBps.toString()
                    onEditingFinished: {
                        var value = parseInt(text)
                        if (!isNaN(value)) {
                            sessionManager.playbackMaxBitrateBps = value
                        }
                    }
                }

                Label {
                    text: "Supported containers"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                TextField {
                    id: containersField
                    placeholderText: "mkv, mp4"
                    Binding {
                        target: containersField
                        property: "text"
                        value: sessionManager.playbackSupportedContainers.join(", ")
                        when: !containersField.activeFocus
                    }
                    onEditingFinished: sessionManager.playbackSupportedContainers = parseList(text)
                }

                Label {
                    text: "Supported video codecs"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                TextField {
                    id: videoCodecsField
                    placeholderText: "h264, hevc"
                    Binding {
                        target: videoCodecsField
                        property: "text"
                        value: sessionManager.playbackSupportedVideoCodecs.join(", ")
                        when: !videoCodecsField.activeFocus
                    }
                    onEditingFinished: sessionManager.playbackSupportedVideoCodecs = parseList(text)
                }

                Label {
                    text: "Supported audio codecs"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                TextField {
                    id: audioCodecsField
                    placeholderText: "aac, ac3"
                    Binding {
                        target: audioCodecsField
                        property: "text"
                        value: sessionManager.playbackSupportedAudioCodecs.join(", ")
                        when: !audioCodecsField.activeFocus
                    }
                    onEditingFinished: sessionManager.playbackSupportedAudioCodecs = parseList(text)
                }

                RowLayout {
                    spacing: Theme.spacingMedium

                    Button {
                        text: "Clear auth"
                        onClicked: sessionManager.clearAuth()
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

                    Button {
                        text: "Clear control plane auth"
                        onClicked: sessionManager.clearControlPlaneAuth()
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

                    Button {
                        text: "Back"
                        onClicked: {
                            if (root.stackView) {
                                root.stackView.pop()
                            }
                        }
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
                }
            }
        }
    }
}
