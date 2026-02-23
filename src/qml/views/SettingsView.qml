import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "settingsView"
    property StackView stackView: null

    function parseList(text) {
        return text.split(/\\s*,\\s*/).filter(function(item) { return item.length > 0 })
    }

    function listValue(objectValue, snakeKey, camelKey) {
        if (!objectValue) {
            return []
        }
        var value = objectValue[snakeKey]
        if (value === undefined && camelKey !== "") {
            value = objectValue[camelKey]
        }
        return value === undefined || value === null ? [] : value
    }

    function managerPreferenceState() {
        var value = apiClient.mediaManagerPreferences.preferences
        if (value === undefined || value === null) {
            value = apiClient.mediaManagerPreferences.preferencesState
        }
        return value || {}
    }

    function managerProvidersFor(type) {
        var providers = listValue(apiClient.mediaManagerPreferences, type + "_providers", type + "Providers")
        var options = [{ label: "Auto-select", value: "" }]
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var label = provider.label
            if (label === undefined || label === "") {
                label = provider.instance_name !== undefined ? provider.instance_name : provider.instanceName
            }
            var providerId = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            options.push({ label: label, value: String(providerId || "") })
        }
        return options
    }

    function managerPreferenceFor(type) {
        var pref = managerPreferenceState()
        if (type === "movie") {
            return String(pref.movie_provider_id || pref.movieProviderId || "")
        }
        if (type === "series") {
            return String(pref.series_provider_id || pref.seriesProviderId || "")
        }
        return String(pref.anime_provider_id || pref.animeProviderId || "")
    }

    function optionIndexForValue(options, value) {
        var needle = String(value || "")
        for (var i = 0; i < options.length; ++i) {
            if (String(options[i].value || "") === needle) {
                return i
            }
        }
        return 0
    }

    function saveManagerPreferences() {
        var movie = movieManagerCombo.currentValue !== undefined ? String(movieManagerCombo.currentValue) : ""
        var series = seriesManagerCombo.currentValue !== undefined ? String(seriesManagerCombo.currentValue) : ""
        var anime = animeManagerCombo.currentValue !== undefined ? String(animeManagerCombo.currentValue) : ""
        apiClient.updateManagerPreferences(movie, series, anime)
    }

    Component.onCompleted: {
        if (apiClient.authToken !== "") {
            apiClient.fetchExtensionsCatalog()
            apiClient.fetchManagerPreferences()
        }
    }

    Connections {
        target: apiClient
        function onAuthTokenChanged() {
            if (apiClient.authToken !== "") {
                apiClient.fetchExtensionsCatalog()
                apiClient.fetchManagerPreferences()
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + Theme.spacingXLarge * 2
        clip: true

        ColumnLayout {
            id: contentColumn
            x: Theme.spacingXLarge
            y: Theme.spacingXLarge
            width: Math.max(0, parent.width - Theme.spacingXLarge * 2)
            spacing: Theme.spacingLarge

            Label {
                text: "Settings"
                color: Theme.textPrimary
                font.pixelSize: 24
                font.family: Theme.fontDisplay
            }

            Rectangle {
                id: card
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: cardContent.implicitHeight + Theme.spacingLarge * 2
                height: implicitHeight

                ColumnLayout {
                    id: cardContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
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

                InlineToast {
                    text: serverDiscovery.statusMessage
                    autoClear: false
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontBody
                }

                Rectangle {
                    height: 1
                    color: Theme.border
                    Layout.fillWidth: true
                }

                Label {
                    text: "Extensions"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.family: Theme.fontDisplay
                }

                RowLayout {
                    spacing: Theme.spacingSmall

                    Button {
                        text: "Refresh extensions"
                        enabled: apiClient.authToken !== ""
                        onClicked: apiClient.refreshExtensionsCatalog()
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

                Label {
                    text: apiClient.extensionsLastRefreshSuccessAt !== ""
                          ? "Last refresh success: " + apiClient.extensionsLastRefreshSuccessAt
                          : "Last refresh success: never"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                Label {
                    text: apiClient.extensionsLastRefreshError !== ""
                          ? "Last refresh error: " + apiClient.extensionsLastRefreshError
                          : "Last refresh error: none"
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                }

                Rectangle {
                    height: 1
                    color: Theme.border
                    Layout.fillWidth: true
                }

                Label {
                    text: "Find Media Manager Routing"
                    color: Theme.textPrimary
                    font.pixelSize: 16
                    font.family: Theme.fontDisplay
                }

                Label {
                    text: "Movie manager"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                ComboBox {
                    id: movieManagerCombo
                    model: root.managerProvidersFor("movie")
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.optionIndexForValue(model, root.managerPreferenceFor("movie"))
                    onActivated: root.saveManagerPreferences()
                }

                Label {
                    text: "Series manager"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                ComboBox {
                    id: seriesManagerCombo
                    model: root.managerProvidersFor("series")
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.optionIndexForValue(model, root.managerPreferenceFor("series"))
                    onActivated: root.saveManagerPreferences()
                }

                Label {
                    text: "Anime manager"
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }

                ComboBox {
                    id: animeManagerCombo
                    model: root.managerProvidersFor("anime")
                    textRole: "label"
                    valueRole: "value"
                    currentIndex: root.optionIndexForValue(model, root.managerPreferenceFor("anime"))
                    onActivated: root.saveManagerPreferences()
                }

                Label {
                    text: "Auto-select uses the first healthy manager provider for each media type."
                    color: Theme.textMuted
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                    wrapMode: Text.WordWrap
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
}
