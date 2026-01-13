import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    property string mediaId: ""
    property string title: ""
    property string subtitle: "" // Year or "30 min left"
    property string backdropUrl: ""
    property real progress: 0.0
    signal clicked(string mediaId)

    width: 280
    height: 200 // Includes text area

    HoverHandler {
        id: hoverHandler
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: root.clicked(root.mediaId)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingSmall

        // Image Container
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: width * 0.5625 // 16:9 aspect ratio
            radius: Theme.radiusSmall
            color: Theme.backgroundCard
            border.color: hoverHandler.hovered ? Theme.accent : Theme.border
            border.width: hoverHandler.hovered ? 2 : 1
            clip: true
            
            scale: hoverHandler.hovered ? 1.02 : 1.0
            Behavior on scale { NumberAnimation { duration: 100 } }

            Image {
                anchors.fill: parent
                anchors.margins: 2
                source: root.backdropUrl
                fillMode: Image.PreserveAspectCrop
                smooth: true
                visible: root.backdropUrl !== ""
                opacity: root.backdropUrl !== "" ? 1 : 0
            }

            Rectangle {
                anchors.fill: parent
                color: "#1A1F2A"
                visible: root.backdropUrl === ""
                
                Label {
                    anchors.centerIn: parent
                    text: "No Image"
                    color: Theme.textMuted
                    font.family: Theme.fontBody
                    font.pixelSize: 12
                }
            }

            // Progress Bar
            Rectangle {
                visible: root.progress > 0
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 2
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
            
            // Play overlay on hover
            Rectangle {
                anchors.fill: parent
                color: "#66000000"
                visible: hoverHandler.hovered
                
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: Theme.accent
                    anchors.centerIn: parent
                    
                    // Triangle play icon shape
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.fillStyle = "#111";
                            ctx.beginPath();
                            ctx.moveTo(14, 10);
                            ctx.lineTo(28, 20);
                            ctx.lineTo(14, 30);
                            ctx.closePath();
                            ctx.fill();
                        }
                    }
                }
            }
        }

        // Text Info
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            
            Label {
                text: root.title
                color: hoverHandler.hovered ? Theme.accent : Theme.textPrimary
                font.family: Theme.fontBody
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            
            Label {
                text: root.subtitle
                color: Theme.textSecondary
                font.family: Theme.fontBody
                font.pixelSize: 12
                elide: Text.ElideRight
                Layout.fillWidth: true
                visible: root.subtitle !== ""
            }
        }
    }
}
