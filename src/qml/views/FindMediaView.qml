import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "findMediaView"
    property StackView stackView: null
    property string searchQuery: ""
    property string selectedType: "movie"
    property var selectedProviderIds: []
    property bool requestPending: false
    property string statusText: ""
    property string addStatusText: ""
    property string pendingAddKey: ""

    function setSearchQuery(query) {
        updateSearchQuery(query, false)
    }

    function updateSearchQuery(query, immediate) {
        searchQuery = query
        if (query.trim() === "") {
            selectedProviderIds = []
            requestPending = false
            statusText = ""
            apiClient.findMedia("", selectedType, [])
            return
        }
        if (immediate) {
            triggerSearch()
        } else {
            searchDebounce.restart()
        }
    }

    function lower(value) {
        if (value === undefined || value === null) {
            return ""
        }
        return String(value).toLowerCase()
    }

    function mediaTypeLabel(value) {
        var normalized = lower(value)
        if (normalized === "movie" || normalized === "movies") {
            return "Movies"
        }
        if (normalized === "series" || normalized === "tv") {
            return "TV"
        }
        if (normalized === "anime") {
            return "Anime"
        }
        return "Movies"
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

    function searchProviderOptions() {
        var providers = listValue(apiClient.mediaFindResult, "search_providers", "searchProviders")
        var options = []
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var label = provider.label
            if (label === undefined || label === "") {
                var instance = provider.instance_name !== undefined ? provider.instance_name : provider.instanceName
                var implementation = provider.implementation !== undefined ? provider.implementation : ""
                label = implementation ? (instance + " (" + implementation + ")") : instance
            }
            var providerId = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            if (providerId !== undefined && providerId !== null && String(providerId) !== "") {
                options.push({ label: label, value: String(providerId || "") })
            }
        }
        return options
    }

    function providerSelected(providerId) {
        var id = String(providerId || "")
        for (var i = 0; i < selectedProviderIds.length; ++i) {
            if (String(selectedProviderIds[i]) === id) {
                return true
            }
        }
        return false
    }

    function toggleProvider(providerId, enabled) {
        var id = String(providerId || "")
        if (id === "") {
            return
        }
        var next = []
        var exists = false
        for (var i = 0; i < selectedProviderIds.length; ++i) {
            var value = String(selectedProviderIds[i])
            if (value === id) {
                exists = true
                if (enabled) {
                    next.push(value)
                }
                continue
            }
            next.push(value)
        }
        if (enabled && !exists) {
            next.push(id)
        }
        selectedProviderIds = next
    }

    function managerProvidersFor(type) {
        var key = type + "_providers"
        var camel = type + "Providers"
        var providers = listValue(apiClient.mediaManagerPreferences, key, camel)
        if (providers.length > 0) {
            return providers
        }
        if (type === "movie") {
            providers = listValue(apiClient.mediaManagerPreferences, "movies_manager_candidates", "moviesManagerCandidates")
        } else if (type === "series") {
            providers = listValue(apiClient.mediaManagerPreferences, "tv_manager_candidates", "tvManagerCandidates")
        } else {
            providers = listValue(apiClient.mediaManagerPreferences, "anime_manager_candidates", "animeManagerCandidates")
        }
        if (providers.length > 0) {
            return providers
        }
        return managerProvidersFromResult()
    }

    function preferencesObject() {
        var value = apiClient.mediaManagerPreferences.preferences
        if (value === undefined || value === null) {
            value = apiClient.mediaManagerPreferences.preferencesState
        }
        return value || {}
    }

    function selectedManagerPreferenceId() {
        var pref = preferencesObject()
        if (selectedType === "movie") {
            return String(pref.movie_provider_id || pref.movieProviderId || "")
        }
        if (selectedType === "series") {
            return String(pref.series_provider_id || pref.seriesProviderId || "")
        }
        return String(pref.anime_provider_id || pref.animeProviderId || "")
    }

    function managerOptionsForSelectedType() {
        var providers = managerProvidersFor(selectedType)
        var options = [{ label: "Auto-select", value: "" }]
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var providerId = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            var label = provider.label
            if (label === undefined || label === "") {
                label = provider.instance_name !== undefined ? provider.instance_name : provider.instanceName
            }
            options.push({ label: label, value: String(providerId || "") })
        }
        return options
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

    function managerLabelByProviderId(providerId) {
        var id = String(providerId || "")
        if (id === "") {
            return ""
        }
        var providers = managerProvidersFromResult()
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var value = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            if (String(value || "") === id) {
                return provider.label || provider.instance_name || provider.instanceName || id
            }
        }
        return id
    }

    function updateSelectedManagerPreference(providerId) {
        var pref = preferencesObject()
        var movieId = String(pref.movie_provider_id || pref.movieProviderId || "")
        var seriesId = String(pref.series_provider_id || pref.seriesProviderId || "")
        var animeId = String(pref.anime_provider_id || pref.animeProviderId || "")
        var target = String(providerId || "")
        if (selectedType === "movie") {
            movieId = target
        } else if (selectedType === "series") {
            seriesId = target
        } else {
            animeId = target
        }
        apiClient.updateManagerPreferences(movieId, seriesId, animeId)
    }

    function findResults() {
        return listValue(apiClient.mediaFindResult, "results", "results")
    }

    function providerErrors() {
        return listValue(apiClient.mediaFindResult, "provider_errors", "providerErrors")
    }

    function managerProvidersFromResult() {
        return listValue(apiClient.mediaFindResult, "manager_providers", "managerProviders")
    }

    function defaultManagerProviderId() {
        var providerId = apiClient.mediaFindResult.default_manager_provider_id
        if (providerId === undefined || providerId === null) {
            providerId = apiClient.mediaFindResult.defaultManagerProviderId
        }
        return String(providerId || "")
    }

    function managerExists(providerId) {
        var id = String(providerId || "")
        if (id === "") {
            return false
        }
        var providers = managerProvidersFromResult()
        for (var i = 0; i < providers.length; ++i) {
            var provider = providers[i]
            var value = provider.provider_id !== undefined ? provider.provider_id : provider.providerId
            if (String(value || "") === id) {
                return true
            }
        }
        return false
    }

    function resolvedManagerProviderIdForAdd() {
        var preferred = selectedManagerPreferenceId()
        if (preferred !== "" && managerExists(preferred)) {
            return preferred
        }
        var defaultId = defaultManagerProviderId()
        if (defaultId !== "" && managerExists(defaultId)) {
            return defaultId
        }
        return ""
    }

    function addDisabledReason() {
        var managers = managerProvidersFromResult()
        if (managers.length === 0) {
            return "No healthy manager provider is available for this media type."
        }
        var preferred = selectedManagerPreferenceId()
        if (preferred !== "" && !managerExists(preferred)) {
            return "Selected manager is unavailable. Choose another manager or Auto."
        }
        if (resolvedManagerProviderIdForAdd() === "") {
            return "Select a manager before adding."
        }
        return ""
    }

    function formatAddError(error) {
        var text = String(error || "")
        if (text === "") {
            return "Add request failed."
        }
        try {
            var payload = JSON.parse(text)
            if (payload.code === "manager_selection_required") {
                return "Multiple managers match this media type. Select one and retry."
            }
            if (payload.code === "missing_manager") {
                return "No compatible manager provider is currently available."
            }
            if (payload.code === "missing_required_secrets") {
                return "Manager is missing required credentials. Configure secrets and retry."
            }
            if (payload.message !== undefined && payload.message !== null) {
                return String(payload.message)
            }
        } catch (e) {
        }
        return text
    }

    function isFindEndpoint(endpoint, suffix) {
        return endpoint.indexOf("/api/v1/find/" + suffix) === 0
                || endpoint.indexOf("/api/v1/find-media/" + suffix) === 0
    }

    function defaultManagerLabel() {
        return managerLabelByProviderId(defaultManagerProviderId())
    }

    function triggerSearch() {
        var query = searchQuery.trim()
        if (query === "" || apiClient.authToken === "") {
            requestPending = false
            return
        }
        statusText = ""
        requestPending = true
        apiClient.findMedia(query, selectedType, selectedProviderIds)
    }

    function resultKey(item) {
        var title = item && item.title ? String(item.title) : ""
        var year = item && item.year ? String(item.year) : ""
        return title + "::" + year
    }

    function addResultToManager(item) {
        var blockedReason = addDisabledReason()
        if (blockedReason !== "") {
            addStatusText = blockedReason
            return
        }
        var managerProviderId = resolvedManagerProviderIdForAdd()
        pendingAddKey = resultKey(item)
        addStatusText = ""
        apiClient.addMediaToManager(selectedType, item, managerProviderId, {})
    }

    onSelectedTypeChanged: {
        selectedProviderIds = []
        if (apiClient.authToken !== "") {
            apiClient.fetchManagerPreferences()
            apiClient.findMedia("", selectedType, [])
        }
        if (searchQuery.trim() !== "") {
            searchDebounce.restart()
        }
    }

    onSelectedProviderIdsChanged: {
        if (searchQuery.trim() !== "") {
            searchDebounce.restart()
        }
    }

    Component.onCompleted: {
        if (apiClient.authToken !== "") {
            apiClient.fetchManagerPreferences()
            apiClient.findMedia("", selectedType, [])
        }
    }

    Timer {
        id: searchDebounce
        interval: 350
        repeat: false
        onTriggered: root.triggerSearch()
    }

    Timer {
        id: managerPreferencesPoll
        interval: 4000
        repeat: true
        running: root.visible && apiClient.authToken !== ""
        onTriggered: apiClient.fetchManagerPreferences()
    }

    Connections {
        target: apiClient

        function onAuthTokenChanged() {
            if (apiClient.authToken !== "") {
                apiClient.fetchManagerPreferences()
                apiClient.findMedia("", root.selectedType, [])
                if (root.searchQuery.trim() !== "") {
                    searchDebounce.restart()
                }
            } else {
                root.requestPending = false
                root.statusText = ""
            }
        }

        function onMediaFindResultChanged() {
            root.requestPending = false
            var options = root.searchProviderOptions()
            var valid = {}
            for (var i = 0; i < options.length; ++i) {
                valid[String(options[i].value || "")] = true
            }
            var filtered = []
            for (var j = 0; j < root.selectedProviderIds.length; ++j) {
                var providerId = String(root.selectedProviderIds[j] || "")
                if (valid[providerId]) {
                    filtered.push(providerId)
                }
            }
            if (filtered.length !== root.selectedProviderIds.length) {
                root.selectedProviderIds = filtered
            }
        }

        function onMediaFindLoadingChanged() {
            if (apiClient.mediaFindLoading) {
                root.requestPending = true
            }
        }

        function onRequestFailed(endpoint, error) {
            if (root.isFindEndpoint(endpoint, "search") ||
                    root.isFindEndpoint(endpoint, "targets")) {
                root.requestPending = false
                root.statusText = error
            } else if (root.isFindEndpoint(endpoint, "preferences")) {
                root.statusText = error
            } else if (root.isFindEndpoint(endpoint, "add")) {
                root.pendingAddKey = ""
                root.addStatusText = root.formatAddError(error)
            }
        }

        function onMediaAddResultChanged() {
            root.pendingAddKey = ""
            var title = apiClient.mediaAddResult.title || "Media"
            var manager = apiClient.mediaAddResult.manager_label || apiClient.mediaAddResult.managerLabel || "manager"
            root.addStatusText = title + " added via " + manager + "."
        }

        function onMediaAddLoadingChanged() {
            if (!apiClient.mediaAddLoading && root.pendingAddKey !== "" && root.addStatusText === "") {
                root.pendingAddKey = ""
            }
        }

        function onExtensionsCatalogChanged() {
            if (apiClient.authToken !== "") {
                apiClient.fetchManagerPreferences()
                apiClient.findMedia("", root.selectedType, [])
            }
        }

        function onExtensionsInstancesChanged() {
            if (apiClient.authToken !== "") {
                apiClient.fetchManagerPreferences()
                apiClient.findMedia("", root.selectedType, [])
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + Theme.spacingXLarge * 2
        clip: true

        ColumnLayout {
            id: content
            x: Theme.spacingXLarge
            y: Theme.spacingXLarge
            width: Math.max(0, parent.width - Theme.spacingXLarge * 2)
            spacing: Theme.spacingLarge

            Label {
                text: "Find Media"
                color: Theme.textPrimary
                font.pixelSize: 24
                font.family: Theme.fontDisplay
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: searchRow.implicitHeight + Theme.spacingLarge * 2

                RowLayout {
                    id: searchRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    TextField {
                        id: findSearchField
                        Layout.fillWidth: true
                        text: root.searchQuery
                        placeholderText: "Search " + root.mediaTypeLabel(root.selectedType) + " titles"
                        onTextEdited: root.updateSearchQuery(text, false)
                        onAccepted: root.updateSearchQuery(text, true)
                    }

                    Button {
                        text: "Search"
                        enabled: findSearchField.text.trim() !== ""
                        onClicked: root.updateSearchQuery(findSearchField.text, true)
                    }

                    Button {
                        text: "Clear"
                        enabled: findSearchField.text.trim() !== ""
                        onClicked: root.updateSearchQuery("", true)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Repeater {
                    model: [
                        { key: "movie", label: "Movies" },
                        { key: "series", label: "TV" },
                        { key: "anime", label: "Anime" }
                    ]

                    delegate: Button {
                        text: modelData.label
                        checkable: true
                        checked: root.selectedType === modelData.key
                        onClicked: root.selectedType = modelData.key
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            border.color: checked ? Theme.accent : Theme.border
                            color: checked ? Theme.accentSoft
                                           : Theme.backgroundCardRaised
                        }
                        contentItem: Label {
                            text: parent.text
                            color: checked ? Theme.textPrimary : Theme.textSecondary
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
                implicitHeight: managerColumn.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: managerColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    Label {
                        text: "Manager Routing"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        text: "Default manager for " + root.mediaTypeLabel(root.selectedType) + ":"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    ComboBox {
                        id: managerPreferenceCombo
                        Layout.fillWidth: true
                        model: root.managerOptionsForSelectedType()
                        textRole: "label"
                        valueRole: "value"
                        currentIndex: root.optionIndexForValue(model, root.selectedManagerPreferenceId())
                        onActivated: {
                            var value = currentValue !== undefined ? String(currentValue) : ""
                            root.updateSelectedManagerPreference(value)
                        }
                    }

                    Label {
                        text: root.defaultManagerLabel() !== ""
                              ? "Current default from provider graph: " + root.defaultManagerLabel()
                              : "No manager currently available for this media type."
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: providersColumn.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: providersColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    Label {
                        text: "Search In"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Repeater {
                            model: root.searchProviderOptions()

                            delegate: Button {
                                readonly property string providerId: modelData.value || ""
                                text: modelData.label || providerId
                                checkable: true
                                checked: root.providerSelected(providerId)
                                onClicked: root.toggleProvider(providerId, checked)
                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    border.color: checked ? Theme.accent : Theme.border
                                    color: checked ? Theme.accentSoft : Theme.backgroundCardRaised
                                }
                                contentItem: Label {
                                    text: parent.text
                                    color: checked ? Theme.textPrimary : Theme.textSecondary
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    Label {
                        text: root.selectedProviderIds.length > 0
                              ? (root.selectedProviderIds.length + " provider filter(s) active.")
                              : "All providers selected."
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }
                }
            }

            BusyIndicator {
                Layout.alignment: Qt.AlignHCenter
                running: root.requestPending || apiClient.mediaFindLoading
                visible: running
            }

            Label {
                Layout.fillWidth: true
                text: root.statusText
                color: "#f26d6d"
                font.pixelSize: 11
                font.family: Theme.fontBody
                visible: root.statusText !== ""
                wrapMode: Text.WordWrap
            }

            Label {
                Layout.fillWidth: true
                text: root.addStatusText
                color: Theme.textSecondary
                font.pixelSize: 11
                font.family: Theme.fontBody
                visible: root.addStatusText !== ""
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.providerErrors()
                delegate: Rectangle {
                    Layout.fillWidth: true
                    radius: Theme.radiusSmall
                    color: "#3a2222"
                    border.color: "#7a3a3a"
                    implicitHeight: errorText.implicitHeight + Theme.spacingSmall * 2

                    Label {
                        id: errorText
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingSmall
                        text: modelData.message || ""
                        color: Theme.textPrimary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: searchQuery.trim() === ""
                      ? "Enter a title to search."
                      : (root.findResults().length === 0 && !root.requestPending && !apiClient.mediaFindLoading
                         ? "No results found."
                         : "")
                color: Theme.textMuted
                font.pixelSize: 12
                font.family: Theme.fontBody
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.findResults()
                delegate: Rectangle {
                    Layout.fillWidth: true
                    radius: Theme.radiusLarge
                    color: Theme.backgroundCard
                    border.color: Theme.border
                    implicitHeight: rowLayout.implicitHeight + Theme.spacingMedium * 2

                    ColumnLayout {
                        id: rowLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingMedium
                        spacing: Theme.spacingSmall

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            Label {
                                Layout.fillWidth: true
                                text: {
                                    var title = modelData.title || "Untitled"
                                    var year = modelData.year || ""
                                    return year !== "" ? (title + " (" + year + ")") : title
                                }
                                color: Theme.textPrimary
                                font.pixelSize: 16
                                font.family: Theme.fontDisplay
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                                implicitWidth: typeLabel.implicitWidth + Theme.spacingSmall * 2
                                implicitHeight: typeLabel.implicitHeight + 6

                                Label {
                                    id: typeLabel
                                    anchors.centerIn: parent
                                    text: root.mediaTypeLabel(modelData.type || "")
                                    color: Theme.textSecondary
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                }
                            }

                            Button {
                                readonly property string addReason: root.addDisabledReason()
                                text: root.pendingAddKey === root.resultKey(modelData) && apiClient.mediaAddLoading
                                      ? "Adding..."
                                      : "Add"
                                enabled: !apiClient.mediaAddLoading && addReason === ""
                                onClicked: root.addResultToManager(modelData)
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.addDisabledReason()
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: text !== ""
                            wrapMode: Text.WordWrap
                        }

                        Label {
                            Layout.fillWidth: true
                            text: modelData.description || ""
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                            visible: text !== ""
                        }

                        Label {
                            Layout.fillWidth: true
                            text: {
                                var labels = modelData.source_labels || modelData.sourceLabels || []
                                return labels.length > 0
                                    ? ("Sources: " + labels.join(", "))
                                    : ""
                            }
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: text !== ""
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
