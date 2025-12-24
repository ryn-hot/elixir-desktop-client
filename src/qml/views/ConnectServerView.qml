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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingXLarge
        spacing: Theme.spacingLarge

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: parent.height * 0.35
            radius: Theme.radiusLarge
            color: Theme.backgroundCard
            border.color: Theme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingLarge
                spacing: Theme.spacingMedium

                Label {
                    text: "Connect to your Elixir server"
                    color: Theme.textPrimary
                    font.pixelSize: 24
                    font.family: Theme.fontDisplay
                    font.weight: Font.DemiBold
                }

                Label {
                    text: "Point the client at your home server and authenticate to load the library."
                    color: Theme.textSecondary
                    font.pixelSize: 13
                    font.family: Theme.fontBody
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    spacing: Theme.spacingMedium
                    PillTag { text: "Qt 6" }
                    PillTag { text: "QML" }
                    PillTag { text: "QTMPV" }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.spacingLarge

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Rectangle {
                        Layout.fillWidth: true
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                        visible: root.notice !== ""

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingMedium
                            spacing: Theme.spacingSmall

                            Label {
                                text: root.notice
                                color: Theme.textSecondary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                wrapMode: Text.Wrap
                            }
                        }
                    }

                    Label {
                        text: "Control plane"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    TextField {
                        text: sessionManager.registryUrl
                        placeholderText: "https://control.elixir.media"
                        onTextChanged: sessionManager.registryUrl = text
                    }

                    TextField {
                        text: sessionManager.controlPlaneEmail
                        placeholderText: "control@example.com"
                        inputMethodHints: Qt.ImhEmailCharactersOnly
                        onTextChanged: sessionManager.controlPlaneEmail = text
                    }

                    TextField {
                        id: controlPlanePasswordField
                        placeholderText: "Control plane password"
                        echoMode: TextInput.Password
                    }

                    RowLayout {
                        spacing: Theme.spacingMedium

                        Button {
                            text: "Control plane sign in"
                            onClicked: {
                                controlPlaneStatusText = "Signing in to control plane..."
                                controlPlaneClient.login(sessionManager.controlPlaneEmail, controlPlanePasswordField.text)
                            }
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                            }
                            contentItem: Label {
                                text: parent.text
                                color: Theme.textPrimary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Button {
                            text: "Create control plane account"
                            onClicked: {
                                controlPlaneStatusText = "Creating control plane account..."
                                controlPlaneClient.signup(sessionManager.controlPlaneEmail, controlPlanePasswordField.text)
                            }
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCard
                                border.color: Theme.border
                            }
                            contentItem: Label {
                                text: parent.text
                                color: Theme.textSecondary
                                font.pixelSize: 12
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    Label {
                        text: controlPlaneClient.authToken !== "" ? "Control plane authenticated" : "Control plane not signed in"
                        color: controlPlaneClient.authToken !== "" ? Theme.accent : Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                    }

                    Label {
                        text: controlPlaneStatusText
                        color: Theme.textSecondary
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        visible: controlPlaneStatusText !== ""
                    }

                    Rectangle {
                        height: 1
                        color: Theme.border
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "Server"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    TextField {
                        text: sessionManager.baseUrl
                        placeholderText: "http://192.168.1.10:44301"
                        onTextChanged: sessionManager.baseUrl = text
                    }

                    Label {
                        text: "Network profile"
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                    }

                    ComboBox {
                        model: ["auto", "lan", "wan"]
                        currentIndex: model.indexOf(sessionManager.networkType)
                        onActivated: sessionManager.networkType = model[index]
                    }

                    Label {
                        text: "Credentials"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    TextField {
                        text: sessionManager.email
                        placeholderText: "you@example.com"
                        inputMethodHints: Qt.ImhEmailCharactersOnly
                        onTextChanged: sessionManager.email = text
                    }

                    TextField {
                        id: passwordField
                        placeholderText: "Password"
                        echoMode: TextInput.Password
                    }

                    RowLayout {
                        spacing: Theme.spacingMedium

                        Button {
                            text: "Sign in"
                            onClicked: {
                                statusText = "Signing in..."
                                apiClient.login(sessionManager.email, passwordField.text)
                            }
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.accent
                            }
                            contentItem: Label {
                                text: parent.text
                                color: "#111111"
                                font.pixelSize: 13
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Button {
                            text: "Create account"
                            onClicked: {
                                statusText = "Creating account..."
                                apiClient.signup(sessionManager.email, passwordField.text)
                            }
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                            }
                            contentItem: Label {
                                text: parent.text
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    Button {
                        text: "Forgot password?"
                        onClicked: resetDialog.open()
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCard
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textSecondary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Label {
                        text: statusText
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        visible: statusText !== ""
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: parent.width * 0.35
                Layout.fillHeight: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCardRaised
                border.color: Theme.border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        text: "Server discovery"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        text: "Find servers on your LAN or via the registry, then pick the endpoint that matches your network profile."
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        wrapMode: Text.Wrap
                    }

                    Rectangle {
                        height: 1
                        color: Theme.border
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "Local servers (mDNS)"
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        font.family: Theme.fontDisplay
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Button {
                            text: "Refresh LAN"
                            onClicked: serverDiscovery.refreshMdns()
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCard
                                border.color: Theme.border
                            }
                            contentItem: Label {
                                text: parent.text
                                color: Theme.textPrimary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Button {
                            text: "Probe"
                            onClicked: serverDiscovery.probeAll()
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCard
                                border.color: Theme.border
                            }
                            contentItem: Label {
                                text: parent.text
                                color: Theme.textPrimary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Repeater {
                            model: serverDiscovery.mdnsModel
                            delegate: ServerListItem {
                                Layout.fillWidth: true
                                name: model.name
                                source: model.source
                                status: model.status
                                lastSeenAt: model.lastSeenAt
                                selectedEndpoint: model.selectedEndpoint
                                selectedNetwork: model.selectedNetwork
                                selectedReachable: model.selectedReachable
                                onUseRequested: function(endpoint, network) {
                                    sessionManager.baseUrl = endpoint
                                    if (network !== "") {
                                        sessionManager.networkType = network
                                    }
                                }
                            }
                        }

                        Label {
                            text: "No local servers discovered yet."
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: serverDiscovery.mdnsModel.count === 0
                        }
                    }

                    Rectangle {
                        height: 1
                        color: Theme.border
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "Registry servers"
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        font.family: Theme.fontDisplay
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall

                        Button {
                            text: "Refresh registry"
                            enabled: controlPlaneClient.authToken !== ""
                            onClicked: serverDiscovery.refreshRegistry()
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCard
                                border.color: Theme.border
                            }
                            contentItem: Label {
                                text: parent.text
                                color: Theme.textPrimary
                                font.pixelSize: 11
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    Label {
                        text: controlPlaneClient.authToken === "" ? "Sign in to the control plane to load registry servers." : ""
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        visible: controlPlaneClient.authToken === ""
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall
                        visible: controlPlaneClient.authToken !== ""

                        Repeater {
                            model: serverDiscovery.registryModel
                            delegate: ServerListItem {
                                Layout.fillWidth: true
                                name: model.name
                                source: model.source
                                status: model.status
                                lastSeenAt: model.lastSeenAt
                                selectedEndpoint: model.selectedEndpoint
                                selectedNetwork: model.selectedNetwork
                                selectedReachable: model.selectedReachable
                                onUseRequested: function(endpoint, network) {
                                    sessionManager.baseUrl = endpoint
                                    sessionManager.selectedServerId = model.serverId
                                    if (network !== "") {
                                        sessionManager.networkType = network
                                    }
                                }
                            }
                        }

                        Label {
                            text: "No registry servers found."
                            color: Theme.textMuted
                            font.pixelSize: 11
                            font.family: Theme.fontBody
                            visible: serverDiscovery.registryModel.count === 0
                        }
                    }

                    Label {
                        text: serverDiscovery.statusMessage
                        color: Theme.textMuted
                        font.pixelSize: 10
                        font.family: Theme.fontBody
                        visible: serverDiscovery.statusMessage !== ""
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
        function onLoginFailed(error) {
            statusText = "Login failed: " + error
        }
        function onRequestFailed(endpoint, error) {
            statusText = "Request failed: " + error
        }
        function onPasswordResetStarted(token, expiresAt) {
            resetToken = token
            resetStatusText = "Reset token generated. Expires at " + expiresAt
        }
        function onPasswordResetCompleted() {
            resetStatusText = "Password reset complete. You can sign in now."
        }
        function onPasswordResetFailed(error) {
            resetStatusText = "Reset failed: " + error
        }
    }

    Connections {
        target: controlPlaneClient
        function onLoginSucceeded() {
            controlPlaneStatusText = "Control plane authenticated."
            serverDiscovery.refreshRegistry()
        }
        function onLoginFailed(error) {
            controlPlaneStatusText = "Control plane login failed: " + error
        }
        function onRequestFailed(endpoint, error) {
            controlPlaneStatusText = "Control plane error: " + error
        }
        function onAuthExpired(message) {
            controlPlaneStatusText = message !== "" ? message : "Control plane session expired."
            sessionManager.clearControlPlaneAuth()
        }
    }

    Component.onCompleted: {
        serverDiscovery.refreshMdns()
        if (controlPlaneClient.authToken !== "") {
            serverDiscovery.refreshRegistry()
        }
    }

    Dialog {
        id: resetDialog
        modal: true
        focus: true
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        width: Math.min(root.width * 0.6, 520)
        contentItem: Rectangle {
            color: Theme.backgroundCard
            radius: Theme.radiusLarge
            border.color: Theme.border

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingLarge
                spacing: Theme.spacingSmall

                Label {
                    text: "Reset password"
                    color: Theme.textPrimary
                    font.pixelSize: 18
                    font.family: Theme.fontDisplay
                }

                Label {
                    text: "Generate a reset token, then set a new password."
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.fontBody
                    wrapMode: Text.Wrap
                }

                TextField {
                    id: resetEmailField
                    text: sessionManager.email
                    placeholderText: "Email"
                    onTextChanged: sessionManager.email = text
                }

                RowLayout {
                    spacing: Theme.spacingSmall
                    TextField {
                        id: resetTokenField
                        Layout.fillWidth: true
                        text: resetToken
                        placeholderText: "Reset token"
                        onTextChanged: resetToken = text
                    }
                    Button {
                        text: "Start reset"
                        onClicked: {
                            resetStatusText = "Requesting reset token..."
                            apiClient.startPasswordReset(resetEmailField.text)
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                TextField {
                    id: resetPasswordField
                    placeholderText: "New password"
                    echoMode: TextInput.Password
                }

                RowLayout {
                    spacing: Theme.spacingMedium
                    Button {
                        text: "Complete reset"
                        onClicked: {
                            resetStatusText = "Completing reset..."
                            apiClient.completePasswordReset(resetTokenField.text, resetPasswordField.text)
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.accent
                        }
                        contentItem: Label {
                            text: parent.text
                            color: "#111111"
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    Button {
                        text: "Close"
                        onClicked: resetDialog.close()
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border
                        }
                        contentItem: Label {
                            text: parent.text
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Label {
                    text: resetStatusText
                    color: Theme.textSecondary
                    font.pixelSize: 11
                    font.family: Theme.fontBody
                    wrapMode: Text.Wrap
                    visible: resetStatusText !== ""
                }
            }
        }
    }
}
