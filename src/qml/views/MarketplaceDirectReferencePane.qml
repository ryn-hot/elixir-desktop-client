import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Pane {
    id: root
    objectName: "marketplaceDirectReferencePane"
    property var client: apiClient
    property bool canManage: false
    property bool expanded: false
    readonly property var preview: client.marketplaceDirectReference || ({})
    readonly property bool busy: client.marketplaceDirectReferenceLoading === true
    signal inspect(var preview)
    visible: canManage
    padding: 12
    implicitHeight: content.implicitHeight + topPadding + bottomPadding
    background: Rectangle { radius: 8; color: Theme.backgroundCardRaised; border.color: Theme.border }
    function clearDraft() {
        if (reference) reference.clear()
        if (typeof client.clearMarketplaceDirectReference === "function") client.clearMarketplaceDirectReference()
    }
    onCanManageChanged: if (!canManage) { clearDraft(); expanded = false }
    Connections {
        target: root.client
        ignoreUnknownSignals: true
        function onSessionStateChanged() { root.clearDraft(); root.expanded = false }
    }
    Component.onDestruction: if (typeof client.clearMarketplaceDirectReference === "function") client.clearMarketplaceDirectReference()
    ColumnLayout {
        id: content
        width: parent.width
        spacing: 8
        Button { objectName: "marketplaceDeveloperReferenceToggle"; text: root.expanded ? "Hide developer reference" : "Have a developer reference?"
            onClicked: root.expanded = !root.expanded }
        ColumnLayout {
            visible: root.expanded
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: Theme.textSecondary
                text: "Paste the developer's signed publication.json, not a download URL. Signature checks do not prove safe code. This does not add a search listing or start an installation." }
            ScrollView {
                Layout.fillWidth: true; Layout.preferredHeight: 110
                TextArea { id: reference; objectName: "marketplaceDeveloperReferenceText"; textFormat: TextEdit.PlainText; wrapMode: TextEdit.Wrap
                    Accessible.name: "Signed developer reference"; placeholderText: "Signed publication.json (at most 64 KiB)"; enabled: root.canManage
                    onTextChanged: if (typeof root.client.clearMarketplaceDirectReference === "function") root.client.clearMarketplaceDirectReference() }
            }
            RowLayout {
                Layout.fillWidth: true
                Button { objectName: "marketplaceCheckDeveloperReference"; text: "Check reference"
                    enabled: root.canManage && !root.busy && reference.text.length > 0 && reference.text.length <= 65536
                    onClicked: root.client.previewMarketplaceDirectReference(reference.text) }
                Button { text: "Clear"; enabled: !root.busy; onClicked: root.clearDraft() }
                BusyIndicator { running: root.busy; visible: running; implicitWidth: 24; implicitHeight: 24 }
            }
            Label { Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: Theme.textPrimary
                visible: !!root.preview.reference_id; text: (root.preview.name || "") + " · " + (root.preview.version || "") }
            Label { Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: Theme.textSecondary
                visible: !!root.preview.reference_id; text: "Signatures checked. Paid adoption is unqualified; source and permission checks still need to pass. Nothing is installed or made searchable." }
            Button { objectName: "marketplaceInspectDeveloperReference"; text: "Choose an instance"
                visible: !!root.preview.reference_id; enabled: root.canManage && !root.busy && root.preview.signatures_verified === true
                onClicked: root.inspect(root.preview) }
        }
    }
}
