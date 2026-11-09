import QtQuick 6.5
import QtQuick.Controls 6.5
import Elixir 1.0

Label {
    id: root
    objectName: "marketplaceCatalogStatus"
    property var snapshot: ({})
    property bool allowed: false
    visible: allowed
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: Theme.textSecondary
    text: summary()

    function summary() {
        if (!allowed) return ""
        if (snapshot.runtime_fresh === false)
            return "Catalog refresh status is unavailable. Protected searches can still retry."
        if (snapshot.runtime_status !== "running")
            return "Catalog refresh is waiting for protected marketplace networking."
        var state = ((snapshot.runtime || {}).participation || {}).catalog
        if (!state) return "This server does not report catalog refresh progress."
        if (state.phase === "unsupported") return "This worker does not support background catalog refresh."
        if (state.phase === "unavailable" || ((state.phase === "refreshing" || state.phase === "waiting")
            && (state.observed_seconds === null || state.observed_seconds > 30)))
            return "Catalog refresh status is stale or unavailable. Cached listings still need current checks."
        var status = state.phase === "refreshing" ? "Refreshing local catalog metadata."
            : state.phase === "paused" ? "Background catalog refresh is paused by connection, resource or work limits."
            : state.phase === "not_started" ? "Waiting for the first peer metadata refresh."
            : "Local catalog metadata refresh is waiting for its next pass."
        if (state.last_peer_page_seconds !== null && state.last_peer_page_seconds !== undefined)
            status += " Last reported peer-page age: " + state.last_peer_page_seconds + " seconds."
        else status += " No successful peer refresh reported yet."
        return status + " Source checks are separate; this is not complete network coverage."
    }
}
