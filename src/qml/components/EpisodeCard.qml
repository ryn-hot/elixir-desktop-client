import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Rectangle {
    id: root
    property string title: ""
    property string description: ""
    property string thumbnail: ""
    property string statusText: ""
    property bool available: false
    property bool blocked: false
    property bool canDelete: false
    property bool canRestore: false
    property bool busy: false
    readonly property int verticalPadding: Theme.space10
    signal playRequested()
    signal deleteRequested()
    signal restoreRequested()

    radius: Theme.radius4
    color: hover.hovered ? Qt.rgba(1, 1, 1, 0.055) : "transparent"
    border.color: "transparent"
    implicitHeight: Math.max(Theme.episodeThumbHeight, detailsColumn.implicitHeight) + verticalPadding * 2

    HoverHandler { id: hover }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 0
        anchors.rightMargin: 0
        anchors.topMargin: root.verticalPadding
        anchors.bottomMargin: root.verticalPadding
        spacing: Theme.space16

        Rectangle {
            Layout.preferredWidth: Theme.episodeThumbWidth
            Layout.preferredHeight: Theme.episodeThumbHeight
            radius: Theme.radius8
            color: Theme.surfaceRaised
            clip: true

            Image {
                id: thumb
                anchors.fill: parent
                source: root.thumbnail
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready && source !== ""
            }

            Rectangle {
                anchors.fill: parent
                color: "#55000000"
                visible: hover.hovered && root.available && !root.blocked
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: Theme.accent
                    anchors.centerIn: parent
                    Image {
                        source: "qrc:/icons/play.svg"
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                    }
                }
            }
        }

        ColumnLayout {
            id: detailsColumn
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.space8

            Label {
                text: root.title
                color: root.available && !root.blocked ? Theme.textPrimary : Theme.textMuted
                font.family: Theme.fontBody
                font.pixelSize: 15
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Label {
                text: root.description !== "" ? root.description : "No description available."
                color: Theme.textSecondary
                font.family: Theme.fontBody
                font.pixelSize: 13
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            RowLayout {
                spacing: Theme.space8
                Label {
                    text: root.statusText
                    color: root.blocked ? Theme.info : (root.available ? Theme.textMuted : Theme.accent)
                    font.family: Theme.fontBody
                    font.pixelSize: 12
                }
                Item { Layout.fillWidth: true }
                ActionButton {
                    text: "Play"
                    compact: true
                    visible: root.available && !root.blocked
                    enabled: !root.busy
                    onClicked: root.playRequested()
                }
                ActionButton {
                    text: root.busy ? "Working..." : "Delete"
                    compact: true
                    variant: "danger"
                    visible: root.canDelete && !root.blocked
                    enabled: !root.busy
                    onClicked: root.deleteRequested()
                }
                ActionButton {
                    text: root.busy ? "Working..." : "Allow again"
                    compact: true
                    visible: root.canRestore
                    enabled: !root.busy
                    onClicked: root.restoreRequested()
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Qt.rgba(1, 1, 1, 0.07)
    }
}
