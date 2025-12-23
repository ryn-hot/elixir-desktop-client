import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root

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
                        text: "Why Qt + QTMPV"
                        color: Theme.textPrimary
                        font.pixelSize: 16
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        text: "Native playback control, smooth timeline sync, and reliable codec support. This client keeps playback local and lets the server do the heavy lifting."
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
                        text: "Status"
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        font.family: Theme.fontDisplay
                    }

                    Label {
                        text: apiClient.authToken !== "" ? "Authenticated" : "Not signed in"
                        color: apiClient.authToken !== "" ? Theme.accent : Theme.textMuted
                        font.pixelSize: 12
                        font.family: Theme.fontBody
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
            if (StackView.view) {
                StackView.view.push(Qt.resolvedUrl("HomeView.qml"))
            }
        }
        function onLoginFailed(error) {
            statusText = "Login failed: " + error
        }
        function onRequestFailed(endpoint, error) {
            statusText = "Request failed: " + error
        }
    }
}
