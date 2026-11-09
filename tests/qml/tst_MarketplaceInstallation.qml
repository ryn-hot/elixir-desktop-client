import QtQuick
import QtQuick.Controls
import QtTest
import "../../src/qml/views" as Views

// UI-only fake transport. No native admission, signatures or cleanup proof.
TestCase {
    id: testCase
    name: "MarketplaceInstallation"
    when: windowShown
    Window {
        width: 1000; height: 1200; visible: true; color: "#121820"
        Item { id: host; anchors.fill: parent }
    }
    QtObject {
        id: client
        signal sessionStateChanged()
        property string authToken: "owner-token"
        property var capabilities: ["secrets_manage"]
        property var marketplaceInstallation: ({})
        property var marketplaceInstallTargets: ({})
        property var marketplaceDirectReference: ({})
        property bool marketplaceInstallationLoading: false
        property string marketplaceInstallationNotice: ""
        property bool marketplaceInstallationHasOriginalStart: false
        property bool marketplaceInstallationHasOriginalAction: false
        property int currentReads: 0
        property int polls: 0
        property int targetReads: 0
        property int starts: 0
        property int approvals: 0
        property int setups: 0
        property int activations: 0
        property int cancellations: 0
        property int stageRetries: 0
        property int startRetries: 0
        property int actionRetries: 0
        property var lastRequest: ({})
        property var setupKeys: []
        property bool setupMatched: false
        function fetchCurrentMarketplaceInstallation() { currentReads++ }
        function pollMarketplaceInstallation() { polls++ }
        function fetchMarketplaceInstallTargets(id, cursor) { targetReads++; lastRequest = {extension:id,cursor:cursor || null} }
        function startMarketplaceInstallation(extension, release, name, instance) {
            starts++; lastRequest = {extension:extension,release:release,name:name,instance:instance}
        }
        function fetchMarketplaceDirectInstallTargets(cursor) { targetReads++; lastRequest = {direct:true,cursor:cursor || null} }
        function startMarketplaceDirectInstallation(name, instance, accepted) { starts++; lastRequest = {direct:true,name:name,instance:instance,accepted:accepted} }
        function approveMarketplaceInstallation(automatic) { approvals++; lastRequest = {automatic:automatic} }
        function submitMarketplaceInstallationSetup(values) {
            setups++; setupKeys = Object.keys(values); setupMatched = values.token === "ui-fixture-value"
        }
        function activateMarketplaceInstallation() { activations++ }
        function cancelMarketplaceInstallation() { cancellations++ }
        function retryMarketplaceInstallationStage() { stageRetries++ }
        function retryMarketplaceInstallationStart() { startRetries++ }
        function retryMarketplaceInstallationAction() { actionRetries++ }
    }
    Component { id: factory; Views.MarketplaceInstallationPane {} }
    function init() {
        client.authToken = "owner-token"; client.capabilities = ["secrets_manage"]
        client.marketplaceInstallation = ({}); client.marketplaceInstallTargets = ({})
        client.marketplaceDirectReference = ({})
        client.marketplaceInstallationLoading = false; client.marketplaceInstallationNotice = ""
        client.marketplaceInstallationHasOriginalStart = false; client.marketplaceInstallationHasOriginalAction = false
        client.currentReads = 0; client.polls = 0; client.targetReads = 0; client.starts = 0
        client.approvals = 0; client.setups = 0; client.activations = 0; client.cancellations = 0
        client.stageRetries = 0; client.startRetries = 0; client.actionRetries = 0
        client.lastRequest = ({}); client.setupKeys = []; client.setupMatched = false
    }
    function createPane(width, owner) {
        return createTemporaryObject(factory, host, {client:client,width:width || 650,canManage:owner===undefined ? true : owner})
    }
    function listing() {
        return {extension_id:"elx:"+"a".repeat(52)+"/example", release_id:"sha256:"+"b".repeat(64), name:"<b>Example</b>"}
    }
    function test_developer_reference_requires_separate_consent_and_current_preview() {
        var pane = createPane()
        var preview = listing(); preview.reference_id = "sha256:" + "d".repeat(64); preview.signatures_verified = true
        client.marketplaceDirectReference = preview
        pane.inspectDirect(preview)
        compare(client.targetReads,1); verify(client.lastRequest.direct)
        client.marketplaceInstallTargets = targets(true)
        var button = findChild(pane,"marketplaceStartInstallation")
        verify(!button.enabled)
        mouseClick(findChild(pane,"marketplaceUnqualifiedConsent"))
        verify(button.enabled); mouseClick(button)
        compare(client.starts,1); verify(client.lastRequest.direct); verify(client.lastRequest.accepted)
        client.marketplaceDirectReference = ({})
        verify(!button.enabled); pane.start(); compare(client.starts,1)
    }
    function test_developer_consent_wraps_in_a_compact_window() {
        var pane = createPane(320)
        var preview = listing(); preview.reference_id = "sha256:" + "d".repeat(64); preview.signatures_verified = true
        client.marketplaceDirectReference = preview; pane.inspectDirect(preview)
        client.marketplaceInstallTargets = targets(true)
        var consent = findChild(pane,"marketplaceUnqualifiedConsent")
        compare(consent.contentItem.wrapMode,Text.WordWrap)
        tryVerify(function() { return consent.width <= pane.width && consent.contentItem.paintedWidth <= consent.contentItem.width+1 })
    }
    function test_source_authorization_loss_is_not_reported_as_installation_success() {
        var pane = createPane()
        var state = operation("recovery_required",["cancel"],[])
        state.preparation = {authorization_lost:true}
        client.marketplaceInstallation = state
        verify(pane.phaseText().indexOf("Owner authorization could not be confirmed") >= 0)
        verify(pane.phaseText().indexOf("original request") >= 0)
    }
    function test_failed_preparation_explains_explicit_cancel_without_retrying_or_activating() {
        var pane = createPane()
        var state = operation("recovery_required",["cancel"],[])
        state.preparation = {phase:"failed"}
        client.marketplaceInstallation = state
        compare(pane.phaseText(),"Download or source verification failed. Cancel this attempt before trying again. No new version was activated.")
        compare(client.starts,0); compare(client.cancellations,0); compare(client.stageRetries,0); compare(client.activations,0)
        verify(!pane.terminal); verify(!pane.hasChoice)
        verify(findChild(pane,"marketplaceCancelInstallation").enabled)
    }
    function test_failed_preparation_does_not_hide_unconfirmed_cleanup_or_activation() {
        var pane = createPane()
        var state = operation("recovery_required",["cancel"],[])
        state.preparation = {phase:"cleanup_failed"}
        client.marketplaceInstallation = state
        verify(pane.phaseText().indexOf("needs recovery") >= 0)
        state = operation("recovery_required",["cancel"],[])
        state.preparation = {phase:"failed"}; state.activation_request_id = "30000000-0000-4000-8000-000000000001"
        client.marketplaceInstallation = state
        verify(pane.phaseText().indexOf("needs recovery") >= 0)
        state = operation("recovery_required",[],[]); state.preparation = {phase:"failed"}
        client.marketplaceInstallation = state
        verify(pane.phaseText().indexOf("needs recovery") >= 0)
        state = operation("recovery_required",["cancel"],[])
        state.preparation = {phase:"failed",authorization_lost:true}
        client.marketplaceInstallation = state
        verify(pane.phaseText().indexOf("Owner authorization could not be confirmed") >= 0)
    }
    function targets(reviewAvailable) {
        return {extension_id:listing().extension_id, installation_ready:false, review_available:reviewAvailable, instances:[
            {instance_id:"10000000-0000-4000-8000-000000000001",name:"Existing",pending:false,controls:{kind:"existing"}},
            {instance_id:"10000000-0000-4000-8000-000000000002",name:"Pending",pending:true,controls:null}
        ], next_cursor:{instance_id:"10000000-0000-4000-8000-000000000020",extension_revision:2}}
    }
    function operation(phase, actions, keys) {
        return {operation_id:"20000000-0000-4000-8000-000000000001",phase:phase,available_actions:actions,
            initial_request:{extension_id:listing().extension_id,target:{kind:"new",name:"My instance"}},
            review_id:"sha256:"+"c".repeat(64),review:{scope:{permissions:["network.egress"],secret_keys:keys || [],
                runtime:{memory_bytes:128*1048576,cpu_millicores:100,pids:64,state_bytes:1048576,
                    temporary_mounts:[{path:"/tmp",bytes:8*1048576}]}}}}
    }
    function test_default_admission_and_exact_target_choice() {
        var pane = createPane()
        compare(client.currentReads,1); verify(!pane.visible)
        pane.inspect(listing()); compare(client.targetReads,1)
        compare(client.lastRequest.extension,listing().extension_id)
        client.marketplaceInstallTargets = targets(false)
        verify(!findChild(pane,"marketplaceStartInstallation").enabled)
        pane.start(); compare(client.starts,0)
        client.marketplaceInstallTargets = targets(true)
        var choice = findChild(pane,"marketplaceTargetChoice")
        compare(choice.count,2) // Pending targets must not be offered.
        findChild(pane,"marketplaceInstanceName").text = "My instance"
        mouseClick(findChild(pane,"marketplaceStartInstallation"))
        compare(client.starts,1); compare(client.lastRequest.extension,listing().extension_id)
        compare(client.lastRequest.release,listing().release_id); compare(client.lastRequest.name,"My instance")
        compare(client.lastRequest.instance,"")
        choice.currentIndex = 1
        choice.activated(1)
        pane.start(); compare(client.starts,2)
        compare(client.lastRequest.instance,targets(true).instances[0].instance_id)
        waitForRendering(pane)
        mouseClick(findChild(pane,"marketplaceNextTargets"))
        compare(client.targetReads,2); compare(client.lastRequest.cursor,targets(true).next_cursor)
        client.marketplaceInstallTargets = ({})
        verify(!findChild(pane,"marketplaceStartInstallation").enabled)
    }
    function test_review_availability_does_not_claim_installation_readiness() {
        var pane = createPane()
        pane.inspect(listing())
        var data = targets(true)
        delete data.review_available
        client.marketplaceInstallTargets = data
        verify(!pane.reviewAvailable); pane.start(); compare(client.starts,0)
        data = targets(true); data.installation_ready = true
        client.marketplaceInstallTargets = data
        verify(!pane.reviewAvailable); pane.start(); compare(client.starts,0)
        client.marketplaceInstallTargets = targets(true)
        verify(pane.reviewAvailable)
        compare(client.marketplaceInstallTargets.installation_ready,false)
        pane.start(); compare(client.starts,1)
        compare(client.approvals,0); compare(client.activations,0)
    }
    function test_target_readiness_refreshes_without_starting_or_approving() {
        var pane = createPane()
        pane.inspect(listing()); client.marketplaceInstallTargets = targets(false)
        var choice = findChild(pane,"marketplaceTargetChoice")
        choice.currentIndex = 1
        choice.activated(1)
        var timer = findChild(pane,"marketplaceTargetReadinessTimer")
        verify(timer.running)
        tryVerify(function() { return client.targetReads >= 2 },3500)
        verify(pane.targetRefreshes > 0)
        compare(client.starts,0); compare(client.approvals,0); compare(client.activations,0)
        verify(!findChild(pane,"marketplaceStartInstallation").enabled)
        client.marketplaceInstallTargets = targets(true)
        tryCompare(choice,"currentIndex",1)
        verify(!timer.running); verify(findChild(pane,"marketplaceStartInstallation").enabled)
        compare(client.starts,0)
    }
    function test_target_readiness_wait_is_bounded_and_stops_on_busy_failure_or_owner_loss() {
        var pane = createPane()
        pane.inspect(listing()); client.marketplaceInstallTargets = targets(false)
        var reads = client.targetReads
        pane.targetRefreshes = pane.maximumTargetRefreshes
        pane.retryTargetReadiness(); compare(client.targetReads,reads)
        pane.refreshChoices(); compare(client.targetReads,++reads); compare(pane.targetRefreshes,0)
        client.marketplaceInstallationLoading = true
        pane.retryTargetReadiness(); compare(client.targetReads,reads)
        client.marketplaceInstallationLoading = false
        client.marketplaceInstallationNotice = "Target checks were not confirmed."
        pane.retryTargetReadiness(); compare(client.targetReads,reads)
        client.marketplaceInstallationNotice = ""
        var unsafe = targets(false); unsafe.installation_ready = true
        client.marketplaceInstallTargets = unsafe
        pane.retryTargetReadiness(); compare(client.targetReads,reads)
        client.marketplaceInstallTargets = targets(false)
        pane.canManage = false; pane.retryTargetReadiness(); compare(client.targetReads,reads)
        pane.canManage = true; pane.retryTargetReadiness(); compare(client.targetReads,reads)
        pane.inspect(listing()); reads++
        client.sessionStateChanged(); pane.retryTargetReadiness(); compare(client.targetReads,reads)
        compare(client.starts,0); compare(client.approvals,0); compare(client.activations,0)
    }
    function test_target_refresh_preserves_exact_instance_and_page_or_requires_a_new_choice() {
        var pane = createPane()
        pane.inspect(listing()); client.marketplaceInstallTargets = targets(false)
        var choice = findChild(pane,"marketplaceTargetChoice")
        choice.currentIndex = 1
        choice.activated(1)
        var first = targets(false).instances[0]
        var other = {instance_id:"10000000-0000-4000-8000-000000000003",name:"Other",pending:false,controls:{kind:"existing"}}
        var page = targets(false).next_cursor
        pane.refreshChoices(page)
        client.marketplaceInstallTargets = ({})
        client.marketplaceInstallationNotice = "Target checks were not confirmed."
        pane.refreshChoices(page)
        client.marketplaceInstallationNotice = ""
        var reordered = targets(false); reordered.instances = [other,first]
        client.marketplaceInstallTargets = reordered
        tryCompare(choice,"currentIndex",2)
        pane.retryTargetReadiness()
        compare(client.lastRequest.cursor,page)
        var removed = targets(true); removed.instances = [other]
        client.marketplaceInstallTargets = removed
        tryCompare(choice,"currentIndex",-1)
        verify(!findChild(pane,"marketplaceStartInstallation").enabled)
        pane.start(); compare(client.starts,0)
    }
    function test_waiting_copy_does_not_require_idle_playback() {
        client.marketplaceInstallation = operation("preparing",["cancel"],[])
        var pane = createPane()
        var message = pane.phaseText()
        verify(message.indexOf("free resources") >= 0)
        verify(message.indexOf("playback starts and seeks take priority") >= 0)
        verify(message.indexOf("idle playback") < 0)
        compare(client.starts,0); compare(client.approvals,0); compare(client.activations,0)
    }
    function test_approval_is_explicit_and_automatic_updates_default_off() {
        client.marketplaceInstallation = operation("awaiting_approval",["approve","cancel"],[])
        var pane = createPane()
        compare(client.approvals,0); compare(client.activations,0)
        var automatic = findChild(pane,"marketplaceAutomaticUpdates")
        verify(!automatic.checked)
        mouseClick(findChild(pane,"marketplaceApproveInstallation"))
        compare(client.approvals,1); compare(client.lastRequest.automatic,false)
        mouseClick(automatic); verify(automatic.checked)
        mouseClick(findChild(pane,"marketplaceApproveInstallation"))
        compare(client.approvals,2); compare(client.lastRequest.automatic,true)
        var changed = operation("awaiting_approval",["approve","cancel"],["token"])
        changed.review_id = "sha256:"+"d".repeat(64)
        client.marketplaceInstallation = changed
        verify(!automatic.checked)
        client.capabilities = []
        verify(!findChild(pane,"marketplaceApproveInstallation").enabled)
        changed = operation("awaiting_approval",["approve","cancel"],[])
        changed.review.scope.secret_keys = "not-an-array"
        client.marketplaceInstallation = changed
        verify(!findChild(pane,"marketplaceApproveInstallation").enabled)
    }
    function test_setup_values_are_masked_and_cleared_on_submit_review_and_capability_loss() {
        client.marketplaceInstallation = operation("awaiting_setup",["setup","cancel"],["token","optional"])
        var pane = createPane()
        var field = findChild(pane,"marketplaceCredential_token")
        verify(field); compare(field.echoMode,TextInput.Password)
        compare(field.Accessible.name,"token credential")
        compare(field.maximumLength,65536)
        field.text = "ui-fixture-value"
        mouseClick(findChild(pane,"marketplaceSubmitSetup"))
        compare(client.setups,1); verify(client.setupMatched); compare(client.setupKeys,["token"])
        compare(field.text,"")
        field.text = "discard-on-capability-change"
        client.capabilities = []
        compare(field.text,""); verify(!findChild(pane,"marketplaceSubmitSetup").enabled)
        client.capabilities = ["secrets_manage"]
        field.text = "discard-on-review-change"
        var changed = operation("awaiting_setup",["setup","cancel"],["token","optional"])
        changed.review_id = "sha256:"+"d".repeat(64)
        client.marketplaceInstallation = changed
        compare(findChild(pane,"marketplaceCredential_token").text,"")
        findChild(pane,"marketplaceCredential_token").text = "discard-on-owner-change"
        pane.canManage = false
        compare(findChild(pane,"marketplaceCredential_token").text,"")
        pane.submitSetup(); compare(client.setups,1)
    }
    function test_activation_cancellation_and_recovery_require_explicit_original_actions() {
        client.marketplaceInstallation = operation("awaiting_commit",["activate","cancel"],[])
        var pane = createPane()
        compare(client.activations,0)
        mouseClick(findChild(pane,"marketplaceActivateInstallation")); compare(client.activations,1)
        mouseClick(findChild(pane,"marketplaceCancelInstallation"))
        var confirmation = findChild(pane,"marketplaceCancelConfirmation")
        verify(confirmation.visible); compare(client.cancellations,0)
        confirmation.reject(); compare(client.cancellations,0)
        pane.confirmCancellation(); confirmation.accept(); compare(client.cancellations,1)
        pane.confirmCancellation()
        var changed = operation("recovery_required",["retry_stage","cancel"],[])
        changed.operation_id = "20000000-0000-4000-8000-000000000002"
        client.marketplaceInstallation = changed
        confirmation.accept(); compare(client.cancellations,1)
        tryCompare(confirmation,"visible",false)
        waitForRendering(pane)
        mouseClick(findChild(pane,"marketplaceRetryStage")); compare(client.stageRetries,1)
        mouseClick(findChild(pane,"marketplaceCheckInstallation")); compare(client.polls,1)
        client.marketplaceInstallationNotice = "Previous result is unconfirmed."
        client.marketplaceInstallationHasOriginalAction = true
        waitForRendering(pane)
        mouseClick(findChild(pane,"marketplaceRetrySavedDecision")); compare(client.actionRetries,1)
        client.marketplaceInstallation = ({})
        client.marketplaceInstallationHasOriginalStart = true
        waitForRendering(pane)
        mouseClick(findChild(pane,"marketplaceRetryOriginalStart")); compare(client.startRetries,1)
    }
    function test_cancellation_confirmation_stays_in_window_and_closes_on_owner_loss() {
        client.marketplaceInstallation = operation("awaiting_commit",["activate","cancel"],[])
        var pane = createPane(390)
        pane.y = -700 // The installation pane may be scrolled far above its last action.
        pane.confirmCancellation()
        var confirmation = findChild(pane,"marketplaceCancelConfirmation")
        tryCompare(confirmation,"opened",true)
        verify(confirmation.x>=0 && confirmation.y>=0)
        verify(confirmation.x+confirmation.width<=confirmation.parent.width+1)
        pane.canManage = false
        tryCompare(confirmation,"visible",false)
        confirmation.accept(); compare(client.cancellations,0)
    }
    function test_owner_busy_and_session_changes_do_not_queue_mutations() {
        var pane = createPane(650,false)
        compare(client.currentReads,0); pane.inspect(listing()); compare(client.targetReads,0)
        pane.canManage = true; pane.inspect(listing()); compare(client.targetReads,1)
        client.marketplaceInstallTargets = targets(true)
        client.marketplaceInstallationLoading = true
        pane.start(); pane.inspect(listing()); compare(client.starts,0); compare(client.targetReads,1)
        client.marketplaceInstallationLoading = false
        client.sessionStateChanged(); compare(pane.selectedListing,({}))
        client.marketplaceInstallation = operation("awaiting_setup",["setup","cancel"],["token"])
        findChild(pane,"marketplaceCredential_token").text = "discard-on-session-change"
        client.sessionStateChanged()
        compare(findChild(pane,"marketplaceCredential_token").text,"")
        pane.inspect(listing()); compare(client.targetReads,1)
    }
    function test_compact_review_and_untrusted_metadata_fit_without_rich_text() {
        client.marketplaceInstallation = operation("awaiting_approval",["approve","cancel"],["token"])
        var pane = createPane(390)
        wait(40)
        for (var name of ["marketplaceAutomaticUpdates","marketplaceApproveInstallation","marketplaceCancelInstallation"]) {
            var control = findChild(pane,name), position = control.mapToItem(pane,0,0)
            verify(position.x >= 0 && position.x+control.width <= pane.width+1,name+" must fit")
        }
        compare(findChild(pane,"marketplaceAutomaticUpdates").contentItem.textFormat,Text.PlainText)
        var resources = findChild(pane,"marketplaceRequestedResources")
        compare(resources.textFormat,Text.PlainText)
        verify(resources.text.indexOf("128 MiB memory")>=0)
        verify(resources.text.indexOf("not measured usage")>=0)
        var image = grabImage(pane)
        compare(image.width,390)
        if (marketplaceCaptureDir.length > 0) image.save(marketplaceCaptureDir+"/marketplace-installation.png")
    }
}
