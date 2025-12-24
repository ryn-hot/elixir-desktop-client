import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import Elixir 1.0

Item {
    id: root
    property string name: ""
    property string source: ""
    property string selectedEndpoint: ""
    property string selectedNetwork: ""
    property bool selectedReachable: false
    property string status: ""
    property string lastSeenAt: ""
    signal useRequested(string endpoint, string network)

    implicitHeight: container.implicitHeight

    Rectangle {
        id: container
        anchors.left: parent.left
        anchors.right: parent.right
        radius: Theme.radiusMedium
        color: Theme.backgroundCard
        border.color: Theme.border

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingMedium
            spacing: Theme.spacingSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Rectangle {
                    width: 10
                    height: 10
                    radius: 5
                    color: root.selectedReachable ? "#36C36C" : "#5A606B"
                }

                Label {
                    text: root.name
                    color: Theme.textPrimary
                    font.pixelSize: 14
                    font.family: Theme.fontDisplay
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: root.selectedNetwork !== ""
                    radius: 6
                    color: Theme.backgroundCardRaised
                    border.color: Theme.border
                    Layout.preferredHeight: 20

                    Label {
                        anchors.centerIn: parent
                        text: root.selectedNetwork.toUpperCase()
                        color: Theme.textSecondary
                        font.pixelSize: 10
                        font.family: Theme.fontBody
                        padding: 6
                    }
                }
            }

            Label {
                text: root.selectedEndpoint === "" ? "No endpoint" : root.selectedEndpoint
                color: Theme.textSecondary
                font.pixelSize: 11
                font.family: Theme.fontBody
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Label {
                    text: root.source === "" ? "" : root.source
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontBody
                }

                Label {
                    text: root.status === "" ? "" : root.status
                    color: Theme.textMuted
                    font.pixelSize: 10
                    font.family: Theme.fontBody
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "Use"
                    enabled: root.selectedEndpoint !== ""
                    onClicked: root.useRequested(root.selectedEndpoint, root.selectedNetwork)
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
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
                visible: root.lastSeenAt !== ""
                text: root.lastSeenAt
                color: Theme.textMuted
                font.pixelSize: 9
                font.family: Theme.fontBody
            }
        }
    }
}
