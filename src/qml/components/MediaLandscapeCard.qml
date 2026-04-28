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
    signal clicked(string mediaId)

    width: Theme.landscapeWidth
    height: Theme.landscapeHeight + 58
    z: hover.hovered ? 5 : 0
    scale: hover.hovered ? 1.025 : 1.0
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
            Layout.preferredWidth: Theme.landscapeWidth
            Layout.preferredHeight: Theme.landscapeHeight
            radius: Theme.radius8
            color: Theme.surfaceRaised
            border.color: hover.hovered ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(1, 1, 1, 0.10)
            clip: true

            Image {
                id: art
                anchors.fill: parent
                source: root.imageSource
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready && source !== ""
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.surface
                visible: !art.visible
            }

            Rectangle {
                anchors.fill: parent
                color: hover.hovered ? "#66000000" : "#18000000"
            }

            Rectangle {
                width: 46
                height: 46
                radius: 23
                anchors.centerIn: parent
                color: Theme.accent
                visible: hover.hovered
                Image {
                    source: "qrc:/icons/play.svg"
                    anchors.centerIn: parent
                    width: 18
                    height: 18
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
        }

        Label {
            text: root.title
            color: Theme.textPrimary
            font.family: Theme.fontBody
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
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
