import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "connectView"
    property StackView stackView: null
    property string notice: ""
    property string statusText: ""
    property string controlPlaneStatusText: ""
    property string resetStatusText: ""
    property string resetToken: ""
    property bool autoSelectEnabled: true
    property bool advancedOpen: false
    property bool wideLayout: width >= 1060

    function normalizeEndpoint(endpoint) {
        var trimmed = (endpoint || "").trim()
        if (trimmed === "") return ""
        if (!trimmed.startsWith("http://") && !trimmed.startsWith("https://")) trimmed = "http://" + trimmed
        while (trimmed.endsWith("/")) trimmed = trimmed.slice(0, -1)
        return trimmed
    }

    function pickBestCandidate(model, desiredServerId) {
        if (!model || model.count === 0) return null
        var best = null
        for (var i = 0; i < model.count; i++) {
            var entry = model.get(i)
            if (!entry) continue
            if (desiredServerId && entry.serverId !== desiredServerId) continue
            var endpoint = entry.selectedEndpoint || ""
            if (endpoint === "") continue
            var score = 0
            if (entry.selectedReachable) score += 2
            var preferred = sessionManager.networkType || "auto"
            if (preferred === "wan") {
                if (entry.selectedNetwork === "wan") score += 1
            } else if (entry.selectedNetwork === "lan") {
                score += 1
            }
            if (!best || score > best.score) {
                best = { endpoint: endpoint, network: entry.selectedNetwork || "", serverId: entry.serverId || "", score: score }
            }
        }
        return best
    }

    function requestAutoSelect() {
        if (autoSelectEnabled) autoSelectTimer.restart()
    }

    function applyAutoSelection() {
        if (!autoSelectEnabled) return
        var candidate = null
        if (sessionManager.selectedServerId !== "") candidate = pickBestCandidate(serverDiscovery.registryModel, sessionManager.selectedServerId)
        if (!candidate) candidate = pickBestCandidate(serverDiscovery.mdnsModel, "")
        if (!candidate) candidate = pickBestCandidate(serverDiscovery.registryModel, "")
        if (!candidate || !candidate.endpoint) return
        var normalized = normalizeEndpoint(candidate.endpoint)
        if (normalized === "") return
        if (sessionManager.baseUrl !== normalized) sessionManager.baseUrl = normalized
        if (candidate.serverId !== "" && sessionManager.selectedServerId !== candidate.serverId) sessionManager.selectedServerId = candidate.serverId
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.appBg
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#232017" }
            GradientStop { position: 0.45; color: Theme.appBg }
            GradientStop { position: 1.0; color: "#0D0D0F" }
        }
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth

        GridLayout {
            width: Math.min(Math.max(320, root.width - Theme.space56), 1240)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Theme.space40
            anchors.bottomMargin: Theme.space56
            columns: root.wideLayout ? 2 : 1
            rowSpacing: Theme.space32
            columnSpacing: Theme.space32

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: root.wideLayout ? 500 : parent.width
                Layout.minimumHeight: 600
                radius: Theme.radius8
                color: "#E51B1D21"
                border.color: Qt.rgba(1, 1, 1, 0.08)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.space32
                    spacing: Theme.space20

                    RowLayout {
                        spacing: Theme.space12
                        Rectangle {
                            width: 42
                            height: 42
                            radius: Theme.radius8
                            color: Theme.accent
                            Label {
                                anchors.centerIn: parent
                                text: "E"
                                color: "#17120A"
                                font.family: Theme.fontDisplay
                                font.pixelSize: 24
                                font.weight: Font.Bold
                            }
                        }
                        ColumnLayout {
                            spacing: 0
                            Label {
                                text: "Elixir"
                                color: Theme.textPrimary
                                font.family: Theme.fontDisplay
                                font.pixelSize: 24
                                font.weight: Font.Bold
                            }
                            Label {
                                text: "Personal media server"
                                color: Theme.textMuted
                                font.family: Theme.fontBody
                                font.pixelSize: 12
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space8
                        Label {
                            text: "Connect to your server"
                            color: Theme.textPrimary
                            font.family: Theme.fontDisplay
                            font.pixelSize: 34
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }
                        Label {
                            text: "Pick a discovered endpoint or enter one manually, then sign in to browse your library."
                            color: Theme.textSecondary
                            font.family: Theme.fontBody
                            font.pixelSize: 14
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radius6
                        color: Theme.surface
                        border.color: Theme.borderSubtle
                        visible: root.notice !== ""
                        implicitHeight: noticeLabel.implicitHeight + Theme.space24
                        Label {
                            id: noticeLabel
                            anchors.fill: parent
                            anchors.margins: Theme.space12
                            text: root.notice
                            color: Theme.textSecondary
                            font.family: Theme.fontBody
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space8
                        Label {
                            text: "Server address"
                            color: Theme.textSecondary
                            font.family: Theme.fontBody
                            font.pixelSize: 12
                        }
                        TextField {
                            Layout.fillWidth: true
                            text: sessionManager.baseUrl
                            placeholderText: "http://192.168.1.10:44301"
                            color: Theme.textPrimary
                            placeholderTextColor: Theme.textMuted
                            selectByMouse: true
                            onTextChanged: sessionManager.baseUrl = text
                            onTextEdited: {
                                autoSelectEnabled = false
                                sessionManager.selectedServerId = ""
                            }
                            background: Rectangle {
                                radius: Theme.radius6
                                color: Theme.surface
                                border.color: parent.activeFocus ? Theme.accent : Theme.borderSubtle
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space12
                        Label {
                            text: "Network"
                            color: Theme.textSecondary
                            font.family: Theme.fontBody
                            font.pixelSize: 12
                        }
                        ComboBox {
                            Layout.preferredWidth: 130
                            model: ["auto", "lan", "wan"]
                            currentIndex: model.indexOf(sessionManager.networkType)
                            onActivated: {
                                sessionManager.networkType = model[index]
                                requestAutoSelect()
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.borderSubtle
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space8
                        Label {
                            text: "Account"
                            color: Theme.textPrimary
                            font.family: Theme.fontDisplay
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }
                        TextField {
                            Layout.fillWidth: true
                            text: sessionManager.email
                            placeholderText: "you@example.com"
                            inputMethodHints: Qt.ImhEmailCharactersOnly
                            color: Theme.textPrimary
                            placeholderTextColor: Theme.textMuted
                            selectByMouse: true
                            onTextChanged: sessionManager.email = text
                            background: Rectangle {
                                radius: Theme.radius6
                                color: Theme.surface
                                border.color: parent.activeFocus ? Theme.accent : Theme.borderSubtle
                            }
                        }
                        TextField {
                            id: passwordField
                            Layout.fillWidth: true
                            placeholderText: "Password"
                            echoMode: TextInput.Password
                            color: Theme.textPrimary
                            placeholderTextColor: Theme.textMuted
                            selectByMouse: true
                            background: Rectangle {
                                radius: Theme.radius6
                                color: Theme.surface
                                border.color: parent.activeFocus ? Theme.accent : Theme.borderSubtle
                            }
                        }
                        CheckBox {
                            checked: true
                            text: "Remember this device"
                            enabled: false
                            opacity: 0.7
                            contentItem: Label {
                                text: parent.text
                                color: Theme.textSecondary
                                font.family: Theme.fontBody
                                font.pixelSize: 12
                                verticalAlignment: Text.AlignVCenter
                                leftPadding: parent.indicator.width + parent.spacing
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space12
                        ActionButton {
                            text: "Sign in"
                            variant: "primary"
                            onClicked: {
                                statusText = "Signing in..."
                                apiClient.login(sessionManager.email, passwordField.text)
                            }
                        }
                        ActionButton {
                            text: "Create account"
                            onClicked: {
                                statusText = "Creating account..."
                                apiClient.signup(sessionManager.email, passwordField.text)
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    ActionButton {
                        text: "Forgot password?"
                        variant: "ghost"
                        compact: true
                        onClicked: resetDialog.open()
                    }

                    InlineToast {
                        Layout.fillWidth: true
                        text: statusText
                        autoClear: false
                        color: statusText.indexOf("failed") >= 0 || statusText.indexOf("Request failed") >= 0 ? Theme.danger : Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        wrapMode: Text.Wrap
                    }

                    Item { Layout.fillHeight: true }

                    ActionButton {
                        text: root.advancedOpen ? "Hide advanced connection" : "Advanced connection"
                        variant: "ghost"
                        compact: true
                        onClicked: root.advancedOpen = !root.advancedOpen
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space8
                        visible: root.advancedOpen

                        TextField {
                            Layout.fillWidth: true
                            text: sessionManager.registryUrl
                            placeholderText: "Control plane URL"
                            color: Theme.textPrimary
                            placeholderTextColor: Theme.textMuted
                            onTextChanged: sessionManager.registryUrl = text
                            background: Rectangle {
                                radius: Theme.radius6
                                color: Theme.surface
                                border.color: parent.activeFocus ? Theme.accent : Theme.borderSubtle
                            }
                        }
                        TextField {
                            Layout.fillWidth: true
                            text: sessionManager.controlPlaneEmail
                            placeholderText: "Control plane email"
                            color: Theme.textPrimary
                            placeholderTextColor: Theme.textMuted
                            inputMethodHints: Qt.ImhEmailCharactersOnly
                            onTextChanged: sessionManager.controlPlaneEmail = text
                            background: Rectangle {
                                radius: Theme.radius6
                                color: Theme.surface
                                border.color: parent.activeFocus ? Theme.accent : Theme.borderSubtle
                            }
                        }
                        TextField {
                            id: controlPlanePasswordField
                            Layout.fillWidth: true
                            placeholderText: "Control plane password"
                            echoMode: TextInput.Password
                            color: Theme.textPrimary
                            placeholderTextColor: Theme.textMuted
                            background: Rectangle {
                                radius: Theme.radius6
                                color: Theme.surface
                                border.color: parent.activeFocus ? Theme.accent : Theme.borderSubtle
                            }
                        }
                        RowLayout {
                            spacing: Theme.space8
                            ActionButton {
                                text: "Control sign in"
                                compact: true
                                onClicked: {
                                    controlPlaneStatusText = "Signing in to control plane..."
                                    controlPlaneClient.login(sessionManager.controlPlaneEmail, controlPlanePasswordField.text)
                                }
                            }
                            ActionButton {
                                text: "Create control account"
                                compact: true
                                onClicked: {
                                    controlPlaneStatusText = "Creating control plane account..."
                                    controlPlaneClient.signup(sessionManager.controlPlaneEmail, controlPlanePasswordField.text)
                                }
                            }
                        }
                        Label {
                            text: controlPlaneStatusText
                            color: Theme.textMuted
                            font.family: Theme.fontBody
                            font.pixelSize: 11
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredWidth: root.wideLayout ? 700 : parent.width
                Layout.minimumHeight: 600
                radius: Theme.radius8
                color: "#B51F2024"
                border.color: Qt.rgba(1, 1, 1, 0.08)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.space32
                    spacing: Theme.space20

                    SectionHeader {
                        Layout.fillWidth: true
                        title: "Available Servers"
                        subtitle: "Elixir will prefer reachable LAN endpoints when available."
                    }

                    RowLayout {
                        spacing: Theme.space8
                        ActionButton {
                            text: "Refresh LAN"
                            compact: true
                            onClicked: serverDiscovery.refreshMdns()
                        }
                        ActionButton {
                            text: "Probe"
                            compact: true
                            onClicked: serverDiscovery.probeAll()
                        }
                        ActionButton {
                            text: "Refresh registry"
                            compact: true
                            enabled: controlPlaneClient.authToken !== ""
                            onClicked: serverDiscovery.refreshRegistry()
                        }
                    }

                    Label {
                        text: "Local"
                        color: Theme.textPrimary
                        font.family: Theme.fontDisplay
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space8
                        Repeater {
                            model: serverDiscovery.mdnsModel
                            delegate: ServerListItem {
                                Layout.fillWidth: true
                                name: model.name || ""
                                source: model.source || ""
                                status: model.status || ""
                                lastSeenAt: model.lastSeenAt || ""
                                selectedEndpoint: model.selectedEndpoint || ""
                                selectedNetwork: model.selectedNetwork || ""
                                selectedReachable: model.selectedReachable === true
                                onUseRequested: function(endpoint, network) {
                                    autoSelectEnabled = false
                                    sessionManager.baseUrl = normalizeEndpoint(endpoint)
                                    sessionManager.selectedServerId = ""
                                    if (network !== "") sessionManager.networkType = network
                                }
                            }
                        }
                        EmptyState {
                            Layout.fillWidth: true
                            implicitHeight: 120
                            title: "No LAN servers yet"
                            message: "Make sure the server is running, then refresh LAN discovery."
                            visible: serverDiscovery.mdnsModel.count === 0
                        }
                    }

                    Label {
                        text: "Registry"
                        color: Theme.textPrimary
                        font.family: Theme.fontDisplay
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space8
                        Repeater {
                            model: serverDiscovery.registryModel
                            delegate: ServerListItem {
                                Layout.fillWidth: true
                                name: model.name || ""
                                source: model.source || ""
                                status: model.status || ""
                                lastSeenAt: model.lastSeenAt || ""
                                selectedEndpoint: model.selectedEndpoint || ""
                                selectedNetwork: model.selectedNetwork || ""
                                selectedReachable: model.selectedReachable === true
                                onUseRequested: function(endpoint, network) {
                                    autoSelectEnabled = true
                                    sessionManager.baseUrl = normalizeEndpoint(endpoint)
                                    sessionManager.selectedServerId = model.serverId || ""
                                    if (network !== "") sessionManager.networkType = network
                                    requestAutoSelect()
                                }
                            }
                        }
                        Label {
                            text: controlPlaneClient.authToken === "" ? "Sign in through Advanced connection to load registry servers." : "No registry servers found."
                            color: Theme.textMuted
                            font.family: Theme.fontBody
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                            visible: serverDiscovery.registryModel.count === 0
                        }
                    }

                    Item { Layout.fillHeight: true }

                    Label {
                        text: serverDiscovery.statusMessage
                        color: Theme.textMuted
                        font.family: Theme.fontBody
                        font.pixelSize: 11
                        wrapMode: Text.Wrap
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }

    Connections {
        target: apiClient
        function onLoginSucceeded() {
            statusText = "Login successful. Loading library..."
            apiClient.fetchLibrary()
            if (root.stackView) {
                root.stackView.clear()
                root.stackView.push(Qt.resolvedUrl("HomeView.qml"), { stackView: root.stackView })
            }
        }
        function onLoginFailed(error) { statusText = "Login failed: " + error }
        function onRequestFailed(endpoint, error) {
            if (endpoint.indexOf("/api/v1/auth") === 0) statusText = "Request failed: " + error
        }
        function onPasswordResetStarted(token, expiresAt) {
            resetToken = token
            resetStatusText = "Reset token generated. Expires at " + expiresAt
        }
        function onPasswordResetCompleted() { resetStatusText = "Password reset complete. You can sign in now." }
        function onPasswordResetFailed(error) { resetStatusText = "Reset failed: " + error }
    }

    Connections {
        target: controlPlaneClient
        function onLoginSucceeded() {
            controlPlaneStatusText = "Control plane authenticated."
            serverDiscovery.refreshRegistry()
        }
        function onLoginFailed(error) { controlPlaneStatusText = "Control plane login failed: " + error }
        function onRequestFailed(endpoint, error) { controlPlaneStatusText = "Control plane error: " + error }
        function onAuthExpired(message) {
            controlPlaneStatusText = message !== "" ? message : "Control plane session expired."
            sessionManager.clearControlPlaneAuth()
        }
    }

    Component.onCompleted: {
        serverDiscovery.refreshMdns()
        if (controlPlaneClient.authToken !== "") serverDiscovery.refreshRegistry()
        requestAutoSelect()
    }

    Connections {
        target: serverDiscovery.mdnsModel
        function onCountChanged() { requestAutoSelect() }
        function onDataChanged(topLeft, bottomRight, roles) { requestAutoSelect() }
    }

    Connections {
        target: serverDiscovery.registryModel
        function onCountChanged() { requestAutoSelect() }
        function onDataChanged(topLeft, bottomRight, roles) { requestAutoSelect() }
    }

    Connections {
        target: sessionManager
        function onSelectedServerIdChanged() { requestAutoSelect() }
        function onNetworkTypeChanged() { requestAutoSelect() }
    }

    Timer {
        id: autoSelectTimer
        interval: 200
        repeat: false
        onTriggered: applyAutoSelection()
    }

    Dialog {
        id: resetDialog
        modal: true
        focus: true
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        width: Math.min(root.width * 0.6, 520)
        background: Rectangle {
            color: Theme.surface
            radius: Theme.radius8
            border.color: Theme.borderSubtle
        }
        contentItem: ColumnLayout {
            spacing: Theme.space12
            Label {
                text: "Reset password"
                color: Theme.textPrimary
                font.pixelSize: 20
                font.family: Theme.fontDisplay
                font.weight: Font.DemiBold
            }
            Label {
                text: "Generate a reset token, then set a new password."
                color: Theme.textSecondary
                font.pixelSize: 13
                font.family: Theme.fontBody
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            TextField {
                id: resetEmailField
                Layout.fillWidth: true
                text: sessionManager.email
                placeholderText: "Email"
                onTextChanged: sessionManager.email = text
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                TextField {
                    id: resetTokenField
                    Layout.fillWidth: true
                    text: resetToken
                    placeholderText: "Reset token"
                    onTextChanged: resetToken = text
                }
                ActionButton {
                    text: "Start reset"
                    compact: true
                    onClicked: {
                        resetStatusText = "Requesting reset token..."
                        apiClient.startPasswordReset(resetEmailField.text)
                    }
                }
            }
            TextField {
                id: resetPasswordField
                Layout.fillWidth: true
                placeholderText: "New password"
                echoMode: TextInput.Password
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space12
                ActionButton {
                    text: "Complete reset"
                    variant: "primary"
                    onClicked: {
                        resetStatusText = "Completing reset..."
                        apiClient.completePasswordReset(resetTokenField.text, resetPasswordField.text)
                    }
                }
                ActionButton {
                    text: "Close"
                    onClicked: resetDialog.close()
                }
            }
            InlineToast {
                Layout.fillWidth: true
                text: resetStatusText
                autoClear: false
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
                wrapMode: Text.Wrap
            }
        }
    }
}
