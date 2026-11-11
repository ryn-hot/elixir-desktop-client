import QtQuick
import QtTest
import "../../src/qml/views" as Views

TestCase {
    id: testCase
    name: "CommunityMarketplace"
    when: windowShown
    Window {
        width: 1100; height: 1000; visible: true; color: "#121820"
        Item { id: host; anchors.fill: parent }
    }
    QtObject {
        id: client
        signal sessionStateChanged()
        signal requestFailed(string endpoint, string error)
        property string authToken: "owner-token"
        property string homeRole: "owner"
        property string activeProfileType: "account"
        property var capabilities: ["extensions_manage", "settings_manage", "server_admin"]
        property var marketplaceSearch: ({})
        property var marketplaceSettings: ({})
        property bool marketplaceSettingsLoading: false
        property int statusPolls: 0
        property var marketplaceSearchResults: []
        property bool marketplaceSearchLoading: false
        property int marketplaceSearchAvailableCount: 0
        property var marketplaceInstallation: ({})
        property var marketplaceInstallTargets: ({})
        property var marketplaceDirectReference: ({})
        property bool marketplaceDirectReferenceLoading: false
        property int previews: 0
        property bool marketplaceInstallationLoading: false
        property string marketplaceInstallationNotice: ""
        property bool marketplaceInstallationHasOriginalStart: false
        property bool marketplaceInstallationHasOriginalAction: false
        property int targetFetches: 0
        property int starts: 0
        property int polls: 0
        property int accepts: 0
        property int clears: 0
        property var lastRequest: ({})
        function startMarketplaceSearch(text, tags, cursor) {
            starts++
            lastRequest = {text: text, tags: tags.slice(), cursor: cursor}
        }
        function pollMarketplaceSearch() { polls++ }
        function pollMarketplaceSettings() { statusPolls++ }
        function acceptMarketplaceSearchResults() { accepts++ }
        function clearMarketplaceSearch() { clears++ }
        function fetchCurrentMarketplaceInstallation() {}
        function fetchMarketplaceInstallTargets(extensionId) { targetFetches++ }
        function clearMarketplaceDirectReference() { marketplaceDirectReference = ({}) }
        function previewMarketplaceDirectReference(text) { previews++; lastRequest = {reference:text} }
        function fetchMarketplaceDirectInstallTargets() { targetFetches++ }
    }
    Component { id: factory; Views.CommunityMarketplaceView {} }
    function init() {
        client.authToken = "owner-token"
        client.homeRole = "owner"; client.activeProfileType = "account"
        client.capabilities = ["extensions_manage", "settings_manage", "server_admin"]
        client.marketplaceSearch = ({})
        client.marketplaceSettings = ({}); client.marketplaceSettingsLoading = false; client.statusPolls = 0
        client.marketplaceSearchResults = []
        client.marketplaceSearchLoading = false
        client.marketplaceSearchAvailableCount = 0
        client.starts = 0; client.polls = 0; client.accepts = 0; client.clears = 0
        client.lastRequest = ({})
        client.marketplaceInstallation = ({}); client.marketplaceInstallTargets = ({})
        client.marketplaceInstallationLoading = false; client.marketplaceInstallationNotice = ""
        client.targetFetches = 0
        client.previews = 0; client.marketplaceDirectReference = ({}); client.marketplaceDirectReferenceLoading = false
    }
    function createView(width) {
        return createTemporaryObject(factory, host, {client: client, width: width || 760, height: 850})
    }
    function card() {
        return {name: "<img src='https://invalid.test/tracker'> Example", publisher: "<b>Publisher</b>",
            version: "1.0.0", description: "<script>alert('no')</script> Public source is checked; popularity is not a safety review.",
            media_tags: ["movies"], extension_id: "elx:" + "a".repeat(52) + "/example", release_id:"sha256:"+"a".repeat(64),
            support: {verified_supporters: 5, weighted_score: 10}}
    }
    function test_renderer_only_twenty_card_profile() {
        if (!marketplaceRenderPerformance) skip("Explicit renderer-only measurement; excludes API/server/VPN/Tor and scale")
        var view = createView()
        client.marketplaceSearch = {phase:"ready", query_id:"renderer-only", local_page_complete:true}
        verify(waitForRendering(view))
        function countCards(item) {
            var count = item.objectName === "communityMarketplaceCard" ? 1 : 0
            var children = item.children || []
            for (var n = 0; n < children.length; ++n) count += countCards(children[n])
            return count
        }
        function p95(values) {
            return values.slice().sort(function(a,b) { return a-b })[Math.ceil(values.length*0.95)-1]
        }
        for (var size of [128, 1024]) {
            var samples = []
            for (var round = 0; round < 32; ++round) {
                var hadCards = client.marketplaceSearchResults.length > 0
                client.marketplaceSearchResults = []
                if (hadCards) verify(waitForRendering(view))
                compare(countCards(view),0)
                var rows = []
                for (var row = 0; row < 20; ++row) {
                    var value = card()
                    value.name = "Renderer sample " + round + " row " + row
                    value.extension_id += "-" + row
                    value.description = ("Plain-text renderer-only fixture. ").repeat(32).slice(0,size)
                    rows.push(value)
                }
                marketplaceRenderClock.start()
                client.marketplaceSearchResults = rows
                var assigned = marketplaceRenderClock.elapsed()
                verify(waitForRendering(view))
                var rendered = marketplaceRenderClock.elapsed()
                compare(countCards(view),20)
                compare(findChild(view,"communityCardName").text,rows[0].name)
                var image = grabImage(view)
                compare(image.width,760); compare(image.height,850)
                samples.push({assign_ms:assigned,frame_ms:rendered,capture_ms:marketplaceRenderClock.elapsed()})
                if (round === 31 && marketplaceCaptureDir.length > 0)
                    image.save(marketplaceCaptureDir + "/renderer-20-" + size + ".png")
            }
            console.info("marketplace_renderer_profile " + JSON.stringify({
                cards:20,description_bytes:size,samples:samples,
                assign_p95_ms:p95(samples.map(function(s) { return s.assign_ms })),
                frame_p95_ms:p95(samples.map(function(s) { return s.frame_ms })),
                capture_p95_ms:p95(samples.map(function(s) { return s.capture_ms })),
                scope:"QML render-only software/offscreen; excludes API validation, HTTP, server, VPN/Tor, physical display, playback and catalog scale"
            }))
        }
    }
    function test_first_result_fast_poll_window_is_bounded_and_not_renewed_by_progress() {
        var view = createView()
        verify(view.viewActive)
        var burst = findChild(view,"communityFirstResultPollWindow")
        var settling = findChild(view,"communityPagePollWindow")
        var poll = findChild(view,"communitySearchPoll")
        compare(burst.interval,1000); compare(settling.interval,3000)
        client.marketplaceSearch = {query_id:"first-query",phase:"checking",searching_peers:false}
        verify(burst.running); verify(settling.running); compare(poll.interval,100)
        tryVerify(function() { return client.polls > 0 },500)
        client.marketplaceSearch = {query_id:"first-query",phase:"checking",searching_peers:false}
        tryCompare(burst,"running",false,1500)
        verify(settling.running); compare(poll.interval,250)
        client.marketplaceSearch = {query_id:"first-query",phase:"checking",searching_peers:false}
        tryCompare(settling,"running",false,2500)
        compare(poll.interval,1000)
        client.marketplaceSearch = {query_id:"first-query",phase:"checking",searching_peers:false}
        verify(!burst.running); verify(!settling.running); compare(poll.interval,1000)
        client.marketplaceSearch = {query_id:"next-query",phase:"checking",searching_peers:false}
        verify(burst.running); compare(poll.interval,100)
        client.marketplaceSearchLoading = true
        verify(!poll.running)
        verify(settling.running)
        client.marketplaceSearchLoading = false
        verify(poll.running)
        view.visible = false
        verify(!burst.running); verify(!settling.running); verify(!poll.running)
        view.visible = true
        verify(!burst.running); verify(!settling.running); compare(poll.interval,1000)
    }
    function test_partial_cards_keep_same_bounded_burst_but_discovery_and_terminal_phase_stop_it() {
        var view = createView()
        verify(view.viewActive)
        var burst = findChild(view,"communityFirstResultPollWindow")
        var settling = findChild(view,"communityPagePollWindow")
        var poll = findChild(view,"communitySearchPoll")
        client.marketplaceSearch = {query_id:"checked-query",phase:"checking",searching_peers:false}
        verify(burst.running)
        client.marketplaceSearchResults = [card()]
        verify(burst.running); verify(settling.running); compare(poll.interval,100)
        client.marketplaceSearch = {query_id:"checked-query",phase:"checking",searching_peers:false}
        verify(burst.running); verify(settling.running); compare(poll.interval,100)
        client.marketplaceSearchResults = []
        verify(burst.running)
        tryCompare(burst,"running",false,1500)
        verify(settling.running); compare(poll.interval,250)
        client.marketplaceSearch = {query_id:"peer-query",phase:"checking",searching_peers:true}
        verify(!burst.running); verify(!settling.running); compare(poll.interval,1000)
        client.marketplaceSearch = {query_id:"peer-query",phase:"checking",searching_peers:false}
        verify(!burst.running); verify(!settling.running)
        client.marketplaceSearch = {query_id:"ready-query",phase:"checking",searching_peers:false}
        verify(burst.running)
        client.marketplaceSearch = {query_id:"ready-query",phase:"ready",searching_peers:false}
        verify(!burst.running); verify(!settling.running); compare(poll.interval,25000)
        client.marketplaceSearch = {query_id:"failed-query",phase:"checking",searching_peers:false}
        verify(burst.running)
        client.marketplaceSearch = {query_id:"failed-query",phase:"unavailable"}
        verify(!burst.running); verify(!settling.running); verify(!poll.running)
    }
    function test_partial_first_reply_starts_bounded_burst_and_failure_cannot_renew_it() {
        var view = createView()
        var burst = findChild(view,"communityFirstResultPollWindow")
        var settling = findChild(view,"communityPagePollWindow")
        var poll = findChild(view,"communitySearchPoll")
        client.marketplaceSearchResults = [card()]
        client.marketplaceSearch = {query_id:"partial-query",phase:"checking",searching_peers:false}
        verify(burst.running); verify(settling.running); compare(poll.interval,100)
        client.requestFailed("/api/v1/marketplace/search/partial-query","failed")
        verify(!burst.running); verify(!settling.running); verify(!poll.running)
        view.searchFailure = ""
        client.marketplaceSearch = {query_id:"partial-query",phase:"checking",searching_peers:false}
        verify(!settling.running); compare(poll.interval,1000)
        client.marketplaceSearch = {query_id:"new-query",phase:"checking",searching_peers:false}
        verify(burst.running); verify(settling.running); compare(poll.interval,100)
        // Progress and additional partial cards cannot restart either window.
        client.marketplaceSearchResults = [card(),card()]
        client.marketplaceSearch = {query_id:"new-query",phase:"checking",searching_peers:false}
        tryCompare(burst,"running",false,1500)
        verify(settling.running); compare(poll.interval,250)
    }
    function test_hidden_or_unidentified_queries_never_start_fast_polling() {
        var view = createTemporaryObject(factory,host,{client:client,width:760,height:850,visible:false})
        var burst = findChild(view,"communityFirstResultPollWindow")
        var settling = findChild(view,"communityPagePollWindow")
        var poll = findChild(view,"communitySearchPoll")
        client.marketplaceSearch = {query_id:"hidden-query",phase:"checking",searching_peers:false}
        verify(!burst.running); verify(!settling.running); verify(!poll.running)
        view.visible = true
        verify(!burst.running); verify(!settling.running); compare(poll.interval,1000)
        client.marketplaceSearch = {phase:"checking",searching_peers:false}
        verify(!burst.running); verify(!settling.running); compare(poll.interval,1000)
        client.marketplaceSearch = {query_id:"visible-query",phase:"checking",searching_peers:false}
        verify(burst.running); verify(settling.running)
        client.authToken = ""
        verify(!burst.running); verify(!settling.running); verify(!poll.running)
        compare(view.pollingQueryId,"")
    }
    function test_empty_peer_search_shows_nonfinal_progress_and_keeps_filters_and_polling_available() {
        var view = createView()
        view.search("")
        client.marketplaceSearch = {phase:"checking", searching_peers:true, network_complete:false}
        var notice = findChild(view,"communitySearchNotice")
        verify(notice.text.indexOf("No checked matches yet") >= 0)
        verify(notice.text.indexOf("Searching community peers") >= 0)
        compare(client.marketplaceSearchResults.length,0)
        tryVerify(function() { return client.polls > 0 },1500)
        var movies = findChild(view,"communityTag_movies")
        verify(movies.enabled)
        mouseClick(movies)
        tryCompare(client,"starts",2,1200)
        compare(client.lastRequest.tags.join(","),"movies")
        client.marketplaceSearch = {phase:"ready", searching_peers:false, network_complete:false}
        verify(notice.text.indexOf("Searching community peers") < 0)
    }

    function test_developer_preview_is_explicit_plain_text_and_not_a_search_card() {
        var view = createView()
        mouseClick(findChild(view,"marketplaceDeveloperReferenceToggle"))
        var input = findChild(view,"marketplaceDeveloperReferenceText")
        input.text = '{"schema_version":1}'
        compare(client.previews,0)
        mouseClick(findChild(view,"marketplaceCheckDeveloperReference"))
        compare(client.previews,1); compare(client.lastRequest.reference,input.text)
        var preview = card(); preview.reference_id = "sha256:" + "d".repeat(64); preview.signatures_verified = true
        client.marketplaceDirectReference = preview
        compare(client.marketplaceSearchResults.length,0)
        mouseClick(findChild(view,"marketplaceInspectDeveloperReference"))
        compare(client.targetFetches,1)
        input.text = "changed"
        verify(!client.marketplaceDirectReference.reference_id)
        client.homeRole = "member"
        verify(!findChild(view,"marketplaceDirectReferencePane").visible)
    }
    function test_owner_capabilities_and_account_are_required() {
        var view = createView()
        verify(view.canManage)
        findChild(view, "communitySearchText").text = "example"
        view.search(""); compare(client.starts, 1)
        client.homeRole = "member"
        verify(!view.canManage); view.search(""); compare(client.starts, 1)
        client.homeRole = "owner"; client.activeProfileType = "managed"
        verify(!view.canManage); view.search(""); compare(client.starts, 1)
        client.activeProfileType = "account"
        for (var missing of ["extensions_manage", "settings_manage", "server_admin"]) {
            client.capabilities = ["extensions_manage", "settings_manage", "server_admin"].filter(function(v) { return v !== missing })
            verify(!view.canManage); view.search(""); compare(client.starts, 1)
        }
    }
    function test_prepared_first_page_is_adopted_without_replacing_the_checked_query() {
        client.marketplaceSearch = {phase:"ready",query_id:"prepared-query",query:{text:"",tags:[],limit:20},next_cursor:"same_cursor"}
        client.marketplaceSearchResults = [card()]
        client.marketplaceSearchAvailableCount = 2
        var view = createView()
        tryCompare(view,"initialRequestAttempted",true)
        compare(client.starts,0)
        compare(client.accepts,1)
        compare(view.submittedQuery,{text:"",tags:[]})
        compare(client.marketplaceSearch.query_id,"prepared-query")
        compare(view.results.length,1)
        view.search("same_cursor")
        compare(client.starts,1); compare(client.lastRequest,{text:"",tags:[],cursor:"same_cursor"})
    }
    function test_native_client_projection_can_be_adopted_without_a_new_search() {
        client.marketplaceSearch = marketplacePreparedSearchFixture
        var view = createView()
        tryCompare(view,"initialRequestAttempted",true)
        compare(view.submittedQuery,{text:"",tags:[]})
        compare(client.starts,0); compare(client.accepts,1)
    }
    function test_initial_browse_starts_once_after_protection_not_on_every_status_poll() {
        var view = createView()
        wait(20); compare(client.starts,0)
        var value = {runtime_fresh:true,runtime_status:"running",participation_applied:false,
            runtime:{participation:{phase:"running",applied_roles:{consumer:true}}}}
        client.marketplaceSettings = value
        wait(20); compare(client.starts,0)
        value = JSON.parse(JSON.stringify(value)); value.participation_applied = true
        client.marketplaceSettings = value
        tryCompare(client,"starts",1)
        compare(client.lastRequest,{text:"",tags:[],cursor:""})
        client.marketplaceSettings = JSON.parse(JSON.stringify(value))
        client.marketplaceSearch = {phase:"unavailable"}
        client.marketplaceSettings = JSON.parse(JSON.stringify(value))
        wait(20); compare(client.starts,1)
    }
    function test_automatic_browse_requires_visible_current_applied_consumer() {
        var value = {runtime_fresh:true,runtime_status:"running",participation_applied:true,
            runtime:{participation:{phase:"running",applied_roles:{consumer:false}}}}
        client.marketplaceSettings = value
        var view = createTemporaryObject(factory,host,{client:client,width:760,height:850,visible:false})
        wait(20); compare(client.starts,0)
        view.visible = true
        wait(20); compare(client.starts,0)
        value = JSON.parse(JSON.stringify(value)); value.runtime.participation.applied_roles.consumer = true
        value.runtime_fresh = false
        client.marketplaceSettings = value
        wait(20); compare(client.starts,0)
        value = JSON.parse(JSON.stringify(value)); value.runtime_fresh = true
        view.visible = false; client.marketplaceSettings = value
        wait(20); compare(client.starts,0)
        view.visible = true
        tryCompare(client,"starts",1)
    }
    function test_nonempty_stale_and_nonowner_queries_cannot_be_adopted_as_prepared_browsing() {
        for (var item of [
            {phase:"ready",query_id:"other",query:{text:"movies",tags:[],limit:20}},
            {phase:"ready",query_id:"other",query:{text:"",tags:["live"],limit:20}},
            {phase:"stale",query_id:"expired",query:{text:"",tags:[],limit:20}},
            {phase:"ready",query:{text:"",tags:[],limit:20}}
        ]) {
            client.marketplaceSearch = item
            var view = createView()
            wait(20); compare(view.submittedQuery,null); compare(client.accepts,0)
            view.destroy(); wait(0)
        }
        client.homeRole = "member"
        client.marketplaceSearch = {phase:"ready",query_id:"not-owned",query:{text:"",tags:[],limit:20}}
        var restricted = createView()
        wait(20); compare(restricted.submittedQuery,null); compare(client.starts,0)
    }
    function test_logout_and_session_changes_clear_search_drafts_and_hide_old_results() {
        var view = createView()
        var field = findChild(view, "communitySearchText")
        field.text = "Private search"
        view.setTag("anime", true)
        view.search("")
        client.marketplaceSearch = {phase:"ready", next_cursor:"old_cursor"}
        client.marketplaceSearchResults = [card()]
        compare(view.results.length, 1)
        client.authToken = ""
        verify(!view.canManage)
        compare(view.results.length, 0)
        compare(field.text, "")
        compare(view.selectedTags, [])
        compare(view.submittedQuery, null)
        verify(!findChild(view,"communityNextPage").enabled)
        view.search(""); compare(client.starts, 1)
        client.authToken = "new-owner-token"
        field.text = "Another search"
        view.setTag("live", true)
        view.search(""); compare(client.starts, 2)
        client.sessionStateChanged()
        compare(field.text, "")
        compare(view.selectedTags, [])
        compare(view.submittedQuery, null)
        verify(client.clears >= 2)
    }
    function test_search_failures_are_explicit_redacted_and_cleared_only_by_a_new_search() {
        var view = createView()
        view.search("")
        client.marketplaceSearch = {phase:"ready", next_cursor:"old_cursor"}
        client.marketplaceSearchResults = [card()]
        var notice = findChild(view,"communitySearchNotice")
        client.requestFailed("/api/v1/marketplace/settings", "unrelated")
        compare(view.searchFailure, "")
        client.requestFailed("/api/v1/marketplace/search/query", "<img src='https://invalid.test/private'>")
        verify(view.searchFailure.indexOf("not confirmed") >= 0)
        compare(notice.text,view.searchFailure)
        compare(notice.textFormat,Text.PlainText)
        verify(notice.text.indexOf("invalid.test") < 0)
        verify(!findChild(view,"communityNextPage").enabled)
        verify(!findChild(view,"communityReviewInstallation").enabled)
        client.marketplaceSearch = {phase:"ready"}
        verify(view.searchFailure !== "")
        view.search("")
        compare(view.searchFailure, "")
        compare(client.starts, 2)
    }
    function test_filters_are_exclusionary_and_busy_submissions_do_not_queue() {
        var view = createView()
        view.setTag("movies", true); view.setTag("anime", true); view.setTag("tv", true)
        compare(view.selectedTags, ["movies", "anime", "tv"])
        view.setTag("live", true); compare(view.selectedTags, ["live"])
        view.setTag("movies", true); compare(view.selectedTags, ["movies"])
        view.setTag("movies", false); compare(view.selectedTags, [])
        findChild(view, "communitySearchText").text = "Example"
        view.search(""); compare(client.starts, 1)
        compare(client.lastRequest.text, "Example"); compare(client.lastRequest.cursor, "")
        client.marketplaceSearchLoading = true
        verify(findChild(view, "communitySearchButton").enabled)
        view.search(""); compare(client.starts, 1)
    }
    function test_search_click_and_enter_coalesce_while_a_status_read_is_busy() {
        var view = createView()
        var field = findChild(view,"communitySearchText")
        var search = findChild(view,"communitySearchButton")
        client.marketplaceSearchLoading = true
        field.text = "First"
        mouseClick(search)
        field.text = "Latest"
        field.accepted()
        tryCompare(findChild(view,"communitySearchDebounce"),"running",false,1000)
        compare(client.starts,0)
        verify(view.draftPending)
        client.marketplaceSearchLoading = false
        tryCompare(client,"starts",1,1000)
        compare(client.lastRequest,{text:"Latest",tags:[],cursor:""})
        wait(450); compare(client.starts,1)

        // A queued read cannot survive logout or turn into a stale cursor read.
        client.marketplaceSearchLoading = true
        mouseClick(search)
        verify(view.draftPending)
        view.search("stale_cursor"); compare(client.starts,1)
        client.authToken = ""
        verify(!view.draftPending)
        client.marketplaceSearchLoading = false
        wait(50); compare(client.starts,1)
    }
    function test_current_card_can_be_inspected_during_background_refresh_without_installing() {
        client.marketplaceSearch = {phase:"checking",query_id:"original",searching_peers:true}
        client.marketplaceSearchResults = [card()]
        var view = createView()
        verify(waitForRendering(view))
        client.marketplaceSearchLoading = true
        var review = findChild(view,"communityReviewInstallation")
        verify(review.enabled)
        // Its own target/action request is still single-flight; a second
        // selection must not be silently dropped by ApiClient's read guard.
        client.marketplaceInstallationLoading = true
        verify(!review.enabled)
        client.marketplaceInstallationLoading = false
        verify(review.enabled)
        mouseClick(review)
        compare(client.targetFetches,1)
        compare(findChild(view,"marketplaceInstallationPane").selectedListing.release_id,card().release_id)
        verify(!findChild(view,"marketplaceStartInstallation").enabled)
        client.marketplaceSearchResults = [] // Real ApiClient removes expired/revoked cards.
        compare(view.results.length,0)
        verify(findChild(view,"communityReviewInstallation") === null)
    }
    function test_typing_and_filters_coalesce_to_one_latest_draft() {
        var view = createView()
        var field = findChild(view, "communitySearchText")
        field.text = "An"; field.textEdited()
        field.text = "Anime"; field.textEdited()
        view.setTag("anime", true)
        compare(client.starts, 0)
        tryCompare(client, "starts", 1, 1500)
        compare(client.lastRequest, {text:"Anime", tags:["anime"], cursor:""})
        wait(450); compare(client.starts, 1)
    }
    function test_typing_refines_a_checked_local_page_faster_without_queueing_edits() {
        var view = createView()
        var field = findChild(view, "communitySearchText")
        var debounce = findChild(view, "communitySearchDebounce")
        field.text = "A"; field.textEdited()
        compare(debounce.interval, 400)
        client.marketplaceSearch = {phase:"ready", query_id:"local", local_page_complete:true}
        field.text = "An"; field.textEdited()
        compare(debounce.interval, 400) // Empty local results still coalesce cold edits.
        client.marketplaceSearchResults = [card()]
        field.text = "Ani"; field.textEdited()
        compare(debounce.interval, 150)
        field.text = "Anime"; field.textEdited()
        compare(debounce.interval, 150)
        verify(debounce.running); compare(client.starts, 0)
        tryCompare(client, "starts", 1, 1000)
        compare(client.lastRequest, {text:"Anime", tags:[], cursor:""})
        verify(!view.draftPending); verify(!debounce.running)

        client.marketplaceSearch = {phase:"checking", query_id:"remote",
            searching_peers:true, local_page_complete:true}
        field.text = "Anime Movie"; field.textEdited()
        compare(debounce.interval, 400)
        compare(client.starts, 1)
        view.visible = false
        verify(!view.draftPending); verify(!debounce.running)
    }
    function test_filter_choices_skip_typing_delay_and_busy_edits_still_coalesce() {
        var view = createView()
        var debounce = findChild(view, "communitySearchDebounce")
        var field = findChild(view, "communitySearchText")
        view.setTag("movies", true)
        compare(debounce.interval, 0)
        tryCompare(client, "starts", 1, 1500)
        compare(client.lastRequest.tags, ["movies"])
        field.text = "Latest"; field.textEdited()
        compare(debounce.interval, 400)
        compare(client.starts, 1)
        tryCompare(client, "starts", 2, 1500)
        client.marketplaceSearchLoading = true
        view.setTag("anime", true)
        view.setTag("live", true)
        compare(debounce.interval, 0)
        tryCompare(debounce, "running", false, 1500)
        compare(client.starts, 2)
        verify(view.draftPending)
        client.marketplaceSearchLoading = false
        tryCompare(client, "starts", 3, 1500)
        compare(client.lastRequest, {text:"Latest", tags:["live"], cursor:""})
        wait(450); compare(client.starts, 3)
    }
    function test_catalog_progress_is_partial_metadata_not_source_or_global_readiness() {
        var view = createView()
        verify(client.statusPolls >= 1)
        var status = findChild(view, "marketplaceCatalogStatus")
        compare(status.textFormat, Text.PlainText)
        client.marketplaceSettings = {runtime_status:"running",runtime_fresh:true,
            runtime:{participation:{catalog:{phase:"waiting", observed_seconds:1,
                last_peer_page_seconds:10,last_peer_scan_seconds:10,last_page_examined:0}}}}
        verify(status.text.indexOf("Source checks are separate") >= 0)
        verify(status.text.indexOf("not complete network coverage") >= 0)
        verify(status.text.indexOf("10 seconds") >= 0)
        client.marketplaceSettings = {runtime_status:"unknown",runtime_fresh:false}
        verify(status.text.indexOf("unavailable") >= 0)
        verify(status.text.indexOf("10 seconds") < 0)
        client.homeRole = "member"
        verify(!status.visible)
    }
    function test_catalog_status_is_shipped_in_resources_and_wraps_on_narrow_views() {
        var bundled = Qt.createComponent("qrc:/qml/views/MarketplaceCatalogStatus.qml")
        compare(bundled.status, Component.Ready, bundled.errorString())
        var status = createTemporaryObject(bundled, host, {allowed:true,width:320,
            snapshot:{runtime_status:"running",runtime_fresh:true,runtime:{participation:{catalog:{
                phase:"waiting",observed_seconds:0,last_peer_page_seconds:123,
                last_peer_scan_seconds:456,last_page_examined:20}}}}})
        verify(status)
        waitForRendering(status)
        compare(status.textFormat, Text.PlainText)
        compare(status.wrapMode, Text.Wrap)
        verify(status.implicitHeight > status.font.pixelSize * 2)
        verify(status.text.indexOf("not complete network coverage") >= 0)
    }
    function test_busy_search_keeps_only_one_replaceable_auto_draft() {
        var view = createView()
        client.marketplaceSearchLoading = true
        var field = findChild(view, "communitySearchText")
        field.text = "Old"; field.textEdited()
        wait(450); compare(client.starts, 0)
        field.text = "Latest"; field.textEdited()
        view.setTag("live", true)
        wait(450); compare(client.starts, 0)
        client.marketplaceSearchLoading = false
        tryCompare(client, "starts", 1, 1500)
        compare(client.lastRequest, {text:"Latest", tags:["live"], cursor:""})
        wait(450); compare(client.starts, 1)
    }
    function test_busy_release_does_not_restart_an_already_elapsed_typing_delay() {
        var view = createView()
        var field = findChild(view, "communitySearchText")
        var debounce = findChild(view, "communitySearchDebounce")
        client.marketplaceSearchLoading = true
        field.text = "Earlier"; field.textEdited()
        field.text = "Latest"; field.textEdited()
        compare(debounce.interval, 400)
        tryCompare(debounce, "running", false, 1500)
        verify(view.draftPending); compare(client.starts, 0)
        client.marketplaceSearchLoading = false
        // Keep response handling non-reentrant, without another 400ms delay.
        compare(client.starts, 0)
        compare(debounce.interval, 0); verify(debounce.running)
        tryCompare(client, "starts", 1, 1500)
        compare(client.lastRequest, {text:"Latest", tags:[], cursor:""})
        verify(!debounce.running); verify(!view.draftPending)
        client.marketplaceSearchLoading = true
        client.marketplaceSearchLoading = false
        compare(client.starts, 1)
        wait(450); compare(client.starts, 1)
    }
    function test_queued_elapsed_draft_can_be_cleared_before_the_next_event_turn() {
        var view = createView()
        var field = findChild(view, "communitySearchText")
        var debounce = findChild(view, "communitySearchDebounce")
        client.marketplaceSearchLoading = true
        field.text = "Old session"; field.textEdited()
        tryCompare(debounce, "running", false, 1500)
        client.marketplaceSearchLoading = false
        compare(debounce.interval, 0); verify(debounce.running)
        client.sessionStateChanged()
        verify(!debounce.running); verify(!view.draftPending)
        wait(50); compare(client.starts, 0)
    }
    function test_busy_release_preserves_a_still_running_typing_delay() {
        var view = createView()
        var field = findChild(view, "communitySearchText")
        var debounce = findChild(view, "communitySearchDebounce")
        client.marketplaceSearchLoading = true
        field.text = "Latest"; field.textEdited()
        verify(debounce.running)
        client.marketplaceSearchLoading = false
        compare(client.starts, 0); verify(debounce.running)
        tryCompare(client, "starts", 1, 1500)
        compare(client.lastRequest, {text:"Latest", tags:[], cursor:""})
        wait(450); compare(client.starts, 1)
    }
    function test_pending_auto_search_does_not_cross_sessions_or_visibility() {
        var view = createView()
        view.setTag("anime", true)
        client.authToken = ""
        client.authToken = "replacement-token"
        wait(450); compare(client.starts, 0); verify(!view.draftPending)
        view.setTag("live", true)
        client.sessionStateChanged()
        wait(450); compare(client.starts, 0); verify(!view.draftPending)
        view.setTag("movies", true)
        view.visible = false
        wait(450); compare(client.starts, 0); verify(!view.draftPending)
        view.visible = true
        wait(450); compare(client.starts, 0)
    }
    function test_untrusted_metadata_is_plain_text_and_results_require_explicit_refresh() {
        client.marketplaceSearch = {phase: "ready", next_cursor: "opaque_cursor"}
        client.marketplaceSearchResults = [card()]
        client.marketplaceSearchAvailableCount = 2
        var view = createView()
        view.search("")
        var name = findChild(view, "communityCardName")
        verify(name); compare(name.textFormat, Text.PlainText); compare(name.text, card().name)
        var verification = findChild(view, "communityCardSourceVerification")
        compare(verification.text, "Source match checked on install")
        compare(verification.textFormat, Text.PlainText)
        verify(findChild(view, "communityShowNewResults").visible)
        mouseClick(findChild(view, "communityShowNewResults")); compare(client.accepts, 1)
        verify(findChild(view, "communityNextPage").visible)
        var scroll = findChild(view, "communityScrollView")
        scroll.contentItem.contentY = Math.max(0, scroll.contentItem.contentHeight - scroll.contentItem.height)
        waitForRendering(view)
        mouseClick(findChild(view, "communityNextPage")); compare(client.lastRequest.cursor, "opaque_cursor")
        verify(findChild(view, "communitySearchNotice").text.indexOf("partial") >= 0)
    }
    function test_expired_unavailable_and_empty_catalog_are_not_safe_or_global_claims() {
        var view = createView()
        var notice = findChild(view, "communitySearchNotice")
        client.marketplaceSearch = {phase: "stale"}
        verify(notice.text.indexOf("expired") >= 0)
        client.marketplaceSearch = {phase: "unavailable"}
        verify(notice.text.indexOf("unavailable") >= 0)
        client.marketplaceSearch = {phase: "ready"}
        verify(notice.text.indexOf("Peer search") >= 0)
        verify(notice.text.indexOf("incomplete") >= 0)
    }
    function test_completed_page_can_explicitly_refresh_order_without_new_cards() {
        client.marketplaceSearch = {phase: "ready"}
        client.marketplaceSearchResults = [card(), card()]
        client.marketplaceSearchAvailableCount = 2
        var view = createView()
        var refresh = findChild(view, "communityShowNewResults")
        verify(refresh.visible)
        compare(refresh.text, "Refresh displayed order")
        mouseClick(refresh)
        compare(client.accepts, 1)
    }
    function test_unavailable_candidates_do_not_hide_an_existing_continuation() {
        client.marketplaceSearch = {phase: "unavailable", next_cursor: "owner_local_cursor"}
        var view = createView()
        view.search("")
        var next = findChild(view, "communityNextPage")
        verify(next.visible); compare(next.text, "Try more results")
        mouseClick(next); compare(client.lastRequest.cursor, "owner_local_cursor")
        client.marketplaceSearch = {phase: "stale", next_cursor: "owner_local_cursor"}
        verify(!next.visible)
    }
    function test_changed_draft_cannot_reuse_an_original_page_cursor() {
        var view = createView()
        var field = findChild(view, "communitySearchText")
        field.text = "Example"
        view.setTag("movies", true)
        view.search("")
        compare(client.starts, 1)
        client.marketplaceSearch = {phase: "ready", next_cursor: "original_cursor"}
        var next = findChild(view, "communityNextPage")
        verify(next.enabled)
        field.text = "Other"
        verify(view.queryChanged)
        verify(!next.enabled)
        verify(findChild(view, "communitySearchNotice").text.indexOf("Updating your search") >= 0)
        view.search("original_cursor")
        compare(client.starts, 1)
        field.text = "Example"
        verify(!view.queryChanged)
        verify(next.enabled)
        view.setTag("live", true)
        verify(view.queryChanged)
        verify(!next.enabled)
        view.search("original_cursor")
        compare(client.starts, 1)
        view.search("")
        compare(client.starts, 2)
        compare(client.lastRequest.text, "Example")
        compare(client.lastRequest.tags, ["live"])
        compare(client.lastRequest.cursor, "")
        verify(!view.queryChanged)
    }
    function test_equivalent_tag_order_pages_the_original_submitted_query() {
        var view = createView()
        findChild(view, "communitySearchText").text = "Example"
        view.setTag("movies", true)
        view.setTag("anime", true)
        view.search("")
        client.marketplaceSearch = {phase: "ready", next_cursor: "original_cursor"}
        view.setTag("movies", false)
        verify(view.queryChanged)
        view.setTag("movies", true)
        compare(view.selectedTags, ["anime", "movies"])
        verify(!view.queryChanged)
        view.search("original_cursor")
        compare(client.starts, 2)
        compare(client.lastRequest.text, "Example")
        compare(client.lastRequest.tags, ["movies", "anime"])
        compare(client.lastRequest.cursor, "original_cursor")
    }
    function test_unknown_cursor_cannot_start_a_search_before_submission() {
        var view = createView()
        client.marketplaceSearch = {phase: "ready", next_cursor: "foreign_cursor"}
        verify(!findChild(view, "communityNextPage").enabled)
        view.search("foreign_cursor")
        compare(client.starts, 0)
    }
    function test_card_opens_exact_version_review_without_starting_installation() {
        client.marketplaceSearch = {phase:"ready"}; client.marketplaceSearchResults = [card()]
        var view = createView()
        var review = findChild(view,"communityReviewInstallation")
        tryVerify(function() { return review.width>0 && review.height>0 })
        waitForRendering(view)
        mouseClick(review)
        compare(client.targetFetches,1)
        var pane = findChild(view,"marketplaceInstallationPane")
        compare(pane.selectedListing.extension_id,card().extension_id)
        compare(pane.selectedListing.release_id,card().release_id)
        verify(!findChild(view,"marketplaceStartInstallation").enabled)
    }
    function test_compact_cards_and_search_fit_the_view() {
        client.marketplaceSearch = {phase: "ready"}
        client.marketplaceSearchResults = [card()]
        client.marketplaceSearchAvailableCount = 1
        var view = createView(390)
        wait(40)
        var button = findChild(view, "communitySearchButton")
        var position = button.mapToItem(view, 0, 0)
        verify(position.x >= 0 && position.x + button.width <= view.width + 1)
        var name = findChild(view, "communityCardName")
        position = name.mapToItem(view, 0, 0)
        verify(position.x >= 0 && position.x + name.width <= view.width + 1)
        verify(name.wrapMode === Text.Wrap)
        var image = grabImage(view)
        compare(image.width, 390); compare(image.height, 850)
        if (marketplaceCaptureDir.length > 0)
            image.save(marketplaceCaptureDir + "/community-marketplace.png")
        view.search("")
        findChild(view, "communitySearchText").text = "Changed search"
        verify(view.queryChanged)
        var notice = findChild(view, "communitySearchNotice")
        verify(notice.text.indexOf("Updating your search") >= 0)
        position = notice.mapToItem(view, 0, 0)
        verify(position.x >= 0 && position.x + notice.width <= view.width + 1)
        waitForRendering(view)
        if (marketplaceCaptureDir.length > 0)
            grabImage(view).save(marketplaceCaptureDir + "/community-marketplace-draft.png")
    }
}
