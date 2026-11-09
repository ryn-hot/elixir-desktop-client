import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "marketplaceSettingsView"
    implicitHeight: content.implicitHeight
    Layout.fillWidth: true
    property var client: apiClient
    // A parent may own first/session reads; visible status polling stays here.
    property bool manageInitialLoad: true
    property bool setupMode: false
    property bool prepareBrowsing: true
    property string notice: ""
    property string editContribution: "auto"
    property int editMetering: 0
    property bool contributionAccepted: false
    property bool supportConsent: false
    property bool issuerAccepted: false
    property bool editConnection: false
    property bool providerConsentAccepted: false
    property double editorRevision: -1
    property string originalPreferences: ""
    property bool reloadRequested: false

    readonly property var response: client.marketplaceSettings || ({})
    readonly property var snapshot: response.settings || ({})
    readonly property bool loaded: typeof snapshot.revision === "number" && snapshot.preferences !== undefined
    readonly property bool busy: client.marketplaceSettingsLoading === true
    readonly property bool canManage: client.homeRole === "owner"
        && client.activeProfileType === "account"
        && client.capabilities && client.capabilities.indexOf("server_admin") >= 0
        && client.capabilities.indexOf("settings_manage") >= 0
        && client.capabilities.indexOf("extensions_manage") >= 0
    readonly property bool dirty: originalPreferences !== "" && JSON.stringify(draftPreferences()) !== originalPreferences
    readonly property bool revisionConflict: loaded && editorRevision >= 0 && editorRevision !== snapshot.revision
    readonly property bool canSave: canManage && loaded && !busy && !revisionConflict
        && (editContribution === "off" || contributionAccepted
            || (loaded && snapshot.preferences.contribution === editContribution))
        && (!supportConsent || issuerAccepted)
    readonly property bool canConfigureConnection: canManage && client.authToken !== "" && client.capabilities.indexOf("secrets_manage") >= 0
    readonly property bool browsePrepared: browsePreparation.firstResultsReady
    readonly property bool browseNeedsRetry: browsePreparation.terminalEmpty || browsePreparation.terminalConnection
    readonly property bool browseRecovering: browsePreparation.recoveringConnection
    readonly property bool canRetryBrowse: browsePreparation.active && browsePreparation.connected
        && !browsePreparation.busy && !browsePreparation.checking
    readonly property string browseSummary: browsePreparation.compactSummary()
    readonly property var providerSetup: response.provider_setup || ({})

    function resetEditor() {
        editorRevision = -1
        originalPreferences = ""
        reloadRequested = false
        editContribution = "auto"
        editMetering = 0
        contributionAccepted = false
        supportConsent = false
        issuerAccepted = false
        notice = ""
        editConnection = false
        providerConsentAccepted = false
        connectionConfig.text = ""
    }
    function syncEditor(force) {
        if (!loaded) return
        if (!force && dirty) return
        var preferences = snapshot.preferences
        editContribution = String(preferences.contribution)
        editMetering = preferences.metering === "unmetered" ? 1 : preferences.metering === "metered" ? 2 : 0
        contributionAccepted = preferences.contribution_disclosure_version === response.contribution_disclosure_version
        supportConsent = preferences.paid_support_consent === true
        issuerAccepted = preferences.issuer_disclosure_version === response.issuer_disclosure_version
        editorRevision = snapshot.revision
        originalPreferences = JSON.stringify(draftPreferences())
        reloadRequested = false
        notice = ""
    }
    function refresh() {
        if (canManage && client.authToken !== "" && !busy) {
            reloadRequested = true
            client.fetchMarketplaceSettings()
        }
    }
    function retryBrowse() {
        if (canManage && loaded && !busy && !dirty && !revisionConflict && browseNeedsRetry && canRetryBrowse)
            browsePreparation.start()
    }
    function draftPreferences() {
        return {
            schema_version: 1,
            contribution: editContribution,
            metering: ["unknown", "unmetered", "metered"][editMetering],
            contribution_disclosure_version: contributionAccepted ? response.contribution_disclosure_version : null,
            paid_support_consent: supportConsent,
            issuer_disclosure_version: issuerAccepted ? response.issuer_disclosure_version : null
        }
    }
    function save() {
        if (!canSave) return
        client.saveMarketplaceSettings(draftPreferences())
    }
    function poll() {
        if (visible && canManage && client.authToken !== "" && !busy)
            client.pollMarketplaceSettings()
    }
    function startupSummary() {
        if (response.runtime_fresh === false) return "Connection status is unavailable. Refresh will retry while this page is open."
        var startup = response.startup
        if (!startup) return ""
        if (!startup.configured) return "No marketplace startup connection is configured on this server."
        if (!startup.retry_owner_present) return "Connection recovery is not running. Check the server before restarting it."
        if (typeof startup.retry_after_seconds === "number")
            return "Connection retry scheduled in up to " + startup.retry_after_seconds + " seconds. Cleanup and protection checks still apply."
        return "Connection recovery is active. This does not confirm a protected connection."
    }
    function runtimeSummary() {
        if (!loaded) return "Marketplace settings are unavailable. Reload to edit."
        var phase = String(response.runtime_status || "unknown")
        if (phase === "not_connected") return "Marketplace networking is not connected. These controls save preferences only."
        if (phase === "failed") return "Marketplace protection or ownership failed. Applied roles are unknown; stopped is not confirmed."
        if (phase === "stopping") return "Marketplace shutdown is in progress. Stopped is not confirmed yet."
        if (phase === "stopped") return ((response.runtime || {}).participation || null)
            ? "The attached marketplace worker has stopped."
            : "No worker is attached to this application lifecycle."
        if (phase === "waiting_for_protection") return "Waiting for protected connectivity. New network work is not ready."
        if (phase === "starting" || phase === "applying") return "Marketplace roles are being applied; this is not an off acknowledgement."
        if (phase !== "running") return "Marketplace runtime status is unavailable."
        if (response.participation_applied !== true) return "Preferences are saved, but this revision is not yet confirmed as applied. Status refreshes automatically."
        var state = ((response.runtime || {}).participation || {})
        var roles = state.applied_roles
        if (!roles) return "Applied marketplace roles are unknown."
        return "Last confirmed roles — consumer: " + (roles.consumer === true ? "on" : "off")
            + "; catalog: " + (roles.catalog === true ? "on" : "off")
            + "; routing: " + (roles.routing === true ? "on" : "off")
            + "; package sharing: " + (state.package_sharing_active === true ? "on" : "off") + "."
    }

    component WrappedCheckBox: CheckBox {
        id: control
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        contentItem: Label {
            text: control.text
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            leftPadding: control.indicator ? control.indicator.width + control.spacing : 0
            color: control.enabled ? Theme.textPrimary : Theme.textMuted
            verticalAlignment: Text.AlignVCenter
        }
    }

    Component.onCompleted: {
        syncEditor()
        if (manageInitialLoad) { if (loaded) poll(); else refresh() }
    }
    Timer {
        interval: 5000; repeat: true
        running: root.visible && root.canManage && root.client.authToken !== ""
            && Qt.application.state === Qt.ApplicationActive
        onTriggered: root.poll()
    }
    Connections {
        target: root.client
        function onMarketplaceSettingsChanged() { root.syncEditor(root.reloadRequested) }
        function onMarketplaceSettingsSaved() {
            root.syncEditor(true)
            root.notice = "Preferences saved. This is not confirmation that contribution is running."
        }
        function onSessionStateChanged() { root.resetEditor(); if (root.manageInitialLoad) root.refresh() }
        function onAuthTokenChanged() {
            if (root.client.authToken === "") root.resetEditor()
            else if (root.manageInitialLoad && !root.loaded) root.refresh()
        }
        function onRequestFailed(endpoint, error) {
            if (endpoint === "/api/v1/marketplace/settings")
                root.notice = "Settings were not confirmed. Reload before retrying. " + error
        }
    }

    ColumnLayout {
        id: content
        width: parent.width
        spacing: 12
        Label {
            text: "Extension marketplace"
            textFormat: Text.PlainText
            color: Theme.textPrimary
            font.family: Theme.fontDisplay
            font.pixelSize: 16
        }
        Label {
            objectName: "marketplaceRuntimeStatus"
            visible: !root.setupMode || ["failed", "stopping", "stopped"].indexOf(String(root.response.runtime_status)) >= 0
            Layout.fillWidth: true
            text: root.runtimeSummary()
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.textSecondary
        }
        Label {
            objectName: "marketplaceStartupStatus"
            Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.textSecondary
            text: root.startupSummary()
            visible: text !== "" && (!root.setupMode || (root.response.startup || {}).configured !== true)
        }
        MarketplaceCatalogStatus {
            Layout.fillWidth: true
            snapshot: root.response
            allowed: !root.setupMode && root.canManage && root.client.authToken !== ""
        }
        MarketplaceBrowsePreparation {
            id: browsePreparation
            Layout.fillWidth: true
            client: root.client
            compact: root.setupMode
            fullCatalog: root.setupMode
            snapshot: root.response
            allowed: root.prepareBrowsing && root.canManage && root.client.authToken !== ""
                && (!root.setupMode || (root.loaded && root.response.runtime_fresh === true
                    && !root.busy && !root.dirty && !root.revisionConflict
                    && (root.snapshot.preferences.contribution === "off"
                        || root.snapshot.preferences.contribution_disclosure_version === root.response.contribution_disclosure_version)))
        }
        ColumnLayout {
            objectName: "marketplaceFreeProviderSetup"
            Layout.fillWidth: true
            visible: root.canConfigureConnection && root.providerSetup.schema_version === 1
            Label {
                text: "Free marketplace VPN"
                color: Theme.textPrimary
            }
            Label {
                Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
                color: Theme.textSecondary
                text: "Use a dedicated Cloudflare WARP identity for marketplace networking, separate from downloads. Cloudflare can see your connecting IP and connection metadata. Your ISP can see the VPN connection. This does not anonymize public source-code accounts or Git metadata. Marketplace traffic stays blocked when protection is unavailable. Availability and performance are not guaranteed."
            }
            RowLayout {
                ActionButton {
                    text: "Cloudflare terms"
                    onClicked: Qt.openUrlExternally("https://www.cloudflare.com/application/terms/")
                }
                ActionButton {
                    text: "Cloudflare privacy"
                    onClicked: Qt.openUrlExternally("https://www.cloudflare.com/application/privacypolicy/")
                }
            }
            Label {
                objectName: "marketplaceProviderConsentStatus"
                Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
                color: Theme.textSecondary
                text: root.providerSetup.enabled === true && root.providerSetup.consent_current === true
                    ? "VPN consent is saved. Live protected status is shown above."
                    : root.providerSetup.enabled === true ? "Review VPN consent again before reconnecting."
                    : "The free marketplace VPN is not enabled."
            }
            WrappedCheckBox {
                objectName: "marketplaceProviderConsent"
                visible: root.providerSetup.enabled !== true || root.providerSetup.consent_current !== true
                text: "I accept Cloudflare's Application Terms and Privacy Policy and authorize a dedicated marketplace WARP identity. I understand that protection requires successful connection checks."
                checked: root.providerConsentAccepted
                onToggled: root.providerConsentAccepted = checked
                enabled: !root.busy && root.client.marketplaceConnectionSaving !== true
            }
            ActionButton {
                objectName: "marketplaceProviderEnable"
                visible: root.providerSetup.enabled !== true || root.providerSetup.consent_current !== true
                text: "Enable free marketplace VPN"
                enabled: root.canConfigureConnection && root.response.runtime_fresh === true
                    && root.loaded && root.snapshot.revision > 0 && !root.busy && !root.dirty && !root.revisionConflict
                    && root.providerConsentAccepted && root.client.marketplaceConnectionSaving !== true
                onClicked: {
                    root.client.saveMarketplaceProviderSetup(true, String(root.providerSetup.consent_version))
                    root.providerConsentAccepted = false
                }
            }
            ActionButton {
                objectName: "marketplaceProviderDisable"
                visible: root.providerSetup.enabled === true
                text: "Disconnect marketplace VPN"
                enabled: root.canConfigureConnection && root.response.runtime_fresh === true
                    && !root.busy && root.client.marketplaceConnectionSaving !== true
                onClicked: { root.client.saveMarketplaceProviderSetup(false, ""); root.providerConsentAccepted = false }
            }
            Label {
                visible: root.snapshot.revision === 0 || root.dirty || root.revisionConflict
                Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
                color: Theme.textSecondary
                text: "Save your marketplace choices below before enabling the VPN. VPN consent does not enable network contribution or paid support."
            }
        }
        ActionButton {
            objectName: "marketplaceConnectionRetry"
            visible: !root.setupMode || ((root.response.startup || {}).retry_owner_present === true && !browsePreparation.connected)
            text: "Retry connection"
            enabled: root.canConfigureConnection && root.client.marketplaceConnectionSaving !== true
                && root.response.runtime_fresh !== false
                && root.response.startup !== undefined
                && root.response.startup.retry_owner_present === true
            onClicked: root.client.retryMarketplaceConnection()
        }
        ActionButton {
            objectName: "marketplaceConnectionEditor"
            visible: !root.setupMode || !browsePreparation.connected
            text: root.editConnection ? "Close custom connection" : root.setupMode ? "Advanced connection settings" : "Custom marketplace VPN connection"
            enabled: root.canConfigureConnection && root.client.marketplaceConnectionSaving !== true
            onClicked: { root.editConnection = !root.editConnection; connectionConfig.text = "" }
        }
        ColumnLayout {
            visible: root.editConnection
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.textSecondary
                text: "Use a separate WireGuard device configuration for marketplace networking—not your downloader or extension-HTTP identity. This advanced IPv4 full-tunnel path requires a public IP endpoint and the server's saved-profile startup selection. Free-provider enrollment is not configured here. DNS follows the marketplace's protected resolver policy."
            }
            TextArea {
                id: connectionConfig; objectName: "marketplaceConnectionConfig"
                Layout.fillWidth: true; Layout.preferredHeight: 140
                textFormat: TextEdit.PlainText; wrapMode: TextEdit.Wrap; selectByMouse: true
                placeholderText: "Paste the dedicated WireGuard configuration"
                enabled: root.canConfigureConnection && root.client.marketplaceConnectionSaving !== true
            }
            ActionButton {
                objectName: "marketplaceConnectionSave"
                text: root.client.marketplaceConnectionSaving === true ? "Working…" : "Save dedicated connection"
                enabled: root.canConfigureConnection && root.client.marketplaceConnectionSaving !== true && connectionConfig.text.trim().length > 0
                onClicked: { root.client.saveMarketplaceWireguard(connectionConfig.text); connectionConfig.text = "" }
            }
        }
        Label {
            objectName: "marketplaceConnectionNotice"
            Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.textSecondary
            text: root.client.marketplaceConnectionNotice || ""
            visible: text !== ""
        }
        WrappedCheckBox {
            objectName: "marketplaceContributionSwitch"
            text: "Help power the extension marketplace"
            enabled: root.canManage && root.loaded && !root.busy
            checked: root.editContribution !== "off"
            onToggled: root.editContribution = checked ? "auto" : "off"
        }
        Label {
            Layout.fillWidth: true
            text: "Off stops contribution, not your searches or downloads. Auto waits for your acknowledgement, an unmetered connection, and passing protection and hardware checks."
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.textSecondary
        }
        Label { text: root.setupMode ? "Internet data limit" : "Connection data plan"; textFormat: Text.PlainText; color: Theme.textSecondary }
        ComboBox {
            objectName: "marketplaceMeteringCombo"
            Layout.fillWidth: true
            model: root.setupMode ? ["Not sure", "No data limit", "Has a data limit"]
                : ["Unknown — do not contribute automatically", "Unmetered", "Metered — do not contribute automatically"]
            enabled: root.canManage && root.loaded && !root.busy
            currentIndex: root.editMetering
            onActivated: root.editMetering = currentIndex
        }
        Label {
            objectName: "marketplaceContributionDisclosure"
            Layout.fillWidth: true
            text: String(root.response.contribution_disclosure || "Reload to read the current contribution disclosure.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.textSecondary
        }
        WrappedCheckBox {
            objectName: "marketplaceContributionAcknowledgement"
            text: "I understand the contribution limits and risks"
            checked: root.contributionAccepted
            enabled: root.canManage && root.loaded && !root.busy
            onToggled: root.contributionAccepted = checked
        }
        WrappedCheckBox {
            objectName: "marketplacePaidSupportConsent"
            visible: !root.setupMode
            text: "Record my preference for optional public paid support"
            checked: root.supportConsent
            enabled: root.canManage && root.loaded && !root.busy
            onToggled: root.supportConsent = checked
        }
        Label {
            objectName: "marketplaceIssuerDisclosure"
            visible: !root.setupMode
            Layout.fillWidth: true
            text: String(root.response.issuer_disclosure || "Reload to read the current account-visibility disclosure.")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.textSecondary
        }
        WrappedCheckBox {
            objectName: "marketplaceIssuerAcknowledgement"
            visible: !root.setupMode
            text: "I understand that Elixir sees the requesting account and extension"
            checked: root.issuerAccepted
            enabled: root.canManage && root.loaded && !root.busy
            onToggled: root.issuerAccepted = checked
        }
        Label {
            Layout.fillWidth: true
            visible: !root.setupMode
            text: "Paid-account connection and credential issuance are not active here. Network contribution does not opt you into public paid support or provider terms."
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.textSecondary
        }
        GridLayout {
            Layout.fillWidth: true
            columns: root.width < 480 ? 1 : 2
            ActionButton {
                Layout.fillWidth: true
                objectName: "marketplaceSaveButton"
                variant: "primary"
                text: root.busy ? "Working…" : "Save preferences"
                enabled: root.canSave
                onClicked: root.save()
            }
            ActionButton {
                Layout.fillWidth: true
                objectName: "marketplaceReloadButton"
                text: root.dirty ? "Discard edits and reload" : "Reload"
                enabled: root.canManage && !root.busy
                onClicked: root.refresh()
            }
        }
        Label {
            objectName: "marketplaceRevisionConflict"
            Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: Theme.textSecondary
            visible: root.revisionConflict
            text: "Settings changed elsewhere. Your edits are preserved, but reload and review the current settings before saving."
        }
        Label {
            objectName: "marketplaceSettingsNotice"
            Layout.fillWidth: true
            visible: text !== ""
            text: root.notice
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: Theme.textSecondary
        }
    }
}
