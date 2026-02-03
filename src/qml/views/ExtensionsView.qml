import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "extensionsView"
    property StackView stackView: null
    property string rotatedSecretValue: ""
    property string rotatedSecretId: ""
    property bool rotatedSecretCopied: false
    property var slotConflictDecisions: ({})
    property var secretDrafts: ({})
    property int planRefreshPendingCount: 0
    property var pendingSecretCreates: ({})
    property bool showStepLegend: false
    property bool pendingRunStatusScroll: false
    property string desiredFilter: "all"

    function isInstalled(extensionId) {
        for (var i = 0; i < apiClient.extensionsInstalled.length; ++i) {
            var item = apiClient.extensionsInstalled[i]
            if (item.extension_id === extensionId) {
                return true
            }
        }
        return false
    }

    function instancesFor(extensionId) {
        var results = []
        for (var i = 0; i < apiClient.extensionsInstances.length; ++i) {
            var item = apiClient.extensionsInstances[i]
            if (item.extension_id === extensionId) {
                results.push(item)
            }
        }
        return results
    }

    function secretsFor(instanceId) {
        var results = []
        for (var i = 0; i < apiClient.extensionsSecrets.length; ++i) {
            var item = apiClient.extensionsSecrets[i]
            if (item.scope === "instance" && item.scope_id === instanceId) {
                results.push(item)
            }
        }
        return results
    }

    function desiredBlueprintCount(appliedFilter) {
        var total = 0
        for (var i = 0; i < apiClient.extensionsDesiredBlueprints.length; ++i) {
            var item = apiClient.extensionsDesiredBlueprints[i]
            if (appliedFilter === undefined || item.applied === appliedFilter) {
                total += 1
            }
        }
        return total
    }

    function filteredDesiredBlueprints() {
        var results = []
        for (var i = 0; i < apiClient.extensionsDesiredBlueprints.length; ++i) {
            var item = apiClient.extensionsDesiredBlueprints[i]
            if (desiredFilter === "applied" && !item.applied) {
                continue
            }
            if (desiredFilter === "pending" && item.applied) {
                continue
            }
            results.push(item)
        }
        return results
    }

    function desiredFilterLabel() {
        if (desiredFilter === "applied") {
            return "No applied desired blueprints."
        }
        if (desiredFilter === "pending") {
            return "No pending desired blueprints."
        }
        return "No desired blueprints."
    }

    function desiredDecisionCount(item) {
        if (!item || item.decisions_json === undefined || item.decisions_json === null) {
            return 0
        }
        var decisions = item.decisions_json.slotConflicts
        if (decisions === undefined || decisions === null) {
            return 0
        }
        return decisions.length || 0
    }

    function desiredStatusColor(applied) {
        return applied ? "#5fbf5a" : Theme.accent
    }

    function reconcileHasRun() {
        return apiClient.extensionsReconcileRun &&
               apiClient.extensionsReconcileRun.run_id !== undefined &&
               apiClient.extensionsReconcileRun.run_id !== ""
    }

    function reconcileStatusValue() {
        if (!apiClient.extensionsReconcileRun || apiClient.extensionsReconcileRun.status === undefined) {
            return ""
        }
        return String(apiClient.extensionsReconcileRun.status)
    }

    function reconcileIsActive() {
        var value = reconcileStatusValue()
        value = value ? String(value).toLowerCase() : ""
        return value === "running" || value === "pending"
    }

    function reconcileErrorValue() {
        if (!apiClient.extensionsReconcileRun || apiClient.extensionsReconcileRun.error === undefined) {
            return ""
        }
        return apiClient.extensionsReconcileRun.error || ""
    }

    function reconcileTimeLine() {
        if (!reconcileHasRun()) {
            return ""
        }
        var parts = []
        if (apiClient.extensionsReconcileRun.created_at) {
            parts.push("Created: " + apiClient.extensionsReconcileRun.created_at)
        }
        if (apiClient.extensionsReconcileRun.finished_at) {
            parts.push("Finished: " + apiClient.extensionsReconcileRun.finished_at)
        }
        return parts.join(" • ")
    }

    function openLatestReconcileRun() {
        if (!reconcileHasRun()) {
            return
        }
        var runId = apiClient.extensionsReconcileRun.run_id
        if (runId === undefined || runId === null || String(runId) === "") {
            return
        }
        apiClient.fetchExtensionRunDetail(String(runId))
        apiClient.fetchExtensionRuns()
        requestRunStatusScroll()
    }

    function requestRunStatusScroll() {
        pendingRunStatusScroll = true
        Qt.callLater(scrollToRunStatus)
    }

    function scrollToRunStatus() {
        if (!pendingRunStatusScroll) {
            return
        }
        if (!runStatusSection || !runStatusSection.visible) {
            return
        }
        if (!contentScroller || !contentScroller.contentItem) {
            return
        }
        var point = runStatusSection.mapToItem(contentScroller.contentItem, 0, 0)
        var targetY = Math.max(0, point.y - Theme.spacingLarge)
        var maxY = Math.max(0, contentScroller.contentHeight - contentScroller.height)
        contentScroller.contentY = Math.min(targetY, maxY)
        pendingRunStatusScroll = false
    }

    function secretDraftKey(scope, scopeId, key) {
        return scope + ":" + (scopeId || "") + ":" + key
    }

    function secretDraftValue(scope, scopeId, key) {
        var lookup = secretDraftKey(scope, scopeId, key)
        if (secretDrafts[lookup] !== undefined) {
            return secretDrafts[lookup]
        }
        return ""
    }

    function setSecretDraftValue(scope, scopeId, key, value) {
        var lookup = secretDraftKey(scope, scopeId, key)
        var updated = {}
        for (var entry in secretDrafts) {
            updated[entry] = secretDrafts[entry]
        }
        updated[lookup] = value
        secretDrafts = updated
    }

    function queueSecretCreate(info, conflict) {
        if (!info || info.scope === "" || info.key === "") {
            return
        }
        var lookup = secretDraftKey(info.scope, info.scopeId, info.key)
        var updated = {}
        for (var entry in pendingSecretCreates) {
            updated[entry] = pendingSecretCreates[entry]
        }
        if (updated[lookup] === undefined) {
            updated[lookup] = {
                scope: info.scope,
                scopeId: info.scopeId,
                key: info.key,
                label: missingSecretLabel(info, conflict)
            }
        }
        pendingSecretCreates = updated
    }

    function finalizeSecretCreates() {
        var keys = Object.keys(pendingSecretCreates)
        if (keys.length === 0) {
            return
        }
        var successes = []
        var failures = []
        for (var i = 0; i < keys.length; ++i) {
            var entry = pendingSecretCreates[keys[i]]
            if (!entry) {
                continue
            }
            if (secretExists(entry.scope, entry.scopeId, entry.key)) {
                successes.push(entry.label)
            } else {
                failures.push(entry.label)
            }
        }
        var status = ""
        var total = successes.length + failures.length
        if (total > 0) {
            status = "Created " + successes.length + " secret" + (successes.length === 1 ? "" : "s") + "."
        }
        if (failures.length > 0) {
            if (status !== "") {
                status += " "
            }
            status += "Failed: " + failures.join(", ")
        }
        pendingSecretCreates = ({})
        if (status !== "") {
            secretToast.show(status)
        } else {
            secretToast.clear()
        }
    }

    function finishSecretCreateBatch() {
        finalizeSecretCreates()
        refreshCurrentPlan()
    }

    function parseMissingSecretToken(token, conflict) {
        var info = {
            scope: "",
            scopeId: "",
            key: "",
            token: token
        }
        if (token === undefined || token === null) {
            return info
        }
        var raw = String(token)
        info.key = raw
        var parts = raw.split(":")
        if (parts.length >= 2) {
            info.scope = parts[0]
            if (info.scope === "global") {
                info.key = parts.slice(1).join(":")
            } else if (info.scope === "instance" || info.scope === "provider") {
                if (parts.length >= 3) {
                    info.scopeId = parts[1]
                    info.key = parts.slice(2).join(":")
                } else {
                    info.key = parts[1]
                }
            } else {
                info.key = parts.slice(1).join(":")
            }
        }
        if (info.scope === "instance" && info.scopeId === "" && conflict && conflict.instance_id) {
            info.scopeId = conflict.instance_id
        }
        return info
    }

    function pendingMissingSecretInfos(conflict) {
        var items = []
        if (!conflict || !conflict.missing) {
            return items
        }
        var seen = {}
        for (var i = 0; i < conflict.missing.length; ++i) {
            var info = parseMissingSecretToken(conflict.missing[i], conflict)
            if (info.scope === "" || info.key === "") {
                continue
            }
            var lookup = secretDraftKey(info.scope, info.scopeId, info.key)
            if (seen[lookup]) {
                continue
            }
            seen[lookup] = true
            if (secretExists(info.scope, info.scopeId, info.key)) {
                continue
            }
            items.push(info)
        }
        return items
    }

    function canCreateAllMissingSecrets(conflict) {
        var items = pendingMissingSecretInfos(conflict)
        if (items.length === 0) {
            return false
        }
        for (var i = 0; i < items.length; ++i) {
            var info = items[i]
            if (secretDraftValue(info.scope, info.scopeId, info.key).trim() === "") {
                return false
            }
        }
        return true
    }

    function createAllMissingSecrets(conflict) {
        var items = pendingMissingSecretInfos(conflict)
        if (items.length === 0) {
            actionToast.show("All required secrets already exist.")
            return
        }
        var missingInputs = []
        for (var i = 0; i < items.length; ++i) {
            var info = items[i]
            if (secretDraftValue(info.scope, info.scopeId, info.key).trim() === "") {
                missingInputs.push(missingSecretLabel(info, conflict))
            }
        }
        if (missingInputs.length > 0) {
            actionToast.show("Provide values for: " + missingInputs.join(", "))
            return
        }
        secretToast.clear()
        planRefreshPendingCount += items.length
        for (var j = 0; j < items.length; ++j) {
            var entry = items[j]
            var value = secretDraftValue(entry.scope, entry.scopeId, entry.key)
            queueSecretCreate(entry, conflict)
            apiClient.createSecret(entry.scope, entry.scopeId || "", entry.key, value)
            setSecretDraftValue(entry.scope, entry.scopeId, entry.key, "")
        }
    }

    function missingSecretLabel(info, conflict) {
        if (info.scope === "global") {
            return "global / " + info.key
        }
        if (info.scope === "instance") {
            var name = conflict && conflict.instance_name ? conflict.instance_name : info.scopeId
            if (name === "" || name === undefined) {
                name = "instance"
            }
            return name + " / " + info.key
        }
        if (info.scope === "provider") {
            var providerId = info.scopeId !== "" ? info.scopeId : "provider"
            return "provider " + providerId + " / " + info.key
        }
        return info.token || info.key
    }

    function secretExists(scope, scopeId, key) {
        if (scope === "" || key === "") {
            return false
        }
        for (var i = 0; i < apiClient.extensionsSecrets.length; ++i) {
            var item = apiClient.extensionsSecrets[i]
            if (!item || item.scope !== scope) {
                continue
            }
            if (scopeId !== "" && scopeId !== undefined && scopeId !== null) {
                if (item.scope_id !== scopeId) {
                    continue
                }
            }
            if (item.key === key) {
                return true
            }
        }
        return false
    }

    function missingSecretsResolved(conflict) {
        if (!conflict || !conflict.missing) {
            return true
        }
        for (var i = 0; i < conflict.missing.length; ++i) {
            var info = parseMissingSecretToken(conflict.missing[i], conflict)
            if (info.scope === "" || info.key === "") {
                return false
            }
            if (!secretExists(info.scope, info.scopeId, info.key)) {
                return false
            }
        }
        return true
    }

    function createMissingSecret(info, conflict) {
        if (!info || info.scope === "" || info.key === "") {
            actionToast.show("Missing secret reference is invalid.")
            return
        }
        var value = secretDraftValue(info.scope, info.scopeId, info.key)
        if (value.trim() === "") {
            actionToast.show("Secret value is required.")
            return
        }
        secretToast.clear()
        queueSecretCreate(info, conflict)
        planRefreshPendingCount += 1
        apiClient.createSecret(info.scope, info.scopeId || "", info.key, value)
        setSecretDraftValue(info.scope, info.scopeId, info.key, "")
    }

    function currentPlanBlueprintId() {
        if (apiClient.extensionsPlan && apiClient.extensionsPlan.blueprint_id) {
            return apiClient.extensionsPlan.blueprint_id
        }
        if (apiClient.extensionsPlan && apiClient.extensionsPlan.blueprintId) {
            return apiClient.extensionsPlan.blueprintId
        }
        return ""
    }

    function currentPlanParamsJson() {
        if (!apiClient.extensionsPlan) {
            return ""
        }
        if (apiClient.extensionsPlan.params === undefined || apiClient.extensionsPlan.params === null) {
            return ""
        }
        try {
            return JSON.stringify(apiClient.extensionsPlan.params)
        } catch (err) {
            return ""
        }
    }

    function refreshCurrentPlan() {
        var blueprintId = currentPlanBlueprintId()
        if (blueprintId === "") {
            return
        }
        apiClient.applyBlueprintPlan(blueprintId, currentPlanParamsJson())
    }

    function runStatusValue() {
        return apiClient.extensionsRun && apiClient.extensionsRun.status ? apiClient.extensionsRun.status : ""
    }

    function runPhaseValue() {
        return apiClient.extensionsRun && apiClient.extensionsRun.phase ? apiClient.extensionsRun.phase : ""
    }

    function runErrorValue() {
        return apiClient.extensionsRun && apiClient.extensionsRun.error ? apiClient.extensionsRun.error : ""
    }

    function runIsActive() {
        var status = runStatusValue()
        return status === "running" || status === "pending"
    }

    function runStepCounts() {
        var counts = { "pending": 0, "running": 0, "completed": 0, "failed": 0, "skipped": 0 }
        var steps = apiClient.extensionsRunSteps
        for (var i = 0; i < steps.length; ++i) {
            var status = steps[i].status || ""
            if (counts[status] !== undefined) {
                counts[status] += 1
            }
        }
        return counts
    }

    function runProgressLabel() {
        var counts = runStepCounts()
        var total = counts.pending + counts.running + counts.completed + counts.failed + counts.skipped
        if (total === 0) {
            return "No steps yet."
        }
        return "Steps: " + counts.completed + " completed, " + counts.running + " running, " +
               counts.pending + " pending, " + counts.failed + " failed"
    }

    function runStatusColor(status) {
        var value = status ? String(status).toLowerCase() : ""
        if (value === "completed") {
            return "#36C36C"
        }
        if (value === "failed") {
            return "#D95C5C"
        }
        if (value === "running") {
            return Theme.accent
        }
        if (value === "pending") {
            return "#999999"
        }
        if (value === "canceled") {
            return "#6B6F76"
        }
        return "#5A606B"
    }

    function stepStatusColor(status) {
        var value = status ? String(status).toLowerCase() : ""
        if (value === "completed") {
            return "#36C36C"
        }
        if (value === "failed") {
            return "#D95C5C"
        }
        if (value === "running") {
            return Theme.accent
        }
        if (value === "pending") {
            return "#999999"
        }
        if (value === "skipped") {
            return "#6B6F76"
        }
        return "#5A606B"
    }

    function planConflictId(conflict) {
        if (conflict.conflict_id) {
            return conflict.conflict_id
        }
        if (conflict.capability && conflict.slot) {
            return conflict.capability + "/" + conflict.slot
        }
        return ""
    }

    function conflictDecision(conflict) {
        var conflictId = planConflictId(conflict)
        if (slotConflictDecisions[conflictId] !== undefined) {
            return slotConflictDecisions[conflictId]
        }
        if (conflict.decision) {
            return conflict.decision
        }
        return ""
    }

    function setConflictDecision(conflict, action) {
        var conflictId = planConflictId(conflict)
        if (conflictId === "") {
            return
        }
        var updated = {}
        for (var key in slotConflictDecisions) {
            updated[key] = slotConflictDecisions[key]
        }
        updated[conflictId] = action
        slotConflictDecisions = updated
    }

    function decisionIndex(action) {
        if (action === "keep_existing") {
            return 0
        }
        if (action === "replace") {
            return 1
        }
        if (action === "abort") {
            return 2
        }
        return -1
    }

    function buildPlanDecisions() {
        var decisions = []
        var conflicts = apiClient.extensionsPlanConflicts
        for (var i = 0; i < conflicts.length; ++i) {
            var conflict = conflicts[i]
            if (conflict.code !== "slot_conflict") {
                continue
            }
            var action = conflictDecision(conflict)
            if (action === "") {
                continue
            }
            decisions.push({
                conflictId: planConflictId(conflict),
                action: action
            })
        }
        return decisions
    }

    function canConfirmPlan() {
        if (apiClient.extensionsPlanId === "") {
            return false
        }
        var conflicts = apiClient.extensionsPlanConflicts
        for (var i = 0; i < conflicts.length; ++i) {
            var conflict = conflicts[i]
            if (conflict.code === "missing_required_secrets") {
                if (!missingSecretsResolved(conflict)) {
                    return false
                }
                continue
            }
            if (conflict.code === "slot_conflict") {
                if (conflict.policy === "auto_replace") {
                    continue
                }
                if (conflict.policy === "deny") {
                    return false
                }
                var action = conflictDecision(conflict)
                if (action === "" || action === "abort") {
                    return false
                }
                continue
            }
            return false
        }
        return true
    }

    Component.onCompleted: {
        if (apiClient.authToken !== "") {
            apiClient.fetchExtensionsCatalog()
            apiClient.fetchExtensionInstances()
            apiClient.fetchInstanceSecrets()
            apiClient.fetchDesiredBlueprints()
            apiClient.fetchLatestReconcileRun()
            apiClient.fetchExtensionRuns()
        }
    }

    Connections {
        target: apiClient
        function onAuthTokenChanged() {
            if (apiClient.authToken !== "") {
                apiClient.fetchExtensionsCatalog()
                apiClient.fetchExtensionInstances()
                apiClient.fetchInstanceSecrets()
                apiClient.fetchDesiredBlueprints()
                apiClient.fetchLatestReconcileRun()
                apiClient.fetchExtensionRuns()
            }
        }
        function onRequestFailed(endpoint, error) {
            if (endpoint.indexOf("/api/v1/extensions/") === 0) {
                actionToast.show(error)
            }
            if (endpoint === "/api/v1/extensions/secrets" && planRefreshPendingCount > 0) {
                planRefreshPendingCount = Math.max(0, planRefreshPendingCount - 1)
                if (planRefreshPendingCount === 0) {
                    finishSecretCreateBatch()
                }
            }
        }
        function onExtensionsCatalogChanged() {
            actionToast.clear()
        }
        function onExtensionsInstancesChanged() {
            actionToast.clear()
        }
        function onExtensionsSecretsChanged() {
            actionToast.clear()
            if (planRefreshPendingCount > 0) {
                planRefreshPendingCount = Math.max(0, planRefreshPendingCount - 1)
                if (planRefreshPendingCount === 0) {
                    finishSecretCreateBatch()
                }
            }
        }
        function onExtensionsPlanChanged() {
            slotConflictDecisions = ({})
            secretDrafts = ({})
            planRefreshPendingCount = 0
            pendingSecretCreates = ({})
        }
        function onExtensionsRunChanged() {
            if (root.pendingRunStatusScroll) {
                root.scrollToRunStatus()
            }
        }
        function onSecretRotated(secretId, value) {
            rotatedSecretId = secretId
            rotatedSecretValue = value
            rotatedSecretCopied = false
            rotatedSecretDialog.open()
        }
        function onDesiredBlueprintsCleared(deleted) {
            if (deleted > 0) {
                desiredToast.show("Cleared " + deleted + " desired blueprint" + (deleted === 1 ? "" : "s") + ".")
            } else {
                desiredToast.show("No desired blueprints cleared.")
            }
        }
    }

    Timer {
        id: runPollTimer
        interval: 2000
        repeat: true
        running: apiClient.extensionsRunId !== "" && root.runIsActive()
        onTriggered: apiClient.fetchExtensionRunDetail(apiClient.extensionsRunId)
    }

    Timer {
        id: reconcilePollTimer
        interval: 2500
        repeat: true
        running: apiClient.authToken !== "" && root.reconcileIsActive()
        onTriggered: apiClient.fetchLatestReconcileRun()
    }

    Timer {
        id: stepLegendTimer
        interval: 5000
        repeat: false
        onTriggered: root.showStepLegend = false
    }

    Flickable {
        id: contentScroller
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
                text: "Extensions"
                color: Theme.textPrimary
                font.pixelSize: 24
                font.family: Theme.fontDisplay
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: statusContent.implicitHeight + Theme.spacingLarge * 2
                height: implicitHeight

                ColumnLayout {
                    id: statusContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: "Registry status"
                            color: Theme.textPrimary
                            font.pixelSize: 16
                            font.family: Theme.fontDisplay
                            Layout.fillWidth: true
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
                    }

                    Label {
                        text: apiClient.extensionsLastRefreshedAt !== ""
                              ? "Last refresh attempt: " + apiClient.extensionsLastRefreshedAt
                              : "Last refresh attempt: never"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    Label {
                        text: apiClient.extensionsLastRefreshSuccessAt !== ""
                              ? "Last success: " + apiClient.extensionsLastRefreshSuccessAt
                              : "Last success: never"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    Label {
                        text: apiClient.extensionsLastRefreshError !== ""
                              ? "Last error: " + apiClient.extensionsLastRefreshError
                              : "Last error: none"
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    Label {
                        text: apiClient.authToken === "" ? "Sign in to load extensions catalog." : ""
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        visible: apiClient.authToken === ""
                    }

                    InlineToast {
                        id: actionToast
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: planContent.implicitHeight + Theme.spacingLarge * 2
                height: implicitHeight

                ColumnLayout {
                    id: planContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: "Blueprint plan"
                            color: Theme.textPrimary
                            font.pixelSize: 16
                            font.family: Theme.fontDisplay
                            Layout.fillWidth: true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        TextField {
                            id: blueprintIdField
                            Layout.preferredWidth: 220
                            placeholderText: "blueprint id"
                            font.pixelSize: 11
                        }

                        TextArea {
                            id: blueprintParamsField
                            Layout.fillWidth: true
                            placeholderText: "params JSON (optional)"
                            wrapMode: TextArea.Wrap
                            font.pixelSize: 11
                            background: Rectangle {
                                color: Theme.backgroundCard
                                border.color: Theme.border
                                radius: Theme.radiusSmall
                            }
                        }

                        Button {
                            text: "Preview plan"
                            enabled: apiClient.authToken !== ""
                            onClicked: apiClient.applyBlueprintPlan(
                                blueprintIdField.text,
                                blueprintParamsField.text)
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

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: apiClient.extensionsPlanId !== ""
                                  ? "Plan ID: " + apiClient.extensionsPlanId
                                  : "No plan loaded."
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "Confirm"
                            enabled: canConfirmPlan()
                            onClicked: apiClient.confirmExtensionsPlan(
                                apiClient.extensionsPlanId,
                                buildPlanDecisions())
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
                            text: "Cancel"
                            enabled: apiClient.extensionsPlanId !== ""
                            onClicked: apiClient.cancelExtensionsPlan(apiClient.extensionsPlanId)
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
                        text: apiClient.extensionsPlanId !== ""
                              ? "Conflicts: " + apiClient.extensionsPlanConflicts.length
                              : ""
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        visible: apiClient.extensionsPlanId !== ""
                    }

                    InlineToast {
                        id: secretToast
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    ColumnLayout {
                        spacing: Theme.spacingSmall
                        visible: apiClient.extensionsPlanId !== ""

                        Label {
                            text: apiClient.extensionsPlanConflicts.length === 0
                                  ? "No conflicts."
                                  : ""
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: apiClient.extensionsPlanConflicts.length === 0
                        }

                        Repeater {
                            model: apiClient.extensionsPlanConflicts
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                                implicitHeight: conflictContent.implicitHeight + Theme.spacingSmall * 2
                                height: implicitHeight

                                ColumnLayout {
                                    id: conflictContent
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Theme.spacingSmall
                                    spacing: Theme.spacingSmall

                                    Label {
                                        text: modelData.code === "slot_conflict"
                                              ? "Slot conflict: " + modelData.capability + "/" + modelData.slot
                                              : "Conflict: " + modelData.code
                                        color: Theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: Theme.fontBody
                                    }

                                    Label {
                                        text: modelData.detail ? modelData.detail : ""
                                        color: Theme.textMuted
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                        visible: modelData.detail !== undefined && modelData.detail !== ""
                                    }

                                    ColumnLayout {
                                        spacing: Theme.spacingSmall
                                        visible: modelData.code === "slot_conflict"

                                        Label {
                                            text: "Policy: " + modelData.policy
                                            color: Theme.textSecondary
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                        }

                                        Label {
                                            text: "Existing providers:"
                                            color: Theme.textSecondary
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                            visible: modelData.existing && modelData.existing.length > 0
                                        }

                                        Repeater {
                                            model: modelData.existing || []
                                            delegate: Label {
                                                text: modelData.extension_id + " / " +
                                                      (modelData.instance_name || modelData.instance_id)
                                                color: Theme.textMuted
                                                font.pixelSize: 11
                                                font.family: Theme.fontBody
                                            }
                                        }

                                        Label {
                                            text: "Planned provider:"
                                            color: Theme.textSecondary
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                            visible: modelData.planned && modelData.planned.length > 0
                                        }

                                        Repeater {
                                            model: modelData.planned || []
                                            delegate: Label {
                                                text: modelData.extension_id + " / " +
                                                      (modelData.instance_name || modelData.instance_id)
                                                color: Theme.textMuted
                                                font.pixelSize: 11
                                                font.family: Theme.fontBody
                                            }
                                        }

                                        Label {
                                            text: modelData.policy === "auto_replace"
                                                  ? "Auto replace will remove existing providers on confirm."
                                                  : modelData.policy === "deny"
                                                    ? "Policy deny blocks replacement."
                                                    : "Choose a resolution before confirming."
                                            color: Theme.textMuted
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                        }

                                        ComboBox {
                                            visible: modelData.policy === "prompt"
                                            model: [
                                                { "label": "Keep existing", "value": "keep_existing" },
                                                { "label": "Replace", "value": "replace" },
                                                { "label": "Abort", "value": "abort" }
                                            ]
                                            textRole: "label"
                                            currentIndex: root.decisionIndex(root.conflictDecision(modelData))
                                            displayText: {
                                                var value = root.conflictDecision(modelData)
                                                if (value === "keep_existing") return "Keep existing"
                                                if (value === "replace") return "Replace"
                                                if (value === "abort") return "Abort"
                                                return "Select resolution..."
                                            }
                                            onActivated: {
                                                var value = model[index].value
                                                root.setConflictDecision(modelData, value)
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        id: missingSecretsBlock
                                        property var conflict: modelData
                                        spacing: Theme.spacingSmall
                                        visible: modelData.code === "missing_required_secrets"

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingSmall

                                            Label {
                                                text: "Missing secrets"
                                                color: Theme.textSecondary
                                                font.pixelSize: 12
                                                font.family: Theme.fontBody
                                                Layout.fillWidth: true
                                            }

                                            Button {
                                                text: "Create all"
                                                enabled: apiClient.authToken !== ""
                                                         && root.canCreateAllMissingSecrets(missingSecretsBlock.conflict)
                                                onClicked: root.createAllMissingSecrets(missingSecretsBlock.conflict)
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
                                            text: (missingSecretsBlock.conflict.instance_name || missingSecretsBlock.conflict.instance_id)
                                                  ? ("Instance: " + (missingSecretsBlock.conflict.instance_name || missingSecretsBlock.conflict.instance_id))
                                                  : ""
                                            color: Theme.textMuted
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                            visible: text !== ""
                                        }

                                        Repeater {
                                            model: missingSecretsBlock.conflict.missing || []
                                            delegate: RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.spacingSmall
                                                property var info: root.parseMissingSecretToken(modelData, missingSecretsBlock.conflict)

                                                Label {
                                                    text: root.missingSecretLabel(info, missingSecretsBlock.conflict)
                                                    color: Theme.textPrimary
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontBody
                                                    Layout.preferredWidth: 220
                                                    elide: Text.ElideRight
                                                }

                                                TextField {
                                                    id: missingSecretValue
                                                    Layout.fillWidth: true
                                                    placeholderText: info.scope === "" ? "unsupported secret" : "secret value"
                                                    font.pixelSize: 11
                                                    echoMode: TextInput.Password
                                                    enabled: info.scope !== "" && !root.secretExists(info.scope, info.scopeId, info.key)
                                                    onTextChanged: root.setSecretDraftValue(info.scope, info.scopeId, info.key, text)
                                                    background: Rectangle {
                                                        color: Theme.backgroundCard
                                                        border.color: Theme.border
                                                        radius: Theme.radiusSmall
                                                    }
                                                    Binding {
                                                        target: missingSecretValue
                                                        property: "text"
                                                        value: root.secretDraftValue(info.scope, info.scopeId, info.key)
                                                        when: !missingSecretValue.activeFocus
                                                    }
                                                }

                                                Button {
                                                    text: root.secretExists(info.scope, info.scopeId, info.key) ? "Created" : "Create"
                                                    enabled: apiClient.authToken !== ""
                                                             && info.scope !== ""
                                                             && !root.secretExists(info.scope, info.scopeId, info.key)
                                                             && missingSecretValue.text.trim() !== ""
                                                    onClicked: root.createMissingSecret(info, missingSecretsBlock.conflict)
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

                                        Label {
                                            text: root.missingSecretsResolved(missingSecretsBlock.conflict)
                                                  ? "All required secrets are present."
                                                  : "Create the missing secrets to enable plan confirmation."
                                            color: Theme.textMuted
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        id: runStatusSection
                        spacing: Theme.spacingSmall
                        visible: apiClient.extensionsRunId !== ""

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            Label {
                                text: "Run status"
                                color: Theme.textPrimary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                Layout.fillWidth: true
                            }

                            Button {
                                text: "Refresh"
                                enabled: apiClient.authToken !== "" && apiClient.extensionsRunId !== ""
                                onClicked: apiClient.fetchExtensionRunDetail(apiClient.extensionsRunId)
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
                            text: "Run ID: " + apiClient.extensionsRunId
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall
                            visible: runStatusValue() !== ""

                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                color: runStatusColor(runStatusValue())
                            }

                            Label {
                                text: "Status: " + runStatusValue() +
                                      (runPhaseValue() !== "" ? (" (" + runPhaseValue() + ")") : "")
                                color: Theme.textSecondary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        Label {
                            text: apiClient.extensionsRun.started_at
                                  ? ("Started: " + apiClient.extensionsRun.started_at)
                                  : ""
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontBody
                            visible: apiClient.extensionsRun && apiClient.extensionsRun.started_at !== undefined
                                     && apiClient.extensionsRun.started_at !== ""
                        }

                        Label {
                            text: apiClient.extensionsRun.finished_at
                                  ? ("Finished: " + apiClient.extensionsRun.finished_at)
                                  : ""
                            color: Theme.textMuted
                            font.pixelSize: 10
                            font.family: Theme.fontBody
                            visible: apiClient.extensionsRun && apiClient.extensionsRun.finished_at !== undefined
                                     && apiClient.extensionsRun.finished_at !== ""
                        }

                        Label {
                            text: runErrorValue()
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: runErrorValue() !== ""
                        }

                        Label {
                            text: runProgressLabel()
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            Label {
                                text: "Steps"
                                color: Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontBody
                                Layout.fillWidth: true
                            }

                            IconButton {
                                label: "i"
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                onClicked: {
                                    root.showStepLegend = !root.showStepLegend
                                    if (root.showStepLegend) {
                                        stepLegendTimer.restart()
                                    } else {
                                        stepLegendTimer.stop()
                                    }
                                }
                                ToolTip.visible: hovered
                                ToolTip.text: root.showStepLegend ? "Hide step legend" : "Show step legend"
                                ToolTip.delay: 300
                            }
                        }

                        RowLayout {
                            id: stepLegendRow
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall
                            visible: root.showStepLegend

                            HoverHandler {
                                id: stepLegendHover
                                onHoveredChanged: {
                                    if (!root.showStepLegend) {
                                        return
                                    }
                                    if (hovered) {
                                        stepLegendTimer.stop()
                                    } else {
                                        stepLegendTimer.restart()
                                    }
                                }
                            }

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: stepStatusColor("completed")
                            }
                            Label {
                                text: "completed"
                                color: Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontBody
                            }

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: stepStatusColor("running")
                            }
                            Label {
                                text: "running"
                                color: Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontBody
                            }

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: stepStatusColor("pending")
                            }
                            Label {
                                text: "pending"
                                color: Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontBody
                            }

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: stepStatusColor("failed")
                            }
                            Label {
                                text: "failed"
                                color: Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontBody
                            }

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: stepStatusColor("skipped")
                            }
                            Label {
                                text: "skipped"
                                color: Theme.textMuted
                                font.pixelSize: 10
                                font.family: Theme.fontBody
                            }
                        }

                        Repeater {
                            model: apiClient.extensionsRunSteps
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                                implicitHeight: stepRow.implicitHeight + Theme.spacingSmall * 2
                                height: implicitHeight

                                ColumnLayout {
                                    id: stepRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Theme.spacingSmall
                                    spacing: Theme.spacingSmall

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSmall

                                        Rectangle {
                                            width: 8
                                            height: 8
                                            radius: 4
                                            color: stepStatusColor(modelData.status)
                                        }

                                        Label {
                                            text: modelData.action_type || "step"
                                            color: Theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        Label {
                                            text: modelData.status || ""
                                            color: Theme.textSecondary
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                        }
                                    }

                                    Label {
                                        text: modelData.error || ""
                                        color: Theme.textMuted
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                        visible: modelData.error !== undefined && modelData.error !== ""
                                        wrapMode: Text.Wrap
                                    }

                                    Label {
                                        text: {
                                            var parts = []
                                            if (modelData.started_at) {
                                                parts.push("Started: " + modelData.started_at)
                                            }
                                            if (modelData.finished_at) {
                                                parts.push("Finished: " + modelData.finished_at)
                                            }
                                            return parts.join(" • ")
                                        }
                                        color: Theme.textMuted
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                        visible: (modelData.started_at !== undefined && modelData.started_at !== "") ||
                                                 (modelData.finished_at !== undefined && modelData.finished_at !== "")
                                        wrapMode: Text.Wrap
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: Theme.spacingSmall

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSmall

                            Label {
                                text: "Run history"
                                color: Theme.textPrimary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                Layout.fillWidth: true
                            }

                            Button {
                                text: "Refresh"
                                enabled: apiClient.authToken !== ""
                                onClicked: apiClient.fetchExtensionRuns(20)
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
                            text: apiClient.extensionsRuns.length === 0 ? "No runs yet." : ""
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: apiClient.extensionsRuns.length === 0
                        }

                        Repeater {
                            model: apiClient.extensionsRuns
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                                implicitHeight: runRow.implicitHeight + Theme.spacingSmall * 2
                                height: implicitHeight

                                ColumnLayout {
                                    id: runRow
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Theme.spacingSmall
                                    spacing: Theme.spacingSmall

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSmall

                                        Rectangle {
                                            width: 10
                                            height: 10
                                            radius: 5
                                            color: runStatusColor(modelData.status)
                                        }

                                        Label {
                                            text: (modelData.status || "unknown") +
                                                  (modelData.phase ? (" • " + modelData.phase) : "")
                                            color: Theme.textPrimary
                                            font.pixelSize: 11
                                            font.family: Theme.fontBody
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }

                                        Button {
                                            text: "View"
                                            enabled: apiClient.authToken !== ""
                                            onClicked: apiClient.fetchExtensionRunDetail(modelData.run_id)
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

                                    Label {
                                        text: "Run ID: " + modelData.run_id
                                        color: Theme.textMuted
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                    }

                                    Label {
                                        text: modelData.created_at ? ("Created: " + modelData.created_at) : ""
                                        color: Theme.textMuted
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                        visible: modelData.created_at !== undefined && modelData.created_at !== ""
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
                implicitHeight: desiredContent.implicitHeight + Theme.spacingLarge * 2
                height: implicitHeight

                ColumnLayout {
                    id: desiredContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: "Desired state"
                            color: Theme.textPrimary
                            font.pixelSize: 16
                            font.family: Theme.fontDisplay
                            Layout.fillWidth: true
                        }

                        Button {
                            text: "Refresh"
                            enabled: apiClient.authToken !== ""
                            onClicked: apiClient.fetchDesiredBlueprints()
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
                            text: "Clear pending"
                            enabled: apiClient.authToken !== "" && desiredBlueprintCount(false) > 0
                            onClicked: apiClient.clearDesiredBlueprints("false")
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
                            text: "Clear all"
                            enabled: apiClient.authToken !== "" && desiredBlueprintCount() > 0
                            onClicked: clearDesiredDialog.open()
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: "#3a2222"
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

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Label {
                            text: "Filter"
                            color: Theme.textSecondary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                        }

                        Button {
                            text: "All"
                            checkable: true
                            checked: desiredFilter === "all"
                            onClicked: desiredFilter = "all"
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: parent.checked ? Theme.backgroundCard : Theme.backgroundCardRaised
                                border.color: parent.checked ? Theme.accent : Theme.border
                            }
                            contentItem: Label {
                                text: parent.text
                                color: parent.checked ? Theme.textPrimary : Theme.textSecondary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Button {
                            text: "Applied"
                            checkable: true
                            checked: desiredFilter === "applied"
                            onClicked: desiredFilter = "applied"
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: parent.checked ? Theme.backgroundCard : Theme.backgroundCardRaised
                                border.color: parent.checked ? Theme.accent : Theme.border
                            }
                            contentItem: Label {
                                text: parent.text
                                color: parent.checked ? Theme.textPrimary : Theme.textSecondary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Button {
                            text: "Pending"
                            checkable: true
                            checked: desiredFilter === "pending"
                            onClicked: desiredFilter = "pending"
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: parent.checked ? Theme.backgroundCard : Theme.backgroundCardRaised
                                border.color: parent.checked ? Theme.accent : Theme.border
                            }
                            contentItem: Label {
                                text: parent.text
                                color: parent.checked ? Theme.textPrimary : Theme.textSecondary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: reconcileRow.implicitHeight
                        height: implicitHeight

                        RowLayout {
                            id: reconcileRow
                            anchors.fill: parent
                            spacing: Theme.spacingSmall

                            Label {
                                text: "Latest reconcile"
                                color: Theme.textSecondary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                            }

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: runStatusColor(reconcileStatusValue())
                            }

                            Label {
                                text: reconcileHasRun()
                                      ? ("Status: " + (reconcileStatusValue() !== "" ? reconcileStatusValue() : "unknown"))
                                      : "No reconcile run yet."
                                color: Theme.textPrimary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Button {
                                id: reconcileNowButton
                                text: "Reconcile now"
                                enabled: apiClient.authToken !== ""
                                onClicked: apiClient.reconcileNow()
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

                        MouseArea {
                            anchors.left: parent.left
                            anchors.right: reconcileNowButton.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            enabled: reconcileHasRun()
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.openLatestReconcileRun()
                        }
                    }

                    Label {
                        text: reconcileTimeLine()
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.family: Theme.fontBody
                        visible: reconcileTimeLine() !== ""
                    }

                    Label {
                        text: reconcileErrorValue()
                        color: "#D95C5C"
                        font.pixelSize: 10
                        font.family: Theme.fontBody
                        visible: reconcileErrorValue() !== ""
                        wrapMode: Text.Wrap
                    }

                    Label {
                        text: "Total: " + desiredBlueprintCount() +
                              " • Applied: " + desiredBlueprintCount(true) +
                              " • Pending: " + desiredBlueprintCount(false)
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    InlineToast {
                        id: desiredToast
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    Label {
                        text: filteredDesiredBlueprints().length === 0
                              ? desiredFilterLabel()
                              : ""
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        visible: filteredDesiredBlueprints().length === 0
                    }

                    Repeater {
                        model: filteredDesiredBlueprints()
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                            implicitHeight: desiredRow.implicitHeight + Theme.spacingSmall * 2
                            height: implicitHeight

                            ColumnLayout {
                                id: desiredRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingSmall
                                spacing: Theme.spacingSmall

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSmall

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingSmall

                                        Rectangle {
                                            width: 8
                                            height: 8
                                            radius: 4
                                            color: desiredStatusColor(modelData.applied)
                                        }

                                        Label {
                                            text: modelData.blueprint_extension_id + " v" + modelData.blueprint_version
                                            color: Theme.textPrimary
                                            font.pixelSize: 12
                                            font.family: Theme.fontBody
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }

                                    PillTag {
                                        text: modelData.applied ? "applied" : "pending"
                                    }
                                }

                                Label {
                                    text: "Desired ID: " + modelData.desired_id
                                    color: Theme.textMuted
                                    font.pixelSize: 10
                                    font.family: Theme.fontBody
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSmall

                                    Label {
                                        text: modelData.created_at ? ("Created: " + modelData.created_at) : ""
                                        color: Theme.textMuted
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                        visible: modelData.created_at !== undefined && modelData.created_at !== ""
                                    }

                                    Label {
                                        text: modelData.applied_at ? ("Applied: " + modelData.applied_at) : ""
                                        color: Theme.textMuted
                                        font.pixelSize: 10
                                        font.family: Theme.fontBody
                                        visible: modelData.applied_at !== undefined && modelData.applied_at !== ""
                                    }
                                }

                                Label {
                                    text: "Decisions: " + desiredDecisionCount(modelData)
                                    color: Theme.textSecondary
                                    font.pixelSize: 10
                                    font.family: Theme.fontBody
                                }
                            }
                        }
                    }
                }

                Dialog {
                    id: clearDesiredDialog
                    modal: true
                    title: "Clear Desired State"
                    standardButtons: Dialog.Cancel | Dialog.Ok
                    onAccepted: apiClient.clearDesiredBlueprints()
                    contentItem: ColumnLayout {
                        spacing: Theme.spacingSmall
                        Label {
                            text: "Clear all desired blueprints?"
                            color: Theme.textPrimary
                            font.pixelSize: 13
                            font.family: Theme.fontDisplay
                        }
                        Label {
                            text: "This removes the desired state targets for all blueprints."
                            color: Theme.textSecondary
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                        }
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
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        text: "Installed (" + apiClient.extensionsInstalled.length + ")"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Repeater {
                        model: apiClient.extensionsInstalled
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            radius: Theme.radiusMedium
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                            implicitHeight: installedRow.implicitHeight + Theme.spacingMedium * 2
                            height: implicitHeight

                            RowLayout {
                                id: installedRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingMedium
                                spacing: Theme.spacingLarge

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSmall

                                    Label {
                                        text: modelData.name !== "" ? modelData.name : modelData.extension_id
                                        color: Theme.textPrimary
                                        font.pixelSize: 14
                                        font.family: Theme.fontDisplay
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        text: modelData.extension_id
                                        color: Theme.textSecondary
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        spacing: Theme.spacingSmall
                                        PillTag { text: modelData.version !== undefined ? ("v" + modelData.version) : "v?" }
                                        PillTag { text: modelData.kind !== undefined ? modelData.kind : "unknown" }
                                        PillTag { text: modelData.trust_level !== undefined ? modelData.trust_level : "unknown" }
                                        PillTag { text: modelData.enabled === true ? "enabled" : (modelData.enabled === false ? "disabled" : "unknown") }
                                    }
                                }

                                Button {
                                    text: modelData.enabled === true ? "Disable" : "Enable"
                                    enabled: apiClient.authToken !== ""
                                    onClicked: {
                                        if (modelData.enabled === true) {
                                            apiClient.disableExtension(modelData.extension_id)
                                        } else {
                                            apiClient.enableExtension(modelData.extension_id)
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

                                Button {
                                    text: "Uninstall"
                                    enabled: apiClient.authToken !== ""
                                    onClicked: uninstallDialog.open()
                                    background: Rectangle {
                                        radius: Theme.radiusSmall
                                        color: "#3a2222"
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

                            Dialog {
                                id: uninstallDialog
                                modal: true
                                title: "Uninstall Extension"
                                standardButtons: Dialog.Cancel | Dialog.Ok
                                onAccepted: apiClient.uninstallExtension(modelData.extension_id)
                                contentItem: ColumnLayout {
                                    spacing: Theme.spacingSmall
                                    Label {
                                        text: "Uninstall " + (modelData.name !== "" ? modelData.name : modelData.extension_id) + "?"
                                        color: Theme.textPrimary
                                        font.pixelSize: 13
                                        font.family: Theme.fontDisplay
                                    }
                                    Label {
                                        text: "This removes the package and disables instances."
                                        color: Theme.textSecondary
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        text: "No installed extensions yet."
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        visible: apiClient.extensionsInstalled.length === 0
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: availableContent.implicitHeight + Theme.spacingLarge * 2
                height: implicitHeight

                ColumnLayout {
                    id: availableContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        text: "Available (" + apiClient.extensionsAvailable.length + ")"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Repeater {
                        model: apiClient.extensionsAvailable
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            radius: Theme.radiusMedium
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                            implicitHeight: availableRow.implicitHeight + Theme.spacingMedium * 2
                            height: implicitHeight

                            RowLayout {
                                id: availableRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingMedium
                                spacing: Theme.spacingLarge

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSmall

                                    Label {
                                        text: modelData.id
                                        color: Theme.textPrimary
                                        font.pixelSize: 14
                                        font.family: Theme.fontDisplay
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        text: modelData.download_url !== undefined ? modelData.download_url : ""
                                        color: Theme.textSecondary
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                        elide: Text.ElideRight
                                    }

                                    RowLayout {
                                        spacing: Theme.spacingSmall
                                        PillTag { text: modelData.version !== undefined ? ("v" + modelData.version) : "v?" }
                                        PillTag { text: modelData.trust !== undefined ? modelData.trust : "unknown" }
                                    }
                                }

                                Button {
                                    property bool alreadyInstalled: root.isInstalled(modelData.id)
                                    text: alreadyInstalled ? "Installed" : "Install"
                                    enabled: apiClient.authToken !== "" && !alreadyInstalled && modelData.download_url !== undefined
                                    onClicked: apiClient.installExtension(modelData.download_url)
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

                    Label {
                        text: "No registry extensions available."
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        visible: apiClient.extensionsAvailable.length === 0
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border
                implicitHeight: instancesContent.implicitHeight + Theme.spacingLarge * 2
                height: implicitHeight

                ColumnLayout {
                    id: instancesContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        text: "Instances"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        text: "Create and manage instances per extension."
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    Repeater {
                        model: apiClient.extensionsInstalled
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            radius: Theme.radiusMedium
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                            implicitHeight: instanceCard.implicitHeight + Theme.spacingMedium * 2
                            height: implicitHeight

                            ColumnLayout {
                                id: instanceCard
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Theme.spacingMedium
                                spacing: Theme.spacingSmall

                                Label {
                                    text: "Extension: " + modelData.extension_id
                                    color: Theme.textPrimary
                                    font.pixelSize: 13
                                    font.family: Theme.fontDisplay
                                    elide: Text.ElideRight
                                }

                                Repeater {
                                    model: root.instancesFor(modelData.extension_id)
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        radius: Theme.radiusSmall
                                        color: Theme.backgroundCard
                                        border.color: Theme.border
                                        implicitHeight: instanceRow.implicitHeight + Theme.spacingSmall * 2
                                        height: implicitHeight

                                        ColumnLayout {
                                            id: instanceRow
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: Theme.spacingSmall
                                            spacing: Theme.spacingSmall

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.spacingSmall

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Theme.spacingSmall

                                                    Label {
                                                        text: modelData.instance_name
                                                        color: Theme.textPrimary
                                                        font.pixelSize: 12
                                                        font.family: Theme.fontDisplay
                                                        elide: Text.ElideRight
                                                    }

                                                    Label {
                                                        text: modelData.instance_id
                                                        color: Theme.textSecondary
                                                        font.pixelSize: 10
                                                        font.family: Theme.fontBody
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                Button {
                                                    text: modelData.enabled === true ? "Disable" : "Enable"
                                                    enabled: apiClient.authToken !== ""
                                                    onClicked: {
                                                        if (modelData.enabled === true) {
                                                            instanceDisableDialog.open()
                                                        } else {
                                                            apiClient.setExtensionInstanceEnabled(modelData.instance_id, true)
                                                        }
                                                    }
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
                                                    text: "Rollback"
                                                    enabled: apiClient.authToken !== ""
                                                             && modelData.rollback_version !== undefined
                                                             && modelData.rollback_version !== null
                                                             && modelData.rollback_version !== ""
                                                    onClicked: instanceRollbackDialog.open()
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
                                                    text: "Delete"
                                                    enabled: apiClient.authToken !== ""
                                                    onClicked: instanceDeleteDialog.open()
                                                    background: Rectangle {
                                                        radius: Theme.radiusSmall
                                                        color: "#3a2222"
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

                                            Dialog {
                                                id: instanceDisableDialog
                                                modal: true
                                                title: "Disable Instance"
                                                standardButtons: Dialog.Cancel | Dialog.Ok
                                                onAccepted: apiClient.setExtensionInstanceEnabled(modelData.instance_id, false)
                                                contentItem: ColumnLayout {
                                                    spacing: Theme.spacingSmall
                                                    Label {
                                                        text: "Disable instance " + modelData.instance_name + "?"
                                                        color: Theme.textPrimary
                                                        font.pixelSize: 13
                                                        font.family: Theme.fontDisplay
                                                    }
                                                    Label {
                                                        text: "This stops the instance until you re-enable it."
                                                        color: Theme.textSecondary
                                                        font.pixelSize: 11
                                                        font.family: Theme.fontBody
                                                    }
                                                }
                                            }

                                            Dialog {
                                                id: instanceDeleteDialog
                                                modal: true
                                                title: "Delete Instance"
                                                standardButtons: Dialog.Cancel | Dialog.Ok
                                                onAccepted: apiClient.deleteExtensionInstance(modelData.instance_id)
                                                contentItem: ColumnLayout {
                                                    spacing: Theme.spacingSmall
                                                    Label {
                                                        text: "Delete instance " + modelData.instance_name + "?"
                                                        color: Theme.textPrimary
                                                        font.pixelSize: 13
                                                        font.family: Theme.fontDisplay
                                                    }
                                                    Label {
                                                        text: "This removes the instance and its secrets."
                                                        color: Theme.textSecondary
                                                        font.pixelSize: 11
                                                        font.family: Theme.fontBody
                                                    }
                                                }
                                            }

                                            Dialog {
                                                id: instanceRollbackDialog
                                                modal: true
                                                title: "Rollback Instance"
                                                standardButtons: Dialog.Cancel | Dialog.Ok
                                                onAccepted: apiClient.rollbackExtensionInstance(modelData.instance_id)
                                                contentItem: ColumnLayout {
                                                    spacing: Theme.spacingSmall
                                                    Label {
                                                        text: "Rollback instance " + modelData.instance_name + "?"
                                                        color: Theme.textPrimary
                                                        font.pixelSize: 13
                                                        font.family: Theme.fontDisplay
                                                    }
                                                    Label {
                                                        text: "This replaces the current runtime with the previous version."
                                                        color: Theme.textSecondary
                                                        font.pixelSize: 11
                                                        font.family: Theme.fontBody
                                                        wrapMode: Text.Wrap
                                                    }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.spacingSmall

                                                TextField {
                                                    id: secretKeyField
                                                    Layout.preferredWidth: 160
                                                    placeholderText: "secret key"
                                                    font.pixelSize: 11
                                                }

                                                TextField {
                                                    id: secretValueField
                                                    Layout.fillWidth: true
                                                    placeholderText: "secret value"
                                                    echoMode: TextInput.Password
                                                    font.pixelSize: 11
                                                }

                                                Button {
                                                    text: "Add secret"
                                                    enabled: apiClient.authToken !== ""
                                                    onClicked: {
                                                        apiClient.createInstanceSecret(
                                                            modelData.instance_id,
                                                            secretKeyField.text,
                                                            secretValueField.text,
                                                            false)
                                                        secretKeyField.text = ""
                                                        secretValueField.text = ""
                                                    }
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

                                                Label {
                                                    text: "Config"
                                                    color: Theme.textSecondary
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontBody
                                                }

                                                TextArea {
                                                    id: instanceConfigField
                                                    Layout.fillWidth: true
                                                    wrapMode: TextArea.Wrap
                                                    font.pixelSize: 11
                                                    background: Rectangle {
                                                        color: Theme.backgroundCard
                                                        border.color: Theme.border
                                                        radius: Theme.radiusSmall
                                                    }
                                                    Binding {
                                                        target: instanceConfigField
                                                        property: "text"
                                                        value: modelData.config_json !== undefined && modelData.config_json !== null
                                                               ? JSON.stringify(modelData.config_json)
                                                               : ""
                                                        when: !instanceConfigField.activeFocus
                                                    }
                                                }

                                                Button {
                                                    text: "Save config"
                                                    enabled: apiClient.authToken !== ""
                                                    onClicked: apiClient.updateExtensionInstanceConfig(modelData.instance_id, instanceConfigField.text)
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

                                                Label {
                                                    text: "Secrets"
                                                    color: Theme.textSecondary
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontBody
                                                }

                                                Repeater {
                                                    model: root.secretsFor(modelData.instance_id)
                                                    delegate: RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: Theme.spacingSmall

                                                        Label {
                                                            text: modelData.key
                                                            color: Theme.textPrimary
                                                            font.pixelSize: 11
                                                            font.family: Theme.fontBody
                                                            Layout.preferredWidth: 160
                                                            elide: Text.ElideRight
                                                        }

                                                        PillTag { text: modelData.rotatable ? "rotatable" : "fixed" }

                                                        Label {
                                                            text: modelData.created_at
                                                            color: Theme.textMuted
                                                            font.pixelSize: 10
                                                            font.family: Theme.fontBody
                                                            Layout.fillWidth: true
                                                            elide: Text.ElideRight
                                                        }

                                                        Button {
                                                            text: "Rotate"
                                                            enabled: apiClient.authToken !== "" && modelData.rotatable
                                                            onClicked: apiClient.rotateSecret(modelData.secret_id)
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

                                                Label {
                                                    text: root.secretsFor(modelData.instance_id).length === 0
                                                          ? "No secrets yet."
                                                          : ""
                                                    color: Theme.textMuted
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontBody
                                                    visible: root.secretsFor(modelData.instance_id).length === 0
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: Theme.spacingSmall

                                                Label {
                                                    text: "Config"
                                                    color: Theme.textSecondary
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontBody
                                                }

                                                TextArea {
                                                    id: instanceConfigFieldAlt
                                                    Layout.fillWidth: true
                                                    wrapMode: TextArea.Wrap
                                                    font.pixelSize: 11
                                                    background: Rectangle {
                                                        color: Theme.backgroundCard
                                                        border.color: Theme.border
                                                        radius: Theme.radiusSmall
                                                    }
                                                    Binding {
                                                        target: instanceConfigFieldAlt
                                                        property: "text"
                                                        value: modelData.config_json !== undefined && modelData.config_json !== null
                                                               ? JSON.stringify(modelData.config_json)
                                                               : ""
                                                        when: !instanceConfigFieldAlt.activeFocus
                                                    }
                                                }

                                                Button {
                                                    text: "Save config"
                                                    enabled: apiClient.authToken !== ""
                                                    onClicked: apiClient.updateExtensionInstanceConfig(modelData.instance_id, instanceConfigFieldAlt.text)
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

                                                Label {
                                                    text: "Secrets"
                                                    color: Theme.textSecondary
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontBody
                                                }

                                                Repeater {
                                                    model: root.secretsFor(modelData.instance_id)
                                                    delegate: RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: Theme.spacingSmall

                                                        Label {
                                                            text: modelData.key
                                                            color: Theme.textPrimary
                                                            font.pixelSize: 11
                                                            font.family: Theme.fontBody
                                                            Layout.preferredWidth: 160
                                                            elide: Text.ElideRight
                                                        }

                                                        PillTag { text: modelData.rotatable ? "rotatable" : "fixed" }

                                                        Label {
                                                            text: modelData.created_at
                                                            color: Theme.textMuted
                                                            font.pixelSize: 10
                                                            font.family: Theme.fontBody
                                                            Layout.fillWidth: true
                                                            elide: Text.ElideRight
                                                        }

                                                        Button {
                                                            text: "Rotate"
                                                            enabled: apiClient.authToken !== "" && modelData.rotatable
                                                            onClicked: apiClient.rotateSecret(modelData.secret_id)
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

                                                Label {
                                                    text: root.secretsFor(modelData.instance_id).length === 0
                                                          ? "No secrets yet."
                                                          : ""
                                                    color: Theme.textMuted
                                                    font.pixelSize: 11
                                                    font.family: Theme.fontBody
                                                    visible: root.secretsFor(modelData.instance_id).length === 0
                                                }
                                            }
                                        }
                                    }
                                }

                                Label {
                                    text: root.instancesFor(modelData.extension_id).length === 0
                                          ? "No instances yet."
                                          : ""
                                    color: Theme.textMuted
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                    visible: root.instancesFor(modelData.extension_id).length === 0
                                }

                                RowLayout {
                                    spacing: Theme.spacingSmall
                                    Layout.fillWidth: true

                                    TextField {
                                        id: instanceNameField
                                        Layout.preferredWidth: 180
                                        placeholderText: "instance name (default)"
                                        font.pixelSize: 11
                                    }

                                    TextArea {
                                        id: instanceConfigField
                                        Layout.fillWidth: true
                                        placeholderText: "config JSON (optional)"
                                        wrapMode: TextArea.Wrap
                                        font.pixelSize: 11
                                        background: Rectangle {
                                            color: Theme.backgroundCard
                                            border.color: Theme.border
                                            radius: Theme.radiusSmall
                                        }
                                    }

                                    Button {
                                        text: "Create"
                                        enabled: apiClient.authToken !== ""
                                        onClicked: {
                                            apiClient.createExtensionInstance(
                                                modelData.extension_id,
                                                instanceNameField.text,
                                                instanceConfigField.text)
                                            instanceNameField.text = ""
                                            instanceConfigField.text = ""
                                        }
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
        }
    }

    Dialog {
        id: rotatedSecretDialog
        modal: true
        title: "Secret rotated"
        standardButtons: Dialog.Ok
        onAccepted: {
            root.rotatedSecretValue = ""
            root.rotatedSecretCopied = false
        }
        contentItem: ColumnLayout {
            spacing: Theme.spacingSmall
            Label {
                text: "New secret value:"
                color: Theme.textSecondary
                font.pixelSize: 11
                font.family: Theme.fontBody
            }
            TextArea {
                id: rotatedSecretText
                text: root.rotatedSecretValue
                readOnly: true
                wrapMode: TextArea.Wrap
                font.pixelSize: 11
                visible: !root.rotatedSecretCopied
                background: Rectangle {
                    color: Theme.backgroundCard
                    border.color: Theme.border
                    radius: Theme.radiusSmall
                }
            }
            Label {
                text: "Copied to clipboard."
                color: Theme.textMuted
                font.pixelSize: 11
                font.family: Theme.fontBody
                visible: root.rotatedSecretCopied
            }
            RowLayout {
                spacing: Theme.spacingSmall
                Button {
                    text: root.rotatedSecretCopied ? "Copied" : "Copy"
                    enabled: !root.rotatedSecretCopied && root.rotatedSecretValue.length > 0
                    onClicked: {
                        rotatedSecretText.selectAll()
                        rotatedSecretText.copy()
                        rotatedSecretText.deselect()
                        root.rotatedSecretValue = ""
                        root.rotatedSecretCopied = true
                    }
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
