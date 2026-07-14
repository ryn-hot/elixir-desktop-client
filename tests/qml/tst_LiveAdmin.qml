import QtQuick
import QtTest
import Elixir 1.0
import "../../src/qml/views" as Views

TestCase {
    id: testCase
    name: "LiveAdmin"
    when: windowShown

    readonly property string providerId: "0a6efebd-f2ad-4bbb-b199-6f0fa820ca5d"
    readonly property string profileId: "56bb1365-f71d-4a09-88aa-754f37cad251"
    readonly property string sessionId: "7858b2ee-753e-42d1-9a34-2fa5c9564ea4"

    Window {
        id: testWindow
        width: 1280
        height: 720
        visible: true

        Item {
            id: host
            anchors.fill: parent
        }
    }

    QtObject {
        id: auth
        property string authToken: "fixture-token"
        property string homeRole: "owner"
        property var capabilities: []
        property var profiles: [{ id: testCase.profileId, name: "Kids" }]
    }

    QtObject {
        id: admin
        property int nextRequestId: 1
        property int providerListCalls: 0
        property int sessionListCalls: 0
        property int keyStateCalls: 0
        property int destinationListCalls: 0
        property int disableCalls: 0
        property int terminateCalls: 0
        property int ruleCreateCalls: 0
        property int grantCalls: 0
        property int keyRotateCalls: 0
        property var lastMutation: ({})
        property var cancelled: []

        signal adminResponseReceived(var requestId, var generation, string operation, var data)
        signal requestFailed(var requestId, var generation, string endpoint, var error)
        signal requestCancelled(var requestId, var generation)
        signal authContextInvalidated()

        function completeLater(id, generation, operation, data) {
            Qt.callLater(function() {
                admin.adminResponseReceived(id, generation, operation, data)
            })
        }

        function listAdminProviders(generation) {
            providerListCalls += 1
            var id = nextRequestId++
            completeLater(id, generation, "adminProviders", [{
                providerId: testCase.providerId,
                enabled: true,
                readiness: "ready",
                providerRevision: 4,
                grantRevision: 7,
                activeSessions: 1,
                effectiveProtocols: ["hls"]
            }])
            return id
        }

        function listAdminSessions(generation) {
            sessionListCalls += 1
            var id = nextRequestId++
            completeLater(id, generation, "adminSessions", [{
                sessionId: testCase.sessionId,
                profileId: testCase.profileId,
                providerId: testCase.providerId,
                deliveryMode: "server_relay",
                protocol: "hls",
                state: "playing",
                revision: 9
            }])
            return id
        }

        function getAdminKeyState(generation) {
            keyStateCalls += 1
            var id = nextRequestId++
            completeLater(id, generation, "keyState", {
                envelopePrimaryKeyId: "live-env-1",
                tokenHashPrimaryKeyId: "live-token-1",
                auditPrimaryKeyId: "live-audit-1",
                revision: 11
            })
            return id
        }

        function listAdminDestinationRules(provider, generation) {
            destinationListCalls += 1
            var id = nextRequestId++
            completeLater(id, generation, "destinationRules", [])
            return id
        }

        function disableAdminProvider(provider, revision, generation) {
            disableCalls += 1
            lastMutation = { operation: "disable", providerId: provider,
                             revision: revision, generation: generation }
            return nextRequestId++
        }

        function terminateAdminSession(session, revision, generation) {
            terminateCalls += 1
            lastMutation = { operation: "terminate", sessionId: session,
                             revision: revision, generation: generation }
            return nextRequestId++
        }

        function createAdminDestinationRule(provider, revision, rule, generation) {
            ruleCreateCalls += 1
            lastMutation = { operation: "createRule", providerId: provider,
                             revision: revision, rule: rule,
                             generation: generation }
            return nextRequestId++
        }

        function updateAdminDestinationRule(provider, ruleId, revision, rule, generation) {
            lastMutation = { operation: "updateRule", providerId: provider,
                             ruleId: ruleId, revision: revision, rule: rule,
                             generation: generation }
            return nextRequestId++
        }

        function deleteAdminDestinationRule(provider, ruleId, revision, generation) {
            lastMutation = { operation: "deleteRule", providerId: provider,
                             ruleId: ruleId, revision: revision,
                             generation: generation }
            return nextRequestId++
        }

        function setAdminProviderGrant(provider, profile, browse, play, revision, generation) {
            grantCalls += 1
            lastMutation = { operation: "setGrant", providerId: provider,
                             profileId: profile, canBrowse: browse,
                             canPlay: play, revision: revision,
                             generation: generation }
            return nextRequestId++
        }

        function revokeAdminProviderGrant(provider, profile, revision, generation) {
            grantCalls += 1
            lastMutation = { operation: "revokeGrant", providerId: provider,
                             profileId: profile, revision: revision,
                             generation: generation }
            return nextRequestId++
        }

        function rotateAdminKey(domain, keyId, revision, generation) {
            keyRotateCalls += 1
            lastMutation = { operation: "rotateKey", domain: domain,
                             keyId: keyId, revision: revision,
                             generation: generation }
            return nextRequestId++
        }

        function cancel(requestId) {
            cancelled.push(requestId)
        }
    }

    Component {
        id: liveAdminComponent
        Views.LiveAdminView {}
    }

    function fullCapabilities() {
        return ["live_manage", "settings_manage", "extensions_manage",
                "sharing_manage", "secrets_manage"]
    }

    function resetMocks() {
        auth.homeRole = "owner"
        auth.capabilities = []
        admin.nextRequestId = 1
        admin.providerListCalls = 0
        admin.sessionListCalls = 0
        admin.keyStateCalls = 0
        admin.destinationListCalls = 0
        admin.disableCalls = 0
        admin.terminateCalls = 0
        admin.ruleCreateCalls = 0
        admin.grantCalls = 0
        admin.keyRotateCalls = 0
        admin.lastMutation = ({})
        admin.cancelled = []
    }

    function init() {
        resetMocks()
    }

    function createView(width, height) {
        return createTemporaryObject(liveAdminComponent, host, {
            width: width,
            height: height,
            adminClient: admin,
            authClient: auth
        })
    }

    function test_capability_and_owner_gates_are_exact() {
        var denied = createView(900, 640)
        verify(denied)
        tryCompare(findChild(denied, "liveAdminAccessDenied"), "visible", true)
        compare(admin.providerListCalls, 0)
        denied.destroy()
        wait(0)

        auth.capabilities = fullCapabilities()
        var allowed = createView(900, 640)
        verify(allowed)
        tryCompare(admin, "providerListCalls", 1)
        tryCompare(allowed, "pendingCount", 0)
        compare(findChild(allowed, "liveAdminAccessDenied").visible, false)
        compare(findChild(allowed, "liveAdminDestinationSection").visible, true)
        compare(findChild(allowed, "liveAdminGrantSection").visible, true)
        compare(findChild(allowed, "liveAdminKeySection").visible, true)
        compare(findChild(allowed, "liveAdminDisableProviderButton").visible, true)

        auth.homeRole = "admin"
        compare(findChild(allowed, "liveAdminDestinationSection").visible, false)
        compare(findChild(allowed, "liveAdminGrantSection").visible, false)
        compare(findChild(allowed, "liveAdminSessionSection").visible, true)
        compare(findChild(allowed, "liveAdminKeySection").visible, true)
    }

    function test_mutations_require_confirmation_and_preserve_revisions() {
        auth.capabilities = fullCapabilities()
        var view = createView(900, 700)
        verify(view)
        tryCompare(findChild(view, "liveAdminProviderPicker"), "count", 1)
        tryCompare(view, "pendingCount", 0)

        var disable = findChild(view, "liveAdminDisableProviderButton")
        verify(disable.enabled)
        mouseClick(disable)
        var dialog = findChild(view, "liveAdminConfirmationDialog")
        tryCompare(dialog, "visible", true)
        compare(admin.disableCalls, 0)
        dialog.accept()
        compare(admin.disableCalls, 1)
        compare(admin.lastMutation.providerId, providerId)
        compare(admin.lastMutation.revision, 4)

        view.finish(admin.nextRequestId - 1)
        var terminate = findChild(view, "liveAdminTerminateSessionButton")
        verify(terminate)
        view.queueSessionTerminate(view.sessions[0])
        tryCompare(dialog, "visible", true)
        compare(admin.terminateCalls, 0)
        dialog.accept()
        compare(admin.terminateCalls, 1)
        compare(admin.lastMutation.sessionId, sessionId)
        compare(admin.lastMutation.revision, 9)
    }

    function test_destination_and_key_actions_are_bounded_and_secret_free() {
        auth.capabilities = fullCapabilities()
        var view = createView(360, 640)
        verify(view)
        tryCompare(findChild(view, "liveAdminProviderPicker"), "count", 1)
        tryCompare(view, "pendingCount", 0)

        var hostField = findChild(view, "liveAdminRuleHost")
        hostField.text = "origin.example"
        var save = findChild(view, "liveAdminSaveRuleButton")
        verify(save.enabled)
        view.queueRuleSave()
        var dialog = findChild(view, "liveAdminConfirmationDialog")
        tryCompare(dialog, "visible", true)
        compare(admin.ruleCreateCalls, 0)
        dialog.accept()
        compare(admin.ruleCreateCalls, 1)
        compare(admin.lastMutation.rule.host, "origin.example")
        compare(admin.lastMutation.revision, 4)

        view.finish(admin.nextRequestId - 1)
        var keyTarget = findChild(view, "liveAdminKeyTarget")
        keyTarget.text = "live-env-2"
        var rotate = findChild(view, "liveAdminRotateKeyButton")
        verify(rotate.enabled)
        view.queueKeyRotation()
        tryCompare(dialog, "visible", true)
        compare(admin.keyRotateCalls, 0)
        dialog.accept()
        compare(admin.keyRotateCalls, 1)
        compare(admin.lastMutation.keyId, "live-env-2")

        var keyText = findChild(view, "liveAdminKeyState")
        verify(keyText.text.indexOf("live-env-1") >= 0)
        verify(keyText.text.indexOf("fixture-token") < 0)
        compare(findChild(view, "liveAdminRefreshButton").Accessible.name,
                "Refresh Live administration")
        verify(findChild(view, "liveAdminProviderSection").width <= view.width)
        verify(findChild(view, "liveAdminDestinationSection").width <= view.width)
    }
}
