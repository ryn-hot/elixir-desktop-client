import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "liveNetworkSettingsView"
    implicitHeight: content.implicitHeight
    Layout.fillWidth: true

    property var client: apiClient
    property string scopeType: "server_default"
    property string editMode: "off"
    property string editPolicyId: ""
    property bool editAllowFallback: false
    property string notice: ""

    readonly property var status: client.liveEgressStatus || ({})
    readonly property bool statusLoaded: status.enabled !== undefined
    readonly property bool canManage: client.homeRole === "owner"
                                             && client.capabilities
                                             && client.capabilities.indexOf("live_manage") >= 0
                                             && client.capabilities.indexOf("settings_manage") >= 0

    function profiles() {
        return status.profiles || []
    }

    function assignments() {
        return status.assignments || []
    }

    function scopeId() {
        return scopeType === "profile" ? String(client.activeProfileId || "") : ""
    }

    function assignment() {
        var scopeKey = scopeType === "server_default" ? "server" : scopeId()
        var values = assignments()
        for (var i = 0; i < values.length; ++i) {
            if (String(values[i].scopeType || "") === scopeType
                    && String(values[i].scopeKey || "") === scopeKey) {
                return values[i]
            }
        }
        return ({})
    }

    function defaultPolicy() {
        return status.defaultPolicy || ({ mode: "off", policyId: "", allowFallback: false })
    }

    function syncEditor() {
        var selected = assignment()
        var inherited = defaultPolicy()
        editMode = String(selected.mode || inherited.mode || "off")
        editPolicyId = String(selected.policyId || inherited.policyId || "")
        editAllowFallback = selected.allowFallback === undefined
                ? Boolean(inherited.allowFallback) : Boolean(selected.allowFallback)
        if (editMode !== "prefer_protected") {
            editAllowFallback = false
        }
        scopeCombo.currentIndex = scopeType === "profile" ? 1 : 0
        modeCombo.currentIndex = modeIndex(editMode)
        profileCombo.currentIndex = profileIndex(editPolicyId)
    }

    function modeIndex(value) {
        if (value === "prefer_protected") return 1
        if (value === "require_protected") return 2
        return 0
    }

    function profileOptions() {
        var options = []
        var values = profiles()
        for (var i = 0; i < values.length; ++i) {
            options.push({ label: values[i].name, value: values[i].id })
        }
        return options
    }

    function profileIndex(value) {
        var values = profileOptions()
        for (var i = 0; i < values.length; ++i) {
            if (String(values[i].value || "") === String(value || "")) return i
        }
        return values.length > 0 ? 0 : -1
    }

    function title(value) {
        return String(value || "off").replace(/_/g, " ").replace(/\b\w/g, function(letter) {
            return letter.toUpperCase()
        })
    }

    Component.onCompleted: syncEditor()

    Connections {
        target: root.client

        function onLiveEgressChanged() {
            root.notice = ""
            root.syncEditor()
        }

        function onRequestFailed(endpoint, error) {
            if (endpoint === "/api/v1/live/admin/egress") {
                root.notice = error
            }
        }
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.spacingMedium

        RowLayout {
            Layout.fillWidth: true

            Label {
                text: "Live stream egress"
                color: Theme.textPrimary
                font.pixelSize: 16
                font.family: Theme.fontDisplay
                Layout.fillWidth: true
            }

            ActionButton {
                objectName: "liveEgressRefreshButton"
                text: "Refresh"
                compact: true
                variant: "ghost"
                enabled: root.canManage && !root.client.liveEgressLoading
                Accessible.name: "Refresh Live stream egress"
                onClicked: root.client.fetchLiveEgressStatus()
            }

            BusyIndicator {
                running: root.client.liveEgressLoading
                visible: running
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: width < 560 ? 1 : 4
            columnSpacing: Theme.spacingLarge
            rowSpacing: Theme.spacingSmall

            Label {
                text: "Feature"
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
            }
            Label {
                objectName: "liveEgressEnabledStatus"
                text: !root.statusLoaded ? "Not loaded" : (status.enabled ? "Enabled" : "Disabled")
                color: status.enabled ? Theme.accent : Theme.textMuted
                font.pixelSize: 12
                font.family: Theme.fontBody
                font.weight: Font.DemiBold
            }
            Label {
                text: "Worker readiness"
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
            }
            Label {
                objectName: "liveEgressReadyStatus"
                text: !root.statusLoaded ? "Not loaded" : (status.ready ? "Ready" : "Unavailable")
                color: status.ready ? Theme.accent : "#D96B6B"
                font.pixelSize: 12
                font.family: Theme.fontBody
                font.weight: Font.DemiBold
            }
            Label {
                text: "Active bindings"
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
            }
            Label {
                text: String(status.activeBindings || 0)
                color: Theme.textPrimary
                font.pixelSize: 12
                font.family: Theme.fontBody
            }
            Label {
                text: "Available workers"
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
            }
            Label {
                text: String(status.availableCapacity || 0)
                color: Theme.textPrimary
                font.pixelSize: 12
                font.family: Theme.fontBody
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.border
        }

        GridLayout {
            Layout.fillWidth: true
            columns: width < 560 ? 1 : 2
            columnSpacing: Theme.spacingLarge
            rowSpacing: Theme.spacingSmall
            enabled: root.canManage && status.enabled === true

            Label {
                text: "Policy scope"
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
            }
            ComboBox {
                id: scopeCombo
                objectName: "liveEgressScopeCombo"
                Layout.fillWidth: true
                model: ["Server default", "This profile"]
                Accessible.name: "Live egress policy scope"
                onActivated: function(index) {
                    root.scopeType = index === 1 ? "profile" : "server_default"
                    root.syncEditor()
                }
            }

            Label {
                text: "Mode"
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
            }
            ComboBox {
                id: modeCombo
                objectName: "liveEgressModeCombo"
                Layout.fillWidth: true
                model: ["Off", "Prefer protected", "Require protected"]
                Accessible.name: "Live egress policy mode"
                onActivated: function(index) {
                    root.editMode = index === 2 ? "require_protected"
                                                : (index === 1 ? "prefer_protected" : "off")
                    if (root.editMode !== "prefer_protected") root.editAllowFallback = false
                }
            }

            Label {
                text: "Gateway profile"
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
                visible: root.editMode !== "off"
            }
            ComboBox {
                id: profileCombo
                objectName: "liveEgressProfileCombo"
                Layout.fillWidth: true
                visible: root.editMode !== "off"
                model: root.profileOptions()
                textRole: "label"
                valueRole: "value"
                Accessible.name: "Live egress gateway profile"
                onActivated: function(index) {
                    root.editPolicyId = String(currentValue || "")
                }
            }

            Label {
                text: "Fallback"
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
                visible: root.editMode === "prefer_protected"
            }
            CheckBox {
                objectName: "liveEgressFallbackCheck"
                text: "Allow direct server fallback"
                checked: root.editAllowFallback
                visible: root.editMode === "prefer_protected"
                Layout.fillWidth: true
                Accessible.name: text
                onToggled: root.editAllowFallback = checked
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Label {
                text: root.notice
                visible: text !== ""
                color: "#D96B6B"
                font.pixelSize: 11
                font.family: Theme.fontBody
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            Item { Layout.fillWidth: root.notice === "" }

            ActionButton {
                objectName: "liveEgressSaveButton"
                text: "Save policy"
                variant: "primary"
                enabled: root.canManage
                         && status.enabled === true
                         && !root.client.liveEgressLoading
                         && (root.editMode === "off" || profileCombo.count > 0)
                         && (root.scopeType !== "profile" || root.scopeId() !== "")
                Accessible.name: "Save Live egress policy"
                onClicked: {
                    var selected = root.assignment()
                    var revision = Number(selected.revision || 0)
                    var policyId = root.editMode === "off" ? ""
                                                                  : String(profileCombo.currentValue || root.editPolicyId)
                    root.notice = ""
                    root.client.updateLiveEgressPolicy(
                                root.scopeType,
                                root.scopeId(),
                                root.editMode,
                                policyId,
                                root.editMode === "prefer_protected" && root.editAllowFallback,
                                revision)
                }
            }
        }
    }
}
