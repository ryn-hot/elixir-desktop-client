import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    objectName: "communityMarketplaceView"
    property var client: apiClient
    property StackView stackView: null
    property var selectedTags: []
    property string searchFailure: ""
    // Draft/pagination convenience only, never a checked server receipt.
    property var submittedQuery: null
    property bool draftPending: false
    property bool initialRequestAttempted: false
    property string pollingQueryId: ""
    readonly property bool queryChanged: submittedQuery !== null
        && (searchText.text !== submittedQuery.text
            || JSON.stringify(selectedTags.slice().sort()) !== JSON.stringify(submittedQuery.tags.slice().sort()))
    readonly property bool canManage: client.authToken !== ""
        && client.homeRole === "owner" && client.activeProfileType === "account"
        && client.capabilities && client.capabilities.indexOf("extensions_manage") >= 0
        && client.capabilities.indexOf("settings_manage") >= 0 && client.capabilities.indexOf("server_admin") >= 0
    readonly property var response: client.marketplaceSearch || ({})
    readonly property var results: canManage ? (client.marketplaceSearchResults || []) : []
    readonly property bool busy: client.marketplaceSearchLoading === true
    // Presentation only. The server keeps peer lookup/admission running; this
    // is never global completeness or authority to install an unchecked card.
    readonly property bool localSearchComplete: response.local_page_complete === true
    readonly property bool viewActive: visible && canManage
        && Qt.application.state === Qt.ApplicationActive
    readonly property var preparation: response.preparation || ({})
    readonly property bool preparingCatalog: preparation.scope === "current_local_catalog"
        && ["checking", "discovering", "waiting"].indexOf(preparation.phase) >= 0

    function setTag(tag, enabled) {
        var tags = selectedTags.slice()
        if (enabled && tag === "live") tags = ["live"]
        else if (enabled) {
            tags = tags.filter(function(value) { return value !== "live" && value !== tag })
            tags.push(tag)
        } else tags = tags.filter(function(value) { return value !== tag })
        selectedTags = tags
        scheduleSearch(true)
    }
    function scheduleSearch(immediate) {
        if (!canManage || !visible) return
        draftPending = true
        // Clicks are complete choices; only typing needs the debounce delay.
        // The same single timer coalesces edits while an HTTP request is busy.
        searchDebounce.interval = immediate === true ? 0 : 400
        searchDebounce.restart()
    }
    function search(cursor) {
        if (!canManage || busy || client.authToken === "") return
        if (cursor && (submittedQuery === null || queryChanged)) return
        searchDebounce.stop()
        draftPending = false
        if (!cursor) submittedQuery = {text: searchText.text, tags: selectedTags.slice()}
        searchFailure = ""
        client.startMarketplaceSearch(submittedQuery.text, submittedQuery.tags, cursor || "")
    }
    function resetSearch() {
        searchDebounce.stop()
        stopSearchPollWindows()
        pollingQueryId = ""
        draftPending = false
        submittedQuery = null
        selectedTags = []
        searchText.clear()
        searchFailure = ""
        initialRequestAttempted = false
        client.clearMarketplaceSearch()
    }
    function initializeBrowse() {
        if (!viewActive || busy || submittedQuery !== null || initialRequestAttempted) return
        var prepared = response.query || ({})
        if ((response.phase === "checking" || response.phase === "ready")
            && typeof response.query_id === "string" && response.query_id !== ""
            && prepared.text === "" && prepared.tags !== null && typeof prepared.tags === "object"
            && prepared.tags.length === 0
            && prepared.limit === 20) {
            // Retain the SAME checked query/cursor. No new receipt lifetime,
            // source fact, HTTP request or detached preparation owner.
            submittedQuery = {text: "", tags: []}
            initialRequestAttempted = true
            client.acceptMarketplaceSearchResults()
            return
        }
        var settings = client.marketplaceSettings || ({})
        var participation = (settings.runtime || {}).participation || ({})
        if (settings.runtime_fresh === true && settings.runtime_status === "running"
            && settings.participation_applied === true && participation.phase === "running"
            && (participation.applied_roles || {}).consumer === true && !response.phase) {
            initialRequestAttempted = true
            search("")
        }
    }
    onCanManageChanged: if (!canManage) resetSearch()
    function stopSearchPollWindows() {
        firstResultPollWindow.stop()
        pagePollWindow.stop()
    }
    function observePollingQuery() {
        var queryId = typeof response.query_id === "string" ? response.query_id : ""
        var changed = queryId !== pollingQueryId
        pollingQueryId = queryId
        if (changed || response.phase !== "checking" || response.searching_peers === true || localSearchComplete)
            stopSearchPollWindows()
        // Both deadlines start once per new query, never from progress replies.
        // The first reply may already contain partial cards. Give that reply
        // the same bounded first-second burst as an initially empty page so
        // the checked remainder need not wait 250ms between reads.
        // Peer discovery and normal background preparation keep the slow poll.
        if (changed && viewActive && queryId !== "" && response.phase === "checking"
            && response.searching_peers !== true && !localSearchComplete && searchFailure === "") {
            pagePollWindow.start()
            firstResultPollWindow.start()
        }
    }
    onResponseChanged: observePollingQuery()
    onSearchFailureChanged: if (searchFailure !== "") stopSearchPollWindows()
    onViewActiveChanged: {
        if (viewActive) Qt.callLater(initializeBrowse)
        else stopSearchPollWindows()
    }
    onVisibleChanged: {
        if (!visible) { searchDebounce.stop(); stopSearchPollWindows(); draftPending = false }
        else Qt.callLater(initializeBrowse)
    }
    onBusyChanged: if (!busy) {
        if (draftPending && !searchDebounce.running) searchDebounce.start()
        else Qt.callLater(initializeBrowse)
    }
    Component.onCompleted: if (visible && canManage) {
        client.pollMarketplaceSettings()
        Qt.callLater(initializeBrowse)
    }
    Timer {
        interval: 5000; repeat: true
        running: root.visible && root.canManage && !root.client.marketplaceSettingsLoading
            && Qt.application.state === Qt.ApplicationActive
        onTriggered: root.client.pollMarketplaceSettings()
    }
    Timer {
        id: searchDebounce
        objectName: "communitySearchDebounce"
        interval: 400
        onTriggered: if (root.draftPending && root.canManage && root.visible && !root.busy) root.search("")
    }
    Connections {
        target: root.client
        ignoreUnknownSignals: true
        function onSessionStateChanged() { root.resetSearch() }
        function onMarketplaceSettingsChanged() { root.initializeBrowse() }
        function onRequestFailed(endpoint, error) {
            if (root.canManage && (endpoint === "/api/v1/marketplace/search"
                || endpoint.indexOf("/api/v1/marketplace/search/") === 0))
                root.searchFailure = "Search was not confirmed. Try searching again."
        }
    }
    Timer {
        id: firstResultPollWindow
        objectName: "communityFirstResultPollWindow"
        interval: 1000; repeat: false
    }
    Timer {
        id: pagePollWindow
        objectName: "communityPagePollWindow"
        interval: 3000; repeat: false
    }
    Timer {
        objectName: "communitySearchPoll"
        interval: root.response.phase === "checking" || root.preparingCatalog
            ? (root.response.phase === "checking" && firstResultPollWindow.running
                && root.response.searching_peers !== true && !root.localSearchComplete ? 100
                : root.response.phase === "checking" && pagePollWindow.running
                    && root.response.searching_peers !== true && !root.localSearchComplete ? 250 : 1000)
            : 25000
        repeat: true
        running: root.viewActive && !root.busy && root.searchFailure === ""
            && (root.response.phase === "checking" || root.response.phase === "ready")
        onTriggered: root.client.pollMarketplaceSearch()
    }
    Component.onDestruction: { searchDebounce.stop(); client.clearMarketplaceSearch() }

    ScrollView {
        id: scroll
        objectName: "communityScrollView"
        anchors.fill: parent
        contentWidth: availableWidth
        ColumnLayout {
            width: scroll.availableWidth
            spacing: 14
            RowLayout {
                Layout.fillWidth: true
                Button { text: "Back"; visible: root.stackView !== null; onClicked: root.stackView.pop() }
                Label { text: "Community extensions"; font.pixelSize: 24; color: Theme.textPrimary; Layout.fillWidth: true }
                BusyIndicator {
                    objectName: "communitySearchActivity"
                    running: root.busy || (root.response.phase === "checking" && !root.localSearchComplete)
                    visible: running; implicitWidth: 28; implicitHeight: 28
                }
            }
            Label {
                Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                color: Theme.textSecondary
                text: "Listings are checked locally for signed paid support and public source. Popularity is not a safety review. Installation availability is controlled by your server."
            }
            Label {
                objectName: "communityPreparationStatus"
                Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                color: Theme.textSecondary
                visible: root.preparation.scope === "current_local_catalog"
                text: root.preparation.phase === "waiting" ? "Further catalog preparation is paused for playback or other work. Checked results remain independently verified."
                    : root.preparingCatalog ? "Preparing more listings in the background. Browsing is available; this is not a complete network scan."
                    : root.preparation.phase === "complete" ? "The observed local catalog pass finished. This is not complete network coverage."
                    : "Further catalog preparation stopped. Search again to refresh; checked results remain independent."
            }
            MarketplaceInstallationPane { id:installation; Layout.fillWidth:true; client:root.client; canManage:root.canManage }
            MarketplaceCatalogStatus {
                Layout.fillWidth: true
                snapshot: root.client.marketplaceSettings || ({})
                allowed: root.canManage
            }
            MarketplaceDirectReferencePane { Layout.fillWidth:true; client:root.client; canManage:root.canManage
                onInspect: function(preview) { installation.inspectDirect(preview) } }
            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: searchText; objectName: "communitySearchText"; Layout.fillWidth: true
                    placeholderText: "Find an extension"; maximumLength: 256; enabled: root.canManage
                    onAccepted: root.scheduleSearch(true)
                    onTextEdited: root.scheduleSearch()
                }
                Button { objectName: "communitySearchButton"; text: "Search"; enabled: root.canManage; onClicked: root.scheduleSearch(true) }
            }
            Flow {
                Layout.fillWidth: true; spacing: 8
                Repeater {
                    model: [{key:"anime",name:"Anime"},{key:"movies",name:"Movies"},{key:"tv",name:"TV"},{key:"live",name:"Live"}]
                    CheckBox {
                        id: filter
                        required property var modelData
                        objectName: "communityTag_" + modelData.key
                        text: modelData.name; enabled: root.canManage
                        checked: root.selectedTags.indexOf(modelData.key) >= 0
                        onClicked: root.setTag(modelData.key, checked)
                        contentItem: Label {
                            text: filter.text; textFormat: Text.PlainText
                            leftPadding: filter.indicator ? filter.indicator.width + filter.spacing : 0
                            color: filter.enabled ? Theme.textPrimary : Theme.textMuted
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
            Label {
                objectName: "communitySearchNotice"; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                color: Theme.textSecondary
                text: !root.canManage ? "Only the signed-in server owner can browse extensions."
                    : root.searchFailure !== "" ? root.searchFailure
                    : root.queryChanged ? "Updating your search… Current results are from the previous search."
                    : root.response.phase === "unavailable" ? "Protected marketplace checks are unavailable or no candidates passed. Review networking settings and try again."
                    : root.response.phase === "stale" ? "Checks expired or security state changed. Search again to refresh."
                    : root.response.phase === "checking" && root.localSearchComplete
                        ? (root.results.length === 0
                            ? "No checked local matches. Checking community peers in the background…"
                            : "Local search finished. Checking community peers in the background…")
                    : root.response.phase === "checking" && root.response.searching_peers === true
                        ? (root.results.length === 0
                            ? "No checked matches yet. Searching community peers… You can change your search."
                            : "Searching community peers… Checked results remain available.")
                    : root.response.phase === "checking" ? "Checking listings, public source and paid support…"
                    : root.response.phase === "ready" && root.results.length === 0 ? "No checked matches on this page. Peer search and network coverage may be incomplete."
                    : "Search checks your local catalog and community peers. Support scores are partial, not global download totals."
            }
            Button {
                objectName: "communityShowNewResults"
                text: root.client.marketplaceSearchAvailableCount > root.results.length
                    ? "Show all " + root.client.marketplaceSearchAvailableCount + " checked results" : "Refresh displayed order"
                visible: root.client.marketplaceSearchAvailableCount > root.results.length
                    || (root.response.phase === "ready" && root.results.length > 1)
                enabled: root.canManage && !root.busy && root.searchFailure === ""
                onClicked: root.client.acceptMarketplaceSearchResults()
            }
            Repeater {
                model: root.results
                Rectangle {
                    required property var modelData
                    objectName: "communityMarketplaceCard"
                    Layout.fillWidth: true; implicitHeight: card.implicitHeight + 24
                    radius: 8; color: Theme.backgroundCardRaised; border.color: Theme.border
                    ColumnLayout {
                        id: card; anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 6
                        Label { objectName: "communityCardName"; Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
                            text: modelData.name; font.pixelSize: 18; color: Theme.textPrimary }
                        Label { Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
                            text: modelData.publisher + " · " + modelData.version + " · " + modelData.media_tags.join(", "); color: Theme.textSecondary }
                        Label { Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
                            text: modelData.description; color: Theme.textPrimary }
                        Label { objectName: "communityCardSourceVerification"; Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
                            text: "Source match checked on install"; color: Theme.textSecondary }
                        Label { Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
                            text: modelData.extension_id; color: Theme.textSecondary; font.pixelSize: 11 }
                        Label { Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
                            text: modelData.support.verified_supporters + " verified paid supporters · partial score " + modelData.support.weighted_score; color: Theme.textSecondary }
                        // Inspecting a still-current card is read-only. A status
                        // poll must not disable it; ApiClient rechecks freshness
                        // and query ownership, and installation has its own gates.
                        Button { objectName:"communityReviewInstallation"; text:"Review installation"; enabled:root.canManage && !root.client.marketplaceInstallationLoading && root.searchFailure === ""
                            onClicked: { installation.inspect(modelData); if (scroll.contentItem && scroll.contentItem.contentY !== undefined) scroll.contentItem.contentY=0 } }
                    }
                }
            }
            Button {
                objectName: "communityNextPage"
                text: root.response.phase === "unavailable" ? "Try more results" : "Next page"
                visible: !!root.response.next_cursor && (root.response.phase === "ready" || root.response.phase === "unavailable")
                enabled: root.canManage && !root.busy && root.searchFailure === ""
                    && root.submittedQuery !== null && !root.queryChanged
                onClicked: root.search(root.response.next_cursor)
            }
        }
    }
}
