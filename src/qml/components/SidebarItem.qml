import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    property string iconSource: ""
    property string label: ""
    property bool isActive: false
    property bool hasActionMenu: false
    
    signal clicked()
    signal menuClicked()

    width: ListView.view ? ListView.view.width : 240
    height: 44

    HoverHandler {
        id: hoverHandler
    }

    TapHandler {
        onTapped: root.clicked()
    }

    // Background
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        radius: 4
        color: {
            if (root.isActive) return "#1Affffff" // Active background
            if (hoverHandler.hovered) return "#0Dffffff" // Hover background
            return "transparent"
        }
    }

    // Selection Marker
    Rectangle {
        width: 3
        height: 24
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.accent
        visible: root.isActive
        radius: 1.5
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16 // Indent from marker
        anchors.rightMargin: 12
        spacing: 12

        // Icon
        Image {
            source: root.iconSource
            sourceSize.width: 20
            sourceSize.height: 20
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            opacity: root.isActive ? 1.0 : 0.7
            visible: root.iconSource !== ""
            // Tinting would require ColorOverlay or icon font, assuming SVG/Image for now
        }

        // Label
        Label {
            text: root.label
            Layout.fillWidth: true
            color: root.isActive ? "#ffffff" : "#cccccc"
            font.family: Theme.bodyFont.family
            font.pixelSize: 14
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        // Menu Icon (Three dots)
        Image {
            source: "qrc:/icons/more_vert.svg" // Placeholder
            sourceSize.width: 16
            sourceSize.height: 16
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            visible: root.hasActionMenu && hoverHandler.hovered
            opacity: 0.7
            
            TapHandler {
                onTapped: root.menuClicked()
            }
        }
    }
}
