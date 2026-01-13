import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Rectangle {
    id: root
    width: Theme.sidebarWidth
    color: Theme.bgSidebar
    
    signal homeRequested()
    signal moviesRequested()
    signal seriesRequested()
    signal animeRequested()
    signal settingsRequested()

    property string currentView: "home"

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Logo Area
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            
            RowLayout {
                anchors.left: parent.left
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                
                Rectangle {
                    width: 28
                    height: 28
                    radius: 6
                    color: Theme.accent
                    
                    Label {
                        anchors.centerIn: parent
                        text: "E"
                        font.family: Theme.headerFont.family
                        font.pixelSize: 18
                        font.bold: true
                        color: "#111"
                    }
                }
                
                Label {
                    text: "Elixir"
                    color: Theme.textPrimary
                    font.family: Theme.headerFont.family
                    font.pixelSize: 20
                    font.weight: Font.Bold
                }
            }
        }

        // Navigation List
        ListView {
            id: navList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: ListModel {
                ListElement { type: "item"; label: "Home"; icon: "qrc:/icons/home.svg"; action: "home" }
                ListElement { type: "item"; label: "Movies"; icon: "qrc:/icons/movie.svg"; action: "movies" }
                ListElement { type: "item"; label: "TV Shows"; icon: "qrc:/icons/tv.svg"; action: "series" }
                ListElement { type: "item"; label: "Anime"; icon: "qrc:/icons/animation.svg"; action: "anime" }
                // Spacer could be handled differently, but for now just items
            }

            delegate: SidebarItem {
                label: model.label
                iconSource: model.icon // Placeholder icons
                isActive: {
                    if (model.action === "home" && root.currentView === "home") return true
                    if (model.action === "movies" && root.currentView === "movies") return true
                    if (model.action === "series" && root.currentView === "series") return true
                    if (model.action === "anime" && root.currentView === "anime") return true
                    return false
                }
                hasActionMenu: true
                onClicked: {
                    if (model.action === "home") root.homeRequested()
                    else if (model.action === "movies") root.moviesRequested()
                    else if (model.action === "series") root.seriesRequested()
                    else if (model.action === "anime") root.animeRequested()
                }
            }
        }

        // Bottom Actions
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
                Layout.preferredHeight: 40
                
                Label {
                    text: "More >"
                    anchors.centerIn: parent
                    color: Theme.textSecondary
                    font.pixelSize: 12
                    font.family: Theme.bodyFont.family
                }
            }
        }
    }
}
