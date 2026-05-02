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
    property bool collapsed: false
    property int badgeCount: 0
    
    signal clicked()
    signal menuClicked()

    width: ListView.view ? ListView.view.width : 240
    height: 46
    ToolTip.text: root.label
    ToolTip.visible: root.collapsed && clickArea.containsMouse && root.label !== ""
    ToolTip.delay: 500

    MouseArea {
        id: clickArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
        cursorShape: Qt.PointingHandCursor
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: root.collapsed ? 8 : 10
        anchors.rightMargin: root.collapsed ? 8 : 12
        radius: Theme.radius8
        color: {
            if (root.isActive) return Qt.rgba(1, 1, 1, 0.08)
            if (clickArea.containsMouse) return Qt.rgba(1, 1, 1, 0.07)
            return "transparent"
        }
        border.color: root.isActive ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : "transparent"
        border.width: root.isActive ? 1 : 0
    }

    Rectangle {
        width: 3
        height: 24
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        color: root.isActive ? Theme.accent : "transparent"
        visible: root.isActive
        radius: 1.5
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: root.collapsed ? 0 : 22
        anchors.rightMargin: root.collapsed ? 0 : 16
        spacing: root.collapsed ? 0 : 12

        Image {
            source: root.iconSource
            sourceSize.width: 20
            sourceSize.height: 20
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            Layout.alignment: root.collapsed ? Qt.AlignHCenter | Qt.AlignVCenter : Qt.AlignVCenter
            opacity: root.isActive ? 0.95 : (clickArea.containsMouse ? 0.86 : 0.66)
            visible: root.iconSource !== ""
        }

        Label {
            text: root.label
            visible: !root.collapsed
            Layout.fillWidth: true
            color: root.isActive ? Theme.textPrimary : Theme.textSecondary
            font.family: Theme.bodyFont.family
            font.pixelSize: 14
            font.weight: root.isActive ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
        }

        Rectangle {
            visible: root.badgeCount > 0 && !root.collapsed
            radius: 9
            color: Theme.accent
            border.color: Theme.accent
            implicitHeight: 18
            implicitWidth: badgeLabel.implicitWidth + 10

            Label {
                id: badgeLabel
                anchors.centerIn: parent
                text: root.badgeCount > 99 ? "99+" : String(root.badgeCount)
                color: "#141414"
                font.family: Theme.bodyFont.family
                font.pixelSize: 10
                font.weight: Font.Bold
            }
        }

        Image {
            source: "qrc:/icons/more_vert.svg"
            sourceSize.width: 16
            sourceSize.height: 16
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            visible: root.hasActionMenu && clickArea.containsMouse && !root.collapsed
            opacity: 0.7
            
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.menuClicked()
                }
                cursorShape: Qt.PointingHandCursor
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: 10
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -10
        width: root.badgeCount > 0 ? 8 : 0
        height: width
        radius: width / 2
        color: Theme.accent
        visible: root.collapsed && root.badgeCount > 0
    }
}
