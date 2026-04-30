import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "extensionControlView"
    property StackView stackView: null
    property string extensionId: ""
    property var pendingAction: null
    property var pendingSecretAction: null
    property var actionSecretValues: ({})
    property var pendingPromptAction: null
    property var actionPromptValues: ({})
    property int postActionRefreshPassesRemaining: 0
    property string activeActionId: ""
    property string activeActionLabel: ""
    property string activeActionDescription: ""

    function controlSurface() {
        var surface = apiClient.extensionControlSurface || {}
        if (String(surface.extensionId || "") !== String(extensionId || "")) {
            return null
        }
        return surface
    }

    function refreshSurface() {
        if (apiClient.authToken === "" || extensionId === "") {
            return
        }
        apiClient.fetchExtensionControlSurface(extensionId)
        apiClient.fetchInstanceSecrets()
    }

    function openControl(targetExtensionId) {
        var trimmed = String(targetExtensionId || "")
        if (!stackView || trimmed === "") {
            return
        }
        if (trimmed === String(extensionId || "")) {
            return
        }
        stackView.push(Qt.resolvedUrl("ExtensionControlView.qml"), {
            stackView: stackView,
            extensionId: trimmed
        })
    }

    function openMarketplace(filters) {
        if (!stackView) {
            return
        }
        var params = filters || {}
        stackView.push(Qt.resolvedUrl("ExtensionsRouteView.qml"), {
            stackView: stackView,
            marketplaceKindFilter: String(params.marketplaceKind || ""),
            marketplaceTargetCapabilityFilter: String(params.marketplaceTargetCapability || ""),
            marketplaceFilterLabel: String(params.marketplaceFilterLabel || ""),
            focusMarketplace: true
        })
    }

    function browserOpenUrl(urlString) {
        var url = String(urlString || "")
        if (url === "") {
            return
        }
        if (apiClient.accessTokenExpired(30)) {
            apiClient.expireAuth("Session expired. Please sign in again.")
            return
        }
        var absolute = url
        if (url.indexOf("http://") !== 0 && url.indexOf("https://") !== 0) {
            var base = String(apiClient.baseUrl || "")
            if (base !== "") {
                absolute = base + (url.indexOf("/") === 0 ? "" : "/") + url
            }
        }
        if (String(apiClient.authToken || "") !== ""
                && absolute.indexOf(String(apiClient.baseUrl || "")) === 0
                && absolute.indexOf("/api/v1/extensions/instances/") >= 0
                && absolute.indexOf("/ui/start") >= 0
                && absolute.indexOf("access_token=") < 0
                && absolute.indexOf("token=") < 0) {
            absolute += (absolute.indexOf("?") >= 0 ? "&" : "?") + "access_token=" + encodeURIComponent(String(apiClient.authToken || ""))
        }
        Qt.openUrlExternally(absolute)
    }

    function openAdvanced() {
        if (!stackView || extensionId === "") {
            return
        }
        stackView.push(Qt.resolvedUrl("AdvancedExtensionsView.qml"), {
            stackView: stackView,
            focusExtensionId: extensionId
        })
    }

    function healthAccent(health) {
        var code = String(health || "")
        if (code === "action_required" || code === "provider_setup_required") {
            return Theme.accentInfo
        }
        if (code === "error" || code === "connection_issue") {
            return Theme.accentDanger
        }
        if (code === "attention" || code === "needs_setup" || code === "needs_attention") {
            return Theme.accent
        }
        if (code === "disabled") {
            return Theme.textMuted
        }
        return Theme.accentSuccess
    }

    function healthTint(health) {
        var code = String(health || "")
        if (code === "action_required" || code === "provider_setup_required") {
            return Theme.accentInfoSoft
        }
        if (code === "error" || code === "connection_issue") {
            return Theme.accentDangerSoft
        }
        if (code === "attention" || code === "needs_setup" || code === "needs_attention") {
            return Theme.accentSoft
        }
        if (code === "disabled") {
            return Theme.accentMutedSoft
        }
        return Theme.accentSuccessSoft
    }

    function noticeAccent(severity) {
        var code = String(severity || "")
        if (code === "error" || code === "danger") {
            return Theme.accentDanger
        }
        if (code === "warning" || code === "attention") {
            return Theme.accent
        }
        return Theme.accentInfo
    }

    function noticeTint(severity) {
        var code = String(severity || "")
        if (code === "error" || code === "danger") {
            return Theme.accentDangerSoft
        }
        if (code === "warning" || code === "attention") {
            return Theme.accentSoft
        }
        return Theme.accentInfoSoft
    }

    function actionBackground(kind, fallbackColor) {
        var code = String(kind || "")
        if (code === "primary") {
            return Theme.accent
        }
        if (code === "info") {
            return Theme.accentInfo
        }
        if (code === "danger") {
            return Theme.accentDangerSoft
        }
        return fallbackColor
    }

    function actionBorder(kind) {
        var code = String(kind || "")
        if (code === "primary") {
            return Theme.accent
        }
        if (code === "info") {
            return Theme.accentInfo
        }
        if (code === "danger") {
            return Theme.accentDanger
        }
        return Theme.border
    }

    function actionTextColor(kind) {
        var code = String(kind || "")
        if (code === "primary" || code === "info") {
            return "#141414"
        }
        return Theme.textPrimary
    }

    function policyAccent(mode) {
        var key = String(mode || "")
        if (key === "managed") {
            return Theme.accentInfo
        }
        if (key === "seeded") {
            return Theme.accent
        }
        if (key === "observed") {
            return Theme.textMuted
        }
        return Theme.border
    }

    function policyTint(mode) {
        var key = String(mode || "")
        if (key === "managed") {
            return Theme.accentInfoSoft
        }
        if (key === "seeded") {
            return Theme.accentSoft
        }
        if (key === "observed") {
            return Theme.accentMutedSoft
        }
        return Theme.backgroundCard
    }

    function displayFieldValue(field) {
        if (!field) {
            return ""
        }
        var value = field.value
        if (field.secret === true) {
            return value === undefined || value === null || String(value) === "" ? "Not set" : "Saved"
        }
        if (value === undefined || value === null) {
            return "Not set"
        }
        if (typeof value === "boolean") {
            return value ? "On" : "Off"
        }
        if (typeof value === "number") {
            return String(value)
        }
        if (Array.isArray(value)) {
            if (value.length === 0) {
                return "None"
            }
            return value.join(", ")
        }
        if (typeof value === "object") {
            var parts = []
            for (var key in value) {
                if (value.hasOwnProperty(key)) {
                    parts.push(key + ": " + String(value[key]))
                }
            }
            return parts.length > 0 ? parts.join(", ") : "Not set"
        }
        var text = String(value)
        return text === "" ? "Not set" : text
    }

    function editableFieldValue(field) {
        if (!field) {
            return ""
        }
        if (field.secret === true) {
            return ""
        }
        var value = field.value
        if (value === undefined || value === null) {
            return ""
        }
        if (typeof value === "boolean" || typeof value === "number") {
            return String(value)
        }
        return String(value)
    }

    function fieldEditPlaceholder(field) {
        if (!field) {
            return ""
        }
        if (field.secret === true) {
            return root.displayFieldValue(field)
        }
        return ""
    }

    function normalizedFieldValue(field, rawValue) {
        var type = String(field && (field.fieldType || field.field_type) || "text")
        if (type === "number") {
            if (typeof rawValue === "number") {
                return rawValue
            }
            var text = String(rawValue || "").trim()
            var parsed = Number(text)
            if (!isNaN(parsed)) {
                return parsed
            }
            return text
        }
        return rawValue
    }

    function submitFieldEdit(field, rawValue) {
        if (!field || field.readonly === true || extensionId === "") {
            return
        }
        var type = String(field.fieldType || field.field_type || "text")
        var label = String(field.label || field.id || "field")
        var text = String(rawValue === undefined || rawValue === null ? "" : rawValue)
        if (field.secret === true && text.trim() === "") {
            return
        }
        if (field.required === true
                && type !== "toggle"
                && type !== "select"
                && text.trim() === "") {
            actionToast.show("Enter " + label + ".")
            return
        }
        root.updateField(field, normalizedFieldValue(field, rawValue))
    }

    function mergeActionParams(action, extraParams) {
        var merged = {}
        if (action && action.params) {
            for (var key in action.params) {
                if (action.params.hasOwnProperty(key)) {
                    if (key === "promptFields" || key === "promptTitle" || key === "submitLabel") {
                        continue
                    }
                    merged[key] = action.params[key]
                }
            }
        }
        if (extraParams) {
            for (var extraKey in extraParams) {
                if (extraParams.hasOwnProperty(extraKey)) {
                    merged[extraKey] = extraParams[extraKey]
                }
            }
        }
        return merged
    }

    function actionPromptFields(action) {
        if (!action || !action.params || !action.params.promptFields) {
            return []
        }
        return action.params.promptFields || []
    }

    function actionPromptTitle(action) {
        if (!action || !action.params) {
            return ""
        }
        return String(action.params.promptTitle || action.label || "Action")
    }

    function actionPromptValue(field) {
        if (!field) {
            return ""
        }
        var key = String(field.id || "")
        if (actionPromptValues[key] !== undefined) {
            return actionPromptValues[key]
        }
        return field.value
    }

    function setActionPromptValue(fieldId, value) {
        var next = {}
        for (var key in actionPromptValues) {
            if (actionPromptValues.hasOwnProperty(key)) {
                next[key] = actionPromptValues[key]
            }
        }
        next[String(fieldId || "")] = value
        actionPromptValues = next
    }

    function actionPromptOptionIndex(field) {
        if (!field || !field.options) {
            return -1
        }
        var current = actionPromptValue(field)
        for (var i = 0; i < field.options.length; ++i) {
            if (field.options[i].value === current) {
                return i
            }
        }
        return -1
    }

    function beginActionRequest(action) {
        activeActionId = String(action && action.id ? action.id : "")
        activeActionLabel = String(action && action.label ? action.label : "Action")
        activeActionDescription = String(action && action.description ? action.description : "")
    }

    function finishActionRequest() {
        activeActionId = ""
        activeActionLabel = ""
        activeActionDescription = ""
    }

    function activeActionProgressSummary() {
        var id = String(activeActionId || "")
        if (id === "add_server" || id === "edit_server" || id === "remove_server") {
            return "Elixir is applying the provider change in NZBGet and waiting for the service to settle."
        }
        if (id === "test_server") {
            return "Elixir is asking NZBGet to validate the provider with its live connection test."
        }
        var description = String(activeActionDescription || "")
        if (description !== "") {
            return description
        }
        return "Elixir is applying the requested change."
    }

    function openActionPrompt(action, params) {
        pendingPromptAction = {
            action: action,
            params: params || {}
        }
        var next = {}
        var fields = actionPromptFields(action)
        for (var i = 0; i < fields.length; ++i) {
            var field = fields[i]
            next[String(field.id || "")] = field.value
        }
        actionPromptValues = next
        actionPromptDialog.title = actionPromptTitle(action)
        actionPromptDialog.open()
    }

    function normalizedPromptValue(field, rawValue) {
        var type = String(field.fieldType || field.field_type || "text")
        if (type === "number") {
            if (typeof rawValue === "number") {
                return rawValue
            }
            var text = String(rawValue || "").trim()
            var parsed = Number(text)
            if (!isNaN(parsed)) {
                return parsed
            }
            return text
        }
        return rawValue
    }

    function actionFieldLabel(field) {
        var key = String(field || "")
        if (key === "api_key") {
            return "API key"
        }
        if (key === "username") {
            return "Username"
        }
        if (key === "password") {
            return "Password"
        }
        return key.replace(/_/g, " ")
    }

    function actionSecretValue(secretKey) {
        return String(actionSecretValues[secretKey] || "")
    }

    function setActionSecretValue(secretKey, value) {
        var next = {}
        for (var key in actionSecretValues) {
            if (actionSecretValues.hasOwnProperty(key)) {
                next[key] = actionSecretValues[key]
            }
        }
        next[String(secretKey || "")] = value
        actionSecretValues = next
    }

    function instanceSecretKeys(instanceId) {
        var keys = {}
        for (var i = 0; i < apiClient.extensionsSecrets.length; ++i) {
            var secret = apiClient.extensionsSecrets[i]
            if (String(secret.scope || "") !== "instance") {
                continue
            }
            if (String(secret.scopeId || "") !== String(instanceId || "")) {
                continue
            }
            keys[String(secret.key || "")] = true
        }
        return keys
    }

    function hasInstanceSecret(instanceId, key) {
        var present = instanceSecretKeys(instanceId)
        return !!present[String(key || "")]
    }

    function runPreparedAction(action, params) {
        if (!action || extensionId === "") {
            return
        }
        var confirmText = String(action.confirmText || "")
        if (confirmText !== "") {
            pendingAction = {
                action: action,
                params: params
            }
            confirmActionDialog.title = String(action.label || "Confirm action")
            confirmActionText.text = confirmText
            confirmActionDialog.open()
            return
        }
        beginActionRequest(action)
        apiClient.invokeExtensionControlAction(extensionId, String(action.id || ""), params)
    }

    function runAction(action, extraParams) {
        if (!action || extensionId === "") {
            return
        }
        var navigateExtensionId = String(action.navigateExtensionId || "")
        if (navigateExtensionId !== "") {
            openControl(navigateExtensionId)
            return
        }
        var navigateView = String(action.navigateView || "")
        if (navigateView === "extensions_marketplace") {
            openMarketplace(action.params || {})
            return
        }
        var openUrl = String(action.openUrl || "")
        if (openUrl !== "") {
            browserOpenUrl(openUrl)
            return
        }
        var params = mergeActionParams(action, extraParams)
        if (actionPromptFields(action).length > 0) {
            openActionPrompt(action, params)
            return
        }
        var secretScopeInstanceId = String(action.secretScopeInstanceId || "")
        var secretKeys = action.secretKeys || []
        if (secretScopeInstanceId !== "" && secretKeys.length > 0) {
            var missing = []
            for (var i = 0; i < secretKeys.length; ++i) {
                var key = String(secretKeys[i] || "")
                if (key !== "" && !hasInstanceSecret(secretScopeInstanceId, key)) {
                    missing.push(key)
                }
            }
            if (missing.length > 0) {
                pendingSecretAction = {
                    action: action,
                    params: params
                }
                actionSecretValues = ({})
                connectorSecretDialog.title = String(action.label || "Connector setup")
                connectorSecretDialog.open()
                return
            }
        }
        runPreparedAction(action, params)
    }

    function submitPendingPromptAction() {
        if (!pendingPromptAction || !pendingPromptAction.action) {
            return true
        }
        var action = pendingPromptAction.action
        var params = pendingPromptAction.params || {}
        var fields = actionPromptFields(action)
        var merged = mergeActionParams(action, params)
        for (var i = 0; i < fields.length; ++i) {
            var field = fields[i]
            var key = String(field.id || "")
            var value = actionPromptValue(field)
            var type = String(field.fieldType || field.field_type || "text")
            if (field.required === true) {
                if (type === "toggle") {
                    // Bool fields are always present.
                } else if (String(value === undefined ? "" : value).trim() === "") {
                    actionToast.show("Enter " + String(field.label || key) + ".")
                    return false
                }
            }
            merged[key] = normalizedPromptValue(field, value)
        }
        pendingPromptAction = null
        actionPromptValues = ({})
        actionPromptDialog.close()
        runPreparedAction(action, merged)
        return true
    }

    function submitPendingSecretAction() {
        if (!pendingSecretAction || !pendingSecretAction.action) {
            return
        }
        var action = pendingSecretAction.action
        var params = pendingSecretAction.params || {}
        var secretScopeInstanceId = String(action.secretScopeInstanceId || "")
        var secretKeys = action.secretKeys || []
        var requiredFields = action.requiredFields || []
        for (var i = 0; i < secretKeys.length; ++i) {
            var key = String(secretKeys[i] || "")
            if (key === "") {
                continue
            }
            if (String(actionSecretValues[key] || "").trim() === "") {
                actionToast.show("Enter " + actionFieldLabel(i < requiredFields.length ? requiredFields[i] : key) + ".")
                return
            }
        }
        if (secretScopeInstanceId !== "") {
            for (var idx = 0; idx < secretKeys.length; ++idx) {
                var createKey = String(secretKeys[idx] || "")
                if (createKey === "") {
                    continue
                }
                apiClient.createInstanceSecret(
                    secretScopeInstanceId,
                    createKey,
                    String(actionSecretValues[createKey] || ""))
            }
        }
        pendingSecretAction = null
        actionSecretValues = ({})
        connectorSecretDialog.close()
        runPreparedAction(action, params)
    }

    function updateField(field, value) {
        if (!field || field.readonly === true || extensionId === "") {
            return
        }
        var payload = {}
        payload[String(field.id || "")] = value
        apiClient.updateExtensionControlSurfaceSettings(extensionId, payload)
    }

    function fieldCurrentOptionIndex(field) {
        if (!field || !field.options) {
            return -1
        }
        var current = field.value
        for (var i = 0; i < field.options.length; ++i) {
            if (field.options[i].value === current) {
                return i
            }
        }
        return -1
    }

    Component.onCompleted: refreshSurface()
    onExtensionIdChanged: refreshSurface()

    Connections {
        target: apiClient

        function onAuthTokenChanged() {
            if (apiClient.authToken !== "") {
                root.refreshSurface()
            }
        }

        function onExtensionControlActionCompleted(targetExtensionId, actionId, message) {
            if (String(targetExtensionId || "") !== String(root.extensionId || "")) {
                return
            }
            var text = String(message || "")
            if (text === "") {
                text = "Action completed."
            }
            root.finishActionRequest()
            actionToast.show(text)
            root.refreshSurface()
            apiClient.fetchExtensionStatusSummary()
            postActionRefreshPassesRemaining = 4
            postActionRefreshTimer.restart()
        }

        function onRequestFailed(endpoint, error) {
            var prefix = "/api/v1/extensions/" + root.extensionId + "/control-surface"
            var actionPrefix = prefix + "/actions/"
            if (root.extensionId !== "" && endpoint.indexOf(actionPrefix) === 0) {
                root.finishActionRequest()
                actionToast.show(error)
                return
            }
            if (root.extensionId !== "" && endpoint.indexOf(prefix) === 0) {
                actionToast.show(error)
            }
        }
    }

    Timer {
        id: postActionRefreshTimer
        interval: 1200
        repeat: false
        onTriggered: {
            if (root.extensionId === "" || apiClient.authToken === "") {
                postActionRefreshPassesRemaining = 0
                return
            }
            if (postActionRefreshPassesRemaining <= 0) {
                return
            }
            postActionRefreshPassesRemaining -= 1
            root.refreshSurface()
            apiClient.fetchExtensionStatusSummary()
            if (postActionRefreshPassesRemaining > 0) {
                postActionRefreshTimer.restart()
            }
        }
    }

    Flickable {
        id: contentScroller
        anchors.fill: parent
        focus: true
        clip: true
        contentWidth: width
        contentHeight: pageContent.implicitHeight + Theme.spacingXLarge * 2
        boundsBehavior: Flickable.StopAtBounds

        Keys.onUpPressed: {
            contentY = Math.max(0, contentY - 120)
            event.accepted = true
        }
        Keys.onDownPressed: {
            contentY = Math.min(Math.max(0, contentHeight - height), contentY + 120)
            event.accepted = true
        }

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            width: 10
        }

        ColumnLayout {
            id: pageContent
            x: Theme.spacingXLarge
            y: Theme.spacingXLarge
            width: Math.max(0, parent.width - Theme.spacingXLarge * 2)
            spacing: Theme.spacingLarge

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXLarge
                Layout.rightMargin: Theme.spacingXLarge
                spacing: Theme.spacingMedium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Label {
                        text: {
                            var surface = root.controlSurface()
                            if (surface) {
                                return String(surface.name || surface.extensionId || "Extension")
                            }
                            return "Extension"
                        }
                        color: Theme.textPrimary
                        font.pixelSize: 24
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        text: {
                            var surface = root.controlSurface()
                            if (!surface) {
                                return "Loading extension controls..."
                            }
                            return surface.instanceName
                                   ? "Manage " + String(surface.instanceName) + " in a native Elixir control page."
                                   : "Manage this extension in a native Elixir control page."
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
                    enabled: apiClient.authToken !== "" && root.extensionId !== ""
                    onClicked: root.refreshSurface()
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
                    text: "Advanced"
                    enabled: root.extensionId !== ""
                    onClicked: root.openAdvanced()
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
                    text: "Back"
                    visible: root.stackView !== null
                    onClicked: root.stackView.pop()
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
                visible: apiClient.extensionControlLoading && root.activeActionLabel !== ""
                radius: Theme.radiusLarge
                color: Theme.backgroundCardRaised
                border.color: Theme.border
                implicitHeight: actionProgressContent.implicitHeight + Theme.spacingMedium * 2

                RowLayout {
                    id: actionProgressContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMedium
                    spacing: Theme.spacingMedium

                    BusyIndicator {
                        running: parent.parent.visible
                        visible: running
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXSmall

                        Label {
                            Layout.fillWidth: true
                            text: "Applying " + root.activeActionLabel + "..."
                            color: Theme.textPrimary
                            font.pixelSize: 13
                            font.family: Theme.fontDisplay
                            wrapMode: Text.WordWrap
                        }

                        Label {
                            Layout.fillWidth: true
                            text: root.activeActionProgressSummary()
                            color: Theme.textSecondary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            wrapMode: Text.WordWrap
                        }
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
                implicitHeight: statusContent.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: statusContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            Label {
                                text: "Status"
                                color: Theme.textPrimary
                                font.pixelSize: 18
                                font.family: Theme.fontDisplay
                            }

                            Label {
                                text: {
                                    var surface = root.controlSurface()
                                    if (!surface) {
                                        return apiClient.extensionControlLoading
                                               ? "Loading extension details..."
                                               : "No control surface is available yet."
                                    }
                                    return String(surface.status.summary || "Working normally")
                                }
                                color: Theme.textPrimary
                                font.pixelSize: 14
                                font.family: Theme.fontBody
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }

                        Rectangle {
                            property var surface: root.controlSurface()
                            property string health: surface ? String(surface.status.health || "ready") : "ready"
                            radius: Theme.radiusSmall
                            color: Qt.rgba(
                                root.healthTint(health).r,
                                root.healthTint(health).g,
                                root.healthTint(health).b,
                                0.18
                            )
                            border.color: root.healthAccent(health)
                            implicitHeight: 28
                            implicitWidth: statusLabel.implicitWidth + 18

                            Label {
                                id: statusLabel
                                anchors.centerIn: parent
                                text: {
                                    if (!parent.surface) {
                                        return apiClient.extensionControlLoading ? "Loading" : "Unknown"
                                    }
                                    var summary = String(parent.surface.status.summary || "")
                                    return summary === "" ? "Ready" : summary
                                }
                                color: parent.border.color
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall
                        visible: root.controlSurface() && (root.controlSurface().status.details || []).length > 0

                        Repeater {
                            model: root.controlSurface() ? (root.controlSurface().status.details || []) : []
                            delegate: Label {
                                Layout.fillWidth: true
                                text: "\u2022 " + String(modelData || "")
                                color: Theme.textSecondary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall
                        visible: root.controlSurface() &&
                                 root.controlSurface().status.telemetry &&
                                 (root.controlSurface().status.telemetry.metrics || []).length > 0

                        Repeater {
                            model: root.controlSurface() && root.controlSurface().status.telemetry
                                   ? (root.controlSurface().status.telemetry.metrics || [])
                                   : []
                            delegate: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                                implicitHeight: 28
                                implicitWidth: metricLabel.implicitWidth + 18

                                Label {
                                    id: metricLabel
                                    anchors.centerIn: parent
                                    text: String((modelData.label || "") + ": " + (modelData.value || ""))
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
                        visible: root.controlSurface() && (root.controlSurface().actions || []).length > 0

                        Repeater {
                            model: root.controlSurface() ? (root.controlSurface().actions || []) : []
                            delegate: Button {
                                text: String(modelData.label || "Run")
                                enabled: !apiClient.extensionControlLoading
                                onClicked: root.runAction(modelData)
                                background: Rectangle {
                                    radius: Theme.radiusSmall
                                    color: root.actionBackground(modelData.kind, Theme.backgroundCardRaised)
                                    border.color: root.actionBorder(modelData.kind)
                                }
                                contentItem: Label {
                                    text: parent.text
                                    color: root.actionTextColor(modelData.kind)
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXLarge
                Layout.rightMargin: Theme.spacingXLarge
                spacing: Theme.spacingMedium
                visible: root.controlSurface() && (root.controlSurface().sections || []).length > 0

                Repeater {
                    model: root.controlSurface() ? (root.controlSurface().sections || []) : []
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusLarge
                        color: Theme.backgroundCard
                        border.color: Theme.border
                        implicitHeight: sectionContent.implicitHeight + Theme.spacingLarge * 2

                        ColumnLayout {
                            id: sectionContent
                            anchors.fill: parent
                            anchors.margins: Theme.spacingLarge
                            spacing: Theme.spacingMedium

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSmall

                                Label {
                                    text: String(modelData.title || "")
                                    color: Theme.textPrimary
                                    font.pixelSize: 18
                                    font.family: Theme.fontDisplay
                                }

                                Label {
                                    text: String(modelData.description || "")
                                    color: Theme.textSecondary
                                    font.pixelSize: 12
                                    font.family: Theme.fontBody
                                    wrapMode: Text.WordWrap
                                    visible: text !== ""
                                    Layout.fillWidth: true
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSmall
                                    visible: !!modelData.policy

                                    Rectangle {
                                        radius: Theme.radiusSmall
                                        color: Qt.rgba(
                                            root.policyTint(String((modelData.policy || {}).mode || "")).r,
                                            root.policyTint(String((modelData.policy || {}).mode || "")).g,
                                            root.policyTint(String((modelData.policy || {}).mode || "")).b,
                                            0.18
                                        )
                                        border.color: root.policyAccent(String((modelData.policy || {}).mode || ""))
                                        implicitHeight: 24
                                        implicitWidth: policyLabel.implicitWidth + 14

                                        Label {
                                            id: policyLabel
                                            anchors.centerIn: parent
                                            text: String((modelData.policy || {}).label || "")
                                            color: parent.border.color
                                            font.pixelSize: 10
                                            font.family: Theme.fontBody
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        text: String((modelData.policy || {}).description || "")
                                        color: Theme.textMuted
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                        visible: text !== ""
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSmall
                                visible: (modelData.notices || []).length > 0

                                Repeater {
                                    model: modelData.notices || []
                                    delegate: Rectangle {
                                        property var noticeData: modelData
                                        Layout.fillWidth: true
                                        radius: Theme.radiusMedium
                                        color: Qt.rgba(
                                            root.noticeTint(String(noticeData.severity || "")).r,
                                            root.noticeTint(String(noticeData.severity || "")).g,
                                            root.noticeTint(String(noticeData.severity || "")).b,
                                            0.16
                                        )
                                        border.color: root.noticeAccent(String(noticeData.severity || ""))
                                        implicitHeight: noticeContent.implicitHeight + Theme.spacingMedium * 2

                                        ColumnLayout {
                                            id: noticeContent
                                            anchors.fill: parent
                                            anchors.margins: Theme.spacingMedium
                                            spacing: Theme.spacingSmall

                                            Label {
                                                Layout.fillWidth: true
                                                text: String(noticeData.title || "")
                                                color: root.noticeAccent(String(noticeData.severity || ""))
                                                font.pixelSize: 13
                                                font.family: Theme.fontDisplay
                                                wrapMode: Text.WordWrap
                                            }

                                            Label {
                                                Layout.fillWidth: true
                                                text: String(noticeData.message || "")
                                                color: Theme.textSecondary
                                                font.pixelSize: 11
                                                font.family: Theme.fontBody
                                                wrapMode: Text.WordWrap
                                                visible: text !== ""
                                            }

                                            Button {
                                                visible: !!noticeData.action
                                                text: String((noticeData.action || {}).label || "Run")
                                                enabled: !apiClient.extensionControlLoading
                                                onClicked: root.runAction(noticeData.action)
                                                background: Rectangle {
                                                    radius: Theme.radiusSmall
                                                    color: root.actionBackground((noticeData.action || {}).kind, Theme.backgroundCard)
                                                    border.color: root.actionBorder((noticeData.action || {}).kind)
                                                }
                                                contentItem: Label {
                                                    text: parent.text
                                                    color: root.actionTextColor((noticeData.action || {}).kind)
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontBody
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingMedium
                                visible: (modelData.fields || []).length > 0

                                Repeater {
                                    model: modelData.fields || []
                                    delegate: Rectangle {
                                        property var fieldData: modelData
                                        Layout.fillWidth: true
                                        radius: Theme.radiusMedium
                                        color: Theme.backgroundCardRaised
                                        border.color: Theme.border
                                        implicitHeight: fieldContent.implicitHeight + Theme.spacingMedium * 2

                                        ColumnLayout {
                                            id: fieldContent
                                            anchors.fill: parent
                                            anchors.margins: Theme.spacingMedium
                                            spacing: Theme.spacingSmall

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.spacingSmall

                                                Label {
                                                    text: String(fieldData.label || "")
                                                    color: Theme.textPrimary
                                                    font.pixelSize: 13
                                                    font.family: Theme.fontDisplay
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                }

                                                Rectangle {
                                                    visible: fieldData.readonly === true
                                                    radius: Theme.radiusSmall
                                                    color: Theme.backgroundCard
                                                    border.color: Theme.border
                                                    implicitHeight: 22
                                                    implicitWidth: readonlyLabel.implicitWidth + 12

                                                    Label {
                                                        id: readonlyLabel
                                                        anchors.centerIn: parent
                                                        text: "Read only"
                                                        color: Theme.textMuted
                                                        font.pixelSize: 10
                                                        font.family: Theme.fontBody
                                                    }
                                                }
                                            }

                                            Switch {
                                                visible: String(fieldData.fieldType || fieldData.field_type || "text") === "toggle"
                                                         && fieldData.readonly !== true
                                                checked: Boolean(fieldData.value)
                                                enabled: !apiClient.extensionControlLoading
                                                onClicked: root.updateField(fieldData, checked)
                                            }

                                            ComboBox {
                                                visible: String(fieldData.fieldType || fieldData.field_type || "text") === "select"
                                                         && fieldData.readonly !== true
                                                Layout.fillWidth: true
                                                model: fieldData.options || []
                                                textRole: "label"
                                                valueRole: "value"
                                                currentIndex: root.fieldCurrentOptionIndex(fieldData)
                                                enabled: !apiClient.extensionControlLoading
                                                onActivated: root.updateField(fieldData, currentValue)
                                            }

                                            Label {
                                                visible: (String(fieldData.fieldType || fieldData.field_type || "text") === "select"
                                                          || String(fieldData.fieldType || fieldData.field_type || "text") === "toggle")
                                                         && fieldData.readonly === true
                                                Layout.fillWidth: true
                                                text: root.displayFieldValue(fieldData)
                                                color: Theme.textPrimary
                                                font.pixelSize: 14
                                                font.family: Theme.fontBody
                                                wrapMode: Text.WordWrap
                                            }

                                            Label {
                                                visible: String(fieldData.fieldType || fieldData.field_type || "text") !== "toggle"
                                                         && String(fieldData.fieldType || fieldData.field_type || "text") !== "select"
                                                         && fieldData.readonly === true
                                                Layout.fillWidth: true
                                                text: root.displayFieldValue(fieldData)
                                                color: Theme.textPrimary
                                                font.pixelSize: 14
                                                font.family: Theme.fontBody
                                                wrapMode: Text.WordWrap
                                            }

                                            RowLayout {
                                                visible: String(fieldData.fieldType || fieldData.field_type || "text") !== "toggle"
                                                         && String(fieldData.fieldType || fieldData.field_type || "text") !== "select"
                                                         && fieldData.readonly !== true
                                                Layout.fillWidth: true
                                                spacing: Theme.spacingSmall

                                                TextField {
                                                    id: inlineFieldEditor
                                                    Layout.fillWidth: true
                                                    text: root.editableFieldValue(fieldData)
                                                    placeholderText: root.fieldEditPlaceholder(fieldData)
                                                    echoMode: fieldData.secret === true ? TextInput.Password : TextInput.Normal
                                                    enabled: !apiClient.extensionControlLoading
                                                    onAccepted: root.submitFieldEdit(fieldData, text)
                                                }

                                                Button {
                                                    text: "Save"
                                                    enabled: !apiClient.extensionControlLoading
                                                    onClicked: root.submitFieldEdit(fieldData, inlineFieldEditor.text)
                                                }
                                            }

                                            Label {
                                                Layout.fillWidth: true
                                                text: String(fieldData.description || "")
                                                color: Theme.textSecondary
                                                font.pixelSize: 11
                                                font.family: Theme.fontBody
                                                wrapMode: Text.WordWrap
                                                visible: text !== ""
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingMedium
                                visible: (modelData.entities || []).length > 0

                                Repeater {
                                    model: modelData.entities || []
                                    delegate: Rectangle {
                                        property var entityData: modelData
                                        Layout.fillWidth: true
                                        radius: Theme.radiusMedium
                                        color: Theme.backgroundCardRaised
                                        border.color: Theme.border
                                        implicitHeight: entityContent.implicitHeight + Theme.spacingMedium * 2

                                        ColumnLayout {
                                            id: entityContent
                                            anchors.fill: parent
                                            anchors.margins: Theme.spacingMedium
                                            spacing: Theme.spacingSmall

                                            Label {
                                                Layout.fillWidth: true
                                                text: String(entityData.title || "")
                                                color: Theme.textPrimary
                                                font.pixelSize: 14
                                                font.family: Theme.fontDisplay
                                                wrapMode: Text.WordWrap
                                            }

                                            Label {
                                                Layout.fillWidth: true
                                                text: String(entityData.subtitle || "")
                                                color: Theme.textSecondary
                                                font.pixelSize: 12
                                                font.family: Theme.fontBody
                                                wrapMode: Text.WordWrap
                                                visible: text !== ""
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.spacingSmall
                                                visible: (entityData.details || []).length > 0

                                                Repeater {
                                                    model: entityData.details || []
                                                    delegate: Label {
                                                        Layout.fillWidth: true
                                                        text: "\u2022 " + String(modelData || "")
                                                        color: Theme.textSecondary
                                                        font.pixelSize: 11
                                                        font.family: Theme.fontBody
                                                        wrapMode: Text.WordWrap
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.spacingSmall
                                                visible: (entityData.actions || []).length > 0

                                                Repeater {
                                                    model: entityData.actions || []
                                                    delegate: Button {
                                                        text: String(modelData.label || "Run")
                                                        enabled: !apiClient.extensionControlLoading
                                                        onClicked: root.runAction(modelData)
                                                        background: Rectangle {
                                                            radius: Theme.radiusSmall
                                                            color: root.actionBackground(modelData.kind, Theme.backgroundCard)
                                                            border.color: root.actionBorder(modelData.kind)
                                                        }
                                                        contentItem: Label {
                                                            text: parent.text
                                                            color: root.actionTextColor(modelData.kind)
                                                            font.pixelSize: 11
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

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSmall
                                visible: (modelData.actions || []).length > 0

                                Repeater {
                                    model: modelData.actions || []
                                    delegate: Button {
                                        text: String(modelData.label || "Run")
                                        enabled: !apiClient.extensionControlLoading
                                        onClicked: root.runAction(modelData)
                                        background: Rectangle {
                                            radius: Theme.radiusSmall
                                            color: root.actionBackground(modelData.kind, Theme.backgroundCardRaised)
                                            border.color: root.actionBorder(modelData.kind)
                                        }
                                        contentItem: Label {
                                            text: parent.text
                                            color: root.actionTextColor(modelData.kind)
                                            font.pixelSize: 11
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

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXLarge
                Layout.rightMargin: Theme.spacingXLarge
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                visible: !apiClient.extensionControlLoading && root.controlSurface() === null
                implicitHeight: emptyState.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: emptyState
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        Layout.fillWidth: true
                        text: "This extension does not expose in-app controls yet."
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                        wrapMode: Text.WordWrap
                    }

                    Label {
                        Layout.fillWidth: true
                        text: "Use Advanced for instances, secrets, and orchestration details while the native control surface is still being expanded."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        wrapMode: Text.WordWrap
                    }

                    Button {
                        text: "Open Advanced"
                        enabled: root.extensionId !== ""
                        onClicked: root.openAdvanced()
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
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: Theme.spacingXLarge
                Layout.rightMargin: Theme.spacingXLarge
                color: "transparent"
                implicitHeight: 28

                InlineToast {
                    id: actionToast
                    anchors.left: parent.left
                    anchors.right: parent.right
                }
            }
        }
    }

    Dialog {
        id: actionPromptDialog
        parent: Overlay.overlay
        modal: true
        focus: true
        standardButtons: Dialog.Cancel | Dialog.Ok
        x: Math.max(Theme.spacingXLarge, (parent.width - width) / 2)
        y: Math.max(Theme.spacingXLarge, (parent.height - height) / 2)
        width: Math.min(parent.width * 0.92, 560)
        height: Math.min(parent.height * 0.9, 720)
        closePolicy: Popup.CloseOnEscape

        onAccepted: {
            if (!root.submitPendingPromptAction()) {
                actionPromptDialog.open()
            }
        }
        onRejected: {
            root.pendingPromptAction = null
            root.actionPromptValues = ({})
        }

        background: Rectangle {
            color: Theme.backgroundCard
            radius: Theme.radiusLarge
            border.color: Theme.border
        }

        contentItem: Flickable {
            clip: true
            contentWidth: width
            contentHeight: promptContent.implicitHeight + Theme.spacingLarge
            boundsBehavior: Flickable.StopAtBounds

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                width: 10
            }

            ColumnLayout {
                id: promptContent
                width: parent.width
                spacing: Theme.spacingMedium

                Label {
                    Layout.preferredWidth: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                    text: "Elixir will apply these settings and run any validation the extension exposes."
                    visible: root.pendingPromptAction !== null
                }

                Repeater {
                    model: root.pendingPromptAction && root.pendingPromptAction.action
                           ? root.actionPromptFields(root.pendingPromptAction.action)
                           : []

                    delegate: ColumnLayout {
                        property var fieldData: modelData
                        property string fieldType: String(fieldData.fieldType || fieldData.field_type || "text")
                        property string fieldKey: String(fieldData.id || "")

                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: String(parent.fieldData.label || parent.fieldKey)
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontDisplay
                        }

                        TextField {
                            visible: parent.fieldType === "text"
                                     || parent.fieldType === "password"
                                     || parent.fieldType === "number"
                            Layout.fillWidth: true
                            placeholderText: String(parent.fieldData.label || parent.fieldKey)
                            echoMode: parent.fieldType === "password"
                                      ? TextInput.Password
                                      : TextInput.Normal
                            inputMethodHints: parent.fieldType === "number"
                                              ? Qt.ImhDigitsOnly
                                              : Qt.ImhNone
                            text: {
                                var value = root.actionPromptValue(parent.fieldData)
                                return value === undefined || value === null ? "" : String(value)
                            }
                            onTextChanged: root.setActionPromptValue(parent.fieldKey, text)
                            color: Theme.textPrimary
                            placeholderTextColor: Theme.textMuted
                            selectedTextColor: Theme.background
                            selectionColor: Theme.accent
                            background: Rectangle {
                                radius: Theme.radiusMedium
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                            }
                        }

                        Switch {
                            visible: parent.fieldType === "toggle"
                            checked: Boolean(root.actionPromptValue(parent.fieldData))
                            onClicked: root.setActionPromptValue(parent.fieldKey, checked)
                        }

                        ComboBox {
                            visible: parent.fieldType === "select"
                            Layout.fillWidth: true
                            model: parent.fieldData.options || []
                            textRole: "label"
                            valueRole: "value"
                            currentIndex: root.actionPromptOptionIndex(parent.fieldData)
                            onActivated: root.setActionPromptValue(parent.fieldKey, currentValue)
                        }

                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            color: Theme.textSecondary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            text: String(parent.fieldData.description || "")
                            visible: text !== ""
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: confirmActionDialog
        parent: Overlay.overlay
        modal: true
        focus: true
        standardButtons: Dialog.Cancel | Dialog.Ok
        x: Math.max(Theme.spacingXLarge, (parent.width - width) / 2)
        y: Math.max(Theme.spacingXLarge, (parent.height - height) / 2)
        width: Math.min(parent.width * 0.8, 420)
        closePolicy: Popup.CloseOnEscape

        onAccepted: {
            if (!root.pendingAction || !root.pendingAction.action) {
                return
            }
            root.beginActionRequest(root.pendingAction.action)
            apiClient.invokeExtensionControlAction(
                root.extensionId,
                String(root.pendingAction.action.id || ""),
                root.pendingAction.params || {})
            root.pendingAction = null
        }
        onRejected: root.pendingAction = null

        contentItem: ColumnLayout {
            spacing: Theme.spacingMedium
            Label {
                id: confirmActionText
                Layout.preferredWidth: 320
                wrapMode: Text.WordWrap
                color: Theme.textPrimary
                font.pixelSize: 13
                font.family: Theme.fontBody
            }
        }
    }

    Dialog {
        id: connectorSecretDialog
        parent: Overlay.overlay
        modal: true
        focus: true
        standardButtons: Dialog.Cancel | Dialog.Ok
        x: Math.max(Theme.spacingXLarge, (parent.width - width) / 2)
        y: Math.max(Theme.spacingXLarge, (parent.height - height) / 2)
        width: Math.min(parent.width * 0.88, 460)
        closePolicy: Popup.CloseOnEscape

        onAccepted: root.submitPendingSecretAction()
        onRejected: {
            root.pendingSecretAction = null
            root.actionSecretValues = ({})
        }

        contentItem: ColumnLayout {
            spacing: Theme.spacingMedium

            Label {
                Layout.preferredWidth: 360
                wrapMode: Text.WordWrap
                color: Theme.textPrimary
                font.pixelSize: 13
                font.family: Theme.fontBody
                text: "Enter the connector credentials Elixir should store before activation."
            }

            Repeater {
                model: root.pendingSecretAction && root.pendingSecretAction.action
                       ? (root.pendingSecretAction.action.secretKeys || [])
                       : []

                delegate: ColumnLayout {
                    property int fieldIndex: index
                    property var actionData: root.pendingSecretAction ? root.pendingSecretAction.action : null
                    property var requiredFields: actionData ? (actionData.requiredFields || []) : []
                    property string secretKey: String(modelData || "")
                    property string fieldLabelText: root.actionFieldLabel(
                                                        fieldIndex < requiredFields.length
                                                        ? requiredFields[fieldIndex]
                                                        : secretKey)

                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Label {
                        text: parent.fieldLabelText
                        color: Theme.textPrimary
                        font.pixelSize: 12
                        font.family: Theme.fontDisplay
                    }

                    TextField {
                        Layout.preferredWidth: 320
                        placeholderText: parent.fieldLabelText
                        echoMode: parent.secretKey.toLowerCase().indexOf("password") >= 0
                                  || parent.secretKey.toLowerCase().indexOf("api_key") >= 0
                                  ? TextInput.Password
                                  : TextInput.Normal
                        text: root.actionSecretValue(parent.secretKey)
                        onTextChanged: root.setActionSecretValue(parent.secretKey, text)
                        color: Theme.textPrimary
                        placeholderTextColor: Theme.textMuted
                        selectedTextColor: Theme.background
                        selectionColor: Theme.accent
                        background: Rectangle {
                            radius: Theme.radiusMedium
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                    }
                }
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: apiClient.extensionControlLoading && root.controlSurface() === null
        visible: running
    }
}
