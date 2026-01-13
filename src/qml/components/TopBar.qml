import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    property string searchQuery: ""
    signal searchChanged(string text)

    height: Theme.topBarHeight

    Rectangle {
        anchors.fill: parent
        color: "transparent" // Main background handles this, or use Theme.bgMain if needed
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 15
        anchors.rightMargin: 15
        spacing: 15

        // Search Bar (Left-Aligned)
        Rectangle {
            Layout.preferredWidth: 250
            Layout.preferredHeight: 36
            radius: 4
            color: Theme.bgSidebar // Slightly lighter than main bg
            border.color: searchField.activeFocus ? Theme.accent : "transparent"
            border.width: 1
            
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8
                
                // Search Icon
                Image {
                    source: "qrc:/icons/search.svg" // Placeholder
                    sourceSize.width: 16
                    sourceSize.height: 16
                    Layout.preferredWidth: 16
                    Layout.preferredHeight: 16
                    opacity: 0.5
                }
                
                TextField {
                    id: searchField
                    Layout.fillWidth: true
                    placeholderText: "Search"
                    color: Theme.textPrimary
                    placeholderTextColor: Theme.textSecondary
                    font.family: Theme.bodyFont.family
                    font.pixelSize: 14
                    background: null
                    selectByMouse: true
                    verticalAlignment: Text.AlignVCenter
                    onTextChanged: root.searchChanged(text)
                }
                
                // Clear Button
                Image {
                    source: "qrc:/icons/close.svg" // Placeholder
                    sourceSize.width: 12
                    sourceSize.height: 12
                    Layout.preferredWidth: 12
                    Layout.preferredHeight: 12
                    visible: searchField.text !== ""
                    opacity: 0.5
                    
                    TapHandler {
                        onTapped: searchField.text = ""
                    }
                }
            }
        }

        Item { Layout.fillWidth: true } // Spacer

        // Action Icons (Right-Aligned)
        RowLayout {
            spacing: 20
            
            // Activity
            Image {
                source: "qrc:/icons/activity.svg" // Placeholder
                sourceSize.width: 20
                sourceSize.height: 20
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                opacity: 0.7
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
            
            // Cast
            Image {
                source: "qrc:/icons/cast.svg" // Placeholder
                sourceSize.width: 20
                sourceSize.height: 20
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                opacity: 0.7
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
            
            // Settings
            Image {
                source: "qrc:/icons/settings.svg" // Placeholder
                sourceSize.width: 20
                sourceSize.height: 20
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                opacity: 0.7
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
            
            // User Avatar
            Rectangle {
                width: 32
                height: 32
                radius: 16
                color: Theme.accent
                
                Label {
                    anchors.centerIn: parent
                    text: "U"
                    color: "#111"
                    font.bold: true
                    font.pixelSize: 14
                }
                
                // Status Badge
                Rectangle {
                    width: 10
                    height: 10
                    radius: 5
                    color: "#4CAF50" // Online green
                    border.color: Theme.bgMain
                    border.width: 2
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }
    }
}
