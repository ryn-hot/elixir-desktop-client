import QtQuick
import QtTest
import "../../src/qml/views" as Views

TestCase {
    id: testCase
    name: "MarketplaceSettings"
    when: windowShown
    Window {
        width: 1100; height: 1800; visible: true; color: "#121820"
        Item { id: host; anchors.fill: parent }
    }
    QtObject {
        id: client
        property string authToken: "owner-token"
        property string homeRole: "owner"
        property string activeProfileType: "account"
        property var capabilities: ["server_admin", "extensions_manage", "settings_manage"]
        property var marketplaceSettings: ({})
        property bool marketplaceSettingsLoading: false
        property bool marketplaceConnectionSaving: false
        property string marketplaceConnectionNotice: ""
        property int connectionCalls: 0
        property string connectionInput: ""
        property int fetchCalls: 0
        property int pollCalls: 0
        property int retryCalls: 0
        property int saveCalls: 0
        property var marketplaceSearch: ({})
        property bool marketplaceSearchLoading: false
        property int marketplaceSearchAvailableCount: 0
        property int searchStarts: 0
        property int searchPolls: 0
        property var lastSearch: ({})
        property var lastPreferences: ({})
        signal marketplaceSettingsSaved()
        signal sessionStateChanged()
        signal requestFailed(string endpoint, string error)
        function fetchMarketplaceSettings() { fetchCalls++ }
        function pollMarketplaceSettings() { pollCalls++ }
        function retryMarketplaceConnection() { retryCalls++ }
        function startMarketplaceSearch(text, tags, cursor) {
            searchStarts++; lastSearch = {text:text,tags:tags.slice(),cursor:cursor}
            marketplaceSearchLoading = true
            marketplaceSearch = {phase:"checking"}
        }
        function pollMarketplaceSearch() { searchPolls++ }
        function saveMarketplaceWireguard(config) { connectionCalls++; connectionInput=config; marketplaceConnectionSaving=true }
        function saveMarketplaceSettings(preferences) {
            saveCalls++
            lastPreferences = JSON.parse(JSON.stringify(preferences))
            marketplaceSettingsLoading = true
        }
    }
    Component { id: factory; Views.MarketplaceSettingsView {} }
    function snapshot(mode, acknowledged) {
        return {
            settings: { revision: 3, preferences: {
                schema_version: 1, contribution: mode || "auto", metering: "unknown",
                contribution_disclosure_version: acknowledged ? 1 : null,
                paid_support_consent: false, issuer_disclosure_version: null
            }},
            contribution_disclosure_version: 1,
            contribution_disclosure: "256 MiB memory, 0.1 CPU core, 512 MiB state. 32 KiB/s upload, 128 KiB/s download, 1 GiB monthly. Contributions pause for playback and unknown or metered connections.",
            issuer_disclosure_version: 1,
            issuer_disclosure: "Elixir sees which account requests a credential for which extension. Public support is optional and does not prove a download or safe code.",
            runtime_status: "not_connected"
        }
    }
    function init() {
        client.authToken = "owner-token"
        client.homeRole = "owner"
        client.activeProfileType = "account"
        client.capabilities = ["server_admin", "extensions_manage", "settings_manage", "secrets_manage"]
        client.marketplaceSettingsLoading = false
        client.marketplaceConnectionSaving=false; client.marketplaceConnectionNotice=""; client.connectionCalls=0; client.connectionInput=""
        client.marketplaceSettings = snapshot("auto", false)
        client.fetchCalls = 0; client.pollCalls = 0; client.retryCalls = 0; client.saveCalls = 0; client.lastPreferences = ({})
        client.marketplaceSearch = ({}); client.marketplaceSearchLoading = false
        client.marketplaceSearchAvailableCount = 0; client.searchStarts = 0; client.searchPolls = 0; client.lastSearch = ({})
    }
    function createView(width) {
        return createTemporaryObject(factory, host, { client: client, width: width || 760 })
    }
    function test_default_auto_is_not_disclosure_or_paid_consent() {
        var view = createView()
        verify(view)
        compare(view.editContribution, "auto")
        compare(view.editMetering, 0)
        compare(view.contributionAccepted, false)
        compare(view.supportConsent, false)
        compare(view.issuerAccepted, false)
        verify(findChild(view, "marketplaceRuntimeStatus").text.indexOf("not connected") >= 0)
        view.save()
        compare(client.saveCalls, 1)
        compare(client.lastPreferences.contribution_disclosure_version, null)
        compare(client.lastPreferences.paid_support_consent, false)
        compare(view.notice, "", "saving is not an optimistic runtime acknowledgement")
    }
    function connectedSnapshot() {
        var value = snapshot("off", true)
        value.runtime_fresh = true; value.runtime_status = "running"; value.participation_applied = true
        value.runtime = {participation:{phase:"running",applied_roles:{consumer:true,catalog:false,routing:false}}}
        return value
    }
    function preparedPage(phase, count) {
        client.marketplaceSearchLoading = false
        client.marketplaceSearchAvailableCount = count
        client.marketplaceSearch = {phase:phase,query_id:"checked-first-page",query:{text:"",tags:[],limit:20}}
    }
    function test_first_page_prepares_once_only_after_confirmed_consumer_connection() {
        var view = createView()
        var preparation = findChild(view, "marketplaceBrowsePreparation")
        var button = findChild(view, "marketplacePrepareBrowsing")
        wait(20); compare(client.searchStarts,0); compare(button.enabled,false)
        var value = connectedSnapshot(); value.participation_applied = false
        client.marketplaceSettings = value
        wait(20); compare(client.searchStarts,0)
        client.marketplaceSettings = connectedSnapshot()
        tryCompare(client,"searchStarts",1)
        compare(client.lastSearch,{text:"",tags:[],cursor:""})
        compare(client.saveCalls,0,"preparation does not grant paid support or enable contribution")
        compare(client.retryCalls,0,"preparation never enrolls or restarts a provider")
        preparedPage("checking",2)
        verify(preparation.summary().indexOf("2 checked listings available for browsing")>=0)
        verify(preparation.summary().indexOf("Checking more")>=0)
        tryCompare(client,"searchPolls",1,1500)
        preparedPage("ready",7)
        verify(preparation.summary().indexOf("7 checked listings")>=0)
        verify(preparation.summary().indexOf("More results")>=0)
        var polls = client.searchPolls
        client.marketplaceSettings = connectedSnapshot()
        wait(1100); compare(client.searchStarts,1); compare(client.searchPolls,polls)
        compare(findChild(view,"marketplaceBrowsePreparationStatus").textFormat,Text.PlainText)
    }
    function test_native_client_projection_is_reused_and_empty_does_not_mean_global_ready() {
        client.marketplaceSettings = connectedSnapshot()
        client.marketplaceSearch = marketplacePreparedSearchFixture
        var view = createView(360)
        var preparation = findChild(view,"marketplaceBrowsePreparation")
        wait(20)
        compare(client.searchStarts,0); compare(preparation.firstPage,true)
        verify(preparation.summary().indexOf("not a complete marketplace scan")>=0)
        var bundled = Qt.createComponent("qrc:/qml/views/MarketplaceBrowsePreparation.qml")
        compare(bundled.status,Component.Ready,bundled.errorString())
        view.height = view.implicitHeight
        waitForRendering(view)
        for (var name of ["marketplaceBrowsePreparationStatus","marketplacePrepareBrowsing"]) {
            var control = findChild(view,name)
            verify(control.width<=view.width+1,name+" overflows")
        }
    }
    function test_prepare_does_not_replace_existing_search_or_retry_failed_attempts_automatically() {
        client.marketplaceSearch = {phase:"checking",query_id:"another-query",query:{text:"anime",tags:["anime"],limit:20}}
        client.marketplaceSettings = connectedSnapshot()
        var view = createView()
        var preparation = findChild(view,"marketplaceBrowsePreparation")
        wait(20); compare(client.searchStarts,0)
        preparation.start(); compare(client.searchStarts,1)
        preparedPage("unavailable",0)
        client.marketplaceSettings = connectedSnapshot()
        wait(20); compare(client.searchStarts,1)
        verify(preparation.summary().indexOf("not confirmed")>=0)
        preparation.start(); compare(client.searchStarts,2)
        client.requestFailed("/api/v1/marketplace/search/private-id","<img src='https://private.invalid/'>")
        verify(preparation.summary().indexOf("not confirmed")>=0)
        verify(preparation.summary().indexOf("private.invalid")<0)
        client.marketplaceSearchLoading = false; client.marketplaceSearch = ({})
        client.marketplaceSettings = connectedSnapshot()
        wait(20); compare(client.searchStarts,2)
    }
    function test_preparation_polling_stops_for_hidden_busy_session_or_connection_loss() {
        client.marketplaceSettings = connectedSnapshot()
        var view = createView()
        tryCompare(client,"searchStarts",1)
        var preparation = findChild(view,"marketplaceBrowsePreparation")
        preparedPage("checking",1)
        view.visible = false
        wait(1100); compare(client.searchPolls,0)
        view.visible = true; client.marketplaceSearchLoading = true
        wait(1100); compare(client.searchPolls,0)
        client.marketplaceSearchLoading = false
        var value = connectedSnapshot(); value.runtime_fresh = false
        client.marketplaceSettings = value
        wait(1100); compare(client.searchPolls,0)
        verify(preparation.summary().indexOf("after protected networking")>=0)
        client.authToken = ""
        compare(preparation.visible,false)
        preparation.start(); compare(client.searchStarts,1)
        client.sessionStateChanged()
        compare(preparation.attempted,false); compare(preparation.failure,"")
    }
    function test_catalog_status_reports_pause_staleness_and_legacy_without_a_ready_claim() {
        var view = createView()
        var status = findChild(view, "marketplaceCatalogStatus")
        var value = snapshot("auto",true)
        value.runtime_status = "running"; value.runtime_fresh = true
        value.runtime = {participation:{catalog:{phase:"paused",observed_seconds:0,
            last_peer_page_seconds:null,last_peer_scan_seconds:null,last_page_examined:null}}}
        client.marketplaceSettings = value
        verify(status.text.indexOf("paused") >= 0)
        verify(status.text.indexOf("No successful peer refresh") >= 0)
        value = JSON.parse(JSON.stringify(value)); value.runtime.participation.catalog.phase = "refreshing"
        client.marketplaceSettings = value
        verify(status.text.indexOf("Refreshing") >= 0)
        value = JSON.parse(JSON.stringify(value)); value.runtime.participation.catalog.observed_seconds = 31
        client.marketplaceSettings = value
        verify(status.text.indexOf("stale or unavailable") >= 0)
        value = JSON.parse(JSON.stringify(value)); value.runtime.participation.catalog = null
        client.marketplaceSettings = value
        verify(status.text.indexOf("does not report") >= 0)
        client.authToken = ""
        verify(!status.visible)
    }
    function test_dedicated_connection_is_explicit_and_private_input_is_cleared_after_submission() {
        var view=createView(380)
        compare(view.editConnection,false)
        view.editConnection=true
        var editor=findChild(view,"marketplaceConnectionConfig"),save=findChild(view,"marketplaceConnectionSave")
        editor.text="private WireGuard fixture"
        tryCompare(save,"enabled",true)
        waitForRendering(view)
        mouseClick(save)
        compare(client.connectionCalls,1);compare(client.connectionInput,"private WireGuard fixture");compare(editor.text,"")
        compare(save.enabled,false)
        client.marketplaceConnectionNotice="<img src='https://untrusted.invalid/'>"
        compare(findChild(view,"marketplaceConnectionNotice").textFormat,Text.PlainText)
        client.marketplaceConnectionSaving=false;editor.text="must not survive logout"
        client.authToken=""
        compare(editor.text,"");compare(view.editConnection,false)
    }
    function test_non_owner_cannot_edit_or_submit_connection() {
        client.homeRole="member"
        var view=createView()
        compare(findChild(view,"marketplaceConnectionEditor").enabled,false)
        compare(findChild(view,"marketplaceConnectionSave").enabled,false)
        compare(client.connectionCalls,0)
    }
    function test_live_status_preserves_unsaved_preferences_and_detects_remote_revision_changes() {
        var view=createView()
        view.editMetering=1
        compare(view.dirty,true)
        var value=snapshot("auto",false)
        value.startup={configured:true,retry_owner_present:true,retry_after_seconds:40}
        client.marketplaceSettings=value
        compare(view.editMetering,1)
        verify(view.startupSummary().indexOf("40 seconds")>=0)
        compare(view.canSave,true)
        value=JSON.parse(JSON.stringify(value));value.settings.revision=4
        client.marketplaceSettings=value
        compare(view.editMetering,1)
        compare(view.revisionConflict,true)
        compare(view.canSave,false)
        view.save();compare(client.saveCalls,0)
        verify(findChild(view,"marketplaceRevisionConflict").visible)
        view.refresh();compare(client.fetchCalls,1)
        client.marketplaceSettings=JSON.parse(JSON.stringify(value))
        compare(view.editMetering,0);compare(view.editorRevision,4)
        compare(view.dirty,false);compare(view.canSave,true)
    }
    function test_poll_failure_hides_old_roles_without_erasing_draft_and_saved_response_sets_new_baseline() {
        var view=createView()
        view.editContribution="off"
        var value=snapshot("auto",false)
        value.runtime_fresh=false;value.runtime_status="unknown"
        client.marketplaceSettings=value
        compare(view.editContribution,"off")
        verify(view.runtimeSummary().indexOf("unavailable")>=0)
        verify(view.startupSummary().indexOf("unavailable")>=0)
        compare(findChild(view,"marketplaceConnectionRetry").enabled,false)
        value=snapshot("off",false);value.settings.revision=4
        client.marketplaceSettings=value
        compare(view.dirty,true)
        client.marketplaceSettingsSaved()
        compare(view.editorRevision,4);compare(view.dirty,false)
        view.editMetering=1
        client.authToken="refreshed-owner-token"
        compare(view.editMetering,1,"ordinary token refresh does not reload a draft")
    }
    function test_retry_requires_live_configured_owner_and_polling_has_no_hidden_or_busy_work() {
        var value=snapshot("auto",false)
        value.startup={configured:true,retry_owner_present:true,retry_after_seconds:240}
        client.marketplaceSettings=value
        var view=createView()
        var retry=findChild(view,"marketplaceConnectionRetry")
        compare(retry.enabled,true);mouseClick(retry);compare(client.retryCalls,1)
        var polls=client.pollCalls
        client.marketplaceSettingsLoading=true;view.poll();compare(client.pollCalls,polls)
        client.marketplaceSettingsLoading=false;view.visible=false;view.poll();compare(client.pollCalls,polls)
        view.visible=true;view.poll();compare(client.pollCalls,polls+1)
        value=JSON.parse(JSON.stringify(value));value.startup.retry_owner_present=false;value.startup.retry_after_seconds=null
        client.marketplaceSettings=value
        compare(retry.enabled,false)
        client.homeRole="member";view.poll();compare(client.pollCalls,polls+1)
    }
    function test_new_enable_requires_contribution_review_not_paid_support() {
        client.marketplaceSettings = snapshot("off", false)
        var view = createView()
        view.editContribution = "auto"
        compare(view.canSave, false)
        view.save(); compare(client.saveCalls, 0)
        view.contributionAccepted = true
        view.editMetering = 1
        compare(view.canSave, true)
        view.save()
        compare(client.lastPreferences.metering, "unmetered")
        compare(client.lastPreferences.contribution_disclosure_version, 1)
        compare(client.lastPreferences.paid_support_consent, false)
        compare(client.lastPreferences.issuer_disclosure_version, null)
    }
    function test_paid_support_requires_separate_issuer_visibility_review() {
        var view = createView()
        view.supportConsent = true
        compare(view.canSave, false)
        view.save(); compare(client.saveCalls, 0)
        view.issuerAccepted = true
        compare(view.canSave, true)
        view.save()
        compare(client.lastPreferences.paid_support_consent, true)
        compare(client.lastPreferences.issuer_disclosure_version, 1)
        compare(client.lastPreferences.contribution_disclosure_version, null)
    }
    function test_opt_out_needs_no_new_acknowledgement() {
        var view = createView()
        view.editContribution = "off"
        compare(view.canSave, true)
        view.save()
        compare(client.lastPreferences.contribution, "off")
        compare(client.lastPreferences.contribution_disclosure_version, null)
    }
    function test_missing_or_failed_settings_disable_save_and_render_plain_text() {
        var view = createView()
        client.marketplaceSettings = ({})
        client.requestFailed("/api/v1/marketplace/settings", "<img src='https://untrusted.invalid/x'>")
        compare(view.canSave, false)
        view.save(); compare(client.saveCalls, 0)
        var label = findChild(view, "marketplaceSettingsNotice")
        compare(label.textFormat, Text.PlainText)
        verify(label.text.indexOf("Reload") >= 0)
        compare(findChild(view, "marketplaceContributionDisclosure").textFormat, Text.PlainText)
        compare(findChild(view, "marketplaceIssuerDisclosure").textFormat, Text.PlainText)
    }
    function test_role_loss_cannot_save_and_session_change_clears_draft_consent() {
        var view = createView()
        view.supportConsent = true; view.issuerAccepted = true
        client.homeRole = "member"
        compare(view.canManage, false)
        view.save(); compare(client.saveCalls, 0)
        client.sessionStateChanged()
        compare(view.supportConsent, false)
        compare(view.issuerAccepted, false)
    }
    function test_saved_pending_failed_and_applied_roles_are_distinct() {
        var value = snapshot("off", false)
        value.runtime_status = "running"
        value.participation_applied = false
        value.runtime = { phase: "running", participation: { applied_roles: null } }
        client.marketplaceSettings = value
        var view = createView()
        verify(view.runtimeSummary().indexOf("not yet confirmed") >= 0)
        value = JSON.parse(JSON.stringify(value))
        value.participation_applied = true
        value.runtime.participation = {
            applied_roles: { consumer: true, catalog: false, routing: false },
            package_sharing_active: false
        }
        client.marketplaceSettings = value
        verify(view.runtimeSummary().indexOf("consumer: on; catalog: off") >= 0)
        value = JSON.parse(JSON.stringify(value))
        value.runtime_status = "failed"
        client.marketplaceSettings = value
        verify(view.runtimeSummary().indexOf("stopped is not confirmed") >= 0)
    }
    function test_narrow_layout_wraps_disclosures_and_controls() {
        var view = createView(360)
        view.height = view.implicitHeight
        waitForRendering(view)
        var names = ["marketplaceContributionSwitch", "marketplaceContributionDisclosure",
            "marketplaceContributionAcknowledgement", "marketplacePaidSupportConsent",
            "marketplaceIssuerDisclosure", "marketplaceIssuerAcknowledgement", "marketplaceMeteringCombo"]
        for (var i = 0; i < names.length; i++) {
            var control = findChild(view, names[i])
            verify(control.x + control.width <= view.width + 1, names[i] + " overflows")
        }
        var image = grabImage(view)
        verify(image.width > 0 && image.height > 0)
        image.save("/tmp/elixir-marketplace-settings-preview.png")
    }
}
