import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    property string searchQuery: ""
    property bool searchVisible: true
    property string profileInitial: "U"
    signal searchChanged(string text)
    signal activityRequested()
    signal castRequested()
    signal settingsRequested()
    signal profileRequested()

    height: Theme.topBarHeight

    Rectangle {
        anchors.fill: parent
        color: Theme.topBarBg
        opacity: 0.94
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Qt.rgba(1, 1, 1, 0.06)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 22
        spacing: 18

        SearchField {
            id: searchBox
            Layout.preferredWidth: root.searchVisible ? (searchBox.fieldActive ? 460 : 360) : 0
            Layout.preferredHeight: 40
            visible: root.searchVisible
            placeholderText: "Search your library"
            onTextEdited: root.searchChanged(text)
        }

        Item { Layout.fillWidth: true }

        RowLayout {
            spacing: 12

            Button {
                id: activityButton
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                padding: 0
                onClicked: root.activityRequested()
                background: Rectangle {
                    radius: 19
                    color: activityButton.hovered ? Theme.surfaceRaised : "transparent"
                }
                contentItem: Image {
                    source: "qrc:/icons/activity.svg"
                    sourceSize.width: 20
                    sourceSize.height: 20
                    opacity: 0.7
                }
            }

            Button {
                id: castButton
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                padding: 0
                onClicked: root.castRequested()
                background: Rectangle {
                    radius: 19
                    color: castButton.hovered ? Theme.surfaceRaised : "transparent"
                }
                contentItem: Image {
                    source: "qrc:/icons/cast.svg"
                    sourceSize.width: 20
                    sourceSize.height: 20
                    opacity: 0.7
                }
            }

            Button {
                id: settingsButton
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                padding: 0
                onClicked: root.settingsRequested()
                background: Rectangle {
                    radius: 19
                    color: settingsButton.hovered ? Theme.surfaceRaised : "transparent"
                }
                contentItem: Image {
                    source: "qrc:/icons/settings.svg"
                    sourceSize.width: 20
                    sourceSize.height: 20
                    opacity: 0.7
                }
            }
            
            Rectangle {
                width: 34
                height: 34
                radius: 17
                color: Theme.accent
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.profileRequested()
                }
                
                Label {
                    anchors.centerIn: parent
                    text: root.profileInitial
                    color: "#111"
                    font.bold: true
                    font.pixelSize: 14
                }

                Rectangle {
                    width: 10
                    height: 10
                    radius: 5
                    color: Theme.success
                    border.color: Theme.bgMain
                    border.width: 2
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                }
            }
        }
    }
}
