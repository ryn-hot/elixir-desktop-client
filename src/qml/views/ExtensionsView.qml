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
    property string activeOptionalAddonId: ""
    property var activeOptionalAddonValues: ({})
    property string pendingOptionalAddonId: ""
    property string pendingOptionalAddonTargetInstanceId: ""
    property var pendingOptionalAddonSecretKeys: []
    property bool runtimeResetInFlight: false
    property string runtimeResetCompletionMessage: ""
    property int runtimeResetPollAttempts: 0
    property int runtimeResetMaxPollAttempts: 45
    property string marketplaceKindFilter: ""
    property string marketplaceTargetCapabilityFilter: ""
    property string marketplaceFilterLabel: ""
    property bool focusMarketplace: false
    property string scopedFixExtensionId: ""
    property string scopedFixState: ""
    property string scopedFixMessage: ""
    property int scopedFixAnimationFrame: 0

    function scopedFixMessageSummary(message) {
        var text = String(message || "").trim()
        if (text === "") {
            return ""
        }
        var newlineIndex = text.indexOf("\n")
        if (newlineIndex >= 0) {
            text = text.slice(0, newlineIndex).trim()
        }
        if (text.length > 180) {
            text = text.slice(0, 177).trim() + "..."
        }
        return text
    }

    function setScopedFixFeedback(extensionId, state, message) {
        scopedFixExtensionId = String(extensionId || "")
        scopedFixState = String(state || "")
        scopedFixMessage = scopedFixMessageSummary(message)
        scopedFixAnimationFrame = 0
        if (scopedFixState === "running" || scopedFixState === "resetting_runtime") {
            scopedFixAnimationTimer.restart()
            scopedFixFeedbackTimer.stop()
        } else if (scopedFixState === "success" &&
                   scopedFixExtensionId !== "" &&
                   scopedFixState !== "") {
            scopedFixAnimationTimer.stop()
            scopedFixFeedbackTimer.restart()
        } else {
            scopedFixAnimationTimer.stop()
            scopedFixFeedbackTimer.stop()
        }
    }

    function clearScopedFixFeedback() {
        scopedFixAnimationTimer.stop()
        scopedFixFeedbackTimer.stop()
        scopedFixExtensionId = ""
        scopedFixState = ""
        scopedFixMessage = ""
        scopedFixAnimationFrame = 0
    }

    function scheduleStatusSummaryRefresh() {
        if (apiClient.authToken === "") {
            return
        }
        statusSummaryRefreshTimer.restart()
    }

    function finishRuntimeReset(state, message) {
        runtimeResetInFlight = false
        runtimeResetPollAttempts = 0
        runtimeResetCompletionMessage = ""
        runtimeResetPollTimer.stop()
        var summary = scopedFixMessageSummary(message)
        if (scopedFixExtensionId !== "") {
            setScopedFixFeedback(scopedFixExtensionId, state, summary)
        }
        if (summary !== "") {
            actionToast.show(summary)
        }
        apiClient.fetchExtensionStatusSummary()
        apiClient.fetchExtensionInstances()
    }

    function statusItemForExtension(extensionId) {
        var needle = String(extensionId || "")
        if (needle === "") {
            return null
        }
        for (var i = 0; i < apiClient.extensionsStatusItems.length; ++i) {
            var candidate = apiClient.extensionsStatusItems[i]
            if (root.extensionIdFor(candidate) === needle) {
                return candidate
            }
        }
        return null
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

    function clearOneClickBlueprintFlow() {
        oneClickBlueprintActive = false
        oneClickBlueprintId = ""
        oneClickBlueprintParams = ""
        oneClickBlueprintStage = ""
        oneClickBlueprintConfirmSent = false
    }

    function clearOptionalAddonPrompt() {
        activeOptionalAddonId = ""
        activeOptionalAddonValues = ({})
    }

    function ensureBlueprintDependencies(blueprintId, paramsJson) {
        apiClient.applyBlueprintPlan(blueprintId, paramsJson)
    }

    function startOneClickBlueprintInstall(blueprintId, downloadUrl, packagePath, paramsJson) {
        var targetId = String(blueprintId || "").trim()
        var sourceUrl = String(downloadUrl || "").trim()
        var sourcePath = String(packagePath || "").trim()
        if (targetId === "" || (sourceUrl === "" && sourcePath === "")) {
            actionToast.show("This stack is missing its install source.")
            return
        }

        oneClickBlueprintActive = true
        oneClickBlueprintId = targetId
        oneClickBlueprintParams = paramsJson || ""
        oneClickBlueprintStage = "installing_blueprint"
        oneClickBlueprintConfirmSent = false

        if (!isInstalled(targetId)) {
            apiClient.installExtensionSource(sourceUrl, sourcePath)
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
            actionToast.show(blockedStageMessage(
                plan,
                "More setup is needed for " + extensionName(installedExtension(oneClickBlueprintId)) + ". Open Advanced to finish."
            ))
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

    function humanizeStageId(stageId) {
        var raw = String(stageId || "").trim()
        if (raw === "") {
            return ""
        }
        return raw.replace(/[_\.]+/g, " ")
                  .replace(/\b\w/g, function(match) { return match.toUpperCase() })
    }

    function blockedStageSummary(planOrRun) {
        if (!planOrRun) {
            return null
        }
        if (planOrRun.blockedStage) {
            return planOrRun.blockedStage
        }
        if (planOrRun.stageSummary && planOrRun.stageSummary.blockedStage) {
            return planOrRun.stageSummary.blockedStage
        }
        return null
    }

    function blockedStageMessage(planOrRun, fallbackMessage) {
        var blocked = blockedStageSummary(planOrRun)
        if (!blocked) {
            return String(fallbackMessage || "")
        }
        var stageLabel = humanizeStageId(blocked.stageId || blocked.stage_id)
        var detail = String(blocked.detail || "")
        if (stageLabel !== "" && detail !== "") {
            return "Blocked at " + stageLabel + ": " + detail
        }
        if (stageLabel !== "") {
            return "Blocked at " + stageLabel + "."
        }
        if (detail !== "") {
            return detail
        }
        return String(fallbackMessage || "")
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

    function openControl(extensionId) {
        if (!stackView) {
            return
        }
        stackView.push(Qt.resolvedUrl("ExtensionControlView.qml"), {
            stackView: stackView,
            extensionId: extensionId || ""
        })
    }

    function canRunScopedFix(card, actionSpec) {
        if (!card || !card.status) {
            return false
        }
        if (String(actionSpec && actionSpec.action || "") !== "fix") {
            return false
        }
        var extensionId = extensionIdFor(card.entry)
        return extensionId === "elixir.modules.sonarr" || extensionId === "elixir.modules.radarr"
    }

    function runScopedFix(card) {
        if (!card) {
            return
        }
        var extensionId = extensionIdFor(card.entry)
        if (extensionId === "") {
            return
        }
        setScopedFixFeedback(
            extensionId,
            "running",
            "Recreating runtime and waiting for service health..."
        )
        apiClient.invokeExtensionControlAction(extensionId, "repair_connection_issue", {})
        actionToast.show("Repairing " + extensionName(card.entry) + "...")
        scheduleStatusSummaryRefresh()
    }

    function isScopedFixRunning(card) {
        if (!card) {
            return false
        }
        return (scopedFixState === "running" || scopedFixState === "resetting_runtime") &&
               scopedFixExtensionId === extensionIdFor(card.entry)
    }

    function scopedFixNoticeVisible(card) {
        if (!card) {
            return false
        }
        return scopedFixExtensionId === extensionIdFor(card.entry) &&
               scopedFixState !== "" &&
               scopedFixMessage !== ""
    }

    function scopedFixNoticeColor(cardAccent, card) {
        if (!scopedFixNoticeVisible(card)) {
            return Theme.textMuted
        }
        if (scopedFixState === "success") {
            return cardAccent
        }
        if (scopedFixState === "error") {
            return Theme.accentDanger
        }
        return Theme.textPrimary
    }

    function scopedFixCardMessage(card) {
        if (!scopedFixNoticeVisible(card)) {
            return ""
        }
        if (!isScopedFixRunning(card)) {
            return scopedFixMessage
        }
        var base = scopedFixMessage !== "" ? scopedFixMessage : "Working"
        var dots = "."
        if (scopedFixAnimationFrame % 3 === 1) {
            dots = ".."
        } else if (scopedFixAnimationFrame % 3 === 2) {
            dots = "..."
        }
        return base + dots
    }

    function scopedFixCanResetRuntime(card) {
        if (!card) {
            return false
        }
        return scopedFixState === "error" &&
               scopedFixExtensionId === extensionIdFor(card.entry)
    }

    function scopedFixButtonLabel(card, actionSpec) {
        if (!isScopedFixRunning(card)) {
            return String(actionSpec && actionSpec.label || "")
        }
        if (scopedFixState === "resetting_runtime") {
            if (scopedFixAnimationFrame % 3 === 1) {
                return "Resetting runtime.."
            }
            if (scopedFixAnimationFrame % 3 === 2) {
                return "Resetting runtime..."
            }
            return "Resetting runtime."
        }
        if (scopedFixAnimationFrame % 3 === 1) {
            return "Repairing.."
        }
        if (scopedFixAnimationFrame % 3 === 2) {
            return "Repairing..."
        }
        return "Repairing."
    }

    function runRuntimeResetFallback(card) {
        if (!card || runtimeResetInFlight) {
            return
        }
        var extensionId = extensionIdFor(card.entry)
        runtimeResetInFlight = true
        runtimeResetCompletionMessage = ""
        runtimeResetPollAttempts = 0
        runtimeResetPollTimer.stop()
        setScopedFixFeedback(
            extensionId,
            "resetting_runtime",
            "Resetting Docker runtime"
        )
        apiClient.resetExtensionsRuntime()
        actionToast.show("Resetting Docker runtime...")
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

    function marketplaceSource(entry) {
        return {
            downloadUrl: String(entry && (entry.download_url || entry.downloadUrl) || "").trim(),
            packagePath: String(entry && (entry.package_path || entry.packagePath) || "").trim()
        }
    }

    function marketplaceFilterActive() {
        return marketplaceKindFilter !== "" || marketplaceTargetCapabilityFilter !== ""
    }

    function normalizeMarketplaceHeuristicId(entry) {
        return String(entry && entry.id ? entry.id : "").toLowerCase()
    }

    function matchesMarketplaceFilter(entry) {
        if (!entry) {
            return false
        }
        var entryId = normalizeMarketplaceHeuristicId(entry)
        if (marketplaceKindFilter !== "") {
            if (marketplaceKindFilter === "connector") {
                if (entryId.indexOf(".connectors.") < 0) {
                    return false
                }
            } else if (marketplaceKindFilter === "blueprint") {
                if (!root.isBlueprintId(entryId)) {
                    return false
                }
            }
        }
        if (marketplaceTargetCapabilityFilter !== "") {
            if (marketplaceTargetCapabilityFilter === "indexer.registry") {
                var looksLikeIndexerConnector =
                        entryId === "elixir.connectors.prowlarr_public_indexers"
                        || entryId === "elixir.connectors.prowlarr_nzbgeek"
                        || (entryId.indexOf("prowlarr_") >= 0
                            && entryId.indexOf("_sonarr") < 0
                            && entryId.indexOf("_radarr") < 0)
                        || entryId.indexOf("indexer") >= 0
                if (!looksLikeIndexerConnector) {
                    return false
                }
            }
        }
        return true
    }

    function clearMarketplaceFilter() {
        marketplaceKindFilter = ""
        marketplaceTargetCapabilityFilter = ""
        marketplaceFilterLabel = ""
        installedExpanded = true
    }

    function maybeFocusMarketplace() {
        if (!focusMarketplace) {
            return
        }
        installedExpanded = false
        marketplaceExpanded = true
        var targetY = Math.max(0, marketplaceSection.y - Theme.spacingLarge)
        pageScroller.contentY = targetY
        focusMarketplace = false
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
        if (code === "runtime_status_stale" || code === "runtime_status_recovering") {
            return Theme.accent
        }
        if (code === "provider_setup_required") {
            return Theme.accentInfo
        }
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
        if (code === "runtime_status_stale" || code === "runtime_status_recovering") {
            return Theme.accentSoft
        }
        if (code === "provider_setup_required") {
            return Theme.accentInfoSoft
        }
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

    function canCreateDefaultInstance(card, actionSpec) {
        if (!card || !card.status) {
            return false
        }
        if (String(actionSpec && actionSpec.action || "") !== "finish_setup") {
            return false
        }
        if (String(card.status.code || "") !== "missing_instance") {
            return false
        }
        var entry = card.entry || {}
        return String(entry.kind || "") !== "blueprint"
    }

    function createDefaultInstance(card) {
        if (!card) {
            return
        }
        var extensionId = extensionIdFor(card.entry)
        if (extensionId === "") {
            return
        }
        apiClient.createExtensionInstance(extensionId, "default", "")
        actionToast.show("Creating default instance for " + extensionName(card.entry) + "...")
        scheduleStatusSummaryRefresh()
    }

    function addonFieldLabel(field) {
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

    function optionalAddonValue(secretKey) {
        return String(activeOptionalAddonValues[secretKey] || "")
    }

    function setOptionalAddonValue(secretKey, value) {
        var next = {}
        for (var key in activeOptionalAddonValues) {
            if (activeOptionalAddonValues.hasOwnProperty(key)) {
                next[key] = activeOptionalAddonValues[key]
            }
        }
        next[String(secretKey || "")] = value
        activeOptionalAddonValues = next
    }

    function hasInstanceSecret(instanceId, key) {
        var present = instanceSecretKeys(instanceId)
        return !!present[String(key || "")]
    }

    function startOptionalAddonActivation(addon) {
        if (!addon) {
            return
        }
        var extensionId = String(addon.extensionId || "")
        if (extensionId === "") {
            return
        }
        var secretScopeInstanceId = String(addon.secretScopeInstanceId || "")
        var secretKeys = addon.secretKeys || []
        if (String(addon.action || "") === "open") {
            root.openControl(extensionId)
            return
        }

        pendingOptionalAddonId = extensionId
        pendingOptionalAddonTargetInstanceId = secretScopeInstanceId
        pendingOptionalAddonSecretKeys = secretKeys

        var installed = installedExtension(extensionId)
        if (installed) {
            if (installed.enabled === false) {
                apiClient.enableExtension(extensionId)
                actionToast.show("Activating " + String(addon.title || extensionId) + "...")
                return
            }
            apiClient.reconcileNow()
            actionToast.show("Refreshing " + String(addon.title || extensionId) + "...")
            pendingOptionalAddonId = ""
            pendingOptionalAddonTargetInstanceId = ""
            pendingOptionalAddonSecretKeys = []
            return
        }

        var available = marketplaceEntry(extensionId)
        var source = marketplaceSource(available)
        if (source.downloadUrl === "" && source.packagePath === "") {
            actionToast.show("This add-on is not available in the marketplace right now.")
            pendingOptionalAddonId = ""
            pendingOptionalAddonTargetInstanceId = ""
            pendingOptionalAddonSecretKeys = []
            return
        }
        apiClient.installExtensionSource(source.downloadUrl, source.packagePath)
        actionToast.show("Activating " + String(addon.title || extensionId) + "...")
    }

    function activateOptionalAddon(addon) {
        if (!addon) {
            return
        }
        var extensionId = String(addon.extensionId || "")
        if (extensionId === "") {
            return
        }
        var secretScopeInstanceId = String(addon.secretScopeInstanceId || "")
        var secretKeys = addon.secretKeys || []
        var needsPrompt = secretScopeInstanceId !== "" && secretKeys.length > 0
        if (needsPrompt) {
            var missing = []
            for (var i = 0; i < secretKeys.length; ++i) {
                var key = String(secretKeys[i] || "")
                if (key !== "" && !hasInstanceSecret(secretScopeInstanceId, key)) {
                    missing.push(key)
                }
            }
            if (missing.length > 0) {
                activeOptionalAddonId = extensionId
                activeOptionalAddonValues = ({})
                return
            }
        }
        startOptionalAddonActivation(addon)
    }

    function submitOptionalAddonPrompt(addon) {
        if (!addon) {
            return
        }
        var secretKeys = addon.secretKeys || []
        var secretScopeInstanceId = String(addon.secretScopeInstanceId || "")
        for (var i = 0; i < secretKeys.length; ++i) {
            var key = String(secretKeys[i] || "")
            if (key === "") {
                continue
            }
            if (String(activeOptionalAddonValues[key] || "").trim() === "") {
                actionToast.show("Enter " + addonFieldLabel((addon.requiredFields || [])[i] || key) + ".")
                return
            }
        }
        if (secretScopeInstanceId !== "" && secretKeys.length > 0) {
            for (var idx = 0; idx < secretKeys.length; ++idx) {
                var createKey = String(secretKeys[idx] || "")
                if (createKey === "") {
                    continue
                }
                var secretValue = String(activeOptionalAddonValues[createKey] || "")
                if (secretValue !== "") {
                    apiClient.createInstanceSecret(secretScopeInstanceId, createKey, secretValue)
                }
            }
        }
        clearOptionalAddonPrompt()
        startOptionalAddonActivation(addon)
    }

    function checkPendingOptionalAddonActivation() {
        if (pendingOptionalAddonId === "") {
            return
        }
        var installed = installedExtension(pendingOptionalAddonId)
        if (!installed || installed.enabled !== true) {
            return
        }
        if (pendingOptionalAddonTargetInstanceId !== "" && pendingOptionalAddonSecretKeys.length > 0) {
            for (var i = 0; i < pendingOptionalAddonSecretKeys.length; ++i) {
                if (!hasInstanceSecret(pendingOptionalAddonTargetInstanceId, pendingOptionalAddonSecretKeys[i])) {
                    return
                }
            }
        }
        apiClient.reconcileNow()
        pendingOptionalAddonId = ""
        pendingOptionalAddonTargetInstanceId = ""
        pendingOptionalAddonSecretKeys = []
    }

    function autoUpdateVisible(card) {
        if (!card || !card.autoUpdate) {
            return false
        }
        return String(card.autoUpdate.label || "") !== "" ||
               String(card.autoUpdate.description || "") !== ""
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
                },
                autoUpdate: item.autoUpdate ? {
                    severity: String(item.autoUpdate.severity || "ready"),
                    code: String(item.autoUpdate.statusCode || ""),
                    label: String(item.autoUpdate.label || ""),
                    description: String(item.autoUpdate.description || ""),
                    releaseVersion: String(item.autoUpdate.releaseVersion || ""),
                    checkedAt: String(item.autoUpdate.checkedAt || "")
                } : null,
                optionalAddons: item.optionalAddons || []
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
        var runtimeStatus = apiClient.extensionsRuntimeStatus || {}
        var runtimeLabel = String(runtimeStatus.label || "")
        if (runtimeLabel !== "") {
            return runtimeLabel
        }
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

    function runtimeStatusVisible() {
        var runtimeStatus = apiClient.extensionsRuntimeStatus || {}
        return String(runtimeStatus.label || "") !== ""
    }

    function runtimeStatusAccent() {
        var runtimeStatus = apiClient.extensionsRuntimeStatus || {}
        var state = String(runtimeStatus.state || "")
        if (state === "degraded" || state === "reboot_required") {
            return Theme.accentDanger
        }
        return Theme.accent
    }

    function runtimeStatusTint() {
        var runtimeStatus = apiClient.extensionsRuntimeStatus || {}
        var state = String(runtimeStatus.state || "")
        if (state === "degraded" || state === "reboot_required") {
            return Theme.accentDangerSoft
        }
        return Theme.accentSoft
    }

    function runtimeStatusDescription() {
        var runtimeStatus = apiClient.extensionsRuntimeStatus || {}
        var description = String(runtimeStatus.description || "")
        var hostWarning = String(runtimeStatus.hostWarning || "")
        var rebootRecommended = Boolean(runtimeStatus.rebootRecommended)
        var autoResetAttempts = Number(runtimeStatus.autoResetAttemptsInWindow || 0)
        var quarantined = runtimeStatus.quarantinedInstances || []
        if (hostWarning !== "" && description.indexOf(hostWarning) < 0) {
            description = description === "" ? hostWarning : description + " " + hostWarning
        }
        if (autoResetAttempts > 0) {
            var resetSuffix = "Elixir has attempted " + autoResetAttempts + " automatic Docker runtime reset"
                            + (autoResetAttempts === 1 ? "" : "s")
                            + " in the current recovery window."
            description = description === "" ? resetSuffix : description + " " + resetSuffix
        }
        if (quarantined.length > 0) {
            var suffix = quarantined.length === 1
                         ? "1 instance is quarantined while Docker stabilizes."
                         : quarantined.length + " instances are quarantined while Docker stabilizes."
            description = description === "" ? suffix : description + " " + suffix
        }
        if (rebootRecommended && description.toLowerCase().indexOf("reboot") < 0) {
            description = description === "" ? "Reboot the computer, then relaunch Elixir." : description + " Reboot the computer, then relaunch Elixir."
        }
        return description
    }

    function marketplaceCards() {
        var cards = []
        for (var i = 0; i < apiClient.extensionsAvailable.length; ++i) {
            var entry = apiClient.extensionsAvailable[i]
            if (isInstalled(entry.id)) {
                continue
            }
            if (marketplaceFilterActive() && !matchesMarketplaceFilter(entry)) {
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
        var source = marketplaceSource(entry)
        if (source.downloadUrl === "" && source.packagePath === "") {
            actionToast.show("This extension does not have an install source.")
            return
        }
        if (isBlueprintId(extensionId)) {
            startOneClickBlueprintInstall(extensionId, source.downloadUrl, source.packagePath, "")
            return
        }
        apiClient.installExtensionSource(source.downloadUrl, source.packagePath)
        actionToast.show("Installing " + String(entry.name || extensionId) + "...")
    }

    function scheduleInitialDataLoad() {
        if (apiClient.authToken === "" || initialDataLoadScheduled) {
            return
        }
        initialDataLoadScheduled = true
        initialLoadTimer.restart()
    }

    Component.onCompleted: {
        scheduleInitialDataLoad()
        Qt.callLater(maybeFocusMarketplace)
    }
    onFocusMarketplaceChanged: Qt.callLater(maybeFocusMarketplace)

    Connections {
        target: apiClient
        function onAuthTokenChanged() {
            if (apiClient.authToken !== "") {
                scheduleInitialDataLoad()
            } else {
                initialDataLoadScheduled = false
                runtimeResetInFlight = false
                runtimeResetCompletionMessage = ""
                runtimeResetPollAttempts = 0
                runtimeResetPollTimer.stop()
                clearScopedFixFeedback()
                clearOneClickBlueprintFlow()
                clearOptionalAddonPrompt()
                pendingOptionalAddonId = ""
                pendingOptionalAddonTargetInstanceId = ""
                pendingOptionalAddonSecretKeys = []
            }
        }

        function onRequestFailed(endpoint, error) {
            if (endpoint === "/api/v1/extensions/runtime/reset") {
                runtimeResetInFlight = false
                runtimeResetCompletionMessage = ""
                runtimeResetPollAttempts = 0
                runtimeResetPollTimer.stop()
                if (scopedFixExtensionId !== "") {
                    setScopedFixFeedback(
                        scopedFixExtensionId,
                        "error",
                        error || "Docker runtime reset failed."
                    )
                }
            }
            if ((endpoint === "/api/v1/extensions/install" || endpoint === "/api/v1/extensions/secrets") &&
                    pendingOptionalAddonId !== "") {
                pendingOptionalAddonId = ""
                pendingOptionalAddonTargetInstanceId = ""
                pendingOptionalAddonSecretKeys = []
            }
            if (endpoint.indexOf("/control-surface/actions/repair_connection_issue") >= 0 &&
                    scopedFixExtensionId !== "") {
                setScopedFixFeedback(
                    scopedFixExtensionId,
                    "error",
                    error || "Repair failed."
                )
            }
            if (endpoint.indexOf("/api/v1/extensions/") === 0) {
                actionToast.show(error)
            }
        }

        function onExtensionControlActionCompleted(targetExtensionId, actionId, message) {
            if (actionId !== "repair_connection_issue") {
                return
            }
            setScopedFixFeedback(
                targetExtensionId,
                "success",
                message && message !== "" ? message : "Repair completed."
            )
            actionToast.show(message && message !== "" ? message : "Repair completed.")
            apiClient.fetchExtensionStatusSummary()
            apiClient.fetchExtensionInstances()
            scheduleStatusSummaryRefresh()
        }

        function onExtensionsRuntimeResetCompleted(status, message) {
            var resetStatus = String(status || "")
            var resetMessage = message && message !== ""
                    ? message
                    : "Docker runtime reset completed."
            if (resetStatus === "reboot_recommended") {
                finishRuntimeReset("error", resetMessage)
                return
            }
            runtimeResetCompletionMessage = resetMessage
            runtimeResetPollAttempts = 0
            if (scopedFixExtensionId !== "") {
                setScopedFixFeedback(
                    scopedFixExtensionId,
                    "resetting_runtime",
                    resetStatus === "recovering"
                            ? resetMessage
                            : "Waiting for Docker runtime health to settle"
                )
            }
            apiClient.fetchExtensionStatusSummary()
            runtimeResetPollTimer.restart()
        }

        function onExtensionsStatusSummaryChanged() {
            if (runtimeResetInFlight) {
                var runtimeStatus = apiClient.extensionsRuntimeStatus || {}
                var runtimeState = String(runtimeStatus.state || "")
                var runtimeDescription = String(runtimeStatus.description || "")
                if (runtimeState === "reboot_required") {
                    finishRuntimeReset(
                        "error",
                        runtimeDescription !== ""
                                ? runtimeDescription
                                : "Docker runtime reset requires a host reboot."
                    )
                    return
                }
                if (runtimeState === "degraded" || runtimeState === "recovering") {
                    runtimeResetPollTimer.restart()
                    return
                }
                if (apiClient.extensionsInstalled.length > 0 &&
                        apiClient.extensionsStatusItems.length === 0) {
                    runtimeResetPollTimer.restart()
                    return
                }
                var targetItem = statusItemForExtension(scopedFixExtensionId)
                var targetCode = targetItem
                        ? String((targetItem.status || {}).code || targetItem.statusCode || targetItem.status_code || "")
                        : ""
                if (scopedFixExtensionId !== "" && targetItem && targetCode !== "ready") {
                    finishRuntimeReset(
                        "error",
                        String(targetItem.description || extensionName(targetItem) + " still needs attention after Docker runtime reset.")
                    )
                    return
                }
                finishRuntimeReset(
                    "success",
                    runtimeResetCompletionMessage !== ""
                            ? runtimeResetCompletionMessage
                            : "Docker runtime reset completed."
                )
                return
            }

            if (scopedFixExtensionId !== "" && scopedFixState !== "") {
                var item = statusItemForExtension(scopedFixExtensionId)
                if (!item || String((item.status || {}).code || item.status_code || item.statusCode || "") === "ready") {
                    clearScopedFixFeedback()
                }
            }
        }

        function onExtensionsCatalogChanged() {
            root.scheduleStatusSummaryRefresh()
            maybeAdvanceOneClickBlueprintInstall()
            checkPendingOptionalAddonActivation()
            Qt.callLater(root.maybeFocusMarketplace)
        }

        function onExtensionsInstancesChanged() {
            root.scheduleStatusSummaryRefresh()
            maybeAdvanceOneClickBlueprintInstall()
            checkPendingOptionalAddonActivation()
        }

        function onExtensionsSecretsChanged() {
            root.scheduleStatusSummaryRefresh()
            checkPendingOptionalAddonActivation()
        }

        function onExtensionsDesiredBlueprintsChanged() {
            root.scheduleStatusSummaryRefresh()
            maybeAdvanceOneClickBlueprintInstall()
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
                actionToast.show(blockedStageMessage(
                    apiClient.extensionsRun,
                    "Setup for " + extensionName(installedExtension(oneClickBlueprintId)) + " needs attention. Open Advanced to finish."
                ))
                oneClickBlueprintStage = "awaiting_user"
                oneClickBlueprintConfirmSent = false
            }
        }
    }

    Timer {
        id: scopedFixFeedbackTimer
        interval: 15000
        repeat: false
        onTriggered: root.clearScopedFixFeedback()
    }

    Timer {
        id: scopedFixAnimationTimer
        interval: 450
        repeat: true
        running: false
        onTriggered: scopedFixAnimationFrame = (scopedFixAnimationFrame + 1) % 3
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
        id: runtimeResetPollTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (!runtimeResetInFlight) {
                return
            }
            runtimeResetPollAttempts += 1
            if (runtimeResetPollAttempts > runtimeResetMaxPollAttempts) {
                finishRuntimeReset(
                    "error",
                    "Docker runtime reset did not stabilize before the timeout."
                )
                return
            }
            apiClient.fetchExtensionStatusSummary()
            apiClient.fetchLatestReconcileRun()
        }
    }

    Timer {
        id: runPollTimer
        interval: 2000
        repeat: true
        running: oneClickBlueprintActive && apiClient.extensionsRunId !== "" && runIsActive()
        onTriggered: apiClient.fetchExtensionRunDetail(apiClient.extensionsRunId)
    }

    Flickable {
        id: pageScroller
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
                visible: root.runtimeStatusVisible()
                radius: Theme.radiusLarge
                color: root.runtimeStatusTint()
                border.color: root.runtimeStatusAccent()
                border.width: 1
                implicitHeight: runtimeStatusColumn.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: runtimeStatusColumn
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingMedium

                        Label {
                            Layout.fillWidth: true
                            text: String((apiClient.extensionsRuntimeStatus || {}).label || "")
                            color: Theme.textPrimary
                            font.pixelSize: 15
                            font.family: Theme.fontDisplay
                        }

                        Button {
                            text: runtimeResetInFlight ? "Resetting..." : "Reset runtime"
                            enabled: !runtimeResetInFlight && apiClient.authToken !== ""
                            onClicked: {
                                runtimeResetInFlight = true
                                runtimeResetCompletionMessage = ""
                                runtimeResetPollAttempts = 0
                                runtimeResetPollTimer.stop()
                                apiClient.resetExtensionsRuntime()
                            }
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: root.runtimeStatusAccent()
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

                        Rectangle {
                            radius: Theme.radiusPill
                            color: Qt.rgba(
                                root.runtimeStatusAccent().r,
                                root.runtimeStatusAccent().g,
                                root.runtimeStatusAccent().b,
                                0.18
                            )
                            implicitHeight: runtimeStateChip.implicitHeight + 8
                            implicitWidth: runtimeStateChip.implicitWidth + 16

                            Label {
                                id: runtimeStateChip
                                anchors.centerIn: parent
                                text: String((apiClient.extensionsRuntimeStatus || {}).state || "").replace("_", " ")
                                color: root.runtimeStatusAccent()
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                            }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        text: root.runtimeStatusDescription()
                        visible: text !== ""
                        wrapMode: Text.WordWrap
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
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

                                        Rectangle {
                                            Layout.fillWidth: true
                                            visible: root.autoUpdateVisible(modelData)
                                            radius: Theme.radiusSmall
                                            color: Theme.backgroundCard
                                            border.color: Qt.rgba(
                                                root.statusAccent(modelData.autoUpdate).r,
                                                root.statusAccent(modelData.autoUpdate).g,
                                                root.statusAccent(modelData.autoUpdate).b,
                                                0.35
                                            )
                                            implicitHeight: attentionAutoUpdateContent.implicitHeight + Theme.spacingSmall * 2

                                            ColumnLayout {
                                                id: attentionAutoUpdateContent
                                                anchors.fill: parent
                                                anchors.margins: Theme.spacingSmall
                                                spacing: Theme.spacingSmall

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Theme.spacingSmall

                                                    Label {
                                                        Layout.fillWidth: true
                                                        text: "Auto-update"
                                                        color: Theme.textPrimary
                                                        font.pixelSize: 11
                                                        font.family: Theme.fontDisplay
                                                    }

                                                    Rectangle {
                                                        radius: Theme.radiusSmall
                                                        color: root.statusChipFill(modelData.autoUpdate)
                                                        border.color: root.statusAccent(modelData.autoUpdate)
                                                        implicitHeight: 22
                                                        implicitWidth: attentionAutoUpdateLabel.implicitWidth + 12

                                                        Label {
                                                            id: attentionAutoUpdateLabel
                                                            anchors.centerIn: parent
                                                            text: String((modelData.autoUpdate || {}).label || "")
                                                            color: root.statusAccent(modelData.autoUpdate)
                                                            font.pixelSize: 10
                                                            font.family: Theme.fontBody
                                                        }
                                                    }
                                                }

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: String((modelData.autoUpdate || {}).description || "")
                                                    visible: text !== ""
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
                                            visible: root.scopedFixNoticeVisible(modelData)

                                            Label {
                                                Layout.fillWidth: true
                                                text: root.scopedFixCardMessage(modelData)
                                                color: root.scopedFixNoticeColor(attentionCard.cardAccent, modelData)
                                                font.pixelSize: 11
                                                font.family: Theme.fontBody
                                                wrapMode: Text.WordWrap
                                            }

                                            Button {
                                                text: runtimeResetInFlight ? "Resetting..." : "Reset Docker runtime"
                                                visible: root.scopedFixCanResetRuntime(modelData)
                                                enabled: !runtimeResetInFlight && apiClient.authToken !== ""
                                                onClicked: root.runRuntimeResetFallback(modelData)
                                                background: Rectangle {
                                                    radius: Theme.radiusSmall
                                                    color: Theme.backgroundCard
                                                    border.color: Theme.accentDanger
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
                                            visible: modelData.optionalAddons && modelData.optionalAddons.length > 0

                                            Label {
                                                text: "Optional add-ons"
                                                color: Theme.textPrimary
                                                font.pixelSize: 12
                                                font.family: Theme.fontDisplay
                                            }

                                            Repeater {
                                                model: modelData.optionalAddons || []
                                                delegate: Rectangle {
                                                    property var addon: modelData
                                                    Layout.fillWidth: true
                                                    radius: Theme.radiusSmall
                                                    color: Theme.backgroundCard
                                                    border.color: Theme.border
                                                    implicitHeight: addonContent.implicitHeight + Theme.spacingSmall * 2
                                                    height: implicitHeight

                                                    ColumnLayout {
                                                        id: addonContent
                                                        anchors.fill: parent
                                                        anchors.margins: Theme.spacingSmall
                                                        spacing: Theme.spacingSmall

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: Theme.spacingSmall

                                                            ColumnLayout {
                                                                Layout.fillWidth: true
                                                                spacing: 2

                                                                Label {
                                                                    text: String(addon.title || addon.extensionId || "")
                                                                    color: Theme.textPrimary
                                                                    font.pixelSize: 12
                                                                    font.family: Theme.fontDisplay
                                                                    Layout.fillWidth: true
                                                                    elide: Text.ElideRight
                                                                }

                                                                Label {
                                                                    text: String(addon.description || "")
                                                                    color: Theme.textSecondary
                                                                    font.pixelSize: 11
                                                                    font.family: Theme.fontBody
                                                                    wrapMode: Text.WordWrap
                                                                    Layout.fillWidth: true
                                                                }
                                                            }

                                                            Rectangle {
                                                                radius: Theme.radiusSmall
                                                                color: Theme.backgroundCardRaised
                                                                border.color: Theme.border
                                                                implicitHeight: 22
                                                                implicitWidth: addonLabel.implicitWidth + 12

                                                                Label {
                                                                    id: addonLabel
                                                                    anchors.centerIn: parent
                                                                    text: String(addon.label || "Available")
                                                                    color: Theme.textSecondary
                                                                    font.pixelSize: 10
                                                                    font.family: Theme.fontBody
                                                                }
                                                            }

                                                            Button {
                                                                text: String(addon.actionLabel || "Activate")
                                                                enabled: apiClient.authToken !== ""
                                                                onClicked: root.activateOptionalAddon(addon)
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
                                                            visible: root.activeOptionalAddonId === String(addon.extensionId || "") &&
                                                                     (addon.secretKeys || []).length > 0

                                                            Repeater {
                                                                model: addon.secretKeys || []
                                                                delegate: TextField {
                                                                    property int fieldIndex: index
                                                                    property var requiredFields: addon.requiredFields || []
                                                                    property string secretKey: String(modelData || "")
                                                                    Layout.fillWidth: true
                                                                    placeholderText: root.addonFieldLabel(
                                                                        fieldIndex < requiredFields.length
                                                                        ? requiredFields[fieldIndex]
                                                                        : secretKey
                                                                    )
                                                                    echoMode: placeholderText.toLowerCase().indexOf("password") >= 0
                                                                              ? TextInput.Password
                                                                              : TextInput.Normal
                                                                    text: root.optionalAddonValue(secretKey)
                                                                    onTextChanged: root.setOptionalAddonValue(secretKey, text)
                                                                    color: Theme.textPrimary
                                                                    font.pixelSize: 12
                                                                    font.family: Theme.fontBody
                                                                    placeholderTextColor: Theme.textMuted
                                                                    background: Rectangle {
                                                                        radius: Theme.radiusSmall
                                                                        color: Theme.backgroundCardRaised
                                                                        border.color: Theme.border
                                                                    }
                                                                }
                                                            }

                                                            RowLayout {
                                                                Layout.fillWidth: true
                                                                spacing: Theme.spacingSmall

                                                                Button {
                                                                    text: "Save and activate"
                                                                    enabled: apiClient.authToken !== ""
                                                                    onClicked: root.submitOptionalAddonPrompt(addon)
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

                                                                Button {
                                                                    text: "Cancel"
                                                                    onClicked: root.clearOptionalAddonPrompt()
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
                                                    }
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingSmall

                                            Button {
                                                property var actionSpec: root.primaryActionFor(modelData)
                                                text: root.scopedFixButtonLabel(modelData, actionSpec)
                                                visible: text !== ""
                                                enabled: !root.isScopedFixRunning(modelData)
                                                onClicked: {
                                                    if (actionSpec.action === "enable") {
                                                        apiClient.enableExtension(root.extensionIdFor(modelData.entry))
                                                    } else if (root.canCreateDefaultInstance(modelData, actionSpec)) {
                                                        root.createDefaultInstance(modelData)
                                                    } else if (root.canRunScopedFix(modelData, actionSpec)) {
                                                        root.runScopedFix(modelData)
                                                    } else {
                                                        root.openControl(root.extensionIdFor(modelData.entry))
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

                                        Rectangle {
                                            Layout.fillWidth: true
                                            visible: root.autoUpdateVisible(modelData)
                                            radius: Theme.radiusSmall
                                            color: Theme.backgroundCard
                                            border.color: Qt.rgba(
                                                root.statusAccent(modelData.autoUpdate).r,
                                                root.statusAccent(modelData.autoUpdate).g,
                                                root.statusAccent(modelData.autoUpdate).b,
                                                0.28
                                            )
                                            implicitHeight: readyAutoUpdateContent.implicitHeight + Theme.spacingSmall * 2

                                            ColumnLayout {
                                                id: readyAutoUpdateContent
                                                anchors.fill: parent
                                                anchors.margins: Theme.spacingSmall
                                                spacing: Theme.spacingSmall

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Theme.spacingSmall

                                                    Label {
                                                        Layout.fillWidth: true
                                                        text: "Auto-update"
                                                        color: Theme.textPrimary
                                                        font.pixelSize: 11
                                                        font.family: Theme.fontDisplay
                                                    }

                                                    Rectangle {
                                                        radius: Theme.radiusSmall
                                                        color: root.statusChipFill(modelData.autoUpdate)
                                                        border.color: root.statusAccent(modelData.autoUpdate)
                                                        implicitHeight: 22
                                                        implicitWidth: readyAutoUpdateLabel.implicitWidth + 12

                                                        Label {
                                                            id: readyAutoUpdateLabel
                                                            anchors.centerIn: parent
                                                            text: String((modelData.autoUpdate || {}).label || "")
                                                            color: root.statusAccent(modelData.autoUpdate)
                                                            font.pixelSize: 10
                                                            font.family: Theme.fontBody
                                                        }
                                                    }
                                                }

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: String((modelData.autoUpdate || {}).description || "")
                                                    visible: text !== ""
                                                    color: Theme.textSecondary
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontBody
                                                    wrapMode: Text.WordWrap
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingSmall
                                            visible: modelData.optionalAddons && modelData.optionalAddons.length > 0

                                            Label {
                                                text: "Optional add-ons"
                                                color: Theme.textPrimary
                                                font.pixelSize: 12
                                                font.family: Theme.fontDisplay
                                            }

                                            Repeater {
                                                model: modelData.optionalAddons || []
                                                delegate: Rectangle {
                                                    property var addon: modelData
                                                    Layout.fillWidth: true
                                                    radius: Theme.radiusSmall
                                                    color: Theme.backgroundCard
                                                    border.color: Theme.border
                                                    implicitHeight: readyAddonContent.implicitHeight + Theme.spacingSmall * 2
                                                    height: implicitHeight

                                                    ColumnLayout {
                                                        id: readyAddonContent
                                                        anchors.fill: parent
                                                        anchors.margins: Theme.spacingSmall
                                                        spacing: Theme.spacingSmall

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: Theme.spacingSmall

                                                            ColumnLayout {
                                                                Layout.fillWidth: true
                                                                spacing: 2

                                                                Label {
                                                                    text: String(addon.title || addon.extensionId || "")
                                                                    color: Theme.textPrimary
                                                                    font.pixelSize: 12
                                                                    font.family: Theme.fontDisplay
                                                                    Layout.fillWidth: true
                                                                    elide: Text.ElideRight
                                                                }

                                                                Label {
                                                                    text: String(addon.description || "")
                                                                    color: Theme.textSecondary
                                                                    font.pixelSize: 11
                                                                    font.family: Theme.fontBody
                                                                    wrapMode: Text.WordWrap
                                                                    Layout.fillWidth: true
                                                                }
                                                            }

                                                            Rectangle {
                                                                radius: Theme.radiusSmall
                                                                color: Theme.backgroundCardRaised
                                                                border.color: Theme.border
                                                                implicitHeight: 22
                                                                implicitWidth: readyAddonLabel.implicitWidth + 12

                                                                Label {
                                                                    id: readyAddonLabel
                                                                    anchors.centerIn: parent
                                                                    text: String(addon.label || "Available")
                                                                    color: Theme.textSecondary
                                                                    font.pixelSize: 10
                                                                    font.family: Theme.fontBody
                                                                }
                                                            }

                                                            Button {
                                                                text: String(addon.actionLabel || "Activate")
                                                                enabled: apiClient.authToken !== ""
                                                                onClicked: root.activateOptionalAddon(addon)
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
                                                            visible: root.activeOptionalAddonId === String(addon.extensionId || "") &&
                                                                     (addon.secretKeys || []).length > 0

                                                            Repeater {
                                                                model: addon.secretKeys || []
                                                                delegate: TextField {
                                                                    property int fieldIndex: index
                                                                    property var requiredFields: addon.requiredFields || []
                                                                    property string secretKey: String(modelData || "")
                                                                    Layout.fillWidth: true
                                                                    placeholderText: root.addonFieldLabel(
                                                                        fieldIndex < requiredFields.length
                                                                        ? requiredFields[fieldIndex]
                                                                        : secretKey
                                                                    )
                                                                    echoMode: placeholderText.toLowerCase().indexOf("password") >= 0
                                                                              ? TextInput.Password
                                                                              : TextInput.Normal
                                                                    text: root.optionalAddonValue(secretKey)
                                                                    onTextChanged: root.setOptionalAddonValue(secretKey, text)
                                                                    color: Theme.textPrimary
                                                                    font.pixelSize: 12
                                                                    font.family: Theme.fontBody
                                                                    placeholderTextColor: Theme.textMuted
                                                                    background: Rectangle {
                                                                        radius: Theme.radiusSmall
                                                                        color: Theme.backgroundCardRaised
                                                                        border.color: Theme.border
                                                                    }
                                                                }
                                                            }

                                                            RowLayout {
                                                                Layout.fillWidth: true
                                                                spacing: Theme.spacingSmall

                                                                Button {
                                                                    text: "Save and activate"
                                                                    enabled: apiClient.authToken !== ""
                                                                    onClicked: root.submitOptionalAddonPrompt(addon)
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

                                                                Button {
                                                                    text: "Cancel"
                                                                    onClicked: root.clearOptionalAddonPrompt()
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
                                                    }
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

                                        Button {
                                            property var actionSpec: root.primaryActionFor(modelData)
                                            text: actionSpec.label
                                            onClicked: {
                                                if (actionSpec.action === "enable") {
                                                    apiClient.enableExtension(root.extensionIdFor(modelData.entry))
                                                } else if (root.canCreateDefaultInstance(modelData, actionSpec)) {
                                                    root.createDefaultInstance(modelData)
                                                } else if (root.canRunScopedFix(modelData, actionSpec)) {
                                                    root.runScopedFix(modelData)
                                                } else {
                                                    root.openControl(root.extensionIdFor(modelData.entry))
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
                id: marketplaceSection
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
                                text: root.marketplaceFilterActive()
                                      ? (root.marketplaceFilterLabel !== ""
                                         ? root.marketplaceFilterLabel
                                         : "Filtered marketplace results.")
                                      : "Browse new extensions and one-click stacks."
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

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall
                            visible: root.marketplaceFilterActive()

                            Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                                implicitHeight: 24
                                implicitWidth: filterLabel.implicitWidth + 14

                                Label {
                                    id: filterLabel
                                    anchors.centerIn: parent
                                    text: root.marketplaceFilterLabel !== ""
                                          ? root.marketplaceFilterLabel
                                          : "Filtered marketplace"
                                    color: Theme.textSecondary
                                    font.pixelSize: 10
                                    font.family: Theme.fontBody
                                }
                            }

                            Button {
                                text: "Clear filter"
                                onClicked: root.clearMarketplaceFilter()
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
                            text: marketplaceCards().length === 0
                                  ? (root.marketplaceFilterActive()
                                     ? "No extensions match this filter right now."
                                     : "No new extensions available right now.")
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
                                                     (String(modelData.download_url || modelData.downloadUrl || "") !== "" ||
                                                      String(modelData.package_path || modelData.packagePath || "") !== "")
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
