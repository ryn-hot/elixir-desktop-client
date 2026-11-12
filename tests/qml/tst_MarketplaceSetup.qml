import QtQuick
import QtTest
import "../../src/qml/views" as Views

TestCase {
    id: testCase
    name: "MarketplaceSetup"
    when: windowShown
    Window {
        width: 1000; height: 1800; visible: true; color: "#121820"
        Item { id: host; anchors.fill: parent }
    }
    QtObject {
        id: client
        property string authToken: "owner-token"
        property string baseUrl: "http://server.invalid"
        property string homeId: "home-one"
        property string activeProfileId: "account-one"
        property string sessionId: "session-one"
        property int capabilityRevision: 1
        property string homeRole: "owner"
        property string activeProfileType: "account"
        property var capabilities: ["server_admin","extensions_manage","settings_manage","secrets_manage"]
        property var marketplaceSettings: ({})
        property bool marketplaceSettingsLoading: false
        property bool marketplaceConnectionSaving: false
        property string marketplaceConnectionNotice: ""
        property var marketplaceSearch: ({})
        property bool marketplaceSearchLoading: false
        property int marketplaceSearchAvailableCount: 0
        property int fetchCalls: 0
        property int pollCalls: 0
        property int searchStarts: 0
        property int searchPolls: 0
        property bool lastPrepareCatalog: false
        property int saveCalls: 0
        property int connectionCalls: 0
        property int retryCalls: 0
        signal marketplaceSettingsSaved()
        signal sessionStateChanged()
        signal requestFailed(string endpoint, string error)
        function fetchMarketplaceSettings() {
            if (marketplaceSettingsLoading) return
            fetchCalls++; marketplaceSettings = ({}); marketplaceSettingsLoading = true
        }
        function pollMarketplaceSettings() { pollCalls++ }
        function startMarketplaceSearch(text,tags,cursor,prepareCatalog) {
            lastPrepareCatalog = prepareCatalog === true
            searchStarts++; marketplaceSearchLoading = true; marketplaceSearch = {phase:"checking"}
        }
        function pollMarketplaceSearch() { searchPolls++ }
        function saveMarketplaceSettings(preferences) { saveCalls++; marketplaceSettingsLoading = true }
        function saveMarketplaceWireguard(config) { connectionCalls++ }
        function retryMarketplaceConnection() { retryCalls++ }
    }
    QtObject {
        id: navigation
        property bool busy: false
        property int replacements: 0
        property string destination: ""
        property var parameters: ({})
        function replace(url,properties) {
            replacements++; destination = String(url); parameters = properties
        }
    }
    Component { id: factory; Views.InitialHomeView {} }
    function snapshot(mode,acknowledged,connected) {
        return {
            settings:{revision:3,preferences:{schema_version:1,contribution:mode || "auto",metering:"unknown",
                contribution_disclosure_version:acknowledged ? 1 : null,paid_support_consent:false,issuer_disclosure_version:null}},
            contribution_disclosure_version:1,contribution_disclosure:"Help power the extension marketplace: eligible servers may share verified installed extensions and bounded catalog/routing data through protected networking. Contribution is optional; off preserves owner-requested searches and downloads. Background limits: 256 MiB memory, 0.1 CPU core, 512 MiB automatic state, 32 KiB/s upload, 128 KiB/s download and 1 GiB combined monthly transfer. Unknown or metered connections do not contribute automatically. Availability and safe code are not guaranteed by popularity.",
            issuer_disclosure_version:1,issuer_disclosure:"Elixir sees credential requests; support is optional.",
            runtime_fresh:true,runtime_status:connected ? "running" : "not_connected",participation_applied:connected===true,
            runtime:connected ? {participation:{phase:"running",applied_roles:{consumer:true,catalog:false,routing:false}}} : null
        }
    }
    function reply(value) {
        client.marketplaceSettingsLoading = false
        client.marketplaceSettings = value
    }
    function progress(phase) {
        return {schema_version:1,phase:phase || "complete",scope:"current_local_catalog",examined:43,
            available:40,omitted:3,pages:3,received:60,local_pass_complete:!phase || phase==="complete",
            network_complete:false,metadata_only:true}
    }
    function page(count,prepared) {
        client.marketplaceSearchLoading = false
        client.marketplaceSearchAvailableCount = count
        client.marketplaceSearch = {phase:"ready",query_id:"same-checked-page",query:{text:"",tags:[],limit:20},
            preparation:prepared===false ? undefined : progress()}
    }
    function createView(width,height) {
        return createTemporaryObject(factory,host,{client:client,stackView:navigation,width:width || 760,height:height || 1600})
    }
    function init() {
        client.authToken="owner-token"; client.baseUrl="http://server.invalid"
        client.homeId="home-one"; client.activeProfileId="account-one"; client.sessionId="session-one"; client.capabilityRevision=1
        client.homeRole="owner"; client.activeProfileType="account"
        client.capabilities=["server_admin","extensions_manage","settings_manage","secrets_manage"]
        client.marketplaceSettings=({}); client.marketplaceSettingsLoading=false
        client.marketplaceSearch=({}); client.marketplaceSearchLoading=false; client.marketplaceSearchAvailableCount=0
        client.marketplaceConnectionSaving=false; client.marketplaceConnectionNotice=""
        client.fetchCalls=0; client.pollCalls=0; client.searchStarts=0; client.searchPolls=0
        client.lastPrepareCatalog=false
        client.saveCalls=0; client.connectionCalls=0; client.retryCalls=0
        navigation.busy=false; navigation.replacements=0; navigation.destination=""; navigation.parameters=({})
    }
    function test_first_owner_waits_for_fresh_settings_and_never_accepts_consent() {
        client.marketplaceSettings=snapshot("auto",true,true)
        var view=createView()
        compare(client.fetchCalls,1); compare(client.marketplaceSettingsLoading,true)
        wait(20); compare(navigation.replacements,0); compare(view.offered,false)
        reply(snapshot("auto",false,false))
        tryCompare(view,"offered",true)
        compare(view.canBrowse,false); compare(client.saveCalls,0); compare(client.connectionCalls,0)
        compare(client.retryCalls,0); compare(client.searchStarts,0)
        compare(findChild(view,"marketplacePaidSupportConsent").visible,false)
        compare(findChild(view,"marketplaceIssuerAcknowledgement").visible,false)
    }
    function test_returning_owner_and_explicit_off_do_not_restart_setup_or_search() {
        for (var choice of [snapshot("auto",true,false),snapshot("off",false,false)]) {
            var view=createView()
            reply(choice)
            tryCompare(navigation,"replacements",1)
            verify(navigation.destination.endsWith("HomeView.qml"))
            compare(client.searchStarts,0); compare(client.saveCalls,0); compare(client.connectionCalls,0)
            view.destroy(); wait(1); navigation.replacements=0
        }
    }
    function test_nonowner_and_managed_profiles_go_home_without_owner_requests() {
        for (var kind of ["member","managed","missing-capability"]) {
            if (kind==="member") client.homeRole="member"
            else if (kind==="managed") { client.homeRole="owner"; client.activeProfileType="managed" }
            else { client.activeProfileType="account"; client.capabilities=["extensions_manage"] }
            var view=createView()
            tryCompare(navigation,"replacements",1)
            verify(navigation.destination.endsWith("HomeView.qml")); compare(client.fetchCalls,0)
            compare(client.searchStarts,0); compare(client.saveCalls,0)
            view.destroy(); wait(1); navigation.replacements=0
        }
    }
    function test_defer_is_always_available_without_mutating_or_claiming_readiness() {
        var view=createView()
        verify(client.marketplaceSettingsLoading)
        verify(findChild(view,"marketplaceSetupLater").enabled)
        view.requestFinish("not-a-destination"); compare(view.pendingDestination,"")
        view.requestFinish("home")
        tryCompare(navigation,"replacements",1)
        verify(navigation.destination.endsWith("HomeView.qml"))
        compare(client.saveCalls,0); compare(client.connectionCalls,0); compare(client.retryCalls,0)
        compare(client.searchStarts,0); compare(view.canBrowse,false)
    }
    function test_hidden_entry_and_session_changes_do_not_fetch_until_visible() {
        var view=createTemporaryObject(factory,host,{client:client,stackView:navigation,width:760,height:640,visible:false})
        wait(20); compare(client.fetchCalls,0)
        client.homeId="other-home"; client.sessionStateChanged()
        wait(20); compare(client.fetchCalls,0)
        view.visible=true
        tryCompare(client,"fetchCalls",1)
        view.visible=false
        reply(snapshot("auto",true,false))
        wait(20); compare(navigation.replacements,0)
        view.visible=true
        tryCompare(navigation,"replacements",1)
    }
    function test_prepared_nonempty_page_requires_saved_choice_and_reuses_the_same_query() {
        var view=createView()
        reply(snapshot("auto",false,true)); tryCompare(view,"offered",true)
        wait(20); compare(client.searchStarts,0,"setup preparation waits for the saved choice")
        page(7,false); wait(20); compare(view.canBrowse,false,"a checked first page is not saved consent")
        client.marketplaceSearch=({})
        reply(snapshot("auto",true,true)); tryCompare(client,"searchStarts",1)
        verify(client.lastPrepareCatalog)
        page(7); tryCompare(view,"canBrowse",true)
        var original=client.marketplaceSearch.query_id
        view.requestFinish("browse")
        tryCompare(navigation,"replacements",1)
        verify(navigation.destination.endsWith("CommunityMarketplaceView.qml"))
        compare(navigation.parameters.client,client)
        compare(client.marketplaceSearch.query_id,original); compare(client.searchStarts,1)
        compare(client.saveCalls,0,"only an explicit editor action can save consent")
    }
    function test_first_page_readiness_does_not_wait_for_background_catalog_completion() {
        var view=createView()
        reply(snapshot("auto",false,true)); tryCompare(view,"offered",true)
        reply(snapshot("off",false,true)); tryCompare(client,"searchStarts",1)
        verify(client.lastPrepareCatalog)
        for (var state of ["discovering","checking","waiting","limited"]) {
            client.marketplaceSearchLoading=false
            client.marketplaceSearchAvailableCount=0
            client.marketplaceSearch={phase:"checking",query_id:"catalog-pass",query:{text:"",tags:[],limit:20},preparation:progress(state)}
            wait(1); compare(view.canBrowse,false)
            verify(findChild(view,"marketplaceBrowsePreparationStatus").text.length>0)
        }
        for (var phase of ["discovering","checking","waiting","limited","unavailable"]) {
            client.marketplaceSearchLoading=false
            client.marketplaceSearchAvailableCount=2
            client.marketplaceSearch={phase:"ready",query_id:"first-page",query:{text:"",tags:[],limit:20},preparation:progress(phase)}
            tryCompare(view,"canBrowse",true)
            compare(client.searchStarts,1,"background progress cannot replace the checked query")
            verify(findChild(view,"marketplaceSetupReadiness").text.indexOf("not a complete network scan")>=0)
        }
        page(2,false); wait(1); compare(view.canBrowse,false,"explicit preparation still requires bounded progress data")
        page(2); tryCompare(view,"canBrowse",true)
        var forged=progress(); forged.network_complete=true
        client.marketplaceSearch.preparation=forged; client.marketplaceSearchChanged()
        wait(1); compare(view.canBrowse,false)
    }
    function test_background_progress_keeps_polling_after_first_page_without_claiming_a_full_pass() {
        var view=createView()
        reply(snapshot("auto",false,true)); tryCompare(view,"offered",true)
        reply(snapshot("off",false,true)); tryCompare(client,"searchStarts",1)
        client.marketplaceSearchLoading=false; client.marketplaceSearchAvailableCount=2
        client.marketplaceSearch={phase:"ready",query_id:"first-page",query:{text:"",tags:[],limit:20},preparation:progress("waiting")}
        tryCompare(view,"canBrowse",true)
        verify(findChild(view,"marketplaceBrowsePreparationStatus").text.indexOf("background")>=0)
        var polls=client.searchPolls
        tryVerify(function() { return client.searchPolls>polls },1500)
        view.visible=false
        polls=client.searchPolls; wait(1100); compare(client.searchPolls,polls)
        compare(client.searchStarts,1)
    }
    function test_terminal_empty_preparation_is_actionable_without_waiting_for_expiry_or_retrying_itself() {
        var view=createView(360,640)
        reply(snapshot("auto",false,true)); tryCompare(view,"offered",true)
        reply(snapshot("off",false,true)); tryCompare(client,"searchStarts",1)
        var preparation=findChild(view,"marketplaceBrowsePreparation")
        for (var phase of ["complete","limited","unavailable"]) {
            client.marketplaceSearchLoading=false; client.marketplaceSearchAvailableCount=0
            client.marketplaceSearch={phase:"ready",query_id:"empty-page",query:{text:"",tags:[],limit:20},preparation:progress(phase)}
            tryCompare(preparation,"terminalEmpty",true)
            compare(view.canBrowse,false)
            var status=findChild(view,"marketplaceBrowsePreparationStatus")
            verify(status.text.indexOf("Retry browse checks")>=0)
            verify(status.text.indexOf("use Elixir for now")>=0)
            var retry=findChild(view,"marketplacePrepareBrowsing")
            verify(retry.visible && retry.enabled)
            var footerRetry=findChild(view,"marketplaceSetupRetryBrowse")
            verify(footerRetry.visible && footerRetry.enabled)
            waitForRendering(view)
            verify(footerRetry.mapToItem(view,0,0).y>=0)
            verify(footerRetry.mapToItem(view,0,0).y+footerRetry.height<=view.height)
            verify(findChild(view,"marketplaceSetupReadiness").text.indexOf("Retry browse checks")>=0)
            compare(client.searchStarts,1,"a terminal result must not silently retry")
        }
        client.marketplaceSearch={phase:"ready",query_id:"empty-page",query:{text:"",tags:[],limit:20},preparation:progress("waiting")}
        compare(preparation.terminalEmpty,false,"a live resource deferral is not a finished empty result")
        client.marketplaceSearchAvailableCount=1
        client.marketplaceSearch={phase:"ready",query_id:"checked-page",query:{text:"",tags:[],limit:20},preparation:progress("unavailable")}
        compare(preparation.terminalEmpty,false,"a failed background pass cannot erase an independent checked card")
        tryCompare(view,"canBrowse",true)
        compare(client.searchStarts,1)
        compare(client.saveCalls,0); compare(client.connectionCalls,0); compare(client.retryCalls,0)
        client.marketplaceSearchAvailableCount=0
        client.marketplaceSearch={phase:"ready",query_id:"empty-page",query:{text:"",tags:[],limit:20},preparation:progress("complete")}
        var editor=findChild(view,"marketplaceSettingsView")
        editor.editMetering=1
        compare(view.canRetryBrowse,false)
        view.retryBrowse(); compare(client.searchStarts,1,"retry cannot discard edited participation choices")
        editor.editMetering=0
        tryCompare(view,"canRetryBrowse",true)
        mouseClick(findChild(view,"marketplaceSetupRetryBrowse"))
        compare(client.searchStarts,2,"one explicit click starts exactly one new browse")
        verify(client.lastPrepareCatalog)
        compare(client.saveCalls,0); compare(client.connectionCalls,0); compare(client.retryCalls,0)
    }
    function test_first_verified_prefix_opens_without_waiting_for_pending_candidates() {
        var view=createView()
        reply(snapshot("auto",false,true)); tryCompare(view,"offered",true)
        reply(snapshot("off",false,true)); tryCompare(client,"searchStarts",1)
        client.marketplaceSearchLoading=false; client.marketplaceSearchAvailableCount=1
        client.marketplaceSearch={phase:"checking",query_id:"checked-prefix",query:{text:"",tags:[],limit:20},preparation:progress("checking")}
        tryCompare(view,"canBrowse",true)
        verify(findChild(view,"marketplaceBrowsePreparationStatus").text.indexOf("Checking more")>=0)
        compare(client.searchStarts,1)
        client.marketplaceSearchLoading=true
        compare(view.canBrowse,false)
        client.marketplaceSearchLoading=false
        tryCompare(view,"canBrowse",true)
        client.marketplaceSearchAvailableCount=0
        compare(view.canBrowse,false)
        client.marketplaceSearchAvailableCount=1
        tryCompare(view,"canBrowse",true)
        view.requestFinish("browse")
        tryCompare(navigation,"replacements",1)
        compare(client.marketplaceSearch.query_id,"checked-prefix")
        compare(client.searchStarts,1,"opening checked results must retain their original query")
    }
    function test_empty_stale_other_query_dirty_or_unprotected_state_never_finishes_as_ready() {
        var view=createView()
        reply(snapshot("auto",false,true)); tryCompare(view,"offered",true)
        page(0); reply(snapshot("off",false,true)); wait(20); compare(view.canBrowse,false)
        page(1); tryCompare(view,"canBrowse",true)
        client.marketplaceSearch={phase:"stale"}; compare(view.canBrowse,false)
        page(1); client.marketplaceSearch.query.text="other"; client.marketplaceSearchChanged()
        wait(20); compare(view.canBrowse,false)
        page(1)
        var editor=findChild(view,"marketplaceSettingsView")
        editor.editMetering=1; compare(view.canBrowse,false)
        editor.editMetering=0; tryCompare(view,"canBrowse",true)
        var lost=snapshot("off",false,true); lost.runtime_fresh=false
        reply(lost); compare(view.canBrowse,false)
        view.requestFinish("browse"); wait(20); compare(navigation.replacements,0)
    }
    function test_terminal_connection_is_actionable_not_an_indefinite_wait_data() {
        return [{tag:"failed",phase:"failed"},{tag:"stopped",phase:"stopped"}]
    }
    function test_owned_startup_recovery_is_not_terminal_or_browse_authority() {
        var view=createView()
        reply(snapshot("auto",false,false)); tryCompare(view,"offered",true)
        var preparation=findChild(view,"marketplaceBrowsePreparation")
        for (var delay of [null,0,5,300]) {
            var recovering=snapshot("off",false,false)
            recovering.runtime_status="failed"
            recovering.runtime={phase:"failed",participation:null}
            recovering.startup={configured:true,retry_owner_present:true,retry_after_seconds:delay}
            reply(recovering)
            compare(preparation.recoveringConnection,true)
            compare(preparation.terminalConnection,false)
            compare(preparation.connected,false)
            compare(view.canBrowse,false); compare(view.canRetryBrowse,false)
            verify(findChild(view,"marketplaceSetupReadiness").text.indexOf("Browsing is not ready")>=0)
            compare(client.searchStarts,0); compare(client.retryCalls,0); compare(client.connectionCalls,0)
        }
        for (var changed of ["stale","no-owner","unconfigured","untrusted-flag"]) {
            var failed=snapshot("off",false,false)
            failed.runtime_status="failed"; failed.runtime={phase:"failed",participation:null}
            failed.startup={configured:true,retry_owner_present:true,retry_after_seconds:5}
            if (changed==="stale") failed.runtime_fresh=false
            else if (changed==="no-owner") failed.startup.retry_owner_present=false
            else if (changed==="unconfigured") failed.startup.configured=false
            else failed.startup.retry_owner_present="true"
            reply(failed)
            compare(preparation.recoveringConnection,false)
            compare(preparation.terminalConnection,changed!=="stale")
            compare(view.canBrowse,false)
        }
        reply(snapshot("off",false,true))
        tryCompare(client,"searchStarts",1,1000,"only actual protected readiness may start the initial browse")
        compare(preparation.recoveringConnection,false)
        page(1); tryCompare(view,"canBrowse",true)
        compare(client.retryCalls,0); compare(client.saveCalls,0)
    }
    function test_terminal_connection_is_actionable_not_an_indefinite_wait(data) {
        var view=createView()
        reply(snapshot("auto",false,true)); tryCompare(view,"offered",true)
        reply(snapshot("off",false,true)); tryCompare(client,"searchStarts",1)
        page(1); tryCompare(view,"canBrowse",true)
        var preparation=findChild(view,"marketplaceBrowsePreparation")
        var lost=snapshot("off",false,false)
        lost.runtime_status=data.phase
        lost.runtime={phase:data.phase,participation:null}
        reply(lost)
        compare(preparation.terminalConnection,true)
        compare(view.canBrowse,false)
        var status=findChild(view,"marketplaceBrowsePreparationStatus")
        verify(status.text.indexOf("unavailable")>=0)
        verify(status.text.indexOf("connection settings")>=0)
        verify(status.text.indexOf("Waiting")<0)
        compare(client.searchStarts,1,"failure must not silently start another query or connection")
        compare(client.connectionCalls,0); compare(client.retryCalls,0)
        lost.runtime_fresh=false; reply(lost)
        compare(preparation.terminalConnection,false,"stale terminal data cannot assert current state")
        compare(view.canBrowse,false)
        reply(snapshot("off",false,true)); tryCompare(view,"canBrowse",true)
        compare(client.searchStarts,1)
    }
    function test_delayed_navigation_rechecks_scope_visibility_and_protection() {
        navigation.busy=true
        var view=createView()
        reply(snapshot("auto",false,true)); tryCompare(view,"offered",true)
        page(2); reply(snapshot("off",false,true)); tryCompare(view,"canBrowse",true)
        view.requestFinish("browse"); wait(20); compare(navigation.replacements,0)
        view.visible=false; navigation.busy=false
        wait(20); compare(navigation.replacements,0)
        var lost=snapshot("off",false,true); lost.participation_applied=false
        reply(lost); view.visible=true
        wait(20); compare(navigation.replacements,0); compare(view.pendingDestination,"")
        navigation.busy=true; view.requestFinish("home")
        client.homeId="home-two"; wait(20)
        compare(view.pendingDestination,""); compare(client.fetchCalls,2)
        client.marketplaceSettingsLoading=false; client.capabilityRevision++
        tryCompare(client,"fetchCalls",3)
        compare(navigation.replacements,0,"privilege revisions cannot inherit queued navigation")
        client.authToken=""; navigation.busy=false
        wait(20); compare(navigation.replacements,0)
    }
    function test_failure_and_retry_do_not_echo_private_data_or_auto_accept_a_new_owner() {
        var view=createView()
        client.marketplaceSettingsLoading=false
        client.requestFailed("/api/v1/marketplace/settings","<img src='https://private.invalid/secret'>")
        verify(view.failure.indexOf("private.invalid")<0)
        compare(findChild(view,"marketplaceSetupFailure").textFormat,Text.PlainText)
        view.retry(); compare(client.fetchCalls,2)
        reply(snapshot("auto",false,true)); tryCompare(view,"offered",true)
        client.marketplaceSettingsLoading=false
        client.requestFailed("/api/v1/marketplace/settings","unknown save outcome")
        view.retry(); reply(snapshot("auto",true,true))
        wait(20); compare(navigation.replacements,0,"retry cannot skip preparation for the new owner")
        compare(client.saveCalls,0)
    }
    function test_stale_snapshot_cannot_auto_continue_or_leave_an_unbounded_spinner() {
        var view=createView()
        var value=snapshot("auto",true,false); value.runtime_fresh=false
        reply(value)
        tryVerify(function() { return view.failure.indexOf("stale")>=0 })
        compare(navigation.replacements,0); compare(view.evaluated,false)
        compare(findChild(view,"marketplaceSetupLoading").running,false)
        view.retry(); reply(snapshot("auto",false,true))
        tryCompare(view,"offered",true)
        compare(findChild(view,"marketplaceRuntimeStatus").visible,false)
        compare(findChild(view,"marketplaceConnectionEditor").visible,false)
        reply(snapshot("off",false,true))
        tryCompare(client,"searchStarts",1)
        page(0)
        verify(findChild(view,"marketplaceBrowsePreparationStatus").text.indexOf("No checked extensions")>=0)
        verify(findChild(view,"marketplacePrepareBrowsing").visible)
        var editor=findChild(view,"marketplaceSettingsView")
        var meter=findChild(view,"marketplaceMeteringCombo")
        compare(meter.currentText,"Not sure")
        editor.editMetering=1
        compare(meter.currentText,"No data limit")
        compare(editor.draftPreferences().metering,"unmetered")
        var fetches=client.fetchCalls
        view.retry(); compare(client.fetchCalls,fetches,"retry cannot discard edited choices")
        compare(view.canBrowse,false)
    }
    function test_native_sequence_packaging_and_compact_controls() {
        var view=createView(360,640)
        reply(snapshot("auto",false,true)); tryCompare(view,"offered",true)
        reply(snapshot("off",false,true)); tryCompare(client,"searchStarts",1)
        client.marketplaceSearchLoading=false
        client.marketplaceSearch={phase:"checking",query_id:"same-checked-page",query:{text:"",tags:[],limit:20},
            preparation:progress("discovering")}
        var later=findChild(view,"marketplaceSetupLater")
        var status=findChild(view,"marketplaceSetupReadiness")
        tryCompare(status,"text","Checking available extensions…")
        verify(later.enabled && later.visible)
        verify(later.mapToItem(view,0,0).y+later.height<=view.height,"deferring must stay visible while checking")
        compare(view.canBrowse,false)
        client.marketplaceSearch=marketplacePreparedSearchFixture
        client.marketplaceSearchLoading=false; client.marketplaceSearchAvailableCount=2
        tryCompare(view,"canBrowse",true)
        var bundled=Qt.createComponent("qrc:/qml/views/InitialHomeView.qml")
        compare(bundled.status,Component.Ready,bundled.errorString())
        var main=Qt.createComponent("qrc:/qml/main.qml")
        compare(main.status,Component.Ready,main.errorString())
        waitForRendering(view)
        for (var name of ["marketplaceSetupLater","marketplaceSetupBrowse","marketplaceSetupReadiness"]) {
            var control=findChild(view,name)
            verify(control.width<=view.width,name+" overflows")
        }
        verify(later.mapToItem(view,0,0).y+later.height<=view.height,"deferring must be reachable without scrolling through setup")
        var image=grabImage(view)
        verify(image.width>0&&image.height>0)
        image.save("/tmp/elixir-marketplace-setup-preview.png")
        view.destroy(); wait(1)
        // Exercise the actual shipped resource too, including the resume path
        // that a source-only import cannot prove is bundled correctly.
        client.marketplaceSettings=({}); client.marketplaceSettingsLoading=false
        var fetches=client.fetchCalls
        var packaged=createTemporaryObject(bundled,host,{client:client,stackView:navigation,width:360,height:640})
        compare(client.fetchCalls,fetches+1)
        packaged.visible=false; reply(snapshot("auto",true,false))
        wait(20); compare(navigation.replacements,0)
        packaged.visible=true
        tryCompare(navigation,"replacements",1)
    }
}
