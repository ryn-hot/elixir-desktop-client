import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import "../components"
import Elixir 1.0

// First owner entry only: existing server preferences remain the decision
// record. No local "setup complete" flag or new readiness/install authority.
Item {
    id: root
    objectName: "marketplaceSetupView"
    property var client: apiClient
    property var stackView: null
    property bool initialized: false
    property bool requested: false
    property bool evaluated: false
    property bool offered: false
    property bool completed: false
    property string failure: ""
    property string pendingDestination: ""
    property string pendingScope: ""
    readonly property string scope: String(client.baseUrl || "") + "|" + String(client.homeId || "")
        + "|" + String(client.activeProfileId || "") + "|" + String(client.sessionId || "")
        + "|" + String(client.capabilityRevision || 0)
    readonly property bool active: visible && !completed && client.authToken !== ""
        && Qt.application.state === Qt.ApplicationActive
    readonly property bool canManage: settingsEditor.canManage
    readonly property var response: client.marketplaceSettings || ({})
    readonly property var preferences: (response.settings || {}).preferences || ({})
    readonly property bool freshSnapshot: settingsEditor.loaded && response.runtime_fresh === true
    readonly property bool decisionSaved: freshSnapshot && (preferences.contribution === "off"
        || (typeof response.contribution_disclosure_version === "number"
            && preferences.contribution_disclosure_version === response.contribution_disclosure_version))
    readonly property bool canPrepare: active && canManage && offered && decisionSaved
        && !settingsEditor.busy && !settingsEditor.dirty && !settingsEditor.revisionConflict
        && client.marketplaceConnectionSaving !== true
    readonly property bool canBrowse: canPrepare && settingsEditor.browsePrepared
    readonly property bool canRetryBrowse: canPrepare && settingsEditor.browseNeedsRetry && settingsEditor.canRetryBrowse

    function resetContext() {
        requested = false; evaluated = false; offered = false; completed = false
        failure = ""; pendingDestination = ""; pendingScope = ""
        settingsEditor.resetEditor()
    }
    function activate() {
        if (!initialized || !active || requested) return
        requested = true
        if (!canManage) requestFinish("home")
        else settingsEditor.refresh() // A fresh read clears old cached settings.
    }
    function evaluateSnapshot() {
        if (!initialized || !active || !requested || evaluated || !canManage
            || client.marketplaceSettingsLoading === true) return
        if (!freshSnapshot) {
            if (settingsEditor.loaded)
                failure = "Marketplace status is stale. Retry setup, or use Elixir for now."
            return
        }
        evaluated = true
        // A returning owner already made this decision. Do not re-block every
        // login, start a new search, or claim their catalog is currently ready.
        if (decisionSaved && !offered) requestFinish("home")
        else offered = true
    }
    function retry() {
        if (!active || !canManage || settingsEditor.busy || settingsEditor.dirty) return
        failure = ""; evaluated = false
        settingsEditor.refresh()
    }
    function retryBrowse() {
        if (canRetryBrowse) settingsEditor.retryBrowse()
    }
    function requestFinish(destination) {
        if (!active || pendingDestination !== "" || !stackView
            || ["home", "browse"].indexOf(destination) < 0
            || (destination === "browse" && !canBrowse)) return
        pendingDestination = destination; pendingScope = scope
        Qt.callLater(tryNavigate)
    }
    function tryNavigate() {
        if (!active || pendingDestination === "" || !stackView || stackView.busy) return
        if (pendingScope !== scope || (pendingDestination === "browse" && !canBrowse)) {
            pendingDestination = ""; pendingScope = ""; return
        }
        var browse = pendingDestination === "browse"
        pendingDestination = ""; pendingScope = ""; completed = true
        // Preserve the exact prepared search for the existing Community view.
        // Deferring changes no consent, contribution, connection or install state.
        stackView.replace(Qt.resolvedUrl(browse ? "CommunityMarketplaceView.qml" : "HomeView.qml"),
            browse ? {stackView:stackView,client:root.client} : {stackView:stackView,sectionFilter:"all"})
    }
    onScopeChanged: if (initialized) { resetContext(); Qt.callLater(activate) }
    onActiveChanged: if (active) {
        Qt.callLater(activate); Qt.callLater(evaluateSnapshot); Qt.callLater(tryNavigate)
    }
    onCanManageChanged: if (initialized) {
        resetContext()
        Qt.callLater(activate)
    }
    Component.onCompleted: { initialized = true; activate() }
    Connections {
        target: root.client
        function onMarketplaceSettingsChanged() { Qt.callLater(root.evaluateSnapshot) }
        function onRequestFailed(endpoint, error) {
            if (root.active && endpoint === "/api/v1/marketplace/settings")
                root.failure = "Marketplace setup could not be loaded. Retry, or use Elixir for now."
        }
    }
    Connections {
        target: root.stackView
        function onBusyChanged() { if (!root.stackView.busy) Qt.callLater(root.tryNavigate) }
    }

    Rectangle { anchors.fill: parent; color: Theme.appBg }
    ScrollView {
        anchors.fill: parent; contentWidth: availableWidth
        anchors.bottomMargin: browseFooter.visible ? browseFooter.height : 0
        ColumnLayout {
            width: Math.max(1, Math.min(760, root.width - 32))
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16
            Item { Layout.preferredHeight: 16 }
            Label {
                Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
                text: "Set up extensions"; color: Theme.textPrimary
                font.family: Theme.fontDisplay; font.pixelSize: 24
            }
            Label {
                Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.textSecondary
                text: "Review marketplace participation and prepare the first checked browse page. Remaining preparation can continue in the background for up to one hour, yielding to playback and new searches. Nothing is installed automatically. You can return to this in Settings."
            }
            BusyIndicator {
                objectName: "marketplaceSetupLoading"
                running: root.active && !root.evaluated && root.failure === ""
                visible: running
            }
            Label {
                objectName: "marketplaceSetupFailure"
                Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.textSecondary
                visible: text !== ""; text: root.failure
            }
            ActionButton {
                objectName: "marketplaceSetupRetry"; text: "Retry setup"
                visible: root.failure !== ""
                enabled: root.active && root.canManage && !settingsEditor.busy && !settingsEditor.dirty
                onClicked: root.retry()
            }
            ActionButton {
                objectName: "marketplaceSetupLater"; text: "Use Elixir for now"
                Layout.fillWidth: true; enabled: root.active
                onClicked: root.requestFinish("home")
            }
            MarketplaceSettingsView {
                id: settingsEditor
                Layout.fillWidth: true
                client: root.client; manageInitialLoad: false; setupMode: true
                prepareBrowsing: root.offered && !root.completed
                visible: root.offered && root.canManage && !root.completed
            }
            Label {
                Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.textMuted
                text: "Leaving does not accept disclosures, enable contribution, or cancel a change you already requested. Existing local media remains usable without the marketplace."
            }
            Item { Layout.preferredHeight: 16 }
        }
    }
    // Keep the prepared page's action on screen rather than below the lengthy
    // participation disclosures. This changes layout only, not readiness.
    Rectangle {
        id: browseFooter
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        visible: root.offered
        height: footerContent.implicitHeight + 24
        color: Theme.appBg
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.border }
        ColumnLayout {
            id: footerContent
            width: Math.max(1, Math.min(760, root.width - 32))
            anchors.horizontalCenter: parent.horizontalCenter; anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Label {
                objectName: "marketplaceSetupReadiness"
                Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.textSecondary
                text: root.canBrowse
                    ? "Checked listings are ready to browse. Remaining checks may continue in the background. This is not a complete network scan."
                    : settingsEditor.browseNeedsRetry || settingsEditor.browseRecovering ? settingsEditor.browseSummary
                    : "Save your participation choice and wait for protected browsing to prepare, or use Elixir for now. An empty page does not prove the marketplace is fully synchronized."
            }
            ActionButton {
                objectName: "marketplaceSetupRetryBrowse"; text: "Retry browse checks"
                visible: settingsEditor.browseNeedsRetry
                Layout.fillWidth: true; enabled: root.canRetryBrowse
                onClicked: root.retryBrowse()
            }
            ActionButton {
                objectName: "marketplaceSetupBrowse"; text: "Open marketplace"
                variant: "primary"
                Layout.fillWidth: true; enabled: root.canBrowse
                onClicked: root.requestFinish("browse")
            }
        }
    }
}
