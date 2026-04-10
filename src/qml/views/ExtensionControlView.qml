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

    function mergeActionParams(action, extraParams) {
        var merged = {}
        if (action && action.params) {
            for (var key in action.params) {
                if (action.params.hasOwnProperty(key)) {
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
        var openUrl = String(action.openUrl || "")
        if (openUrl !== "") {
            Qt.openUrlExternally(openUrl)
            return
        }
        var params = mergeActionParams(action, extraParams)
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
            actionToast.show(text)
        }

        function onRequestFailed(endpoint, error) {
            var prefix = "/api/v1/extensions/" + root.extensionId + "/control-surface"
            if (root.extensionId !== "" && endpoint.indexOf(prefix) === 0) {
                actionToast.show(error)
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
                                    color: String(modelData.kind || "") === "primary"
                                           ? Theme.accent
                                           : Theme.backgroundCardRaised
                                    border.color: String(modelData.kind || "") === "primary"
                                                  ? Theme.accent
                                                  : Theme.border
                                }
                                contentItem: Label {
                                    text: parent.text
                                    color: String(modelData.kind || "") === "primary"
                                           ? "#141414"
                                           : Theme.textPrimary
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

                                            Label {
                                                visible: String(fieldData.fieldType || fieldData.field_type || "text") !== "toggle"
                                                         && String(fieldData.fieldType || fieldData.field_type || "text") !== "select"
                                                Layout.fillWidth: true
                                                text: root.displayFieldValue(fieldData)
                                                color: Theme.textPrimary
                                                font.pixelSize: 14
                                                font.family: Theme.fontBody
                                                wrapMode: Text.WordWrap
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
                                                            color: String(modelData.kind || "") === "primary"
                                                                   ? Theme.accent
                                                                   : String(modelData.kind || "") === "danger"
                                                                     ? Theme.accentDangerSoft
                                                                     : Theme.backgroundCard
                                                            border.color: String(modelData.kind || "") === "primary"
                                                                          ? Theme.accent
                                                                          : String(modelData.kind || "") === "danger"
                                                                            ? Theme.accentDanger
                                                                            : Theme.border
                                                        }
                                                        contentItem: Label {
                                                            text: parent.text
                                                            color: String(modelData.kind || "") === "primary"
                                                                   ? "#141414"
                                                                   : Theme.textPrimary
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
                                            color: String(modelData.kind || "") === "primary"
                                                   ? Theme.accent
                                                   : Theme.backgroundCardRaised
                                            border.color: String(modelData.kind || "") === "primary"
                                                          ? Theme.accent
                                                          : Theme.border
                                        }
                                        contentItem: Label {
                                            text: parent.text
                                            color: String(modelData.kind || "") === "primary"
                                                   ? "#141414"
                                                   : Theme.textPrimary
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
        id: confirmActionDialog
        modal: true
        standardButtons: Dialog.Cancel | Dialog.Ok
        anchors.centerIn: parent

        onAccepted: {
            if (!root.pendingAction || !root.pendingAction.action) {
                return
            }
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
        modal: true
        standardButtons: Dialog.Cancel | Dialog.Ok
        anchors.centerIn: parent

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
