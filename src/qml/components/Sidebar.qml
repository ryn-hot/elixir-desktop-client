import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Rectangle {
    id: root
    width: Theme.sidebarWidth
    color: Theme.sidebarBg
    
    signal homeRequested()
    signal moviesRequested()
    signal seriesRequested()
    signal animeRequested()
    signal findMediaRequested()
    signal acquisitionRequested()
    signal extensionsRequested()
    signal settingsRequested()

    property string currentView: "home"
    property int acquisitionBadgeCount: 0

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 82
            
            RowLayout {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                
                Rectangle {
                    width: 34
                    height: 34
                    radius: Theme.radius8
                    color: Theme.accent
                    
                    Label {
                        anchors.centerIn: parent
                        text: "E"
                        font.family: Theme.headerFont.family
                        font.pixelSize: 20
                        font.bold: true
                        color: "#111"
                    }
                }
                
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        text: "Elixir"
                        color: Theme.textPrimary
                        font.family: Theme.headerFont.family
                        font.pixelSize: 21
                        font.weight: Font.Bold
                    }

                    Label {
                        text: "Media Server"
                        color: Theme.textMuted
                        font.family: Theme.fontBody
                        font.pixelSize: 11
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0
                    }
                }
            }
        }

        ListView {
            id: navList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: ListModel {
                ListElement { type: "section"; label: "Browse"; icon: ""; action: "" }
                ListElement { type: "item"; label: "Home"; icon: "qrc:/icons/home.svg"; action: "home" }
                ListElement { type: "item"; label: "Movies"; icon: "qrc:/icons/movie.svg"; action: "movies" }
                ListElement { type: "item"; label: "TV Shows"; icon: "qrc:/icons/tv.svg"; action: "series" }
                ListElement { type: "item"; label: "Anime"; icon: "qrc:/icons/animation.svg"; action: "anime" }
                ListElement { type: "section"; label: "Elixir"; icon: ""; action: "" }
                ListElement { type: "item"; label: "Find Media"; icon: "qrc:/icons/search.svg"; action: "find_media" }
                ListElement { type: "item"; label: "Acquisition"; icon: "qrc:/icons/activity.svg"; action: "acquisition" }
                ListElement { type: "item"; label: "Extensions"; icon: "qrc:/icons/settings.svg"; action: "extensions" }
            }

            delegate: Item {
                width: ListView.view ? ListView.view.width : Theme.sidebarWidth
                height: model.type === "section" ? 38 : 46

                Label {
                    anchors.left: parent.left
                    anchors.leftMargin: 24
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: model.label
                    color: Theme.textMuted
                    font.family: Theme.fontBody
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0
                    visible: model.type === "section"
                }

                SidebarItem {
                    anchors.fill: parent
                    visible: model.type !== "section"
                    label: model.label
                    iconSource: model.icon
                    isActive: {
                        if (model.action === "home" && root.currentView === "home") return true
                        if (model.action === "movies" && root.currentView === "movies") return true
                        if (model.action === "series" && root.currentView === "series") return true
                        if (model.action === "anime" && root.currentView === "anime") return true
                        if (model.action === "find_media" && root.currentView === "find_media") return true
                        if (model.action === "acquisition" && root.currentView === "acquisition") return true
                        if (model.action === "extensions" && root.currentView === "extensions") return true
                        return false
                    }
                    badgeCount: model.action === "acquisition" ? root.acquisitionBadgeCount : 0
                    hasActionMenu: false
                    onClicked: {
                        if (model.action === "home") root.homeRequested()
                        else if (model.action === "movies") root.moviesRequested()
                        else if (model.action === "series") root.seriesRequested()
                        else if (model.action === "anime") root.animeRequested()
                        else if (model.action === "find_media") root.findMediaRequested()
                        else if (model.action === "acquisition") root.acquisitionRequested()
                        else if (model.action === "extensions") root.extensionsRequested()
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            
            SidebarItem {
                label: "Settings"
                iconSource: "qrc:/icons/settings.svg"
                isActive: root.currentView === "settings"
                onClicked: root.settingsRequested()
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.space24
            }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 1
        color: Qt.rgba(1, 1, 1, 0.06)
    }
}
