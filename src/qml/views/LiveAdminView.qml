import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import Elixir 1.0

Item {
    id: root
    objectName: "liveAdminView"

    property StackView stackView: null
    property var adminClient: (typeof liveApiClient !== "undefined") ? liveApiClient : null
    property var authClient: (typeof apiClient !== "undefined") ? apiClient : null
    property int generation: 1
    property var providers: []
    property var sessions: []
    property var destinationRules: []
    property var keyState: ({})
    property int selectedProviderIndex: -1
    property string selectedRuleId: ""
    property var pendingRequests: ({})
    property int pendingCount: 0
    property string noticeText: ""
    property bool noticeError: false
    property string pendingAction: ""
    property string pendingTitle: ""
    property string pendingDetail: ""
    property var pendingPayload: ({})

    readonly property bool canLiveManage: hasCapability("live_manage")
    readonly property bool canManageDestinations: canLiveManage
                                                   && homeRole() === "owner"
                                                   && hasCapability("settings_manage")
    readonly property bool canDisableProviders: canLiveManage
                                                && hasCapability("extensions_manage")
    readonly property bool canManageGrants: canLiveManage
                                             && homeRole() === "owner"
                                             && hasCapability("sharing_manage")
    readonly property bool canManageKeys: canLiveManage
                                           && hasCapability("secrets_manage")
    readonly property bool busy: pendingCount > 0
    readonly property var selectedProvider: selectedProviderIndex >= 0
                                            && selectedProviderIndex < providers.length
                                            ? providers[selectedProviderIndex] : null
    readonly property string selectedProviderId: selectedProvider
                                                  ? String(selectedProvider.providerId || "") : ""

    function hasCapability(capability) {
        return authClient && authClient.capabilities
                && authClient.capabilities.indexOf(capability) >= 0
    }

    function homeRole() {
        return authClient ? String(authClient.homeRole || "") : ""
    }

    function profileId(profile) {
        return String(profile ? (profile.id || profile.profileId || profile.profile_id || "") : "")
    }

    function profileName(profile) {
        if (!profile) {
            return "Unknown profile"
        }
        return String(profile.name || profile.displayName || profile.display_name
                      || profileId(profile))
    }

    function profiles() {
        return authClient && authClient.profiles ? authClient.profiles : []
    }

    function providerLabel(provider) {
        if (!provider) {
            return "Unknown provider"
        }
        var id = String(provider.providerId || "")
        return id.substring(0, 8) + "  " + String(provider.readiness || "unknown")
    }

    function stateLabel(value) {
        return String(value || "unknown").replace(/_/g, " ")
    }

    function track(requestId) {
        if (!requestId) {
            return
        }
        var next = Object.assign({}, pendingRequests)
        next[String(requestId)] = true
        pendingRequests = next
        pendingCount += 1
    }

    function finish(requestId) {
        var key = String(requestId)
        if (!pendingRequests[key]) {
            return
        }
        var next = Object.assign({}, pendingRequests)
        delete next[key]
        pendingRequests = next
        pendingCount = Math.max(0, pendingCount - 1)
    }

    function cancelPending() {
        if (adminClient && adminClient.cancel) {
            for (var requestId in pendingRequests) {
                adminClient.cancel(Number(requestId))
            }
        }
        pendingRequests = ({})
        pendingCount = 0
    }

    function refreshAll() {
        cancelPending()
        generation += 1
        noticeText = ""
        noticeError = false
        if (!adminClient || !canLiveManage) {
            providers = []
            sessions = []
            destinationRules = []
            keyState = ({})
            selectedProviderIndex = -1
            return
        }
        track(adminClient.listAdminProviders(generation))
        track(adminClient.listAdminSessions(generation))
        if (canManageKeys) {
            track(adminClient.getAdminKeyState(generation))
        }
        if (canManageDestinations && selectedProviderId !== "") {
            track(adminClient.listAdminDestinationRules(selectedProviderId, generation))
        }
    }

    function loadDestinationRules() {
        destinationRules = []
        selectedRuleId = ""
        clearRuleDraft()
        if (adminClient && canManageDestinations && selectedProviderId !== "") {
            track(adminClient.listAdminDestinationRules(selectedProviderId, generation))
        }
    }

    function showNotice(text, error) {
        noticeText = String(text || "")
        noticeError = error === true
    }

    function beginAction(action, title, detail, payload) {
        pendingAction = action
        pendingTitle = title
        pendingDetail = detail
        pendingPayload = payload || ({})
        mutationDialog.open()
    }

    function executePendingAction() {
        if (!adminClient) {
            return
        }
        var payload = pendingPayload
        var requestId = 0
        if (pendingAction === "providerDisable") {
            requestId = adminClient.disableAdminProvider(
                        payload.providerId, payload.revision, generation)
        } else if (pendingAction === "ruleCreate") {
            requestId = adminClient.createAdminDestinationRule(
                        payload.providerId, payload.providerRevision,
                        payload.rule, generation)
        } else if (pendingAction === "ruleUpdate") {
            requestId = adminClient.updateAdminDestinationRule(
                        payload.providerId, payload.ruleId, payload.revision,
                        payload.rule, generation)
        } else if (pendingAction === "ruleDelete") {
            requestId = adminClient.deleteAdminDestinationRule(
                        payload.providerId, payload.ruleId, payload.revision,
                        generation)
        } else if (pendingAction === "grantSet") {
            requestId = adminClient.setAdminProviderGrant(
                        payload.providerId, payload.profileId,
                        payload.canBrowse, payload.canPlay,
                        payload.revision, generation)
        } else if (pendingAction === "grantRevoke") {
            requestId = adminClient.revokeAdminProviderGrant(
                        payload.providerId, payload.profileId,
                        payload.revision, generation)
        } else if (pendingAction === "sessionTerminate") {
            requestId = adminClient.terminateAdminSession(
                        payload.sessionId, payload.revision, generation)
        } else if (pendingAction === "keyRotate") {
            requestId = adminClient.rotateAdminKey(
                        payload.domain, payload.keyId, payload.revision,
                        generation)
        }
        track(requestId)
        pendingAction = ""
        pendingPayload = ({})
    }

    function ruleDraft() {
        return {
            scheme: String(ruleScheme.currentValue || ""),
            host: ruleHost.text.trim(),
            port: rulePort.value,
            path: rulePath.text.trim(),
            networkScope: String(ruleScope.currentValue || ""),
            allowFetch: allowFetch.checked,
            allowCredentials: allowCredentials.checked,
            allowClientDisclosure: allowDisclosure.checked
        }
    }

    function ruleDraftValid() {
        var rule = ruleDraft()
        if (rule.host === "" || rule.path === "" || rule.path[0] !== "/") {
            return false
        }
        if ((rule.allowCredentials || rule.allowClientDisclosure)
                && (rule.scheme !== "https" || !rule.allowFetch)) {
            return false
        }
        if ((rule.scheme === "rtmp" || rule.scheme === "srt")
                && (!rule.allowFetch || rule.allowCredentials
                    || rule.allowClientDisclosure)) {
            return false
        }
        return rule.networkScope !== "private_lan" || !rule.allowClientDisclosure
    }

    function clearRuleDraft() {
        selectedRuleId = ""
        ruleScheme.currentIndex = 1
        ruleHost.text = ""
        rulePort.value = 443
        rulePath.text = "/"
        ruleScope.currentIndex = 0
        allowFetch.checked = true
        allowCredentials.checked = false
        allowDisclosure.checked = false
    }

    function editRule(rule) {
        selectedRuleId = String(rule.ruleId || "")
        ruleScheme.currentIndex = Math.max(0, ruleScheme.indexOfValue(rule.scheme))
        ruleHost.text = String(rule.host || "")
        rulePort.value = Number(rule.port || 443)
        rulePath.text = String(rule.path || "/")
        ruleScope.currentIndex = Math.max(0, ruleScope.indexOfValue(rule.networkScope))
        allowFetch.checked = rule.allowFetch === true
        allowCredentials.checked = rule.allowCredentials === true
        allowDisclosure.checked = rule.allowClientDisclosure === true
    }

    function selectedRule() {
        for (var i = 0; i < destinationRules.length; ++i) {
            if (String(destinationRules[i].ruleId || "") === selectedRuleId) {
                return destinationRules[i]
            }
        }
        return null
    }

    function queueRuleSave() {
        if (!selectedProvider || !ruleDraftValid()) {
            showNotice("Destination rule fields are invalid.", true)
            return
        }
        var draft = ruleDraft()
        var existing = selectedRule()
        if (existing) {
            beginAction("ruleUpdate", "Update destination rule",
                        "Replace revision " + existing.revision + " for " + existing.host + ".",
                        { providerId: selectedProviderId,
                          ruleId: existing.ruleId,
                          revision: existing.revision,
                          rule: draft })
        } else {
            beginAction("ruleCreate", "Create destination rule",
                        "Approve " + draft.scheme + "://" + draft.host + ":" + draft.port + draft.path + ".",
                        { providerId: selectedProviderId,
                          providerRevision: selectedProvider.providerRevision,
                          rule: draft })
        }
    }

    function queueRuleDelete(rule) {
        beginAction("ruleDelete", "Delete destination rule",
                    "Delete " + rule.scheme + "://" + rule.host + ":" + rule.port + rule.path + ". Active sessions may end.",
                    { providerId: selectedProviderId,
                      ruleId: rule.ruleId,
                      revision: rule.revision })
    }

    function queueProviderDisable() {
        if (!selectedProvider) {
            return
        }
        beginAction("providerDisable", "Disable Live provider",
                    "Disable provider " + selectedProviderId + " and terminate its Live sessions.",
                    { providerId: selectedProviderId,
                      revision: selectedProvider.providerRevision })
    }

    function queueGrant(revoke) {
        var profile = grantProfile.currentIndex >= 0
                ? profiles()[grantProfile.currentIndex] : null
        var id = profileId(profile)
        if (!selectedProvider || id === "") {
            showNotice("Select a provider and profile.", true)
            return
        }
        beginAction(revoke ? "grantRevoke" : "grantSet",
                    revoke ? "Revoke Live access" : "Set Live access",
                    (revoke ? "Revoke" : "Update") + " Live access for " + profileName(profile) + ".",
                    { providerId: selectedProviderId,
                      profileId: id,
                      canBrowse: revoke ? false : grantBrowse.checked,
                      canPlay: revoke ? false : grantPlay.checked,
                      revision: selectedProvider.grantRevision })
    }

    function queueSessionTerminate(session) {
        beginAction("sessionTerminate", "Terminate Live session",
                    "Terminate session " + String(session.sessionId || "") + ".",
                    { sessionId: session.sessionId, revision: session.revision })
    }

    function queueKeyRotation() {
        var keyId = keyTarget.text.trim()
        if (keyId === "" || !keyState.revision) {
            showNotice("Enter a configured key ID.", true)
            return
        }
        beginAction("keyRotate", "Rotate Live key",
                    "Set " + keyDomain.currentText + " primary to " + keyId + ".",
                    { domain: keyDomain.currentValue,
                      keyId: keyId,
                      revision: keyState.revision })
    }

    function currentKey(domain) {
        if (domain === "envelope") {
            return String(keyState.envelopePrimaryKeyId || "Unavailable")
        }
        if (domain === "token_hash") {
            return String(keyState.tokenHashPrimaryKeyId || "Unavailable")
        }
        return String(keyState.auditPrimaryKeyId || "Unavailable")
    }

    Connections {
        target: root.adminClient
        ignoreUnknownSignals: true

        function onAdminResponseReceived(requestId, responseGeneration, operation, data) {
            root.finish(requestId)
            if (responseGeneration !== root.generation) {
                return
            }
            if (operation === "adminProviders") {
                var previous = root.selectedProviderId
                root.providers = data || []
                root.selectedProviderIndex = root.providers.length > 0 ? 0 : -1
                for (var i = 0; i < root.providers.length; ++i) {
                    if (String(root.providers[i].providerId || "") === previous) {
                        root.selectedProviderIndex = i
                        break
                    }
                }
                if (root.canManageDestinations) {
                    root.loadDestinationRules()
                }
            } else if (operation === "adminSessions") {
                root.sessions = data || []
            } else if (operation === "destinationRules") {
                root.destinationRules = data || []
            } else if (operation === "keyState") {
                root.keyState = data || ({})
            } else {
                root.showNotice("Live administrative change completed.", false)
                root.track(root.adminClient.listAdminProviders(root.generation))
                root.track(root.adminClient.listAdminSessions(root.generation))
                if (root.canManageKeys) {
                    root.track(root.adminClient.getAdminKeyState(root.generation))
                }
            }
        }

        function onRequestFailed(requestId, responseGeneration, endpoint, error) {
            if (String(endpoint || "").indexOf("/api/v1/live/admin") !== 0) {
                return
            }
            root.finish(requestId)
            if (responseGeneration !== root.generation) {
                return
            }
            root.showNotice(String(error.message || error.code || "Live administration failed."), true)
        }

        function onRequestCancelled(requestId) {
            root.finish(requestId)
        }

        function onAuthContextInvalidated() {
            root.refreshAll()
        }
    }

    Component.onCompleted: Qt.callLater(refreshAll)
    Component.onDestruction: cancelPending()

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + Theme.spacingXLarge * 2
        clip: true

        ColumnLayout {
            id: contentColumn
            x: Theme.spacingXLarge
            y: Theme.spacingXLarge
            width: Math.max(0, parent.width - Theme.spacingXLarge * 2)
            spacing: Theme.spacingLarge

            GridLayout {
                Layout.fillWidth: true
                columns: width >= 720 ? 3 : 1
                columnSpacing: Theme.spacingMedium
                rowSpacing: Theme.spacingSmall

                Label {
                    text: "Live administration"
                    color: Theme.textPrimary
                    font.pixelSize: 24
                    font.family: Theme.fontDisplay
                    Layout.fillWidth: true
                }

                Button {
                    objectName: "liveAdminRefreshButton"
                    text: root.busy ? "Refreshing..." : "Refresh"
                    enabled: root.canLiveManage && !root.busy
                    Accessible.name: "Refresh Live administration"
                    onClicked: root.refreshAll()
                }

                Button {
                    objectName: "liveAdminBackButton"
                    text: "Back to settings"
                    visible: root.stackView !== null
                    Accessible.name: "Back to settings"
                    onClicked: root.stackView.pop()
                }
            }

            Rectangle {
                objectName: "liveAdminAccessDenied"
                Layout.fillWidth: true
                visible: !root.canLiveManage
                color: Theme.backgroundCard
                border.color: Theme.border
                radius: Theme.radiusSmall
                implicitHeight: deniedText.implicitHeight + Theme.spacingLarge * 2

                Label {
                    id: deniedText
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    text: "Live administration is not available for this profile."
                    color: Theme.textSecondary
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                }
            }

            Rectangle {
                objectName: "liveAdminNotice"
                Layout.fillWidth: true
                visible: root.noticeText !== ""
                color: root.noticeError ? "#3A2024" : "#20362D"
                border.color: root.noticeError ? "#D96B6B" : "#5FBF7F"
                radius: Theme.radiusSmall
                implicitHeight: noticeLabel.implicitHeight + Theme.spacingMedium * 2

                Label {
                    id: noticeLabel
                    objectName: "liveAdminNoticeText"
                    anchors.fill: parent
                    anchors.margins: Theme.spacingMedium
                    text: root.noticeText
                    color: Theme.textPrimary
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                }
            }

            Rectangle {
                objectName: "liveAdminProviderSection"
                Layout.fillWidth: true
                visible: root.canLiveManage
                color: Theme.backgroundCard
                border.color: Theme.border
                radius: Theme.radiusSmall
                implicitHeight: providerContent.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: providerContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        text: "Providers"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    ComboBox {
                        id: providerPicker
                        objectName: "liveAdminProviderPicker"
                        Layout.fillWidth: true
                        model: root.providers
                        currentIndex: root.selectedProviderIndex
                        displayText: root.providerLabel(root.selectedProvider)
                        Accessible.name: "Live provider"
                        delegate: ItemDelegate {
                            width: providerPicker.width
                            text: root.providerLabel(modelData)
                        }
                        onActivated: function(index) {
                            root.selectedProviderIndex = index
                            root.loadDestinationRules()
                        }
                    }

                    Label {
                        visible: root.selectedProvider !== null
                        text: root.selectedProvider
                              ? "Status: " + root.stateLabel(root.selectedProvider.readiness)
                                + "   Sessions: " + root.selectedProvider.activeSessions
                                + "   Policy revision: " + root.selectedProvider.providerRevision
                                + "   Grant revision: " + root.selectedProvider.grantRevision
                              : ""
                        color: Theme.textSecondary
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    Button {
                        objectName: "liveAdminDisableProviderButton"
                        text: "Disable provider"
                        visible: root.canDisableProviders
                        enabled: root.selectedProvider && root.selectedProvider.enabled === true && !root.busy
                        Accessible.name: "Disable selected Live provider"
                        onClicked: root.queueProviderDisable()
                    }
                }
            }

            Rectangle {
                objectName: "liveAdminDestinationSection"
                Layout.fillWidth: true
                visible: root.canManageDestinations
                color: Theme.backgroundCard
                border.color: Theme.border
                radius: Theme.radiusSmall
                implicitHeight: destinationContent.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: destinationContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        text: "Destination policy"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Repeater {
                        model: root.destinationRules

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            color: Theme.backgroundCardRaised
                            border.color: String(modelData.ruleId || "") === root.selectedRuleId
                                          ? Theme.accent : Theme.border
                            radius: Theme.radiusSmall
                            implicitHeight: ruleRow.implicitHeight + Theme.spacingMedium * 2

                            RowLayout {
                                id: ruleRow
                                anchors.fill: parent
                                anchors.margins: Theme.spacingMedium
                                spacing: Theme.spacingSmall

                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.scheme + "://" + modelData.host + ":"
                                          + modelData.port + modelData.path
                                          + "  r" + modelData.revision
                                    color: Theme.textPrimary
                                    wrapMode: Text.WrapAnywhere
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                }

                                Button {
                                    text: "Edit"
                                    Accessible.name: "Edit destination rule"
                                    onClicked: root.editRule(modelData)
                                }

                                Button {
                                    text: "Delete"
                                    Accessible.name: "Delete destination rule"
                                    onClicked: root.queueRuleDelete(modelData)
                                }
                            }
                        }
                    }

                    Label {
                        visible: root.destinationRules.length === 0
                        text: "No destination rules."
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= 760 ? 4 : (width >= 440 ? 2 : 1)
                        columnSpacing: Theme.spacingSmall
                        rowSpacing: Theme.spacingSmall

                        ComboBox {
                            id: ruleScheme
                            objectName: "liveAdminRuleScheme"
                            Layout.fillWidth: true
                            model: [{ label: "HTTP", value: "http" },
                                    { label: "HTTPS", value: "https" },
                                    { label: "RTMP", value: "rtmp" },
                                    { label: "SRT", value: "srt" }]
                            textRole: "label"
                            valueRole: "value"
                            currentIndex: 1
                            Accessible.name: "Destination scheme"
                        }

                        TextField {
                            id: ruleHost
                            objectName: "liveAdminRuleHost"
                            Layout.fillWidth: true
                            placeholderText: "origin.example"
                            maximumLength: 253
                            Accessible.name: "Destination host"
                        }

                        SpinBox {
                            id: rulePort
                            objectName: "liveAdminRulePort"
                            Layout.fillWidth: true
                            from: 1
                            to: 65535
                            value: 443
                            editable: true
                            Accessible.name: "Destination port"
                        }

                        TextField {
                            id: rulePath
                            objectName: "liveAdminRulePath"
                            Layout.fillWidth: true
                            text: "/"
                            maximumLength: 2048
                            Accessible.name: "Destination path prefix"
                        }

                        ComboBox {
                            id: ruleScope
                            objectName: "liveAdminRuleScope"
                            Layout.fillWidth: true
                            model: [{ label: "Public", value: "public" },
                                    { label: "Private LAN", value: "private_lan" }]
                            textRole: "label"
                            valueRole: "value"
                            Accessible.name: "Destination network scope"
                        }

                        CheckBox {
                            id: allowFetch
                            objectName: "liveAdminAllowFetch"
                            text: "Allow fetch"
                            checked: true
                            Accessible.name: text
                        }

                        CheckBox {
                            id: allowCredentials
                            objectName: "liveAdminAllowCredentials"
                            text: "Allow credentials"
                            Accessible.name: text
                        }

                        CheckBox {
                            id: allowDisclosure
                            objectName: "liveAdminAllowDisclosure"
                            text: "Allow client disclosure"
                            Accessible.name: text
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Button {
                            objectName: "liveAdminSaveRuleButton"
                            text: root.selectedRuleId === "" ? "Create rule" : "Update rule"
                            enabled: root.selectedProvider !== null && root.ruleDraftValid() && !root.busy
                            Accessible.name: text
                            onClicked: root.queueRuleSave()
                        }

                        Button {
                            text: "Clear editor"
                            Accessible.name: "Clear destination rule editor"
                            onClicked: root.clearRuleDraft()
                        }
                    }
                }
            }

            Rectangle {
                objectName: "liveAdminGrantSection"
                Layout.fillWidth: true
                visible: root.canManageGrants
                color: Theme.backgroundCard
                border.color: Theme.border
                radius: Theme.radiusSmall
                implicitHeight: grantContent.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: grantContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        text: "Profile access"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    ComboBox {
                        id: grantProfile
                        objectName: "liveAdminGrantProfile"
                        Layout.fillWidth: true
                        model: root.profiles()
                        displayText: root.profileName(currentIndex >= 0 ? root.profiles()[currentIndex] : null)
                        Accessible.name: "Profile for Live access"
                        delegate: ItemDelegate {
                            width: grantProfile.width
                            text: root.profileName(modelData)
                        }
                    }

                    RowLayout {
                        CheckBox {
                            id: grantBrowse
                            objectName: "liveAdminGrantBrowse"
                            text: "Browse"
                            checked: true
                            onToggled: if (!checked) grantPlay.checked = false
                        }
                        CheckBox {
                            id: grantPlay
                            objectName: "liveAdminGrantPlay"
                            text: "Play"
                            checked: true
                            enabled: grantBrowse.checked
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall
                        Button {
                            objectName: "liveAdminSetGrantButton"
                            text: "Set access"
                            enabled: root.selectedProvider && grantProfile.currentIndex >= 0 && !root.busy
                            Accessible.name: "Set profile Live access"
                            onClicked: root.queueGrant(false)
                        }
                        Button {
                            objectName: "liveAdminRevokeGrantButton"
                            text: "Revoke access"
                            enabled: root.selectedProvider && grantProfile.currentIndex >= 0 && !root.busy
                            Accessible.name: "Revoke profile Live access"
                            onClicked: root.queueGrant(true)
                        }
                    }
                }
            }

            Rectangle {
                objectName: "liveAdminSessionSection"
                Layout.fillWidth: true
                visible: root.canLiveManage
                color: Theme.backgroundCard
                border.color: Theme.border
                radius: Theme.radiusSmall
                implicitHeight: sessionContent.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: sessionContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        text: "Sessions"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Repeater {
                        model: root.sessions
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                            radius: Theme.radiusSmall
                            implicitHeight: sessionRow.implicitHeight + Theme.spacingMedium * 2

                            RowLayout {
                                id: sessionRow
                                anchors.fill: parent
                                anchors.margins: Theme.spacingMedium
                                spacing: Theme.spacingSmall

                                Label {
                                    Layout.fillWidth: true
                                    text: String(modelData.sessionId || "")
                                          + "\n" + root.stateLabel(modelData.state)
                                          + "  " + root.stateLabel(modelData.deliveryMode)
                                          + "  r" + modelData.revision
                                    color: Theme.textPrimary
                                    wrapMode: Text.WrapAnywhere
                                    font.pixelSize: 11
                                    font.family: Theme.fontBody
                                }

                                Button {
                                    objectName: "liveAdminTerminateSessionButton"
                                    text: "Terminate"
                                    enabled: modelData.state !== "ended"
                                             && modelData.state !== "expired"
                                             && modelData.state !== "failed"
                                             && !root.busy
                                    Accessible.name: "Terminate Live session"
                                    onClicked: root.queueSessionTerminate(modelData)
                                }
                            }
                        }
                    }

                    Label {
                        visible: root.sessions.length === 0
                        text: "No active or failed sessions."
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }
                }
            }

            Rectangle {
                objectName: "liveAdminKeySection"
                Layout.fillWidth: true
                visible: root.canManageKeys
                color: Theme.backgroundCard
                border.color: Theme.border
                radius: Theme.radiusSmall
                implicitHeight: keyContent.implicitHeight + Theme.spacingLarge * 2

                ColumnLayout {
                    id: keyContent
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        text: "Cryptographic keys"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        objectName: "liveAdminKeyState"
                        Layout.fillWidth: true
                        text: "Envelope: " + root.currentKey("envelope")
                              + "\nToken hash: " + root.currentKey("token_hash")
                              + "\nAudit: " + root.currentKey("audit")
                              + "\nRevision: " + String(root.keyState.revision || "Unavailable")
                        color: Theme.textSecondary
                        wrapMode: Text.WrapAnywhere
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= 560 ? 2 : 1
                        columnSpacing: Theme.spacingSmall
                        rowSpacing: Theme.spacingSmall

                        ComboBox {
                            id: keyDomain
                            objectName: "liveAdminKeyDomain"
                            Layout.fillWidth: true
                            model: [{ label: "Envelope", value: "envelope" },
                                    { label: "Token hash", value: "token_hash" },
                                    { label: "Audit", value: "audit" }]
                            textRole: "label"
                            valueRole: "value"
                            Accessible.name: "Live key domain"
                        }

                        TextField {
                            id: keyTarget
                            objectName: "liveAdminKeyTarget"
                            Layout.fillWidth: true
                            placeholderText: "Configured key ID"
                            maximumLength: 32
                            Accessible.name: "Configured Live key ID"
                        }
                    }

                    Button {
                        objectName: "liveAdminRotateKeyButton"
                        text: "Rotate primary key"
                        enabled: keyTarget.text.trim() !== ""
                                 && root.keyState.revision > 0 && !root.busy
                        Accessible.name: "Rotate selected Live primary key"
                        onClicked: root.queueKeyRotation()
                    }
                }
            }
        }
    }

    Dialog {
        id: mutationDialog
        objectName: "liveAdminConfirmationDialog"
        parent: Overlay.overlay
        modal: true
        anchors.centerIn: parent
        width: Math.min(520, Math.max(280, root.width - Theme.spacingLarge * 2))
        title: root.pendingTitle
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: root.executePendingAction()
        onRejected: {
            root.pendingAction = ""
            root.pendingPayload = ({})
        }

        Label {
            width: parent.width
            text: root.pendingDetail
            color: Theme.textPrimary
            wrapMode: Text.WordWrap
            font.pixelSize: 12
            font.family: Theme.fontBody
        }
    }
}
