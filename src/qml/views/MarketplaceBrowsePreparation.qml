import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import "../components"
import Elixir 1.0

// First usable page, then optional bounded background catalog preparation. No separate
// queue, readiness receipt, persisted result, or install/source authority.
ColumnLayout {
    id: root
    objectName: "marketplaceBrowsePreparation"
    property var client: apiClient
    property bool allowed: false
    property bool compact: false
    property bool fullCatalog: false
    property var snapshot: ({})
    property bool attempted: false
    property string failure: ""
    readonly property bool active: visible && allowed && client.authToken !== ""
        && Qt.application.state === Qt.ApplicationActive
    readonly property bool connected: snapshot.runtime_fresh === true
        && snapshot.runtime_status === "running" && snapshot.participation_applied === true
        && ((snapshot.runtime || {}).participation || {}).phase === "running"
        && (((snapshot.runtime || {}).participation || {}).applied_roles || {}).consumer === true
    // Startup recovery is scheduling data, not protected-connection authority.
    // An initial consent/configuration failure may still have its ONE retry
    // owner. Do not call it terminal while that owner is active.
    readonly property bool recoveringConnection: snapshot.runtime_fresh === true
        && ["failed", "stopped"].indexOf(snapshot.runtime_status) >= 0
        && (snapshot.startup || {}).configured === true
        && (snapshot.startup || {}).retry_owner_present === true
    readonly property bool terminalConnection: snapshot.runtime_fresh === true && !recoveringConnection
        && ["failed", "stopped"].indexOf(snapshot.runtime_status) >= 0
    readonly property var response: client.marketplaceSearch || ({})
    readonly property var query: response.query || ({})
    readonly property var preparation: response.preparation || ({})
    readonly property bool catalogProgressValid: !fullCatalog || (preparation.schema_version === 1
        && preparation.scope === "current_local_catalog"
        && ["checking", "discovering", "waiting", "complete", "limited", "unavailable"].indexOf(preparation.phase) >= 0
        && typeof preparation.local_pass_complete === "boolean"
        && preparation.local_pass_complete === (preparation.phase === "complete") && preparation.network_complete === false
        && preparation.metadata_only === true)
    readonly property bool preparingCatalog: fullCatalog && catalogProgressValid
        && ["checking", "discovering", "waiting"].indexOf(preparation.phase) >= 0
    // Native QVariantList values are Qt sequence objects, not JS Arrays.
    readonly property bool firstPage: query.text === "" && query.tags !== null
        && typeof query.tags === "object"
        && query.tags.length === 0 && query.limit === 20
        && typeof response.query_id === "string" && response.query_id !== ""
    readonly property bool busy: client.marketplaceSearchLoading === true
    readonly property bool checking: firstPage && response.phase === "checking"
    readonly property int checkedCount: firstPage ? client.marketplaceSearchAvailableCount : 0
    // A checked prefix is usable while the remaining candidates are pending.
    // Neither this nor a completed first page claims complete network coverage.
    readonly property bool firstResultsReady: connected && firstPage && catalogProgressValid
        && ["checking", "ready"].indexOf(response.phase) >= 0 && checkedCount > 0
        && !busy && failure === ""
    // A finished empty attempt is actionable now, not after its receipt ages
    // into "stale". This is NOT proof that the network has no extensions.
    readonly property bool terminalEmpty: !busy && checkedCount === 0 && (failure !== ""
        || ["unavailable", "stale"].indexOf(response.phase) >= 0
        || (firstPage && response.phase === "ready" && catalogProgressValid && !preparingCatalog))
    visible: allowed
    spacing: 8

    function start() {
        if (!active || !connected || busy) return
        attempted = true
        failure = ""
        client.startMarketplaceSearch("", [], "", fullCatalog)
    }
    function prepareOnce() {
        // Do not replace an existing browse, a failed attempt, or another
        // view's query just because a five-second status poll arrived.
        if (active && connected && !attempted && !busy && !response.phase) start()
    }
    function summary() {
        if (terminalConnection) return "Protected marketplace networking is unavailable. Review connection settings or use Elixir for now."
        if (recoveringConnection) return recoverySummary()
        if (!connected) return "Extension browsing will prepare after protected networking connects."
        if (failure !== "") return failure
        if (terminalEmpty && firstPage && response.phase === "ready") return emptySummary()
        if (checking) return checkedCount > 0
            ? checkedCount + " checked listings available for browsing. Checking more listings…"
            : "Preparing the first browse page: checking public source and paid support…"
        if (firstPage && response.phase === "ready") return checkedCount > 0
            ? checkedCount + " checked listings available for browsing. More results may still be available."
                + (preparingCatalog ? " Remaining preparation continues in the background." : "")
            : preparingCatalog ? "No checked listings on this page yet. " + catalogSummary()
                : "No checked listings on this page. This is not a complete marketplace scan."
        if (response.phase === "stale") return "Browse checks expired. Prepare again to refresh."
        if ((firstPage || attempted) && response.phase === "unavailable")
            return "Browse preparation was not confirmed. Check the connection, or try again."
        return "Prepare the first checked page before opening community extensions."
    }
    function compactSummary() {
        if (terminalConnection) return "Protected connection unavailable. Review connection settings, or use Elixir for now."
        if (recoveringConnection) return recoverySummary()
        if (!connected) return "Waiting for protected marketplace networking."
        if (failure !== "" || response.phase === "unavailable") return "Browse checks were not confirmed. Try again."
        if (terminalEmpty && firstPage && response.phase === "ready") return emptySummary()
        if (checking) return checkedCount > 0 ? checkedCount + " checked listings ready. Checking more listings…" : "Checking available extensions…"
        if (firstPage && response.phase === "ready") return checkedCount > 0
            ? "First browse page prepared: " + checkedCount + " checked listings."
                + (preparingCatalog ? " More preparation continues in the background." : "")
            : preparingCatalog ? "No checked extensions found yet. " + catalogSummary()
                : "No checked extensions found yet. You can use Elixir for now."
        if (response.phase === "stale") return "Browse checks expired. Prepare them again."
        return "Prepare the first checked browse page."
    }
    function recoverySummary() {
        var seconds = (snapshot.startup || {}).retry_after_seconds
        return typeof seconds === "number" && seconds >= 0 && seconds <= 300
            ? "Protected connection retry scheduled in up to " + Math.ceil(seconds) + " seconds. Browsing is not ready."
            : "Protected connection recovery is active. Browsing is not ready."
    }
    function emptySummary() {
        if (fullCatalog && preparation.phase === "unavailable")
            return "Browse preparation was not confirmed. No checked extensions are ready. Retry browse checks, or use Elixir for now."
        if (fullCatalog && preparation.phase === "limited")
            return "Preparation reached its work limit with no checked extensions ready. Retry browse checks, or use Elixir for now."
        return "No checked extensions were found from the peers reached. Retry browse checks, or use Elixir for now. This is not a complete marketplace scan."
    }
    function catalogSummary() {
        if (preparation.phase === "discovering") return "Loading extension listings: "
            + (typeof preparation.received === "number" ? preparation.received : 0) + " records received. Source checks follow."
        if (preparation.phase === "waiting") return "Background preparation paused for playback or other work. It will resume when resources are available."
        if (preparation.phase === "limited") return "Preparation reached its work limit. You can retry or use Elixir for now."
        if (preparation.phase === "unavailable") return "Further preparation was not confirmed. Checked listings are independent; retry to refresh."
        var count = typeof preparation.examined === "number" ? preparation.examined : 0
        return "Preparing the known local catalog: " + count + " listings checked. Public-source checks may take time."
    }
    onActiveChanged: if (active) Qt.callLater(prepareOnce)
    onConnectedChanged: if (connected) Qt.callLater(prepareOnce)
    Component.onCompleted: Qt.callLater(prepareOnce)
    Connections {
        target: root.client
        function onSessionStateChanged() { root.attempted = false; root.failure = "" }
        function onRequestFailed(endpoint, error) {
            if (root.active && root.attempted && (endpoint === "/api/v1/marketplace/search"
                || endpoint.indexOf("/api/v1/marketplace/search/") === 0))
                root.failure = "Browse preparation was not confirmed. Try preparing again."
        }
    }
    Timer {
        interval: 1000; repeat: true
        running: root.active && root.connected && root.failure === "" && (root.checking || root.preparingCatalog) && !root.busy
        onTriggered: root.client.pollMarketplaceSearch()
    }
    Label {
        objectName: "marketplaceBrowsePreparationStatus"
        Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
        color: Theme.textSecondary
        text: root.compact ? root.compactSummary() : root.summary()
    }
    ActionButton {
        objectName: "marketplacePrepareBrowsing"
        visible: !root.compact || (!root.checking && (root.failure !== "" || root.response.phase === "unavailable"
            || root.response.phase === "stale" || (!!root.response.phase && (!root.firstPage || !root.catalogProgressValid
                || (root.checkedCount === 0 && !root.preparingCatalog)))))
        text: root.compact ? "Retry browse checks" : root.checking ? "Preparing browsing…" : "Prepare browsing"
        enabled: root.active && root.connected && !root.busy && !root.checking
        onClicked: root.start()
    }
    Label {
        visible: !root.compact
        Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
        color: Theme.textMuted
        text: fullCatalog
            ? "Open after the first checked page. Further preparation may continue for up to one hour, yielding to playback and new searches. This is not a complete network scan. Installation and updates verify source and packages separately."
            : "This checks one page, not the whole network. Installation and updates still verify source and package contents separately."
    }
}
