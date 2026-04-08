import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "extensionsView"
    property StackView stackView: null
    property bool installedExpanded: true
    property bool marketplaceExpanded: true
    property bool initialDataLoadScheduled: false
    property bool oneClickBlueprintActive: false
    property string oneClickBlueprintId: ""
    property string oneClickBlueprintParams: ""
    property string oneClickBlueprintStage: ""
    property bool oneClickBlueprintConfirmSent: false
    property bool pendingBlueprintDependencyInstall: false
    property string pendingBlueprintPlanId: ""
    property string pendingBlueprintPlanParams: ""
    property var pendingBlueprintDependencies: []

    function scheduleStatusSummaryRefresh() {
        if (apiClient.authToken === "") {
            return
        }
        statusSummaryRefreshTimer.restart()
    }

    function extensionIdFor(entry) {
        if (!entry) {
            return ""
        }
        return String(entry.extension_id !== undefined ? entry.extension_id : entry.id || "")
    }

    function extensionName(entry) {
        if (!entry) {
            return ""
        }
        var value = entry.name
        if (value === undefined || value === null || value === "") {
            value = extensionIdFor(entry)
        }
        return String(value || "")
    }

    function extensionDescription(entry) {
        if (!entry) {
            return ""
        }
        var manifest = manifestFor(entry)
        var value = manifest && manifest.description !== undefined ? manifest.description : entry.description
        return value === undefined || value === null ? "" : String(value)
    }

    function manifestFor(entry) {
        if (!entry) {
            return null
        }
        var manifest = entry.manifest_json
        if (manifest === undefined) {
            manifest = entry.manifestJson
        }
        return manifest || null
    }

    function trustLabel(entry) {
        if (!entry) {
            return ""
        }
        var value = entry.trust_level
        if (value === undefined) {
            value = entry.trustLevel
        }
        return value === undefined || value === null ? "" : String(value)
    }

    function kindLabel(entry) {
        if (!entry) {
            return ""
        }
        return String(entry.kind || "")
    }

    function isInstalled(extensionId) {
        var needle = String(extensionId || "")
        for (var i = 0; i < apiClient.extensionsInstalled.length; ++i) {
            if (extensionIdFor(apiClient.extensionsInstalled[i]) === needle) {
                return true
            }
        }
        return false
    }

    function installedExtension(extensionId) {
        var needle = String(extensionId || "")
        for (var i = 0; i < apiClient.extensionsInstalled.length; ++i) {
            var item = apiClient.extensionsInstalled[i]
            if (extensionIdFor(item) === needle) {
                return item
            }
        }
        return null
    }

    function instancesFor(extensionId) {
        var needle = String(extensionId || "")
        var results = []
        for (var i = 0; i < apiClient.extensionsInstances.length; ++i) {
            var item = apiClient.extensionsInstances[i]
            if (String(item.extension_id || "") === needle) {
                results.push(item)
            }
        }
        return results
    }

    function instanceSecretKeys(instanceId) {
        var needle = String(instanceId || "")
        var keys = {}
        for (var i = 0; i < apiClient.extensionsSecrets.length; ++i) {
            var item = apiClient.extensionsSecrets[i]
            if (String(item.scope || "") !== "instance") {
                continue
            }
            if (String(item.scope_id || "") !== needle) {
                continue
            }
            keys[String(item.key || "")] = true
        }
        return keys
    }

    function requiredInstanceSecretKeys(entry) {
        var manifest = manifestFor(entry)
        if (!manifest || !manifest.runtime || !manifest.runtime.env) {
            return []
        }
        var keys = []
        var seen = {}
        var env = manifest.runtime.env
        for (var i = 0; i < env.length; ++i) {
            var item = env[i]
            if (!item || item.from_secret === undefined || item.from_secret === null) {
                continue
            }
            var ref = String(item.from_secret)
            if (ref.indexOf("instance:") !== 0) {
                continue
            }
            var key = ref.slice("instance:".length)
            if (key !== "" && !seen[key]) {
                seen[key] = true
                keys.push(key)
            }
        }
        return keys
    }

    function missingSecretsForInstance(entry, instance) {
        if (!instance) {
            return []
        }
        var required = requiredInstanceSecretKeys(entry)
        if (required.length === 0) {
            return []
        }
        var present = instanceSecretKeys(instance.instance_id)
        var missing = []
        for (var i = 0; i < required.length; ++i) {
            var key = required[i]
            if (!present[key]) {
                missing.push(key)
            }
        }
        return missing
    }

    function desiredBlueprintRecord(extensionId) {
        var needle = String(extensionId || "")
        for (var i = 0; i < apiClient.extensionsDesiredBlueprints.length; ++i) {
            var item = apiClient.extensionsDesiredBlueprints[i]
            var blueprintId = item.blueprint_extension_id
            if (blueprintId === undefined) {
                blueprintId = item.blueprintExtensionId
            }
            if (String(blueprintId || "") === needle) {
                return item
            }
        }
        return null
    }

    function isBlueprintId(extensionId) {
        var value = String(extensionId || "")
        return value.indexOf(".blueprints.") >= 0 || value.indexOf("blueprint.") === 0
    }

    function blueprintConnectorsFor(blueprintId) {
        var entry = installedExtension(blueprintId)
        if (!entry) {
            return []
        }
        var manifest = manifestFor(entry)
        if (!manifest || manifest.connectors === undefined || manifest.connectors === null) {
            return []
        }
        return manifest.connectors
    }

    function blueprintPreferredModulesFor(blueprintId) {
        var entry = installedExtension(blueprintId)
        if (!entry) {
            return []
        }
        var manifest = manifestFor(entry)
        if (!manifest || !manifest.preferences || !manifest.preferences.providers) {
            return []
        }
        var providers = manifest.preferences.providers
        var modules = []
        var seen = {}
        for (var key in providers) {
            if (!providers.hasOwnProperty(key)) {
                continue
            }
            var pref = providers[key]
            if (!pref || pref.prefer === undefined || pref.prefer === null) {
                continue
            }
            for (var i = 0; i < pref.prefer.length; ++i) {
                var extensionId = String(pref.prefer[i] || "")
                if (extensionId === "" || extensionId === blueprintId || seen[extensionId]) {
                    continue
                }
                seen[extensionId] = true
                modules.push(extensionId)
            }
        }
        return modules
    }

    function clearPendingBlueprintPlan() {
        pendingBlueprintDependencyInstall = false
        pendingBlueprintPlanId = ""
        pendingBlueprintPlanParams = ""
        pendingBlueprintDependencies = []
    }

    function clearOneClickBlueprintFlow() {
        oneClickBlueprintActive = false
        oneClickBlueprintId = ""
        oneClickBlueprintParams = ""
        oneClickBlueprintStage = ""
        oneClickBlueprintConfirmSent = false
    }

    function ensureBlueprintDependencies(blueprintId, paramsJson) {
        if (blueprintId === "") {
            apiClient.applyBlueprintPlan(blueprintId, paramsJson)
            return
        }
        var connectors = blueprintConnectorsFor(blueprintId)
        var modules = blueprintPreferredModulesFor(blueprintId)
        var required = []
        var seen = {}
        for (var i = 0; i < connectors.length; ++i) {
            var connectorId = String(connectors[i] || "")
            if (connectorId !== "" && !seen[connectorId]) {
                seen[connectorId] = true
                required.push(connectorId)
            }
        }
        for (var j = 0; j < modules.length; ++j) {
            var moduleId = String(modules[j] || "")
            if (moduleId !== "" && !seen[moduleId]) {
                seen[moduleId] = true
                required.push(moduleId)
            }
        }

        var missing = []
        for (var k = 0; k < required.length; ++k) {
            var extensionId = required[k]
            var installed = installedExtension(extensionId)
            if (!installed) {
                var available = marketplaceEntry(extensionId)
                if (available && available.download_url) {
                    apiClient.installExtension(String(available.download_url))
                    missing.push(extensionId)
                    continue
                }
                actionToast.show("Missing required extension " + extensionId + ". Open Advanced to finish setup.")
                clearOneClickBlueprintFlow()
                return
            }
            if (installed.enabled === false) {
                apiClient.enableExtension(extensionId)
                missing.push(extensionId)
            }
        }

        if (missing.length === 0) {
            apiClient.applyBlueprintPlan(blueprintId, paramsJson)
            return
        }

        pendingBlueprintDependencyInstall = true
        pendingBlueprintPlanId = blueprintId
        pendingBlueprintPlanParams = paramsJson
        pendingBlueprintDependencies = missing
    }

    function startOneClickBlueprintInstall(blueprintId, downloadUrl, paramsJson) {
        var targetId = String(blueprintId || "").trim()
        var sourceUrl = String(downloadUrl || "").trim()
        if (targetId === "" || sourceUrl === "") {
            actionToast.show("This stack is missing its package URL.")
            return
        }

        oneClickBlueprintActive = true
        oneClickBlueprintId = targetId
        oneClickBlueprintParams = paramsJson || ""
        oneClickBlueprintStage = "installing_blueprint"
        oneClickBlueprintConfirmSent = false

        if (!isInstalled(targetId)) {
            apiClient.installExtension(sourceUrl)
            actionToast.show("Installing " + targetId + "...")
            return
        }

        var installed = installedExtension(targetId)
        if (installed && installed.enabled === false) {
            apiClient.enableExtension(targetId)
            return
        }

        oneClickBlueprintStage = "installing_dependencies"
        ensureBlueprintDependencies(targetId, oneClickBlueprintParams)
    }

    function maybeAdvanceOneClickBlueprintInstall() {
        if (!oneClickBlueprintActive || oneClickBlueprintId === "") {
            return
        }
        if (oneClickBlueprintStage === "installing_blueprint") {
            var installed = installedExtension(oneClickBlueprintId)
            if (!installed) {
                return
            }
            if (installed.enabled === false) {
                apiClient.enableExtension(oneClickBlueprintId)
                return
            }
            oneClickBlueprintStage = "installing_dependencies"
            ensureBlueprintDependencies(oneClickBlueprintId, oneClickBlueprintParams)
        }
    }

    function checkPendingBlueprintPlan() {
        if (!pendingBlueprintDependencyInstall || pendingBlueprintPlanId === "") {
            return
        }
        for (var i = 0; i < pendingBlueprintDependencies.length; ++i) {
            var installed = installedExtension(pendingBlueprintDependencies[i])
            if (!installed || installed.enabled !== true) {
                return
            }
        }
        var blueprintId = pendingBlueprintPlanId
        var paramsJson = pendingBlueprintPlanParams
        clearPendingBlueprintPlan()
        apiClient.applyBlueprintPlan(blueprintId, paramsJson)
    }

    function maybeAutoConfirmOneClickBlueprintPlan() {
        if (!oneClickBlueprintActive || oneClickBlueprintId === "" || apiClient.extensionsPlanId === "") {
            return
        }
        var plan = apiClient.extensionsPlan
        var planBlueprintId = plan.blueprint_id !== undefined ? String(plan.blueprint_id || "") : String(plan.blueprintId || "")
        if (planBlueprintId !== oneClickBlueprintId) {
            return
        }
        if (apiClient.extensionsPlanConflicts.length > 0) {
            oneClickBlueprintStage = "awaiting_user"
            oneClickBlueprintConfirmSent = false
            actionToast.show("More setup is needed for " + extensionName(installedExtension(oneClickBlueprintId)) + ". Open Advanced to finish.")
            return
        }
        if (oneClickBlueprintConfirmSent) {
            return
        }
        oneClickBlueprintStage = "confirming"
        oneClickBlueprintConfirmSent = true
        apiClient.confirmExtensionsPlan(apiClient.extensionsPlanId)
    }

    function runIsActive() {
        if (!apiClient.extensionsRun || apiClient.extensionsRun.status === undefined) {
            return false
        }
        var status = String(apiClient.extensionsRun.status || "")
        return status === "pending" || status === "running"
    }

    function openAdvanced(extensionId) {
        if (!stackView) {
            return
        }
        stackView.push(Qt.resolvedUrl("AdvancedExtensionsView.qml"), {
            stackView: stackView,
            focusExtensionId: extensionId || ""
        })
    }

    function marketplaceEntry(extensionId) {
        var needle = String(extensionId || "")
        for (var i = 0; i < apiClient.extensionsAvailable.length; ++i) {
            var item = apiClient.extensionsAvailable[i]
            if (String(item.id || "") === needle) {
                return item
            }
        }
        return null
    }

    function severityColor(severity) {
        if (severity === "attention") {
            return Theme.accent
        }
        if (severity === "disabled") {
            return Theme.textMuted
        }
        return Theme.accentSuccess
    }

    function statusAccent(status) {
        if (!status) {
            return Theme.border
        }
        var code = String(status.code || "")
        if (code === "connection_issue" || code === "degraded_runtime") {
            return Theme.accentDanger
        }
        if (status.severity === "attention") {
            return Theme.accent
        }
        if (status.severity === "disabled") {
            return Theme.textMuted
        }
        return Theme.accentSuccess
    }

    function statusTint(status) {
        if (!status) {
            return Theme.backgroundCardRaised
        }
        var code = String(status.code || "")
        if (code === "connection_issue" || code === "degraded_runtime") {
            return Theme.accentDangerSoft
        }
        if (status.severity === "attention") {
            return Theme.accentSoft
        }
        if (status.severity === "disabled") {
            return Theme.accentMutedSoft
        }
        return Theme.accentSuccessSoft
    }

    function statusChipFill(status) {
        if (!status) {
            return Theme.backgroundCard
        }
        return Qt.rgba(
            statusTint(status).r,
            statusTint(status).g,
            statusTint(status).b,
            0.18
        )
    }

    function primaryActionFor(card) {
        if (!card || !card.status) {
            return { label: "", action: "" }
        }
        var label = String(card.status.actionLabel || "")
        var action = String(card.status.action || "")
        if (label === "") {
            if (action === "enable") {
                label = "Enable"
            } else if (action === "finish_setup") {
                label = "Finish setup"
            } else if (action === "fix") {
                label = "Fix"
            } else {
                label = "Open"
            }
        }
        return { label: label, action: action }
    }

    function installedCards() {
        var cards = []
        for (var i = 0; i < apiClient.extensionsStatusItems.length; ++i) {
            var item = apiClient.extensionsStatusItems[i]
            var severity = String(item.severity || "ready")
            cards.push({
                entry: {
                    extension_id: String(item.extensionId || ""),
                    name: String(item.name || item.extensionId || ""),
                    version: String(item.version || ""),
                    kind: String(item.kind || ""),
                    trust_level: String(item.trustLevel || ""),
                    enabled: item.enabled !== false
                },
                status: {
                    severity: severity,
                    order: severity === "attention" ? 0 : (severity === "disabled" ? 2 : 1),
                    code: String(item.statusCode || ""),
                    label: String(item.label || "Ready"),
                    description: String(item.description || ""),
                    action: String(item.primaryAction || "open"),
                    actionLabel: String(item.primaryActionLabel || "Open")
                }
            })
        }
        cards.sort(function(left, right) {
            if (left.status.order !== right.status.order) {
                return left.status.order - right.status.order
            }
            return extensionName(left.entry).localeCompare(extensionName(right.entry))
        })
        return cards
    }

    function attentionCards() {
        return installedCards().filter(function(item) {
            return item.status.severity === "attention"
        })
    }

    function readyCards() {
        return installedCards().filter(function(item) {
            return item.status.severity !== "attention"
        })
    }

    function attentionSummaryText() {
        if (apiClient.extensionsInstalled.length > 0 && apiClient.extensionsStatusItems.length === 0) {
            return "Checking extension status..."
        }
        var count = apiClient.extensionsNeedsAttentionCount
        if (count === 0) {
            return apiClient.extensionsInstalled.length === 0
                   ? "Install extensions from the marketplace below."
                   : "All extensions healthy"
        }
        return count + " extension" + (count === 1 ? "" : "s") + " need attention"
    }

    function marketplaceCards() {
        var cards = []
        for (var i = 0; i < apiClient.extensionsAvailable.length; ++i) {
            var entry = apiClient.extensionsAvailable[i]
            if (isInstalled(entry.id)) {
                continue
            }
            cards.push(entry)
        }
        cards.sort(function(left, right) {
            var leftBlueprint = isBlueprintId(left.id)
            var rightBlueprint = isBlueprintId(right.id)
            if (leftBlueprint !== rightBlueprint) {
                return leftBlueprint ? -1 : 1
            }
            var leftName = String(left.name || left.id || "")
            var rightName = String(right.name || right.id || "")
            return leftName.localeCompare(rightName)
        })
        return cards
    }

    function installMarketplaceEntry(entry) {
        if (!entry) {
            return
        }
        var extensionId = String(entry.id || "")
        var downloadUrl = String(entry.download_url || entry.downloadUrl || "")
        if (downloadUrl === "") {
            actionToast.show("This extension does not have a download URL.")
            return
        }
        if (isBlueprintId(extensionId)) {
            startOneClickBlueprintInstall(extensionId, downloadUrl, "")
            return
        }
        apiClient.installExtension(downloadUrl)
        actionToast.show("Installing " + String(entry.name || extensionId) + "...")
    }

    function scheduleInitialDataLoad() {
        if (apiClient.authToken === "" || initialDataLoadScheduled) {
            return
        }
        initialDataLoadScheduled = true
        initialLoadTimer.restart()
    }

    Component.onCompleted: scheduleInitialDataLoad()

    Connections {
        target: apiClient
        function onAuthTokenChanged() {
            if (apiClient.authToken !== "") {
                scheduleInitialDataLoad()
            } else {
                initialDataLoadScheduled = false
                clearPendingBlueprintPlan()
                clearOneClickBlueprintFlow()
            }
        }

        function onRequestFailed(endpoint, error) {
            if (endpoint.indexOf("/api/v1/extensions/") === 0) {
                actionToast.show(error)
            }
        }

        function onExtensionsCatalogChanged() {
            root.scheduleStatusSummaryRefresh()
            maybeAdvanceOneClickBlueprintInstall()
            checkPendingBlueprintPlan()
        }

        function onExtensionsInstancesChanged() {
            root.scheduleStatusSummaryRefresh()
            maybeAdvanceOneClickBlueprintInstall()
            checkPendingBlueprintPlan()
        }

        function onExtensionsSecretsChanged() {
            root.scheduleStatusSummaryRefresh()
        }

        function onExtensionsDesiredBlueprintsChanged() {
            root.scheduleStatusSummaryRefresh()
            maybeAdvanceOneClickBlueprintInstall()
            checkPendingBlueprintPlan()
        }

        function onExtensionsPlanChanged() {
            maybeAutoConfirmOneClickBlueprintPlan()
        }

        function onExtensionsRunChanged() {
            if (!oneClickBlueprintActive || !apiClient.extensionsRun || apiClient.extensionsRun.status === undefined) {
                return
            }
            var status = String(apiClient.extensionsRun.status || "")
            if (status === "completed") {
                actionToast.show(extensionName(installedExtension(oneClickBlueprintId)) + " is ready.")
                clearOneClickBlueprintFlow()
                apiClient.fetchExtensionsCatalog()
                apiClient.fetchExtensionInstances()
                apiClient.fetchInstanceSecrets()
                apiClient.fetchDesiredBlueprints()
            } else if (status === "failed" || status === "canceled") {
                actionToast.show("Setup for " + extensionName(installedExtension(oneClickBlueprintId)) + " needs attention. Open Advanced to finish.")
                oneClickBlueprintStage = "awaiting_user"
                oneClickBlueprintConfirmSent = false
            }
        }
    }

    Timer {
        id: initialLoadTimer
        interval: 120
        repeat: false
        onTriggered: {
            apiClient.fetchExtensionsCatalog()
            apiClient.fetchExtensionInstances()
            apiClient.fetchInstanceSecrets()
            apiClient.fetchDesiredBlueprints()
            apiClient.fetchExtensionStatusSummary()
        }
    }

    Timer {
        id: statusSummaryRefreshTimer
        interval: 120
        repeat: false
        onTriggered: apiClient.fetchExtensionStatusSummary()
    }

    Timer {
        id: runPollTimer
        interval: 2000
        repeat: true
        running: oneClickBlueprintActive && apiClient.extensionsRunId !== "" && runIsActive()
        onTriggered: apiClient.fetchExtensionRunDetail(apiClient.extensionsRunId)
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

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingMedium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Label {
                        text: "Extensions"
                        color: Theme.textPrimary
                        font.pixelSize: 24
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        text: attentionSummaryText()
                        color: attentionCards().length > 0 ? Theme.accent : Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }
                }

                Button {
                    text: "Advanced"
                    enabled: apiClient.authToken !== ""
                    onClicked: root.openAdvanced("")
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
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: installedContent.implicitHeight + Theme.spacingLarge * 2
                height: implicitHeight

                ColumnLayout {
                    id: installedContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                text: "Installed"
                                color: Theme.textPrimary
                                font.pixelSize: 18
                                font.family: Theme.fontDisplay
                            }

                            Label {
                                text: apiClient.extensionsInstalled.length === 0
                                      ? "Your installed extensions live here."
                                      : apiClient.extensionsStatusItems.length === 0
                                        ? "Checking what needs attention..."
                                      : attentionCards().length > 0
                                        ? attentionCards().length + " need attention first."
                                        : "Everything installed is ready."
                                color: Theme.textSecondary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                            }
                        }

                        Button {
                            text: installedExpanded ? "Collapse" : "Expand"
                            onClicked: installedExpanded = !installedExpanded
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

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium
                        visible: installedExpanded

                        Label {
                            text: "No extensions installed yet."
                            color: Theme.textMuted
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            visible: apiClient.extensionsInstalled.length === 0
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall
                            visible: attentionCards().length > 0

                            Label {
                                text: "Needs attention"
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontDisplay
                            }

                            Repeater {
                                model: root.attentionCards()
                                delegate: Rectangle {
                                    id: attentionCard
                                    property color cardAccent: root.statusAccent(modelData.status)
                                    Layout.fillWidth: true
                                    radius: Theme.radiusMedium
                                    color: Theme.backgroundCardRaised
                                    border.color: Qt.rgba(cardAccent.r, cardAccent.g, cardAccent.b, 0.5)
                                    implicitHeight: cardContent.implicitHeight + Theme.spacingMedium * 2
                                    height: implicitHeight
                                    clip: true

                                    Rectangle {
                                        width: 4
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        color: parent.cardAccent
                                        opacity: 0.95
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: parent.radius
                                        color: root.statusTint(modelData.status)
                                        opacity: 0.16
                                    }

                                    ColumnLayout {
                                        id: cardContent
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingMedium
                                        spacing: Theme.spacingSmall

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingSmall

                                            Label {
                                                text: root.extensionName(modelData.entry)
                                                color: Theme.textPrimary
                                                font.pixelSize: 14
                                                font.family: Theme.fontDisplay
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                radius: Theme.radiusSmall
                                                color: root.statusChipFill(modelData.status)
                                                border.color: attentionCard.cardAccent
                                                implicitHeight: 24
                                                implicitWidth: statusLabel.implicitWidth + 14

                                                Label {
                                                    id: statusLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.status.label
                                                    color: attentionCard.cardAccent
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontBody
                                                }
                                            }
                                        }

                                        RowLayout {
                                            spacing: Theme.spacingSmall
                                            Repeater {
                                                model: [
                                                    modelData.entry.version ? "v" + modelData.entry.version : "",
                                                    root.kindLabel(modelData.entry),
                                                    root.trustLabel(modelData.entry)
                                                ]
                                                delegate: PillTag {
                                                    visible: modelData !== ""
                                                    text: modelData
                                                }
                                            }
                                        }

                                        Label {
                                            text: modelData.status.description
                                            color: Theme.textSecondary
                                            font.pixelSize: 12
                                            font.family: Theme.fontBody
                                            wrapMode: Text.WordWrap
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingSmall

                                            Button {
                                                property var actionSpec: root.primaryActionFor(modelData)
                                                text: actionSpec.label
                                                visible: text !== ""
                                                onClicked: {
                                                    if (actionSpec.action === "enable") {
                                                        apiClient.enableExtension(root.extensionIdFor(modelData.entry))
                                                    } else {
                                                        root.openAdvanced(root.extensionIdFor(modelData.entry))
                                                    }
                                                }
                                                background: Rectangle {
                                                    radius: Theme.radiusSmall
                                                    color: attentionCard.cardAccent
                                                    border.color: attentionCard.cardAccent
                                                }
                                                contentItem: Label {
                                                    text: parent.text
                                                    color: "#141414"
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

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall
                            visible: readyCards().length > 0

                            Label {
                                text: attentionCards().length > 0 ? "Ready" : "Installed"
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontDisplay
                            }

                            Repeater {
                                model: root.readyCards()
                                delegate: Rectangle {
                                    id: readyCard
                                    property color cardAccent: root.statusAccent(modelData.status)
                                    Layout.fillWidth: true
                                    radius: Theme.radiusMedium
                                    color: Theme.backgroundCardRaised
                                    border.color: Qt.rgba(cardAccent.r, cardAccent.g, cardAccent.b, 0.28)
                                    implicitHeight: readyContent.implicitHeight + Theme.spacingMedium * 2
                                    height: implicitHeight
                                    clip: true

                                    Rectangle {
                                        width: 3
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        color: parent.cardAccent
                                        opacity: modelData.status.severity === "ready" ? 0.55 : 0.4
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: parent.radius
                                        color: root.statusTint(modelData.status)
                                        opacity: modelData.status.severity === "ready" ? 0.08 : 0.12
                                    }

                                    ColumnLayout {
                                        id: readyContent
                                        anchors.fill: parent
                                        anchors.margins: Theme.spacingMedium
                                        spacing: Theme.spacingSmall

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingSmall

                                            Label {
                                                text: root.extensionName(modelData.entry)
                                                color: Theme.textPrimary
                                                font.pixelSize: 14
                                                font.family: Theme.fontDisplay
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                radius: Theme.radiusSmall
                                                color: root.statusChipFill(modelData.status)
                                                border.color: readyCard.cardAccent
                                                implicitHeight: 24
                                                implicitWidth: readyStatusLabel.implicitWidth + 14

                                                Label {
                                                    id: readyStatusLabel
                                                    anchors.centerIn: parent
                                                    text: modelData.status.label
                                                    color: readyCard.cardAccent
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontBody
                                                }
                                            }
                                        }

                                        Label {
                                            text: modelData.status.description
                                            color: Theme.textSecondary
                                            font.pixelSize: 12
                                            font.family: Theme.fontBody
                                            wrapMode: Text.WordWrap
                                        }

                                        RowLayout {
                                            spacing: Theme.spacingSmall
                                            Repeater {
                                                model: [
                                                    modelData.entry.version ? "v" + modelData.entry.version : "",
                                                    root.kindLabel(modelData.entry),
                                                    root.trustLabel(modelData.entry)
                                                ]
                                                delegate: PillTag {
                                                    visible: modelData !== ""
                                                    text: modelData
                                                }
                                            }
                                        }

                                        Button {
                                            property var actionSpec: root.primaryActionFor(modelData)
                                            text: actionSpec.label
                                            onClicked: {
                                                if (actionSpec.action === "enable") {
                                                    apiClient.enableExtension(root.extensionIdFor(modelData.entry))
                                                } else {
                                                    root.openAdvanced(root.extensionIdFor(modelData.entry))
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
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: marketplaceContent.implicitHeight + Theme.spacingLarge * 2
                height: implicitHeight

                ColumnLayout {
                    id: marketplaceContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Label {
                                text: "Marketplace"
                                color: Theme.textPrimary
                                font.pixelSize: 18
                                font.family: Theme.fontDisplay
                            }

                            Label {
                                text: "Browse new extensions and one-click stacks."
                                color: Theme.textSecondary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                            }
                        }

                        Button {
                            text: "Refresh"
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

                        Button {
                            text: marketplaceExpanded ? "Collapse" : "Expand"
                            onClicked: marketplaceExpanded = !marketplaceExpanded
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

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall
                        visible: marketplaceExpanded

                        Label {
                            text: marketplaceCards().length === 0
                                  ? "No new extensions available right now."
                                  : ""
                            color: Theme.textMuted
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            visible: text !== ""
                        }

                        Repeater {
                            model: root.marketplaceCards()
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                radius: Theme.radiusMedium
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                                implicitHeight: marketCardContent.implicitHeight + Theme.spacingMedium * 2
                                height: implicitHeight

                                ColumnLayout {
                                    id: marketCardContent
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingMedium
                                    spacing: Theme.spacingSmall

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSmall

                                        Label {
                                            text: String(modelData.name || modelData.id || "")
                                            color: Theme.textPrimary
                                            font.pixelSize: 14
                                            font.family: Theme.fontDisplay
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        Button {
                                            text: root.isBlueprintId(modelData.id) ? "Install stack" : "Install"
                                            enabled: apiClient.authToken !== "" &&
                                                     !root.isInstalled(modelData.id) &&
                                                     String(modelData.download_url || modelData.downloadUrl || "") !== ""
                                            onClicked: root.installMarketplaceEntry(modelData)
                                            background: Rectangle {
                                                radius: Theme.radiusSmall
                                                color: Theme.accent
                                                border.color: Theme.accent
                                            }
                                            contentItem: Label {
                                                text: parent.text
                                                color: "#141414"
                                                font.pixelSize: 11
                                                font.family: Theme.fontBody
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                    }

                                    RowLayout {
                                        spacing: Theme.spacingSmall
                                        Repeater {
                                            model: [
                                                modelData.version ? "v" + modelData.version : "",
                                                root.isBlueprintId(modelData.id) ? "blueprint" : "",
                                                modelData.trust ? String(modelData.trust) : ""
                                            ]
                                            delegate: PillTag {
                                                visible: modelData !== ""
                                                text: modelData
                                            }
                                        }
                                    }

                                    Label {
                                        text: String(modelData.description || modelData.id || "")
                                        color: Theme.textSecondary
                                        font.pixelSize: 12
                                        font.family: Theme.fontBody
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                }
            }

            InlineToast {
                id: actionToast
                color: Theme.textMuted
                font.pixelSize: 11
                font.family: Theme.fontBody
            }
        }
    }
}
