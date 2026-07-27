import QtQuick
import QtTest
import Elixir 1.0
import "../../src/qml/components" as Components
import "../../src/qml/views" as Views

TestCase {
    id: testCase
    name: "LiveBrowse"
    when: windowShown

    Window {
        id: testWindow
        width: 1280
        height: 720
        visible: true

        Item {
            id: host
            anchors.fill: parent
        }
    }

    ListModel { id: rows }

    QtObject {
        id: mock
        property var providers: []
        property var catalogs: []
        property string selectedProviderId: ""
        property string selectedCatalogId: ""
        property bool catalogIndexLoading: false
        property bool pageLoading: false
        property bool loadingMore: false
        property bool itemLoading: false
        property bool hasMore: false
        property bool stale: false
        property bool partial: false
        property var errors: []
        property var lastError: ({})
        property var selectedItem: ({})
        property var selectedStreams: []
        property int refreshIndexCalls: 0
        property int selectCatalogCalls: 0
        property int loadItemCalls: 0
        property string homeRole: "owner"
        property var capabilities: ["live_manage", "settings_manage"]
        property string activeProfileId: "30000000-0000-4000-8000-000000000003"
        property bool liveEgressLoading: false
        property int fetchLiveEgressCalls: 0
        property var liveEgressStatus: ({
            enabled: true,
            ready: true,
            activeBindings: 0,
            availableCapacity: 6,
            defaultPolicy: { mode: "off", policyId: "", allowFallback: false },
            profiles: [{
                id: "warp-default",
                name: "WARP",
                kind: "warp",
                selectableByProfiles: true
            }],
            assignments: [{
                id: "80000000-0000-4000-8000-000000000008",
                scopeType: "profile",
                scopeKey: "30000000-0000-4000-8000-000000000003",
                mode: "require_protected",
                policyId: "warp-default",
                allowFallback: false,
                revision: 3
            }]
        })

        signal liveEgressChanged()
        signal loadingChanged()
        signal requestFailed(string endpoint, string error)

        function refreshIndex() { refreshIndexCalls += 1 }
        function selectCatalog(providerId, catalogId, filters) {
            selectedProviderId = providerId
            selectedCatalogId = catalogId
            selectCatalogCalls += 1
        }
        function refreshPage() {}
        function loadMoreItems() {}
        function loadItem(providerId, itemKey) { loadItemCalls += 1 }
        function cancelItemRequest() { itemLoading = false }
        function cancel() { itemLoading = false }
        function fetchLiveEgressStatus() { fetchLiveEgressCalls += 1 }
        function updateLiveEgressPolicy(scopeType, scopeId, mode, policyId,
                                        allowFallback, expectedRevision) {}
    }

    Component {
        id: liveViewComponent
        Views.LiveView {}
    }

    Component {
        id: detailsViewComponent
        Views.LiveDetailsView {}
    }

    Component {
        id: filterBarComponent
        Components.LiveFilterBar {}
    }

    Component {
        id: eventCardComponent
        Components.LiveEventCard {}
    }

    SignalSpy {
        id: itemRequestedSpy
        signalName: "itemRequested"
    }

    function resetMock() {
        rows.clear()
        mock.providers = []
        mock.catalogs = []
        mock.selectedProviderId = ""
        mock.selectedCatalogId = ""
        mock.catalogIndexLoading = false
        mock.pageLoading = false
        mock.loadingMore = false
        mock.itemLoading = false
        mock.hasMore = false
        mock.stale = false
        mock.partial = false
        mock.errors = []
        mock.lastError = ({})
        mock.selectedItem = ({})
        mock.selectedStreams = []
        mock.refreshIndexCalls = 0
        mock.selectCatalogCalls = 0
        mock.loadItemCalls = 0
        mock.homeRole = "owner"
        mock.capabilities = ["live_manage", "settings_manage"]
        mock.liveEgressLoading = false
        mock.fetchLiveEgressCalls = 0
        itemRequestedSpy.target = null
        itemRequestedSpy.clear()
    }

    function init() { resetMock() }

    function readyFixture() {
        mock.providers = [{
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "instanceId": "80000000-0000-4000-8000-000000000008",
            "extensionId": "fixture.live.provider",
            "name": "Fixture Sports",
            "readiness": "ready",
            "accountState": "not_required"
        }]
        mock.catalogs = [{
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "catalogId": "live_events",
            "name": "Live Now",
            "filters": []
        }]
    }

    function multiProviderFixture() {
        mock.providers = [{
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "instanceId": "80000000-0000-4000-8000-000000000008",
            "extensionId": "fixture.live.pluto",
            "name": "Pluto TV",
            "readiness": "ready",
            "accountState": "connected"
        }, {
            "providerId": "1b7f0fce-03be-4ccc-922a-701fb931db6e",
            "instanceId": "90000000-0000-4000-8000-000000000009",
            "extensionId": "fixture.live.sports",
            "name": "Live Sports Streams",
            "readiness": "ready",
            "accountState": "not_required"
        }]
        mock.catalogs = [{
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "catalogId": "channels",
            "name": "Channels",
            "filters": []
        }, {
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "catalogId": "guide",
            "name": "Guide",
            "filters": []
        }, {
            "providerId": "1b7f0fce-03be-4ccc-922a-701fb931db6e",
            "catalogId": "live_now",
            "name": "Live Now",
            "filters": []
        }, {
            "providerId": "1b7f0fce-03be-4ccc-922a-701fb931db6e",
            "catalogId": "today",
            "name": "Today",
            "filters": []
        }]
    }

    function appendLongEvent() {
        rows.append({
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "itemKey": "lvk1.item.fixture-key-value",
            "itemType": "event",
            "title": "An intentionally long championship event title that must remain inside its card at every supported viewport",
            "subtitle": "A long provider-defined league and venue subtitle",
            "description": "Fixture description",
            "status": "live",
            "startsAtLocal": new Date("2026-07-10T20:00:00Z"),
            "endsAtLocal": new Date("2026-07-10T22:00:00Z"),
            "poster": ({}),
            "background": ({}),
            "logo": ({}),
            "categories": ["Football"],
            "badges": ["Live"],
            "facts": []
        })
    }

    function createLiveView(width, height) {
        return createTemporaryObject(liveViewComponent, host, {
            "width": width,
            "height": height,
            "liveModel": mock,
            "client": mock,
            "itemsModel": rows,
            "serverBaseUrl": ""
        })
    }

    function test_loading_empty_and_unavailable_states() {
        mock.catalogIndexLoading = true
        var loadingView = createLiveView(900, 600)
        verify(loadingView)
        compare(findChild(loadingView, "liveIndexLoading").visible, true)

        mock.catalogIndexLoading = false
        var emptyView = createLiveView(900, 600)
        verify(emptyView)
        compare(findChild(emptyView, "liveEmptyProviders").visible, true)

        mock.providers = [{"providerId": "fixture", "name": "Offline", "readiness": "unavailable"}]
        var unavailableView = createLiveView(900, 600)
        verify(unavailableView)
        compare(findChild(unavailableView, "liveProvidersUnavailable").visible, true)

        readyFixture()
        mock.catalogs = []
        var noCatalogView = createLiveView(900, 600)
        verify(noCatalogView)
        compare(findChild(noCatalogView, "liveEmptyCatalogs").visible, true)

        readyFixture()
        mock.selectedProviderId = "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d"
        mock.selectedCatalogId = "live_events"
        var noEventsView = createLiveView(900, 600)
        verify(noEventsView)
        compare(findChild(noEventsView, "liveEmptyPage").visible, true)
    }

    function test_unavailable_provider_retries_until_catalogs_become_ready() {
        mock.providers = [{
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "name": "Starting provider",
            "readiness": "unavailable"
        }]
        var view = createTemporaryObject(liveViewComponent, host, {
            "width": 900,
            "height": 600,
            "liveModel": mock,
            "client": mock,
            "itemsModel": rows,
            "serverBaseUrl": "",
            "startupRefreshIntervalMs": 20,
            "startupRefreshMaxAttempts": 2
        })
        verify(view)
        compare(mock.refreshIndexCalls, 0)
        tryVerify(function() { return mock.refreshIndexCalls > 0 }, 500)
        verify(findChild(view, "liveStartupRefreshTimer"))

        view.destroy()
        resetMock()
        readyFixture()
        mock.catalogs = []
        var emptyReadyView = createTemporaryObject(liveViewComponent, host, {
            "width": 900,
            "height": 600,
            "liveModel": mock,
            "client": mock,
            "itemsModel": rows,
            "serverBaseUrl": "",
            "startupRefreshIntervalMs": 20,
            "startupRefreshMaxAttempts": 2
        })
        verify(emptyReadyView)
        wait(100)
        compare(mock.refreshIndexCalls, 0)
    }

    function test_catalog_selection_waits_for_index_reconciliation() {
        readyFixture()
        mock.catalogIndexLoading = true
        var view = createLiveView(900, 600)
        verify(view)
        compare(mock.selectCatalogCalls, 0)

        mock.catalogIndexLoading = false
        mock.loadingChanged()
        tryVerify(function() { return mock.selectCatalogCalls === 1 })
        compare(mock.selectedCatalogId, "live_events")
    }

    function test_single_provider_keeps_provider_navigation_hidden() {
        readyFixture()
        var view = createLiveView(900, 600)
        verify(view)

        var providerTabs = findChild(view, "liveProviderTabs")
        var catalogTabs = findChild(view, "liveCatalogTabs")
        tryCompare(providerTabs, "count", 1)
        compare(providerTabs.visible, false)
        tryCompare(catalogTabs, "count", 1)
        compare(catalogTabs.visible, true)
        tryCompare(mock, "selectedCatalogId", "live_events")
    }

    function test_multi_provider_navigation_scopes_and_restores_catalogs() {
        multiProviderFixture()
        var view = createLiveView(1100, 700)
        verify(view)

        var providerTabs = findChild(view, "liveProviderTabs")
        var catalogTabs = findChild(view, "liveCatalogTabs")
        tryCompare(providerTabs, "count", 2)
        compare(providerTabs.visible, true)
        tryCompare(mock, "selectedProviderId",
                   "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d")
        tryCompare(mock, "selectedCatalogId", "channels")
        tryCompare(catalogTabs, "count", 2)
        tryVerify(function() {
            return catalogTabs.itemAtIndex(0)
                    && catalogTabs.itemAtIndex(0).text === "Channels"
                    && catalogTabs.itemAtIndex(1)
                    && catalogTabs.itemAtIndex(1).text === "Guide"
        })

        mouseClick(catalogTabs.itemAtIndex(1))
        tryCompare(mock, "selectedCatalogId", "guide")

        mouseClick(providerTabs.itemAtIndex(1))
        tryCompare(mock, "selectedProviderId",
                   "1b7f0fce-03be-4ccc-922a-701fb931db6e")
        tryCompare(mock, "selectedCatalogId", "live_now")
        tryVerify(function() {
            return catalogTabs.itemAtIndex(0)
                    && catalogTabs.itemAtIndex(0).text === "Live Now"
                    && catalogTabs.itemAtIndex(1)
                    && catalogTabs.itemAtIndex(1).text === "Today"
        })
        mouseClick(catalogTabs.itemAtIndex(1))
        tryCompare(mock, "selectedCatalogId", "today")

        mouseClick(providerTabs.itemAtIndex(0))
        tryCompare(mock, "selectedProviderId",
                   "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d")
        tryCompare(mock, "selectedCatalogId", "guide")
        tryVerify(function() {
            return catalogTabs.itemAtIndex(0)
                    && catalogTabs.itemAtIndex(0).text === "Channels"
        })

        mouseClick(providerTabs.itemAtIndex(1))
        tryCompare(mock, "selectedCatalogId", "today")
        var callsBeforeRefresh = mock.selectCatalogCalls
        mock.catalogIndexLoading = true
        mock.loadingChanged()
        mock.catalogs = mock.catalogs.slice(0)
        mock.catalogIndexLoading = false
        mock.loadingChanged()
        compare(mock.selectedProviderId,
                "1b7f0fce-03be-4ccc-922a-701fb931db6e")
        compare(mock.selectedCatalogId, "today")
        compare(mock.selectCatalogCalls, callsBeforeRefresh)
        compare(providerTabs.itemAtIndex(1).Accessible.name,
                "Live Sports Streams Live provider")
    }

    function test_failed_provider_does_not_hide_ready_provider() {
        mock.providers = [{
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "name": "Pluto TV",
            "readiness": "unavailable",
            "disabledReason": "Provider timed out"
        }, {
            "providerId": "1b7f0fce-03be-4ccc-922a-701fb931db6e",
            "name": "Live Sports Streams",
            "readiness": "ready"
        }]
        mock.catalogs = [{
            "providerId": "1b7f0fce-03be-4ccc-922a-701fb931db6e",
            "catalogId": "live_now",
            "name": "Live Now",
            "filters": []
        }]
        mock.partial = true
        mock.errors = [{
            "code": "LIVE_PROVIDER_TIMEOUT",
            "message": "Provider timed out",
            "retryable": true,
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d"
        }]

        var view = createLiveView(1000, 700)
        verify(view)
        tryCompare(mock, "selectedProviderId",
                   "1b7f0fce-03be-4ccc-922a-701fb931db6e")
        tryCompare(mock, "selectedCatalogId", "live_now")

        var providerTabs = findChild(view, "liveProviderTabs")
        var catalogTabs = findChild(view, "liveCatalogTabs")
        tryCompare(providerTabs, "count", 2)
        tryVerify(function() {
            return providerTabs.itemAtIndex(0) && providerTabs.itemAtIndex(1)
        })
        compare(providerTabs.itemAtIndex(0).enabled, false)
        compare(providerTabs.itemAtIndex(1).enabled, true)
        verify(providerTabs.itemAtIndex(0).Accessible.description.indexOf(
                   "Provider timed out") >= 0)
        tryCompare(catalogTabs, "count", 1)
        tryCompare(catalogTabs.itemAtIndex(0), "text", "Live Now")
        tryCompare(findChild(view, "liveNoticeBanner"), "visible", true)
    }

    function test_partial_stale_and_error_notice_states() {
        readyFixture()
        mock.partial = true
        mock.errors = [{
            "code": "LIVE_PROVIDER_TIMEOUT",
            "message": "Provider timed out",
            "retryable": true,
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d"
        }]
        var view = createLiveView(900, 600)
        verify(view)
        tryCompare(findChild(view, "liveNoticeBanner"), "visible", true)
        verify(findChild(view, "liveNoticeText").text.indexOf("Fixture Sports") >= 0)
        mock.errors = []
        mock.partial = false
        mock.stale = true
        compare(findChild(view, "liveNoticeBanner").visible, false)
        appendLongEvent()
        tryCompare(findChild(view, "liveEventGrid"), "count", 1)
        tryCompare(findChild(view, "liveNoticeBanner"), "visible", true)
        rows.clear()
        tryCompare(findChild(view, "liveEventGrid"), "count", 0)
        mock.stale = false
        mock.lastError = {"code": "LIVE_PROVIDER_TIMEOUT", "message": "Provider timed out", "retryable": true}
        compare(findChild(view, "liveNoticeBanner").visible, false)
        tryCompare(findChild(view, "livePageError"), "visible", true)
        verify(findChild(view, "livePageContent").height > 0)
    }

    function test_account_required_states_use_native_connect_and_reconnect_copy() {
        mock.providers = [{
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "instanceId": "80000000-0000-4000-8000-000000000008",
            "extensionId": "fixture.live.provider",
            "name": "Fixture Premium",
            "readiness": "needs_account",
            "accountState": "needs_account"
        }]
        var missing = createLiveView(900, 600)
        verify(missing)
        var unavailable = findChild(missing, "liveProvidersUnavailable")
        tryCompare(unavailable, "visible", true)
        compare(unavailable.title, "Live provider needs an account")
        compare(unavailable.actionText, "Connect account")

        mock.providers = [{
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "instanceId": "80000000-0000-4000-8000-000000000008",
            "extensionId": "fixture.live.provider",
            "name": "Fixture Premium",
            "readiness": "ready",
            "accountState": "connected"
        }]
        mock.catalogs = [{
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "catalogId": "premium",
            "name": "Premium",
            "filters": []
        }]
        mock.selectedProviderId = "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d"
        mock.selectedCatalogId = "premium"
        mock.lastError = {
            "code": "LIVE_ACCOUNT_REQUIRED",
            "message": "Connect or reconnect this Live provider account.",
            "retryable": false,
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d"
        }
        var rejected = createLiveView(900, 600)
        verify(rejected)
        var pageError = findChild(rejected, "livePageError")
        tryCompare(pageError, "visible", true)
        compare(pageError.title, "Live provider needs an account")
        compare(pageError.actionText, "Reconnect account")
    }

    function test_event_card_keyboard_accessibility_and_long_text() {
        readyFixture()
        appendLongEvent()
        var view = createLiveView(360, 640)
        verify(view)
        var grid = findChild(view, "liveEventGrid")
        tryCompare(grid, "count", 1)
        var card = findChild(view, "liveEventCard")
        verify(card)
        tryVerify(function() { return card.width > 0 && card.width <= grid.width }, 1000)
        verify(card.contentFits)
        compare(card.Accessible.name.indexOf("championship") >= 0, true)
        compare(card.Accessible.name, liveAccessibilityGolden.eventCard)
        compare(findChild(view, "liveRefreshButton").Accessible.name,
                liveAccessibilityGolden.refresh)
        compare(findChild(view, "liveCatalogTab").Accessible.name,
                liveAccessibilityGolden.catalogTab)
        itemRequestedSpy.target = view
        testWindow.requestActivate()
        tryCompare(testWindow, "active", true)
        card.forceActiveFocus()
        tryCompare(card, "activeFocus", true)
        keyClick(Qt.Key_Space)
        compare(itemRequestedSpy.count, 1)
        compare(itemRequestedSpy.signalArguments[0][1], "lvk1.item.fixture-key-value")
    }

    function test_unknown_channel_status_is_not_exposed_as_a_badge() {
        var card = createTemporaryObject(eventCardComponent, host, {
            "width": 300,
            "height": 232,
            "itemData": {
                "itemType": "channel",
                "title": "Fixture Channel",
                "status": "unknown"
            }
        })
        verify(card)
        var statusPill = findChild(card, "liveStatusPill")
        verify(statusPill)
        compare(statusPill.visible, false)
        verify(card.Accessible.description.indexOf("unknown") < 0)

        card.itemData = {
            "itemType": "channel",
            "title": "Fixture Channel",
            "status": "unavailable"
        }
        tryCompare(statusPill, "visible", true)
        compare(statusPill.label, "UNAVAILABLE")
    }

    function test_live_vpn_policy_is_available_from_toolbar() {
        readyFixture()
        var view = createLiveView(900, 700)
        verify(view)
        compare(mock.fetchLiveEgressCalls, 1)

        var button = findChild(view, "liveEgressPolicyButton")
        verify(button.visible)
        compare(button.text, "VPN: Required")
        verify(button.Accessible.name.indexOf("VPN: Required") >= 0)

        mouseClick(button)
        var popup = findChild(view, "liveEgressPolicyPopup")
        tryCompare(popup, "opened", true)
        verify(findChild(view, "liveToolbarNetworkSettings"))
        compare(findChild(view, "liveEgressScopeCombo").currentIndex, 1)
        compare(findChild(view, "liveEgressModeCombo").currentIndex, 2)
        verify(popup.width <= view.width)
        verify(popup.height <= view.height)

        popup.close()
        mock.homeRole = "admin"
        tryCompare(button, "visible", false)
    }

    function test_responsive_card_geometry_data() {
        return [
            {"tag": "mobile", "width": 360, "height": 640},
            {"tag": "tablet", "width": 800, "height": 700},
            {"tag": "desktop", "width": 1440, "height": 900},
            {"tag": "1080p", "width": 1920, "height": 1080},
            {"tag": "1440p", "width": 2560, "height": 1440},
            {"tag": "4k", "width": 3840, "height": 2160}
        ]
    }

    function test_responsive_card_geometry(data) {
        readyFixture()
        appendLongEvent()
        var view = createLiveView(data.width, data.height)
        verify(view)
        var grid = findChild(view, "liveEventGrid")
        tryCompare(grid, "count", 1)
        var card = findChild(view, "liveEventCard")
        tryVerify(function() { return card.width > 0 && card.width <= grid.width }, 1000)
        verify(card.x >= 0)
        verify(card.x + card.width <= grid.width + 1)
    }

    function test_extension_filter_types_render_native_controls() {
        var bar = createTemporaryObject(filterBarComponent, host, {
            "width": 1000,
            "definitions": [
                {"id": "featured", "label": "Featured", "type": "toggle", "options": []},
                {"id": "league", "label": "League", "type": "single_select", "options": [{"label": "A", "value": "a"}]},
                {"id": "sport", "label": "Sport", "type": "multi_select", "options": [{"label": "Football", "value": "football"}]},
                {"id": "query", "label": "Search", "type": "search", "options": []},
                {"id": "date", "label": "Date", "type": "date", "options": []}
            ]
        })
        verify(bar)
        verify(findChild(bar, "liveFilterToggle"))
        verify(findChild(bar, "liveFilterSingle"))
        verify(findChild(bar, "liveFilterMulti"))
        verify(findChild(bar, "liveFilterSearch"))
        verify(findChild(bar, "liveFilterDate"))
    }

    function test_malicious_metadata_is_rendered_as_plain_text() {
        readyFixture()
        mock.providers = [{
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "name": "<img src=x onerror=alert(1)>",
            "readiness": "ready"
        }]
        rows.append({
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "itemKey": "lvk1.item.malicious-fixture",
            "itemType": "event",
            "title": "<b>Provider markup must remain text</b>",
            "subtitle": "<a href='https://evil.invalid'>not a link</a>",
            "description": "plain",
            "status": "live",
            "startsAtLocal": new Date("2026-07-10T20:00:00Z"),
            "endsAtLocal": new Date("2026-07-10T22:00:00Z"),
            "poster": ({}), "background": ({}), "logo": ({}),
            "categories": [], "badges": [], "facts": []
        })
        var view = createLiveView(800, 700)
        verify(view)
        tryCompare(findChild(view, "liveEventGrid"), "count", 1)
        var title = findChild(view, "liveEventTitle")
        var source = findChild(view, "liveEventSource")
        compare(title.text, "<b>Provider markup must remain text</b>")
        compare(title.textFormat, Text.PlainText)
        compare(source.text, "<img src=x onerror=alert(1)>")
        compare(source.textFormat, Text.PlainText)
    }

    function test_theme_meets_normal_text_contrast() {
        function linear(channel) {
            return channel <= 0.03928 ? channel / 12.92
                                      : Math.pow((channel + 0.055) / 1.055, 2.4)
        }
        function luminance(color) {
            return 0.2126 * linear(color.r) + 0.7152 * linear(color.g)
                   + 0.0722 * linear(color.b)
        }
        function contrast(a, b) {
            var high = Math.max(luminance(a), luminance(b))
            var low = Math.min(luminance(a), luminance(b))
            return (high + 0.05) / (low + 0.05)
        }
        verify(contrast(Theme.textPrimary, Theme.appBg) >= 4.5)
        verify(contrast(Theme.textSecondary, Theme.appBg) >= 4.5)
        verify(contrast(Theme.textMuted, Theme.appBg) >= 4.5)
    }

    function test_details_loading_error_and_long_metadata() {
        mock.itemLoading = true
        var loading = createTemporaryObject(detailsViewComponent, host, {
            "width": 360,
            "height": 640,
            "liveModel": mock,
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "itemKey": "lvk1.item.fixture-key-value"
        })
        verify(loading)
        compare(findChild(loading, "liveDetailsLoading").visible, true)

        mock.itemLoading = false
        mock.lastError = {"message": "Details unavailable", "retryable": true}
        var errorView = createTemporaryObject(detailsViewComponent, host, {
            "width": 800,
            "height": 700,
            "liveModel": mock,
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "itemKey": "lvk1.item.fixture-key-value"
        })
        verify(errorView)
        compare(findChild(errorView, "liveDetailsError").visible, true)

        mock.lastError = ({})
        mock.selectedItem = {
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "itemKey": "lvk1.item.fixture-key-value",
            "title": "An extremely long live event title that wraps without covering controls or adjacent event metadata",
            "subtitle": "International fixture",
            "description": "A provider-defined description with enough text to verify wrapping across narrow and wide details layouts without escaping its content column.",
            "status": "live",
            "startsAtLocal": new Date("2026-07-10T20:00:00Z"),
            "badges": ["Live"],
            "facts": [{"label": "Commentary", "value": "English"}],
            "poster": null,
            "background": null
        }
        mock.selectedStreams = [{"label": "Primary", "quality": "1080p", "language": "en", "protocolHint": "hls"}]
        var details = createTemporaryObject(detailsViewComponent, host, {
            "width": 360,
            "height": 640,
            "liveModel": mock,
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "itemKey": "lvk1.item.fixture-key-value"
        })
        verify(details)
        compare(findChild(details, "liveDetailsBack").Accessible.name,
                liveAccessibilityGolden.back)
        var title = findChild(details, "liveDetailsTitle")
        var description = findChild(details, "liveDetailsDescription")
        verify(title.width <= details.width)
        verify(description.width <= details.width)
        compare(findChild(details, "liveDetailsContent").visible, true)

        mock.selectedStreams = []
        var noStreams = createTemporaryObject(detailsViewComponent, host, {
            "width": 800,
            "height": 700,
            "liveModel": mock,
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "itemKey": "lvk1.item.fixture-key-value"
        })
        verify(noStreams)
        var noStreamsState = findChild(noStreams, "liveDetailsNoStreams")
        compare(noStreamsState.visible, true)
        var beforeRefresh = mock.loadItemCalls
        noStreamsState.actionRequested()
        compare(mock.loadItemCalls, beforeRefresh + 1)
    }

    function test_visual_evidence() {
        if (c12CaptureDir === "") skip("Visual capture directory was not requested")
        readyFixture()
        appendLongEvent()

        testWindow.width = 360
        testWindow.height = 640
        var mobile = createLiveView(360, 640)
        verify(mobile)
        tryCompare(findChild(mobile, "liveEventGrid"), "count", 1)
        wait(20)
        var mobileImage = grabImage(mobile)
        compare(mobileImage.width, 360)
        compare(mobileImage.height, 640)
        mobileImage.save(c12CaptureDir + "/live-mobile.png")
        mobile.destroy()
        wait(0)

        testWindow.width = 1440
        testWindow.height = 900
        var desktop = createLiveView(1440, 900)
        verify(desktop)
        tryCompare(findChild(desktop, "liveEventGrid"), "count", 1)
        wait(20)
        var desktopImage = grabImage(desktop)
        compare(desktopImage.width, 1440)
        compare(desktopImage.height, 900)
        desktopImage.save(c12CaptureDir + "/live-desktop.png")
        desktop.destroy()
        wait(0)

        mock.selectedItem = {
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "itemKey": "lvk1.item.fixture-key-value",
            "title": "International Championship: Home Club versus Visiting Club",
            "subtitle": "Fixture League / Main Stadium",
            "description": "Provider-defined event metadata remains readable across compact viewports.",
            "status": "live",
            "startsAtLocal": new Date("2026-07-10T20:00:00Z"),
            "badges": ["Live", "English"],
            "facts": [{"label": "Commentary", "value": "English"}],
            "poster": ({}),
            "background": ({})
        }
        mock.selectedStreams = [{"label": "Primary", "quality": "1080p", "language": "en", "protocolHint": "hls"}]
        testWindow.width = 360
        testWindow.height = 640
        var details = createTemporaryObject(detailsViewComponent, host, {
            "width": 360,
            "height": 640,
            "liveModel": mock,
            "providerId": "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d",
            "itemKey": "lvk1.item.fixture-key-value"
        })
        verify(details)
        wait(20)
        var detailsImage = grabImage(details)
        compare(detailsImage.width, 360)
        compare(detailsImage.height, 640)
        detailsImage.save(c12CaptureDir + "/live-details-mobile.png")
    }

    function test_multi_provider_visual_evidence() {
        if (c12CaptureDir === "") skip("Visual capture directory was not requested")
        multiProviderFixture()
        appendLongEvent()

        testWindow.width = 1440
        testWindow.height = 900
        var desktop = createLiveView(1440, 900)
        verify(desktop)
        var providerTabs = findChild(desktop, "liveProviderTabs")
        var catalogTabs = findChild(desktop, "liveCatalogTabs")
        tryCompare(providerTabs, "count", 2)
        tryCompare(catalogTabs, "count", 2)
        wait(20)
        var desktopImage = grabImage(desktop)
        desktopImage.save(c12CaptureDir + "/live-multi-provider-desktop.png")
        desktop.destroy()
        wait(0)

        resetMock()
        multiProviderFixture()
        appendLongEvent()
        testWindow.width = 360
        testWindow.height = 640
        var mobile = createLiveView(360, 640)
        verify(mobile)
        tryCompare(findChild(mobile, "liveProviderTabs"), "count", 2)
        tryCompare(findChild(mobile, "liveCatalogTabs"), "count", 2)
        wait(20)
        var mobileImage = grabImage(mobile)
        mobileImage.save(c12CaptureDir + "/live-multi-provider-mobile.png")
    }
}
