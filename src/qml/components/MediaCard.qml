import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Qt5Compat.GraphicalEffects
import Elixir 1.0

Item {
    id: root
    
    // Properties
    property string title: ""
    property string subtitle: ""
    property string imageSource: ""
    property double progress: 0.0
    property string cardType: "portrait" // "portrait" | "landscape"
    property string badgeText: "" // e.g. "Unplayed" or count
    property string mediaId: ""
    
    signal clicked(string mediaId)

    // Dimensions based on type
    width: cardType === "landscape" ? Theme.landscapeWidth : Theme.posterWidth
    height: cardType === "landscape" ? Theme.landscapeHeight + 40 : Theme.posterHeight + 40 // +40 for metadata

    // Hover State
    HoverHandler {
        id: hoverHandler
    }

    TapHandler {
        onTapped: root.clicked(root.mediaId)
    }

    // Scale Effect on Focus/Hover
    scale: hoverHandler.hovered ? 1.05 : 1.0
    Behavior on scale { NumberAnimation { duration: 150 } }
    z: hoverHandler.hovered ? 10 : 1

    // Main Card Content
    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Image Container
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.cardType === "landscape" ? Theme.landscapeHeight : Theme.posterHeight
            
            // Image
            Image {
                id: posterImage
                anchors.fill: parent
                source: root.imageSource
                fillMode: Image.PreserveAspectCrop
                visible: false // Hidden because we use OpacityMask
                asynchronous: true
            }

            Rectangle {
                id: mask
                anchors.fill: parent
                radius: 4
                visible: false
            }

            OpacityMask {
                anchors.fill: posterImage
                source: posterImage
                maskSource: mask
            }

            // Focus Border
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: "white"
                border.width: 3
                radius: 4
                visible: hoverHandler.hovered
            }

            // Landscape Overlay (Progress + Play Button)
            Item {
                anchors.fill: parent
                visible: root.cardType === "landscape"

                // Play Button (Center)
                Rectangle {
                    width: 48
                    height: 48
                    radius: 24
                    color: "#cc000000"
                    anchors.centerIn: parent
                    visible: hoverHandler.hovered
                    
                    Rectangle {
                        width: 0
                        height: 0
                        color: "transparent"
                        border.color: "transparent"
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 2
                        
                        // Simple triangle using rotation hack or canvas
                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.fillStyle = Theme.accent;
                                ctx.beginPath();
                                ctx.moveTo(-8, -10);
                                ctx.lineTo(12, 0);
                                ctx.lineTo(-8, 10);
                                ctx.closePath();
                                ctx.fill();
                            }
                        }
                    }
                }

                // Progress Bar (Bottom)
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 4
                    color: "#80000000"
                    visible: root.progress > 0
                    
                    Rectangle {
                        height: parent.height
                        width: parent.width * root.progress
                        color: Theme.accent
                    }
                }
                
                // Time Remaining (Bottom Right)
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    anchors.bottomMargin: 12 // Above progress bar
                    width: timeLabel.width + 12
                    height: 20
                    radius: 10
                    color: "#cc000000"
                    visible: root.progress > 0 && root.progress < 0.9
                    
                    Label {
                        id: timeLabel
                        anchors.centerIn: parent
                        text: Math.round((1.0 - root.progress) * 20) + " min" // Placeholder logic
                        color: "white"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            // Portrait Overlay (Corner Badge)
            Item {
                anchors.fill: parent
                visible: root.cardType === "portrait" && root.badgeText !== ""
                
                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: Theme.accent
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: -8
                    z: 5
                    
                    Label {
                        anchors.centerIn: parent
                        text: root.badgeText
                        color: "black"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }
        }

        // Metadata
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            
            Label {
                text: root.title
                Layout.fillWidth: true
                color: Theme.textPrimary
                font.family: Theme.bodyFont.family
                font.pixelSize: root.cardType === "landscape" ? 14 : 13
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            
            Label {
                text: root.subtitle
                Layout.fillWidth: true
                color: Theme.textSecondary
                font.family: Theme.bodyFont.family
                font.pixelSize: 12
                elide: Text.ElideRight
                visible: text !== ""
            }
        }
    }
}
