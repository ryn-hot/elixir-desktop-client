import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import Elixir 1.0

Rectangle {
    id: root
    property string name: ""
    property string source: ""
    property string selectedEndpoint: ""
    property string selectedNetwork: ""
    property bool selectedReachable: false
    property string status: ""
    property string lastSeenAt: ""
    signal useRequested(string endpoint, string network)

    radius: Theme.radius8
    color: itemHover.hovered ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.035)
    border.color: root.selectedReachable ? Theme.accentSuccess : Qt.rgba(1, 1, 1, 0.08)
    implicitHeight: content.implicitHeight + Theme.spacingMedium * 2

    Layout.fillWidth: true

    HoverHandler { id: itemHover }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.spacingMedium
        spacing: Theme.spacingSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSmall

            Rectangle {
                width: 10
                height: 10
                radius: 5
                color: root.selectedReachable ? Theme.success : Theme.textDisabled
            }

            Label {
                text: root.name
                color: Theme.textPrimary
                font.pixelSize: 15
                font.family: Theme.fontDisplay
                font.weight: Font.DemiBold
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Rectangle {
                visible: root.selectedNetwork !== ""
                width: networkLabel.implicitWidth + 14
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.06)
                border.color: Theme.borderSubtle
                Layout.preferredHeight: 20

                Label {
                    id: networkLabel
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

            ActionButton {
                text: "Use"
                compact: true
                enabled: root.selectedEndpoint !== ""
                onClicked: root.useRequested(root.selectedEndpoint, root.selectedNetwork)
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
