import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Pane {
    id: root
    objectName: "marketplaceInstallationPane"
    property var client: apiClient
    property bool canManage: false
    property var selectedListing: ({})
    property string lastOperation: ""
    property string lastReview: ""
    property string cancellationOperation: ""
    property int targetRefreshes: 0
    readonly property int maximumTargetRefreshes: 30
    property var targetPageCursor: ({})
    // User intent is an instance ID, never a transient ComboBox row number.
    property var selectedTargetInstance: null
    readonly property var operation: client.marketplaceInstallation || ({})
    readonly property var targets: client.marketplaceInstallTargets || ({})
    readonly property bool busy: client.marketplaceInstallationLoading === true
    readonly property string notice: client.marketplaceInstallationNotice || ""
    readonly property var actions: operation.available_actions || []
    // Receipt acknowledgement accepts the decision; source archiving/staging
    // can finish later. Keep observing that SAME operation across this gap.
    readonly property bool approvalAcknowledged: !!operation.latest_action
        && operation.latest_action.kind === "approve" && operation.latest_action.status === "acknowledged"
    readonly property bool hasOperation: !!operation.operation_id
    readonly property bool terminal: ["activated", "cancelled", "stopped"].indexOf(operation.phase) >= 0
    readonly property bool hasChoice: !!selectedListing.extension_id && (!hasOperation || terminal)
    readonly property bool matchingTargets: hasChoice && targets.extension_id === selectedListing.extension_id
    // This enables a request, not an installation or a permission grant.
    readonly property bool reviewAvailable: matchingTargets && targets.review_available === true
        && targets.installation_ready === false
    readonly property var scope: operation.review && operation.review.scope ? operation.review.scope : ({})
    readonly property var keyReview: reviewedKeys()
    readonly property var secretKeys: keyReview.keys
    readonly property bool canUseSecrets: client.capabilities && client.capabilities.indexOf("secrets_manage") >= 0
    readonly property var choices: targetChoices()
    readonly property int chosenTargetIndex: {
        for (var i = 0; i < choices.length; ++i)
            if (choices[i].instance_id === selectedTargetInstance) return i
        return -1
    }
    readonly property bool waitingForTargetReadiness: visible && canManage && hasChoice && matchingTargets
        && !busy && notice === "" && !reviewAvailable && targets.installation_ready === false
        && targetRefreshes < maximumTargetRefreshes
    visible: canManage && (hasChoice || hasOperation || busy || notice !== "")
    padding: 12
    implicitHeight: content.implicitHeight + topPadding + bottomPadding
    background: Rectangle { radius: 8; color: Theme.backgroundCardRaised; border.color: Theme.border }

    function reviewedKeys() {
        var raw = scope.secret_keys
        if (!raw || typeof raw !== "object" || typeof raw.length !== "number" || raw.length > 64) return {valid:false, keys:[]}
        var keys = []
        for (var i = 0; i < raw.length; ++i) {
            if (typeof raw[i] !== "string" || !/^[A-Za-z0-9_.-]{1,64}$/.test(raw[i]) || keys.indexOf(raw[i]) >= 0)
                return {valid:false, keys:[]}
            keys.push(raw[i])
        }
        return {valid:true, keys:keys}
    }
    function targetChoices() {
        var rows = [{name:"Create a new instance", instance_id:""}]
        if (!matchingTargets) return rows
        var instances = targets.instances || []
        for (var i = 0; i < instances.length; ++i) {
            var row = instances[i]
            if (!row.pending && row.controls)
                rows.push({name:row.name + " · " + row.instance_id.slice(0,8), instance_id:row.instance_id})
        }
        return rows
    }
    function inspect(card) {
        if (!canManage || busy || (hasOperation && !terminal)) return
        targetRefreshes = 0; targetPageCursor = ({}); selectedTargetInstance = ""
        selectedListing = {extension_id:card.extension_id, release_id:card.release_id, name:card.name}
        targetChoice.currentIndex = 0
        instanceName.text = card.name
        client.fetchMarketplaceInstallTargets(card.extension_id)
    }
    function inspectDirect(preview) {
        if (!canManage || busy || (hasOperation && !terminal) || !preview.reference_id || preview.signatures_verified !== true) return
        targetRefreshes = 0; targetPageCursor = ({}); selectedTargetInstance = ""
        selectedListing = {extension_id:preview.extension_id,release_id:preview.release_id,name:preview.name,direct_reference:preview.reference_id}
        unqualifiedConsent.checked = false
        targetChoice.currentIndex = 0
        instanceName.text = preview.name
        client.fetchMarketplaceDirectInstallTargets()
    }
    function refreshChoices(cursor, automatic) {
        if (!canManage || busy || !hasChoice) return
        targetPageCursor = cursor || ({})
        if (!automatic) targetRefreshes = 0
        if (selectedListing.direct_reference) client.fetchMarketplaceDirectInstallTargets(targetPageCursor)
        else client.fetchMarketplaceInstallTargets(selectedListing.extension_id,targetPageCursor)
    }
    function syncTargetChoice() {
        // Called after model updates; read the LATEST intent rather than a
        // captured row or old response. A removed instance stays unselected.
        if (root) targetChoice.currentIndex = chosenTargetIndex
    }
    function retryTargetReadiness() {
        if (!waitingForTargetReadiness) return
        targetRefreshes++
        refreshChoices(targetPageCursor,true)
    }
    function directAccepted() {
        return !selectedListing.direct_reference || (unqualifiedConsent.checked
            && (client.marketplaceDirectReference || ({})).reference_id === selectedListing.direct_reference)
    }
    function start() {
        if (!canManage || busy || !reviewAvailable || !hasChoice || !directAccepted()
            || targetChoice.currentIndex !== chosenTargetIndex) return
        var row = choices[chosenTargetIndex]
        if (row) {
            targetRefreshes = maximumTargetRefreshes
            if (selectedListing.direct_reference) client.startMarketplaceDirectInstallation(instanceName.text,row.instance_id,true)
            else client.startMarketplaceInstallation(selectedListing.extension_id, selectedListing.release_id, instanceName.text, row.instance_id)
        }
    }
    function clearSecrets() {
        if (!credentials) return
        for (var i = 0; i < credentials.count; ++i) {
            var row = credentials.itemAt(i)
            if (row) row.valueField.clear()
        }
    }
    function submitSetup() {
        if (!canManage || busy || actions.indexOf("setup") < 0 || !keyReview.valid || (secretKeys.length && !canUseSecrets)) return
        var values = {}
        for (var i = 0; i < credentials.count; ++i) {
            var row = credentials.itemAt(i)
            if (row && row.valueField.text !== "") values[secretKeys[i]] = row.valueField.text
        }
        client.submitMarketplaceInstallationSetup(values)
        clearSecrets()
    }
    function checkStatus() {
        if (!canManage || busy) return
        if (hasOperation) client.pollMarketplaceInstallation()
        else client.fetchCurrentMarketplaceInstallation()
    }
    function confirmCancellation() {
        if (!canManage || busy || !hasOperation || actions.indexOf("cancel") < 0) return
        cancellationOperation = operation.operation_id
        cancelConfirmation.open()
    }
    function operationLabel() {
        var request = operation.initial_request || ({})
        var id = request.extension_id || "Extension request"
        var name = id.slice(id.lastIndexOf("/") + 1)
        var target = request.target || ({})
        return name + (target.kind === "new" ? " · " + target.name : target.instance_id ? " · Instance " + target.instance_id.slice(0,8) : "")
    }
    function resourceText() {
        var runtime = scope.runtime
        if (!runtime) return ""
        var temporary = 0, mounts = runtime.temporary_mounts || []
        for (var i=0; i<mounts.length; ++i) temporary += mounts[i].bytes
        return "Requested limits, not measured usage: " + runtime.memory_bytes/1048576 + " MiB memory, "
            + runtime.cpu_millicores/1000 + " CPU cores, " + (runtime.state_bytes || 0)/1048576
            + " MiB saved state, " + temporary/1048576 + " MiB temporary storage."
    }
    function phaseText() {
        if (operation.preparation && operation.preparation.authorization_lost === true)
            return "Owner authorization could not be confirmed. Sign in and check the original request before starting again."
        switch (operation.phase) {
        case "awaiting_approval": return approvalAcknowledged
            ? "Approval received. Waiting for source preparation to finish…"
            : "Review the access this version requests. Popularity is not a safety review."
        case "awaiting_setup": return "Add the requested credentials, or leave blanks to keep existing values."
        case "awaiting_commit": return "Setup checks passed. Activate this version when you are ready."
        case "activated": return "This version was activated. Runtime availability is reported separately by your server."
        case "cancelled": return "This request was cancelled. An already active version was kept."
        case "stopped": return "This request stopped. Check status before starting another request."
        case "recovery_required":
            if (operation.preparation && operation.preparation.phase === "failed"
                && !operation.configured_instance && !operation.activation_request_id
                && actions.indexOf("cancel") >= 0)
                return "Download or source verification failed. Cancel this attempt before trying again. No new version was activated."
            return "This request needs recovery. Check status, retry the original request, or cancel when available."
        default: return hasOperation ? "Your server is checking this request. It may wait for free resources; playback starts and seeks take priority." : "Choose an instance for this exact version."
        }
    }
    Component.onCompleted: {
        if (canManage && client.authToken !== "" && typeof client.fetchCurrentMarketplaceInstallation === "function")
            client.fetchCurrentMarketplaceInstallation()
    }
    Component.onDestruction: clearSecrets()
    onCanManageChanged: if (!canManage) { clearSecrets(); targetRefreshes = maximumTargetRefreshes; selectedTargetInstance = null; if (cancelConfirmation) cancelConfirmation.close() }
    onCanUseSecretsChanged: if (!canUseSecrets) clearSecrets()
    onVisibleChanged: if (!visible) clearSecrets()
    onChoicesChanged: Qt.callLater(syncTargetChoice)
    onSelectedTargetInstanceChanged: Qt.callLater(syncTargetChoice)
    Connections {
        target: root.client
        ignoreUnknownSignals: true
        function onSessionStateChanged() { root.clearSecrets(); root.targetRefreshes = root.maximumTargetRefreshes; root.selectedTargetInstance = null; root.selectedListing = ({}) }
        function onMarketplaceInstallationChanged() {
            if (root.selectedListing.direct_reference && (root.client.marketplaceDirectReference || ({})).reference_id !== root.selectedListing.direct_reference) {
                root.selectedListing = ({})
                unqualifiedConsent.checked = false
            }
            var operation = root.operation.operation_id || ""
            var review = root.operation.review_id || ""
            if (operation !== root.lastOperation || review !== root.lastReview) {
                root.clearSecrets()
                automaticUpdates.checked = false
                cancelConfirmation.close()
            }
            root.lastOperation = operation; root.lastReview = review
        }
    }
    Timer {
        objectName: "marketplaceTargetReadinessTimer"
        interval: 2000; repeat: true
        running: root.waitingForTargetReadiness
        onTriggered: root.retryTargetReadiness()
    }
    Timer {
        objectName: "marketplaceInstallationPollTimer"
        interval: 1000; repeat: true
        running: root.visible && root.canManage && !root.busy && root.hasOperation
            && (["queued","capturing_target","selecting_source","preparing","staging","installing","activating","cancelling"].indexOf(root.operation.phase) >= 0
                || (root.operation.phase === "awaiting_approval" && root.approvalAcknowledged)
                || (!!root.operation.latest_action && ["queued","running"].indexOf(root.operation.latest_action.status) >= 0))
        onTriggered: root.client.pollMarketplaceInstallation()
    }
    ColumnLayout {
        id: content
        anchors.left: parent.left; anchors.right: parent.right
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Label { text: root.hasOperation ? root.operationLabel() : "Review installation"; textFormat: Text.PlainText; wrapMode: Text.Wrap
                color: Theme.textPrimary; font.pixelSize: 18; Layout.fillWidth: true }
            BusyIndicator { running: root.busy; visible: running; implicitWidth: 24; implicitHeight: 24 }
        }
        Label { Layout.fillWidth: true; text: root.phaseText(); textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.textSecondary }
        Label { objectName:"marketplaceInstallationNotice"; Layout.fillWidth:true; visible:text!==""; text:root.notice
            textFormat:Text.PlainText; wrapMode:Text.Wrap; color:Theme.textSecondary }
        ColumnLayout {
            visible: root.hasChoice
            Layout.fillWidth: true
            Label { text: root.selectedListing.name || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; Layout.fillWidth:true; color:Theme.textPrimary }
            ComboBox { id:targetChoice; objectName:"marketplaceTargetChoice"; Layout.fillWidth:true; model:root.choices; textRole:"name"; enabled:!root.busy
                onModelChanged: Qt.callLater(root.syncTargetChoice)
                onActivated: function(index) {
                    var row = root.choices[index]
                    if (root.canManage && !root.busy && row) root.selectedTargetInstance = row.instance_id
                }
            }
            TextField { id:instanceName; objectName:"marketplaceInstanceName"; Layout.fillWidth:true; maximumLength:128
                Accessible.name:"Instance name"
                visible:targetChoice.currentIndex===0; placeholderText:"Instance name"; enabled:!root.busy }
            CheckBox { id:unqualifiedConsent; objectName:"marketplaceUnqualifiedConsent"; visible:!!root.selectedListing.direct_reference; Layout.fillWidth:true
                Layout.minimumWidth:0; text:"I accept this unqualified developer version."
                enabled:root.canManage && !root.busy
                contentItem: Label { text:unqualifiedConsent.text; font:unqualifiedConsent.font; color:Theme.textPrimary
                    textFormat:Text.PlainText; wrapMode:Text.WordWrap; verticalAlignment:Text.AlignVCenter
                    leftPadding:!unqualifiedConsent.mirrored && unqualifiedConsent.indicator ? unqualifiedConsent.indicator.width+unqualifiedConsent.spacing : 0
                    rightPadding:unqualifiedConsent.mirrored && unqualifiedConsent.indicator ? unqualifiedConsent.indicator.width+unqualifiedConsent.spacing : 0 }
            }
            Label { visible:!!root.selectedListing.direct_reference; Layout.fillWidth:true; textFormat:Text.PlainText; wrapMode:Text.Wrap; color:Theme.textSecondary
                text:"Paid adoption is unqualified. Signatures do not prove safe code; source and permission checks are still required." }
            Label { objectName:"marketplaceInstallationAdmission"; Layout.fillWidth:true; visible:!root.reviewAvailable
                text:root.waitingForTargetReadiness ? "Waiting for protected source review. Choices refresh automatically; no installation has started."
                    : root.matchingTargets ? "Source review is not ready. Check your server, then refresh choices." : "Refresh the listing and its instance choices before reviewing."
                textFormat:Text.PlainText; wrapMode:Text.Wrap; color:Theme.textSecondary }
            Flow {
                Layout.fillWidth:true; spacing:8
                Button { objectName:"marketplaceStartInstallation"; text:root.selectedListing.direct_reference ? "Review developer version" : "Review this version"; enabled:root.canManage && root.reviewAvailable && !root.busy && root.chosenTargetIndex >= 0 && targetChoice.currentIndex === root.chosenTargetIndex && root.directAccepted(); onClicked:root.start() }
                Button { text:"Refresh choices"; enabled:!root.busy; onClicked:root.refreshChoices() }
                Button { objectName:"marketplaceNextTargets"; text:"More instances"; visible:root.matchingTargets && !!root.targets.next_cursor
                    enabled:!root.busy; onClicked:root.refreshChoices(root.targets.next_cursor) }
            }
        }
        ColumnLayout {
            visible:root.actions.indexOf("approve")>=0
            Layout.fillWidth:true
            Label { Layout.fillWidth:true; textFormat:Text.PlainText; wrapMode:Text.Wrap; color:Theme.textPrimary
                text:"Requested access: " + ((root.scope.permissions || []).length ? root.scope.permissions.join(", ") : "No extra permission names") }
            Label { Layout.fillWidth:true; textFormat:Text.PlainText; wrapMode:Text.Wrap; color:Theme.textSecondary
                text:root.secretKeys.length ? "Secret keys: " + root.secretKeys.join(", ") : "No secret keys requested." }
            Label { objectName:"marketplaceRequestedResources"; Layout.fillWidth:true; textFormat:Text.PlainText; wrapMode:Text.Wrap
                color:Theme.textSecondary; text:root.resourceText(); visible:text!=="" }
            CheckBox { id:automaticUpdates; objectName:"marketplaceAutomaticUpdates"; text:"Allow automatic updates when enabled on this server"
                enabled:!root.busy && !root.approvalAcknowledged; checked:false; Layout.fillWidth:true
                contentItem: Label { text:automaticUpdates.text; textFormat:Text.PlainText; wrapMode:Text.Wrap
                    leftPadding:automaticUpdates.indicator ? automaticUpdates.indicator.width+automaticUpdates.spacing : 0
                    verticalAlignment:Text.AlignVCenter; color:Theme.textPrimary } }
            Button { objectName:"marketplaceApproveInstallation"; text:"Approve this access"; enabled:root.canManage && !root.busy && !root.approvalAcknowledged && root.keyReview.valid && (root.secretKeys.length===0 || root.canUseSecrets)
                onClicked:root.client.approveMarketplaceInstallation(automaticUpdates.checked) }
        }
        ColumnLayout {
            id:setup
            visible:root.actions.indexOf("setup")>=0
            Layout.fillWidth:true
            onVisibleChanged: if (!visible) root.clearSecrets()
            Repeater {
                id:credentials; model:root.secretKeys
                ColumnLayout {
                    required property string modelData
                    property alias valueField:password
                    Layout.fillWidth:true
                    Label { text:modelData; textFormat:Text.PlainText; color:Theme.textPrimary; Layout.fillWidth:true; wrapMode:Text.Wrap }
                    TextField { id:password; objectName:"marketplaceCredential_"+modelData; Layout.fillWidth:true
                        Accessible.name:modelData+" credential"
                        echoMode:TextInput.Password; maximumLength:65536; enabled:root.canUseSecrets && !root.busy; placeholderText:"Keep existing or enter a value" }
                }
            }
            Button { objectName:"marketplaceSubmitSetup"; text:"Check setup"; enabled:root.canManage && !root.busy && root.keyReview.valid && (root.secretKeys.length===0 || root.canUseSecrets)
                onClicked:root.submitSetup() }
        }
        Flow {
            Layout.fillWidth:true; spacing:8
            Button { objectName:"marketplaceActivateInstallation"; text:"Activate version"; visible:root.actions.indexOf("activate")>=0; enabled:root.canManage && !root.busy; onClicked:root.client.activateMarketplaceInstallation() }
            Button { objectName:"marketplaceRetryStage"; text:"Retry original staging"; visible:root.actions.indexOf("retry_stage")>=0; enabled:root.canManage && !root.busy; onClicked:root.client.retryMarketplaceInstallationStage() }
            Button { objectName:"marketplaceCancelInstallation"; text:"Cancel request"; visible:root.actions.indexOf("cancel")>=0; enabled:root.canManage && !root.busy; onClicked:root.confirmCancellation() }
            Button { objectName:"marketplaceCheckInstallation"; text:"Check status"; enabled:root.canManage && !root.busy; onClicked:root.checkStatus() }
            Button { objectName:"marketplaceRetryOriginalStart"; text:"Retry original start"; visible:!root.hasOperation && root.client.marketplaceInstallationHasOriginalStart===true; enabled:root.canManage && !root.busy; onClicked:root.client.retryMarketplaceInstallationStart() }
            Button { objectName:"marketplaceRetrySavedDecision"; text:"Retry saved decision"; visible:root.notice!=="" && root.client.marketplaceInstallationHasOriginalAction===true; enabled:root.canManage && !root.busy; onClicked:root.client.retryMarketplaceInstallationAction() }
        }
    }
    Dialog {
        id:cancelConfirmation; objectName:"marketplaceCancelConfirmation"; modal:true; title:"Cancel this request?"
        parent:Overlay.overlay
        anchors.centerIn:parent
        // Use the normal width while the overlay has no window yet. A zero-
        // width wrapped body can feed back into the style's implicit sizing.
        width:parent && parent.width>32 ? Math.min(380,parent.width-32) : 380
        standardButtons:Dialog.Ok|Dialog.Cancel
        contentItem: Label { text:"Discard this staged request? An already active version is kept."; textFormat:Text.PlainText; wrapMode:Text.Wrap }
        onAccepted: {
            if (root.canManage && !root.busy && root.operation.operation_id===root.cancellationOperation && root.actions.indexOf("cancel")>=0)
                root.client.cancelMarketplaceInstallation()
        }
    }
}
