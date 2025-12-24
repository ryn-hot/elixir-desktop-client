import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "connectView"
    property StackView stackView: null

    property string statusText: ""

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
                            enabled: apiClient.authToken !== ""
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
                        text: apiClient.authToken === "" ? "Sign in to load registry servers." : ""
                        color: Theme.textMuted
                        font.pixelSize: 11
                        font.family: Theme.fontBody
                        visible: apiClient.authToken === ""
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingSmall
                        visible: apiClient.authToken !== ""

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
            serverDiscovery.refreshRegistry()
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
    }

    Component.onCompleted: {
        serverDiscovery.refreshMdns()
        if (apiClient.authToken !== "") {
            serverDiscovery.refreshRegistry()
        }
    }
}
