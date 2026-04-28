import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    property string mediaId: ""
    property string title: ""
    property string subtitle: ""
    property string imageSource: ""
    property double progress: 0
    property bool trackedByManager: false
    property string badgeText: ""
    signal clicked(string mediaId)

    width: Theme.posterWidth
    height: Theme.posterHeight + 58
    z: hover.hovered ? 5 : 0
    scale: hover.hovered ? 1.035 : 1.0
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    HoverHandler { id: hover }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked(root.mediaId)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Rectangle {
            id: posterFrame
            Layout.preferredWidth: Theme.posterWidth
            Layout.preferredHeight: Theme.posterHeight
            radius: Theme.radius8
            color: Theme.surfaceRaised
            border.color: hover.hovered ? Qt.rgba(1, 1, 1, 0.55) : Qt.rgba(1, 1, 1, 0.10)
            clip: true

            Image {
                id: poster
                anchors.fill: parent
                source: root.imageSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready && source !== ""
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 130 } }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.surface
                visible: !poster.visible

                ColumnLayout {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    spacing: 10
                    Label {
                        text: root.title.length > 0 ? root.title.charAt(0).toUpperCase() : "E"
                        color: Theme.accent
                        font.family: Theme.fontDisplay
                        font.pixelSize: 42
                        font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }
                    Label {
                        text: root.title
                        color: Theme.textSecondary
                        font.family: Theme.fontBody
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        horizontalAlignment: Text.AlignHCenter
                        Layout.fillWidth: true
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: hover.hovered ? "#66000000" : "transparent"
                visible: hover.hovered

                Rectangle {
                    width: 46
                    height: 46
                    radius: 23
                    anchors.centerIn: parent
                    color: Theme.accent
                    Image {
                        source: "qrc:/icons/play.svg"
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 4
                color: "#99000000"
                visible: root.progress > 0 && root.progress < 0.98
                Rectangle {
                    height: parent.height
                    width: parent.width * Math.max(0, Math.min(1, root.progress))
                    color: Theme.accent
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                width: managedLabel.implicitWidth + 14
                height: 22
                radius: 11
                color: "#D9101215"
                border.color: Theme.borderSubtle
                visible: root.trackedByManager || root.badgeText !== ""
                Label {
                    id: managedLabel
                    anchors.centerIn: parent
                    text: root.badgeText !== "" ? root.badgeText : "Managed"
                    color: Theme.textSecondary
                    font.family: Theme.fontBody
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
        }

        Label {
            text: root.title
            color: Theme.textPrimary
            font.family: Theme.fontBody
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
            maximumLineCount: 1
            Layout.fillWidth: true
        }

        Label {
            text: root.subtitle
            color: Theme.textMuted
            font.family: Theme.fontBody
            font.pixelSize: 12
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }
}
