import QtQuick
import QtQuick.Controls
import QtTest
import "../../src/qml/views" as Views

TestCase {
    id: testCase
    name: "Extensions"
    when: windowShown

    property int openLiveCalls: 0

    Window {
        id: testWindow
        width: 1000
        height: 800
        visible: true

        Item {
            id: host
            anchors.fill: parent
        }
    }

    QtObject {
        id: apiClient
        signal requestFailed(string endpoint, string error)
        signal extensionControlActionCompleted(string targetExtensionId,
                                               string actionId, string message)
        signal extensionAccountSetupStarted(string extensionId, string instanceId,
                                            string setupId, string configureUrl)
        signal extensionAccountSetupStatusReceived(string extensionId, string instanceId,
                                                   string setupId, bool completed)
        signal extensionAccountSetupCompleted(string extensionId, string instanceId,
                                              string setupId)
        signal extensionsRuntimeResetCompleted(string status, string message)
        signal extensionsStatusSummaryChanged()
        signal extensionsCatalogChanged()
        signal extensionsPlanChanged()
        property string authToken: ""
        property string baseUrl: "http://127.0.0.1:3000"
        property bool extensionControlLoading: false
        property var extensionControlSurface: ({})
        property int exactFetchCalls: 0
        property int exactUpdateCalls: 0
        property int exactActionCalls: 0
        property int accountSetupCalls: 0
        property string lastExtensionId: ""
        property string lastInstanceId: ""
        property string lastActionId: ""
        property var extensionsInstalled: [{
            "extension_id": "fixture.live.provider",
            "manifest_json": {
                "provides": [{"capability": "live.catalog_provider"}]
            }
        }]
        property var extensionsAvailable: []
        property var extensionsCore: []
        property var extensionsInstances: []
        property var extensionsSecrets: []
        property var extensionsDesiredBlueprints: []
        property var extensionsStatusItems: [{
            "extensionId": "fixture.live.provider",
            "name": "Fixture Live Provider",
            "version": "1.0.0",
            "kind": "module",
            "trustLevel": "community",
            "enabled": true,
            "severity": "ready",
            "statusCode": "ready",
            "label": "Ready",
            "description": "This extension is ready for Live.",
            "primaryAction": "open",
            "primaryActionLabel": "Open"
        }]
        property int extensionsNeedsAttentionCount: 0
        property var extensionsRuntimeStatus: ({})
        property var extensionsReconcileRun: ({})
        property string extensionsPlanId: ""
        property var extensionsRun: ({})

        function refreshExtensionsCatalog() {}
        function fetchExtensionsCatalog() {}
        function fetchExtensionInstances() {}
        function fetchInstanceSecrets() {}
        function fetchDesiredBlueprints() {}
        function fetchExtensionStatusSummary() {}
        function fetchLatestReconcileRun() {}
        function accessTokenExpired() { return false }
        function expireAuth() {}
        function fetchExtensionControlSurfaceForInstance(extensionId, instanceId) {
            exactFetchCalls += 1
            lastExtensionId = extensionId
            lastInstanceId = instanceId
        }
        function fetchExtensionControlSurface() {}
        function updateExtensionControlSurfaceSettingsForInstance(extensionId, instanceId, values) {
            exactUpdateCalls += 1
            lastExtensionId = extensionId
            lastInstanceId = instanceId
        }
        function updateExtensionControlSurfaceSettings() {}
        function invokeExtensionControlActionForInstance(extensionId, instanceId, actionId, params) {
            exactActionCalls += 1
            lastExtensionId = extensionId
            lastInstanceId = instanceId
            lastActionId = actionId
        }
        function invokeExtensionControlAction() {}
        function startExtensionAccountSetup(extensionId, instanceId) {
            accountSetupCalls += 1
            lastExtensionId = extensionId
            lastInstanceId = instanceId
        }
        function checkExtensionAccountSetup() {}
    }

    Component {
        id: extensionsViewComponent
        Views.ExtensionsView {}
    }

    Component {
        id: extensionControlViewComponent
        Views.ExtensionControlView {}
    }

    function init() {
        apiClient.authToken = ""
        apiClient.extensionControlSurface = ({})
        apiClient.exactFetchCalls = 0
        apiClient.exactUpdateCalls = 0
        apiClient.exactActionCalls = 0
        apiClient.accountSetupCalls = 0
        apiClient.lastExtensionId = ""
        apiClient.lastInstanceId = ""
        apiClient.lastActionId = ""
    }

    function test_ready_live_provider_can_open_live() {
        openLiveCalls = 0
        var view = createTemporaryObject(extensionsViewComponent, host, {
            "width": 1000,
            "height": 800,
            "openLiveRequested": function() { testCase.openLiveCalls += 1 }
        })
        verify(view)

        var openLive = findChild(view, "extensionsOpenLiveButton")
        tryVerify(function() { return openLive && openLive.visible })
        mouseClick(openLive)
        compare(openLiveCalls, 1)
    }

    function test_live_account_actions_target_the_exact_instance() {
        var extensionId = "fixture.live.provider"
        var instanceId = "80000000-0000-4000-8000-000000000008"
        apiClient.authToken = "owner-access"
        apiClient.extensionControlSurface = {
            "extensionId": extensionId,
            "instanceId": instanceId,
            "name": "Fixture Live Provider",
            "version": "1.0.0",
            "kind": "module",
            "trustLevel": "community",
            "enabled": true,
            "status": {
                "health": "ready",
                "summary": "Ready",
                "details": []
            },
            "sections": [],
            "actions": []
        }
        var view = createTemporaryObject(extensionControlViewComponent, host, {
            "width": 900,
            "height": 700,
            "extensionId": extensionId,
            "instanceId": instanceId
        })
        verify(view)
        tryCompare(apiClient, "exactFetchCalls", 1)
        compare(apiClient.lastExtensionId, extensionId)
        compare(apiClient.lastInstanceId, instanceId)

        view.runAction({
            "id": "start_live_account_setup",
            "params": {
                "accountSetup": "external",
                "instanceId": instanceId
            }
        })
        compare(apiClient.accountSetupCalls, 1)
        compare(apiClient.lastExtensionId, extensionId)
        compare(apiClient.lastInstanceId, instanceId)

        view.updateField({ "id": "token", "readonly": false }, "value")
        compare(apiClient.exactUpdateCalls, 1)
        view.runPreparedAction({
            "id": "disconnect_live_account",
            "confirmText": ""
        }, {})
        compare(apiClient.exactActionCalls, 1)
        compare(apiClient.lastActionId, "disconnect_live_account")
        compare(apiClient.lastInstanceId, instanceId)
    }
}
