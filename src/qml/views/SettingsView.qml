import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingXLarge
        spacing: Theme.spacingLarge

        Label {
            text: "Settings"
            color: Theme.textPrimary
            font.pixelSize: 24
            font.family: Theme.fontDisplay
        }

        Rectangle {
            Layout.fillWidth: true
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

                RowLayout {
                    spacing: Theme.spacingMedium

                    Button {
                        text: "Clear auth"
                        onClicked: sessionManager.clearAuth()
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
                        text: "Back"
                        onClicked: {
                            if (StackView.view) {
                                StackView.view.pop()
                            }
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCard
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
            }
        }
    }
}
