import QtQuick
import QtTest
import "../../src/qml/views" as Views

TestCase {
    id: testCase
    name: "LiveNetworkSettings"
    when: windowShown

    readonly property string profileId: "30000000-0000-4000-8000-000000000003"

    Window {
        id: testWindow
        width: 900
        height: 720
        visible: true

        Item {
            id: host
            anchors.fill: parent
        }
    }

    QtObject {
        id: client
        property string homeRole: "owner"
        property var capabilities: ["live_manage", "settings_manage"]
        property string activeProfileId: testCase.profileId
        property bool liveEgressLoading: false
        property int fetchCalls: 0
        property int updateCalls: 0
        property var lastUpdate: ({})
        property var liveEgressStatus: ({
            enabled: true,
            ready: true,
            activeBindings: 2,
            availableCapacity: 6,
            defaultPolicy: {
                mode: "off",
                policyId: "",
                allowFallback: false
            },
            profiles: [{
                id: "warp-default",
                name: "WARP",
                kind: "warp",
                selectableByProfiles: true
            }],
            assignments: [{
                id: "70000000-0000-4000-8000-000000000007",
                scopeType: "server_default",
                scopeKey: "server",
                mode: "prefer_protected",
                policyId: "warp-default",
                allowFallback: true,
                revision: 7
            }, {
                id: "80000000-0000-4000-8000-000000000008",
                scopeType: "profile",
                scopeKey: testCase.profileId,
                mode: "require_protected",
                policyId: "warp-default",
                allowFallback: false,
                revision: 3
            }]
        })

        signal liveEgressChanged()
        signal requestFailed(string endpoint, string error)

        function fetchLiveEgressStatus() {
            fetchCalls += 1
        }

        function updateLiveEgressPolicy(scopeType, scopeId, mode, policyId,
                                        allowFallback, expectedRevision) {
            updateCalls += 1
            lastUpdate = {
                scopeType: scopeType,
                scopeId: scopeId,
                mode: mode,
                policyId: policyId,
                allowFallback: allowFallback,
                expectedRevision: expectedRevision
            }
        }
    }

    Component {
        id: viewComponent
        Views.LiveNetworkSettingsView {}
    }

    function init() {
        client.homeRole = "owner"
        client.capabilities = ["live_manage", "settings_manage"]
        client.fetchCalls = 0
        client.updateCalls = 0
        client.lastUpdate = ({})
    }

    function createView(width, height) {
        return createTemporaryObject(viewComponent, host, {
            client: client,
            width: width,
            height: height
        })
    }

    function test_capability_and_status_gate() {
        var view = createView(760, 600)
        verify(view)
        compare(view.canManage, true)
        compare(findChild(view, "liveEgressEnabledStatus").text, "Enabled")
        compare(findChild(view, "liveEgressReadyStatus").text, "Ready")
        verify(findChild(view, "liveEgressSaveButton").enabled)

        client.capabilities = ["live_manage"]
        tryCompare(view, "canManage", false)
        compare(findChild(view, "liveEgressSaveButton").enabled, false)
        client.capabilities = ["live_manage", "settings_manage"]
        client.homeRole = "admin"
        tryCompare(view, "canManage", false)
    }

    function test_fallback_visibility_and_cas_mutation() {
        var view = createView(760, 600)
        verify(view)
        var fallback = findChild(view, "liveEgressFallbackCheck")
        tryCompare(fallback, "visible", true)
        compare(fallback.checked, true)

        var mode = findChild(view, "liveEgressModeCombo")
        mode.activated(2)
        compare(view.editMode, "require_protected")
        compare(fallback.visible, false)
        mode.activated(1)
        compare(fallback.visible, true)

        mouseClick(findChild(view, "liveEgressSaveButton"))
        compare(client.updateCalls, 1)
        compare(client.lastUpdate.scopeType, "server_default")
        compare(client.lastUpdate.scopeId, "")
        compare(client.lastUpdate.mode, "prefer_protected")
        compare(client.lastUpdate.policyId, "warp-default")
        compare(client.lastUpdate.allowFallback, false)
        compare(client.lastUpdate.expectedRevision, 7)
    }

    function test_profile_scope_and_compact_accessibility() {
        var view = createView(340, 620)
        verify(view)
        var scope = findChild(view, "liveEgressScopeCombo")
        scope.activated(1)
        compare(view.scopeType, "profile")
        compare(view.editMode, "require_protected")

        mouseClick(findChild(view, "liveEgressSaveButton"))
        compare(client.lastUpdate.scopeType, "profile")
        compare(client.lastUpdate.scopeId, profileId)
        compare(client.lastUpdate.expectedRevision, 3)
        compare(findChild(view, "liveEgressRefreshButton").Accessible.name,
                "Refresh Live stream egress")
        verify(findChild(view, "liveEgressScopeCombo").width <= view.width)
        verify(findChild(view, "liveEgressModeCombo").width <= view.width)
        verify(findChild(view, "liveEgressSaveButton").width <= view.width)
    }
}
