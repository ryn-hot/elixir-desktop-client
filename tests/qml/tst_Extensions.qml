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
        signal extensionsRuntimeResetCompleted(string status, string message)
        signal extensionsStatusSummaryChanged()
        signal extensionsCatalogChanged()
        signal extensionsPlanChanged()
        property string authToken: ""
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
    }

    Component {
        id: extensionsViewComponent
        Views.ExtensionsView {}
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
}
