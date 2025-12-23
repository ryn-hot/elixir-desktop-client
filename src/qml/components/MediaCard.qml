import QtQuick 6.5
import QtQuick.Controls 6.5

import Elixir 1.0

Item {
    id: root
    property string mediaId: ""
    property string title: ""
    property string posterUrl: ""
    property real progress: 0.0
    signal clicked(string mediaId)

    width: 150
    height: 220

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.radiusMedium
        color: Theme.backgroundCard
        border.color: mouseArea.containsMouse ? Theme.accent : Theme.border
        scale: mouseArea.containsMouse ? 1.03 : 1.0
        antialiasing: true

        Behavior on scale {
            NumberAnimation { duration: 120 }
        }

        Image {
            anchors.fill: parent
            anchors.margins: 2
            source: root.posterUrl
            fillMode: Image.PreserveAspectCrop
            smooth: true
            visible: root.posterUrl !== ""
            opacity: root.posterUrl !== "" ? 1 : 0
        }

        Rectangle {
            anchors.fill: parent
            color: "#1A1F2A"
            visible: root.posterUrl === ""
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 36
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#00000000" }
                GradientStop { position: 1.0; color: "#A0000000" }
            }
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 10
            text: root.title
            color: Theme.textPrimary
            font.pixelSize: 12
            font.family: Theme.fontBody
            elide: Text.ElideRight
        }

        Rectangle {
            visible: root.progress > 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 4
            color: Theme.accentSoft
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * root.progress
                color: Theme.accent
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked(root.mediaId)
    }
}
